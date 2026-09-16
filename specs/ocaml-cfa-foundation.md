---
name: roster-spec
type: spec
status: live
feature: OCaml CFA foundation
brief: briefs/ocaml-cfa-foundation-intake.md
date: 2026-09-16
version: 1.0.0
---

# OCaml CFA Foundation (Stage 2)

**Status:** VALIDATED contract under delegated routine gates, 2026-09-16.
Nothing here claims implementation, passing checks, or formal proof.
Claims lifecycle remains draft because the canonical reconciler is not installed.

The routine human gate is satisfied by the user's explicit authorization to run
the Roster pipeline autonomously. Research, clarification, adversarial challenge
and formalization used independent roles; root performed cross-spec examination
and final review. The
canonical claims validation/projection tool is unavailable, so the claims block
below is draft metadata only.

## Problem, scope, and terms

The callgraph currently resolves direct calls and a narrow set of aliases but has
no finite function-value propagation domain. This stage introduces a conservative
same-CMT inclusion foundation so supported indirect heads can retain actual source
targets beside unresolved contributions.

In scope are nonrecursive single-variable bindings at structure root or within the
same callable; known function identities and collector-promoted literals; and
`if`, `match`, and sequence-result joins. The analysis batch is one OCaml 5.3 CMT.

Out of scope are a general OCaml evaluator, a public embedding API, changes to the
numeric guard domain, proof graphs, call/return/argument/environment transfer,
recursive transfer, captures, general pattern transfer, partial-closure flow,
functor substitution, cross-session identity, and independently compiled variant
reuse. Those are not silently moved into this stage.

- **CFA value:** `(targets, reasons)`, two independent finite sets.
- **Cell:** a session-local node holding a CFA value.
- **Bottom:** `(empty, empty)`; it is not unknown-only.
- **Occurrence:** one physical application expression within a CMT session,
  independent of its source coordinates.
- **Main producer:** the persisted producer with ordinal-qualified identities,
  kinds, and reason fields.
- **Flat producer:** the established bare-caller, kind-less representation.

Existing `GuardAbstractValue`, exception raise sets, lambda nodes, call kinds,
`LocalValueAliasInvocation`, `ResolutionRelation`, and row-multiset semantics are
unchanged. Existing lambda names and collision suffixes remain authoritative.
This spec narrowly refines historical one-hop refusal assertions in
`tezos-residual-targets` and related executable expectations only for the newly
supported same-CMT nonrecursive single-variable subset. Existing MUST saturation,
MAY_TOP frontier, body stamps, scopes, independent residuals, immediate
predecessor alias provenance, and frozen measurements remain unchanged.

## Clarifications

| Q | A |
|---|---|
| Which old refusals change? | Only the explicit same-CMT nonrecursive single-variable alias/literal/branch-result subset; no general higher-order closure. |
| Does unknown absorb known targets? | No; independent finite sets retain both. |
| Can source positions identify cells? | No; resolved binders and physical expressions within one CMT session do. |
| Where is finalization? | Once per CMT after collection and authoritative body identity reconciliation. |
| Must flat adopt main's shadow names? | No; retain its namespace, with explicit unknown where caller/target identity is unrepresentable. |
| What survives target expansion? | Every occurrence's applicable metadata and independent residuals; never merge distinct same-line occurrences. |
| Is full derivation provenance required? | No; actual target/source identity, call site and producer run only. |

No user questions were needed: answers are grounded in the validated intake and
research. No human quiz answers were fabricated.

## User stories and scenarios

### US-1 — trustworthy finite value propagation (P0)

As an analysis developer, I want function candidates and unknown contributions
propagated to closure so downstream absence conclusions use a deterministic,
conservative result.

**Why this priority:** Incorrect joins invalidate downstream absence conclusions.
**Scope:** No compiler evaluator, public API, numeric changes or proof graph.
**Independent Test:** Compare a pure finite-cell probe with independent closure
enumeration, without compiler or database dependencies.

1. **Given** `a`, `b`, `c`, target `f` seeded at `a`, and copies `a -> b -> c`,
   **when** the solver runs, **then** `c` contains `f` and no reason.
2. **Given** one branch containing `f` and another containing opaque reason `r`,
   **when** both copy into `c`, **then** `c` contains both and neither absorbs the
   other.
