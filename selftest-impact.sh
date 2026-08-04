#!/usr/bin/env bash
# selftest-impact.sh — change-impact briefing (§3). Builds a throwaway git repo + a ⊤-marked DB
# from synthetic NDJSON, then checks that arch-impact answers each question correctly AND labels
# every approximation in the right direction.
#
# The properties under test, in order of how badly a regression would hurt:
#   1. a diff hunk maps to the function whose line span contains it — and to NO other
#   2. reverse reachability finds the callers, and separates DEFINITE from MAY (⊤-hidden)
#   3. forward reachability reports the ⊤ frontier instead of pretending the radius is a bound
#   4. an index with no line spans degrades to FILE granularity loudly, never silently
#   5. --fail-on-new-findings is exit-1 only when the diff actually touches a finding line
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; IMPACT="$HERE/arch-impact"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }

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
command -v python3 >/dev/null 2>&1 || { echo "selftest-impact: python3 required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "selftest-impact: git required" >&2; exit 2; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t

# app.src: three functions at known, non-overlapping line spans.
#   lines 1-3   entry     (exported)
#   lines 5-7   helper
#   lines 9-11  unrelated (exported) — must NEVER be touched by a hunk inside helper
mkdir -p "$REPO/src"
cat > "$REPO/src/app.src" <<'EOF'
fn entry:
  call helper
  end
EOF
cat >> "$REPO/src/app.src" <<'EOF'

fn helper:
  compute
  end

fn unrelated:
  noop
  end
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -qm init

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"entry","file_path":"src/app.src","exported":true,"line_start":1,"line_end":3}
{"type":"function","name":"helper","file_path":"src/app.src","line_start":5,"line_end":7}
{"type":"function","name":"unrelated","file_path":"src/app.src","exported":true,"line_start":9,"line_end":11}
{"type":"function","name":"reflector","file_path":"src/dyn.src","exported":true,"line_start":1,"line_end":2}
{"type":"function","name":"test_helper","file_path":"test/app_test.src","line_start":1,"line_end":2}
{"type":"call","caller_name":"entry","caller_file":"src/app.src","callee_name":"helper","callee_file":"src/app.src","call_site":"src/app.src:2","kind":"MUST"}
{"type":"call","caller_name":"test_helper","caller_file":"test/app_test.src","callee_name":"helper","callee_file":"src/app.src","call_site":"test/app_test.src:1","kind":"MUST"}
{"type":"call","caller_name":"helper","caller_file":"src/app.src","callee_name":"unrelated","callee_file":"src/app.src","call_site":"src/app.src:6","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"reflector","caller_file":"src/dyn.src","callee_name":"*TOP*","callee_file":null,"call_site":"src/dyn.src:1","kind":"MAY_TOP"}
NDJSON
[ -f "$DB" ] || { echo "selftest-impact: loader produced no DB" >&2; exit 1; }

# line spans must survive the load — everything else here depends on it
spans=$(sqlite3 "$DB" "SELECT count(*) FROM functions WHERE line_start IS NOT NULL;")
[ "$spans" = "5" ] || note "expected 5 loaded line spans, got $spans"

# --- 1. hunk → function, at line granularity ---------------------------------------------
# Edit ONLY line 6 (inside helper). entry and unrelated must not appear as touched.
sed -i '6s/.*/  compute_v2/' "$REPO/src/app.src"
git -C "$REPO" commit -qam "change helper"
OUT="$("$IMPACT" "$DB" --diff HEAD~1..HEAD --repo "$REPO" --format json 2>/dev/null)"
touched=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(",".join(sorted(t["name"] for t in json.load(sys.stdin)["touched"])))')
[ "$touched" = "helper" ] || note "hunk on line 6 should touch exactly 'helper', got '$touched'"

# --- 2. reverse reachability, definite vs ⊤-hidden ----------------------------------------
# entry and test_helper definitely reach helper; reflector holds a ⊤ edge so it MAY.
get() { printf '%s' "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"$1\"])"; }
[ "$(get upstream_count)" = "2" ] || note "expected 2 definite upstream (entry, test_helper), got $(get upstream_count)"
printf '%s' "$OUT" | grep -q '"entry ' || note "entry should be listed as an affected exported function"
[ "$(get may_upstream_count)" = "1" ] || note "expected reflector as the single ⊤-hidden may-caller, got $(get may_upstream_count)"
printf '%s' "$OUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert "reflector" in " ".join(r["may_affected_exported"]), r["may_affected_exported"]
assert any("test_helper" in t for t in r["tests_reaching"]), r["tests_reaching"]
' 2>/dev/null || note "reflector must be a MAY-affected export and test_helper a reaching test"

# a definite caller must NOT also be counted as a may-caller (double counting)
printf '%s' "$OUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert not any("entry" in s for s in r["may_affected_exported"]), r["may_affected_exported"]
' 2>/dev/null || note "entry is a DEFINITE caller and must not be repeated in the may-reach set"

# --- 3. forward radius is reported as a lower bound, with the frontier --------------------
[ "$(get downstream_count)" = "1" ] || note "helper should definitely reach 1 function (unrelated), got $(get downstream_count)"
"$IMPACT" "$DB" --diff HEAD~1..HEAD --repo "$REPO" 2>/dev/null | grep -q 'lower bound' \
  || note "the forward radius must be labelled a lower bound, never a bound"

# --- 4. an unchanged-span sibling is never dragged in -------------------------------------
printf '%s' "$OUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert "unrelated" not in [t["name"] for t in r["touched"]], r["touched"]
' 2>/dev/null || note "'\''unrelated'\'' (lines 9-11) must not be touched by a hunk on line 6"

# --- 4b. an index whose producer computed no decisions must say "not computed" -------------
printf '%s' "$OUT" | python3 -c '
import json,sys
assert json.load(sys.stdin)["decision_analysis_available"] is False
' 2>/dev/null || note "an empty decisions table must read as NOT COMPUTED, never as 'nothing to report'"

# --- 4c. machine-output contract: one strict JSON object, computed/contract_ok/verdict --------
printf '%s' "$OUT" | strict_json_ok \
  || note "arch-impact --format json must emit exactly one JSON object with no float/Intlit values"
printf '%s' "$OUT" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["computed"] is True, r["computed"]
assert isinstance(r["contract_ok"], bool)
assert r["verdict"] == "pass", r["verdict"]                # --fail-on-new-findings was not requested
assert r["new_findings"] == len(r["findings"]["decisions"])
assert r["findings"]["computed"] is False, r["findings"]    # no decisions table on this index
assert isinstance(r["findings"]["reason"], str) and r["findings"]["reason"], r["findings"]
' 2>/dev/null || note "computed/contract_ok/verdict/findings.computed+reason must be present and coherent"

# --- 5. no-span index degrades to file granularity, LOUDLY --------------------------------
NOSPAN="$(mktemp --suffix=.db)"; rm -f "$NOSPAN"
"$LOAD" "$NOSPAN" <<'NDJSON' 2>/dev/null
{"type":"function","name":"entry","file_path":"src/app.src","exported":true}
{"type":"function","name":"helper","file_path":"src/app.src"}
{"type":"call","caller_name":"entry","caller_file":"src/app.src","callee_name":"helper","callee_file":"src/app.src","call_site":"src/app.src:2","kind":"MUST"}
NDJSON
ERR="$("$IMPACT" "$NOSPAN" --diff HEAD~1..HEAD --repo "$REPO" 2>&1 >/dev/null)"
printf '%s' "$ERR" | grep -q 'no function in this index has a line span' \
  || note "a span-less index must warn on stderr, not silently over-attribute"
NS="$("$IMPACT" "$NOSPAN" --diff HEAD~1..HEAD --repo "$REPO" --format json 2>/dev/null)"
printf '%s' "$NS" | python3 -c '
import json,sys; r=json.load(sys.stdin)
names=sorted(t["name"] for t in r["touched"])
assert names==["entry","helper"], names          # whole file, over-attributed on purpose
assert all(t["how"].startswith("file") for t in r["touched"]), r["touched"]
assert r["files_file_granular"]==["src/app.src"], r["files_file_granular"]
' 2>/dev/null || note "span-less index must map the whole FILE and say so in `how`/files_file_granular"

# --- 6. a HALF span is refused at load time -----------------------------------------------
HALF="$(mktemp --suffix=.db)"; rm -f "$HALF"
printf '%s\n%s\n' \
  '{"type":"function","name":"f","file_path":"x","line_start":3}' \
  '{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}' \
  | "$LOAD" "$HALF" >/dev/null 2>&1
[ $? -eq 0 ] && note "a function record with line_start but no line_end must ABORT the load"

# --- 7. --fail-on-new-findings only fires on a touched finding line ------------------------
FDB="$(mktemp --suffix=.db)"; rm -f "$FDB"
"$LOAD" "$FDB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"helper","file_path":"src/app.src","line_start":5,"line_end":7}
{"type":"call","caller_name":"helper","caller_file":"src/app.src","callee_name":"x","callee_file":null,"call_site":"src/app.src:6","kind":"MUST"}
{"type":"decision","file_path":"src/app.src","line":6,"col":3,"form":"if","arity":2,"verdict":"DEAD_SUBTERM","decided_by":"enumeration","evidence":"e","snippet":"a && a"}
{"type":"decision","file_path":"src/app.src","line":10,"col":3,"form":"if","arity":2,"verdict":"DEAD_SUBTERM","decided_by":"enumeration","evidence":"e","snippet":"b && b"}
NDJSON
"$IMPACT" "$FDB" --diff HEAD~1..HEAD --repo "$REPO" --fail-on-new-findings >/dev/null 2>&1
[ $? -eq 1 ] || note "--fail-on-new-findings must exit 1: the diff touches line 6, which carries a finding"
FOUT="$("$IMPACT" "$FDB" --diff HEAD~1..HEAD --repo "$REPO" --format json 2>/dev/null)"
printf '%s' "$FOUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)["findings"]["decisions"]
assert [d["line"] for d in r]==[6], r      # line 10 is NOT in the diff and must not be reported
' 2>/dev/null || note "only the finding on a TOUCHED line may be reported (line 10 was untouched)"

# exit code 1 <-> JSON verdict "fail": a consumer with only stdout must reach the same
# conclusion as one with only the exit code
FFOUT="$("$IMPACT" "$FDB" --diff HEAD~1..HEAD --repo "$REPO" --format json --fail-on-new-findings 2>/dev/null)"
printf '%s' "$FFOUT" | strict_json_ok || note "JSON output must stay strict even when --fail-on-new-findings fires"
printf '%s' "$FFOUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"] == "fail", r["verdict"]
assert r["new_findings"] == 1, r["new_findings"]
assert r["findings"]["computed"] is True, r["findings"]
' 2>/dev/null || note "verdict must read 'fail' exactly when the exit code is 1"

