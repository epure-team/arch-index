#!/usr/bin/env bash
# check-mutant-key.sh — is `mutants`'s natural key actually discriminating, on a real population?
#
# Why this is not a `GROUP BY … HAVING count(*) > 1`.
# bin/arch_body_compare/arch_body_compare.ml:82 probes for duplicates that way, and that is
# correct THERE, because the column it groups on carries no constraint. Here the key IS a UNIQUE
# constraint, so a duplicate never becomes a group — it becomes a REJECTED INSERT and the table
# never holds it. A GROUP BY over `mutants` therefore returns 0 whatever the key is worth,
# including if the key were a single constant column. It is a probe that cannot fail.
#
# What this counts instead: rows the constraint REJECTS when the population is re-inserted into a
# fresh table carrying the same key. And, because a discriminating key can still be measured on a
# fabricated population, it prints WHAT the population is made of, not only how big it is.
#
# The positive control is the half that makes the whole thing mean something. A population whose
# rows happen to be pairwise distinct produces 0 rejections under ANY key, a dropped constraint
# included. So one row is deliberately re-offered and MUST be rejected. If it is accepted, the key
# is not enforced and this check fails — that is the assertion, not the zero above it.
#
# Usage:  scripts/check-mutant-key.sh <db> [more.db ...]
#         With no argument it looks for the largest `mutants` population among *.db under the tree.
# Exit:   0 = the key is enforced and discriminating on this population.
#         1 = the assertion fired: the deliberate duplicate was ACCEPTED, so the key is not live.
#         2 = harness error (no sqlite3, no migration file, no population to measure).

set -uo pipefail

command -v sqlite3 >/dev/null 2>&1 || { echo "check-mutant-key: sqlite3 not found" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MIGRATION="$ROOT/mutants-schema-migration.sql"
[ -r "$MIGRATION" ] || { echo "check-mutant-key: cannot read $MIGRATION" >&2; exit 2; }

dbs=("$@")
if [ "${#dbs[@]}" -eq 0 ]; then
  while IFS= read -r d; do dbs+=("$d"); done < <(find "$ROOT" -name '*.db' -type f 2>/dev/null)
fi
[ "${#dbs[@]}" -gt 0 ] || { echo "check-mutant-key: no database given and none found under $ROOT" >&2; exit 2; }

# Pick the LARGEST available population: a key probed on three rows says nothing about a key.
best=""; best_n=-1
for d in "${dbs[@]}"; do
  n="$(sqlite3 "$d" "SELECT count(*) FROM mutants;" 2>/dev/null)" || continue
  [ -n "$n" ] || continue
  if [ "$n" -gt "$best_n" ]; then best_n="$n"; best="$d"; fi
done

if [ -z "$best" ]; then
  echo "check-mutant-key: no database under $ROOT has a \`mutants\` table."
  echo "  Nothing was measured, so nothing is asserted. Run a campaign"
  echo "  (arch-mutants run …) first; that is what populates the table this probes."
  exit 2
fi

if [ "$best_n" -eq 0 ]; then
  echo "check-mutant-key: $best has a \`mutants\` table with 0 rows."
  echo "  A population of 0 makes every key look perfect. Nothing is asserted."
  exit 2
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
probe="$scratch/probe.db"
sqlite3 "$probe" < "$MIGRATION" || { echo "check-mutant-key: could not apply $MIGRATION" >&2; exit 2; }

# Say what the population IS. A key can be perfectly discriminating and still have been measured
# on rows that are all copies of one shape, in which case the number above is about the fixture.
echo "check-mutant-key: population from $best"
sqlite3 "$best" <<'SQL' | sed 's/^/  · /'
SELECT 'rows                    : ' || count(*) FROM mutants;
SELECT 'distinct files          : ' || count(DISTINCT file_path) FROM mutants;
SELECT 'distinct lines          : ' || count(DISTINCT line) FROM mutants;
SELECT 'distinct column spans   : ' || count(DISTINCT col_start || ':' || col_end) FROM mutants;
SELECT 'distinct replacements   : ' || count(DISTINCT replacement) FROM mutants;
SELECT 'distinct source hashes  : ' || count(DISTINCT source_hash) FROM mutants;
SELECT 'rows with NULL function : ' || count(*) FROM mutants WHERE function_id IS NULL;
SQL

# Re-insert the whole population into the fresh, constrained table. INSERT OR IGNORE lets the
# constraint reject rather than abort, and total_changes() counts what it ACCEPTED.
sqlite3 "$probe" <<SQL > "$scratch/accepted"
ATTACH DATABASE '$best' AS src;
INSERT OR IGNORE INTO main.mutants
  (file_path, line, col_start, col_end, replacement, source_hash, function_id, function_name)
SELECT file_path, line, col_start, col_end, replacement, source_hash, function_id, function_name
FROM src.mutants;
SELECT changes();
SQL
accepted="$(tail -1 "$scratch/accepted")"
[ -n "$accepted" ] || { echo "check-mutant-key: the re-insert produced no count" >&2; exit 2; }
rejected=$(( best_n - accepted ))

echo
echo "  population $best_n row(s) → $accepted accepted, $rejected REJECTED by the UNIQUE constraint"
echo "      (rejected, not grouped: under a constraint a duplicate never becomes a group)"
if [ "$rejected" -eq 0 ]; then
  echo "      A zero here means the source table's own constraint already held, which is the"
  echo "      expected steady state. It would be non-zero if two campaigns had written the same"
  echo "      site with different content — the case the key exists to make impossible."
fi

# The positive control. Re-offer one row that is already in the probe table.
sqlite3 "$probe" <<'SQL' > "$scratch/control"
INSERT OR IGNORE INTO mutants
  (file_path, line, col_start, col_end, replacement, source_hash, function_id, function_name)
SELECT file_path, line, col_start, col_end, replacement, source_hash, function_id, 'RE-OFFERED'
FROM mutants LIMIT 1;
SELECT changes();
SQL
control="$(tail -1 "$scratch/control")"

echo
if [ "$control" != "0" ]; then
  echo "check-mutant-key: FAILED — a row identical on (file_path, line, col_start, col_end,"
  echo "  replacement, source_hash) was ACCEPTED. The UNIQUE constraint is not enforcing the key,"
  echo "  so every count above was measuring nothing."
  exit 1
fi
echo "check-mutant-key: the deliberate duplicate was rejected — the key is live and discriminating."
exit 0
