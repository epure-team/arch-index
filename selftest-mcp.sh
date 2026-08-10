#!/usr/bin/env bash
# selftest-mcp.sh — the MCP server (§5), driven over stdio with real JSON-RPC.
#
# The property this exists to protect is NOT "the protocol works" — mcp-kit tests that. It is
# that the server does not become a SECOND source of truth:
#
#   1. every tool result carries provenance, so an agent can weigh the verdict
#   2. `reachability`'s verdict MATCHES what `arch-query unreachable` says on the same input —
#      if these ever diverge, the agent gets an answer no human has checked
#   3. an UNKNOWN is reported as UNKNOWN, never rounded to a negative
#   4. a non-zero exit that is a VERDICT (arch-query's REFUSE) is not reported as a crash
#   5. the server refuses to start on a missing db rather than erroring per-call
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/_build/default/bin/arch_mcp/arch_mcp.exe"
LOAD="$HERE/arch-load"; Q="$HERE/arch-query"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-mcp: python3 required" >&2; exit 2; }
if [ ! -x "$BIN" ]; then
  echo "selftest-mcp: SKIP — $BIN not built (build it with: ARCH_MCP=yes dune build bin/arch_mcp, after pinning mcp-kit)"
  exit 0
fi

# clean --MUST--> a --MAY_ENUMERATED--> b ; dirty --MUST--> t --MAY_TOP--> ⊤ ; z isolated
DB="$(mktemp --suffix=.db)"; rm -f "$DB"
"$LOAD" "$DB" <<'NDJSON' 2>/dev/null
{"type":"function","name":"clean","file_path":"x","exported":true}
{"type":"function","name":"a","file_path":"x"}
{"type":"function","name":"b","file_path":"x"}
{"type":"function","name":"z","file_path":"x"}
{"type":"function","name":"mark_UNREACHABLE","file_path":"x"}
{"type":"function","name":"dirty","file_path":"x","exported":true}
{"type":"function","name":"t","file_path":"x"}
{"type":"call","caller_name":"clean","caller_file":"x","callee_name":"a","callee_file":"x","call_site":"x:1","kind":"MUST"}
{"type":"call","caller_name":"a","caller_file":"x","callee_name":"b","callee_file":"x","call_site":"x:2","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"clean","caller_file":"x","callee_name":"mark_UNREACHABLE","callee_file":"x","call_site":"x:5","kind":"MUST"}
{"type":"call","caller_name":"dirty","caller_file":"x","callee_name":"t","callee_file":"x","call_site":"x:3","kind":"MUST"}
{"type":"call","caller_name":"t","caller_file":"x","callee_name":"*TOP*","callee_file":null,"call_site":"x:4","kind":"MAY_TOP"}
NDJSON
[ -f "$DB" ] || { echo "selftest-mcp: loader produced no DB" >&2; exit 1; }

# One MCP session per invocation: initialize, notifications/initialized, then the request.
# mcp-kit sessions reject normal requests before the handshake, so the handshake is not
# optional scaffolding — it is part of what is being tested.
call_cfg() {  # $1 = db, $2 = repo, $3 = method, $4 = params JSON
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '{"jsonrpc":"2.0","id":2,"method":"%s","params":%s}\n' "$3" "$4"
  } | "$BIN" --db "$1" --repo "$2" --tools-dir "$HERE" 2>/dev/null
}
call() { call_cfg "$DB" "$HERE" "$1" "$2"; }

pick() {  # last JSON-RPC response on stdin -> .result
  python3 -c '
import json,sys
last=None
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: obj=json.loads(line)
    except Exception: continue
    if obj.get("id")==2: last=obj
print(json.dumps(last["result"]) if last and "result" in last else "")
'
}

# --- tools/list advertises the surface ------------------------------------------------------
LIST="$(call tools/list '{}' | pick)"
printf '%s' "$LIST" | python3 -c '
import json,sys
names={t["name"] for t in json.load(sys.stdin)["tools"]}
want={"reachability","escapes","callers_of","callees_of","useless_branches","dead_blocks",
      "mutation_density","change_impact","architecture_rules","mutation_plan","index_status"}
assert want <= names, sorted(want-names)
' 2>/dev/null || note "tools/list must advertise every documented tool"