# an untouched-line-only diff must pass the gate
sed -i '2s/.*/  call helper2/' "$REPO/src/app.src"
git -C "$REPO" commit -qam "change entry"
"$IMPACT" "$FDB" --diff HEAD~1..HEAD --repo "$REPO" --fail-on-new-findings >/dev/null 2>&1
[ $? -eq 0 ] || note "--fail-on-new-findings must PASS when the diff touches no finding line"
PFOUT="$("$IMPACT" "$FDB" --diff HEAD~1..HEAD --repo "$REPO" --format json --fail-on-new-findings 2>/dev/null)"
printf '%s' "$PFOUT" | python3 -c '
import json,sys
assert json.load(sys.stdin)["verdict"] == "pass"
' 2>/dev/null || note "verdict must read 'pass' exactly when the exit code is 0"

# --- 7b. exit code 3 <-> JSON verdict "refused": a gate whose input was never computed --------
# $DB carries no decision analysis at all (built in step 1, no {"type":"decision",...} records).
"$IMPACT" "$DB" --diff HEAD~1..HEAD --repo "$REPO" --fail-on-new-findings >/dev/null 2>&1
[ $? -eq 3 ] || note "--fail-on-new-findings on an index with no decision analysis must REFUSE (exit 3), never pass or fail"
RFOUT="$("$IMPACT" "$DB" --diff HEAD~1..HEAD --repo "$REPO" --format json --fail-on-new-findings 2>/dev/null)"
printf '%s' "$RFOUT" | strict_json_ok || note "JSON output must stay strict on the sound-refusal path too"
printf '%s' "$RFOUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"] == "refused", r["verdict"]
assert r["findings"]["computed"] is False, r["findings"]
' 2>/dev/null || note "verdict must read 'refused' exactly when the exit code is 3 — never confused with 'fail' (1) or a crash (2)"

