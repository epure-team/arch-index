#!/usr/bin/env bash
# selftest-load.sh — PR-B end-to-end: a Tier-0 producer's NDJSON → arch-load → ⊤-marked DB →
# arch-query sound queries. Proves the loader enforces the contract (rejects un-kinded edges) and
# that the resulting DB drives REACHABLE/UNREACHABLE/UNKNOWN correctly. No tree-sitter needed.
set -u   # not pipefail (grep -q SIGPIPEs arch-query mid-output; see selftest-contract.sh)
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; Q="$HERE/arch-query"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-load: python3 required" >&2; exit 2; }
say() { "$Q" "$@" 2>&1; }

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
# A Tier-0 producer's stream: functions + kinded call edges.
# clean--MUST-->a--MAY_ENUMERATED-->b ; dirty--MUST-->t--MAY_TOP-->*TOP* ; z isolated.
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"clean","file_path":"x","exported":true}
{"type":"function","name":"a","file_path":"x"}
{"type":"function","name":"b","file_path":"x"}
{"type":"function","name":"z","file_path":"x"}
{"type":"function","name":"dirty","file_path":"x","exported":true}
{"type":"function","name":"t","file_path":"x"}
{"type":"call","caller_name":"clean","caller_file":"x","callee_name":"a","callee_file":"x","call_site":"x:1","kind":"MUST"}
{"type":"call","caller_name":"a","caller_file":"x","callee_name":"b","callee_file":"x","call_site":"x:2","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"dirty","caller_file":"x","callee_name":"t","callee_file":"x","call_site":"x:3","kind":"MUST"}
{"type":"call","caller_name":"t","caller_file":"x","callee_name":"*TOP*","callee_file":null,"call_site":"x:4","kind":"MAY_TOP"}
NDJSON
[ -f "$DB" ] || { echo "selftest-load: loader produced no DB" >&2; exit 1; }

# the produced DB is contract-marked and queries soundly
sqlite3 "$DB" "SELECT value FROM comment_db_meta WHERE key='callgraph_contract';" | grep -q '^v1$' || note "loaded DB missing callgraph_contract flag"
say "$DB" unreachable clean z | grep -q 'UNREACHABLE:'          || note "unreachable clean z should be UNREACHABLE"
say "$DB" unreachable clean b | grep -q 'REACHABLE (may-reach)' || note "unreachable clean b should be REACHABLE"
say "$DB" unreachable dirty z | grep -q 'UNKNOWN:'             || note "unreachable dirty z should be UNKNOWN (reaches a MAY_TOP)"
say "$DB" reaches clean a | grep -q 'PATH EXISTS (must-reach)' || note "reaches clean a should be a MUST path"
say "$DB" reaches clean b | grep -q 'no MUST path'             || note "reaches clean b is MAY_ENUMERATED, not a MUST path"
say "$DB" escapes dirty   | grep -q '\bt\b'                    || note "escapes dirty should list t"

# ENFORCEMENT: an un-kinded / invalid-kind edge must ABORT the load (never silently produce a lie).
BAD="$(mktemp --suffix=.db)"; rm -f "$BAD"
printf '%s\n' '{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1"}' | "$LOAD" "$BAD" >/dev/null 2>&1
[ "$?" -eq 2 ] || note "loader must ABORT (exit 2) on a call edge with missing kind"
[ -f "$BAD" ] && note "loader must NOT produce a DB when it aborts on invalid input"
printf '%s\n' '{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"garbage"}' | "$LOAD" "$BAD" >/dev/null 2>&1
[ "$?" -eq 2 ] || note "loader must ABORT (exit 2) on an invalid kind value"

# ZERO-EDGE GUARD: a producer that fails silently emits 0 edges → trust-stamped DB where everything
# reads UNREACHABLE. arch-load must ABORT (exit 2) by default; --allow-empty overrides.
EMPTY="$(mktemp --suffix=.db)"; rm -f "$EMPTY"
printf '%s\n' '{"type":"function","name":"solo","file_path":"x"}' | "$LOAD" "$EMPTY" >/dev/null 2>&1
[ "$?" -eq 2 ] || note "loader must ABORT (exit 2) on 0 call edges (false-confidence guard)"
[ -f "$EMPTY" ] && note "loader must NOT produce a DB on 0-edge abort"
# --allow-empty lets through a genuinely call-free input
printf '%s\n' '{"type":"function","name":"solo","file_path":"x"}' | "$LOAD" --allow-empty "$EMPTY" >/dev/null 2>&1
[ "$?" -eq 0 ] || note "loader with --allow-empty must succeed on 0-edge input"
rm -f "$EMPTY"

rm -f "$DB" "$BAD"
if [ "$fails" -eq 0 ]; then echo "arch-index load selftest: PASS"; exit 0; else echo "arch-index load selftest: FAIL ($fails)"; exit 1; fi
