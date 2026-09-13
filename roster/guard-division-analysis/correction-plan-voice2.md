# R1 Correction Plan — Independent Voice 2

## Planning basis and fixed boundary

This is a corrective plan for an already implemented experimental `arch-guard` slice.  It accepts the intake's product choices as fixed: a report-only, intraprocedural OCaml-int analysis over explicitly supplied trusted CMT implementation artifacts; the five result statuses; inventory of the eight declared primitive identities; and the public `arch_guard` executable plus root `arch-guard` dispatcher.  It does not turn the private Dune library into an installed embedding API, change `arch-index`, expand corpus discovery, or claim a security proof.

The correction is complete only when the amended behavior, its diagnostic/report contract, the new regression ratchet, and all stated existing/new gates agree.  A test that merely exercises a private helper is not evidence for the CLI contract.

## Sequential vertical correction steps

1. Establish a correction baseline and freeze the observable contract before changing implementation.

   Record the current failing R1 evidence against pre-fix SHA `d44c0c6ae8f4991549f6de5bbc2bdb3f24eb25ec`, including the known report-context defect location.  Write/finalize the spec first: repeatable explicit CMT inputs; stdout-only stable sorted text and closed JSON; exit `0` for complete reports irrespective of statuses, `2` for command/input/internal failure with no complete JSON; and the resource/dispatch rules.  Define exact JSON keys, text projections, ordering, reason spelling/order, census derivation, and the machine-readable representation of empty inventory before modifying producer code.  Freeze the child limits at 120 seconds and 16 MiB for the standalone checker, and freeze UTF-8 spelling-length measurement as bytes, not OCaml character count.  This step prevents the repair from passing by changing the oracle or silently widening output.

2. Correct report context at the single result-model boundary, then prove both renderers consume it.

   Extend the canonical completed-analysis result with required report context, computed from accepted input/configuration rather than assembled separately in text and JSON.  Populate it for classified and accepted-empty inventories with: linked compiler identity, host `Sys.int_size`/31-or-63 width, supplied-artifact scope, and the explicit trusted same-compiler/same-target/no-source-freshness assumptions.  Include the fixed limitations: no completeness or execution guarantee, no confirmed-failure claim for potential results, no machine-checked proof, no interprocedural or heap reasoning, indirect operations and omitted artifacts excluded.  Render JSON and text from exactly that result.  Do not emit a partial report on a rejected/mutated/wrong CMT.  Add contract assertions that absence of sites still has context and that ZERO means conditional-on-reachability, not observed execution.

3. Repair and harden syntax inventory independently of semantic interpretation.

   Make inventory a full accepted-CMT traversal that records every direct recognized primitive occurrence and preserves original operand-slot metadata, including partial application; semantic eligibility may only augment, never remove, an inventoried site.  Match compiler-resolved `Val_prim` identity, not source spelling, and retain the declared inventory coverage for OCaml `int`, `int32`, `int64`, and `nativeint`; only direct native-int div/mod can become semantically classified.  Freeze immediate-site coordinates and deterministic ordering.  Explicitly encode operand categories/reasons for later saturation, overapplication, labels, absence of original slot 2 despite later arguments, unresolved/non-native operands, and indirect/unlisted operations.  This prevents a semantic traversal limitation from appearing as an empty or incomplete syntactic census.

4. Make eligibility, ancestry, and unsupported classification a closed, compositional gate.

   Before applying any numeric transfer, calculate a site eligibility record containing primitive/operand type, original argument-slot availability, application shape, and enclosing execution-region ancestry.  Combine all exclusion causes deterministically rather than retaining the first incidental one.  Unsupported structure/effects—loops in every syntactic position, recursion, handlers/try, mutation/heap facts, defaults/cases outside the supported fragment, methods, effect primitives, indirect calls, and other unlisted calls—must propagate explicit ancestry reasons to affected sites while leaving unrelated siblings analyzable.  Unsupported sites must always be `UNSUPPORTED`; reject any unsupported result carrying only a numeric reason, and never return NONZERO or UNREACHABLE for it.  Unknown ordinary calls should top only where their result is interpreted, never be expanded or granted heap facts.

