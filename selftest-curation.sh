#!/usr/bin/env bash
# selftest-curation.sh — B1 (arch-coverage-load) + B2 (arch-query read surfaces) +
# B3 (arch-curate write surface): the curation ledgers, end to end.
#
# Under test: B1's strict validation (malformed input aborts before any write) and its
# written/skipped/ignored accounting; B2's "latest snapshot per function" read and exit-3 refusal
# on an index without the ledger tables; B3's provenance requirement on gardening_log, its
# constraint-conflict messages, and that gardening_log only ever grows (append-only).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; Q="$HERE/arch-query"; CL="$HERE/arch-coverage-load"; CUR="$HERE/arch-curate"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-curation: sqlite3 required" >&2; exit 2; }
say() { ARCH_QUERY_FORMAT=list "$Q" "$@" 2>&1; }

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
sqlite3 "$DB" < "$HERE/architecture-schema.sql"
sqlite3 "$DB" <<'SQL'
INSERT INTO modules(path, lines) VALUES ('lib/a.ml', 10), ('lib/b.ml', 10);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/a.ml'), 'f', 1, 5),
  ((SELECT id FROM modules WHERE path='lib/a.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/b.ml'), 'dup', 3, 4);
SQL

# =================================================================================================
# B1 — arch-coverage-load
# =================================================================================================

# ---- happy path: written/skipped/ignored accounting -------------------------------------------
OUT="$(printf '%s\n' \
  '{"function":"f","covered_lines":3,"total_lines":10}' \
  '{"function":"ghost","covered_lines":1,"total_lines":1}' \
  '{"function":"dup","covered_lines":1,"total_lines":1}' \
  | "$CL" "$DB" 2>&1)"
echo "$OUT" | grep -q 'wrote 1, skipped 1' || note "arch-coverage-load must report wrote=1 skipped=1: $OUT"
echo "$OUT" | grep -q 'ignored 1' || note "arch-coverage-load must report ignored=1 (ambiguous 'dup'): $OUT"
N="$(sqlite3 "$DB" "SELECT count(*) FROM coverage;")"
[ "$N" -eq 1 ] || note "coverage table must have exactly 1 row after the happy-path load, got $N"

# ---- malformed input aborts the WHOLE load, nothing partial gets written -----------------------
BEFORE="$(sqlite3 "$DB" "SELECT count(*) FROM coverage;")"
printf '%s\n%s\n' \
  '{"function":"f","covered_lines":1,"total_lines":10}' \
  '{"function":"f","covered_lines":9,"total_lines":10,"extra":1}' \
  | "$CL" "$DB" >/dev/null 2>&1
[ $? -eq 2 ] || note "an unknown field must abort the load with exit 2"
AFTER="$(sqlite3 "$DB" "SELECT count(*) FROM coverage;")"
[ "$AFTER" -eq "$BEFORE" ] || note "an aborted load must not write ANY row, even ones before the malformed line ($BEFORE -> $AFTER)"

printf '%s\n' '{"function":"f","covered_lines":11,"total_lines":10}' | "$CL" "$DB" >/dev/null 2>&1
[ $? -eq 2 ] || note "covered_lines > total_lines must abort the load"

printf '%s\n%s\n' '{"function":"f","covered_lines":1,"total_lines":10}' '{"function":"f","covered_lines":2,"total_lines":10}' | "$CL" "$DB" >/dev/null 2>&1
[ $? -eq 2 ] || note "the same function name twice in one input must abort the load (one snapshot, one row per function)"

# ---- a second, later snapshot: coverage improves, both rows are KEPT (history) -----------------
sleep 1
printf '%s\n' '{"function":"f","covered_lines":8,"total_lines":10}' | "$CL" "$DB" >/dev/null 2>&1
N="$(sqlite3 "$DB" "SELECT count(*) FROM coverage WHERE function_id=(SELECT id FROM functions WHERE name='f');")"
[ "$N" -eq 2 ] || note "a second load must APPEND a second snapshot for f, not replace the first (got $N rows)"

