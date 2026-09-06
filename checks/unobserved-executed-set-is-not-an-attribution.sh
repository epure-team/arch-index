#!/usr/bin/env bash
# checks/unobserved-executed-set-is-not-an-attribution.sh — runnable directly. CHECK-25 / FR-007.
#
# The defect. At bin/arch_mutants/arch_mutants.ml:1425-1427 (and again at :1575 and :1703) the
# driver read the wrapper's trace with
#
#     Option.value ~default:sel.sel_executed (Hashtbl.find_opt executed_by_id …)
#
# so a mutant for which the wrapper wrote NO trace line silently got the PLANNED set recorded
# as the set that executed. That value then fed `mutant_runs.executed_tests`,
# `executed_superset`, and — decisively — a `mutant_kills` row with
# `attribution = singleton_executed_set` whenever the planned set happened to hold exactly one
# test. That is a per-test attribution naming a test nobody ever observed running, written by
# the one table in the schema that exists to keep attribution honest.
#
# The fixture. An index where `other` (lib/y.ml:30-40) is reached by exactly ONE test,
# t_gamma, so the planned set for the mutant at lib/y.ml:35 IS a singleton and the buggy path
# is reachable rather than merely present. The engine stub then exits 0 without ever invoking
# the wrapper — what a crashed, skipped or misconfigured engine looks like — while the report
# claims that mutant was KILLED. Before the fix this produced `t_gamma / singleton_executed_set`
# out of zero observed test runs, and stamped the campaign complete.
#
# Exit: 0 = an unobserved executed set produces no record of any kind;
#       1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
B="$repo/_build/default/bin"

fatal() { echo "unobserved-executed-set: $*" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || fatal "sqlite3 is required"
[ -x "$repo/scripts/mutaml-wrapper.sh" ] || fatal "the wrapper is missing"
for exe in arch_load/arch_load.exe arch_mutants/arch_mutants.exe; do
  [ -x "$B/$exe" ] || fatal "$B/$exe is not built — run 'dune build' first. Nothing was checked."
done

W="$(mktemp -d "${TMPDIR:-/tmp}/unobserved-executed.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

fails=0
assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1 — $3"
  else echo "  ✗ $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

cat > "$W/stream.ndjson" <<'S'
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"t_gamma","file_path":"test/alpha_test.ml","line_start":7,"line_end":9}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"other","file_path":"lib/y.ml","line_start":30,"line_end":40}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"t_gamma","caller_file":"test/alpha_test.ml","callee_name":"other","callee_file":"lib/y.ml","call_site":"test/alpha_test.ml:8","kind":"MUST"}
S
"$B/arch_load/arch_load.exe" "$W/t.db" < "$W/stream.ndjson" >/dev/null 2>&1 || fatal "arch-load failed"
cat > "$W/cat.ndjson" <<'C'
{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
{"id":"m2","file":"lib/y.ml","line":35,"col_start":1,"col_end":4,"replacement":"false"}
C
cat > "$W/report.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"KILLED","id":"m2"}
R
"$B/arch_mutants/arch_mutants.exe" plan "$W/t.db" --tests 'file:test/**' --format json > "$W/plan.json" \
  || fatal "arch-mutants plan failed"

# The planned set for m2 must be the SINGLETON the defect needs. Asserted, not assumed: if the
# fixture ever stopped producing it, every assertion below would pass vacuously.
planned_m2="$(grep -c '"t_gamma"' "$W/plan.json")"
[ "$planned_m2" -ge 1 ] || fatal "the fixture no longer plans t_gamma for lib/y.ml — the defect's path would be unreachable"

printf '#!/bin/sh\nexit 0\n' > "$W/engine.sh"; chmod +x "$W/engine.sh"

out="$(ARCH_MUTANTS_WORKDIR="$W/work" ARCH_MUTANTS_WRAPPER="$repo/scripts/mutaml-wrapper.sh" \
  "$B/arch_mutants/arch_mutants.exe" run "$W/t.db" --plan "$W/plan.json" --engine "$W/engine.sh" \
  --test-cmd true --catalogue "$W/cat.ndjson" --report "$W/report.ndjson" \
  --tests 'file:test/**' --format json 2>"$W/err")"

trace_lines="$(grep -c . "$W/work/wrapper-trace.tsv" 2>/dev/null)"
trace_lines="${trace_lines:-0}"
assert_eq "the fixture really produced no trace line" "0" "$trace_lines"

jnum() { printf '%s' "$out" | grep -o "\"$1\": *[0-9]*" | grep -o '[0-9]*' | head -1; }
jbool() { printf '%s' "$out" | grep -o "\"$1\": *[a-z]*" | sed 's/.*: *//' | head -1; }

assert_eq "both unobserved mutants are counted" "2" "$(jnum mutants_unobserved_executed_set)"
assert_eq "neither is counted as attempted"     "0" "$(jnum mutants_attempted)"
assert_eq "an unobserved KILLED is not a kill"  "0" "$(jnum killed)"
assert_eq "no attribution is recorded"          "0" "$(jnum attributions_recorded)"
assert_eq "the campaign is not complete"        "false" "$(jbool completed)"
assert_eq "no run row is persisted"  "0" "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_runs')"
assert_eq "no kill row is persisted" "0" "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_kills')"
assert_eq "completed_at stays NULL"  "0" \
  "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL')"
# The decisive one, stated as the name rather than a count: the planned test must not appear
# in mutant_kills at all. A count of 0 above already implies it, but this says WHICH name the
# old code invented, so a future regression is legible at a glance.
assert_eq "t_gamma is never named as a killer" "" \
  "$(sqlite3 "$W/t.db" "SELECT group_concat(test_name) FROM mutant_kills")"
# And the planned set is not republished as what executed.
assert_eq "the JSON never claims an executed set here" "0" \
  "$(printf '%s' "$out" | grep -c '"executed_tests": \[$')"

echo
if [ "$fails" -gt 0 ]; then
  echo "unobserved-executed-set: FAIL — $fails assertion(s) fired." >&2
  echo "  A mutant whose executed set was never observed produced a record that claims one." >&2
  exit 1
fi
echo "unobserved-executed-set: PASS — a mutant with no trace line is recorded nowhere and"
echo "  attributed to nobody. What would have made this non-zero: the pre-fix"
echo "  \`Option.value ~default:sel.sel_executed\`, which substituted the PLANNED singleton and"
echo "  wrote 't_gamma / singleton_executed_set' out of zero observed test runs."
exit 0
