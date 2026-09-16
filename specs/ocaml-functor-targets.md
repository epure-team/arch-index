---
name: roster-spec
type: spec
status: live
feature: OCaml functor actual-member target correspondence
brief: briefs/ocaml-functor-targets-intake.md
date: 2026-09-16
version: 1.0.0
---

# Spec — OCaml functor actual-member target correspondence (Stage 4)

## Clarifications

| Q | A |
|---|---|
| What authenticates a correspondence? | One existing artifact-local binding chain: matched application occurrence, direct named functor declaration, named formal binder and one-based formal position, plus a constraint-peeled named actual rooted at a nonpersistent `Ident`. Text is never sufficient. |
| Which actual paths are supported? | A `Tmod_ident` path without `Papply`, whose complete local-rooted `Pdot` path resolves to concrete exports in the same artifact. Anonymous structures, unpacks, module aliases, persistent roots and application-owned paths are excluded. |
| Which members are callable evidence? | Existing `Direct_body` and invocation-safe `One_hop_alias` exports, including members below concrete nested owners/includes. Missing, opaque, primitive, field, method, destructured and multi-hop/module-alias cases are not evidence. |
| What happens to `module_param` uncertainty? | It remains as the original `MAY_TOP/module_param` row. Proven targets are additional `MAY_ENUMERATED` rows; supported applications never close the world or create `MUST`. |
| How are repeated and curried applications combined? | Each binding contributes only to its declaration identity and formal position. Target relations union context-insensitively and deduplicate canonically; every distinct artifact-local proof retains its own witness. |
| Does an application instantiate or clone the functor body? | No. The original source-level body and physical call occurrence remain the graph objects. Applications add target rows and provenance witnesses only. |
| How do compiled variants contribute? | Exact copies reuse the representative graph but collect per-artifact proofs. A nonidentical same-source variant may contribute only after a complete local proof and a unique stable-field reconciliation to an existing representative occurrence; compiler IDs never cross artifacts. |
| Does the flat LSP producer gain targets? | No. It has no CMT binding identity. Main CMT output is normative; flat remains unknown/unchanged and is a regression control only. |
| How is pinned-corpus attribution proved? | Every candidate-only relation must join to at least one persisted artifact-scoped witness carrying the full application/formal/actual/member/caller/target chain. At least one such new relation must exist across Irmin plus protocol. |

## User Stories

### US-1: Resolve supported formal-member calls (Priority: P0)

As a Tezos or Irmin call-graph reader, I want a call through a named functor
formal to gain the concrete callable members of every explicitly matched named
actual module, so that supported functor indirection becomes queryable without
pretending the indexed corpus is closed.

**Why this priority:** named module parameters account for a large remaining
Tezos/Irmin unknown family, and the repository already records the necessary
artifact-local application/formal/actual identity premises.

**Scope:** This story does NOT support persistent/cross-unit actuals,
`Path.Papply`, anonymous structures, unpacks, module aliases, synthesized
instances, body cloning, or removal of the `module_param` frontier.

**Independent Test:** compile one authentic CMT fixture containing direct,
repeated, curried, nested, alias and opaque cases, then inspect exact main rows,
witnesses and query results independently of the corpus benchmark.

**Acceptance Scenarios:**

1. **Given** local `A` with direct body `f`, named functor `F(X)` whose `run`
   calls `X.f`, and matched `F(A)`, **when** the CMT is indexed, **then** the
   original call occurrence has a `MAY_ENUMERATED` edge to `A.f` and retains its
   separate `MAY_TOP/module_param` edge, with no clone or `MUST`.
2. **Given** matched `F(A)`, `F(B)` and repeated `F(A)`, **when** collection
   order changes, **then** `A.f` and `B.f` each occur once as canonical target
   relations, the TOP frontier remains, and all distinct proofs remain as
   deterministic witnesses.
3. **Given** curried `G(X)(Y)`, nested actual `A.B`, an invocation-safe one-hop
   value alias, an opaque member and unsupported actual shapes, **when** each
   application is indexed, **then** only the member targets authenticated for
   the corresponding formal positions are added and every other case remains
   unknown without a guessed target.

### US-2: Keep independently compiled variants identity-safe (Priority: P0)

