#!/usr/bin/env bash
# selftest-coverage.sh — reachability-weighted coverage (§4).
#
# Almost every check here is about a distinction that a naive coverage tool collapses, and that
# collapsing is precisely how coverage numbers become untrustworthy:
#
#   1. "no instrumentation data" is NOT "0% covered"
#   2. covered-but-only-⊤-reachable is flagged, not counted as API-exercised
#   3. covered AND mutants survive = tests that check nothing (the pairing, not a percentage)
#   4. an empty tracefile ABORTS rather than reporting 0%
#   5. merged/duplicated LCOV records SUM rather than overwrite
#   6. the `coverage` table actually gets written
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; COV="$HERE/arch-coverage"; MUT="$HERE/arch-mutants"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-coverage: python3 required" >&2; exit 2; }

# api (exported) --MUST--> hot, cold ; api --MAY_TOP--> ⊤ ... and `hidden` is only in the ⊤ cone
DB="$(mktemp --suffix=.db)"; rm -f "$DB"
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"api","file_path":"lib/api.ml","exported":true,"line_start":1,"line_end":8}
{"type":"function","name":"hot","file_path":"lib/hot.ml","line_start":10,"line_end":20}
{"type":"function","name":"cold","file_path":"lib/cold.ml","line_start":10,"line_end":20}
{"type":"function","name":"nodata","file_path":"lib/nodata.ml","line_start":10,"line_end":20}
{"type":"function","name":"dyn","file_path":"lib/dyn.ml","line_start":1,"line_end":5}
{"type":"function","name":"hidden","file_path":"lib/hidden.ml","line_start":1,"line_end":5}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"hot","callee_file":"lib/hot.ml","call_site":"lib/api.ml:2","kind":"MUST"}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"cold","callee_file":"lib/cold.ml","call_site":"lib/api.ml:3","kind":"MUST"}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"nodata","callee_file":"lib/nodata.ml","call_site":"lib/api.ml:4","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/dyn.ml","callee_name":"hidden","callee_file":"lib/hidden.ml","call_site":"lib/dyn.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/dyn.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/dyn.ml:3","kind":"MAY_TOP"}
NDJSON
[ -f "$DB" ] || { echo "selftest-coverage: loader produced no DB" >&2; exit 1; }

LC="$(mktemp)"
cat > "$LC" <<'EOF'
SF:lib/api.ml
DA:2,5
end_of_record
SF:lib/hot.ml
DA:11,7
DA:12,7
end_of_record
SF:lib/cold.ml
DA:11,0
DA:12,0
end_of_record
SF:lib/hidden.ml
DA:2,3
end_of_record
EOF
# lib/nodata.ml is deliberately absent from the tracefile.

OUT="$("$COV" "$DB" "$LC" --format json 2>/dev/null)"

# --- 1. no data != 0% -----------------------------------------------------------------------
printf '%s' "$OUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["api_never_exercised"]==["cold"], r["api_never_exercised"]
# nodata has NO DA record: it must be "not instrumented", never counted as never-exercised
assert r["api_no_coverage_data"]==["nodata"], r["api_no_coverage_data"]
assert "lib/nodata.ml" in r["files_in_index_not_instrumented"], r["files_in_index_not_instrumented"]
' 2>/dev/null || note "a function with no DA record must be 'no data', never 'never exercised'"

# --- 2. covered but only ⊤-reachable --------------------------------------------------------
printf '%s' "$OUT" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["covered_via_top_only"]==["hidden"], r["covered_via_top_only"]
' 2>/dev/null || note "a covered function reachable only through a ⊤ edge must be flagged apart"

# --- 4. an empty tracefile ABORTS -----------------------------------------------------------
EMPTY="$(mktemp)"; : > "$EMPTY"
"$COV" "$DB" "$EMPTY" >/dev/null 2>&1
[ $? -eq 2 ] || note "an LCOV file with no SF records must abort — 0% and 'never ran' are not the same"
BADDA="$(mktemp)"; printf 'DA:3,1\n' > "$BADDA"
"$COV" "$DB" "$BADDA" >/dev/null 2>&1
[ $? -eq 2 ] || note "a DA record before any SF must abort as malformed"
BADN="$(mktemp)"; printf 'SF:lib/hot.ml\nDA:11,x\nend_of_record\n' > "$BADN"
"$COV" "$DB" "$BADN" >/dev/null 2>&1
[ $? -eq 2 ] || note "a non-integer DA hit count must abort, not be silently read as zero"
BADNEG="$(mktemp)"; printf 'SF:lib/hot.ml\nDA:11,-3\nend_of_record\n' > "$BADNEG"
"$COV" "$DB" "$BADNEG" >/dev/null 2>&1
[ $? -eq 2 ] || note "a negative DA hit count must abort — summed across records it can cancel a real hit"
# A DA record AFTER end_of_record belongs to no file. Crediting it to the previous one invents
# coverage: here it would mark lib/hot.ml:11 as hit and hide that `hot` was never exercised.
AFTEREOR="$(mktemp)"; printf 'SF:lib/hot.ml\nDA:12,1\nend_of_record\nDA:11,9\n' > "$AFTEREOR"
"$COV" "$DB" "$AFTEREOR" >/dev/null 2>&1
[ $? -eq 2 ] || note "a DA record after end_of_record must abort, not be credited to the previous file"

