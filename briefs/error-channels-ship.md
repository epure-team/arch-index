# Ship — error-channels

**Date:** 2026-09-04
**PR:** https://github.com/epure-team/arch-index/pull/60
**Branch:** `feat/error-channels` → `main`, 42 commits, 57 files, +9137/−106
**Merge:** NOT performed — the human merges.

## Gate evidence

| Gate | Result |
|---|---|
| Review | GO (round 3, full fan-out; no CRITICAL, no novel HIGH) |
| QA | GO (round 1, no qualifying causes) |
| Build | exit 0 |
| Tests | 126/126, exit 0 |
| arch-rules | 4 rules, 0 failing |
| Self-index golden | diff empty |
| Schema version | base 1.7 → 1.8, exactly one `docs/schema.md` row |
| `runner.ml` / `exn_raise_sets.ml` | zero-diff vs origin/main |
| Frozen exception channel, octez-manager | 12317 / 3024 (24.6%) / 47.6% / 491 / 2245 — exact |
| Frozen exception channel, proto_alpha | 14452 / 3436 (23.8%) / 46.4% / 19 / 35 — exact |

## Carried forward as follow-ups (user-selected, all four)

1. `arch-coverage-matrix` has no `error_channels` row, so it is silent about whether this analysis
   ran. Data already exists (`comment_db_meta.error_contract`). Agreed with the roadmap session
   that this is mine.
2. NDJSON record types for the `exn_*` rows — the prerequisite for any non-OCaml producer. Until
   then a Flat database answers `NOT_ANALYSED`, which is correct, but it blocks the porting
   contract this PR documents.
3. Module-qualified addressing for `may-fail`/`raises`. 540 of 14452 proto_alpha names are shared;
   every verdict carries only the bare name. **Pre-existing** — `raises` has resolved names this
   way since PR #54. Must be coordinated with the roadmap session's qualified-name work.
4. An or-pattern spanning the whole arm (`Error A | Error C`) closes nothing, where the same
   intent inside the constructor closes both. Sound direction, real precision loss; the exception
   channel already flattens arm-level disjunctions and the value channels do not.

## Coordination

Sequenced with the roadmap session (roadmap 1.6, qualified-name resolution): it rebases onto this
after a human merges, not onto the local merge commit. Its spec now carries an identity-diff gate
over `exn_origins.exn_path`, `exn_scope_catches.exn_path` and `exn_rebinds`, because error
identities are canonical qualified paths — a resolver change can move identity strings while
counts hold, silently changing what `fails-with` returns.
