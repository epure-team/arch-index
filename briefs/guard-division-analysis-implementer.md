# Implementer Brief — guard-division-analysis

**Date:** 2026-09-13
**Status: VALIDATED**

Workdir MUST /home/mathias/dev/arch-index-worktrees/guard-division-analysis; not the default main checkout. Read /home/mathias/.codex/RTK.md; shell commands rtk proxy, local edits apply_patch. Preserve unrelated files. No additional worktree needed.

Before code, read specs/guard-division-analysis.md completely: this is the frozen normative behavior/output contract, not optional context. Plan controls decomposition/domain choice; spec controls exact observables. If contradictory, escalate rather than improvise. No user quiz or new approval needed within scope; never waive technical gates.

## Goal

Deliver experimental arch-guard as a separate OCaml library/CLI in this repository, without changing arch-index's extraction or existing rule verdicts. Read explicitly selected trusted compiler artifacts, inventory integer division/remainder operands, then use a bounded intraprocedural abstract interpreter to distinguish divisors known nonzero, known zero when reached, possibly zero, unreachable under the model, and unsupported. Measure useful precision on owned native fixtures and report the owned library honestly even if it has no target sites.

This is the approved roadmap's separate value-analysis experiment, not a vulnerability-hunting workflow. Semantic results apply only to recognized OCaml int primitives within the declared fragment/assumptions. No absence-of-bugs, guaranteed execution, machine-checked certificate, or whole-program completeness claim.

## Scope Boundary

Out of scope: existing database schema, lib/arch_index or lib/arch_tools behavior changes; rule allow-lists/reference edits; cross-language, array bounds, interprocedural summaries/call expansion, external project scanning, SMT/proof backend, editor/MCP/UI integration, automatic remediation and build/discovery of arbitrary projects.

V1 numeric domain handles OCaml int only, host Sys.int_size recorded. Other integer families remain inventoried but UNSUPPORTED. Loops, recursive evaluation, exception handlers, effects, mutation/heap reasoning and optional/default-argument semantics are not interpreted; sites in unsupported execution regions must stay UNSUPPORTED. Nested functions are separate entry contexts with unknown parameters/captures, never inheriting a branch's execution guarantee. No recursive unrolling or guessed loop bound.

## Relevant Files

Existing files read for contracts/patterns (read-only in this slice unless test integration named):
| File | Role | Key snippet |
|---|---|---|
| dune-project | compiler/dependency floor | (ocaml (>= 5.3.0)); cmdliner,yojson,digestif |
| lib/arch_index/arch_index_exn.ml | adjacent syntax identity, remain unchanged | Texp_ident ... Val_prim ... prim_name; original slot2 |
| lib/arch_index/arch_index_cmt.ml | CMT entry contract, remain unchanged | Cmt_format.read; Implementation structure |
| bin/arch_callgraph_ocaml/dune | CLI packaging pattern | public_name + libraries |
| tezt/lib/dune | generated CLI build dependency | target cli_paths.ml |
| tezt/tests/main.ml and dune | integration registration/build | module registration/test stanza |
| tezt/tests/decision_lint.ml | owned compiler fixture/report checks | with_project; run_command |
| scripts/origin-consumer.js | independent recurring baseline | status/reference comparison; no modifications |
| .github/workflows/ci.yml | existing full suite/self gates | build/test/self-index/recalibration/consumer |

New component paths to be frozen in plan: lib/arch_guard/, bin/arch_guard/, root arch-guard wrapper, tests/owned fixtures, checker, docs/arch-guard.md and README/CHANGELOG. No change to project-wide compiler floor; use installed dependencies where sufficient. If new dependency proves necessary, justify in plan, do not install globally.

## Architecture Notes

Operational choices under explicit standing autonomy:

