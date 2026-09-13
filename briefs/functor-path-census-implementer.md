# implementer — functor-path-census

**Status: VALIDATED**

Implement only roster/functor-path-census/{probe.ml,run.js,check.js,fixture.ml,README.md,report.json} plus pipeline artifacts. Read the intake and full plan. Native test-first, actual assertion RED then minimal GREEN. No production edits. Root controls baseline; implementation build ownership transferred explicitly.

# Plan — functor-path-census

**Date:** 2026-09-13
**Status: VALIDATED**

## Sequential steps

1. Native fixture and independently authored checks, executable stub then actual
   assertion RED. Freeze a version1 JSON contract before implementing.
2. Standalone OCaml probe: exact real collect results plus catalogue callback
   bijection, two-pass identities, complete terminal Path syntax, root category.
   GREEN native checks; no product file edits.
3. Node wrapper: strict manifest and pre/post hashes, exact checkout staging,
   temp-only probe builds, per-unit CRC inventory, validated output; negative
   cases and deterministic semantic replay. GREEN, then fixed410 corpus twice.
4. Independent interpretation, full existing gates, round commit, roster review,
   QA, exact-head CI/PR rebase merge, roadmap and owned-artifact cleanup.

One internal measurement deliverable, not horizontal product layers.

## Consensus Table

| Point | Sol | Terra | Status |
|---|---|---|---|
| Real API/ordinal bijection | required | required | AGREE |
| Artifact-local identities | required | required | AGREE |
| Named-unit presence is not ownership | required | required | AGREE |
| Fixtures and negative/replay controls | required | required | AGREE |
| Scope: internal measurement only | retained | retained | AGREE |

No USER-CHALLENGE or unresolved direction disagreement. Sol's additional generic
failure cases are risks to assess, not new product features.

## Decisions made

- version1 report: provenance plus artifacts array in manifest order, applications
  in ordinal order. Each application has ordinal/status/reason; unsupported rows
  additionally retain location, terminal path tree/display, applied-head depth,
  root key/name/category and path identity class. All other outcomes retained for
  denominator checks.
- Artifact key is exact manifest path, unique across slices. Row key is
  (artifact,ordinal). Ordinals are local to one decoded structure, checked against
  both existing APIs. Do not merge compiler identities across decoded CMTs.
- Root categories: persistent_unit, named_functor_parameter,
  bound_rhs_structure/alias/application/functor/unpack, unknown_nonpersistent,
  applied_or_extra_path. Last category has no asserted root key.
- Preserve all Path constructors recursively; extra type variants are encoded
  explicitly. Peel module constraints and literal apply/apply_unit while keeping
  application depth; full terminal path syntax is not a normalized owner.
- Path.same assigns within-artifact equivalence classes in ordinal order.
  Display distinct counts and artifact-scoped identity-class counts are separate.
- Unit inventory compares exact cmt_modname, without normalization; duplicates
  reported as multiple candidates. Record cmt_imports CRCs and interface digest,
  never load a CMI or infer member ownership.
- Location uses existing location_json (including ghost), not rewritten source
  positions. No source freshness claim.
- Build existing arch-index normally before probe compilation. Probe compiler
  inherits explicitly selected OCaml5.3 environment; package arch-index comes from
  exact _build/install/default/lib staging via OCAMLPATH, archive digest retained.
- Probe builds and fixtures only in owned mkdtemp. Wrapper never creates a worktree.
  One clean implementation worktree is permitted for isolation from existing
  user files; removed with its normal build after landing.
- Invalid input: nonzero, stderr diagnostic, no new success JSON report. Preserve
  any preexisting output; never overwrite unrelated reports. Success publication
  only after all validation. Before/after checks are not atomic snapshot proof.
- Replay compares semantic measurement payload separately from binary/provenance
  fields that may contain temporary build-dependent identity.
- Roadmap: /home/mathias/notes/2026-09-01-arch-index-roadmap.md.

## Quality gates

Existing: explicit opam switch /home/mathias/dev/arch-index.
dune build --root .; dune test --root . --force; node scripts/review-bundle-verify.js;
git diff --check; bash scripts/check-scope-diff.sh briefs/functor-path-census-manifest.txt.
New:
opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-path-census/check.js
opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-path-census/run.js --manifest roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv --out roster/functor-path-census/report.json
Replay uses a new owned output and compares semantic payload; no fixed corpus in CI.
Check command self-generates its native CMTs; no Tezos requirement for local checks.
No formatter/coverage instrumentation configured; no invented percentage.

## Identified risks

Ordinal drift: exact independent fixture counts and API bijection.
Display conflation: repeated/shadowed fixture plus Path.same groups.
Partial report: validate everything before exclusive creation.
Source drift: digest checks before/after, limits explicit.
Unusual compiler syntax: encode recursively, reject undecodable artifacts.
Selected corpus bias: all claims explicitly410-only.

## Assumptions

Environment decode is established for prior collector; full census still tested.
No dependency installation required. Ghost locations retained, unknowns explicit.
Native fixture need not synthesize impossible module-head extra-type syntax;
constructor handling still explicit, any unexercised branch disclosed.
Standing autonomy covers routine plan quizzes; no answers fabricated.

