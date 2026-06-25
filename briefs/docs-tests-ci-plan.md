# Plan — docs-tests-ci

**Date:** 2026-06-25
**Status:** VALIDATED

## Sequential Steps

Steps are ordered by dependency. Each step is independently completable and reviewable.

**Step 1 — Add test framework deps to dune-project and arch-index.opam**
- Add `ppx_inline_test`, `ppx_assert`, `alcotest` to `(depends ...)` in `dune-project`
- Add same to `arch-index.opam`
- Confirm `lib/arch_index/dune` can accept `(inline_tests)` + `(pps ... ppx_inline_test ppx_assert)` without conflicting with existing `ppx_blob` / `ppx_deriving_yojson` ppx chain
- Completion criterion: `opam install --deps-only --yes .` succeeds with new deps; `dune build` still passes

**Step 2 — Write inline unit tests for `comment_parser.ml`**
- Pure string-processing module, no IO, no sqlite3 — cleanest target
- Add `(inline_tests)` to `lib/arch_index/dune`; add `ppx_inline_test ppx_assert` to the pps list
- Cover: `@pre`/`@post`/`@violators` tag extraction, `make_body` edge cases (`"none"`, `""`, `Present`), `score` field extraction
- Note: there are two comment parsers (`comment_parser.ml` and `arch_index_comment_parser.ml`); target both with `let%test` blocks in their respective files
- Completion criterion: `dune test` runs and passes with at least 5 test assertions per parser

**Step 3 — Write inline unit tests for `arch_index_db.ml` (happy paths only)**
- `arch_index_db.ml` uses `Sqlite3` and `exec_exn` calls `exit 1` on SQL errors — error path tests would kill the test runner
- Use `(inline_tests)` only (inline in the lib stanza — `arch_index_db` is a private module, unreachable from an external `test/` stanza)
- Tests use an in-memory SQLite DB (`:memory:`) to avoid filesystem side effects
- Cover: schema creation, function insert/read roundtrip, calls insert, `comment_db_meta` write/read
- Skip all error paths — no refactoring of `exec_exn` (out of scope)
- Completion criterion: `dune test` passes with ≥ 4 happy-path assertions

**Step 4 — Add alcotest integration test suite for arch-load contract**
- Create `test/` directory with a `dune` stanza: `(test (name test_contract) (libraries arch_index alcotest) ...)`
- Note: this only works for non-private modules. `arch_index_db` and `arch_index_cmt` are private; only `arch_index` public surface is testable from here
- Write alcotest tests that exercise the `arch_index` public API (the top-level module) against an in-memory DB, validating edge-kind enforcement behavior (MUST / MAY_ENUMERATED / MAY_TOP round-trips)
- Completion criterion: `dune test` runs alcotest suite and reports named test cases

**Step 5 — Fix `dune test || true` in CI**
- Remove `|| true` from `.github/workflows/ci.yml`
- This step runs AFTER steps 2–4 so there are actual passing tests; removing it before that means any future breakage silently passes
- Completion criterion: `dune test` exit code is honored in CI

**Step 6 — Wire `selftest-contract.sh` and `selftest-load.sh` into CI**
- Add a `Shell tests` CI step after `dune test`
- Confirm both scripts are executable and `arch-query`, `arch-load` are available without a compiled binary (they are shell scripts)
- `selftest-load.sh` requires `python3` — confirm available on ubuntu-latest (yes, pre-installed)
- `selftest-contract.sh` requires `sqlite3` — confirm available on ubuntu-latest (yes, pre-installed)
- Completion criterion: CI step exits 0 on both selftests

**Step 7 — Build `arch-callgraph-ocaml` in CI and run self-indexing golden test**
- Add `setup-go` action to CI workflow (pin to the version in `callgraph-go/go.mod`)
- Add a `Build arch-callgraph-ocaml` CI step: `(cd callgraph-go && go build -o ../arch-callgraph-ocaml-bin ./...)` or equivalent
- Run self-indexing: `./arch-callgraph-ocaml _build/default/lib/arch_index/ /tmp/self.db`
- Run `./arch-query /tmp/self.db stats > /tmp/self-stats.txt`
- **Golden file**: on first passing run, commit `test/fixtures/self-index-stats.txt` as the golden
- CI check: `diff test/fixtures/self-index-stats.txt /tmp/self-stats.txt`
- **ADR**: create `docs/adr/001-self-index-golden.md` documenting the golden file policy and how to update it (run locally, verify, commit)
- Completion criterion: CI step passes; golden file committed; ADR present

