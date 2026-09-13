# Intake Brief — guard-division-analysis

**Date:** 2026-09-12T20:03:50.963Z
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

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

- Build: opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . (full corpus build, including installation targets)
- Full suite: opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
- Whitespace: git diff --check (no separate configured formatter/full linter).
- Existing fresh self-index/golden; scripts/recalibrate.sh --check; arch-rules self --on-vacuous fail; arch-impact self; scripts/origin-consumer.js then artifact validator.
- New standalone checks must use0pass/1assertion/>=2execution mapping, built into Tezt: authentic compiled fixture CLI, conservative boundary/negative cases, numeric transfer/join laws and output/input contract. Exact CHECK commands frozen in spec.
- Domain tests: bounded exhaustive concrete-vs-abstract containment for small word widths plus31/63 extrema; join/idempotence/bottom/monotonicity controls, wrap-to-zero case and branch shadowing.
- Native fixtures compile with actual configured OCaml; test aliases, guards, branch joins, unknown calls, nested functions/captures, unsupported loop/try and integer families, shadowed operators, partial applications.
- Exact-head remote CI required before merge. Existing origin corpus and rules remain unchanged; no pin/reference automatic edits.

## Open Questions

## R1 correction amendment — operator validation under standing autonomy

The independent review is NO-GO; this amendment closes its seven OPEN findings without weakening the 47 functional requirements or 19 acceptance criteria. No new user approval or completed correction is claimed.

V1's supported public interfaces are the installed `arch_guard` executable and root `arch-guard` dispatcher. `lib/arch_guard` remains a private Dune implementation library for that executable and owned test probes, not an installed `arch-index.guard` embedding API. Compiler global state may be reset within the CLI process; host-process restoration and a new subprocess/serialization embedding API are not deliverables. Verify private library absence and public executable presence in the freshly generated installation manifest, and retain working probe linkage.

Correct report context in both JSON and text, including accepted empty inventories: linked compiler, host 31/63-bit width, supplied-artifact scope, trusted same-compiler/same-target and no-source-freshness assumptions; explicit limitations on completeness, execution, confirmed failure, machine-checked proof, interprocedural/heap reasoning, indirect operations and omitted artifacts. Keep the closed JSON schema unchanged and project text from the same result.

Add a self-contained new `scripts/check-guard-report-context.js` regression executable (no required arguments) for finding `lib/arch_guard/arch_guard.ml:213:spec#cd378d70`, with pre-fix SHA `d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec`. It must compile owned empty and classified fixtures and call the actual CLI in both formats, returning 0/pass, 1/assertion, >=2/setup or execution, with 120-second and 16-MiB child caps. The red/green gate overlays only this new file into a pre-fix archive: it must not depend on newly added helpers. Use an existing built CLI normally; build the single CLI target only if absent in the archive, using the caller's configured compiler environment. Record authentic pre-fix assertion failure and corrective success; register the check in Tezt. Never nest Dune when the normal suite already supplies the binary.

Strengthen existing inventory, numeric and report modes with owned native or trusted Typedtree/CMT-seam fixtures. Cover later saturation, overapplication, labelled operands, missing original slot 2 with later arguments, combined eligibility/ancestry and unresolved/non-native operand and guard types. Assert immediate-site cardinality, unchanged slot metadata and exact sorted reasons. Cover alpha-renaming, aliases before/inside refinement, fresh nested/curried/immediately-applied entries beneath nonzero/contradictory/unsupported ancestors, inner locals, defaults/cases, multiple exclusion causes, unaffected siblings, all loop positions and closed dispatch including methods/effect primitives, indirect and unlisted calls. Check status-specific reasons, reject unsupported sites with only a numeric reason, compare every site field and census between JSON and text on an all-five-status fixture, and include wrong-reason/omitted-text-field sensitivity controls. Exercise reversed distinct accepted inputs byte-for-byte, duplicate coordinates, exact 256/257 UTF-8-byte spelling boundaries, help/version and wrapper no-auto-build behavior.

Corrections stay in already named component/test/docs paths plus the exact new standalone ratchet file. If fixture tables need separation, use the existing `tezt/fixtures/arch_guard/` scope; do not broaden the manifest to all scripts. OCaml fixture/report/package changes precede the JS oracle integration; serialize all Dune commands in the active worktree. Finish with full build, full forced suite, all standalone checks, fresh self/golden/origin gates and committed clean-build recalibration, followed by a fresh independent roster review and QA. Preserve R1 findings and cross-runtime degraded evidence; no PR before GO gates. Update the roadmap and clean only owned disposable artifacts.

None deferred to implementation. Representation and module layout are engineering choices within the required behavior, resolved in plan; flags/output contract/bounds and ambiguities are adversarially frozen in spec before implementation.
