#!/usr/bin/env bash
# checks/generic-status-vocabulary-is-closed.sh — runnable directly. CHECK-29 / FR-031.
#
# The defect. `load_generic` read `status` as a bare string with no vocabulary check at all,
# unlike `load_mutaml`, which dies on an unrecognised one. `report` then bucketed it with
#
#     if st = "KILLED" || st = "TIMEOUT" then incr killed
#     else if st <> "SURVIVED" then incr errored
#
# — a catch-all over a CLOSED vocabulary. So a misspelled status ("SURVIVE", "survivedd"), or
# a fifth value added to the schema's CHECK without updating this bucketing, was counted as an
# ENGINE ERROR: a real defect removed from the defect list with no crash, no log, and a gate
# that still exits 0. `scripts/check-total-matches.sh` is structurally blind to this — its own
# header documents the `if x = "KILLED"` exclusion — which is why the refusal has to live in
# the code and not in the lint.
#
# What this pins:
#   1. an NDJSON record whose status is outside the vocabulary ABORTS (exit 2) and NAMES the
#      offending string, rather than being counted anywhere;
#   2. the same refusal fires under --fail-on-survivors, so the gate cannot pass on a report
#      it did not understand;
#   3. the NEGATIVE CONTROL: all four legal statuses and the wrapper's REFUSED still load and
#      are counted in their own buckets. Without it, "refuse everything" would pass 1 and 2.
#
# Exit: 0 = the vocabulary is closed and the four legal values still work;
#       1 = an assertion fired; >=2 = harness error.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd -P)"
repo="$(cd "$here/.." && pwd -P)"
B="$repo/_build/default/bin"

fatal() { echo "generic-status-vocabulary: $*" >&2; exit 2; }
for exe in arch_load/arch_load.exe arch_mutants/arch_mutants.exe; do
  [ -x "$B/$exe" ] || fatal "$B/$exe is not built — run 'dune build' first. Nothing was checked."
done

W="$(mktemp -d "${TMPDIR:-/tmp}/generic-status.XXXXXX")" || fatal "mktemp failed"
trap 'rm -rf "$W"' EXIT

fails=0
assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1 — $3"
  else echo "  ✗ $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

cat > "$W/stream.ndjson" <<'S'
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
S
"$B/arch_load/arch_load.exe" "$W/t.db" < "$W/stream.ndjson" >/dev/null 2>&1 || fatal "arch-load failed"

M() { "$B/arch_mutants/arch_mutants.exe" report "$W/t.db" "$1" --tests 'file:test/**' "${@:2}"; }

# ---- 1. an unrecognised status aborts, and says which one --------------------------------
# "SURVIVE" is one keystroke from the real thing and is exactly what the old catch-all read
# as an engine error: the survivor vanished from the defect list and the gate stayed green.
cat > "$W/typo.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SURVIVE","id":"m1"}
R
out="$(M "$W/typo.ndjson" --format json 2>&1)"; code=$?
assert_eq "a misspelled status aborts rather than being counted" "2" "$code"
assert_eq "the refusal names the offending string" "1" \
  "$(printf '%s' "$out" | grep -c '"SURVIVE"')"
# It must not have been quietly bucketed on the way out.
assert_eq "nothing was counted as an engine error instead" "0" \
  "$(printf '%s' "$out" | grep -c '"errored"')"

# ---- 2. the gate cannot pass on a report it did not understand ---------------------------
M "$W/typo.ndjson" --fail-on-survivors >/dev/null 2>&1
assert_eq "--fail-on-survivors also refuses the unknown status" "2" "$?"

# A value a future schema CHECK might add is the same case, and the one the FR is about.
cat > "$W/future.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SKIPPED","id":"m1"}
R
M "$W/future.ndjson" --format json >/dev/null 2>&1
assert_eq "a status added to the vocabulary elsewhere aborts here" "2" "$?"

# ---- 3. NEGATIVE CONTROL: the legal vocabulary still loads and still buckets --------------
# Without this, a `report` that refused every input would pass everything above.
cat > "$W/legal.ndjson" <<'R'
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/x.ml","line":16,"status":"KILLED","id":"m2"}
{"file":"lib/x.ml","line":17,"status":"TIMEOUT","id":"m3"}
{"file":"lib/x.ml","line":18,"status":"ERROR","id":"m4"}
{"file":"lib/x.ml","line":19,"status":"REFUSED","id":"m5"}
R
j="$(M "$W/legal.ndjson" --format json 2>"$W/err")"; code=$?
assert_eq "the five legal values load without a refusal" "0" "$code"
jnum() { printf '%s' "$j" | grep -o "\"$1\": *[0-9]*" | grep -o '[0-9]*' | head -1; }
assert_eq "KILLED and TIMEOUT are the killed bucket" "2" "$(jnum killed)"
assert_eq "ERROR alone is the errored bucket"        "1" "$(jnum errored)"
assert_eq "REFUSED is counted apart from both"       "1" "$(jnum refused_by_wrapper)"
assert_eq "SURVIVED is the only survivor"            "1" \
  "$(printf '%s' "$j" | grep -c '"function": *"covered"')"

echo
if [ "$fails" -gt 0 ]; then
  echo "generic-status-vocabulary: FAIL — $fails assertion(s) fired." >&2
  echo "  A status outside the closed vocabulary is being counted instead of refused, which" >&2
  echo "  deletes a defect from the defect list with no crash and no log." >&2
  exit 1
fi
echo "generic-status-vocabulary: PASS — an unrecognised status aborts and is named, while the"
echo "  four engine statuses and the wrapper's refusal still land in their own buckets."
exit 0