5. Correct the abstract domain and transfer discipline without weakening conservative overflow behavior.

   Select and document a finite domain with distinct bottom and top, zero/nonzero restriction, and a join that can represent MAY_ZERO.  Ensure literals and immutable aliases prove nonzero; an unguarded parameter remains MAY_ZERO; equality/inequality zero guards refine only int-typed compiler-resolved identities; contradictory restrictions give bottom/UNREACHABLE; and joining zero with nonzero produces MAY_ZERO.  Bindings must use compiler identifier identity so alpha-renaming and source/operator shadowing cannot alter facts.  Keep local immutable scalar facts across permitted sequencing only.  For addition/subtraction/multiplication and quotient/remainder, use conservative modular-int transfers valid at both 31 and 63 bits; overflow can widen to top and never proves nonzero with unbounded arithmetic.  Do not concretely divide by zero; min-int divided by minus one may remain imprecise.

6. Correct entry-context and call-boundary isolation.

   Analyze a nested function, curried function, or immediately applied nested entry as a fresh context with unknown parameters and captures, irrespective of a nonzero, contradictory, or unsupported enclosing branch.  Never inherit a parent's reachability guarantee into a new entry.  Retain the direct enclosing ancestry when a site truly lies in an unsupported region, but do not allow that ancestry to contaminate an independent nested entry.  Verify inner local bindings can still refine inside their own supported entry.  Keep optional/default arguments, call expansion, recursive unrolling, and guessed loop bounds out of the interpreter.

7. Enforce artifact admission, identity, and dispatcher behavior at the CLI perimeter.

   Canonicalize and deduplicate repeated physical input paths; reject symlinks; hash before and after CMT read; and reject interface, packed, partial, wrong-compiler, changed, or unsupported-annotation artifacts with diagnostics and no complete JSON.  Reject distinct accepted artifacts that duplicate module/source identity or site coordinates rather than merge/count inflate, and verify reverse input ordering yields byte-identical output.  Accept only explicit CMT arguments—no recursive discovery, source build, execution, or third-party scan.  The root dispatcher must forward to an existing installed/built executable and must not auto-build.  Help/version behavior must be stable and independently tested.

8. Add native/CMT-seam fixture coverage that closes each reported blind spot.

   Extend owned fixtures/checks in the named arch-guard scope for syntax cardinality and original slots, all five statuses, aliases before and inside refinement, alpha-renaming, shadowed source operators, all recognized integer families, unknown calls, joins, branch guards, contradictory constraints, and wrap-to-zero.  Add adversarial application fixtures for saturation/overapplication/labels/missing slot 2 and unresolved/non-native types; use trusted Typedtree/CMT seams only where native source cannot reliably express the needed malformed/edge shape.  Add nested/curried/immediately-applied entries under nonzero, contradictory, and unsupported ancestors; inner locals; defaults/cases; multiple reasons; unaffected siblings; all loop placements; methods/effects; indirect and unlisted calls.  Assert exact sorted status-specific reasons, immediate-site cardinality, preserved metadata, and census counts.  Include sensitivity controls that deliberately omit a text field or substitute a reason and must fail.

9. Add the mandated self-contained external report-context ratchet, after the OCaml behavior is green.

   Create exactly `scripts/check-guard-report-context.js`, with no required arguments and no dependency on post-fix helpers.  It compiles owned empty and classified fixtures and invokes the actual CLI in JSON and text formats.  It validates required context/limitations in both, reconciles every site field and census on an all-five-status fixture, and fails if context/fields/reasons are missing or inaccurate.  Its red phase overlays only this file into an archive of the stated pre-fix commit, uses an already-built executable where available and otherwise builds only the CLI target under the caller's configured compiler environment, then records authentic assertion failure.  Its green phase records success on the correction.  Return `0` for pass, `1` for assertion, and `>=2` for setup/execution failure; enforce the specified child caps.  Register it in Tezt, but avoid nested Dune when Tezt/the normal suite already supplies the binary.