As an index operator, I want exact copies and nonidentical same-source CMT
variants handled without cross-artifact compiler-identity borrowing, so that
independently proven functor facts are neither duplicated nor discarded.

**Why this priority:** Dune can compile one source in several executable
contexts; exact copies are already reusable, while nonidentical variants are
currently dropped before their bounded additive facts can be considered.

**Scope:** This story does NOT merge differing function, type, exception or
caller graphs and does not make arbitrary same-source occurrences equivalent.

**Independent Test:** index byte copies and separately compiled variants with
colliding textual names and deliberately ambiguous occurrences, then compare
canonical rows, witness provenance and refusal counts under reordered discovery.

**Acceptance Scenarios:**

1. **Given** byte-identical CMTs under different artifact paths, **when** graph
   reuse succeeds, **then** the source graph is shared, bindings and witnesses
   are collected per artifact, and equal target relations remain idempotent.
2. **Given** a nonidentical same-source variant with a complete artifact-local
   proof and exactly one stable-field match to a representative call occurrence,
   **when** its source module row cannot be reinserted, **then** its bounded
   target and witness may still contribute to that existing occurrence.
3. **Given** unrelated compiler IDs with equal spelling/stamps/locations, an
   absent occurrence, or zero/multiple reconciliation matches, **when** the
   variant is processed, **then** no graph fact or witness is fabricated and
   the representative occurrence's existing unknown frontier remains.

### US-3: Prove impact and non-regression (Priority: P1)

As an analysis maintainer, I want authentic synthetic and pinned-corpus gates
with machine-checkable attribution witnesses, so that a shipped gain is
reproducible, non-regressive and specifically caused by supported functor
correspondence.

**Why this priority:** row-count deltas alone cannot distinguish a semantic
functor gain from an unrelated or display-only change.

**Scope:** This story does NOT claim precision/recall, whole-program soundness,
completeness, physical runtime instances or a performance bound.

**Independent Test:** run the checkers' pass, assertion and setup controls, then
compare a freshly produced candidate with the frozen Stage-3 410-input snapshot.

**Acceptance Scenarios:**

1. **Given** the authentic fixture matrix, **when** CHECK-1 runs the real
   producer and consumers, **then** it proves target/TOP coexistence, formal-slot
   isolation, witness integrity, variant refusal and flat non-inference.
2. **Given** the pinned Stage-3 baseline and unchanged 410-input manifest,
   **when** CHECK-3 runs, **then** it observes zero resolved-relation losses,
   zero new/upgraded `MUST`, at least one combined candidate-only relation, and
   a valid exact-key witness for every candidate-only relation.
3. **Given** missing, stale, partial, malformed, timed-out or crashing setup,
   **when** a checker runs, **then** it is non-green with exit at least 2;
   assertion mismatches exit 1 and successful reports state all limitations.

## Challenges

All 62 adversarial challenges were resolved from the validated brief, live code
and existing specs; none required an additional product choice.

