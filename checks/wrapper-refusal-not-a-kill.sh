#!/usr/bin/env bash
# checks/wrapper-refusal-not-a-kill.sh — runnable directly. CHECK-24 / FR-031.
#
# The defect. `scripts/mutaml-wrapper.sh` refused with `exit 2`. mutaml persists the RAW
# exit code rather than the label it prints — src/runner/runner.ml:109-110 saves
# `{ status = ret; mutant }` over `status : int` (src/common/mutaml_common.ml:74) — and the
# adapter at bin/arch_mutants/arch_mutants.ml read `Int 0` as SURVIVED, `Int 124` as TIMEOUT
# and EVERY OTHER CODE as KILLED. So a wrapper that could not do its job at all produced a
# campaign of clean KILLS: the single worst reading available, because a kill is the one
# outcome this design treats as self-certifying proof. A wholly broken selection would have
# read as a healthy test suite.
#
# What this pins, end to end and through the real chain rather than by inspection:
#   1. every refusal path of the wrapper exits exactly 99 — MUTAML_MUTANT unset, a mutant it
#      was never given, and a selection file it cannot read;
#   2. a real campaign whose engine hands the wrapper an uncatalogued mutant and writes the
#      wrapper's OWN exit code into a mutaml-shaped report ends with killed=0, one refusal
#      counted, NO `mutant_runs` row, NO `mutant_kills` row, and `completed_at` still NULL.
#
# The engine stub here is a faithful miniature of mutaml's runner: it sets MUTAML_MUTANT,
# invokes the test command, and persists the raw exit code. That is what makes this a check
# on the CHAIN and not on one function's spelling.
#
# Exit: 0 = a refusal is never a kill; 1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
B="$repo/_build/default/bin"
WRAPPER="$repo/scripts/mutaml-wrapper.sh"
REFUSAL=99

fatal() { echo "wrapper-refusal-not-a-kill: $*" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || fatal "sqlite3 is required"
[ -x "$WRAPPER" ] || fatal "$WRAPPER is not executable"
for exe in arch_load/arch_load.exe arch_mutants/arch_mutants.exe; do
  [ -x "$B/$exe" ] || fatal "$B/$exe is not built — run 'dune build' first. Nothing was checked."
done

W="$(mktemp -d "${TMPDIR:-/tmp}/wrapper-refusal.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

fails=0
assert_eq() { # label expected actual
  if [ "$2" = "$3" ]; then
    echo "  ✓ $1 — $3"
  else
    echo "  ✗ $1 — expected $2, got $3"
    fails=$((fails + 1))
  fi
}

# ---- PART 1: every refusal path exits the reserved code, and nothing else ---------------
printf 'm1\t0\tt_alpha\tt_alpha\n' > "$W/sel.tsv"
export ARCH_MUTANTS_TRACE="$W/trace.tsv"
export ARCH_MUTANTS_TEST_CMD=true
: > "$ARCH_MUTANTS_TRACE"

ARCH_MUTANTS_SELECTION="$W/sel.tsv" "$WRAPPER" >/dev/null 2>&1
assert_eq "MUTAML_MUTANT unset refuses with $REFUSAL" "$REFUSAL" "$?"

ARCH_MUTANTS_SELECTION="$W/sel.tsv" MUTAML_MUTANT=never-catalogued "$WRAPPER" >/dev/null 2>&1
assert_eq "an uncatalogued mutant refuses with $REFUSAL" "$REFUSAL" "$?"

ARCH_MUTANTS_SELECTION="$W/does-not-exist.tsv" MUTAML_MUTANT=m1 "$WRAPPER" >/dev/null 2>&1
assert_eq "an unreadable selection file refuses with $REFUSAL" "$REFUSAL" "$?"

# A mutant that IS catalogued must still run normally: a guard that refuses everything would
# satisfy the three assertions above and be worthless.
ARCH_MUTANTS_SELECTION="$W/sel.tsv" MUTAML_MUTANT=m1 "$WRAPPER" >/dev/null 2>&1
assert_eq "a catalogued mutant is NOT refused" "0" "$?"
unset ARCH_MUTANTS_TRACE ARCH_MUTANTS_TEST_CMD

# ---- PART 2: the whole chain, through the real driver -----------------------------------
cat > "$W/stream.ndjson" <<'S'
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
S
"$B/arch_load/arch_load.exe" "$W/t.db" < "$W/stream.ndjson" >/dev/null 2>&1 || fatal "arch-load failed"
cat > "$W/cat.muts" <<'C'
[{"number":1,"repl":"true","loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":15,"pos_cnum":100,"pos_bol":97},"loc_end":{"pos_cnum":106,"pos_bol":97}}}]
C
"$B/arch_mutants/arch_mutants.exe" plan "$W/t.db" --tests 'file:test/**' --format json > "$W/plan.json" \
  || fatal "arch-mutants plan failed"

