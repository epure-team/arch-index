# Plan — arch-health-queries

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous; Voice 1 inline architect, Voice 2 codex; quiz waived per user pre-authorization)

## Sequential steps

1. **Slice A — health subcommands + main-schema selftest fixture** — six case branches in `arch-query` (`large-files [N]`, `large-functions [N]`, `god-modules [N]`, `missing-docs`, `missing-mli`, `unsafe-strings [N]`) with **column-level** feature-detection (xinfo per required column, not table-level), `^[0-9]+$` threshold validation (exit 2), exit-3 guidance refusals, deterministic ORDER BY; new `selftest-health.sh` that builds a tiny **main-schema** DB via `sqlite3 + architecture-schema.sql` DDL inline (existing selftests only cover flat schema — Voice 2 #4) and asserts each command incl. refusals on a flat DB. Done: CHECK-1/2/6, AC-1/2.
2. **Slice B — duplicates + type-search branches** — same file; NULL/empty signatures excluded; `type-search <field|-> [type]` AND-composed with LIKE escaping (`%`,`_`,`\` + ESCAPE) on top of the existing quote-strip; exit 2 when no real value; exit 3 without `signature`/`type_fields` columns. Extend selftest-health fixture with types/type_fields rows. Done: CHECK-3, AC-3.
3. **Slice C — arch-body-compare CLI + tests + docs** — `bin/arch_body_compare/` + top-level wrapper; flags occurrences whose source file is missing/range NULL vs genuinely empty (CLI checks `Sys.file_exists` itself — the library collapses these, Voice 2 #6); **sorts DIFFERS groups by digest** before printing (Hashtbl.fold nondeterminism, Voice 2 #7); bound-parameter name lookup is inside the library already (verify); exits 0/1/2/3 per FR-011; `test/test_arch_index_compare.ml` with tmpdir fixture sources; README + arch-query header docs. Done: CHECK-4/5, AC-4/5.

## Dependencies

A → B (same selftest fixture grows); C independent of A/B but shares docs commit. Branch: stack on `feat/arch-mcp-server` (accepted risk: README/header conflict surface on rebase — Voice 2 #8; mitigated by keeping doc edits append-only sections).

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Column-level schema variance (signature/line_start/exposed may each be absent) | High | misleading empty results | per-command required-column list; refuse loudly (Voice 2 #1/#2) |
| Bash LIKE escaping bugs | Medium | wrong matches/injection-ish | escape helper + selftest cases with `%`/quote inputs (Voice 2 #3) |
| Health commands "work" but answer empty on unenriched DBs | Medium | false confidence | selftest fixture is a REAL main-schema DB with enriched rows (Voice 2 #5) |
| compare_bodies empty-body collapse | High (spec EC-19/20/21) | fake IDENTICAL verdicts | CLI-side file-existence/range checks + flags (Voice 2 #6) |
| DIFFERS nondeterminism | Medium | flaky checks | sort groups by digest (Voice 2 #7) |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Selftest vehicle | new selftest-health.sh with inline main-schema fixture | existing selftests are flat-only |
| Empty-body handling | CLI distinguishes missing-file/NULL-range/empty; library untouched | keep epure-proven library verbatim; spec only requires flagging |
| Threshold style | positional [N] with regex validation | bash A/B limit; fan-in convention |
| Stacking | continue stack on feat/arch-mcp-server | items unmerged; doc sections append-only |

## Assumptions

- `compare_bodies` name lookup already uses a bound parameter (verify in Slice C before relying on FR-014).
- No metrics-gate impact: none of the new queries alter emitted metrics.

## Consensus Table

| Point | Voice 1 | Voice 2 (codex) | Status |
|---|---|---|---|
| 3 slices, fixture-first selftest | ✅ | ✅ (#4/#5 demanded it) | AGREE |
| Column-level feature detection | ✅ | ✅ (#2) | AGREE |
| CLI-side empty-body disambiguation | ✅ | ✅ (#6) | AGREE |
| Sort DIFFERS groups | (missed) | ✅ (#7) | AGREE — adopted |
| Stacked branch risk | accept | flag (#8) | AGREE (accepted, mitigated) |
| No USER-CHALLENGE | — | — | — |
