# Architecture voice 1 — guard-division-analysis

## Proposed domain representation

Use a width-parameterized finite constant/zero domain:

`Bottom | Const(bit-pattern) | Nonzero | Top`

- `Bottom` means no modeled execution reaches the expression.
- `Const(0)` is the exact-zero fact; every other `Const` is nonzero.
- `Nonzero` represents any nonzero OCaml `int` value.
- `Top` represents any OCaml `int`, including zero.
- Constants are normalized with explicit modular signed semantics at the selected test width; production analysis uses `Sys.int_size` and records it. This prevents host unbounded arithmetic from proving a wrapped result nonzero.
- Join is the least upper bound: identical constants remain exact; distinct nonzero constants join to `Nonzero`; zero joined with any nonzero value becomes `Top`; `Bottom` is the identity.
- Restriction by equality to zero maps `Top` to `Const(0)` and `Nonzero` to `Bottom`; inequality maps `Top` to `Nonzero` and `Const(0)` to `Bottom`. Contradictory restrictions therefore become unreachable.
- Exact constant arithmetic is evaluated with explicit width-aware modular operations. Nonconstant transfers use conservative zero-preservation rules only where sound; otherwise they widen to `Top`. Division/remainder transfer never performs a concrete division when the divisor may be zero, and may return `Top` even after a nonzero-divisor restriction.

This is smaller than an interval product while still meeting the required exact-literal, alias, zero restriction, join, bottom, and overflow behavior. It deliberately does not retain ordering facts that the requested guard fragment does not require.

## Sequenced thin end-to-end slices

1. **Freeze the executable contract and trust boundary**
   - Specify the explicit repeatable input flag, text and JSON modes, closed JSON fields, deterministic ordering keys, resource bounds, diagnostics, and exit mapping: analysis findings including `ZERO`, `MAY_ZERO`, and `UNSUPPORTED` exit 0; command/input/internal failure exits 2.
   - Freeze the five semantic statuses exactly as `NONZERO`, `ZERO`, `MAY_ZERO`, `UNREACHABLE`, and `UNSUPPORTED`, including the reached-only meaning of `ZERO` and the prohibition on `NONZERO`/`UNREACHABLE` in unsupported regions.
   - Freeze artifact acceptance/rejection, hash-before/read/hash-after behavior, canonical-path deduplication, symlink rejection, duplicate logical artifact rejection, and stdout-only output.
   - Freeze syntax inventory fields, semantic result/reason fields, artifact census, empty-inventory representation, compiler/width/trust metadata, and wording that scopes results only to supplied trusted artifacts.
   - **Dependencies:** none.
   - **Demo:** invoke the wrapper with help, malformed options, no/invalid inputs, and output-mode selections; compare deterministic diagnostics and exit codes to the contract without analyzing a valid site yet.
   - **Completion criterion:** the spec fixes every CLI flag, bound, field, ordering rule, reason-code vocabulary, and error case needed by later slices.

2. **Inventory real compiler-identified primitive sites from one trusted artifact**
   - Add the separate `lib/arch_guard/` library, `bin/arch_guard/` executable, and root `arch-guard` wrapper without changing `lib/arch_index` behavior.
   - Validate and read explicitly supplied CMT artifacts; accept only implementation annotations from the compatible compiler and reject interface, packed, partial, wrong-version, symlinked, changed-during-read, duplicate-path, and duplicate module/source artifacts.
   - Walk accepted typed trees in an inventory-only pass and identify the eight declared int/int32/int64/nativeint division/remainder primitive identities through `Val_prim`; preserve original operand-slot identity. Record partial applications as inventory entries with an unsupported operand/execution reason rather than as executed division sites.
   - Emit stable text and JSON reports with artifact metadata, raw syntax census, and an explicit empty inventory.
   - **Dependencies:** step 1.
   - **Demo:** compile an owned fixture containing native-int division, shadowed source operators, other integer families, and a partial application; show that only compiler primitives are inventoried and all sites have stable locations/categories.
   - **Completion criterion:** raw syntax counts are independent of semantic traversal and identical across repeated runs/input order permutations.

