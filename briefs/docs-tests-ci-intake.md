# Intake Brief — docs-tests-ci

**Date:** 2026-06-25
**Status:** VALIDATED
**Type:** chore

## Goal

Clean up the arch-index repo so it is self-contained, easy to onboard from, and has reliable
automated quality gates. Three sub-goals:

1. **README** — rewrite as a short focused landing page (~1 screen). Move detailed content
   (edge-kind contract, schema reference, soundness rationale) into linked `docs/` files.
   Use Mermaid diagrams where they clarify data flow or architecture (e.g. producer → arch-load
   → SQLite → arch-query pipeline).

2. **Tests** — the repo has 4 shell integration tests (`selftest-*.sh`) but zero OCaml unit tests.
   The CI `dune test || true` silently swallows failures. Add OCaml unit tests for the library
   core (comment parser, DB schema, edge-kind contract enforcement). Ensure `selftest-*.sh` run in
   CI without needing a real LSP server for the contract/load selftests (which are already
   self-contained).

3. **CI + self-application** — fix the `|| true` suppression, wire `selftest-contract.sh` and
   `selftest-load.sh` (no external deps) into CI, and add a self-indexing step: arch-index indexes
   its own OCaml source and `arch-query stats` reports a plausible function count (≥ 10 functions,
   ≥ 1 call edge) — demonstrating end-to-end correctness on the repo itself.

## Scope Boundary

Out of scope:
- `selftest-callgraph-go.sh` and `selftest-callgraph-ocaml.sh` in CI: both require a running
  LSP server (gopls / ocamllsp) and a warm-up period — too fragile for CI without significant
  infrastructure work. They stay as local developer selftests.
- Rewriting or refactoring OCaml library logic (this is docs/tests/CI only).
- Adding new arch-index features (new query types, new language backends, etc.).
- Changing the binary build pipeline (`build.sh`, `_build/`).

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `README.md` | Main landing doc — to be shortened | 10.2K; contains edge-kind table, schema, install, usage — all to be split out |
| `SPEC-sound-callgraph.md` | Existing detailed spec | 10.5K — link from README, keep as-is |
| `architecture-schema.sql` | DB schema reference | 19.3K — link from README |
| `.github/workflows/ci.yml` | CI definition | `dune test \|\| true` silently ignores test failures |
| `selftest-contract.sh` | Contract layer selftest | Self-contained (sqlite3 only) — can run in CI |
| `selftest-load.sh` | Loader selftest | Self-contained (python3 + sqlite3) — can run in CI |
| `selftest-callgraph-go.sh` | Go end-to-end selftest | Requires gopls — local only |
| `selftest-callgraph-ocaml.sh` | OCaml end-to-end selftest | Requires ocamllsp — local only |
| `arch-index` | Wrapper: builds index DB | Shell; invokes `bin/arch_index_cli` |
| `arch-query` | Wrapper: queries index DB | Shell; SQLite queries + edge-kind contract logic |
| `arch-load` | Loader: NDJSON → SQLite | Shell or binary; enforces edge-kind contract |
| `lib/arch_index/` | OCaml library — main source | No test files exist today |
| `lib/arch_index/arch_index_db.ml` | DB schema / write helpers | Key target for unit tests |
| `lib/arch_index/comment_parser.ml` | Doc comment extraction | Key target for unit tests |
| `lib/arch_index/arch_index_cmt.ml` | CMT-based call extraction | 35.8K — complex, test selectively |
| `dune-project` | Build config | `(lang dune 3.13)`; no test stanza yet |

## Architecture Notes

**Pipeline** (relevant for Mermaid diagram in README):
```
Source code
  → LSP server (gopls / rust-analyzer / ocamllsp / …)
  → arch_index_cli (OCaml binary)
  → SQLite DB (comment_db schema)
  → arch-query (shell script → sqlite3 queries)
```
Or via Tier-0/1 producers:
```
Source code
  → arch-callgraph-go / arch-callgraph-ocaml (Tier-1 CMT producer)
  → NDJSON stream
  → arch-load
  → SQLite DB (⊤-marked, callgraph_contract flag set)
  → arch-query (sound unreachability queries)
```

**Edge-kind contract** (⊤-marking): `calls.kind ∈ {MUST, MAY_ENUMERATED, MAY_TOP}` — this is the
core correctness invariant. `selftest-contract.sh` and `selftest-load.sh` already test it well;
they just need to run in CI.

**Self-indexing**: arch-index can index its own OCaml source using `ocamllsp`. In CI, a simpler
approach is to use `arch-callgraph-ocaml` (CMT-based, no live LSP needed after `dune build`) on
the compiled `_build/` output.

## Quality Gates

```bash
# Build
opam exec -- dune build

# OCaml unit tests (to be added under lib/arch_index/test/ or inline)
opam exec -- dune test

# Shell integration tests (self-contained — no LSP)
./selftest-contract.sh
./selftest-load.sh

# Self-indexing smoke test (post build)
./arch-callgraph-ocaml _build/default/lib/arch_index/ /tmp/self.db
./arch-query /tmp/self.db stats
# Expect: functions ≥ 10, calls ≥ 1

# Lint/Format
# Not documented — note: `dune fmt` can enforce ocamlformat; not currently configured
```

## Decisions (validated by user)

- **OCaml test framework**: use **both** — `ppx_inline_test` for fast inline unit tests on pure
  functions (comment parser, DB helpers); `alcotest` for named integration-style test suites
  that need richer failure output. Add both to `dune-project` deps.

- **Self-indexing in CI**: use `arch-callgraph-ocaml` on the `_build/` CMT output produced by
  `dune build`. This requires Go in the CI runner — add a `setup-go` step to `ci.yml`. Smoke
  test: `arch-query /tmp/self.db stats` must report ≥ 10 functions and ≥ 1 call edge.

- **`docs/` split**: three files:
  - `docs/edge-kind-contract.md` — edge-kind / ⊤-marking / soundness rationale
  - `docs/schema.md` — DB schema reference (link to `architecture-schema.sql`)
  - `docs/install.md` — LSP backend install instructions per language
  Keep `SPEC-sound-callgraph.md` as-is.

## Open Questions

_(none — all resolved above)_
