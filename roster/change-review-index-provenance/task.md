# Roster intake — change-review index provenance

## Objective

Enrich only `arch-impact --format json` with the stable index provenance a
future change-review consumer needs to reject incomparable briefings.  This is
the second prerequisite after PR125's input provenance, not the consumer
itself.

## Contract

Add a versioned `index_provenance` object to JSON output:

- `version: 1`;
- `schema_version: string | null`;
- `producers`: canonical records with `producer`, `producer_version | null`,
  `soundness_class`, and `invocation_digest | null`;
- `analysis_coverage`: canonical records with `language | null`, `analysis`,
  `status`, and `detail | null`.

Values must be collected through the same shared report provenance reader, so
`arch-report` and `arch-impact` cannot silently disagree about a database's
producer/coverage facts.  The consumer will compare a stable producer identity
(excluding invocation digests) and exact declared coverage; digests remain
provenance only because DB path currently affects them.

## Non-goals

- No change-review runner, baseline comparison, source digest, CI gate, index
  rebuild, or baseline promotion.
- No change to text/Markdown impact output, graph closure, MUST/MAY/TOP
  vocabulary or existing JSON fields.
- No claim that an empty producer list proves a trustworthy or complete index.

## Acceptance

1. Main-schema provenance and flat-schema absence are distinguishable and
   deterministic.
2. JSON matches `arch-report` for a fixture with producer and coverage rows.
3. The existing authentic impact controls retain the bounded-MAY/TOP wording.
4. The full impact Tezt file and global build pass before review.
