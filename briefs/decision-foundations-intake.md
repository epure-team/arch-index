# Intake Brief — decision-foundations

**Date:** 2026-08-02
**Status:** VALIDATED (autonomous run)
**Type:** feature
**Roadmap:** lot 1 of the decision-analysis roadmap
(`docs/research/mcdc-coverage-feasibility.md` R1, R2)

## Goal

Land the two recommendations the feasibility study ranked cheapest and highest
value-per-line, and which are — measurably — still not done after the PoC work:

**R1 — make the compiler's redundancy warnings explicit.** No `dune` file in the
tree carries a `flags` stanza, so warnings 8 (inexhaustive match), 11 (unused
match case), 26/27 (unused let/variable) are promoted to errors only by dune's
*implicit* dev-profile default. That guarantee vanishes under `--profile
release` and would vanish again if the default changed. Warning 11 is the
compiler's own version of this whole feature — it proves a `match` arm is
unreachable — and it already caught a duplicated case during PoC development.
Make it explicit and profile-independent.

**R2 — stop discarding statically-unreachable blocks.** `Arch_index_cfg.solve`
computes `reachable` per block; `Arch_index_cfg.reachable` is exported, asserted
on by `test/test_cfg.ml`, and has **zero production consumers** — the sole
indexing call site (`arch_index_cmt.ml`) reads `always_exec` alone. Every call
recorded in an entry-unreachable block is statically dead code *with a source
location*, and the indexer throws that away.

**Value:** R2 turns an existing internal invariant into a shippable query with no
new analysis. Both were identified in the study's ranked plan as S-cost, and both
have sat undone while the expensive tiers (SMT, second frontend) were built.

## Scope Boundary

Explicitly OUT of scope:

- Decision/condition persistence (`decisions`, `conditions` tables) — lot 2.
- The NDJSON producer contract extension (R9) — lot 3.
- The Go backend: it has its own `alwaysExec` but emits through `arch-load`,
  whose wire format cannot carry these fields until lot 3.
- The purity join (`v_pure_functions`) — later lot.
- Any change to edge-kind semantics or to `reaches`/`unreachable`.
- Fixing warnings the new stanza may surface elsewhere: the stanza must be added
  at a strictness the tree already satisfies, not used as a refactor trigger.

## Relevant Files

| file | role |
|---|---|
| `lib/*/dune` | R1: add the explicit `flags` stanza |
| `lib/arch_index/arch_index_cfg.mli` | `reachable` — the verdict being surfaced |
| `lib/arch_index/arch_index_cmt.ml` | `collect_calls_from_expr` — where the verdict is computed and dropped |
| `lib/arch_index/arch_index_db.ml/.mli` | insertion path |
| `architecture-schema.sql` | new `dead_code_sites` table + view |
| `arch-query` | new `dead-blocks` subcommand |
| `test/fixtures/self-index-stats.txt` | golden, regenerate per ADR 001 if counts move |

## Design Decisions

**Why a table of SITES, not of blocks.** A CFG block has no source location —
it is an int index over a graph built by the walker. A *call* recorded in an
unreachable block does have one (`call_site`). "This call at `file:line` can
never execute" is actionable; "function F has 3 unreachable blocks" is not. So
the unit of record is the dead call site, keyed to its function.

**Soundness direction.** A block is dead only if entry-unreachable in the CFG the
walker built. Constructs the walker does not model degrade to opaque
straight-line nodes (FR-006), which keeps them reachable — so the analysis
under-reports dead code and never over-claims. That is the correct direction for
a finding whose action is "delete this".

**Not a gate.** Like the R8 mutability metrics, this is reported and queried,
never used to fail CI in this lot. Ratcheting is R4, a later lot, and only after
a baseline exists and has been triaged.

## Quality Gates

- `dune build` green under **both** dev and release profiles (R1 must not break
  release).
- `dune test` green (42 tests / 4 suites).
- `selftest-contract`, `selftest-load`, `selftest-callgraph-ocaml`,
  `selftest-effects` green.
- `STRICT=1 selftest-callgraph-soundness` green with `P1: 57 passed, 0 failed`.
- Self-index golden regenerated deliberately per `docs/adr/001-self-index-golden.md`
  if and only if counts move, with the reason recorded in the commit.
- `arch-query <db> dead-blocks` returns without error on a main-schema DB and
  **refuses with an explicit message** on a flat DB that lacks the table — the
  capability-reporting rule (study §8.4): a clean result on a backend that
  computed nothing must never look like a clean result.

## Acceptance Criteria

- AC-1: every library `dune` carries an explicit `flags` stanza promoting
  warnings 8/11/26/27 to errors, and `dune build --profile release` stays green.
- AC-2: a call recorded in an entry-unreachable block is persisted with its
  function and its `call_site`.
- AC-3: `arch-query <db> dead-blocks` lists those sites, module-qualified.
- AC-4: on a DB whose producer did not compute them, the subcommand refuses
  rather than printing an empty table.
- AC-5: no existing query, verdict, or edge kind changes.