# --- 5. duplicated records SUM ---------------------------------------------------------------
# A merged/sharded run emits the same file twice. Overwriting would discard a shard's hits, so a
# line hit only in the SECOND record must still read as covered.
DUP="$(mktemp)"
cat > "$DUP" <<'EOF'
SF:lib/cold.ml
DA:11,0
DA:12,0
end_of_record
SF:lib/cold.ml
DA:11,4
DA:12,0
end_of_record
EOF
"$COV" "$DB" "$DUP" --format json 2>/dev/null | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert "cold" not in r["api_never_exercised"], ("second record hits were discarded", r)
' 2>/dev/null || note "duplicate SF records must SUM hit counts, not overwrite"

# --- an empty --roots selector must ABORT ---------------------------------------------------
"$COV" "$DB" "$LC" --roots 'file:nope/**' >/dev/null 2>&1
[ $? -eq 2 ] || note "--roots matching nothing must abort, not report against an empty API cone"

# ...and so must the DEFAULT roots on an index that marks no exports. This is the same failure
# wearing different clothes: every list comes back empty for want of a starting point, and an
# empty report is read as a clean one.
NOEXP="$(mktemp --suffix=.db)"; rm -f "$NOEXP"
"$LOAD" "$NOEXP" <<'NDJSON' 2>/dev/null
{"type":"function","name":"internal","file_path":"lib/hot.ml","line_start":10,"line_end":20}
NDJSON
"$COV" "$NOEXP" "$LC" >/dev/null 2>&1
[ $? -eq 2 ] || note "--roots exported on an index with zero exports must abort, not report an empty (hence clean-looking) cone"

