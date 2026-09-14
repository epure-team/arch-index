# Attempt4 selection — documentary, not a retained gain

Three of the existing five approved product iterations shipped via PR105–107.
No reset: two iterations remain. Product main05e4a8a; local delivery record82c5a81.
Existing unrelated files and held PR93 remain outside scope.

## Loop1 — single local recursive function invocations

- Objective: improve exact call-target resolution in Tezos Irmin and protocol.
- Why now: current collector traverses local binding RHSs before registering their
  compiler stamps (`arch_index_cmt.ml:1946–1973`). Real self-calls to single local
  `let rec aux` literals remain callback_param TOP in retained data: Irmin unix/io.ml
  bindings28/39, calls32/44; tree.ml alist_iter2 binding33, calls41/45/48.
- Confidence: medium
- Writable scope: lib/arch_index/arch_index_cmt.ml; task-native Tezt and roster,
  spec/brief artifacts; exact self-reference refresh only after pristine attribution
  if independently required; external roadmap and existing loop results.
- Read-only context: fixed410 Tezos CMTs/source, previous baselines/checkers,
  docs/edge-kind-contract.md, current callgraph tests, held PR93.
- Metric: additional independently witnessed ordinary call-site target relations
  versus retainedIrmin4781/protocol12046, with zero lost retained relations.
- Verify: NOT YET AVAILABLE — distinct PR107 baseline and per-occurrence witness
  must be prepared before any product edit; census is not a gain verifier.
- Guard: `opam exec -- dune exec tezt/tests/main.exe -- --no-color`
- Max iterations: 2 (remaining allocation of user's exact5, overriding template3–5;
  this proposal selects attempt4 only and does not combine speculative changes).
- Risk: medium
- Keep rule: positive verified gain, zero loss/unexplained movement/new MUST,
  full roster and guard pass, exact-head required green CI then rebase merge.
- Discard rule: neutral/worse metric, wrong targets, unexplained preservation
  changes or unresolved guard failure; preserve all unrelated work.
- KB basis: none; repository graph contracts, tests and exact compiler artifacts.

## Recommendation

- Best starting loop: Loop1, after full roster setup.
- Why: exact local compiler binder and already-promoted body, unlike genuinely
  symbolic functor parameters, first-class log modules or external linkage gaps.
- Missing setup: neutral research, fresh baseline, contractual spec, independent
  native witness, actual assertion RED and deterministic whole-corpus comparator.

Boundary proposed for specification: singleton local Recursive Texp_let only,
plain variable pattern and direct function literal. Self invocation heads only;
no mutual groups, wrappers/aliases, non-head escapes or global recognition widening.
No new MUST. Existing literal naming/collision ordinals must remain unchanged:
the actual observed body identity is required, not a guessed/pre-allocated name.
Preserve arity/partial/overapplication, stored-body availability and every old
CFG/effect/flat fact outside explicitly admitted transitions/residuals.

Terra independently confirmed the sequence and native source/DB examples.
Its initial suggestion to seed the ordinary lambda table would affect non-head
occurrences and possibly introduce MUST; main rejects that shortcut under the
existing loop contract. This is a research proposal, not final design approval.

Current canonical corpus was reconstructed from immutable PR106 baseline plus
PR107 counted removals/additions:45052rows, exactdigest9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e.
The retained changes.json after_positioned has only370 delta-local rows, not the
whole corpus; it must not be used as a global census. Irmin itself was unchanged
in PR107. Its55 callback_param rows named aux are prospecting counts only.

## Tool Opportunities

[TOOL] Compiler-native singleton-recursive-binder occurrence witness — replaces
name/location guessing with exact binder, owner and stored-body evidence.
Trigger: candidate verification. Output: counted admitted pairs or refusal.
