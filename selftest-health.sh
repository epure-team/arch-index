#!/usr/bin/env bash
# selftest-health.sh — e2e checks for the code-health query pack
# (specs/arch-health-queries.md). Builds a REAL main-schema fixture from
# architecture-schema.sql (existing selftests only cover the flat schema).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

FAILS=0
note() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MAIN="$TMP/main.db"; FLAT="$TMP/flat.db"

# main-schema fixture from the canonical DDL + enriched rows
sqlite3 "$MAIN" < architecture-schema.sql
sqlite3 "$MAIN" "
INSERT INTO modules(id,path,lines,has_mli) VALUES
  (1,'src/big.ml',600,1),(2,'src/small.ml',80,0),(3,'src/other.ml',90,NULL);
INSERT INTO functions(id,module_id,name,signature,line_start,line_end,exposed,intent) VALUES
  (1,1,'huge_fn','int -> int',1,100,1,'does things'),
  (2,1,'tiny_fn','int -> int',101,102,1,NULL),
  (3,2,'helper','string -> string',1,10,0,''),
  (4,1,'dup_sig','unit -> unit',110,112,1,'x'),
  (5,2,'dup_sig','unit -> unit',20,22,1,'y');
INSERT INTO types(id,module_id,name,kind,exposed) VALUES
  (1,1,'config','record',1),(2,2,'settings','record',1),(3,3,'prefs','record',1);
INSERT INTO type_fields(type_id,field_name,field_type,position) VALUES
  (1,'instance_name','string',0),(2,'instance_name','string',0),(3,'instance_name','string',0),
  (1,'port','int',1),(2,'pct_100%','string',1);
"

# flat fixture for refusal cases
printf '%s\n' '{"type":"function","name":"f","file_path":"x","exported":true}' \
  '{"type":"call","caller_name":"f","caller_file":"x","callee_name":"g","callee_file":null,"call_site":"x:1","kind":"MAY_TOP"}' \
  | ./arch-load "$FLAT" >/dev/null

# ── US-1 health commands on main schema ─────────────────────────────────────
./arch-query "$MAIN" large-files 500 | grep -q 'src/big.ml' || note "large-files: expected src/big.ml"
./arch-query "$MAIN" large-functions 50 | grep -q 'huge_fn' || note "large-functions: expected huge_fn"
./arch-query "$MAIN" god-modules 2 | grep -q 'src/big.ml' || note "god-modules: expected src/big.ml (3 fns)"
./arch-query "$MAIN" missing-docs | grep -q 'tiny_fn' || note "missing-docs: expected tiny_fn (NULL intent)"
if ./arch-query "$MAIN" missing-docs | grep -q 'helper'; then note "missing-docs: helper is not exposed, must not appear"; fi
./arch-query "$MAIN" missing-mli | grep -q 'src/small.ml' || note "missing-mli: expected src/small.ml"
./arch-query "$MAIN" missing-mli | grep -q 'src/other.ml' || note "missing-mli: NULL has_mli must count as missing"
./arch-query "$MAIN" unsafe-strings 3 | grep -q 'instance_name' || note "unsafe-strings: expected instance_name (3x)"
if ./arch-query "$MAIN" unsafe-strings 4 | grep -q 'instance_name'; then note "unsafe-strings 4: instance_name must be below threshold"; fi

# thresholds: validation + empty-result exit 0
rc=0; ./arch-query "$MAIN" god-modules abc >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "god-modules abc: expected exit 2"
./arch-query "$MAIN" large-files 100000 >/dev/null || note "empty result must exit 0"

# refusals on flat schema (column-level detection)
for c in "large-files" "large-functions" "missing-docs" "missing-mli" "unsafe-strings 3" "duplicates" "type-search x"; do
  rc=0; ./arch-query "$FLAT" $c >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 3 ] || note "flat $c: expected exit 3"
done
# god-modules on flat falls back to file_path grouping (has file_path)
./arch-query "$FLAT" god-modules 0 >/dev/null 2>&1 || note "flat god-modules: file_path fallback should work"

# ── US-2 duplicates + type-search ───────────────────────────────────────────
./arch-query "$MAIN" duplicates | grep -q 'dup_sig' || note "duplicates: expected dup_sig group"
if ./arch-query "$MAIN" duplicates | grep -q 'huge_fn'; then note "duplicates: huge_fn must not appear"; fi
./arch-query "$MAIN" type-search instance_name | grep -q 'config' || note "type-search field: expected config"
./arch-query "$MAIN" type-search - string | grep -q 'settings' || note "type-search type-only: expected settings"
./arch-query "$MAIN" type-search 'pct_100%' | grep -q 'settings' || note "type-search wildcard: literal % must match"
if ./arch-query "$MAIN" type-search zzz_none | grep -q 'config'; then note "type-search: zzz_none must match nothing"; fi
rc=0; ./arch-query "$MAIN" type-search - >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "type-search -: expected exit 2"

# determinism
diff <(./arch-query "$MAIN" unsafe-strings 1) <(./arch-query "$MAIN" unsafe-strings 1) >/dev/null \
  || note "unsafe-strings: nondeterministic output"