| IDs | Story | Challenge | Resolution |
|---|---|---|---|
| C-1/C-5/C-6 | US-1 | Text, shadowing and currying can misassign a formal. | Eligibility uses the existing artifact-local declaration key, named binder key, matched application kind and telescope position. `head_application_ordinal` is provenance only. |
| C-2/C-3/C-4/C-21/C-22 | US-1 | The accepted application and actual syntax was ambiguous. | Only existing collected/matched applications qualify. The actual is a constraint-peeled local-rooted `Tmod_ident`/`Pdot` path without `Papply`; the fixture's `A` is local. All excluded shapes retain TOP and existing catalogue/binding diagnostics. |
| C-7/C-8/C-9 | US-1 | “Callable member” and member depth were unspecified. | Any finite `Pdot` member path below proven concrete owners is supported; its leaf must be the existing stored direct function body. Existing recursive direct bodies qualify; destructuring/primitives/methods/fields do not. |
| C-10/C-11/C-12 | US-1 | Alias-hop and opacity boundaries were unclear. | Only the existing invocation-safe one-hop value alias qualifies. Module aliases, mixed/multi-hop chains, cycles, persistent destinations and opaque destinations add no target. Existing `None` export ownership defines opacity. |
| C-13/C-14/C-18 | US-1 | Missing/opaque members and unknown multiplicity were unclear. | They add no bounded target and retain exactly the original physical occurrence's `MAY_TOP/module_param`; applications do not create additional TOP rows. A positive correspondence is a separate MAY row. |
| C-15/C-16/C-17/C-20 | US-1 | Relation deduplication could erase provenance or clone occurrences. | Existing canonical call identity deduplicates target rows. A stable physical occurrence discriminator separates equal locations, and every distinct proof remains a witness. No function/caller/body/application graph clone is allowed. |
| C-19 | US-1 | Flat cannot encode the CMT proof or TOP reason. | Flat is explicitly non-normative and unchanged; it must not gain a Stage-4 target. Its existing unknown tuple is a regression control, not a MAY/MUST proof. |
| C-23/C-24 | US-2 | “Same source” and “exact copy” lacked authority. | Same source is the existing normalized project-relative source plus compiler unit. Reuse requires authoritative full-byte equality and its SHA-256 guard; a digest alone never qualifies. |
| C-25/C-26/C-32/C-38 | US-2 | Graph sharing, artifact provenance and failure semantics conflicted. | Only graph rows are shared. Each artifact keeps its path and independently collects witnesses. Collection failure keeps existing incomplete/failed-input behavior and contributes no witness. Relation cardinality and witness cardinality are separate. |
| C-27/C-28/C-29/C-30/C-31/C-35/C-36/C-37 | US-2 | A nonidentical variant had no safe graph owner or occurrence join. | A complete local proof is collected before insertion loss, then attaches only to one representative occurrence matching normalized source/unit, canonical caller, normalized site, formal-member path and occurrence shape. Zero/multiple/absent matches add nothing. Only calls/witnesses may be added; compiler IDs and other graph entities never cross artifacts. |
| C-33/C-34/C-40 | US-2 | Variant failure/unknown evidence and diagnostics were underspecified. | A proven target coexists with the representative TOP. A failed variant creates no artifact-count-dependent TOP. Existing catalogue/binding failure rows remain authoritative; deterministic checker counters cover member/reconciliation refusals. |
| C-39 | US-2 | Discovery order could change winners or serialization. | Set union, canonical call deduplication and sorted complete witness serialization must make row/witness output invariant to enumeration order. |
| C-41 | US-3 | “Authentic fixture” was vague. | Tests compile source during the check under the selected supported OCaml switch and exercise the real producer, database and consumers. |
| C-42/C-43/C-57 | US-3 | Baseline, corpus pinning and cache freshness were incomplete. | CHECK-3 freezes the Stage-3 producer/schema/snapshot/revision plus the 410-entry manifest and hashes, freshly builds/copies the candidate inputs, revalidates all hashes and refuses stale or drifting state. |
| C-44/C-45/C-46/C-47/C-48 | US-3 | Loss/gain/MUST/relation identities were ambiguous. | Main canonical relation and row identities remain those of the existing comparison library. Any global loss or new/upgraded MUST fails and slice counts are reported separately; one combined Irmin-or-protocol gain suffices. Flat is excluded from corpus semantics. |
| C-49/C-50/C-51/C-52 | US-3 | Attribution could be optional, textual or lost after deduplication. | Every candidate-only relation must have an exact-key/foreign-key artifact-local witness; all witnesses persist in sorted form. A witness on a baseline relation is reported but is not a gain. |
| C-53 | US-3 | “Consumer behavior” named no boundary. | CHECK-1 asserts main SQL rows and `arch-query` answers; flat is tested only for unchanged unknown behavior. |
| C-54/C-55/C-56 | US-3 | Partial setup and abnormal termination could appear green. | Assertion mismatches alone exit 1; every exception, signal, timeout, schema or partial/setup failure exits at least 2. Overall setup failure prevents either slice being called green. |
| C-58 | US-3 | Witnesses could vary by checkout path. | Project-relative paths, canonical names/locations and sorted JSON remove absolute roots and order variance. |
| C-59 | US-3 | Limitations were prose-only. | Checker output and updated documentation must contain and test the no-whole-program, no-completeness and no-performance-bound limitations. |
| C-60/C-61/C-62 | US-1/US-2 | Shapes/UID, Merlin and odoc use richer identity models. | Shapes/UID and Merlin solve cross-unit navigation, not runtime target closure; odoc models documentation identity. Adopting them changes compiler/storage/cross-unit scope. Stage 4 deliberately reuses authenticated local bindings and retains TOP; these approaches remain future work. |

