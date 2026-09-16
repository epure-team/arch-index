# Implementation Report — ocaml-cfa-propagation

**Mode:** full  
**Implemented SHA:** `b5a52f312b693b0e9facaa890b137cfda25f8a22` plus the pending round-3 correction  
**Status:** COMPLETED

## Delivered behavior

- Extended the finite inclusion domain with typed uncertainty and finite residual
  values, including late target/reason/residual activation and clone isolation.
- Made CMT-session finalization exception-atomic and every mutator reject use after
  finalization.
- Added same-CMT, context-insensitive actual-to-formal and normal-return-to-physical-
  application-result propagation for the explicitly supported callable grammar.
- Added all-simple recursive groups, exact immutable lexical captures and finite
  `(callable, consumed-leading-slots)` residuals for staged applications.
- Preallocated every residual identity before solving and queued watcher
  notifications iteratively, so long activation chains do not recurse on the
  native stack.
- Predeclared supported local mutual-recursion groups, retained CFA occurrence
  tokens for directly staged heads, and kept overapplication callback-open
  instead of leaking the raw function-valued return.
- Preserved direct edges as authoritative, CFA-derived targets as `MAY_ENUMERATED`,
  and independent callback frontiers without duplicate CFA rows.

## Modified product and test files

The implementation changes the CFA domain/session and CMT collector under
`lib/arch_index/`, extends `test/test_cfa.ml`, adds the authentic
`tezt/fixtures/ocaml_cfa/{higher_order,metadata}.ml` fixtures, and extends
`tezt/tests/{ocaml_cfa_foundation,local_recursion_targets}.ml`. Self-index reference updates are justified
by `roster/ocaml-cfa-propagation/self-reference-evidence.md` and reproduced by
`roster/ocaml-cfa-propagation/calibrate-self.js`.

## Verification evidence

- `opam exec -- dune build --root .`: exit 0.
- `opam exec -- dune test --root . --force`: exit 0; 345/345 Tezt scenarios and
  all OCaml test suites passed.
- CHECK-1: exit 0; 517 finite-domain oracle cases.
- CHECK-2: exit 0; authentic main/flat/metadata/identity/consumer controls.
- CHECK-3: exit 0; pinned 410-input Tezos corpus, Irmin 4849→4919, protocol
  12171→12427, 326 relation gains, zero relation losses and zero new `MUST`.
  Canonical rows are 45052→45287 (114 removed, 349 added); producer observation
  was 3587 ms and 156056 KiB sampled RSS.
- Self-reference 2×2 calibration: the current engine adds two calls on the old
  corpus and six calls while removing one on the current corpus, with no origin
  changes attributable to the engine. Two post-correction runs have identical
  totals and call/origin digests.

## Scope and residual limits

No cross-CMT resolution, functor/member matching, mutable or aggregate capture,
optional/default/destructured formal support, returned-callable overapplication,
query redesign, storage migration or whole-program completeness claim was added.
No new worktree was created and the seven pre-existing foreign paths in the
manifest remain untouched.

## Review round-1 ratchet

Round 1 was `NO-GO` with seven findings: residual identities allocated during
solve; an over-broad recursive-group admission predicate; recursively invoked
watchers; late registration of mutual local binders; loss of the CFA token for
a directly staged application head; raw-return leakage on overapplication; and
CHECK-2 misclassification of the new assertion families.

All seven are corrected. Permanent coverage includes pre/post residual-identity
counts, a 20,000-cell iterative watcher chain, mixed supported/unsupported
recursive groups, direct staged heads, local mutual recursion, downstream
overapplication, mixed-arity metadata and controlled propagation/recursion/
capture/setup classifier exits. The single runnable ratchet is
`roster/ocaml-cfa-propagation/check-review-fixes.js`; it exits 0 after running
the native domain regressions, authentic CHECK-2 and its 0/1/2 exit controls.
The original reviewed tree was dirty, so no automatic clean-SHA RED claim is
made; the round-1 findings and their reproducing assertions remain the manual
RED evidence. No finding was waived and no contract was relaxed.

## Review round-2 ratchet

Round 2 confirmed all seven earlier findings resolved and found one new HIGH:
the collector registered a CFA occurrence for a supported simple-let head such
as `(let chosen = target in chosen) x`, but `record_head` discarded its token and
persisted `MAY_TOP`. Authentic CMT coverage reproduced the failure with zero
bounded targets and one callback frontier. The marker branch now retains
`Texp_let` occurrences; the same test observes exactly one `MAY_ENUMERATED`
target and no callback frontier. Unsupported let shapes remain open in the CFA
expression evaluator.

Post-correction verification is green: full suite 345/345, CHECK-1 517 cases,
authentic CHECK-2 and its 0/1/2 controls, the combined review ratchet, and
pinned-410 CHECK-3. The corpus result is unchanged at Irmin +70, protocol +256,
326 gains, zero losses and zero new `MUST`; the observed producer run was
13682 ms and 156076 KiB. Two fresh self-index 2×2 runs have identical totals
and digests at 27 modules, 1143 functions, 7066 calls and 614 origins.

Round 3 then exposed the broader invariant behind the direct-head fix: the
common dispatcher supported `Texp_let`, while the root and local computed-value
admission lists did not, and the direct regression lacked a flat assertion. A
shared `supported_computed_value` classifier now drives all three admission
sites. Authentic direct/root/local rich+flat positives and a destructured-let
negative reproduced six pre-fix failures and now pass without widening the
supported let grammar. The friction log's out-of-vocabulary classes were also
remapped to the closed Roster vocabulary.

Post-correction verification is green again: full suite 345/345, CHECK-1 517
cases, authentic CHECK-2 plus its exit controls, and the combined review
ratchet. Pinned-410 CHECK-3 now records Irmin 4849→4921 (+72) and protocol
12171→12441 (+270), for 342 relation gains, zero losses and zero new `MUST`.
Canonical rows are 45052→45290 (127 removed, 365 added); the producer run took
3188 ms with 156020 KiB sampled RSS. Two fresh self-index 2×2 runs agree at 27
modules, 1143 functions, 7066 calls and 614 origins with identical digests.