3. **Given** a finite cycle `a -> b -> a` seeded with `f`, **when** constraints
   are reordered or duplicated, **then** closure terminates with identical sets.
4. **Given** an unseeded cycle, **when** solved, **then** the solver returns bottom
   and an invoked consumer does not treat it as a closed impossible callable.

### US-2 — authentic CMT targets without lost facts (P0)

As a graph-query consumer, I want supported function-value applications linked to
actual source targets so unresolved heads shrink without concealing uncertainty.

**Why this priority:** A detached solver alone does not improve indexed data.
**Scope:** Only the explicit stage2 fragment; stage3/4 flows remain excluded.
**Independent Test:** Compile benign fixtures, run real main and flat extraction,
inspect actual targets, unknown fields and main consumer query verdicts.

1. **Given** `let f x=x`, `let a=f`, `let b=a`, and `let run x=b x`, **when** the
   CMT is indexed, **then** main names actual `f` as `MAY_ENUMERATED`, not `MUST`,
   while aliases retain immediate-predecessor facts.
2. **Given** selection between two collector-promoted literals, **when** that
   value is applied, **then** both actual identities remain candidates even with
   equal or ghost positions.
3. **Given** selection between known `f` and an opaque callback, **when** applied,
   **then** `f` and an explicit unknown frontier coexist; unsupported captures or
   returned values do not become closed through unit visibility.
4. **Given** conditional, dead, partial, and overapplied occurrences in exception
   and value-channel scopes, **when** candidates expand, **then** each occurrence
   retains applicable metadata and independent residuals, including two calls on
   one line.
5. **Given** an unobserved/rejected body or a producer-unrepresentable identity,
   **when** finalized, **then** it remains explicit unknown rather than a silently
   bounded missing or homonymous target.

## Adversarial resolutions

| ID | Story | Binding resolution |
|---|---|---|
| C-1 | US-1 | Product-set semantics, componentwise order/equality/union, explicit bottom; diagnostic witnesses are nonsemantic. |
| C-2 | US-1/2 | Pure bottom stays bottom; invoked bottom becomes main `callback_param` or flat's exact unknown tuple and is never erased. |
| C-3 | US-1 | Vocabulary is target seed, reason seed, and inclusion/copy; branch join is multiple copies; no application transfer. |
| C-4 | US-2 | Eligibility follows compiler binders for root/same-callable nonrecursive single-variable bindings; recursive groups and module syntax gain no transfer. |
| C-5 | US-2 | Join all normally returning RHS values without feasibility claims; preserve effects/error channels; pattern-bound values are unknown. |
| C-6 | US-2 | Binder and physical-expression identities are session-local; positions are display/provenance only. |
| C-7 | US-2 | Main resolves actual ordinal identity; flat requires faithful same-file mapping and otherwise emits kind-less unknown, never a homonym. |
| C-8 | US-2 | Only the authoritative collector maps a physical literal to its final name/owner; missing, rejected, or wrong-owner mapping is unbounded. |
| C-9 | US-2 | Visible unit bindings are eligible; another callable's binder is an unsupported capture. |
| C-10 | US-2 | Opaque occurrence identity controls expansion; raw occurrences, escape edges, and residuals do not cross-deduplicate. |
| C-11 | US-2 | Candidate partiality uses authoritative `fn_arity`; unknown/omitted-label cases retain unknown; one overapplication residual belongs to the occurrence. |
| C-12 | US-2 | Existing resolved static handling wins; only unresolved supported head contribution is refined; aliases/escapes remain independent. |
| C-13 | US-2 | Closed reason mapping is explicit; flat has no reason column; missing main callers retain existing failure/drop behavior. |
| C-14 | US-1/2 | Three checks have exact commands and exit contracts; unavailable external corpus is an error, not green or native-CI failure. |
| C-15 | US-1 | This is finite inclusion closure, not full higher-order 0CFA; stage-3 state transitions are excluded. |
| C-16 | US-1 | A sparse worklist must equal an independent repeated-scan oracle; no definitional-interpreter implementation is prescribed. |
| C-17 | US-1 | Numeric guard TOP is not reused: known candidates coexist with an open frontier. |
| C-18 | US-1/2 | Reason kinds are semantic; optional witnesses are not; independent occurrences/residual causes remain separate. |
| C-19 | US-2 | OCaml 5.3 is the supported Typedtree contract; no cross-version/session/variant identity claim. |
| C-20 | US-2 | Transitive application refinement does not replace immediate-predecessor alias provenance or create a proof chain. |