## Functional Requirements

#### Formal-member resolution

- **FR-001** [US-1]: When the existing binder collector successfully identifies an eligible application in one CMT artifact, the resolver MUST evaluate its named formal-member correspondence for concrete target evidence.
- **FR-002** [US-1]: An eligible correspondence MUST contain an immediate named functor declaration, a supported matched application kind, a named formal with binder key and a positive one-based `formal_position`.
- **FR-003** [US-1]: The resolver MUST accept only a constraint-peeled `Tmod_ident` actual without `Papply`, rooted in a nonpersistent local module owner within the same artifact.
- **FR-004** [US-1]: For an eligible local `Pdot` actual, the resolver MUST resolve its complete path against same-artifact structured-module ownership, including recursively concrete nested owners and includes.
- **FR-005** [US-1]: A local module alias, anonymous structure, unpack, persistent root, application-owned path, or any actual/member path containing `Papply` MUST NOT add a concrete target.
- **FR-006** [US-1]: A requested member exported by the proven actual as `Direct_body` MUST add its stored concrete callable as a target of the original formal-member occurrence.
- **FR-007** [US-1]: A requested member exported as an invocation-safe `One_hop_alias` MUST add the alias's stored underlying callable as a target of the original occurrence.
- **FR-008** [US-1]: A missing, opaque, primitive, method, field, destructured, multi-hop-alias or module-alias member MUST NOT be treated as callable evidence.
- **FR-009** [US-1]: A curried application MUST select its slot by artifact-local declaration identity, named formal binder and telescope position; `head_application_ordinal` MUST NOT define slot identity.
- **FR-010** [US-1]: Multiple supported applications MUST union their independently proven targets context-insensitively and MUST deduplicate relation rows by the existing canonical call identity without erasing proof provenance.
- **FR-011** [US-1]: Every independently proven positive correspondence MUST persist a deterministic artifact-local witness containing application ordinal, declaration and formal identity, formal position, actual/member path, physical caller occurrence, target and exact-key links sufficient to validate the whole identity chain.
- **FR-012** [US-1]: The resolver MUST consume only existing catalogue/binding traversal outcomes; nested, local, include and curried contexts MUST inherit that collector's eligibility and refusal semantics.
- **FR-013** [US-1]: When no concrete member target is proven, the output MUST preserve the single pre-existing `MAY_TOP/module_param` relation and MUST NOT add a per-application TOP relation.
- **FR-014** [US-1]: Every proven target MUST be a separate `MAY_ENUMERATED` row coexisting with the original `MAY_TOP/module_param`; this feature MUST NOT add or upgrade a `MUST` relation.
- **FR-015** [US-1]: Each physical formal-member `Texp_apply` in the representative graph MUST remain one caller occurrence; the feature MUST NOT clone functions, callers, functor bodies or application-specific graph nodes.
- **FR-016** [US-1]: Flat LSP output MUST preserve its prior unknown behavior and MUST NOT infer or emit a Stage-4 CMT target.

#### Compiled-variant identity safety

- **FR-017** [US-2]: Two artifacts MAY share an `ExactCmtGraphReuse` only when their normalized project-relative source and compiler unit match and authoritative full bytes plus SHA-256 guard match; compiler identities MUST NOT be compared across artifacts.
- **FR-018** [US-2]: Every exact-copy artifact MUST collect catalogue, binding and correspondence provenance independently and each witness MUST retain that artifact's own path.
- **FR-019** [US-2]: If per-artifact catalogue, binding or correspondence collection fails, existing incomplete/failure semantics MUST remain and no positive witness for that artifact may persist.
- **FR-020** [US-2]: A complete artifact-local positive proof from a nonidentical same-source variant MUST be collected before source-path insertion can discard that artifact.
- **FR-021** [US-2]: A nonidentical variant proof MUST attach only when exactly one representative occurrence matches normalized source and compiler unit, canonical caller, normalized call site, formal-member path and occurrence shape.
- **FR-022** [US-2]: Zero or multiple representative matches, or a local occurrence absent from the representative graph, MUST add neither target nor positive witness.
- **FR-023** [US-2]: Cross-artifact reconciliation MUST occur only after a complete artifact-local proof and MUST use stable source-level fields; equal compiler stamp, spelling or location alone MUST NOT authenticate it.
- **FR-024** [US-2]: Variant handling MUST NOT merge or create function, type, exception or caller nodes and MUST NOT perform a general graph merge.
- **FR-025** [US-2]: Given the same complete artifact set in any discovery order, canonical main rows, refusal counts and sorted witnesses MUST be identical.
- **FR-026** [US-2]: A refused or failed variant proof MUST NOT add an artifact-count-dependent TOP row; deterministic acceptance output MUST distinguish binding, member and reconciliation refusal counts without inventing graph facts.

