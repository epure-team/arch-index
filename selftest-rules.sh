#!/usr/bin/env bash
# selftest-rules.sh — architecture fitness functions (§2).
#
# The property that matters most here is that the FOUR verdicts stay distinct. A tool that
# collapses "I proved it cannot" into "I found nothing" is exactly the tool this one exists to
# replace, so every test below is really the same test: does the engine still know the
# difference between a proof and a blind spot?
#
#   VIOLATION            a MUST path exists
#   POSSIBLE             reachable only over MAY_ENUMERATED
#   UNKNOWN              nothing found, but the cone escapes through a ⊤ edge
#   UNKNOWN_NO_CONTRACT  nothing found, on an index that never marked ⊤ at all
#   PASS                 nothing found, cone closed, index ⊤-marked — a real proof
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; RULES="$HERE/arch-rules"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-rules: python3 required" >&2; exit 2; }

# stdin: assert it is EXACTLY one JSON object (no trailing garbage) and that no float/Intlit
# value appears anywhere in the tree — the machine-output contract is int/bool/string/null/
# array/object only.
strict_json_ok() {
  python3 -c '
import json, sys
s = sys.stdin.read().lstrip()
dec = json.JSONDecoder()
obj, idx = dec.raw_decode(s)
assert s[idx:].strip() == "", "trailing data after the JSON object"
def walk(v):
    if isinstance(v, float):
        raise AssertionError("float found in machine output: %r" % (v,))
    if isinstance(v, dict):
        for x in v.values():
            walk(x)
    elif isinstance(v, list):
        for x in v:
            walk(x)
walk(obj)
'
}

