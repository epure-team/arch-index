#!/usr/bin/env bash
# selftest-curation-doc.sh — docs/curation-workflow.md's ```sql``` reference blocks are not just
# prose: they are extracted, in order, and actually RUN against a fresh architecture-schema.sql
# database. If a schema change breaks the doc's SQL (a renamed column, a dropped table), this
# fails — doc/schema drift breaks CI instead of quietly going stale.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DOC="$HERE/docs/curation-workflow.md"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-curation-doc: sqlite3 required" >&2; exit 2; }
[ -f "$DOC" ] || { echo "selftest-curation-doc: $DOC not found" >&2; exit 2; }

EXTRACTED="$(mktemp)"
awk '/^```sql$/{flag=1; next} /^```$/{if (flag) print ""; flag=0} flag' "$DOC" > "$EXTRACTED"
[ -s "$EXTRACTED" ] || { echo "selftest-curation-doc: no \`\`\`sql block found in $DOC — extraction is broken or the doc lost its reference section" >&2; exit 1; }
N_BLOCKS="$(grep -c '^```sql$' "$DOC")"
[ "$N_BLOCKS" -ge 4 ] || note "expected at least 4 \`\`\`sql blocks (gardening_tasks, unsafe_params x2, gardening_log), found $N_BLOCKS"

DB="$(mktemp --suffix=.db)"; rm -f "$DB"
sqlite3 "$DB" < "$HERE/architecture-schema.sql" || { echo "selftest-curation-doc: architecture-schema.sql failed to load" >&2; exit 2; }
sqlite3 "$DB" <<'SQL'
INSERT INTO modules(path, lines) VALUES ('lib/installer.ml', 50);
INSERT INTO functions(module_id, name, line_start, line_end)
VALUES ((SELECT id FROM modules WHERE path='lib/installer.ml'), 'install_node', 1, 40);
SQL

sqlite3 "$DB" < "$EXTRACTED" 2>/tmp/curation-doc-sql-errors.txt
rc=$?
if [ "$rc" -ne 0 ]; then
  note "the doc's \`\`\`sql\`\`\` blocks failed to run against a fresh architecture-schema.sql DB — doc/schema drift:"
  cat /tmp/curation-doc-sql-errors.txt >&2
fi

# The doc's own narrative: after running its blocks IN ORDER, this is the state they claim to
# produce (task opened for issue 214, the param recorded THEN marked fixed, one log entry).
[ "$(sqlite3 "$DB" "SELECT count(*) FROM gardening_tasks WHERE github_issue=214 AND status='open';")" = "1" ] \
  || note "the doc's gardening_tasks INSERT must open exactly one task for issue 214"
[ "$(sqlite3 "$DB" "SELECT fixed FROM unsafe_params WHERE param_name='instance';")" = "1" ] \
  || note "the doc's unsafe_params INSERT-then-UPDATE must leave instance marked fixed=1"
[ "$(sqlite3 "$DB" "SELECT count(*) FROM gardening_log WHERE pr_number=217 AND issue_number=214;")" = "1" ] \
  || note "the doc's gardening_log INSERT must append exactly one entry for PR 217 / issue 214"
[ "$(sqlite3 "$DB" "SELECT contributor FROM gardening_log WHERE pr_number=217;")" = "jdoe" ] \
  || note "the doc's gardening_log INSERT must carry contributor='jdoe' (provenance)"

# The append-only claim: none of the extracted blocks may UPDATE or DELETE gardening_log.
grep -qiE '(UPDATE|DELETE)[^;]*gardening_log' "$EXTRACTED" \
  && note "docs/curation-workflow.md must not contain an UPDATE/DELETE against gardening_log — it is append-only"

rm -f "$DB" "$EXTRACTED" /tmp/curation-doc-sql-errors.txt
if [ "$fails" -eq 0 ]; then echo "selftest-curation-doc: PASS"; else echo "selftest-curation-doc: $fails FAILURE(S)"; exit 1; fi
