#!/usr/bin/env bash
# selftest-mcp.sh — end-to-end MCP stdio session checks (specs/arch-mcp-server.md).
# Covers client-compat hazards a unit test can miss: initialized notification,
# string ids, nested arguments, garbage-line recovery, stdout purity.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

FAILS=0
note() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }

command -v jq >/dev/null || { echo "selftest-mcp: jq required" >&2; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DB="$TMP/flat.db"

# Build a ⊤-marked flat DB via the NDJSON loader (same shape as selftest-load).
printf '%s\n' \
  '{"type":"function","name":"clean","file_path":"x","exported":true}' \
  '{"type":"function","name":"a","file_path":"x","exported":false}' \
  '{"type":"call","caller_name":"clean","caller_file":"x","callee_name":"a","callee_file":"x","call_site":"x:1","kind":"MUST"}' \
  '{"type":"call","caller_name":"a","caller_file":"x","callee_name":"ext","callee_file":null,"call_site":"x:2","kind":"MAY_TOP"}' \
  | ./arch-load "$DB" >/dev/null

OUT="$TMP/session.out"
# Session: initialize (string id) → initialized notification → tools/list →
# garbage line → tools/call with nested arguments → unsound-refusal call.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  'garbage line' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"arch_unreachable","arguments":{"from":"clean","to":"nowhere"}}}' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"arch_find","arguments":{"substr":"cle"}}}' \
  | ./arch-mcp --db "$DB" 2>/dev/null > "$OUT"

# stdout purity: every line must be valid JSON.
while IFS= read -r line; do
  echo "$line" | jq -e . >/dev/null 2>&1 || note "non-JSON line on stdout: $line"
done < "$OUT"

# 5 responses expected (notification produces none).
[ "$(wc -l < "$OUT")" -eq 5 ] || note "expected 5 responses, got $(wc -l < "$OUT")"

jq -s -e '.[0].id == "init-1" and .[0].result.protocolVersion == "2024-11-05"' "$OUT" >/dev/null \
  || note "initialize: bad id echo or protocolVersion"
jq -s -e '.[1].result.tools | length == 11' "$OUT" >/dev/null \
  || note "tools/list: expected 11 tools"
jq -s -e '.[2].error.code == -32700 and .[2].id == null' "$OUT" >/dev/null \
  || note "garbage line: expected -32700 with null id"
jq -s -e '.[3].result.isError == false and (.[3].result.content[0].text | fromjson | .verdict == "UNKNOWN")' "$OUT" >/dev/null \
  || note "arch_unreachable: expected UNKNOWN verdict (MAY_TOP reachable)"
jq -s -e '.[4].result.content[0].text | fromjson | .matches[0].name == "clean"' "$OUT" >/dev/null \
  || note "arch_find: expected match 'clean'"

# Refusal on a legacy (non-⊤-marked) DB.
LEG="$TMP/legacy.db"
sqlite3 "$LEG" "CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER); \
                CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT); \
                INSERT INTO functions VALUES('f','x',1);"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"arch_unreachable","arguments":{"from":"f","to":"g"}}}' \
  | ./arch-mcp --db "$LEG" 2>/dev/null \
  | jq -e '.result.isError == true and (.result.content[0].text | contains("REFUSED"))' >/dev/null \
  || note "legacy DB: expected REFUSED isError"

# Startup failures → exit 2.
./arch-mcp --db /nonexistent-db-path 2>/dev/null && note "nonexistent db: expected exit 2" || [ $? -eq 2 ] || note "nonexistent db: wrong exit code"
./arch-mcp --db "$TMP" 2>/dev/null && note "directory db: expected exit 2" || [ $? -eq 2 ] || note "directory db: wrong exit code"
echo "not sqlite" > "$TMP/junk"; ./arch-mcp --db "$TMP/junk" </dev/null 2>/dev/null && note "junk db: expected exit 2" || [ $? -eq 2 ] || note "junk db: wrong exit code"

if [ "$FAILS" -eq 0 ]; then echo "arch-index mcp selftest: OK"; else echo "arch-index mcp selftest: FAIL ($FAILS)"; exit 1; fi
