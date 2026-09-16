# QA Brief — ocaml-cfa-propagation

**Date:** 2026-09-16T19:06:00+02:00
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1; `qa_no_go_round` is 0/5 and there are no causes or
escalations.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---:|
| Build | `opam exec -- dune build --root .` | ✅ PASS | 0.30 s |
| Tests | `opam exec -- dune test --root . --force` | ✅ 345/345 | 329 s |
| Format/lint | No standalone command documented by the validated QA scope/intake | N/A (recorded skip) | — |
| CHECK-1 | `node roster/ocaml-cfa-propagation/check-domain.js` | ✅ 517 cases | 1.48 s |
| CHECK-2 | `node roster/ocaml-cfa-propagation/check-cmt.js` | ✅ PASS | 25.93 s |
| CHECK-3 | `node roster/ocaml-cfa-propagation/check-tezos.js` | ✅ PASS | 4.94 s |
| Review ratchet | `node roster/ocaml-cfa-propagation/check-review-fixes.js` | ✅ PASS | 27.88 s |
| Setup control | `EPURE_ARCH_INDEX_TIMEOUT_S=1 node roster/ocaml-cfa-propagation/check-cmt.js` | ✅ expected exit 2 | 1.54 s |

CHECK-3 selected all 410 pinned inputs and measured Irmin 4849→4921 (+72)
and protocol 12171→12441 (+270): 342 relation gains, zero relation losses,
zero new `MUST`, 45052→45290 canonical rows, 3078 ms producer wall time and
156116 KiB sampled RSS. These are structural measurements, not a soundness or
completeness claim.

## Behaviors validated

- Lifecycle rejection, exception-atomic finalization, finite reasons/residuals,
  iterative propagation and direct/mutual recursion passed CHECK-1.
- Shared root/local/head grammar, arguments, returns, exact captures, staged
  partial flow, mixed arity and metadata passed authentic rich/flat CHECK-2.
- Direct/root/local supported lets each resolve exactly in rich and flat
  projections; the destructured-let negative remains callback-open.
- CFA edges remain `MAY_ENUMERATED`, direct edges remain authoritative, and the
  pinned Tezos corpus gains relations without losing an existing relation or
  introducing a new `MUST`.
- A partial LSP timeout is now a setup error (exit 2), not eight false CFA
  assertion failures.
- The diff contains no Stage-4 functor correspondence, Stage-5 query redesign,
  storage migration or backend replacement.

## Tests: detail

- New or strengthened regression assertions: 15 (14 rich/flat let-admission
  assertions plus one timeout-classification ratchet).
- Existing Tezt scenarios: 345 pass, 0 skip, 0 fail.
- Regression detected: NO.

## Claims and code-intel

- Claims reconciliation: skipped; no reconciler is installed in this project.
- Code-intel gate: skipped (no `kb/properties.md` / code-intel block).

## TUI

Not applicable: the validated QA scope declares no TUI scenario.

## Cross-runtime QA

Skipped by the shared breaker: OpenCode was already degraded during review and
its runtime digest is unchanged (`opencode:76f897c73342fdbf`).

## Verdict

**GO** — ready for `/roster-ship`.
