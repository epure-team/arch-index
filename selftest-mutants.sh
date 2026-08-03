#!/usr/bin/env bash
# selftest-mutants.sh — call-graph-targeted mutation testing (§1).
#
# arch-index does not mutate anything; it decides WHAT is worth mutating and WHO should have
# caught each survivor. So the properties under test are all about the join being honest:
#
#   1. every indexed function lands in exactly one plan bucket (nothing silently vanishes)
#   2. a target carries the tests that must rerun for it
#   3. code no test reaches is NOT a mutation target — it is a dead-code finding
#   4. a survivor is attributed to the innermost enclosing function, with its reaching tests
#   5. a survivor that maps to no indexed function is REPORTED, never dropped
#   6. the mutaml adapter reads both status encodings and REFUSES anything else
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; MUT="$HERE/arch-mutants"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-mutants: python3 required" >&2; exit 2; }

# t_alpha --MUST--> covered (10-20) --MUST--> inner (14-16)   both targets, via t_alpha
#                              `--MUST--> shared (30-40)        target, via t_alpha AND t_beta
# t_beta  --MUST--> shared
# (nobody) --------> orphan (50-60)                             dead-code territory, not a target
# dyn --MAY_TOP--> ⊤ ; dyn --MUST--> shadowed                   a ⊤ edge OUTSIDE the test cone,
#                                                               which must not weaken anything
DB="$(mktemp --suffix=.db)"; rm -f "$DB"
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"t_beta","file_path":"test/beta_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"inner","file_path":"lib/x.ml","line_start":14,"line_end":16}
{"type":"function","name":"shared","file_path":"lib/y.ml","line_start":30,"line_end":40}
{"type":"function","name":"orphan","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"function","name":"dyn","file_path":"lib/d.ml","line_start":1,"line_end":5}
{"type":"function","name":"shadowed","file_path":"lib/d.ml","line_start":7,"line_end":9}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"inner","callee_file":"lib/x.ml","call_site":"lib/x.ml:13","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"shared","callee_file":"lib/y.ml","call_site":"lib/x.ml:12","kind":"MUST"}
{"type":"call","caller_name":"t_beta","caller_file":"test/beta_test.ml","callee_name":"shared","callee_file":"lib/y.ml","call_site":"test/beta_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/d.ml","callee_name":"shadowed","callee_file":"lib/d.ml","call_site":"lib/d.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/d.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/d.ml:3","kind":"MAY_TOP"}
NDJSON
[ -f "$DB" ] || { echo "selftest-mutants: loader produced no DB" >&2; exit 1; }

PLAN="$("$MUT" plan "$DB" --tests 'file:test/**' --format json 2>/dev/null)"

# --- 1. the buckets partition the index ----------------------------------------------------
printf '%s' "$PLAN" | python3 -c '
import json,sys; p=json.load(sys.stdin)
assert p["unaccounted"]==0, ("functions lost from the plan", p["unaccounted"])
' 2>/dev/null || note "every indexed function must land in exactly one bucket (unaccounted != 0)"

# --- 2. targets carry the tests that must rerun --------------------------------------------
printf '%s' "$PLAN" | python3 -c '
import json,sys; p=json.load(sys.stdin)
t={x["function"]: x for x in p["targets"]}
assert set(t)=={"covered","inner","shared"}, sorted(t)
assert t["covered"]["reaching_tests"]==["t_alpha"], t["covered"]
assert t["shared"]["reaching_tests"]==["t_alpha","t_beta"], t["shared"]
' 2>/dev/null || note "targets must be exactly the test-reachable functions, each with its reaching tests"

# --- 3. unreached code is a dead-code finding, not a mutation target ------------------------
printf '%s' "$PLAN" | python3 -c '
import json,sys; p=json.load(sys.stdin)
assert "orphan" in p["unreached"], p["unreached"]
assert "orphan" not in [x["function"] for x in p["targets"]]
# dyn holds the only ⊤ edge, and NO test reaches dyn — so it cannot make anything secretly
# tested, and the unreached list stays a proof.
assert p["test_cone_escapes"]==[], p["test_cone_escapes"]
assert p["unreached_is_proof"] is True, p
assert set(p["unreached"])=={"orphan","dyn","shadowed"}, p["unreached"]
' 2>/dev/null || note "a ⊤ edge OUTSIDE the test cone must not weaken the unreached proof"

# --- 3b. a ⊤ edge INSIDE the test cone destroys the proof ----------------------------------
DB2="$(mktemp --suffix=.db)"; rm -f "$DB2"
"$LOAD" "$DB2" <<'NDJSON' 2>/dev/null
{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"orphan","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/x.ml:12","kind":"MAY_TOP"}
NDJSON
"$MUT" plan "$DB2" --tests 'file:test/**' --format json 2>/dev/null | python3 -c '
import json,sys; p=json.load(sys.stdin)
assert p["test_cone_escapes"]==["covered"], p["test_cone_escapes"]
assert p["unreached_is_proof"] is False, p
assert p["unaccounted"]==0, p["unaccounted"]
' 2>/dev/null || note "a ⊤ edge INSIDE the test cone must drop unreached_is_proof to False"
"$MUT" plan "$DB2" --tests 'file:test/**' 2>/dev/null | grep -q 'not a proof' \
  || note "the text report must say the unreached list is not a proof when the cone escapes"
rm -f "$DB2"

# --- the allowlist form is engine-consumable -----------------------------------------------
LINES="$("$MUT" plan "$DB" --tests 'file:test/**' --format lines 2>/dev/null | sort)"
[ "$(printf '%s' "$LINES" | grep -c .)" = "3" ] || note "the allowlist must have one range per spanned target"
printf '%s' "$LINES" | grep -q '^lib/x.ml:10-20$' || note "allowlist must carry file:start-end ranges"

# --- an empty --tests selector must ABORT, not plan against nothing -------------------------
"$MUT" plan "$DB" --tests 'file:nope/**' >/dev/null 2>&1
[ $? -eq 2 ] || note "a --tests selector matching nothing must abort (else every function reads as unreached)"

# --- 4./5. attribution -----------------------------------------------------------------------
MR="$(mktemp)"
cat > "$MR" <<'NDJSON'
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"1","mutation":"a && b -> a || b"}
{"file":"lib/y.ml","line":35,"status":"SURVIVED","id":"2"}
{"file":"lib/x.ml","line":11,"status":"KILLED","id":"3"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"4"}
{"file":"lib/absent.ml","line":3,"status":"SURVIVED","id":"5"}
NDJSON
REP="$("$MUT" report "$DB" "$MR" --tests 'file:test/**' --format json 2>/dev/null)"
printf '%s' "$REP" | python3 -c '
import json,sys; r=json.load(sys.stdin)
s={x["id"]: x for x in r["survivors"]}
assert r["killed"]==1, r["killed"]
# line 15 sits in BOTH covered(10-20) and inner(14-16): the innermost span must win, otherwise
# a survivor is blamed on an enclosing function the developer would have to hunt through.
assert s["1"]["function"]=="inner", s["1"]
assert s["2"]["reaching_tests"]==["t_alpha","t_beta"], s["2"]
# a survivor in code no test reaches is NOT a weak test — it is untested code, and must say so
assert s["4"]["function"]=="orphan" and s["4"]["reaching_tests"]==[], s["4"]
# a survivor that maps to nothing indexed must be REPORTED, never silently dropped
assert [m["file"] for m in r["unmapped"]]==["lib/absent.ml"], r["unmapped"]
assert r["total"]==5, r["total"]
' 2>/dev/null || note "attribution must pick the innermost span, list reaching tests, and report unmapped survivors"

