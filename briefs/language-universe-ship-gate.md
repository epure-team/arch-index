# Ship Gate — language-universe

**Date:** 2026-09-03
**Mode:** fast

## Commits prepared

```
33aa832 feat(schema): functions.language + functions.universe (roadmap 1.1)
cf47d64 fix(schema): distinguish the two flat-schema writers via built_by (HIGH)
```

Branch: `feat/language-universe`
Target: `main`
Base: rebased onto `origin/main@38553ff` (post PR #54) after the review round's CRITICAL finding.

## Pipeline summary

- **Review:** GO (`briefs/language-universe-review.json`) — reviewer + architect, cross-runtime
  codex degraded (no findings contributed all session). Both independently found and fixed the
  same CRITICAL (stale branch base — rebased). architect also found 1 HIGH (fixed — `built_by`
  discriminator) and 1 MEDIUM (accepted follow-up — Go/Rust producers don't emit `language` yet).
- **QA:** GO (`briefs/language-universe-qa.md`) — build clean, 91/91 tests. No spec exists (Fast
  mode); substituted independent fresh-fixture reverification of all three schema-writing paths
  (main schema, `runner.ml` flat schema, `bin/arch_load`), each confirmed correct and mutually
  distinguishable via `built_by`.
- Re-verified immediately before this ship: build clean under the correct `arch-index` opam
  switch, 91/91 tests again. `@fmt` reports one pre-existing diff (`lib/arch_index/dune`,
  `bin/arch_body_compare/dune` argument-list wrapping) — confirmed present on `main` HEAD too,
  not introduced by this task, not a blocker.

## What this feature does

Tags every indexed function/module with its source `language` (`"ocaml"`, `"go"`,
`"typescript"`, …) and adds a `universe` flag (`internal`/`external`) to `functions` — the
foundation the roadmap's Phase 1 coverage-matrix and boundary-edge items build on. Three
independent schema writers touched: the main CMT-based schema, `runner.ml`'s LSP-based flat
schema, and `bin/arch_load`'s NDJSON loader (which also gets its first-ever `schema_version`
stamp — a previously undiscovered instance of issue #51's silent-drift bug class).

## Authorization

Per the user's standing instruction ("travaille en autonomie, tu as le droit de merger tes PRs
SSI elles ont passé toutes les phases du pipeline roster") — review GO + QA GO both hold, full
pipeline passed. Proceeding to push, open PR, and merge autonomously once CI is green, without
pausing for further confirmation.
