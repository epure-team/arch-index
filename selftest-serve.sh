#!/usr/bin/env bash
# selftest-serve.sh — arch-serve serves a flat-schema index over HTTP, and refuses
# a main-schema one instead of dying with an internal error.
#
# arch-serve reached "qa GO" and was then never wired up: no root wrapper, no docs
# entry, no test. What that hid is that it reads `functions.file_path`, which only
# the FLAT schema has -- pointing it at the repo's own self-index (MAIN schema)
# crashed with an uncaught Sqlite3.Error("no such column: file_path"). Both halves
# are asserted here: the shapes it does serve, and the shape it must decline.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
fails=0
note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }

command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-serve: sqlite3 required" >&2; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "selftest-serve: curl required" >&2; exit 2; }

SERVE="$HERE/arch-serve"
[ -x "$SERVE" ] || { echo "selftest-serve: arch-serve wrapper not executable" >&2; exit 2; }

TMP="$(mktemp -d)"
SRV_PID=""
cleanup() {
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  # The port must be free again for the next run; wait for the process to go.
  [ -n "$SRV_PID" ] && wait "$SRV_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

# A port nobody else is likely to hold. Fixed rather than random so a leaked
# server from a previous run surfaces as a failure here instead of silently
# answering these assertions.
PORT=7387

# ------------------------------------------------------------- flat fixture --
FLAT="$TMP/flat.db"
sqlite3 "$FLAT" <<'SQL'
CREATE TABLE comment_db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE functions (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, file_path TEXT NOT NULL,
  line_start INTEGER NOT NULL DEFAULT 0, line_end INTEGER NOT NULL DEFAULT 0,
  exported INTEGER NOT NULL DEFAULT 0, signature TEXT, summary TEXT,
  comment_quality_score INTEGER, has_pre INTEGER NOT NULL DEFAULT 0,
  has_post INTEGER NOT NULL DEFAULT 0, has_violators INTEGER NOT NULL DEFAULT 0,
  has_violates INTEGER NOT NULL DEFAULT 0, violators_raw TEXT, violates_raw TEXT,
  tests_raw TEXT, quint_raw TEXT
);
CREATE TABLE calls (
  id INTEGER PRIMARY KEY, caller_name TEXT NOT NULL, caller_file TEXT NOT NULL,
  callee_name TEXT NOT NULL, callee_file TEXT, call_site TEXT, kind TEXT
);
INSERT INTO functions (id,name,file_path,line_start,line_end,exported) VALUES
  (1,'Entry','svc/main.go',3,7,1),
  (2,'helper','svc/main.go',9,11,0);
INSERT INTO calls (caller_name,caller_file,callee_name,callee_file,call_site,kind) VALUES
  ('Entry','svc/main.go','helper','svc/main.go','svc/main.go:5','MAY_ENUMERATED');
SQL

# ------------------------------------------------------------- main fixture --
# Only the shape matters: `functions` with module_id and no file_path.
MAIN="$TMP/main.db"
sqlite3 "$MAIN" <<'SQL'
CREATE TABLE comment_db_meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE modules (id INTEGER PRIMARY KEY, name TEXT, path TEXT);
CREATE TABLE functions (
  id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, signature TEXT,
  line_start INTEGER, line_end INTEGER, exposed INTEGER
);
CREATE TABLE calls (
  id INTEGER PRIMARY KEY, caller_id INTEGER, callee_id INTEGER,
  callee_name TEXT, call_site TEXT, kind TEXT
);
INSERT INTO modules VALUES (1,'M','lib/m.ml');
INSERT INTO functions VALUES (1,1,'f',NULL,1,2,1);
SQL

# --------------------------------------------------- main schema is refused --
out="$("$SERVE" "$MAIN" --port "$PORT" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] \
  || note "main-schema index: expected exit 2, got $rc"
case "$out" in
  *"MAIN schema"*) : ;;
  *) note "main-schema refusal should name the schema, got: $out" ;;
esac
case "$out" in
  *"internal error"*|*"Sqlite3.Error"*)
    note "main-schema index still dies with an internal error: $out" ;;
  *) : ;;
esac

# ------------------------------------------------------- flat schema serves --
"$SERVE" "$FLAT" --port "$PORT" >"$TMP/serve.log" 2>&1 &
SRV_PID=$!

# Poll for readiness rather than sleeping a guessed interval.
ready=0
for _ in $(seq 1 50); do
  if curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null; then ready=1; break; fi
  # A server that died is never going to become ready.
  kill -0 "$SRV_PID" 2>/dev/null || break
  sleep 0.2
done

if [ "$ready" -ne 1 ]; then
  note "server did not answer on port $PORT: $(cat "$TMP/serve.log")"
else
  code=$(curl -sS -o "$TMP/index.html" -w '%{http_code}' "http://localhost:$PORT/")
  [ "$code" = "200" ] || note "GET / returned $code"
  [ -s "$TMP/index.html" ] || note "GET / returned an empty body"

  # The SPA is served from a compiled-in blob; an empty one would still be 200.
  grep -qi "<html\|<!doctype" "$TMP/index.html" \
    || note "GET / did not return HTML"

  fns=$(curl -sS "http://localhost:$PORT/api/functions")
  case "$fns" in
    *'"name":"Entry"'*) : ;;
    *) note "/api/functions did not list Entry: $(printf '%s' "$fns" | head -c 200)" ;;
  esac
  case "$fns" in
    *'"name":"helper"'*) : ;;
    *) note "/api/functions did not list helper: $(printf '%s' "$fns" | head -c 200)" ;;
  esac

  mods=$(curl -sS "http://localhost:$PORT/api/modules")
  case "$mods" in
    *svc*) : ;;
    *) note "/api/modules did not derive a module from svc/main.go: $(printf '%s' "$mods" | head -c 200)" ;;
  esac

  # A route that does not exist must not be a 200 with a plausible body.
  code=$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:$PORT/api/nope")
  [ "$code" = "404" ] || note "unknown route returned $code, expected 404"
fi

if [ "$fails" -eq 0 ]; then
  echo "selftest-serve: PASS"
else
  echo "selftest-serve: FAIL ($fails)" >&2
  exit 1
fi