"$MUT" report "$DB" "$MR" --tests 'file:test/**' --fail-on-survivors >/dev/null 2>&1
[ $? -eq 1 ] || note "--fail-on-survivors must exit 1 when survivors exist"
CLEAN="$(mktemp)"; printf '%s\n' '{"file":"lib/x.ml","line":11,"status":"KILLED","id":"9"}' > "$CLEAN"
"$MUT" report "$DB" "$CLEAN" --tests 'file:test/**' --fail-on-survivors >/dev/null 2>&1
[ $? -eq 0 ] || note "--fail-on-survivors must exit 0 when every mutant was killed"

# --- 6. the mutaml adapter -------------------------------------------------------------------
# mutaml's own sources disagree on `status`: the type says int (exit code), the runner maps exit
# codes to strings first. Both must work; anything else must ABORT rather than be guessed,
# because a mis-read status inverts the verdict and deletes a real defect from the report.
mk_mutaml() {  # $1 = status literal (JSON), $2 = out file
  cat > "$2" <<EOF
[{"status":$1,"mutant":{"number":3,"repl":"true","loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":15,"pos_bol":0,"pos_cnum":0},"loc_end":{"pos_fname":"lib/x.ml","pos_lnum":15,"pos_bol":0,"pos_cnum":9},"loc_ghost":false}}}]
EOF
}
for pair in '0:1' '"passed":1' '1:0' '"failed":0' '124:0' '"timeout":0'; do
  st="${pair%:*}"; want="${pair##*:}"
  MJ="$(mktemp)"; mk_mutaml "$st" "$MJ"
  got="$("$MUT" report "$DB" "$MJ" --from mutaml --tests 'file:test/**' --format json 2>/dev/null \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["survivors"]))' 2>/dev/null)"
  [ "$got" = "$want" ] || note "mutaml status $st should give $want survivor(s), got '$got'"
  rm -f "$MJ"
done
BAD="$(mktemp)"; mk_mutaml '"weird"' "$BAD"
"$MUT" report "$DB" "$BAD" --from mutaml --tests 'file:test/**' >/dev/null 2>&1
[ $? -eq 2 ] || note "an unrecognised mutaml status must ABORT — guessing it inverts the verdict"
NOLOC="$(mktemp)"
printf '%s\n' '[{"status":0,"mutant":{"number":1,"repl":null,"loc":{}}}]' > "$NOLOC"
"$MUT" report "$DB" "$NOLOC" --from mutaml --tests 'file:test/**' >/dev/null 2>&1
[ $? -eq 2 ] || note "a mutaml entry with no usable loc must abort, not be silently skipped"
NOTLIST="$(mktemp)"; printf '%s\n' '{"status":0}' > "$NOTLIST"
"$MUT" report "$DB" "$NOTLIST" --from mutaml --tests 'file:test/**' >/dev/null 2>&1
[ $? -eq 2 ] || note "a mutaml report that is not a JSON array must abort"

# mutaml attribution must reach the same answer as the generic path for the same location
MJ="$(mktemp)"; mk_mutaml '0' "$MJ"
"$MUT" report "$DB" "$MJ" --from mutaml --tests 'file:test/**' --format json 2>/dev/null \
  | python3 -c '
import json,sys; s=json.load(sys.stdin)["survivors"][0]
assert s["function"]=="inner", s
assert s["reaching_tests"]==["t_alpha"], s
' 2>/dev/null || note "the mutaml adapter must attribute exactly as the generic path does"

rm -f "$DB" "$MR" "$CLEAN" "$BAD" "$NOLOC" "$NOTLIST" "$MJ"
if [ "$fails" -eq 0 ]; then echo "selftest-mutants: PASS"; else echo "selftest-mutants: $fails FAILURE(S)"; exit 1; fi
