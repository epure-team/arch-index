# Plan — ocaml-cfa-foundation

**Date:** 2026-09-16
**Status: VALIDATED**

Routine plan quiz and execution gate delegated by explicit user authorization.
No human answers fabricated. Decomposition source: validated intake only; spec
consulted for status gate, not mined to invent work.

## Sequential steps

1. **Alias-to-query vertical slice** — Test first: a root f, a=f, b=a and a
   separate run calling b; preserve predecessor alias facts and static calls.
   Build the minimal private finite kernel, per-CMT session/ownership, deferred
   heads and main/flat integration needed to make that real fixture pass.
   Completion: actual f identity in main MAY_ENUMERATED, faithful flat mapping
   or explicit unknown where its representation is insufficient; finite-domain
   tests and existing suite pass. No standalone-kernel-only delivery.
2. **Literal/join-to-query slice** — Add branch and sequence result transfers,
   authoritative physical literal reconciliation, and mixed known/opaque
   contributions end-to-end. Completion: multiple actual targets plus surviving
   unknown frontier, equal-position/shadow/capture refusals tested in both paths.
3. **Occurrence preservation and qualification slice** — Exercise arity, partial,
   conditional/dead occurrences, scopes/channels, residuals and point-free
   predecessor invariants; update only obsolete supported-form expectations.
   Add independent standalone checks and pinned Tezos before/after comparison,
   documentation and final serial full gates. Completion: every in-scope
   behavior tested and every corpus relation delta explained, not necessarily gain.
4. **Roster review → QA → ship** — Independent review and QA, fix in scope,
   exact-final-head required CI green, guarded rebase merge. Only then stage3.

## Dependencies

Each slice is end-to-end and keeps both producers in scope. Kernel/session
scaffolding is a dependency inside slice1, not an independently shipped horizontal
layer. Slice2 depends on slice1 actual identity publication; slice3 qualifies
the integrated subset. All three slices form one stage2 PR.

## Consensus Table

| Point | Sol | Terra | Status |
|---|---|---|---|
| Separate numeric guard from target domain | agree | agree | AGREE |
| Per-CMT ownership + authoritative literal names | required | required | AGREE |
| Preserve unknowns and occurrence metadata | required | required | AGREE |
| Main/flat integration and pinned corpus | required | required | AGREE |
| Presentation mostly horizontal | eight layers | six layers | AGREE: root groups into vertical slices without changing dependencies/scope |
| Resource-limit policy unclear | question | question | AGREE: no arbitrary cutoff or new public configuration; finite closure, explicit failure if any implementation limit is declared |

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Two traversals disagree on names/ownership | high | wrong target | physical identity, collector notification, refusal tests |
| Flat has weaker identity/proof vocabulary | high | wrong homonym | preserve namespace; explicit unknown on unrepresentable identities |
| Mixed frontier or residual silently erased | high | false absence | occurrence-level assertions; independent solver oracle |
| Golden source-growth churn | high | masks regression | measured attribution, frozen corpus, no policy weakening |
| Accidental capture/recursive transfer | medium | unsupported closure | owner boundary and unsupported fixtures |
| Full suite cost | high | slow feedback | serialize, targeted RED then full GREEN gates, no duplicate build worktrees |

## Decisions and assumptions

No generic shared guard library, public embedding API, schema vocabulary extension,
full proof chain or stage3/4 behavior. Existing provenance fields are used, with
exact specification limiting claims. No configured solver cutoff is assumed.
Both voices asked implementation-seam/match/identity questions already answered
by research and validated contract; no direction reversal or material unresolved
user choice remains. Plan does not independently reinterpret those answers.

## Files

```text
lib/arch_index/arch_index_cfa.ml
lib/arch_index/arch_index_cfa.mli
lib/arch_index/arch_index_cfa_cmt.ml
lib/arch_index/arch_index_cfa_cmt.mli
lib/arch_index/arch_index_cmt.ml
lib/arch_index/arch_index_cmt.mli
lib/arch_index/call_graph_extractor.ml
lib/arch_index/dune
tezt/tests/ocaml_cfa_foundation.ml
tezt/tests/local_value_targets.ml
tezt/tests/callgraph_soundness.ml
tezt/tests/dune
tezt/tests/main.ml
tezt/fixtures/ocaml_cfa/
test/test_cfa.ml
test/dune
docs/edge-kind-contract.md
roster/ocaml-cfa-foundation/
```

Pipeline artifacts: briefs/, this task's spec, skills-meta/friction.jsonl.
Source-growth reference files are NOT automatically permitted: if gates require
changes outside this list, present measured attribution and obtain scope authority.

## Quality gates

```sh
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
rtk proxy node roster/ocaml-cfa-foundation/check-domain.js
rtk proxy node roster/ocaml-cfa-foundation/check-cmt.js
rtk proxy node roster/ocaml-cfa-foundation/check-tezos.js
```

No configured independent formatter/linter/coverage gate. CHECK3 requires the
external pinned corpus: unavailable is >=2, never green; native CI must not
depend on external checkout. All checks implemented with 0 pass/1 assertion/
>=2 setup-error semantics. No package installation or unnecessary worktree.
