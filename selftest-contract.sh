#!/usr/bin/env bash
# selftest-contract.sh — PR-A: prove the edge-kind contract query layer on HAND-BUILT DBs (no backend).
# Asserts: reaches = MUST-only under-approx; unreachable = sound over-approx (REACHABLE/UNREACHABLE/
# UNKNOWN) on a ⊤-marked DB; and that unreachable/escapes REFUSE on a legacy (un-⊤-marked) DB.
set -u   # NOT pipefail: `grep -q` closes the pipe early on a match, SIGPIPE-ing arch-query mid-output;
         # pipefail would then mislabel a successful match as a pipeline failure (stats prints >1 table).
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$HERE/arch-query"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-contract: sqlite3 required" >&2; exit 2; }
say() { "$Q" "$@" 2>&1; }

# ---------- ⊤-marked DB ----------
# clean--MUST-->a--MAY_ENUMERATED-->b ; dirty--MUST-->t--MAY_TOP-->*TOP* ; z is isolated.
TM="$(mktemp --suffix=.db)"; rm -f "$TM"
sqlite3 "$TM" <<'SQL'
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT);
INSERT INTO functions VALUES('clean','x',1),('a','x',0),('b','x',0),('z','x',0),('dirty','x',1),('t','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES
 ('clean','x','a','x','x:1','MUST'),
 ('a','x','b','x','x:2','MAY_ENUMERATED'),
 ('dirty','x','t','x','x:3','MUST'),
 ('t','x','*TOP*',NULL,'x:4','MAY_TOP');
SQL

# reaches = MUST-only under-approx
say "$TM" reaches clean a | grep -q 'PATH EXISTS (must-reach)' || note "reaches clean a should be a MUST path"
say "$TM" reaches clean b | grep -q 'no MUST path'             || note "reaches clean b is via MAY_ENUMERATED, must NOT be a MUST path"
say "$TM" reaches clean z | grep -q 'no MUST path'             || note "reaches clean z should be no MUST path"

# unreachable = sound over-approx
say "$TM" unreachable clean b | grep -q 'REACHABLE (may-reach)' || note "unreachable clean b should be REACHABLE (b in MUST∪MAY_ENUMERATED closure)"
say "$TM" unreachable clean z | grep -q 'UNREACHABLE:'          || note "unreachable clean z should be UNREACHABLE (no path, no reachable MAY_TOP)"
say "$TM" unreachable dirty z | grep -q 'UNKNOWN:'             || note "unreachable dirty z should be UNKNOWN (dirty reaches a MAY_TOP)"
say "$TM" unreachable dirty z | grep -q 'UNREACHABLE:'         && note "unreachable dirty z must NOT be UNREACHABLE (a ⊤ is reachable)"

# escapes = the ⊤ frontier
say "$TM" escapes dirty | grep -q '\bt\b'  || note "escapes dirty should list t (the fn making the MAY_TOP edge)"
say "$TM" escapes clean | grep -q '\bt\b'  && note "escapes clean must NOT list t (t not reachable from clean)"

# stats shows the contract + kind breakdown
say "$TM" stats | grep -q 'contract: v1' || note "stats should report the contract flag"

# ---------- legacy (un-⊤-marked) DB ----------
LG="$(mktemp --suffix=.db)"; rm -f "$LG"
sqlite3 "$LG" <<'SQL'
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT);
INSERT INTO functions VALUES('p','x',1),('qq','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT);
INSERT INTO calls VALUES('p','x','qq','x','x:1');
SQL

# unreachable/escapes must REFUSE (exit 3) on a legacy DB — never give a false-sound answer.
say "$LG" unreachable p qq >/dev/null 2>&1; [ "$?" -eq 3 ] || note "unreachable on a legacy (un-⊤-marked) DB must REFUSE with exit 3"
say "$LG" escapes p        >/dev/null 2>&1; [ "$?" -eq 3 ] || note "escapes on a legacy DB must REFUSE with exit 3"
# reaches still works on a legacy DB (every edge treated as MUST).
say "$LG" reaches p qq | grep -q 'PATH EXISTS (must-reach)' || note "reaches on a legacy DB should treat edges as MUST and find the path"

# ---------- malformed ⊤-marked DB (adversarial-review regression) ----------
# Flag set, but a REAL edge has kind=NULL (a backend bug). A NULL kind is invisible to both SQL
# filters (3-valued logic), so without the integrity gate this path A->mid->sink would read as a
# false-sound UNREACHABLE. The gate must REFUSE (exit 3), and the verdict must NEVER be UNREACHABLE.
ML="$(mktemp --suffix=.db)"; rm -f "$ML"
sqlite3 "$ML" <<'SQL'
CREATE TABLE comment_db_meta(key TEXT, value TEXT); INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT); INSERT INTO functions VALUES('A','x',1),('mid','x',0),('sink','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES ('A','x','mid','x','x:1','MUST'),('mid','x','sink','x','x:2',NULL);
SQL
out=$(say "$ML" unreachable A sink); rc=$?
[ "$rc" -eq 3 ] || note "malformed ⊤-marked DB (NULL-kind edge on a real path) must REFUSE (exit 3); got rc=$rc"
printf '%s' "$out" | grep -q 'UNREACHABLE:' && note "malformed DB must NEVER yield a (false-sound) UNREACHABLE: $out"
# A DB with the flag but NO kind column must also refuse (not raw-error).
NK="$(mktemp --suffix=.db)"; rm -f "$NK"
sqlite3 "$NK" "CREATE TABLE comment_db_meta(key TEXT,value TEXT); INSERT INTO comment_db_meta VALUES('callgraph_contract','v1'); CREATE TABLE functions(name TEXT,file_path TEXT,exported INT); CREATE TABLE calls(caller_name TEXT,caller_file TEXT,callee_name TEXT,callee_file TEXT,call_site TEXT); INSERT INTO calls VALUES('A','x','b','x','x:1');"
say "$NK" unreachable A b >/dev/null 2>&1; [ "$?" -eq 3 ] || note "flag set but no kind column must REFUSE (exit 3)"

rm -f "$TM" "$LG" "$ML" "$NK"
if [ "$fails" -eq 0 ]; then echo "arch-index contract selftest: PASS"; exit 0; else echo "arch-index contract selftest: FAIL ($fails)"; exit 1; fi
