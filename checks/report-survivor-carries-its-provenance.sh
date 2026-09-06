#!/usr/bin/env bash
# checks/report-survivor-carries-its-provenance.sh — runnable directly. CHECK-27 / FR-013.
#
# The defect. `arch-mutants report` printed survivors with NO selection provenance anywhere —
# not in the text rendering, not in the JSON, not per survivor — and `--fail-on-survivors`
# exited 1 on that unqualified list. So on an index whose TEST CONE ESCAPES through a ⊤ edge,
# where the very same status published through `run`/`verdict` is UNKNOWN because the reaching
# tests MAY NEVER HAVE RUN, `report` still called it a survivor and failed the build on it.
# That is the one thing this branch's soundness rule exists to forbid, bypassed by the
# subcommand a CI pipeline is most likely to invoke, while the driver's own comment at
# `arch_mutants.ml` states "FR-013: never a status without its provenance, in either format".
#
# What this pins, on two indexes that differ in exactly one edge:
#   A. cone CLOSED (the ⊤ edge is outside the test cone) → proved_superset, verdict SURVIVED,
#      and --fail-on-survivors FAILS. This is the negative control: without it, "refuse to
#      fail" would pass every other assertion here.
#   B. cone ESCAPES (a test reaches the ⊤-holding function) → top_bounded, verdict UNKNOWN,
#      the caveat is printed next to the survivor, and --fail-on-survivors does NOT fail —
#      because failing a build on a mutant whose reaching tests may never have run is a false
#      accusation against a real test.
#
# Exit: 0 = every survivor carries its provenance and the gate is qualified by the verdict;
#       1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
B="$repo/_build/default/bin"

fatal() { echo "report-survivor-provenance: $*" >&2; exit 2; }
for exe in arch_load/arch_load.exe arch_mutants/arch_mutants.exe; do
  [ -x "$B/$exe" ] || fatal "$B/$exe is not built — run 'dune build' first. Nothing was checked."
done

W="$(mktemp -d "${TMPDIR:-/tmp}/report-provenance.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

fails=0
assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1 — $3"
  else echo "  ✗ $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

# ---- the two indexes, differing in ONE edge ---------------------------------------------
# Shared: t_alpha -> covered(lib/x.ml:10-20), and dyn holds the only ⊤ edge.
common='{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"dyn","file_path":"lib/d.ml","line_start":1,"line_end":5}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/d.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/d.ml:3","kind":"MAY_TOP"}'

printf '%s\n' "$common" > "$W/closed.ndjson"
# The ONE extra edge: covered -> dyn drags the ⊤ holder INSIDE the test cone.
{ printf '%s\n' "$common"
  echo '{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"dyn","callee_file":"lib/d.ml","call_site":"lib/x.ml:12","kind":"MUST"}'
} > "$W/escaping.ndjson"

for v in closed escaping; do
  "$B/arch_load/arch_load.exe" "$W/$v.db" < "$W/$v.ndjson" >/dev/null 2>&1 \
    || fatal "arch-load failed for $v"
done

cat > "$W/report.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1","mutation":"a && b -> a || b"}
R

M() { "$B/arch_mutants/arch_mutants.exe" "$@"; }

# ---- PRECONDITION: the two indexes really do differ in cone escape ----------------------
# Read off `plan`, which has carried this measurement since before the fix, so the
# precondition cannot be satisfied by the code under test. Without it every assertion below
# could pass while both indexes were secretly identical.
proof_of() { M plan "$W/$1.db" --tests 'file:test/**' --format json \
  | grep -o '"unreached_is_proof": *[a-z]*' | sed 's/.*: *//'; }
[ "$(proof_of closed)" = "true" ] \
  || fatal "the closed fixture's cone is not closed; the contrast is gone"
[ "$(proof_of escaping)" = "false" ] \
  || fatal "the escaping fixture's cone does not escape; the contrast is gone"

# ---- 1. JSON carries the provenance, at the top and on every survivor -------------------
for v in closed:proved_superset escaping:top_bounded; do
  db="${v%%:*}"; want="${v##*:}"
  j="$(M report "$W/$db.db" "$W/report.ndjson" --tests 'file:test/**' --format json 2>/dev/null)"
  got="$(printf '%s' "$j" | grep -o '"selection_provenance": *"[a-z_]*"' | head -1 | sed 's/.*"\([a-z_]*\)"$/\1/')"
  assert_eq "$db: the report names its selection provenance" "$want" "${got:-<absent>}"
  # Per survivor, not only once at the top: the survivor line is what a reader copies out.
  n_surv="$(printf '%s' "$j" | grep -c '"function": *"covered"')"
  n_prov="$(printf '%s' "$j" | grep -c '"selection_provenance"')"
  assert_eq "$db: the survivor object carries the provenance too" "$((n_surv + 1))" "$n_prov"
done

vj="$(M report "$W/escaping.db" "$W/report.ndjson" --tests 'file:test/**' --format json 2>/dev/null)"
assert_eq "a ⊤-bounded survivor publishes UNKNOWN, not SURVIVED" "1" \
  "$(printf '%s' "$vj" | grep -c '"verdict": *"UNKNOWN"')"
cj="$(M report "$W/closed.db" "$W/report.ndjson" --tests 'file:test/**' --format json 2>/dev/null)"
assert_eq "a survivor under a proved superset publishes SURVIVED" "1" \
  "$(printf '%s' "$cj" | grep -c '"verdict": *"SURVIVED"')"

# ---- 2. the TEXT rendering says it too, next to the survivor ----------------------------
txt="$(M report "$W/escaping.db" "$W/report.ndjson" --tests 'file:test/**' 2>/dev/null)"
assert_eq "the text header names the selection provenance" "1" \
  "$(printf '%s' "$txt" | grep -c '^  . selection provenance: top_bounded')"
assert_eq "the text header states the caveat in words" "1" \
  "$(printf '%s' "$txt" | grep -c 'MAY have missed a covering test')"
# The line a reader copies out is the SURVIVOR line, so the qualification has to be on it and
# not only in a header six lines up.
assert_eq "the survivor line publishes UNKNOWN, not SURVIVED" "1" \
  "$(printf '%s' "$txt" | grep -c '^  . UNKNOWN lib/x.ml:15')"
assert_eq "the survivor line carries its own provenance" "1" \
  "$(printf '%s' "$txt" | grep -c 'engine status SURVIVED under top_bounded')"
assert_eq "no survivor is printed as a bare SURVIVED" "0" \
  "$(printf '%s' "$txt" | grep -c '^  . SURVIVED ')"

# ---- 3. the gate fails on a genuine survivor and only on one ----------------------------
M report "$W/closed.db" "$W/report.ndjson" --tests 'file:test/**' --fail-on-survivors >/dev/null 2>&1
assert_eq "--fail-on-survivors fails on a proved survivor" "1" "$?"
M report "$W/escaping.db" "$W/report.ndjson" --tests 'file:test/**' --fail-on-survivors >/dev/null 2>&1
assert_eq "--fail-on-survivors does NOT fail on a ⊤-bounded UNKNOWN" "0" "$?"

echo
if [ "$fails" -gt 0 ]; then
  echo "report-survivor-provenance: FAIL — $fails assertion(s) fired." >&2
  echo "  \`report\` is publishing a status without its selection provenance, or failing a" >&2
  echo "  build on a mutant whose reaching tests may never have run." >&2
  exit 1
fi
echo "report-survivor-provenance: PASS — every survivor carries its provenance and the gate"
echo "  fires only on a verdict that is genuinely SURVIVED."
exit 0