# ── US-3 arch-body-compare ──────────────────────────────────────────────────
PROJ="$TMP/proj"; mkdir -p "$PROJ/src"
printf 'let dup x =\n  x + 1\n' > "$PROJ/src/a.ml"
printf 'let dup x =\n    x + 1\n' > "$PROJ/src/b.ml"
BODYDB="$TMP/body.db"
sqlite3 "$BODYDB" "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT);
CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, line_start INTEGER, line_end INTEGER);
INSERT INTO modules VALUES(1,'src/a.ml'),(2,'src/b.ml');
INSERT INTO functions VALUES(1,1,'dup',1,2),(2,2,'dup',1,2);"
./arch-body-compare --db "$BODYDB" --project-root "$PROJ" dup | grep -q 'IDENTICAL' || note "body-compare: expected IDENTICAL"
rc=0; ./arch-body-compare --db "$BODYDB" --project-root "$PROJ" nope >/dev/null || rc=$?; [ "$rc" -eq 1 ] || note "body-compare unknown: expected exit 1"
rc=0; ./arch-body-compare --db "$FLAT" --project-root "$PROJ" f >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 3 ] || note "body-compare flat: expected exit 3"
rc=0; ./arch-body-compare --db "$BODYDB" dup >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "body-compare missing root: expected exit 2"


# ── Curation layer (specs/arch-gardening-queries.md) ────────────────────────
# Execute the documented ledger SQL VERBATIM (extracted from docs) — doc drift breaks CI.
DOC_SQL=$(awk '/<!-- selftest:begin -->/,/<!-- selftest:end -->/' docs/curation-workflow.md | sed '/^```/d;/selftest:/d')
[ -n "$DOC_SQL" ] || note "curation: extracted zero SQL statements from docs/curation-workflow.md"
printf '%s\n' "$DOC_SQL" | sqlite3 "$MAIN" || note "curation: documented SQL failed to execute"

# unsafe-params ledger queries
./arch-query "$MAIN" unsafe-params | grep -q 'instance' || note "unsafe-params: expected unfixed 'instance' row"
sqlite3 "$MAIN" "UPDATE unsafe_params SET fixed=1 WHERE github_issue=42;"
if ./arch-query "$MAIN" unsafe-params | grep -q 'instance'; then note "unsafe-params: fixed row must leave default view"; fi
./arch-query "$MAIN" unsafe-params fixed | grep -q 'instance' || note "unsafe-params fixed: expected row"
./arch-query "$MAIN" unsafe-params all | grep -q 'instance' || note "unsafe-params all: expected row"
rc=0; ./arch-query "$MAIN" unsafe-params bogus >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "unsafe-params bogus: expected exit 2"

# gardening
sqlite3 "$MAIN" "INSERT INTO gardening_tasks(category,title,status) VALUES('coverage','wip task','in_progress'),('coverage','done task','done');"
./arch-query "$MAIN" gardening | grep -q 'split src/big.ml' || note "gardening open: expected open task"
./arch-query "$MAIN" gardening | grep -q 'wip task' || note "gardening open: in_progress must be included"
if ./arch-query "$MAIN" gardening | grep -q 'done task'; then note "gardening open: done must be excluded"; fi
./arch-query "$MAIN" gardening log | grep -q 'Instance_name.t' || note "gardening log: expected log row"
rc=0; ./arch-query "$MAIN" gardening bogus >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "gardening bogus: expected exit 2"

# coverage loader + low-coverage latest-record semantics
printf '%s\n' \
  '{"type":"coverage","function":"tiny_fn","module":"src/big.ml","covered_lines":3,"total_lines":10}' \
  '{"type":"coverage","function":"helper","module":"src/small.ml","covered_lines":2,"total_lines":10}' \
  | ./arch-coverage-load --db "$MAIN" --stamp 2026-07-08T00:00:00Z | grep -q '2 written' || note "coverage-load: expected 2 written"
# second snapshot: tiny_fn improves to 80%
printf '%s\n' '{"type":"coverage","function":"tiny_fn","module":"src/big.ml","covered_lines":8,"total_lines":10}' \
  | ./arch-coverage-load --db "$MAIN" --stamp 2026-07-09T00:00:00Z >/dev/null
if ./arch-query "$MAIN" low-coverage 50 | grep -q 'tiny_fn'; then note "low-coverage: latest snapshot (80%) must exclude tiny_fn"; fi
./arch-query "$MAIN" low-coverage 50 | grep -q 'helper' || note "low-coverage: helper (20%) expected"
# idempotent rerun with same stamp
printf '%s\n' '{"type":"coverage","function":"tiny_fn","module":"src/big.ml","covered_lines":8,"total_lines":10}' \
  | ./arch-coverage-load --db "$MAIN" --stamp 2026-07-09T00:00:00Z | grep -q '0 written, 0 skipped, 1 ignored' || note "coverage-load: rerun must be ignored"
# malformed → rollback, count unchanged
BEFORE=$(sqlite3 "$MAIN" "SELECT count(*) FROM coverage;")
rc=0; printf '%s\n' '{"type":"coverage","function":"helper","module":"src/small.ml","covered_lines":9,"total_lines":3}' \
  | ./arch-coverage-load --db "$MAIN" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || note "coverage-load malformed: expected exit 2"
AFTER=$(sqlite3 "$MAIN" "SELECT count(*) FROM coverage;")
[ "$BEFORE" = "$AFTER" ] || note "coverage-load malformed: rollback failed"
# bad stamp / flat refusal
rc=0; ./arch-coverage-load --db "$MAIN" --stamp '2026-7-8' </dev/null >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 2 ] || note "coverage-load bad stamp: expected exit 2"
rc=0; ./arch-coverage-load --db "$FLAT" </dev/null >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 3 ] || note "coverage-load flat: expected exit 3"
rc=0; ./arch-query "$FLAT" low-coverage >/dev/null 2>&1 || rc=$?; [ "$rc" -eq 3 ] || note "flat low-coverage: expected exit 3"
if [ "$FAILS" -eq 0 ]; then echo "arch-index health selftest: OK"; else echo "arch-index health selftest: FAIL ($FAILS)"; exit 1; fi