**Step 8 — Write `docs/` files**
- `docs/edge-kind-contract.md`: extract edge-kind table, MUST/MAY_ENUMERATED/MAY_TOP semantics, soundness rationale from current README and `SPEC-sound-callgraph.md`
- `docs/schema.md`: reference to `architecture-schema.sql` with a brief description of the `functions` and `calls` tables; link the SQL file for full schema
- `docs/install.md`: LSP backend install instructions per language (go/rust/ts/python/ocaml), currently in README
- `docs/adr/` directory: home for ADRs (populated by step 7)
- Completion criterion: 3 docs files + ADR created; all cross-links work on GitHub

**Step 9 — Rewrite README**
- Target: ≤ 1 screen (~50 lines max, excluding Mermaid diagrams)
- Include: 1-paragraph project description, two Mermaid pipeline diagrams (LSP path + CMT path), quick-start usage (3–4 commands), links to `docs/install.md`, `docs/edge-kind-contract.md`, `docs/schema.md`, `SPEC-sound-callgraph.md`
- Remove: everything else (edge-kind table, schema details, install instructions per-language, soundness rationale)
- Mermaid diagrams: use `graph LR` syntax for the two producer pipelines
- Completion criterion: README renders correctly on GitHub; all `docs/` links resolve; README is ≤ 50 lines of prose + diagrams

## Dependencies

- Step 2 and 3 must precede Step 5 (tests must exist before removing `|| true`)
- Step 7 must precede golden file commit (need a real run to establish baseline)
- Step 8 must precede Step 9 (README links to docs/ files)
- Steps 1–6 are independent of Steps 8–9 (docs work can be parallelized with test work)

## Identified Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `ppx_inline_test` conflicts with existing `ppx_blob`/`ppx_deriving_yojson` pps chain | Medium | High | Test the pps addition in Step 1 before writing any test code; fall back to separate `ppx_driver` stanza if needed |
| `arch_index_db.exec_exn` calls `exit 1` — kills test runner on error paths | High | Medium | Only test happy paths (decided); document this limitation in the test file |
| `_build/` CMT path layout changes with dune version bumps | Medium | High | Verify exact path on first CI run; pin the path in the CI step; golden file catches regressions |
| Go binary (`arch-callgraph-ocaml`) build path in CI is unverified | Medium | High | Step 7 explicitly builds from source; verify `callgraph-go/` has a `go.mod` |
| Golden file diff is too sensitive (fails on cosmetic output changes) | Low | Medium | ADR documents update procedure; easy to update if intentional |
| Mermaid diagrams in README rot over time | Low | Low | Diagrams cover stable pipeline shape, not internals; acceptable risk |

## Decisions Made

| Point | Decision | Reason |
|---|---|---|
| Test layout for private modules | Inline tests inside `lib/arch_index/` | `(private_modules)` blocks external `test/` stanza for `arch_index_db`/`arch_index_cmt` |
| `arch_index_db` error paths | Skip — happy paths only | `exec_exn` calls `exit 1`; refactoring is out of scope |
| Self-indexing threshold | Golden file diff + ADR | Provides real regression protection without an arbitrary number |
| ADR location | `docs/adr/` | Standard location; scales to future ADRs |
| Test frameworks | `ppx_inline_test` (inline) + `alcotest` (integration) | User decision; binding rule: private/internal modules → inline tests; public `arch_index` API surface → alcotest |
| `arch_index_cmt.ml` testing | Skip unit tests | 35.8K, complex, requires CMT fixture files; shell selftests cover it adequately |

## Assumptions

- `callgraph-go/` contains a valid `go.mod` and `arch-callgraph-ocaml` can be built from it in CI
- `arch-query` and `arch-load` are pure shell scripts with no dependency on the compiled OCaml binary
- ubuntu-latest CI runner has `python3`, `sqlite3`, and a recent-enough Go pre-installed (will also add `setup-go` for correctness)
- `arch-query stats` output format is stable enough to golden-file
- `lib/arch_index/dune` currently lists `(private_modules ...)` — inline tests are the correct solution