#### Corpus proof and non-regression

- **FR-027** [US-3]: CHECK-1 MUST compile authentic source fixtures with the selected supported OCaml switch and exercise the real main producer, database and consumers.
- **FR-028** [US-3]: CHECK-1 MUST cover direct, repeated-union, curried, nested/include, one-hop-alias, opaque/unsupported, exact-copy, nonidentical-variant, ambiguous reconciliation and order-invariance cases.
- **FR-029** [US-3]: CHECK-1 MUST verify main call rows, witness rows and exact identity chains, SQL and `arch-query` behavior, negative/refusal counters, flat non-inference and 0/1/at-least-2 controls.
- **FR-030** [US-3]: CHECK-3 MUST compare a freshly built stable candidate with a frozen exact Stage-3 producer/schema/snapshot/revision and the revalidated fixed 410-artifact manifest/hashes.
- **FR-031** [US-3]: Stale, missing, mismatched or partial fixture, build, schema, manifest, artifact or corpus input MUST produce a non-green setup result and MUST NOT be reported as an assertion success.
- **FR-032** [US-3]: CHECK-3 MUST compare exact canonical row multisets and resolved-relation sets, fail on any global relation loss or added/upgraded `MUST`, and report Irmin and protocol counts separately.
- **FR-033** [US-3]: A successful CHECK-3 MUST contain at least one combined candidate-only resolved relation across Irmin and protocol; either individual slice MAY have zero gain.
- **FR-034** [US-3]: Every candidate-only resolved relation MUST have at least one valid persisted witness joined through the exact artifact-scoped identity chain; display-name equality MUST NOT validate attribution.
- **FR-035** [US-3]: All produced witnesses MUST serialize deterministically in sorted project-relative form; witnesses for baseline-existing relations MUST be reported but MUST NOT satisfy the positive-gain condition.
- **FR-036** [US-3]: Each checker MUST return 0 only for a complete pass, 1 only for an assertion mismatch and at least 2 for exceptions, signals, timeouts, schema or setup failures; reports and documentation MUST state no whole-program guarantee, no completeness guarantee and no performance bound.

## Acceptance Criteria