# --- every covered function lands in SOME bucket ---------------------------------------------
# `orphan` is covered, is not in the API cone, and is not in the ⊤ cone either. Before the
# 'outside the API cone' bucket existed it appeared in no list at all and simply vanished — the
# report looked complete while dropping a function the tests demonstrably execute.
ORPH="$(mktemp --suffix=.db)"; rm -f "$ORPH"
"$LOAD" "$ORPH" <<'NDJSON' 2>/dev/null
{"type":"function","name":"api","file_path":"lib/api.ml","exported":true,"line_start":1,"line_end":8}
{"type":"function","name":"orphan","file_path":"lib/hot.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"api","callee_file":"lib/api.ml","call_site":"lib/api.ml:2","kind":"MUST"}
NDJSON
"$COV" "$ORPH" "$LC" --format json 2>/dev/null | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["covered_outside_api_cone"]==["orphan"], r
buckets = set(r["api_never_exercised"]) | set(r["api_no_coverage_data"]) \
        | set(r["covered_via_top_only"]) | set(r["covered_outside_api_cone"])
assert "orphan" in buckets, ("a covered function appears in no bucket at all", r)
' 2>/dev/null || note "a covered function outside the API and ⊤ cones must still be reported, not silently dropped"

# --- the mutant ambiguity guard counts over the WHOLE index ----------------------------------
# `dup` exists twice; only one copy has coverage data. Counting duplicates among INSTRUMENTED
# functions sees one, stays silent, and blames the surviving mutant on whichever copy happens to
# be instrumented — which may be the other one.
# Built on the MAIN schema, not through arch-load: the flat schema keys functions by name, so
# it cannot represent two functions sharing one — which is the situation under test.
AMB="$(mktemp --suffix=.db)"; rm -f "$AMB"
sqlite3 "$AMB" < "$HERE/architecture-schema.sql" 2>/dev/null
sqlite3 "$AMB" <<'SQL' 2>/dev/null
INSERT INTO modules(id,path) VALUES (1,'lib/api.ml'),(2,'lib/hot.ml'),(3,'lib/nodata.ml');
INSERT INTO functions(id,module_id,name,line_start,line_end,exposed)
  VALUES (1,1,'api',1,8,1),(2,2,'dup',10,20,0),(3,3,'dup',10,20,0);
INSERT INTO calls(caller_id,callee_id,callee_name,call_site,kind)
  VALUES (1,2,'dup','lib/api.ml:2','MUST'),(1,3,'dup','lib/api.ml:3','MUST');
INSERT INTO comment_db_meta(key,value) VALUES ('callgraph_contract','v1');
SQL
AMBR="$(mktemp)"; printf '%s\n' '{"file":"lib/hot.ml","line":11,"status":"SURVIVED","id":"1"}' > "$AMBR"
AMBJ="$(mktemp)"
"$MUT" report "$AMB" "$AMBR" --tests 'fn:api' --format json > "$AMBJ" 2>/dev/null
"$COV" "$AMB" "$LC" --mutants "$AMBJ" --format json 2>/dev/null | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert "dup" in r["mutants_ambiguous_names"], ("ambiguity went unreported", r)
assert [d["function"] for d in r["covered_but_mutants_survive"]]==[], ("mutant was attributed to one of two same-named functions", r)
' 2>/dev/null || note "a name shared with a NON-instrumented function must still count as ambiguous"

# --- 3. the coverage x mutants pairing -------------------------------------------------------
MR="$(mktemp)"; printf '%s\n' '{"file":"lib/hot.ml","line":11,"status":"SURVIVED","id":"1"}' > "$MR"
MJ="$(mktemp)"
"$MUT" report "$DB" "$MR" --tests 'fn:api' --format json > "$MJ" 2>/dev/null
"$COV" "$DB" "$LC" --mutants "$MJ" --format json 2>/dev/null | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["mutants_available"] is True, r
got=[(d["function"], d["survivors"]) for d in r["covered_but_mutants_survive"]]
assert got==[("hot",1)], got
' 2>/dev/null || note "a covered function with a surviving mutant must be reported as tested-by-nothing"
# without --mutants it must say NOT COMPUTED, never "none"
"$COV" "$DB" "$LC" 2>/dev/null | grep -q 'not computed' \
  || note "without --mutants the pairing must read 'not computed', never 'none'"
# a file that is not an arch-mutants report must abort rather than yield an empty pairing
NOTAREPORT="$(mktemp)"; printf '[]\n' > "$NOTAREPORT"
"$COV" "$DB" "$LC" --mutants "$NOTAREPORT" >/dev/null 2>&1
[ $? -eq 2 ] || note "a --mutants file that is not an arch-mutants report must abort"

# --- 6. --write populates the table ----------------------------------------------------------
"$COV" "$DB" "$LC" --write >/dev/null 2>&1
n=$(sqlite3 "$DB" "SELECT count(*) FROM coverage_by_name;" 2>/dev/null)
[ "${n:-0}" -ge 3 ] || note "--write must populate the coverage table (got ${n:-0} rows)"
sqlite3 "$DB" "SELECT covered_lines||'/'||total_lines FROM coverage_by_name WHERE function_name='hot';" \
  | grep -q '^2/2$' || note "hot has 2 instrumented lines, both hit — expected 2/2"
sqlite3 "$DB" "SELECT covered_lines||'/'||total_lines FROM coverage_by_name WHERE function_name='cold';" \
  | grep -q '^0/2$' || note "cold has 2 instrumented lines, neither hit — expected 0/2"
# rerunning must not accumulate duplicate rows
"$COV" "$DB" "$LC" --write >/dev/null 2>&1
n2=$(sqlite3 "$DB" "SELECT count(*) FROM coverage_by_name;" 2>/dev/null)
[ "$n2" = "$n" ] || note "--write must replace, not accumulate ($n then $n2 rows)"

# --- 7. contract_ok is the STRICT check (round-2 review, F6): same malformed-⊤-marked fixture
# as selftest-contract.sh's "ML" case, selftest-impact.sh's 4d, selftest-rules.sh's — the flag is
# set, `kind` exists, but a REAL edge has kind=NULL. arch-coverage must agree with
# arch-impact/arch-rules that this index is NOT sound, from the same Arch_db.contract_ok helper.
ML="$(mktemp --suffix=.db)"; rm -f "$ML"
sqlite3 "$ML" <<'SQL'
CREATE TABLE comment_db_meta(key TEXT, value TEXT); INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT, line_start INT, line_end INT); INSERT INTO functions VALUES('A','x',1,NULL,NULL),('mid','x',0,NULL,NULL),('sink','x',0,NULL,NULL);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES ('A','x','mid','x','x:1','MUST'),('mid','x','sink','x','x:2',NULL);
SQL
MLC="$(mktemp)"
cat > "$MLC" <<'EOF'
SF:x
DA:1,1
end_of_record
EOF
MLOUT="$("$COV" "$ML" "$MLC" --format json 2>/dev/null)"
printf '%s' "$MLOUT" | python3 -c '
import json,sys
assert json.load(sys.stdin)["sound_reachability"] is False
' 2>/dev/null || note "arch-coverage: a NULL-kind edge on a flag-stamped index must report sound_reachability:false"
rm -f "$ML" "$MLC"

rm -f "$DB" "$LC" "$EMPTY" "$BADDA" "$BADN" "$BADNEG" "$AFTEREOR" "$DUP" "$MR" "$MJ" "$NOTAREPORT" "$NOEXP" "$ORPH" "$AMB" "$AMBR" "$AMBJ"
if [ "$fails" -eq 0 ]; then echo "selftest-coverage: PASS"; else echo "selftest-coverage: $fails FAILURE(S)"; exit 1; fi
