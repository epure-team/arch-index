# Implementation Brief — guard-division-analysis

**Date:** 2026-09-13
**Mode:** full
**Status:** COMPLETED

The status and gates below describe the pre-R1 implementation checkpoint, not the
current correction. R1 review is NO-GO; corrective implementation is now running
under plan613d6e2 and must replace this summary with fresh evidence before completion.

## Ratchet

- finding: `lib/arch_guard/arch_guard.ml:213:spec#cd378d70`
- check: `scripts/check-guard-report-context.js` (new self-contained file)
- red command: `rtk proxy node scripts/check-guard-report-context.js`
- pre_fix_sha: `d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec`
- check_encodable: true
- current evidence: actual CLI RED exit1 on empty and classified missing text compiler
  context before production edits; integrated full-suite RED exit1, only the new
  check failed (255 other Tezt +64 Alcotest pass). Minimal report/package correction
  then passed256Tezt+64Alcotest. Actual archive helper RED/GREEN verified0 with blob
  8108aa657905871c8693120bb3168ce40b9d6c0f; evidence correction-context-ratchet.json.
  Final fixture/oracle correction and independent R2 still pending.

## Modified files

| Paths | Change | Purpose |
|---|---|---|
| lib/arch_guard/, bin/arch_guard/, arch-guard | New component | Separate bounded OCaml divisor analysis and report-only CLI |
| scripts/check-arch-guard.js, tezt/fixtures/arch_guard/, tezt/tests/guard_division_analysis.ml | New checks/probes | Independent concrete oracle, native fixtures, contract boundaries |
| tezt/lib/dune, tezt/tests/dune, tezt/tests/main.ml | Test integration | Build and execute ten new guard tests/checker modes |
| tezt/tests/must_null_ceiling.ml | Authorized calibration exception | Pin383→430, unchanged25 headroom/query/floor |
| docs/arch-guard.md, README.md, CHANGELOG.md | Documentation | Experimental contract and limitations |
| briefs/, specs/guard-division-analysis.md, roster/guard-division-analysis/, skills-meta/friction.jsonl | Pipeline artifacts | Scope, decisions and reproducible evidence |

Product checkpoint68e77df61c68f811331180abfc25293911b2f955; calibration fae9243.
Existing lib/arch_index/lib/arch_tools, database/schema, rules, golden and origin references unchanged.

## Decisions made

Constant-zero-v1 uses Bottom/Const/Nonzero/Top with explicit word width and conservative
overflow. Syntax inventory is independent from interpretation; unsupported ancestry is sticky,
function entries reset local state, compiler identifier identity distinguishes shadowing.
CMT environment reconstruction uses only the linked compiler standard library.
Changed-read testing uses a private shared-reader seam, not a public probe or timing-race claim.
Installed CLI error atomicity is tested separately. See native TDD notes and
independent-checker-progress.md for authentic RED/GREEN and corrected test expectations.

User continuation resolved the previous excluded-pin blocker with one narrow amendment.
ratchet-source-growth.md attributes every additional call: all396 baseline rows preserved,
34 new rows in four new files. Independent Terra attribution review agrees; not formal QA.
Old383 pin lagged baseline396; new430 measures the full branch corpus. No extractor change.

## Quality gates

Commands ran in this worktree, compiler-backed commands under
`opam exec --switch=/home/mathias/dev/arch-index --` (shell prefix `rtk proxy`).

- Full `dune build --root .`: exit0. @install alone is insufficient for whole-repo ratchet.
- `dune test --root . --force`: exit0,255/255Tezt and64Alcotest.
  Retained final-full-suite.log; all six guard checkers and both failure controls executed.
- Numeric evidence:12 native inventory sites plus26 additional cases;640734 actual domain
  responses and23219242 law assertions. Deterministic testing, not machine-checked proof.
- `env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check`:
  committed fae9243, exit0; golden23/828/5223 in all cells; ratchet A=B396,C=D430,pin430.
- Fresh self index: golden23modules/828functions/5223calls byte-identical; origin producer
  and artifact validator exit0,held. All origin checker modes also pass in full suite.
- Self rules exit0: one proved,threeUNKNOWN,zero failures. No precision improvement claimed.
- Self impact against77c7691436a716bfec503e22f1649a4303179fcc..HEAD: exit0,
  zero touched indexed functions,66 changed files outside index UNKNOWN; effects and
  decision analysis not computed. Not a claim of zero semantic impact.
- `git diff --check` and `bash scripts/check-scope-diff.sh briefs/guard-division-analysis-manifest.txt`: exit0.
- Review bundle preflight:22 SHA verified,version1.6.0. No separate configured formatter.

## Points of attention for review

Audit actual compiler primitive/type identity, unsupported ancestry, alias patterns,
modular arithmetic, exact resource boundaries, output buffering and domain oracle independence.
Private changed-read seam evidence must not be described as a live filesystem race test.
All47FR/19AC require independent review; implementation completion is not review/QA GO.

## Identified out-of-scope

No Tezos scan or measured production precision gain. No whole-program safety, source freshness,
formal certificate, interprocedural reasoning or functor specialization delivered here.
Owned arch-index library census is genuinely empty for divisor sites; do not generalize it.
Next roadmap slice remains bounded functor instantiation. No unrelated worktree cleanup.