1. Typed compiler primitive identity (Val_prim) distinguishes division/remainder from shadowed source operators. Cover the eight int/int32/int64/nativeint div/mod primitive identities for inventory. Partial application retains original operand slots and is unsupported, not an executed division.
2. Analyze direct native int div/mod sites, constants, immutable local variable bindings/aliases, sequencing, basic int arithmetic and pure if branches. At minimum recognize zero equality/inequality guards (including their compiler-resolved polymorphic identities at int type) and local binding shadowing using compiler identifier identity.
3. Numeric state must genuinely overapproximate values and support branch restriction and joins, with bottom distinct from top. Representation is a plan decision (interval/zero-exclusion or an equally expressive finite domain); required observations: literal2 and local alias2 become nonzero; an unguarded parameter remains possibly-zero; the nonzero branch of d=0/d<>0 becomes nonzero; branches yielding0/2 join to possibly-zero; contradictory constraints produce unreachable.
4. OCaml modular overflow is not C undefined behavior. Transfers must be conservative for both31/63-bit int semantics in unit-domain tests, while CLI declares host-width trusted-build assumption. Overflow may widen to top; never use unbounded-integer arithmetic to prove a wrapped result nonzero. Quotient/remainder abstract values may conservatively be top; precise min_int/-1 value modeling is not required. The zero-divisor classification must never execute a concrete division by zero.
5. Unknown ordinary calls return top; no call expansion. No heap facts retained. Immutable local scalar facts may remain; unsupported structural/effectful regions get explicit reasons. Syntax inventory is a separate complete pass over accepted CMT trees so the semantic pass cannot hide sites it cannot interpret.
6. CLI uses explicit repeatable CMT inputs (no recursive third-party search). Stable sorted text/JSON output; JSON carries schema/tool/compiler/int-width, input path+digest+module, artifact scope/counts, syntax site location/primitive/operand category, semantic status/reasons and census. Scope is artifacts provided, never all source code. Source location is compiler metadata; source-to-CMT freshness and target-width correspondence are trusted assumptions, not verified certificates.
7. Proposed status vocabulary: NONZERO, ZERO, MAY_ZERO, UNREACHABLE, UNSUPPORTED. ZERO means zero whenever the site is reached under the modeled conditions, not proof that the site executes. MAY_ZERO is potential, not a confirmed failure. Unsupported regions never yield NONZERO/UNREACHABLE. No matching sites yields an explicit empty inventory, not a safety claim.
8. This experiment is report-only: successful analysis exits0 even for ZERO/MAY_ZERO/UNSUPPORTED; command/input/internal error exits2 with diagnostics and no complete JSON. No silent partial report on unreadable/wrong-version/unsupported CMT annotation/midread change; do not overwrite user files (stdout only). CLI flags, closed output fields and resource bounds fixed by spec before code.
9. Repeated inputs are deduplicated by canonical physical path; distinct accepted artifacts with duplicate module/source identity are rejected rather than merged/count-inflated. CMT symlinks rejected. Hash before/after read to catch changed inputs; no adversarial filesystem atomicity claim. Accept only Implementation, explicitly diagnose interface/packed/partial/wrong compiler. No arbitrary build/execution triggered by CLI.
10. Measure fixture census against raw syntax: count each classification and added useful NONZERO/UNREACHABLE distinctions separately, unsupported denominator visible. Run tool on owned library artifacts and report zero sites honestly; do not broaden corpus to invent impact. Existing self-index golden and origin-consumer gates unchanged.

No claims authority/KB/hook installation exists. Keyword check on durable task text: trust-boundary false, critical true (proof wording). Operator selects trust-boundary yes for semantic-evidence consumer limits; Full already authorized. No critical backend inferred from heuristic. Formalization here is a specification plus deterministic tests, not formal verification.

## Quality Gates

All commands prefixed rtk proxy, cwd task worktree, no concurrent Dune on same tree.

- Build: opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
- Full suite: opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
- Whitespace: git diff --check (no separate configured formatter/full linter).
- Existing fresh self-index/golden; scripts/recalibrate.sh --check; arch-rules self --on-vacuous fail; arch-impact self; scripts/origin-consumer.js then artifact validator.
- New standalone checks must use0pass/1assertion/>=2execution mapping, built into Tezt: authentic compiled fixture CLI, conservative boundary/negative cases, numeric transfer/join laws and output/input contract. Exact CHECK commands frozen in spec.
- Domain tests: bounded exhaustive concrete-vs-abstract containment for small word widths plus31/63 extrema; join/idempotence/bottom/monotonicity controls, wrap-to-zero case and branch shadowing.
- Native fixtures compile with actual configured OCaml; test aliases, guards, branch joins, unknown calls, nested functions/captures, unsupported loop/try and integer families, shadowed operators, partial applications.
- Exact-head remote CI required before merge. Existing origin corpus and rules remain unchanged; no pin/reference automatic edits.

## Open Questions

