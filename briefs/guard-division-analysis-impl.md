# Implementation Brief — guard-division-analysis

**Date:** 2026-09-13
**Mode:** full
**Status:** COMPLETED

R1 corrective implementation complete under plan613d6e2. Product checkpoint
00f4df8acbab8174eb9142b6efecb7cc3f4ca5e2 is verified by pristine calibration;
this summary is not independent R2 review or QA GO. All seven R1 findings remain
in the review ledger until independently adjudicated.

## Modified files

| Paths | Change | Purpose |
|---|---|---|
| lib/arch_guard/, bin/arch_guard/, arch-guard | New private component/public CLI | Bounded OCaml divisor analysis, shared report context and escaped text paths |
| scripts/check-arch-guard.js, scripts/check-guard-report-context.js | Independent checks | Six modes, status-aware exact oracles and standalone context regression |
| tezt/fixtures/arch_guard/ | Private probes/fixtures | Native binding/entry/exclusion matrix; typed-tree malformed-input seams |
| tezt/lib/dune, tezt/tests/dune, tezt/tests/main.ml, tezt/tests/guard_division_analysis.ml | Integration | Eleven guard tests/checker invocations, exact runtime dependencies |
| tezt/tests/must_null_ceiling.ml | Earlier authorized calibration exception | Pin383→430; unchanged25 headroom/query/floor; no R1-correction pin edit |
| docs/arch-guard.md, README.md, CHANGELOG.md | Documentation | CLI-only public boundary, private library, contract and limitations |
| briefs/, specs/guard-division-analysis.md, roster/guard-division-analysis/, skills-meta/friction.jsonl | Pipeline/evidence | Scope, decisions, full output and reproducible checks |

Existing lib/arch_index, lib/arch_tools, database/schema, rules, golden and origin
references are unchanged by this feature. Earlier checkpoints68e77df/fae9243 and
R1 evidence remain history, not overwritten.

## Decisions made

Constant-zero-v1 retains Bottom/Const/Nonzero/Top, explicit payload width and
conservative overflow. Syntax inventory stays independent of interpretation;
unsupported ancestry is sticky and every function entry resets local numeric
state. Compiler identifiers distinguish binders. No numerical-domain redesign.

The only supported public v1 surface is the installed CLI/root wrapper. The
implementation library is private, rather than offering an in-process compiler
global-state restoration guarantee. Both formats project every shared assumption
and limitation, including indirect operations and omitted artifacts.

Root integration found that raw newline paths violated FR-043. A maintained
positive actual-CLI RED preceded minimal JSON-string escaping in text; JSON schema
and classifications are unchanged. An expected-failure replacement was rejected.
Wrong-reason and missing/duplicate text-field negative controls exercise the same
oracle; numeric statuses reject exclusion reasons. Unsafe max-column decimals
come from the explicitly constructed fixture, not a fabricated generic coordinate.

Native R1 cases add36 sites with exact expectations. Malformed application/type
and effect identities use disclosed private Typedtree seams, not claims about
native compiler output. Two selector defects were caught by real RED and an
independent post-mutation observer; mutation flags alone had been insufficient.

## Quality gates

All shell commands use rtk proxy, compiler-backed commands additionally use
opam exec --switch=/home/mathias/dev/arch-index --, cwd the active worktree.

- Full dune build --root .:0. @install alone is insufficient for whole-repo ratchet.
- Root dune test --root . --force after final edits:0,256/256Tezt and64Alcotest,
  complete correction-full-suite.log retained.
- All six independent guard modes, standalone context check and three origin
  checker modes:0. Assertion/execution controls1/2; correction-checker-modes.jsonl.
- Domain640734 actual probe responses,23219242 law assertions, exhaustive widths3–8
  and sampled31/63 extrema. Executable evidence, not machine-checked proof.
- Native original12-site fixture and26 numeric cases preserved; R1 native36 sites:
 19 numeric covered,6NONZERO,2ZERO,11MAY_ZERO,17UNSUPPORTED,precision gain6.
- Fresh self golden exact23modules/828functions/5223calls. Origin producer and
  artifact validator0,held UNKNOWN,zero drift; correction-self-summary.json.
- Self rules0:one proved,threeUNKNOWN,zero failures. No improvement claimed.
- Pristine committed00f4df8 recalibration0: golden23/828/5223 in all four cells;
  ceiling A=B396,C=D437; current pin430 within unchanged25 headroom. Source-only
  movement, no extractor behavior delta; correction-recalibration.log.
- Self impact at00f4df8 against77c7691:0,zero indexed functions touched,100 files
  outside index UNKNOWN; effects/decision not computed. Not zero semantic impact.
- Whitespace and manifest scope gates0; review bundle22SHA verified1.6.0.
- Supplemental opam lint remains exit1 pre-existing non-gating packaging debt.
  Optional odoc absent. No metadata changes, dependency installation or hidden PASS.

## Points of attention for review

Independently revalidate all47FR/19AC and six CHECKs, the pending standalone
ratchet, private installation boundary, exact oracle sensitivity and malformed
seam selectors. R1 seven finding IDs must be preserved until verified closure.
Full independent fan-out is required because visible report/public boundary changed.
Cross-runtime R1 non-conforming output was discarded; honor same-cycle breaker.

## Ratchet

- finding: lib/arch_guard/arch_guard.ml:213:spec#cd378d70
- check: scripts/check-guard-report-context.js (new self-contained file)
- red command: rtk proxy node scripts/check-guard-report-context.js
- pre_fix_sha: d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec
- check_encodable: true
- evidence: actual empty/classified CLI RED1 before production edits; integrated
  suite RED1 only new context test failed. Actual archive verifyCheck later0:
  red_verified=true, check_blob8108aa657905871c8693120bb3168ce40b9d6c0f,
  current GREEN, not weakened. Root final standalone0. Independent R2 gate must
  verify and promote numbered CHECK/AC before clearing the CRITICAL finding.

## Identified out-of-scope

No Tezos scan or measured production gain. No whole-program safety, guaranteed
execution, source freshness, formal certificate, heap/interprocedural analysis or
functor specialization. Owned arch-index corpus has23artifacts and genuinely
zero matching sites. Next roadmap slice remains bounded functor instantiation.
Only owned temporary verification artifacts are cleaned; unrelated worktrees,
main dirt and local cost telemetry are preserved.