# Layered fixture:
#   ui.handle   --MUST-->        db.write          (a definite layering violation)
#   api.serve   --MAY_ENUM-->    db.write          (possible: dynamic dispatch could land there)
#   job.run     --MUST--> util.helper --MAY_TOP--> ⊤   (escapes: cannot rule anything out)
#   pure.calc   --MUST-->        pure.inner        (closed cone: a real proof)
DB="$(mktemp --suffix=.db)"; rm -f "$DB"
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"ui.handle","file_path":"src/ui/handler.ts","exported":true}
{"type":"function","name":"api.serve","file_path":"src/api/serve.ts","exported":true}
{"type":"function","name":"job.run","file_path":"src/job/run.ts"}
{"type":"function","name":"util.helper","file_path":"src/util/helper.ts"}
{"type":"function","name":"pure.calc","file_path":"src/pure/calc.ts"}
{"type":"function","name":"pure.inner","file_path":"src/pure/inner.ts"}
{"type":"function","name":"db.write","file_path":"lib/db/write.ts"}
{"type":"function","name":"db.my_write","file_path":"lib/db/my_write.ts"}
{"type":"call","caller_name":"ui.handle","caller_file":"src/ui/handler.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/ui/handler.ts:5","kind":"MUST"}
{"type":"call","caller_name":"api.serve","caller_file":"src/api/serve.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/api/serve.ts:9","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"job.run","caller_file":"src/job/run.ts","callee_name":"util.helper","callee_file":"src/util/helper.ts","call_site":"src/job/run.ts:3","kind":"MUST"}
{"type":"call","caller_name":"util.helper","caller_file":"src/util/helper.ts","callee_name":"*TOP*","callee_file":null,"call_site":"src/util/helper.ts:7","kind":"MAY_TOP"}
{"type":"call","caller_name":"pure.calc","caller_file":"src/pure/calc.ts","callee_name":"pure.inner","callee_file":"src/pure/inner.ts","call_site":"src/pure/calc.ts:2","kind":"MUST"}
NDJSON
[ -f "$DB" ] || { echo "selftest-rules: loader produced no DB" >&2; exit 1; }

RF="$(mktemp)"
cat > "$RF" <<'EOF'
rule "ui must not reach persistence"
  forbid reach from file:src/ui/** to file:lib/db/**
rule "api must not reach persistence"
  forbid reach from file:src/api/** to file:lib/db/**
rule "jobs must not reach persistence"
  forbid reach from file:src/job/** to file:lib/db/**
rule "pure code must not reach persistence"
  forbid reach from file:src/pure/** to file:lib/db/**
EOF
OUT="$("$RULES" "$DB" "$RF" --format json 2>/dev/null)"
v() { printf '%s' "$OUT" | python3 -c "
import json,sys
for r in json.load(sys.stdin)['results']:
    if r['rule'].startswith('$1'): print(r['verdict']); break
"; }
[ "$(v 'ui must')"   = "VIOLATION" ] || note "MUST path ui→db must be VIOLATION, got $(v 'ui must')"
[ "$(v 'api must')"  = "POSSIBLE"  ] || note "MAY_ENUMERATED path api→db must be POSSIBLE, got $(v 'api must')"
[ "$(v 'jobs must')" = "UNKNOWN"   ] || note "a cone escaping through ⊤ must be UNKNOWN, got $(v 'jobs must')"
[ "$(v 'pure code')" = "PASS"      ] || note "a closed cone on a ⊤-marked index must PASS, got $(v 'pure code')"

# --- machine-output contract: one strict JSON object, computed/contract_ok/verdict/counts -----
printf '%s' "$OUT" | strict_json_ok \
  || note "arch-rules --format json must emit exactly one JSON object with no float/Intlit values"
printf '%s' "$OUT" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["computed"] is True, r["computed"]
assert r["contract_ok"] is True, r          # this DB is ⊤-marked (kinded edges throughout)
assert r["verdict"] == "fail", r["verdict"] # ui (VIOLATION) and api (POSSIBLE, fails by default)
assert r["failing"] == len(r["failed"]) == 2, (r["failing"], r["failed"])
assert r["unknown"] == 1, r["unknown"]      # jobs must (UNKNOWN)
assert r["vacuous"] == 0, r["vacuous"]
assert r["not_computed"] == 0, r["not_computed"]
' 2>/dev/null || note "computed/contract_ok/verdict/failing/unknown/vacuous/not_computed must be present and coherent"
"$RULES" "$DB" "$RF" >/dev/null 2>&1
[ $? -eq 1 ] || note "verdict 'fail' above must correspond to exit code 1"

# --- the glob boundary: lib/db/** must not be confused with a sibling ---------------------
# A rule aimed at lib/db/write.ts must not silently also cover lib/db/my_write.ts's neighbours,
# and **/write.ts must NOT match my_write.ts — a boundary slip here breaks verdicts both ways.
BF="$(mktemp)"
cat > "$BF" <<'EOF'
rule "boundary"
  forbid reach from file:src/ui/** to file:**/write.ts
EOF
BOUT="$("$RULES" "$DB" "$BF" --format json 2>/dev/null)"
printf '%s' "$BOUT" | python3 -c '
import json,sys
r=json.load(sys.stdin)["results"][0]
assert r["verdict"]=="VIOLATION", r
assert r["target_size"]==1, ("**/write.ts must match write.ts ONLY, not my_write.ts", r)
' 2>/dev/null || note "**/write.ts must match exactly one file (not my_write.ts)"

# --- exported-outside ---------------------------------------------------------------------
EF="$(mktemp)"
cat > "$EF" <<'EOF'
rule "only the api layer is exported"
  forbid exported outside file:src/api/**
EOF
EOUT="$("$RULES" "$DB" "$EF" --format json 2>/dev/null)"
printf '%s' "$EOUT" | python3 -c '
import json,sys
r=json.load(sys.stdin)["results"][0]
assert r["verdict"]=="VIOLATION", r
assert len(r["detail"])==1 and "ui.handle" in r["detail"][0], r["detail"]
' 2>/dev/null || note "exported-outside must flag ui.handle and only ui.handle"

# --- a vacuous rule is a FAILURE, not a pass ----------------------------------------------
VF="$(mktemp)"
cat > "$VF" <<'EOF'
rule "aimed at nothing"
  forbid reach from file:src/nonexistent/** to file:lib/db/**
EOF
"$RULES" "$DB" "$VF" >/dev/null 2>&1
[ $? -eq 1 ] || note "a rule matching no code must FAIL by default (a gate that gates nothing)"
"$RULES" "$DB" "$VF" --on-vacuous warn >/dev/null 2>&1
[ $? -eq 0 ] || note "--on-vacuous warn must downgrade a vacuous rule to a warning"

# --- exit-code policy ----------------------------------------------------------------------
PF="$(mktemp)"; printf 'rule "p"\n  forbid reach from file:src/api/** to file:lib/db/**\n' > "$PF"
"$RULES" "$DB" "$PF" >/dev/null 2>&1;                     [ $? -eq 1 ] || note "POSSIBLE must fail by default"
"$RULES" "$DB" "$PF" --on-possible warn >/dev/null 2>&1;  [ $? -eq 0 ] || note "--on-possible warn must not fail"
UF="$(mktemp)"; printf 'rule "u"\n  forbid reach from file:src/job/** to file:lib/db/**\n' > "$UF"
"$RULES" "$DB" "$UF" >/dev/null 2>&1;                     [ $? -eq 0 ] || note "UNKNOWN must be fail-open by default"
"$RULES" "$DB" "$UF" --on-unknown fail >/dev/null 2>&1;   [ $? -eq 1 ] || note "--on-unknown fail must fail"

# --- an index with NO ⊤-marking may never emit PASS -----------------------------------------
# Same graph shape as the closed-cone case, but built without the contract: "no path" there may
# merely hide a dropped dynamic edge, so the proof is not available.
LEGACY="$(mktemp --suffix=.db)"; rm -f "$LEGACY"
sqlite3 "$LEGACY" <<'SQL'
CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0,
                       line_start INTEGER, line_end INTEGER);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT,
                   call_site TEXT);
INSERT INTO functions(name,file_path) VALUES ('pure.calc','src/pure/calc.ts'),
                                             ('pure.inner','src/pure/inner.ts'),
                                             ('db.write','lib/db/write.ts');
INSERT INTO calls VALUES ('pure.calc','src/pure/calc.ts','pure.inner','src/pure/inner.ts','x:1');
SQL
LF="$(mktemp)"; printf 'rule "l"\n  forbid reach from file:src/pure/** to file:lib/db/**\n' > "$LF"
LOUT="$("$RULES" "$LEGACY" "$LF" --format json 2>/dev/null)"
printf '%s' "$LOUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
r=d["results"][0]
assert r["verdict"]=="UNKNOWN_NO_CONTRACT", r
assert d["contract_ok"] is False, d          # top-level contract_ok must track the same fact
' 2>/dev/null || note "an un-⊤-marked index must degrade PASS to UNKNOWN_NO_CONTRACT, never PASS, and report contract_ok:false"

# --- a malformed rule file ABORTS ----------------------------------------------------------
# A gate that silently skips the rule it could not parse is a gate that silently stops gating.
for bad in 'forbid reach from file:a to file:b' \
           'rule "x"' \
           'rule "x"
  forbid teleport from file:a to file:b' \
           'rule "x"
  forbid reach from a to file:b'; do
  MF="$(mktemp)"; printf '%s\n' "$bad" > "$MF"
  "$RULES" "$DB" "$MF" >/dev/null 2>&1
  [ $? -eq 2 ] || note "malformed rule file must abort with exit 2: <<$bad>>"
  rm -f "$MF"
done
EMPTY="$(mktemp)"; : > "$EMPTY"
"$RULES" "$DB" "$EMPTY" >/dev/null 2>&1
[ $? -eq 2 ] || note "an empty rules file must abort — reporting a vacuous all-pass is worse"

# --- effect / dep rules report NOT_COMPUTED, never a false clean ---------------------------
NF="$(mktemp)"
cat > "$NF" <<'EOF'
rule "no global mutation from ui"
  forbid effect from file:src/ui/** kind:GlobalVar
rule "ui must not declare a dep on db"
  forbid dep from module:src/ui/** to module:lib/db/**
EOF
NOUT="$("$RULES" "$DB" "$NF" --format json 2>/dev/null)"
printf '%s' "$NOUT" | python3 -c '
import json,sys
vs=[r["verdict"] for r in json.load(sys.stdin)["results"]]
assert vs==["NOT_COMPUTED","NOT_COMPUTED"], vs
' 2>/dev/null || note "effect/dep rules on an index lacking that data must say NOT_COMPUTED, not PASS"

# ...and saying NOT_COMPUTED is only half the job: a rule that reads "n/a" on every run is
# indistinguishable from one that passes, so it must FAIL the gate by default. Unlike UNKNOWN
# (an analysis result), NOT_COMPUTED means the rule was never evaluated at all.
"$RULES" "$DB" "$NF" >/dev/null 2>&1
[ $? -eq 1 ] || note "NOT_COMPUTED must fail the gate by default — a never-evaluated rule is not a passing rule"
"$RULES" "$DB" "$NF" --on-not-computed warn >/dev/null 2>&1
[ $? -eq 0 ] || note "--on-not-computed warn must downgrade NOT_COMPUTED to a warning"
printf '%s' "$NOUT" | python3 -c '
import json,sys
d=json.load(sys.stdin); assert len(d["failed"])==2, d["failed"]
assert d["failing"]==2 and d["not_computed"]==2 and d["unknown"]==0 and d["vacuous"]==0, d
assert d["verdict"]=="fail", d["verdict"]
' 2>/dev/null || note "the json report must list NOT_COMPUTED rules under failed, and count them in not_computed/failing"
printf '%s' "$NOUT" | strict_json_ok || note "arch-rules JSON must stay strict on the NOT_COMPUTED path too"
# arch-rules never refuses at the process level (no exit 3 anywhere in this tool) — confirm the
# verdict vocabulary stays within {pass, fail}, so a workflow gate never has to special-case a
# third value that cannot occur here.
for j in "$OUT" "$LOUT" "$NOUT"; do
  printf '%s' "$j" | python3 -c '
import json,sys
assert json.load(sys.stdin)["verdict"] in ("pass","fail")
' 2>/dev/null || note "arch-rules verdict must always be pass or fail, never refused (this tool has no exit-3 path)"
done

# --- a misspelled policy must ABORT, never silently disable the gate ------------------------
# `--on-possible fial` used to compare unequal to "fail" and turn a failing rule green: the
# safest-looking flag in the tool was the one that removed the check.
for bad in --on-unknown --on-possible --on-vacuous --on-not-computed; do
  "$RULES" "$DB" "$RF" "$bad" fial >/dev/null 2>&1
  [ $? -eq 2 ] || note "$bad with a misspelled value must abort, not be read as 'do not fail'"
done

rm -f "$DB" "$LEGACY" "$RF" "$BF" "$EF" "$VF" "$PF" "$UF" "$LF" "$NF" "$EMPTY"
if [ "$fails" -eq 0 ]; then echo "selftest-rules: PASS"; else echo "selftest-rules: $fails FAILURE(S)"; exit 1; fi