None deferred to implementation. Representation and module layout are engineering choices within the required behavior, resolved in plan; flags/output contract/bounds and ambiguities are adversarially frozen in spec before implementation.



## Approved implementation decomposition

## Sequential steps

1. **Attributable inventory through the CLI.** TDD a compiled owned fixture through explicit CMT intake, complete primitive inventory, closed report and errors. Add library/CLI/wrapper, initial checker and Tezt registration together. Preserve unsupported inventory first, then enable later numeric capabilities. Finish native identity/slot/dedup/empty report and malformed-input tests before next slice.
2. **Constant and immutable-value classification through the CLI.** TDD native literals/aliases/parameters and arithmetic vectors. Add the domain and a test-only batch probe for an independent JS BigInt oracle. Constants/aliases yield required statuses; unknown calls remain top. All excluded regions already default unsupported. Full suite after this vertical increment.
3. **Guards and entry boundaries through the CLI.** TDD zero restrictions, branch joins, false/contradictory branches, shadowing, simultaneous binding groups and fresh nested functions. Add interpreter support while keeping sticky unsupported ancestry. Negative fixtures cover every excluded family and opaque-call arguments. Full suite after this increment.
4. **Auditable bounded report delivery.** Complete all exact/one-over limits, metadata anomaly, failure atomicity, format equivalence and checker assertion/error controls. Finish docs and actual owned-library census. Run all existing self gates unchanged, then independent roster review/QA, exact-head green PR and rebase merge. Clean only owned scratch/build/worktree after evidence is retained.

## Dependencies

1 precedes 2: raw census must remain independent of numeric interpretation. 2 precedes 3: restriction/join require an audited domain. 4 completes all integration and regression evidence, but tests and exclusions start in step1. These are internal TDD increments in one bounded PR, not separately shippable incomplete contracts.

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Domain | `Bottom | Const of int64 | Nonzero | Top`, explicit width parameter, public domain name `constant-zero-v1` | Smallest adequate nonrelational abstraction; constants represented safely at 31/63 signed widths. |
| Concretization | Bottom=empty; Const=singleton within signed width; Nonzero=all signed values except0; Top=all signed values | Makes precision and tests explicit. |
| Join | Bottom identity; same constant preserved; distinct nonzero facts -> Nonzero; zero plus nonzero -> Top; Top absorbing | Covers required0/2 and nonzero branches. |
| Restriction | equality0: intersect with{0}; inequality0: remove0; contradiction ->Bottom | Zero exclusion without intervals. |
| Arithmetic | Exact singleton result only when representable, checked before unsafe host operations; otherwise Top; div/mod result Top | Avoid host wrap or min_int/-1 assumptions; independent modular oracle verifies containment. Non-singleton arithmetic may return Top except Bottom propagation in domain API. |
| Entry state | Reachable flag separate from abstract value; fresh supported function resets reachable/env, preserves unsupported ancestry | Prevents accidental false unreachable from ignored expressions or captures. |
| Layout | Separate domain, CMT/inventory, interpreter and report modules under lib/arch_guard; public CLI under bin/arch_guard | Existing extraction libraries untouched, no new dependency required. |
| Tests | Standalone JS checker with six independent modes; native compiled fixtures and test-only OCaml batch probe; Tezt executes checks | Independent oracle without one process per numeric vector; no new public probe API. |
| Checker batching | Bound batches to captured-output/process limits; full small-width concrete pairs and non-singleton samples | Exhaustive small-width containment fits bounded processes; 31/63 extrema are supplementary samples. |

## Files

Create lib/arch_guard/ (domain, input/inventory, interpreter, report and interfaces/dune), bin/arch_guard/ (CLI/dune), arch-guard, tezt/fixtures/arch_guard/ (owned fixtures plus test-only probe/dune), tezt/tests/guard_division_analysis.ml, scripts/check-arch-guard.js, docs/arch-guard.md.
Modify only test integration tezt/lib/dune, tezt/tests/dune, tezt/tests/main.ml and README.md/CHANGELOG.md. Pipeline artifacts briefs/, roster/guard-division-analysis/, specs/guard-division-analysis.md and skills-meta/friction.jsonl are allowed. No existing lib/arch_index or lib/arch_tools changes, no CI/reference/allow-list changes intended.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| False nonzero from overflow | medium | high | Prechecked constants, Top fallback, independent BigInt oracle for complete represented input sets. |
| Unsupported/default/capture leakage | high | high | Inventory independent; unsupported-first; fresh function entry; nested negative fixtures. |
| Incomplete syntax traversal | medium | high | Full compiler traversal plus inventory-to-result reconciliation; defaults/unsupported still counted. |
| Compiler patch/magic assumptions | medium | high | Linked reader checks; exposed diagnostic granularity; trusted-build assumptions, no invented producer version. |
| Large fixture/control tests exceed process cap | medium | medium | Batch independent probe requests, avoid huge single stdout; deterministic bounded setup; record setup failures >=2. |
| Vacuous owned corpus | high | medium | Report measured0 honestly; fixture precision not Tezos impact. |
| Existing baseline perturbation | low | high | Separate component and unchanged self gates; no golden/reference rewrite. |

