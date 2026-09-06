#!/usr/bin/env bash
# checks/identity-doctrine-is-resolved.sh — runnable directly: `bash <path> [repo]`.
#
# Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
#
# WHY THIS EXISTS. Two documents in this branch each held a COHERENT and MUTUALLY EXCLUSIVE
# theory of what identifies a mutant, and nothing anywhere said which one governed.
#
#   mutants-schema-migration.sql: a mutant is identified by where the mutation is and what it
#   replaces, "never by an engine-assigned id (engine ids are not trusted for identity)", and
#   engine_mutant_id is "NOT part of any identity".
#
#   bin/arch_mutants/arch_mutants.ml: the join's FIRST key was the engine's own id.
#
# A reader could satisfy either and be following the project. That is not a comment problem;
# it is why the same defect survived three rounds of review — each round fixed the symptom
# the driver's own theory made visible.
#
# THE RESOLUTION, and the reason it goes THIS way rather than the other. An engine id is a
# COORDINATE, not an identity: it is handed out by one run of one engine over one catalogue,
# nothing in the mutant determines it, and re-running the engine or reordering the catalogue
# gives the same mutant a different number. When two coherent documents contradict each other,
# the one asserting a PROPERTY outranks the one asserting a MECHANISM — the migration's claim
# is checkable and stays true, while the driver's described how the code happened to join on
# the day it was written. THE MIGRATION PREVAILS.
#
# What this file asserts is therefore both halves: that the resolution is WRITTEN, in every
# file that held a side of it, and — the load-bearing half — that the code no longer has the
# shape the losing theory required. A doctrine present only as prose is a doctrine the next
# author will contradict again.

set -u
repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
name=identity-doctrine-is-resolved

MIG="$repo/mutants-schema-migration.sql"
DRV="$repo/bin/arch_mutants/arch_mutants.ml"
DB="$repo/bin/arch_mutants/arch_mutant_db.ml"

for f in "$MIG" "$DRV" "$DB"; do
  [ -f "$f" ] || { echo "$name: $f is missing — nothing was checked." >&2; exit 2; }
done

fails=0
ok()   { printf '  \342\234\223 %s\n' "$1"; }
bad()  { printf '  \342\234\227 %s\n' "$1"; fails=$((fails + 1)); }

# $1 label · $2 file · $3 extended regex that must MATCH
must_match() {
  if grep -Eqi -- "$3" "$2"; then ok "$1"; else bad "$1 — no line matching /$3/ in ${2#$repo/}"; fi
}
# $1 label · $2 file · $3 extended regex that must NOT match
must_not_match() {
  local hits
  hits=$(grep -Ec -- "$3" "$2" 2>/dev/null || true)
  if [ "${hits:-0}" = "0" ]; then ok "$1"; else bad "$1 — $hits line(s) matching /$3/ in ${2#$repo/}"; fi
}

echo "probe 1 — the resolution is written in the SQL that asserts the property"
must_match "the migration carries the IDENTITY DOCTRINE heading" "$MIG" 'IDENTITY DOCTRINE'
must_match "it says which document prevails, and does not merely restate its own claim" "$MIG" 'prevail'
must_match "it still states the property itself" "$MIG" 'not trusted for identity'
must_match "engine_mutant_id is marked RUN-scoped, not mutant-scoped" "$MIG" 'RUN.?scope'

echo "probe 2 — the same resolution is written in the driver that held the other side"
must_match "the driver carries the IDENTITY DOCTRINE heading" "$DRV" 'IDENTITY DOCTRINE'
must_match "the driver says the migration prevails" "$DRV" 'prevail'
must_match "and gives the reason: a coordinate is not an identity" "$DRV" 'coordinate'

echo "probe 3 — and in the write layer, where engine_mutant_id is actually bound"
must_match "the write layer carries the heading" "$DB" 'IDENTITY DOCTRINE'
must_match "and marks the engine id RUN-scoped where it is bound" "$DB" 'RUN.?scope'

# PROBE 4 IS A GREP, AND A GREP CANNOT ENFORCE A DOCTRINE. It asserts that ONE known
# shape -- the identifier `by_id` -- is absent. The same join arm reintroduced under any
# other name passes it. That is a scope narrower than the word "resolved" in this file's
# name, so the claim is narrowed here rather than dressed up with a cleverer pattern.
#
# WHAT ACTUALLY ENFORCES THE DOCTRINE, and it is not this file:
#   * the TYPE. `site_key` is a distinct record with no id field, so an identity cannot
#     carry an engine id by construction; and `engine_name` splits Engine_declared from
#     Report_ordinal so a synthesised ordinal cannot inhabit a name's slot. A property the
#     compiler enforces needs no check and cannot have a scope narrower than its title,
#     because it has no title.
#   * the BEHAVIOUR. checks/join-independent-of-id-shape.js runs one report against a
#     numbered, a named, a mixed and a degenerate catalogue and asserts the joins AGREE.
#     Any residual id-sensitivity diverges there, under whatever name it is written.
# This file documents that the resolution is WRITTEN in all three places. It does not
# prove it is obeyed. Read it as a documentation gate, not as an enforcement one.
echo "probe 4 — one known shape of the losing theory is absent (a NAME grep: see the header)"
# The join arm itself. A doctrine that survives only in comments is one the next author
# contradicts without noticing, so the assertion is on the code.
must_not_match "no engine-id join arm remains in the driver" "$DRV" '(^|[^_[:alnum:]])by_id([^_[:alnum:]]|$)'
# The field that let a synthesised report ordinal sit in an engine name's slot. After the
# split it is a variant, so a bare `id : string` member on the report record must not return.
must_not_match "the report record has no bare 'id : string' field to re-conflate" "$DRV" '^[[:space:]]*id[[:space:]]*:[[:space:]]*string;'

echo ""
if [ "$fails" -gt 0 ]; then
  echo "$name: FAIL — $fails assertion(s) fired." >&2
  echo "  The schema and the driver still hold opposing theories of mutant identity with" >&2
  echo "  nothing marking which governs, or the code still carries the shape the losing" >&2
  echo "  theory required. Either way the next author can satisfy the wrong one and be" >&2
  echo "  following the project — which is how this defect survived three reviews." >&2
  exit 1
fi
echo "$name: PASS — 4 probes, 11 assertions. Probes 1-3 are documentation gates; probe 4\n  greps ONE name. Enforcement lives in the type and in join-independent-of-id-shape.js."
echo "  What would have made this non-zero: writing the resolution in one file only, stating"
echo "  it without saying which document prevails, or leaving the engine-id join arm in place"
echo "  under a comment that disowns it."
exit 0