3. **Classify constants and immutable aliases with the minimal domain**
   - Implement the explicit-width abstract domain and environment keyed by compiler identifiers, not names.
   - Interpret native-int constants, immutable local bindings/aliases, sequencing, and direct native-int div/mod applications. Classify divisor facts as `NONZERO`, `ZERO`, or `MAY_ZERO`; keep all non-native integer-family sites `UNSUPPORTED` with explicit reasons.
   - Evaluate exact constant arithmetic using modular width semantics; conservatively widen uncertain or overflow-sensitive nonconstant results. Never concretely evaluate division/remainder with a zero or maybe-zero divisor.
   - Pair every raw syntax site with exactly one semantic result so analysis cannot erase inventory entries.
   - **Dependencies:** steps 1–2.
   - **Demo:** an authentic compiled fixture reports literal `2` and a local alias of `2` as `NONZERO`, literal `0` as `ZERO`, a parameter as `MAY_ZERO`, and int32/int64/nativeint sites as `UNSUPPORTED` while preserving the raw census.
   - **Completion criterion:** bounded exhaustive small-width containment and 31/63-bit extrema tests pass, including wrap-to-zero, lattice join/idempotence/bottom/monotonicity, and a zero divisor without analyzer failure.

4. **Add branch-sensitive classification and unreachable modeled paths**
   - Recognize compiler-resolved integer equality/inequality-to-zero guards and propagate restrictions into pure `if` branches.
   - Join branch environments and values with the domain lattice; preserve identifier-based shadowing.
   - Mark sites reached only through contradictory accumulated restrictions as `UNREACHABLE`. Treat nested functions as separate entry contexts with unknown parameters/captures, so an enclosing branch cannot lend them reachability or nonzero facts.
   - Support basic pure integer arithmetic only through the conservative width-aware transfers frozen for step 3.
   - **Dependencies:** step 3.
   - **Demo:** fixture results show the nonzero side of `d = 0` and `d <> 0` as `NONZERO`, contradictory constraints as `UNREACHABLE`, branch values `0`/`2` joined to `MAY_ZERO`, and a shadowed variable classified from its own identifier.
   - **Completion criterion:** branch, join, contradiction, shadowing, and nested-function negative tests pass for both guard spellings.

5. **Fence unsupported execution regions without contaminating supported facts**
   - Detect loops, recursive evaluation, exception handlers, effects, mutation/heap-dependent reasoning, and optional/default-argument semantics as unsupported execution regions with stable explicit reasons.
   - Unknown ordinary calls return `Top`; retain only sound immutable local scalar facts across them and no heap facts. Do not expand calls.
   - Ensure every inventoried site in an unsupported region remains `UNSUPPORTED`, never `NONZERO` or `UNREACHABLE`, while supported sibling regions continue to receive semantic classifications.
   - **Dependencies:** steps 2–4.
   - **Demo:** a mixed fixture containing a pure guarded site, unknown call, nested function/capture, loop, try/handler, and mutation reports each independently with the expected reason and unchanged raw syntax total.
   - **Completion criterion:** negative fixtures demonstrate conservative degradation at each unsupported boundary and no unsupported site receives an evidentiary status.

6. **Deliver honest owned-corpus measurement and repository integration**
   - Build the standalone checker into Tezt with the required `0` pass, `1` assertion, and `>=2` execution-error mapping.
   - Run authentic compiled fixtures and report per-status census, useful added `NONZERO`/`UNREACHABLE` distinctions, and the visible unsupported denominator against the raw syntax inventory.
   - Run arch-guard on the owned library artifacts and preserve an explicit zero-site result if that is the observed inventory; do not broaden the corpus.
   - Document the model, unsupported fragment, trusted-build/source-location/host-width assumptions, result semantics, input handling, and non-claims in `docs/arch-guard.md`, README, and CHANGELOG.
   - Integrate only the named test/build paths; preserve the existing self-index golden, recalibration, rule self-check, impact, origin-consumer, and artifact-validation baselines without reference or allow-list changes.
   - **Dependencies:** steps 1–5.
   - **Demo:** one command produces stable human and JSON reports for the complete owned fixture corpus and the owned library, with honest counts and documented interpretation.
   - **Completion criterion:** build, full suite, whitespace check, all existing baselines, new standalone checks, and exact-head remote CI pass.

## Dependency rationale

- The contract must precede implementation because later fixtures otherwise encode accidental flags, reason strings, bounds, or JSON shape.
- Inventory must precede semantic interpretation because the separate raw census is the guard against silently hidden sites.
- Constant/alias semantics precede branch semantics because restriction and join depend on a tested lattice and width-aware transfer layer.
- Unsupported-region fencing follows the supported core so each boundary can be tested for conservative degradation while retaining inventory completeness.
- Corpus measurement is last because it is meaningful only after both semantic capability and unsupported accounting are stable; each earlier slice remains independently executable and demonstrable.

## Assumptions forced by the brief