# mutaml in miniature: name a mutant, run the test command, persist its RAW exit code.
cat > "$W/engine.sh" <<'E'
#!/bin/sh
rc=0
MUTAML_MUTANT=never-catalogued "$1" || rc=$?
printf '[{"status":%d,"mutant":{"number":1,"loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":15}}}}]\n' \
  "$rc" > "$REPORT_OUT"
exit 0
E
chmod +x "$W/engine.sh"

out="$(REPORT_OUT="$W/report.json" ARCH_MUTANTS_WORKDIR="$W/work" ARCH_MUTANTS_WRAPPER="$WRAPPER" \
  "$B/arch_mutants/arch_mutants.exe" run "$W/t.db" --plan "$W/plan.json" --engine "$W/engine.sh" \
  --test-cmd true --catalogue "$W/cat.muts" --report "$W/report.json" --from mutaml \
  --tests 'file:test/**' --format json 2>"$W/err")"

persisted="$(grep -o '"status":[0-9]*' "$W/report.json" 2>/dev/null | head -1)"
assert_eq "the wrapper's raw code is what mutaml would persist" '"status":99' "$persisted"

jnum() { printf '%s' "$out" | grep -o "\"$1\": *[0-9]*" | grep -o '[0-9]*' | head -1; }
jbool() { printf '%s' "$out" | grep -o "\"$1\": *[a-z]*" | sed 's/.*: *//' | head -1; }

assert_eq "a refusal is not a kill"            "0"     "$(jnum killed)"
assert_eq "a refusal is not a timeout"         "0"     "$(jnum timed_out)"
assert_eq "a refusal is not a survivor"        "0"     "$(jnum survived)"
assert_eq "a refusal is not an engine error"   "0"     "$(jnum errored)"
assert_eq "the refusal is counted as its own"  "1"     "$(jnum mutants_refused_by_wrapper)"
assert_eq "a refused mutant is not attempted"  "0"     "$(jnum mutants_attempted)"
assert_eq "no attribution is recorded"         "0"     "$(jnum attributions_recorded)"
assert_eq "the campaign is not complete"       "false" "$(jbool completed)"
assert_eq "no run row is persisted"            "0"     "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_runs')"
assert_eq "no kill row is persisted"           "0"     "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_kills')"
assert_eq "completed_at stays NULL"            "0"     \
  "$(sqlite3 "$W/t.db" 'SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL')"

echo
if [ "$fails" -gt 0 ]; then
  echo "wrapper-refusal-not-a-kill: FAIL — $fails assertion(s) fired." >&2
  echo "  A wrapper that could not do its job was recorded as something other than a refusal." >&2
  echo "  The report the driver read was:" >&2
  sed 's/^/    | /' "$W/report.json" >&2 2>/dev/null
  exit 1
fi
echo "wrapper-refusal-not-a-kill: PASS — the wrapper refuses with $REFUSAL on every refusal path,"
echo "  and the driver maps exactly that code to a NOT-ATTEMPTED outcome. What would have made this"
echo "  non-zero: the pre-fix chain, where a refusal exited 2, mutaml persisted 2, and the adapter's"
echo "  \`Int _ -> KILLED\` arm turned it into a clean kill with completed_at stamped."
exit 0