10. Validate packaging, documentation, and release-facing truthfulness.

   Verify a fresh installation manifest exposes `arch_guard` and does not expose a private `arch-index.guard` library, while retained owned probes still link through the intended private build dependency.  Update only the named README, CHANGELOG, and `docs/arch-guard.md` to state artifact scope, trusted assumptions, empty-inventory meaning, status semantics, exit behavior, unsupported boundaries, and non-claims exactly as implemented.  Documentation must not advertise an embedding API, arbitrary-project discovery, absence-of-bugs, confirmed failures from MAY_ZERO, or target-width portability beyond the declared trusted-build assumption.

11. Run serialized end-to-end verification and preserve the correction evidence.

   Run no concurrent Dune processes in the worktree.  Execute the full root build, forced root suite, whitespace check, the standalone checker, existing fresh self-index/golden, recalibration check, rules self check with vacuity failure, impact self, origin consumer, and artifact validator using the frozen commands.  Run domain containment tests at small widths plus 31/63 extrema, join/idempotence/bottom/monotonicity controls, boundary 256/257 UTF-8-byte checks, fixture CLI tests, reversed input ordering, duplicate-coordinate rejection, and wrapper no-auto-build checks.  Perform committed clean-build recalibration, retain R1 finding/degraded cross-runtime evidence, then request a fresh independent roster review and QA.  Do not create a PR until those reviews return GO.

## Assumptions

1. The existing implementation and its generated installation manifest can be repaired within the already frozen component, fixture, documentation, Tezt, and exact standalone-checker paths.
2. The configured compiler can compile owned fixtures and produce readable native CMT implementation artifacts, and its linked compiler identity is available to the CLI.
3. Canonical physical paths, before/after hashes, and compiler metadata are adequate operational checks, while not an atomic-filesystem or source-freshness certificate.
4. The test environment can enforce the checker child time/memory limits and provide the existing built executable or build only its target in the pre-fix archive.
5. A domain conservative at both OCaml 31- and 63-bit `int` widths is feasible without adding global dependencies or changing the project compiler floor.

## Primary risks and controls

1. **Output drift between text and JSON.** One canonical result/context model plus all-field/census cross-format checks keeps projections coupled.
2. **Inventory undercount hidden by UNSUPPORTED semantics.** Independent raw syntax census and immediate-site/cardinality assertions make this observable.
3. **Unsound nonzero conclusion from overflow, ancestry, or captured facts.** Widen on uncertainty, isolate entries, distinguish bottom/top, and exhaustively test containment at boundaries.
4. **False acceptance of incomplete/ambiguous artifact sets.** Reject instead of merge, require explicit inputs, and emit no complete JSON on admission failure.
5. **A ratchet that passes without exercising the real regression.** Archive overlay contains only the checker; it must demonstrate pre-fix assertion failure and post-fix success through the actual CLI.
6. **Packaging accidentally creates an unsupported public API.** Inspect the fresh manifest explicitly; exercise private probes only through the Dune test build.
7. **Dune/build interference invalidates evidence.** Serialize Dune commands and avoid nested builds when a binary is provided by the normal test suite.

## Questions to resolve in the pre-implementation spec (engineering, not product-direction changes)

1. What exact compiler-derived stable identifiers and location fields constitute a site coordinate, particularly when distinct artifacts report the same source/module identity?
2. What finite-domain encoding best meets the required refinements and modular conservatism, and which arithmetic operations receive useful transfer versus unconditional top?
3. Which existing fixture build path supplies the all-five-status CMT artifact, and what exact CLI invocation is used by Tezt so the standalone ratchet never assumes an uninstalled binary location?
4. How will the checker enforce a 16-MiB cap portably in the supported CI/runtime environment, and how is an inability to apply that cap classified as `>=2` rather than a false passing assertion?
5. What are the exact schema version/tool-version literals, compiler-version normalization, and text grammar needed to make byte-for-byte reverse-input determinism testable without masking environment-provided paths?
6. Which malformed edge cases require trusted Typedtree/CMT seams rather than native OCaml fixtures, and how will those seams be marked so they do not misrepresent compiler-produced source behavior?