Prior-art challenges were informed by Matthew Might's
[k-CFA/0CFA reference implementation](https://matt.might.net/articles/implementation-of-kcfa-and-0cfa/),
Darais et al.'s [Abstracting Definitional Interpreters](https://plum-umd.github.io/abstracting-definitional-interpreters/),
and OCaml's [5.3 Typedtree](https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli),
[5.3 Cmt_format](https://github.com/ocaml/ocaml/blob/5.3/file_formats/cmt_format.mli),
and [5.5 Typedtree](https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli).
These establish useful precedents, not this project's unknown element, queue API,
provenance schema, or compiler-version portability.

## Functional requirements

### US-1 domain

- **FR-001** [US-1]: The analyzer MUST model each cell as a pair of a finite target-identity set and a finite unknown-reason-kind set. Trace: US1-S1–S4, C-1, CHECK-1.
- **FR-002** [US-1]: The analyzer MUST order values componentwise by subset, compare both semantic sets, and join by componentwise union. Trace: US1-S2/S3, C-1/C-16/C-17, CHECK-1.
- **FR-003** [US-1]: The analyzer MUST represent bottom only as `(empty, empty)` and MUST NOT equate it with unknown-only. Trace: US1-S4, C-1/C-2, CHECK-1.
- **FR-004** [US-1]: The analyzer MUST support target seeds, reason seeds, and inclusion/copy constraints; it MUST express branch join as multiple copies into one result cell. Trace: US1-S1–S3, C-3, CHECK-1.
- **FR-005** [US-1]: The analyzer MUST propagate targets and reasons independently and MUST NOT let either absorb the other. Trace: US1-S2, C-1/C-17, CHECK-1.
- **FR-006** [US-1]: The analyzer MUST compute the least fixed point, terminate on finite copy cycles, reschedule a visited cycle when a new seed arrives, and return results invariant under ordering and duplicate constraints. Trace: US1-S1/S3, C-3/C-15/C-16, CHECK-1.
- **FR-007** [US-1]: The analyzer MUST match an independent repeated-scan finite-set oracle for both components. Trace: C-3/C-14/C-16, CHECK-1.
- **FR-008** [US-1]: The analyzer MUST NOT include diagnostic witnesses in semantic equality, joins, scheduling, or closure; witnesses of one reason kind MUST join to one semantic reason. Trace: C-1/C-18, CHECK-1.
- **FR-009** [US-1]: The analyzer MUST NOT claim call, return, argument, environment, capture, recursive value, or partial-closure transfer; this exclusion MUST NOT exclude pure-solver copy cycles. Trace: C-3/C-15, CHECK-1.
- **FR-010** [US-1]: The analyzer MUST NOT permit a consumer to interpret an invoked bottom cell as a closed impossible callable. Trace: US1-S4, C-2, CHECK-1/CHECK-2.
- **FR-011** [US-1]: The analyzer's CHECK-1 MUST return 0 on pass, 1 only for an explicit assertion failure, and at least 2 for environment, load, or build failure. Trace: C-14, CHECK-1.

### US-2 CMT integration

- **FR-012** [US-2]: The analyzer MUST process an entire CMT as one batch and finalize only after every actual literal name has been observed. Trace: US2-S1/S2/S5, C-8, CHECK-2.
- **FR-013** [US-2]: The analyzer MUST use resolved compiler `Ident` identity for binders and physical expression identity for literals/applications within one OCaml 5.3 CMT session; positions MUST be display/provenance only. Trace: C-4/C-6/C-10/C-19, CHECK-2.
- **FR-014** [US-2]: The analyzer MUST NOT claim identity equality across sessions, compiler versions, reparses, or independently compiled variants. Trace: C-6/C-19, CHECK-2/CHECK-3.
- **FR-015** [US-2]: The analyzer MUST newly support nonrecursive single-variable root bindings and same-callable nonrecursive single-variable lets, including branch-valued top-level bindings. Trace: US2-S1, C-4, CHECK-2.
- **FR-016** [US-2]: The analyzer MUST NOT add substitution or transfer for recursive groups, destructured pattern bindings, another callable's captures, nested-module/include/open syntax, call results, returned functions, arguments, or partial closures. Trace: US2-S3, C-4/C-5/C-9, CHECK-2.
- **FR-017** [US-2]: The analyzer MUST preserve established direct/static and owned-module handling; an already resolved static occurrence MUST win and MUST NOT receive a duplicate CFA replacement. Trace: C-4/C-9/C-12, CHECK-2.
- **FR-018** [US-2]: The analyzer MUST resolve aliases by binder identity so later shadowing cannot retarget an earlier alias. Trace: C-4/C-7, CHECK-2.
- **FR-019** [US-2]: The analyzer MUST conservatively join every normally returning RHS value of `if`, `match`, and result-valued sequence expressions without assuming feasibility or exhaustiveness. Trace: US2-S2/S3, C-5, CHECK-2.
- **FR-020** [US-2]: The analyzer MUST include normally returning exception-case RHS values while preserving error channels, and MUST NOT invent a returned function value for an unhandled exception. Trace: C-5, CHECK-2.
- **FR-021** [US-2]: The analyzer MUST preserve calls, effects, and channels from guards, scrutinees, and sequence prefixes while propagating only the sequence result value. Trace: C-5/C-10, CHECK-2.
- **FR-022** [US-2]: The analyzer MUST seed pattern-bound values as unknown for new transfer while retaining independently known constant RHS candidates. Trace: C-5, CHECK-2.
- **FR-023** [US-2]: The analyzer MUST allow visible unit-level binders in nested callable bodies, but MUST retain a binder owned by another callable as an unsupported capture contribution. Trace: US2-S3, C-9, CHECK-2.
- **FR-024** [US-2]: The analyzer MUST reconcile a physical literal only through the authoritative collector notification for its actual name/owner; missing, rejected, or wrong-owner notification MUST NOT create a bounded target. Trace: US2-S2/S5, C-8, CHECK-2.
- **FR-025** [US-2]: The analyzer MUST preserve distinct actual literal identities despite equal or ghost positions and MUST preserve collector-assigned collision ordinals. Trace: US2-S2, C-6/C-8, CHECK-2.
- **FR-026** [US-2]: The analyzer MUST refine only an unresolved supported head contribution; main MUST classify every CFA candidate `MAY_ENUMERATED`, never `MUST`, while flat MUST remain kind-less and MUST NOT claim that classification contract. Trace: US2-S1, C-7/C-12, CHECK-2.
- **FR-027** [US-2]: The analyzer MUST deduplicate candidates only by actual target identity within one occurrence; it MUST keep separate occurrences, residuals, alias rows, and escape facts separate. Trace: US2-S4, C-10/C-12/C-18, CHECK-2.
- **FR-028** [US-2]: The analyzer MUST preserve immediate-predecessor `value_alias` provenance and its caller-query exclusion independently of transitive application refinement. Trace: US2-S1, C-20, CHECK-2.
- **FR-029** [US-2]: The analyzer MUST copy each occurrence's applicable caller, call-site, original partiality, conditionality, deadness, scope, channel, and independent residual facts to expansion outputs; bounded rows MUST keep `top_reason` and `top_anchor` NULL, TOP anchors MUST remain only on applicable unknown rows, and deadness MUST NOT erase an occurrence. Trace: US2-S4, C-2/C-10, CHECK-2.
- **FR-030** [US-2]: The analyzer MUST preserve two physical applications on one source line as distinct occurrences. Trace: US2-S4, C-10, CHECK-2.
- **FR-031** [US-2]: The analyzer MUST derive known candidate arity from existing `fn_arity`: recursively count `Texp_function` parameters, count `Tfunction_cases` as one, a tuple parameter as one, two curried parameters as two, and each labeled formal as one; arity at most zero MUST be unknown. Trace: C-11, CHECK-2.
- **FR-032** [US-2]: For new CFA handling, the analyzer MUST count OCaml 5.3 application slots whose expression option is `Some`; it MUST preserve original partiality and additionally mark a candidate partial when supplied count is below known arity; any omitted labeled slot or unknown arity MUST retain explicit unknown and MUST NOT guess saturation; the existing static path MUST remain unchanged. Trace: C-11, CHECK-2.
- **FR-033** [US-2]: The analyzer MUST add or retain exactly one returned-function residual for an original known overapplication occurrence, not one per candidate. Trace: US2-S4, C-11, CHECK-2.
- **FR-034** [US-2]: The analyzer MUST preserve an opaque-head frontier and independent residual causes separately even when persisted TOP reason text coincides. Trace: US2-S3/S4, C-11/C-18, CHECK-2.
- **FR-035** [US-2]: The analyzer MUST translate an invoked unresolved bottom head in main to explicit `callback_param` unknown and MUST NOT emit zero rows. Trace: C-2/C-13, CHECK-2.
- **FR-036** [US-2]: The analyzer MUST map unsupported capture, unsupported pattern value, opaque value, and bottom to `callback_param`; known dropped/unobserved bodies to `dropped_node`; and MUST preserve established `module_param` and `ambiguous_unit` causes. Trace: US2-S3/S5, C-13, CHECK-2.
- **FR-037** [US-2]: The analyzer MUST retain flat's bare caller namespace and kind-less schema; a newly generated flat unknown MUST have `callee_name='*TOP*'`, `callee_file=None`, the original caller name/file and call-site, and `edge_form=NULL`; existing non-CFA unknown displays MUST NOT be globally renamed. Trace: C-2/C-7/C-13, CHECK-2.
- **FR-038** [US-2]: The analyzer MUST require a unique faithful same-file mapping before flat emits a new bounded candidate; a missing, ambiguous, or unrepresentable mapping MUST emit the FR-037 tuple, MUST NOT use `name_to_file` or a homonym, and MUST NOT set a callee file. Trace: US2-S5, C-7, CHECK-2.
- **FR-039** [US-2]: The analyzer MUST suppress newly bounded flat CFA facts at an ambiguous caller namespace and MUST emit the FR-037 unknown at that existing caller. Trace: C-7, CHECK-2.
- **FR-040** [US-2]: The analyzer MUST have main resolve actual ordinal-qualified target identities; a missing main caller MUST retain existing extraction failure/drop behavior and MUST NOT fabricate a caller row. Trace: C-7/C-13, CHECK-2.
- **FR-041** [US-2]: The analyzer MUST NOT add a kind token, `edge_form` token, proof-chain schema, fabricated callee file, or non-NULL CFA `edge_form`; flat MUST NOT be advertised as having main's proof/query contract. Trace: C-7/C-13/C-20, CHECK-2.
- **FR-042** [US-2]: The analyzer's CHECK-2 MUST exercise real compiled main/flat fixtures including bottom, collisions, metadata, candidate arity, ambiguous identities, and consumer queries, with CHECK-1's exit contract. Trace: C-14, CHECK-2.
- **FR-043** [US-2]: The analyzer's CHECK-3 MUST separately report exact gains/losses against the frozen pinned Tezos corpus plus resource observations; unavailable corpus MUST return at least 2 and MUST NOT be reported green or fail native CI. Trace: C-14, CHECK-3.
- **FR-044** [US-2]: The analyzer MUST NOT alter the frozen stage-1 baseline or claim stage-3 application/environment semantics or stage-4 variant reuse. Trace: C-14/C-15/C-19, CHECK-3.

## Acceptance criteria

- **AC-1** [US-1 happy path; C-1/C-3; FR-001/004/005]: Given `a -> b -> c` with `f` seeded at `a`, CHECK-1 observes `c=({f},empty)`.
- **AC-2** [US-1 happy path; C-1/C-17; FR-002/005]: Given `f` and opaque `r` copied into one result, CHECK-1 observes `({f},{r})`.
- **AC-3** [US-1; C-3/C-15/C-16; FR-006/007]: A seeded finite cycle terminates and all orderings/duplicates agree with the independent oracle, including a late-arriving seed.
- **AC-4** [US-1/US-2; C-1/C-2; FR-003/010/035/037]: An unseeded cycle is bottom in CHECK-1, while CHECK-2 shows an invocation remains explicit unknown in both producers.
- **AC-5** [US-1; C-1/C-18; FR-003/008]: Unknown-only differs from bottom and multiple witnesses of one reason kind yield one semantic reason.
- **AC-6** [US-1; C-14; FR-011]: CHECK-1 exhibits the specified 0/1/at-least-2 exit contract.
- **AC-7** [US-2 happy path; C-12/C-20; FR-015/017/026/028]: The `f/a/b/run` CMT emits main `f` as `MAY_ENUMERATED`, keeps immediate alias rows, and duplicates no static fact.
- **AC-8** [US-2 happy path; C-6/C-8; FR-012/013/024/025]: Two selected promoted literals retain distinct actual identities despite equal/ghost positions and preserve collision ordinals.
- **AC-9** [US-2 happy path; C-9/C-17; FR-019/023/026/034]: A visible `f` plus opaque parameter emits known-plus-unknown; visible top-level target plus unsupported capture does likewise.
- **AC-10** [US-2; C-5; FR-019/020/021/022]: Match/sequence fixtures preserve guard, scrutinee, prefix, and error facts; returning exception RHS joins; unhandled exception fabricates no target; pattern values remain unknown beside known RHS values.
- **AC-11** [US-2; C-4/C-7; FR-016/018/040]: Shadowing resolves the earlier main binder identity and recursive aliases remain unsupported.
- **AC-12** [US-2; C-2/C-10; FR-027/029/030]: Same-line applications with differing occurrence metadata remain distinct; bounded rows have NULL TOP fields and applicable unknown anchors/residuals survive separately.
- **AC-13** [US-2; C-11; FR-031/032]: Tuple, curried, labeled, and `Tfunction_cases` fixtures obey `fn_arity`; under one supplied expression arity-one/two candidates get conservative per-candidate partiality, while omitted labels and nonpositive/unknown arity retain unknown without changing static handling.
- **AC-14** [US-2; C-11/C-18; FR-033/034]: A known overapplication with multiple candidates produces exactly one occurrence residual alongside any independent opaque frontier.
- **AC-15** [US-2; C-8/C-13; FR-024/036]: Rejected, unobserved, missing-notification, and wrong-owner bodies never become bounded and use the prescribed unknown cause.
- **AC-16** [US-2; C-7; FR-037/038/039/040/041]: Flat bounds only a unique faithful same-file target; ambiguity emits the exact flat unknown tuple without homonym lookup or bounded fact, while main emits the actual ordinal-qualified identity.
- **AC-17** [US-2; C-2/C-7/C-13; FR-035/037/041]: Invoked bottom remains an occurrence: main emits `callback_param`, flat emits its kind-less tuple, and flat makes no main-equivalent proof claim.
- **AC-18** [US-2; C-14; FR-042]: CHECK-2 observes producer outputs and consumer verdicts and exhibits the specified exit contract.
- **AC-19** [US-2; C-14; FR-014/043/044]: CHECK-3 reports frozen-corpus gains/losses separately; unavailable corpus returns at least 2 and no cross-session, stage-3, or stage-4 conclusion is claimed.

## Edge cases

- Empty targets plus a reason is unknown-only, not bottom; same-kind diagnostic witnesses join semantically once.
- A seed entering an already visited cycle reschedules it to the same least closure.
- An alias preceding a same-spelling binder retains its earlier identity.
- Equal/ghost literal positions remain distinct; an unrepresentable flat target is unknown.
- Exception-case normal results join while error channels survive; pattern-bound values remain unknown beside independent known RHS values.
- A visible top-level target and enclosing-callable capture form known-plus-unknown.
- Candidate arities one and two under one supplied argument preserve conservative per-candidate partiality.
- Same-line occurrences preserve separate scopes/deadness; opaque and overapplication residual causes both survive.
- An effectful sequence prefix retains calls/channels while only its result value propagates.
- Recursive-group aliases remain outside new transfer.

## Runnable checks

These are required deliverables, not claims that scripts exist or pass. Each uses
exit 0 for pass, 1 only for an assertion failure, and at least 2 for setup,
environment, load, build, or unavailable-corpus failure.

- **CHECK-1** [AC-1/2/3/4/5/6]: `rtk proxy node roster/ocaml-cfa-foundation/check-domain.js` — compare the finite-cell solver against independent set-closure enumeration, including bottom, mixed values, duplicates, late seeds, and cycles.
- **CHECK-2** [AC-4/7/8/9/10/11/12/13/14/15/16/17/18]: `rtk proxy node roster/ocaml-cfa-foundation/check-cmt.js` — compile benign OCaml 5.3 fixtures, run real main and flat producers, and inspect outputs and consumer verdicts. Self-contained native coverage belongs in CI.
- **CHECK-3** [AC-19]: `rtk proxy node roster/ocaml-cfa-foundation/check-tezos.js` — report exact relation gains/losses and resource observations against the frozen pinned corpus. Corpus absence is exit at least 2 and is not native-CI failure.

## Claims metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"ocaml-cfa-foundation","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":["https://matt.might.net/articles/implementation-of-kcfa-and-0cfa/"],"depends_on":[]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":["https://plum-umd.github.io/abstracting-definitional-interpreters/"],"depends_on":["FR-006"]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":["FR-003"]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":["https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli"],"depends_on":[]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":["https://github.com/ocaml/ocaml/blob/5.5/typing/typedtree.mli"],"depends_on":["FR-013"]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":["FR-013"]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-018","lifecycle":"draft","external_sources":[],"depends_on":["FR-013"]}
{"record":"requirement","id":"FR-019","lifecycle":"draft","external_sources":[],"depends_on":["FR-004"]}
{"record":"requirement","id":"FR-020","lifecycle":"draft","external_sources":[],"depends_on":["FR-019"]}
{"record":"requirement","id":"FR-021","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-022","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-023","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-024","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-025","lifecycle":"draft","external_sources":[],"depends_on":["FR-013","FR-024"]}
{"record":"requirement","id":"FR-026","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-027","lifecycle":"draft","external_sources":[],"depends_on":["FR-013"]}
{"record":"requirement","id":"FR-028","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-029","lifecycle":"draft","external_sources":[],"depends_on":["FR-027"]}
{"record":"requirement","id":"FR-030","lifecycle":"draft","external_sources":[],"depends_on":["FR-013","FR-027"]}
{"record":"requirement","id":"FR-031","lifecycle":"draft","external_sources":["https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli"],"depends_on":[]}
{"record":"requirement","id":"FR-032","lifecycle":"draft","external_sources":["https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli"],"depends_on":["FR-031"]}
{"record":"requirement","id":"FR-033","lifecycle":"draft","external_sources":[],"depends_on":["FR-032"]}
{"record":"requirement","id":"FR-034","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-035","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-036","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-037","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-038","lifecycle":"draft","external_sources":[],"depends_on":["FR-037"]}
{"record":"requirement","id":"FR-039","lifecycle":"draft","external_sources":[],"depends_on":["FR-037","FR-038"]}
{"record":"requirement","id":"FR-040","lifecycle":"draft","external_sources":[],"depends_on":["FR-013"]}
{"record":"requirement","id":"FR-041","lifecycle":"draft","external_sources":[],"depends_on":["FR-037"]}
{"record":"requirement","id":"FR-042","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-043","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-044","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-004","FR-005"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-002","FR-005"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-006","FR-007"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-003","FR-010","FR-035","FR-037"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-003","FR-008"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-011"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-015","FR-017","FR-026","FR-028"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-012","FR-013","FR-024","FR-025"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-019","FR-023","FR-026","FR-034"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-019","FR-020","FR-021","FR-022"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-016","FR-018","FR-040"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-027","FR-029","FR-030"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-031","FR-032"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-033","FR-034"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-024","FR-036"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-037","FR-038","FR-039","FR-040","FR-041"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-035","FR-037","FR-041"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-042"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-009","FR-014","FR-043","FR-044"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-4","AC-5","AC-6"]}
{"record":"check","id":"CHECK-2","for":["AC-4","AC-7","AC-8","AC-9","AC-10","AC-11","AC-12","AC-13","AC-14","AC-15","AC-16","AC-17","AC-18"]}
{"record":"check","id":"CHECK-3","for":["AC-19"]}
```

## Entities

- CFAValue: independent finite function-target and unknown-reason sets.
- CFACell: one session-local location in the finite inclusion equation system.
- CFAApplicationOccurrence: one collected application occurrence independent of source position.
- CFAAnalysisSession: one OCaml5.3 CMT analysis and body-identity reconciliation lifetime.
- Existing lambda node, call kind, raise-set, GuardAbstractValue and ResolutionRelation definitions remain unchanged.

## Validation record

Root read the complete assembled contract and corrected missing story test/scope
fields, frontmatter, clarification/entity sections and FR-009 AC coverage.
Independent formalization resolved candidate arity and exact flat unknown tuple
gaps; source checks confirmed fn_arity and existing argument representation.
Two stories, seven clarifications, twenty resolved challenges, forty-four FRs,
nineteen ACs and three planned checks. The full adversarial questions and their
resolutions are retained in roster/ocaml-cfa-foundation/spec-challenges.md.
Routine quiz waived by explicit user autonomy; technical review/QA/exact-head CI
remain mandatory. Claims validation/projection is unavailable, not simulated.
