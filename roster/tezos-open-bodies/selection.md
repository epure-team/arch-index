# Attempt 3 selection — documentary, not a retained result

Two of five product attempts delivered (PR105/106). This selects the next
focused change within the same loop, not a new five-iteration loop.

## Loop 1 — lexical-open function bodies

- Objective: improve exact compiler-identity call-target resolution on fixed410.
- Why now: independent compiler-libs census finds63 wrapped function binders and
  344 Pident applications in protocol;181 target the exact step binder at
  script_interpreter.ml:637. arch_index_cmt.ml:883 only recognizes direct
  Texp_function RHS. This count includes local definitions and is not a gain bound.
- Confidence: medium
- Writable scope: lib/arch_index/arch_index_cmt.ml; bounded consumer correction
  only if independently required; task-specific Tezt/roster/spec/brief artifacts;
  external roadmap and existing loop results. Exact manifest frozen at planning.
- Read-only context: fixed410 manifest/CMTs, Tezos checkout, previous attempt
  baselines/comparators/reviews, existing call/value/effect contracts, held PR93.
- Metric: additional independently witnessed ordinary call-site target relations
  versus retained4781Irmin/11730protocol, with zero lost retained relations.
- Verify: `node roster/tezos-open-bodies/verify.js` — NOT YET AVAILABLE; do not
  execute a product improvement until distinct baseline and admission tests exist.
- Guard: `opam exec -- dune exec tezt/tests/main.exe -- --no-color`
- Max iterations: 3 (remaining allocation of existing approved5; no reset).
- Risk: medium
- Keep rule: positive verified gain, no unexplained graph movement or lost
  relations, all roster/guard gates pass, exact-head greenCI then merge.
- Discard rule: no gain, false target, unaccounted effects/value movement or
  unresolved guard regression; preserve unrelated user work.
- KB basis: none; repository compiler/callgraph contracts and regression tests.

## Recommendation

- Best starting loop: Loop1, as the next focus inside the current loop.
- Why: concrete local compiler binders and syntactic function bodies. Other large
  residual clusters involve external includes (ret_succ_adding234), computed
  partial applications (storage pack/unpack), or genuinely unknown parameters;
  those need different contracts and are not bundled here.
- Missing setup: independent per-occurrence witness, frozen PR106 predecessor
  with neutral replay, native RED tests, new spec and exact manifest. This is
  not yet an execution-ready product proposal; setup is within approved scope.

## Native documentary evidence

`census.ml` links compiler-libs only, traverses all410 unchanged CMTs, identifies
Texp_open chains ending in Texp_function and counts Pident applications by the
same Ident.unique_name within each CMT. Actual run exit0.63bindings/344applications,
0Irmin bindings. Output `improvement/2026-09-14-tezos-resolution/attempt3-open-census.tsv`,
SHA256 b4335dc9c22df9e1f816d25046fcc7f4b33fbc5a27e66e6d253f7e11cbc0af69.
Every observed open is Tmod_ident, not computed module. No arch-index helper
linked, no output used as witness admission, no product change. Owned temporary
probe source/binary/compiler artifacts removed after execution; no worktree.

Important boundary: an arbitrary local-open module expression can have effects;
the fact that these63 use paths is not permission to erase arbitrary opens or
to change root-body attribution, optional-parameter effects or returned values.

Fresh Terra read-only design check plus main DB inspection confirms Raw.step's
callable body is the pre-existing synthetic node Raw.step.<fun:639:5>, which owns
460 outgoing calls. Target that identity without moving its calls; do not simply
widen the old body-only classifier. See design-investigation.md for the proposed
application-only, structural-binding, single-path-open scope and flat boundary.
This design note is not a review GO or an implementation plan.