# ---- refuses cleanly on a non-main-schema / missing-table DB -----------------------------------
FLAT="$(mktemp --suffix=.db)"; rm -f "$FLAT"
"$LOAD" "$FLAT" <<'NDJSON' 2>/dev/null
{"type":"function","name":"f","file_path":"x","exported":true}
{"type":"function","name":"g","file_path":"x"}
{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}
NDJSON
printf '%s\n' '{"function":"f","covered_lines":1,"total_lines":1}' | "$CL" "$FLAT" >/dev/null 2>&1
[ $? -eq 2 ] || note "arch-coverage-load on a flat (arch-load) index must fail cleanly (exit 2 — it is not an unsound-verdict situation, the table simply is not there)"

# =================================================================================================
# B2 — arch-query low-coverage / gardening / unsafe-params
# =================================================================================================

# ---- low-coverage reads the LATEST snapshot per function, not every historical row --------------
OUT="$(say "$DB" low-coverage)"
N="$(echo "$OUT" | grep -c "^lib/a.ml|f|")"
[ "$N" -eq 1 ] || note "low-coverage must show exactly ONE row for f (latest snapshot only), got $N: $OUT"
echo "$OUT" | grep -q '^lib/a.ml|f|80.0|8|10' || note "low-coverage must show f's LATEST snapshot (8/10=80%%), not an older one: $OUT"

# ---- exit-3 refusal when the ledger tables are absent (flat index) ------------------------------
for cmd in low-coverage "gardening open" "gardening log" "unsafe-params"; do
  "$Q" "$FLAT" $cmd >/dev/null 2>&1
  [ $? -eq 3 ] || note "'$cmd' on a flat (arch-load) index must REFUSE with exit 3"
done

# =================================================================================================
# B3 — arch-curate (open-task / mark-fixed / add-unsafe-param / log)
# =================================================================================================

"$CUR" "$DB" open-task --issue 900 --category type-safety --title 'fix f.instance' --function f >/dev/null 2>&1
[ $? -eq 0 ] || note "open-task must succeed on a fresh issue"
say "$DB" gardening open | grep -q '900|type-safety' || note "gardening open must list the freshly-opened task"

"$CUR" "$DB" open-task --issue 900 --category x --title y >/dev/null 2>&1
[ $? -eq 2 ] || note "open-task must refuse re-using an already-tracked github_issue (exit 2)"

"$CUR" "$DB" open-task --issue 901 --category x --title y --module lib/a.ml --function f >/dev/null 2>&1
[ $? -eq 2 ] || note "open-task must refuse when BOTH --module and --function are given"

"$CUR" "$DB" add-unsafe-param --function f --param instance --current string --target Instance.t --issue 900 >/dev/null 2>&1
[ $? -eq 0 ] || note "add-unsafe-param must succeed for a fresh (function,param) pair"
say "$DB" unsafe-params | grep -q 'instance|string|Instance.t|900|0' || note "unsafe-params (default unfixed) must list the freshly-recorded param"

"$CUR" "$DB" add-unsafe-param --function f --param instance --current string >/dev/null 2>&1
[ $? -eq 2 ] || note "add-unsafe-param must refuse re-recording an already-tracked (function,param) pair"

"$CUR" "$DB" mark-fixed --function f --param nope >/dev/null 2>&1
[ $? -eq 2 ] || note "mark-fixed must refuse a param that was never recorded"

"$CUR" "$DB" mark-fixed --function f --param instance >/dev/null 2>&1
[ $? -eq 0 ] || note "mark-fixed must succeed on a recorded param"
say "$DB" unsafe-params fixed | grep -q 'instance.*1$' || note "unsafe-params fixed must list instance as fixed=1 after mark-fixed"
say "$DB" unsafe-params unfixed | grep -q 'instance' && note "unsafe-params unfixed must NOT list instance anymore (it is fixed now)"

# ---- provenance is MANDATORY on gardening_log, not merely conventional -------------------------
"$CUR" "$DB" log --category type-safety --description 'no contributor' --pr 1 >/dev/null 2>&1
[ $? -eq 2 ] || note "log without --contributor must be refused (provenance is mandatory)"
"$CUR" "$DB" log --contributor alice --category type-safety --description 'no pr' >/dev/null 2>&1
[ $? -eq 2 ] || note "log without --pr must be refused (provenance is mandatory)"