- **AC-1** [US-1 happy path]: A supported local `F(A)` maps the original `X.f` occurrence to `A.f` as `MAY_ENUMERATED` while retaining `MAY_TOP/module_param` and a complete witness.
- **AC-2** [US-1 repeated applications]: `F(A)`, `F(B)` and repeated `F(A)` yield one canonical relation per occurrence/target, all distinct witnesses, stable order and the independent TOP row.
- **AC-3** [US-1 curried/nested]: Curried formal positions and a constraint-peeled local nested `Pdot` actual resolve only their intended member without shadowing or slot confusion.
- **AC-4** [US-1 alias boundary]: Direct and invocation-safe one-hop value-alias members resolve; multi-hop/module aliases, primitives, methods, fields, destructuring and opacity do not.
- **AC-5** [US-1 unsupported boundary]: Persistent roots, local module aliases, anonymous structures, unpacks, application-owned paths and `Papply` add no target and no extra TOP.
- **AC-6** [US-1 graph integrity]: Equal/overlapping locations retain distinct physical occurrences; no graph entity is cloned and every positive mapping has an exact-chain witness.
- **AC-7** [US-1 flat isolation]: Equivalent flat LSP input remains unknown and contains no guessed Stage-4 target.
- **AC-8** [US-2 exact copies]: Full-byte/hash-guarded copies reuse the representative graph but collect artifact-specific witnesses; digest-only or failed collection cannot contribute.
- **AC-9** [US-2 variants]: A nonidentical variant contributes only a locally proven target that uniquely reconciles to the representative; absent, ambiguous and unrelated-ID cases contribute none.
- **AC-10** [US-2 determinism]: Reordered artifact discovery yields identical canonical rows, refusal counts and sorted witnesses without compiler-ID borrowing or general graph merging.
- **AC-11** [US-3 authentic gate]: CHECK-1 and CHECK-2 cover the synthetic matrix, exact witness chain, consumers, variants, flat regression, full native suite and independent functor-binding contracts.
- **AC-12** [US-3 pinned safety]: CHECK-3 revalidates all frozen/current inputs and observes zero global relation loss and no added/upgraded `MUST`, reporting both slices separately.
- **AC-13** [US-3 attributed impact]: CHECK-3 observes at least one combined candidate-only relation and validates every candidate-only relation through one or more complete witnesses; pre-existing relations do not count.
- **AC-14** [US-3 honest failure/reporting]: Assertion controls exit 1; stale, missing, partial, malformed, timed-out or crashing setup exits at least 2; green reports contain all three limitation statements.

## Edge Cases

- EC-1 [US-1]: No supported application for a formal → only the original `module_param` frontier remains.
- EC-2 [US-1]: Local `A` shadows a persistent or earlier local `A` → only `Ident.same` inside the application artifact authenticates the actual.
- EC-3 [US-1]: Two physical `X.f` applications share one source line → separate occurrence discriminators prevent cross-assignment.
- EC-4 [US-1]: `A` has no `f`, or `f` is opaque → no target/witness; one original TOP remains.
- EC-5 [US-1]: `A.f` and `B.f` resolve to one underlying body → one canonical relation may have multiple retained witnesses.
- EC-6 [US-1]: `G(A)(A)` supplies one actual to two formal positions → positions remain distinct even if final target relations deduplicate.
- EC-7 [US-1]: First curried application is unsupported → later binding is eligible only if the existing binding collector independently marks its formal position matched.
- EC-8 [US-1]: Any actual or member path contains `Papply` → no bounded target is emitted.
- EC-9 [US-2]: Equal digest but unequal bytes → not an exact copy.
- EC-10 [US-2]: One variant contains an occurrence absent from the representative → no reconciliation or graph contribution.
- EC-11 [US-2]: One source span maps to multiple representative call nodes → reconciliation refuses rather than choosing by order.
- EC-12 [US-2]: One variant proves `A.f`, another proves `B.f` for the same uniquely reconciled occurrence → both targets and their witnesses union; the representative TOP remains.
- EC-13 [US-2]: Exact-copy graph reuse succeeds but that artifact's binding/correspondence collection fails → graph remains, failed input is recorded, and the artifact contributes no witness.
- EC-14 [US-3]: Candidate adds witnesses only for baseline relations → reported evidence, but positive-gain criterion fails.
- EC-15 [US-3]: Candidate adds a relation with missing/textual-only witness → assertion failure.
- EC-16 [US-3]: Irmin gains and protocol is unchanged, or vice versa → positive criterion may pass; both slice outcomes are reported.
- EC-17 [US-3]: Either corpus slice is missing or stale → overall setup failure, no partial green result.
- EC-18 [US-3]: Candidate adds several witnessed targets but loses one unrelated relation → assertion failure.

## Runnable Checks

Every command uses 0 = complete pass, 1 = assertion failure and at least 2 =
setup/load/environment error. These are required deliverables and are not
treated as passing until implemented and observed RED then GREEN.