## Assumptions and validation

All voice1 product questions concern fields already frozen by the completed spec; no re-opened product ambiguity. Root selects domain under explicit autonomous engineering authority; neither voice asks to change direction. Source bound intake sha256 ef51fd545c3112823dda4aa42e09c92c5b33d08fad2f0fd24a8d07d9bbd274b8; neutral question manifest digest rechecked8056e06cda5882b53effb1218c03e2c6922a8e6f25a6356b58528048c721b5a0.
No installed claims reconciler/KB/hooks; no simulated checks. No new global installation. Human plan quiz/repeated validation replaced by standing autonomy, not represented as answers obtained. Exact technical gates remain mandatory.


## Exact quality gates

All commands cwd this task worktree. Never run concurrent Dune here. Capture terminal exit codes.

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
- `rtk proxy git diff --check`
- `rtk proxy node scripts/check-arch-guard.js inventory`
- `rtk proxy node scripts/check-arch-guard.js numeric`
- `rtk proxy node scripts/check-arch-guard.js domain`
- `rtk proxy node scripts/check-arch-guard.js inputs`
- `rtk proxy node scripts/check-arch-guard.js report`
- `rtk proxy node scripts/check-arch-guard.js owned`
- `rtk proxy node checks/origin-recurring-consumer.js authentic`, then failures and package modes separately.
- Fresh `rtk proxy node scripts/origin-consumer.js --out <new-owned-leaf>`, then `rtk proxy node scripts/origin-consumer-artifacts.js <same-leaf>`. Resolve a fresh owned parent with mktemp -d; never execute placeholders. Preserve compact evidence before removing owned DB/build scratch.
- Existing fresh self golden, `scripts/recalibrate.sh --check`, arch-rules self with --on-vacuous fail and arch-impact self: execute current CI commands unchanged during verification, record exact resolved paths/commands. No pin/reference/allow edits. Exact-head remote CI must independently pass before merge.

Standalone check exits0 pass/1 assertion/>=2 execution error. Tezt must also exercise deliberate assertion and execution controls. Every check mode sets up independently; authentic native fixtures cannot be replaced by static schema-only mocks. Limit tests can use test-only internal fixture/probe seams for inaccessible malformed typed trees and serialization boundaries, with actual CLI failure-path integration; disclose seam-only checks rather than claim CLI exercise where absent. No configured coverage-percentage target: report behavioral coverage honestly, do not invent percentage.


## Execution constraints

Root owns manifest/ACTIVE_TASK and baseline before source edits. Specialist implements OCaml first under roster-implement/TDD, then non-OCaml checker/docs integration. Test first must compile and fail on an actual assertion (missing binary/load failure alone is not RED). Use minimal no-feature stubs only to make the expected behavioral test executable, explicitly labeled scaffolding; do not count setup error as RED. Log each red/green and full suite terminal outcome. Full suite baseline before code, full suite after each semantic increment.

All selected spec obligations must be covered or explicitly reported as untested for review/QA, never silently downgraded. Do not move unsupported fencing to the end. A recognized site under an unsupported ancestor cannot be nonzero/unreachable even in if false. Unknown ordinary calls instead return Top and independently visit arguments. Public ID is perartifact preorder, not crossbuild fingerprint.

No database schema/existing extraction/rule or reference changes; no Tezos run in this slice. Preserve source/output paths and caller-supplied artifacts; no auto builds from CLI. Wrapper only dispatches built binary. Test-only probe not installed publicly. Never global tool installs or unrelated cleanup. Finish with compact evidence and completed implementation brief only after all required gates pass; root integrates/commits and routes independent review.