1. The later specification will choose concrete flag names, numeric resource limits, JSON key names, stable reason codes, and deterministic location/order tie-breakers; the intake mandates that these be fixed but does not provide their exact values.
2. The eight primitive identities and their operand-slot conventions can be enumerated unambiguously from compiler metadata for the repository's OCaml floor; the intake states the set but not the literal primitive-name table.
3. “Basic int arithmetic” can be limited to the exact operator set frozen in the specification. Any operator absent from that set must conservatively yield `Top` or an unsupported reason rather than be guessed.
4. Compiler compatibility can be decided before accepting an annotation and exposed as a deterministic diagnostic, even though the exact compatibility predicate is not stated here.
5. Stable source-site identity can be derived from compiler location plus primitive/operand metadata, with a spec-defined tie-breaker for equal or ghost locations.
6. Immutable local scalar facts may survive an unknown ordinary call only where compiler typing establishes immutability and the expression is outside an otherwise unsupported effectful region.
7. The owned library artifacts to measure are available through the repository build graph; the CLI itself will never discover or build them.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---:|---:|---|
| Primitive application shape or original operand slots differ across full and partial applications | High | High | Freeze an explicit compiler-identity/arity table and test fully applied, partially applied, aliased, and shadowed forms against raw typed fixtures. |
| CMT reading can partially succeed before discovering an unsupported annotation or input mutation | Medium | High | Stage validation and reporting; buffer the complete report and emit only after every artifact and post-read digest passes. |
| The four-element domain is implemented with host arithmetic and becomes unsound at wraparound | Medium | High | Parameterize width, normalize bit patterns explicitly, exhaust small widths, cover 31/63 extrema and wrap-to-zero, and widen whenever an exact modular transfer is unavailable. |
| Treating structural traversal as semantic reachability leaks `NONZERO` into loops, handlers, effects, or nested closures | High | High | Keep inventory and interpretation separate; make unsupported-region context and function entry reset explicit and test every boundary negatively. |
| Equality recognition by printed operator name misclassifies shadowed or polymorphic operations | Medium | High | Match compiler-resolved identities and verified int typing only; test shadowing and non-int equality. |
| A raw site is omitted when semantic interpretation aborts or declines a subtree | Medium | High | Produce inventory first, require a total site-to-result reconciliation, and fail internally rather than emit an incomplete “complete” JSON report. |
| Canonicalization/dedup semantics vary for relative paths, hard links, or module/source collisions | Medium | Medium | Freeze canonical physical-path rules and duplicate identity keys in the contract; cover reordered aliases and collision cases. Do not claim adversarial filesystem atomicity. |
| Output stability is undermined by compiler traversal order or nondeterministic map iteration | Medium | Medium | Define a total sort key and canonical JSON serialization; compare byte-identical output across runs and permuted inputs. |
| `UNREACHABLE` is overclaimed for code outside the supported intraprocedural fragment | Medium | High | Permit it only from `Bottom` produced by modeled branch restrictions; unsupported context dominates and nested functions reset execution state. |
| Owned-corpus zero results are mistaken for safety evidence | High | High | Always print artifact scope, raw count, unsupported denominator, and non-claim language; test the zero-site report explicitly. |
| New Tezt build dependency accidentally perturbs existing CLI generation or baselines | Medium | Medium | Add only named integration wiring, retain independent existing gates, and prohibit golden/reference/allow-list updates in this work. |
| Resource limits truncate analysis yet appear complete | Medium | High | Specify whether exceeding each bound is an exit-2 incomplete-analysis error; never emit a complete JSON document after a bound/input/internal failure. |

## Questions to settle before implementation

These are specification questions, not invitations to invent implementation-time answers; the intake says they must be adversarially frozen before code begins.

1. What are the exact CLI flag names, defaults, repeatability rules, and numeric resource limits, and does every limit breach uniformly produce exit 2 with no JSON?
2. What is the complete closed JSON schema, including schema/tool/compiler version formats, digest encoding, location representation, reason-code vocabulary, census invariants, and deterministic sort key?
3. What exact eight `Val_prim` identities and original operand-slot mappings are accepted, including curried/partial application shapes?
4. Which compiler-resolved equality/inequality identities at int type are recognized, and which basic arithmetic primitives receive transfers in V1?
5. What exact wrong-version/annotation compatibility condition is checked, and how are ghost/missing source locations represented?
6. What keys define duplicate module/source identity across distinct artifacts, and are hard links considered duplicate physical inputs after canonicalization?
7. Which per-artifact and aggregate counts must reconcile for a report to be considered complete, especially when an artifact has zero sites?
8. Which owned library artifacts are passed explicitly by the test harness, and what command demonstrates their honest zero-site result without adding discovery behavior to the CLI?
9. Does stdout remain completely empty for every exit-2 path in both modes, with diagnostics only on stderr, or is a structured JSON error permitted? The “no complete JSON” requirement alone does not settle this.
10. How are unsupported contexts nested and prioritized when multiple reasons apply, so output remains stable and semantic statuses cannot leak through an outer unsupported region?