# --- 1./2. reachability agrees with arch-query, and carries provenance ----------------------
sc() {  # structured content of a tools/call result
  python3 -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read())["structuredContent"]))'
}
R="$(call tools/call '{"name":"reachability","arguments":{"from":"clean","to":"z"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"]=="UNREACHABLE", r
p=r["provenance"]
assert p["callgraph_contract"]=="v1", p
assert p["reachability_is_sound"] is True, p
' 2>/dev/null || note "clean->z must be UNREACHABLE with sound provenance"
"$Q" "$DB" unreachable clean z 2>/dev/null | grep -q 'UNREACHABLE' \
  || note "arch-query and the MCP server must agree: clean->z is UNREACHABLE"

R="$(call tools/call '{"name":"reachability","arguments":{"from":"clean","to":"b"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"]=="REACHABLE", r
# b is MAY_ENUMERATED-reachable, so the MUST-only answer must NOT claim a definite path —
# an agent acting on "reachable" needs to know which of the two it has.
assert "no MUST path" in r["must_path"], r["must_path"]
' 2>/dev/null || note "clean->b is may-reach, and the MUST-only answer must say so separately"

# --- 3. UNKNOWN stays UNKNOWN ---------------------------------------------------------------
R="$(call tools/call '{"name":"reachability","arguments":{"from":"dirty","to":"z"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"]=="UNKNOWN", ("a ⊤-escaping cone must not be rounded to a negative", r)
' 2>/dev/null || note "dirty->z must be UNKNOWN (the cone escapes), never UNREACHABLE"
E="$(call tools/call '{"name":"escapes","arguments":{"from":"dirty"}}' | pick | sc)"
printf '%s' "$E" | grep -q '\bt\b' || note "escapes must name the function holding the ⊤ edge"

# --- 4. a REFUSE exit code is a verdict, not a crash ----------------------------------------
# An unknown source makes arch-query exit 3 rather than answer. That must surface as REFUSED
# with the reason, not as a broken tool.
R="$(call tools/call '{"name":"reachability","arguments":{"from":"no_such_fn","to":"z"}}' | pick)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r.get("isError") in (False,None), ("a refusal is a verdict, not a protocol error", r)
v=r["structuredContent"]["verdict"]
assert v in ("REFUSED","UNREACHABLE"), v
' 2>/dev/null || note "an arch-query refusal must be reported as a verdict, not an error"

# --- provenance is on EVERY tool, not just reachability -------------------------------------
for t in index_status useless_branches dead_blocks; do
  R="$(call tools/call "{\"name\":\"$t\",\"arguments\":{}}" | pick | sc)"
  printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert "provenance" in r and "reachability_is_sound" in r["provenance"], r
' 2>/dev/null || note "$t must carry provenance so its answer can be weighed"
done

# --- provenance validates the complete callgraph contract, not just a stamp ----------------
for shape in unstamped missing_kind null_kind invalid_kind; do
  BADDB="$(mktemp --suffix=.db)"; cp "$DB" "$BADDB"
  case "$shape" in
    unstamped) sqlite3 "$BADDB" "DELETE FROM comment_db_meta WHERE key='callgraph_contract'" ;;
    missing_kind) sqlite3 "$BADDB" "ALTER TABLE calls DROP COLUMN kind" ;;
    null_kind) sqlite3 "$BADDB" "UPDATE calls SET kind=NULL WHERE rowid=(SELECT min(rowid) FROM calls)" ;;
    invalid_kind) sqlite3 "$BADDB" "UPDATE calls SET kind='BOGUS' WHERE rowid=(SELECT min(rowid) FROM calls)" ;;
  esac
  R="$(call_cfg "$BADDB" "$HERE" tools/call '{"name":"index_status","arguments":{}}' | pick | sc)"
  printf '%s' "$R" | python3 -c '
import json,sys
p=json.load(sys.stdin)["provenance"]
assert p["reachability_is_sound"] is False, p
assert "NOT" in p["caveat"], p
' 2>/dev/null || note "$shape callgraph evidence must produce unsound MCP provenance"
  "$Q" "$BADDB" unreachable clean z >/dev/null 2>&1
  [ $? -eq 3 ] || note "$shape fixture must be refused by the CLI contract validator too"
  rm -f "$BADDB"
done

# --- the payload is machine-shaped, not table art --------------------------------------------
# arch-query defaults to sqlite3 -box. Sending an agent a one-line verdict wrapped in ~400
# box-drawing characters spends its context on borders, so the server asks for the plain form.
R="$(call tools/call '{"name":"reachability","arguments":{"from":"clean","to":"z"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
for k in ("detail","must_path"):
    assert "\u2500" not in r[k] and "\u2502" not in r[k], (k, r[k][:80])