- **CHECK-1** [AC-1/2/3/4/5/6/7/8/9/10/11]: `rtk proxy node roster/ocaml-functor-targets/check-cmt.js` → compile authentic fixtures; inspect main calls/witnesses, consumers, exact copies, nonidentical variants, refusal/order controls and flat non-inference.
- **CHECK-2** [AC-11]: `rtk proxy node roster/ocaml-functor-targets/check-native.js` → run the full native Tezt suite and every independent `check-functor-bindings.js` mode with normalized 0/1/at-least-2 classification.
- **CHECK-3** [AC-12/13/14]: `rtk proxy node roster/ocaml-functor-targets/check-tezos.js` → validate frozen Stage-3 and current inputs, compare exact pinned410 rows/relations, validate every gain witness and record resource observations plus limitations.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"ocaml-functor-targets","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":["functor-binding-resolution/FR-001"]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":["ocaml-cfa-propagation/FR-020"]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":["ocaml-cfa-propagation/FR-033"]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":["ocaml-data-preservation/FR-009"]}
{"record":"requirement","id":"FR-018","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-019","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-020","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-021","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-022","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-023","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-024","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-025","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-026","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-027","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-028","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-029","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-030","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-031","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-032","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-033","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-034","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-035","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-036","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002","FR-003","FR-006","FR-011","FR-013","FR-014"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-010","FR-011","FR-013","FR-014","FR-025"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-004","FR-009","FR-012"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-006","FR-007","FR-008"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-005","FR-008","FR-013"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-011","FR-015"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-017","FR-018","FR-019"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-020","FR-021","FR-022","FR-023","FR-024","FR-026"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-023","FR-024","FR-025","FR-026"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-027","FR-028","FR-029","FR-036"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-030","FR-031","FR-032"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-033","FR-034","FR-035"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-031","FR-036"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-4","AC-5","AC-6","AC-7","AC-8","AC-9","AC-10","AC-11"]}
{"record":"check","id":"CHECK-2","for":["AC-11"]}
{"record":"check","id":"CHECK-3","for":["AC-12","AC-13","AC-14"]}
```

## Entities

- `FunctorApplicationOccurrence`: unchanged from `functor-instance-resolution`; one immediate ordinary/unit module application in one selected implementation Typedtree, identified by artifact path and preorder ordinal.
- `FunctorBindingResult`: unchanged from `functor-binding-resolution`; the matched or unresolved binding provenance result for exactly one catalogue occurrence.
- `LocalStructureTarget`: unchanged from `tezos-residual-targets`; an existing function-body definition selected through same-CMT structured-module binder ownership, not a runtime instance.
- `ExactCmtGraphReuse`: unchanged from `ocaml-data-preservation`; per-run reuse of a successfully extracted graph for an exact artifact copy under the same source/unit mapping.
- `ResolutionRelation`: unchanged from `tezos-residual-targets`; one canonical caller/source-line/internal-target tuple, not a unique syntactic expression.
- `FunctorTargetCorrespondenceWitness`: one persisted positive, artifact-local proof chain from an existing matched functor application/formal slot and concrete actual member to one representative graph occurrence and stored target.
- `RepresentativeGraphOccurrence`: one already indexed physical formal-member call selected as the unique stable-field destination of zero or more artifact-local correspondence witnesses; it is not a cloned runtime instance.
- `ModuleParameterFrontier`: the original `MAY_TOP/module_param` contribution at a formal-member occurrence, retained independently of every known target.

## Prior-art decision

OCaml Shapes/UIDs and Merlin's project index can trace definitions across
compilation units, while odoc has explicit documentation-level application
identities. They do not establish a closed runtime target set. Adopting them here
would add compiler-version, storage and cross-unit scope. Stage 4 therefore uses
already authenticated artifact-local bindings, persists its narrower positive
witnesses and retains `ModuleParameterFrontier`; Shapes/UID integration remains a
separate future design track.

## Validation Record

The comprehension question asked which rows coexist after a proven `F(A)`
mapping; the consistency question asked whether a zero-or-multiple-match
nonidentical variant may add a target. The user then explicitly repeated the
instruction to finish the roadmap. This is recorded as approval to proceed;
no quiz answers are fabricated. The canonical answers remain AC-1 (separate
`MAY_ENUMERATED` plus retained `MAY_TOP/module_param`) and AC-9 (no contribution
without exactly one representative match).

Three stories, nine clarifications, 62 challenges resolved, 36 requirements,
14 acceptance criteria and three runnable checks. Claims metadata was parsed
and cross-reference checked locally (36 FR, 14 AC, 3 CHECK); deterministic
claims validation/projection is unavailable because no reconciler is installed.