BEFORE_LOG="$(sqlite3 "$DB" "SELECT count(*) FROM gardening_log;")"
"$CUR" "$DB" log --contributor alice --category type-safety --description 'fixed f.instance' --pr 55 --issue 900 >/dev/null 2>&1
[ $? -eq 0 ] || note "a fully-provenanced log entry must succeed"
AFTER_LOG="$(sqlite3 "$DB" "SELECT count(*) FROM gardening_log;")"
[ "$AFTER_LOG" -eq $((BEFORE_LOG + 1)) ] || note "log must append exactly one row ($BEFORE_LOG -> $AFTER_LOG)"
say "$DB" gardening log | grep -q 'alice|type-safety|fixed f.instance|55|900' || note "gardening log must show the new entry with its provenance"

# append-only: arch-curate exposes no edit/delete verb at all
"$CUR" 2>&1 | grep -qE '^\s+(edit|delete|remove|update)-' && note "arch-curate must not expose an edit/delete/remove/update subcommand against gardening_log"

# a second log entry must ADD to the log, never replace the first
"$CUR" "$DB" log --contributor bob --category coverage --description 'raised coverage on f' --pr 56 >/dev/null 2>&1
N="$(sqlite3 "$DB" "SELECT count(*) FROM gardening_log;")"
[ "$N" -eq $((AFTER_LOG + 1)) ] || note "a second log call must add a row, not replace the first ($AFTER_LOG -> $N)"
say "$DB" gardening log | grep -q 'alice' || note "the first log entry (alice) must still be present after a second log call"
say "$DB" gardening log | grep -q 'bob'   || note "the second log entry (bob) must be present"

# ---- exit-3 feature-detect on a flat (arch-load) index -------------------------------------------
"$CUR" "$FLAT" open-task --issue 1 --category x --title y >/dev/null 2>&1
[ $? -eq 3 ] || note "arch-curate open-task on a flat index must REFUSE with exit 3 (no gardening_tasks table)"
"$CUR" "$FLAT" log --contributor alice --category x --description y --pr 1 >/dev/null 2>&1
[ $? -eq 3 ] || note "arch-curate log on a flat index must REFUSE with exit 3 (no gardening_log table)"

# ---- corrected indexer preserves all curation through two rebuilds and removal -----------------
CG="$HERE/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
if [ -x "$CG" ]; then
  RX="$(mktemp -d)"
  mkdir -p "$RX/src"
  printf '(lang dune 3.0)\n' > "$RX/dune-project"
  printf '(library (name reidx) (modules reidx))\n' > "$RX/src/dune"
  printf 'let kept x = x + 1\nlet removed x = x - 1\n' > "$RX/src/reidx.ml"
  (cd "$RX" && dune build >/dev/null)
  RDB="$RX/index.db"
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  sqlite3 "$RDB" <<'SQL'
INSERT INTO coverage(function_id,covered_lines,total_lines,recorded_at)
 SELECT id,7,9,'2025-01-02T03:04:05Z' FROM functions WHERE name='removed';
INSERT INTO unsafe_params(function_id,param_name,current_type,target_type,fixed,fixed_at,github_issue)
 SELECT id,'raw','string','Safe.t',1,'2025-02-03T04:05:06Z',4321 FROM functions WHERE name='removed';
INSERT INTO gardening_tasks(github_issue,category,title,target_function_id,status,created_at,completed_at)
 SELECT 7654,'safety','retain me',id,'done','2025-03-04T05:06:07Z','2025-03-05T05:06:07Z'
 FROM functions WHERE name='removed';
INSERT INTO gardening_log(date,contributor,category,description,pr_number,issue_number,created_at)
 VALUES('2025-04-05','alice','safety','retained log',99,7654,'2025-04-05T06:07:08Z');