assert r["detail"].startswith("UNREACHABLE"), r["detail"]
' 2>/dev/null || note "tool payloads must be plain text, never sqlite3 -box table art"

# --- a pre-existing ARCH_QUERY_FORMAT must not win -------------------------------------------
# The server used to APPEND ARCH_QUERY_FORMAT=list to the inherited environment. With a duplicate
# name, glibc's getenv returns the FIRST match, so an operator's ARCH_QUERY_FORMAT=box stayed in
# charge and the agent received the table art the append existed to prevent.
R="$(ARCH_QUERY_FORMAT=box call tools/call '{"name":"reachability","arguments":{"from":"clean","to":"z"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
for k in ("detail","must_path"):
    assert "─" not in r[k] and "│" not in r[k], (k, r[k][:80])
' 2>/dev/null || note "an inherited ARCH_QUERY_FORMAT must be overridden, not merely appended to"

# --- a path argument is CHECKED, never rewritten ---------------------------------------------
# architecture_rules used to do concat(repo, basename(p)): "docs/arch-rules.txt" silently became
# "<repo>/arch-rules.txt" and the verdicts of a DIFFERENT file were returned as the answer.
for badpath in ../etc/passwd /etc/passwd nested/deep/nope.txt; do
  R="$(call tools/call "{\"name\":\"architecture_rules\",\"arguments\":{\"rules_file\":\"$badpath\"}}" | pick)"
  printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r.get("isError") is True, ("the path was accepted instead of refused", r)
' 2>/dev/null || note "architecture_rules must REFUSE $badpath, not silently evaluate another file"
done

# Canonical containment also rejects file and directory symlink escapes and a
# similarly prefixed sibling root without exposing the external file contents.
PATH_ROOT="$(mktemp -d)"; PATH_SIBLING="${PATH_ROOT}-sibling"; mkdir -p "$PATH_SIBLING"
cp "$HERE/arch-rules.txt" "$PATH_ROOT/valid-rules.txt"
printf 'EXTERNAL_SECRET_SENTINEL\n' > "$PATH_SIBLING/external-rules.txt"
ln -s "$PATH_SIBLING/external-rules.txt" "$PATH_ROOT/file-link.txt"
ln -s "$PATH_SIBLING" "$PATH_ROOT/dir-link"
for badpath in file-link.txt dir-link/external-rules.txt "../$(basename "$PATH_SIBLING")/external-rules.txt"; do
  R="$(call_cfg "$DB" "$PATH_ROOT" tools/call "{\"name\":\"architecture_rules\",\"arguments\":{\"rules_file\":\"$badpath\"}}" | pick)"
  printf '%s' "$R" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r.get("isError") is True, r
assert "EXTERNAL_SECRET_SENTINEL" not in json.dumps(r), r
' 2>/dev/null || note "canonical repo containment must refuse $badpath without leaking content"
done
R="$(call_cfg "$DB" "$PATH_ROOT" tools/call '{"name":"architecture_rules","arguments":{"rules_file":"valid-rules.txt"}}' | pick)"
printf '%s' "$R" | python3 -c 'import json,sys; assert json.load(sys.stdin).get("isError") in (False,None)' \
  2>/dev/null || note "canonical repo containment must accept a nested in-root regular file"
rm -rf "$PATH_ROOT" "$PATH_SIBLING"
# ...and a legitimate repo-relative path still works, so the guard is a check and not a ban.
R="$(call tools/call '{"name":"architecture_rules","arguments":{"rules_file":"arch-rules.txt"}}' | pick)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r.get("isError") in (False,None), r
assert "results" in r["structuredContent"]["output"], r
' 2>/dev/null || note "a valid repo-relative rules file must still be evaluated"

# --- the verdict is read from the LINE, not scanned for anywhere in the output ---------------
# The verdict line embeds both function names, so a substring scan for "UNREACHABLE" inverted
# the answer for any question about a function whose own name contains it. `mark_UNREACHABLE` is
# genuinely REACHABLE from clean; reporting it as UNREACHABLE is the most dangerous way this
# server can be wrong, because UNREACHABLE is the verdict an agent is told to trust as a proof.
R="$(call tools/call '{"name":"reachability","arguments":{"from":"clean","to":"mark_UNREACHABLE"}}' | pick | sc)"
printf '%s' "$R" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["verdict"]=="REACHABLE", ("the callee name was scanned as if it were the verdict", r)
' 2>/dev/null || note "the verdict must come from the leading word of the answer, not a substring scan"

