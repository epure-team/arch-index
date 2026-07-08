# QA Brief — selftest-effects-failure

**Date:** 2026-07-09
**Status:** GO ✅

## Environment (load-bearing)

All gates run under the project's **local opam switch**, not the shell default:
```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
```
The default `octez-setup` switch ships an older eio/cohttp-eio/mirage-crypto-rng; building
under it fails with unrelated API errors (`_ Eio.Flow.source` arity, `Cohttp_eio.Server.respond_string`,
`Mirage_crypto_rng_unix.use_default`). Verified identical on clean `main` → environment
artifact, not a code defect and not introduced by this branch.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build` | ✅ PASS | <2s |
| Tests | `dune test --force` | ✅ PASS (all Alcotest suites, incl. capability_db 17, parsers 10) | <1s |
| selftest-effects | `./selftest-effects.sh` | ✅ PASS (the fix under test) | ~2s |
| selftest-contract | `./selftest-contract.sh` | ✅ PASS | <1s |
| selftest-load | `./selftest-load.sh` | ✅ PASS | <1s |
| selftest-callgraph-go | `./selftest-callgraph-go.sh` | ✅ PASS | ~1s |

## Tests: detail

- New tests added: 0 (fix validated by the existing end-to-end `selftest-effects.sh`).
- Existing tests: all pass, no regressions.
- Behavioral check (encoded by selftest-effects.sh): on a CMT-built OCaml index,
  `pure-fns` no longer reports the fixture mutators as pure, and `effects-of` surfaces
  `FieldAccess` + `HashTbl` — i.e. the qualified-vs-unqualified join now matches.

## Cross-runtime QA

Second runtime: **codex** (`codex exec --sandbox workspace-write`), instructed to use the
local switch and independently re-run all gates. Verdict: **GO**. All 5 gates exit 0, no
disputed claims. codex note: "All gates passed using the local opam switch. selftest-effects.sh
passed and reported effects fixture coverage, confirming the pure-fns/effects-of behavioral
check." No discrepancy with the primary run.

## Out-of-scope pre-existing failure (documented, not a blocker)

`selftest-callgraph-ocaml.sh` fails on clean `main` (verified identical, RC=1) — NOT touched
by this branch and NOT in the CI gate set. It has two independent layers:
1. Assertion `name LIKE '%.add'` assumes qualified names (trivial pattern bug).
2. **Real issue:** `arch-callgraph-ocaml` in main-schema mode emits `calls.kind = NULL` and
   sets no `callgraph_contract` meta flag, so every edge-kind soundness verdict
   (`reaches`/`unreachable`/`escapes`) and the edge-kind integrity check fail.

Fixing (2) is a producer soundness feature in `arch_index_cmt` — a separate task, deliberately
not folded into this effects fix. Logged as a follow-up.

## Verdict

**GO** — ready for `/roster-ship`.
