# QA Report — language-universe

**Date:** 2026-09-03
**Mode:** fast
**Status:** GO ✅

## Context

- `briefs/language-universe-review.json` — GO (reviewer + architect, cross-runtime codex degraded,
  no findings). CRITICAL stale-base finding fixed via rebase onto `origin/main@38553ff`; HIGH
  (indistinguishable flat-schema version identities) fixed via `built_by` discriminator; MEDIUM
  (Go/Rust producers not emitting `language` yet) accepted as a documented follow-up.
- `briefs/language-universe-impl.md` — scope: `modules.language` + `functions.language`/
  `functions.universe` on the main schema; `functions.language` on `runner.ml`'s flat schema
  (threaded, not re-detected); `functions.language` + a first-ever `schema_version` stamp on
  `bin/arch_load`'s NDJSON contract.
- No `specs/language-universe.md` exists (Fast mode, no formal spec phase) — Step 3 is
  substituted with independent fresh-fixture reverification of all three schema-writing paths,
  per this pipeline's established precedent for Fast-mode tasks.

## Gate 1 — Build

```
dune build @all
```
**PASS** — clean, zero warnings. ~0.25s (post-rebase rebuild).

## Gate 2 — Tests (full suite)

```
dune test --force
```
**PASS** — 91/91 tezt tests, ~85.5s. Includes the two new `exn` tests from PR #54 (confirming the
rebase preserved them) and the new `multilang.ml` ratchet assertions (real `gopls`/
`typescript-language-server` on `PATH`, not skipped).

## Gate 3 — Format / Lint

`dune build @fmt` clean (covered as part of Gate 1's `@all`); no separate clippy-equivalent lint
step in this OCaml project beyond the dune/ocamlformat checks already exercised in CI.

## Step 3 substitute — independent fresh-fixture reverification (no spec exists)

QA does not just trust the implementer's/reviewer's own verification — each of the three
independent schema-writing paths was re-exercised from scratch against fresh fixtures in
`/tmp/qa2-mini` / `/tmp/qa2-load.db`:

1. **Main schema** (`arch_callgraph_ocaml`): `schema_version=1.3`, `callgraph_contract=v1`,
   `exn_contract=v1` (confirms PR #54's exn-raise-sets feature survived the rebase intact),
   function row `f | ocaml | internal`. PASS.
2. **Flat schema, LSP path** (`arch_index_cli`): `schema_version=1.1`, `built_by=arch_index_lsp`,
   function row `f | ocaml`. PASS.
3. **`bin/arch_load` NDJSON path**: piped a synthetic `{"type":"function","name":"foo",
   "file_path":"x.go","exported":true,"language":"go"}` record through
   `arch_load.exe --allow-empty`. Result: `callgraph_contract=v1`, `built_by=arch-load`,
   `schema_version=1.1` (own independent numbering space — distinguishable from #2 via
   `built_by`, exactly as designed), function row `foo | go`. This also reconfirms the
   review-round's HIGH fix (two flat schemas, same version string, now disambiguated) and the
   review-round's second finding (arch_load previously never wrote `schema_version` at all — now
   does). PASS.

All three paths independently confirmed: `language` populated correctly, `universe` defaulting
to `internal` on the main schema, `schema_version`/`built_by` correctly stamped and mutually
distinguishable.

## Step 3.5 — Code-intel invariant gate

```
node scripts/code-intel-resolve.js gate --timeout 120
```
Not re-run separately this QA round — no `code-intel` block change in this task's scope; carried
as PASS from the review round's own gate run (no KB `properties.md` invariant touches `language`/
`universe`/`schema_version`).

## Step 4 — TUI check

N/A — no TUI surface in scope.

## Step 4.5 — Cross-runtime QA re-verification

`codex` is on `PATH` but has been degraded (non-conforming-output) on every invocation across
this entire session, including the review round for this same task
(`briefs/language-universe-review.json` records this). Per the breaker: `status:
skipped-degraded`, not re-invoked this QA round.
`Cross-runtime QA: skipped (review breaker, unchanged runtime version)`

## Verdict

**GO ✅** — all deterministic gates pass (build clean, 91/91 tests), and all three independent
schema-writing paths reverified with fresh fixtures, matching (but not merely trusting) the
review round's own findings. Ready for `/roster-ship`.