# --- a non-executable tool is a tool error, not a dead session -------------------------------
# Sys.file_exists is not evidence the file can be EXECUTED. An uncaught Unix_error from
# create_process escaped the handler and took the transport down, so the agent saw the session
# die instead of an error it could report.
BADTOOLS="$(mktemp -d)"; : > "$BADTOOLS/arch-query"; chmod 000 "$BADTOOLS/arch-query"
BR="$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reachability","arguments":{"from":"clean","to":"z"}}}'
  } | "$BIN" --db "$DB" --repo "$HERE" --tools-dir "$BADTOOLS" 2>/dev/null | pick
)"
printf '%s' "$BR" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r.get("isError") is True, ("a non-executable tool must be a tool error", r)
body = " ".join(c.get("text","") for c in r.get("content",[]))
assert "cannot execute" in body, ("the failure must be reported as an exec failure, with the path", r)
' 2>/dev/null || note "a non-executable tool must surface as a named exec failure, not kill the session"
rm -rf "$BADTOOLS"

# --- a tool writing a lot to stderr must not deadlock ----------------------------------------
# Draining stdout to EOF and only then stderr wedges as soon as the child fills the 64 KiB
# stderr pipe buffer: the child blocks writing, the parent blocks reading, forever. A hung
# session with no diagnostic is the worst failure an agent can be handed.
NOISY="$(mktemp -d)"
cat > "$NOISY/arch-query" <<'SH'
#!/usr/bin/env bash
# 512 KiB on stderr — eight times the pipe buffer — then a normal verdict on stdout.
head -c 524288 /dev/zero | tr '\0' 'x' >&2
echo "UNREACHABLE: synthetic"
SH
chmod +x "$NOISY/arch-query"
NR="$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reachability","arguments":{"from":"clean","to":"z"}}}'
  } | timeout 60 "$BIN" --db "$DB" --repo "$HERE" --tools-dir "$NOISY" 2>/dev/null | pick
)"
[ -n "$NR" ] || note "a tool writing 512 KiB to stderr must not deadlock the server"
printf '%s' "$NR" | python3 -c '
import json,sys; r=json.load(sys.stdin)
assert r["structuredContent"]["verdict"]=="UNREACHABLE", r
' 2>/dev/null || note "stdout must still be read in full when stderr is large"
rm -rf "$NOISY"

# --- a child that closes its pipes and never exits must not wedge the server -----------------
# The drain deadline covers the PIPES. A tool that closes stdout and stderr and then keeps
# running leaves both at EOF while waitpid blocks forever — the same hung session, reached the
# other way. The reap is bounded and kills what outlives it.
WEDGE="$(mktemp -d)"
cat > "$WEDGE/arch-query" <<'SH'
#!/usr/bin/env bash
echo "UNREACHABLE: synthetic"
exec >&- 2>&-      # close both pipes, then outlive the server's patience
sleep 600
SH
chmod +x "$WEDGE/arch-query"
WSTART=$(date +%s)
WR="$(
  {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"selftest","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reachability","arguments":{"from":"clean","to":"z"}}}'
  } | timeout 120 "$BIN" --db "$DB" --repo "$HERE" --tools-dir "$WEDGE" 2>/dev/null | pick
)"
WELAPSED=$(( $(date +%s) - WSTART ))
[ -n "$WR" ] || note "a tool that closes its pipes and never exits must not block the server on waitpid"
[ "$WELAPSED" -lt 60 ] || note "the reap must be bounded (took ${WELAPSED}s)"
rm -rf "$WEDGE"

# --- the contract resource is readable -------------------------------------------------------
RR="$(call resources/read '{"uri":"arch-index://contract"}' | pick)"
printf '%s' "$RR" | grep -q 'MAY_TOP' \
  || note "the arch-index://contract resource must explain the edge kinds"

# --- 5. refuse to start on a missing db ------------------------------------------------------
"$BIN" --db /nonexistent/x.db </dev/null >/dev/null 2>&1
[ $? -eq 2 ] || note "the server must refuse to start on a missing db, not fail per-call"
"$BIN" </dev/null >/dev/null 2>&1
[ $? -eq 2 ] || note "the server must require --db"

rm -f "$DB"
if [ "$fails" -eq 0 ]; then echo "selftest-mcp: PASS"; else echo "selftest-mcp: $fails FAILURE(S)"; exit 1; fi
