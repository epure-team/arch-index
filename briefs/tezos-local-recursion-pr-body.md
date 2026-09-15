## Summary

- Resolve exact same-CMT self-calls in singleton local recursive function literals to their observed, stored bodies as MAY_ENUMERATED.
- Keep unsupported groups, non-head references, flat extraction, callers/effects and legacy overapplication residuals unchanged; no new MUST or general 0CFA.
- On the pinned410 Tezos corpus: +68 Irmin / +111 proto_alpha target relations, zero losses or unexplained changes. Four self-reference updates have pristine source-only attribution, without policy relaxation.

## Test plan

- [x] Four new native Tezt tests: exact identity/exclusions, real storage refusals, flat compatibility.
- [x] Three personal roster reviews and main final QA: build,340/340 tests, CHECK1–6; review and QA convergence pass.
- [x] Compiler-native witness replay for181 changed heads;179 gained relations;45052 canonical rows preserved; zero new MUST, lost relation or removed legacy TOP residual.
- [x] Rich preservation coverage strengthened after review caught omitted type/dependency/reexport families and vacuous mutation/deref controls.
- [ ] Required GitHub CI green on the exact PR head before guarded rebase merge.

## Evidence and limits

See `briefs/tezos-local-recursion-review.json`, `briefs/tezos-local-recursion-qa.md` and `roster/tezos-local-recursion/`.

First QA stalled in the unchanged TypeScript polyglot test. The unchanged focused reproduction and one complete QA retry passed; the NO-GO remains in the audit and the intermittent LSP cause is not claimed fixed. OpenCode cross-runtime output was non-conforming and discarded, not accepted as a pass. No formatter/coverage gate is configured; global legacy-spec claims parsing remains unavailable.

Native tests run in normal CI. Raw fixed410 Tezos/baseline/calibration evidence is local and pinned; corpus-specific checkers are not portable standalone CI gates. This is iteration4 of the approved5, not a claim of complete defunctorization.
