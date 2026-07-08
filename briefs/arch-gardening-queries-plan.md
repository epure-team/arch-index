# Plan — arch-gardening-queries

**Date:** 2026-07-08
**Status:** VALIDATED (autonomous; Voice 1 inline, Voice 2 codex — 6 objections, all adopted; quiz waived per user pre-authorization)

## Sequential steps

1. **Slice A — query branches (fixture-only data)** — hoist the `hq_*` helpers out of the health case branch to script-level functions (objection #6 — shared, not duplicated); add `low-coverage [N=50]` (latest-record via `MAX(recorded_at)` subquery), `gardening [open|log]`, `unsafe-params [unfixed|fixed|all]`; extend `selftest-health.sh` fixture with coverage (two snapshots for one fn), tasks (3 statuses), ledger rows — no loader needed to test queries (objection #1). Done: CHECK-1.
2. **Slice B — arch-coverage-load** — `bin/arch_coverage_load/` + wrapper: BEGIN/COMMIT transaction; malformed → ROLLBACK all + exit 2, no summary (objection #4 semantics: skips before an abort still warned on stderr, but zero rows persist); `--stamp` validated strict UTC `YYYY-MM-DDTHH:MM:SSZ` else exit 2 (objection #2 — lexicographically sortable); resolution contract explicitly lossy: exactly-one candidate row after name(+module) filter else skip (objection #3, documented); written/skipped/ignored summary; refuse exit 3 without functions/modules/coverage. Alcotest suite + selftest scenarios. Done: CHECK-2/3.
3. **Slice C — docs + drift-proofing** — `docs/curation-workflow.md` with fenced ```sql blocks between `<!-- selftest:begin/end -->` markers; selftest EXTRACTS those exact blocks (awk) and executes them (objection #5 — no copied fixture); README + arch-query header. Done: CHECK-4/5.

## Dependencies
A → B (fixture baseline) → C (docs reference both). Branch stacks on feat/arch-health-queries.

## Identified risks

| Risk | P | I | Mitigation |
|---|---|---|---|
| latest-record SQL subtly wrong | M | wrong verdicts | dedicated two-snapshot selftest case; strict UTC stamps |
| lossy name resolution surprises | M | silent data gaps | skips loudly counted + documented contract |
| helper hoist breaks health branches | L | regressions | selftest-health re-run is the gate |
| doc-SQL extraction fragility | L | CI flake | fixed markers + awk between them; fail loudly if zero statements extracted |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Slice order | queries first w/ fixture data | objection #1 |
| Stamp format | strict `YYYY-MM-DDTHH:MM:SSZ` | objection #2 |
| Resolution | exactly-one-match else skip | objection #3 |
| Abort semantics | rollback-all, no summary, exit 2 | objection #4 |
| Doc drift | execute extracted fenced SQL | objection #5 |
| Helpers | hoist hq_* to script level | objection #6 |
| Loader language | OCaml (intake open question) | id resolution + validation is logic; effects-load precedent |

## Consensus Table
All six Voice-2 objections adopted (AGREE after adjustment); no DISAGREE, no USER-CHALLENGE.
