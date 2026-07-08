# Reviewer Brief — arch-health-queries

**Status:** VALIDATED
**Contract:** specs/arch-health-queries.md (FR-001..015, EC list). Cite IDs.

## Audit first

1. Column-level feature detection per command (not table-level) — the top plan risk; probe each branch against a flat DB (must exit 3, never empty-success where the source column is absent).
2. LIKE escape helper correctness in bash (`%`,`_`,`\` + ESCAPE) and quote-strip interaction; threshold regex validation (exit 2 paths).
3. duplicates: NULL/empty signatures excluded; same-module repeats excluded; deterministic order.
4. arch-body-compare: DIFFERS groups sorted by digest; empty-body flags for missing files/NULL ranges; exit taxonomy 0/1/2/3; bound-param name lookup in the library.
5. selftest-health.sh: real main-schema fixture (from architecture-schema.sql), not hand-rolled divergent DDL; covers refusals + wildcard inputs.
6. Docs: arch-query header + README updated; no doc drift with items 1–2 sections.

## Spot-run

CHECK-1/2/3/4/6 from the spec.