SQL
  SNAP="$(sqlite3 "$RDB" "SELECT covered_lines,total_lines,recorded_at FROM coverage; SELECT param_name,current_type,target_type,fixed,fixed_at,github_issue FROM unsafe_params; SELECT github_issue,category,title,status,created_at,completed_at FROM gardening_tasks; SELECT date,contributor,category,description,pr_number,issue_number,created_at FROM gardening_log;")"
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  SNAP2="$(sqlite3 "$RDB" "SELECT covered_lines,total_lines,recorded_at FROM coverage; SELECT param_name,current_type,target_type,fixed,fixed_at,github_issue FROM unsafe_params; SELECT github_issue,category,title,status,created_at,completed_at FROM gardening_tasks; SELECT date,contributor,category,description,pr_number,issue_number,created_at FROM gardening_log;")"
  [ "$SNAP" = "$SNAP2" ] || note "two reindexes must preserve every curation value and timestamp exactly"
  printf 'let kept x = x + 1\n' > "$RX/src/reidx.ml"
  (cd "$RX" && dune build >/dev/null)
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  ORPHAN="$(sqlite3 "$RDB" "SELECT function_id IS NULL,target_module_path,target_function_name FROM coverage;")"
  [ "$ORPHAN" = "1|src/reidx.ml|removed" ] \
    || note "removed coverage target must survive with durable path/name and NULL live id (got $ORPHAN)"
  [ "$(sqlite3 "$RDB" 'SELECT count(*) FROM unsafe_params; SELECT count(*) FROM gardening_tasks; SELECT count(*) FROM gardening_log;')" = $'1\n1\n1' ] \
    || note "removed targets must not delete unsafe/task/log ledger rows"
  ORPHAN_SNAPSHOT="$(sqlite3 "$RDB" "
    SELECT id,function_id IS NULL,target_module_path,target_function_name,covered_lines,total_lines,recorded_at FROM coverage;
    SELECT id,function_id IS NULL,target_module_path,target_function_name,param_name,current_type,target_type,fixed,fixed_at,github_issue FROM unsafe_params;
    SELECT id,target_module_id IS NULL,target_function_id IS NULL,target_module_path,target_function_module_path,target_function_name,github_issue,category,title,status,created_at,completed_at FROM gardening_tasks;
    SELECT id,date,contributor,category,description,pr_number,issue_number,created_at FROM gardening_log;")"
  [ "$(sqlite3 "$RDB" "SELECT target_module_path,target_function_name FROM unsafe_params; SELECT target_function_module_path,target_function_name FROM gardening_tasks;")" = $'src/reidx.ml|removed\nsrc/reidx.ml|removed' ] \
    || note "every removed function ledger must retain its durable module/function identity"
  # Once live IDs are NULL, subsequent backups must use durable identity rather
  # than inner-joining the now-absent function. Exercise two more rebuilds so a
  # one-generation orphan implementation cannot pass.
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  "$CG" --build-dir="$RX/_build/default" --db-path="$RDB" --schema-path="$HERE/architecture-schema.sql" >/dev/null
  ORPHAN_SNAPSHOT_AFTER="$(sqlite3 "$RDB" "
    SELECT id,function_id IS NULL,target_module_path,target_function_name,covered_lines,total_lines,recorded_at FROM coverage;
    SELECT id,function_id IS NULL,target_module_path,target_function_name,param_name,current_type,target_type,fixed,fixed_at,github_issue FROM unsafe_params;
    SELECT id,target_module_id IS NULL,target_function_id IS NULL,target_module_path,target_function_module_path,target_function_name,github_issue,category,title,status,created_at,completed_at FROM gardening_tasks;
    SELECT id,date,contributor,category,description,pr_number,issue_number,created_at FROM gardening_log;")"
  [ "$ORPHAN_SNAPSHOT" = "$ORPHAN_SNAPSHOT_AFTER" ] \
    || note "orphan ledger rows and durable identity must survive every later reindex exactly"
  rm -rf "$RX"
fi

rm -f "$DB" "$FLAT"
if [ "$fails" -eq 0 ]; then echo "selftest-curation: PASS"; else echo "selftest-curation: $fails FAILURE(S)"; exit 1; fi