# --- diff parsing: content lines are not headers, and a pure deletion is a change -----------
# Two failures the earlier parser had, in ONE fixture because they arise together. Under
# --unified=0 a removed line is written as "-" ^ content, so a deleted `-- comment` arrives as
# "--- comment" and was read as a file header — inventing a file named after the comment text,
# or a spurious deletion when that text was "/dev/null". And a pure-deletion hunk
# (`@@ -3 +1,0 @@`) adds no new line, so the loop marked nothing and the deletion site vanished
# from a file that was otherwise reported as modified.
DR="$(mktemp -d)"
git -C "$DR" init -q
git -C "$DR" config user.email t@t; git -C "$DR" config user.name t
# q.sql line 3 is `++ /dev/null`: as a REMOVED line it is written `+++ /dev/null`, which the
# earlier parser read as "this file was deleted" — and every later hunk in the file was then
# dropped, because `cur` had been cleared. Line 1 is `-- header comment`, removed as
# `--- header comment`, which it read as a file header.
cat > "$DR/q.sql" <<'EOF'
-- header comment
SELECT 1;
++ /dev/null
SELECT 2;
SELECT 3;
SELECT 4;
SELECT 5;
EOF
git -C "$DR" add -A && git -C "$DR" commit -qm init
# delete lines 1 and 3, and edit the line that ends up at new line 3 — a MIXED diff, so neither
# the deleted-file branch nor the deletion-only branch can rescue it.
printf 'SELECT 1;\nSELECT 2;\nSELECT 33;\nSELECT 4;\nSELECT 5;\n' > "$DR/q.sql"
git -C "$DR" commit -qam edit
DDB="$(mktemp --suffix=.db)"; rm -f "$DDB"
"$LOAD" "$DDB" <<'NDJSON' >/dev/null 2>&1
{"type":"function","name":"top","file_path":"q.sql","exported":true,"line_start":1,"line_end":2}
{"type":"function","name":"mid","file_path":"q.sql","line_start":3,"line_end":4}
{"type":"function","name":"bot","file_path":"q.sql","line_start":5,"line_end":7}
{"type":"call","caller_name":"top","caller_file":"q.sql","callee_name":"mid","callee_file":"q.sql","call_site":"q.sql:1","kind":"MUST"}
NDJSON
DOUT="$("$IMPACT" "$DDB" --diff HEAD~1..HEAD --repo "$DR" --format json 2>/dev/null)"
printf '%s' "$DOUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
names={f["name"] for f in r["touched"]}
# the edit lands at new line 3, inside mid — but only if the `+++ /dev/null` CONTENT line was
# not read as a header, which cleared the current file and dropped every later hunk
assert "mid" in names, ("a content line was parsed as a file header, dropping the later hunks", r)
# the two deletions straddle top; a pure-deletion hunk adds no new line to mark
assert "top" in names, ("a pure-deletion hunk marked no line, so the deletion site vanished", r)
# and no file was invented out of comment text
for ghost in ("/dev/null", "header comment"):
    assert ghost not in set(r["files_unmatched"]) and ghost not in set(r["files_file_granular"]), \
        ("a diff CONTENT line became a file: " + ghost, r)
' 2>/dev/null || note "diff parsing: content lines must not be read as headers, and a pure-deletion hunk must still mark its site"
rm -rf "$DR"; rm -f "$DDB"

rm -f "$DB" "$NOSPAN" "$HALF" "$FDB"
if [ "$fails" -eq 0 ]; then echo "selftest-impact: PASS"; else echo "selftest-impact: $fails FAILURE(S)"; exit 1; fi
