---
name: roster-spec
type: spec
status: live
feature: one-hop local value-alias invocation targets
brief: briefs/tezos-residual-targets-intake.md
date: 2026-09-14
version: 1.0.0
---

# Spec — Local value-alias invocation targets (attempt2 of5)

## Clarifications

Eight Q/A items are recorded in [spec-input](../roster/tezos-residual-targets/spec-input.md).
All eight adversarial challenges are resolved in
[spec-resolutions](../roster/tezos-residual-targets/spec-resolutions.md), including
exact prior-state hashes and observable partial/return behavior. These documents
are part of this contract. No product changes preceded the freeze.

Eligibility means plain exported Tpat_var, bare Texp_ident with resolved Pident,
syntactic arrow RHS and identity in the existing same-CMT body table. An
exp_extra constraint does not change exp_desc; an actual wrapper/computation does.
Invocation lookup and point-free emission are distinct consumers: existing
point-free facts remain unchanged, even where a further improvement is possible.

## User Stories

### US-1: Follow qualified calls through known local value aliases (Priority: P0)

As an index consumer I want invocations through known local aliases to reach
their real bodies so I can follow call chains.
**Why this priority:** explicit examples occur in protocol and Irmin.
**Scope:** no module aliases, functor expansion, unqualified alias calls or closure.
**Independent Test:** native fixture queries exact stored targets and pending metadata.

1. **Given** Owned.alias=base with an actual local base body, **when** run applies
   Owned.alias 1, **then** one exact same-file body head is MAY_ENUMERATED with
   null edge_form and TOP fields.
2. **Given** an alias bound to base before base is shadowed, **when** the alias is
   invoked later, **then** it targets the original body's actual #N stored name.
   A later mask of alias itself prevents eligibility.
3. **Given** parameter, multi-hop, computed, primitive or opaque cases and a
   same-named decoy, **when** invoked, **then** the old refusal remains.
4. **Given** required/optional label holes or2 supplied arguments to a3-ary body,
   **when** indexed, **then** pending partial uses supplied Some expressions and
   actual syntactic arity; no invented residual. A fully supplied overapplication
   emits one callback_param *TOP* residual at that site.
5. **Given** callback/letop/dead/conditional and point-free uses, **when** indexed,
   **then** invocation targets gain resolution with old metadata, point-free facts
   stay unchanged, rejected targets remain dropped_node TOP, and flat output
   never borrows a foreign homonym.

### US-2: Compare against the delivered state (Priority: P0)

As maintainer I want incremental comparison against PR105 so previous gains
cannot count as another improvement.
**Why this priority:** the five-attempt loop requires sequential measurable gains.
**Scope:** no generic benchmark product or public CLI.
**Independent Test:** neutral replay and mutated input/multiset controls without product edits.

1. **Given** unchanged PR105 producer and410 inputs, **when** a fresh predecessor
   is produced and replayed, **then**45052 canonical rows match SHA90e76d6...
   and4772/11615 relations; both self/reproduction comparisons are neutral.
2. **Given** a new supported candidate, **when** exact one-hop compiler witnesses
   are checked, **then** every changed occurrence/allowed return residual is
   accounted for with multiplicity, zero losses and separate slice gains.
3. **Given** wrong provenance, changed/missing inputs, foreign run, malformed
   witness, duplicate deletion, new MUST or point-free movement, **when**
   verified, **then** deterministic refusal/setup exits deny keep.
4. **Given** a neutral or unreviewed candidate, **when** reported, **then** no
   retained gain is claimed; retention also requires full roster/guards and
   exact-head green CI/rebase merge before attempt3.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | UID/shape prior art versus binder identity | Per-CMT resolved Ident product lookup; independent UID/alias/body evidence, disagreements refuse. |
| C-2 | US-1 | Eligibility form/type/path | All predicates required; explicit unsupported forms refuse. |
| C-3 | US-1 | Shadowing/mask timing | Alias RHS identity fixed at declaration; owner exports follow source order. |
| C-4 | US-1 | Partial/residual observables | Pending API metadata and exact per-head/residual rows, not invented schema fields. |
| C-5 | US-1 | Distinct consumer semantics | Invocation gains only; config/point-free behavior unchanged. |
| C-6 | US-2 | Which baseline is authoritative? | Distinct fresh PR105 predecessor with exact canonical and provenance pins. |
| C-7 | US-2 | Which changes are permitted? | Only paired same-file non-alias TOP-to-body heads and witnessed returns; exact multiset accounting. |
| C-8 | US-2 | Exit classes | Valid forbidden movement/native assertion1; malformed setup/input/witness/tool>=2. |

Full exact resolutions and EC outcomes are in the linked resolution table.
Official OCaml5.3 UID/shape prior art is explicitly handled by C-1, not ignored.

## Functional Requirements

- **FR-001** [US-1]: The indexer MUST resolve supported applied, callback and letop qualified local alias uses to the directly named same-CMT function body.
- **FR-002** [US-1]: Eligibility MUST require all declared binding/form/path/type/body conditions and MUST refuse unsupported alias RHSs and owners.
- **FR-003** [US-1]: Resolution MUST use compiler declaration and owner identity, never names, cross-CMT stamps or contradictory endpoint evidence as fallback.
- **FR-004** [US-1]: Targets MUST retain actual ordinal-qualified stored names and source-order masking; later shadowing MUST NOT retarget an alias.
- **FR-005** [US-1]: Supported occurrences MUST emit exactly one ordinary MAY_ENUMERATED body head with null TOP fields; storage rejection MUST remain dropped_node TOP and unsupported identities MUST retain their old refusals.
- **FR-006** [US-1]: Applied alias heads MUST preserve real syntactic-arity/supplied-argument partial behavior and exactly one existing-form anchored callback_param return residual for overapplication, as C-4 defines.
- **FR-007** [US-1]: Callback/letop/CFG/scope/channel/configuration-head semantics and every point-free output MUST remain unchanged except the explicitly supported invocation target.
- **FR-008** [US-1]: Flat output MUST retain body display and attribute only an actual same-file symbol, never a foreign homonym or invented kind/TOP fields.
- **FR-009** [US-2]: The authoritative predecessor MUST be freshly produced PR105 state with the exact C-6 hashes,45052 rows and4772/11615 relations; the original baseline MUST remain historical and unchanged.
- **FR-010** [US-2]: Setup MUST reproduce the predecessor neutrally before product edits and bind DB path, producer, schema, corpus and source provenance; canonical identity MUST NOT depend on surrogate DB bytes.
- **FR-011** [US-2]: Allowed head movement MUST be only non-value_alias module_param/no-target MAY_TOP to same-file body MAY_ENUMERATED with null TOP fields and preserved caller/site/form.
- **FR-012** [US-2]: Every changed occurrence MUST consume an exact one-hop compiler alias-to-body witness with matching positions and multiplicity; malformed or conflicting evidence MUST refuse.
- **FR-013** [US-2]: Only separately witnessed applied-head overapplication residuals MAY be added; all other canonical facts, including point-free rows, MUST remain unchanged.
- **FR-014** [US-2]: Relation loss, unconsumed changes, new MUST or point-free movement MUST refuse; gains MUST be distinct relation tuples reported separately for Irmin/protocol.
- **FR-015** [US-2]: Valid forbidden changes/native assertion failures MUST return1; malformed setup/input/witness/native compile/load failures MUST return>=2; every nonzero result MUST deny keep.
- **FR-016** [US-1]: The function-body table MUST remain body-only; alias declarations MUST NOT become MUST-eligible function bodies or acquire zero syntactic arity there.
- **FR-017** [US-2]: Keep MUST require positive incremental gain, native/full guards, independent roster review/QA and exact-head green CI/rebase merge; neutral setup or model consensus MUST NOT count as a retained iteration.

## Acceptance Criteria

- AC-1 [US-1 happy path]: Supported qualified alias invocation -> exact same-file MAY_ENUMERATED body head.
- AC-2 [US-1,C-1/C-2]: Exact one-hop identity/type/form controls -> eligible only with body; names/unsupported forms/competing evidence refuse.
- AC-3 [US-1,C-3]: Earlier-body alias and later export mask -> correct #N target or refusal, never retargeting.
- AC-4 [US-1,C-4]: Required/optional label and hidden-arrow native cases -> exact pending partial and return-row counts.
- AC-5 [US-1,C-5]: Callback/letop/conditional/dead uses -> target improvement only; scope/channel/config and all point-free facts unchanged.
- AC-6 [US-1,C-5]: Rejected body and absent flat symbol -> dropped_node TOP or display/fileNULL, respectively.
- AC-7 [US-2 happy path,C-6]: Fresh pinned predecessor and repeat/self ->45052 canonical rows, exact digest,4772/11615 relations, zero changes.
- AC-8 [US-2,C-7]: Exact one-hop witnesses with duplicate multiplicity -> only permitted heads/returns consumed, separate positive incremental gains.
- AC-9 [US-2,C-8]: Invalid input/provenance/run/witness versus valid forbidden mutation -> correct>=2 versus1 exits, never keep.
- AC-10 [US-2,C-7]: New MUST, relation loss, point-free movement, duplicate deletion -> refusal.
- AC-11 [US-1,C-4]: Body table and unqualified alias-call behavior -> unchanged, never alias-as-body MUST.
- AC-12 [US-2,C-7/C-8]: Neutral/unreviewed/unguarded result -> no keep; full delivery gates required.
- AC-13 [US-2]: Current producer's self golden -> exact byte match, no threshold or automatic refresh.

## Edge Cases

EC-1 absent body -> old refusal. EC-2 later shadowing -> original body identity.
EC-3 label holes/default Some -> exact supplied-count semantics. EC-4 missing
flat symbol -> no foreign attribution. EC-5 same alias applied and point-free ->
only applied resolution changes. EC-6 different DB bytes -> canonical/provenance
identity wins. EC-7 insufficient duplicate witnesses -> refusal1. EC-8 allowed
return residual plus genuine gain -> comparison may pass; downstream gates still
required. All map to the numbered story/challenge resolutions above.

## Runnable Checks

Deliverables, not claims of existing/passing checks. Standalone exits0=PASS,
1=actual assertion/forbidden movement,>=2=setup/input/tool failure.

- CHECK-1 [AC-1,AC-2,AC-3,AC-4,AC-5,AC-6,AC-11] (authentic-success-path, fail-closed-path): `node roster/tezos-residual-targets/check-native.js` -> actual compiled fixture, both collectors, pending metadata and storage queries. Genuine baseline RED before product edit.
- CHECK-2 [AC-8,AC-9,AC-10]: `node roster/tezos-residual-targets/check-comparison.js` -> positive and negative provenance/run/identity/multiset/witness controls using actual verifier routines.
- CHECK-3 [AC-7,AC-9]: `node roster/tezos-residual-targets/prepare-baseline.js --check` -> validate/replay distinct pinned predecessor record at improvement/2026-09-14-tezos-resolution/attempt2-baseline/provenance.json. First creation uses explicit --create, refuses overwrite and removes only its owned selection/temp builds.
- CHECK-4 [AC-8,AC-9,AC-10,AC-12]: `node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json` -> candidate against pinned predecessor, exact source/alias/body witnesses and full changed groups. --self omits witness; unwitnessed candidate may pass only if neutral. Report never independently authorizes keep.
- CHECK-5 [AC-13]: `node roster/tezos-call-resolution/check-self-index-smoke.js` -> exact existing producer/SQLite golden, no auto-refresh.

Full guard: local-switch dune build --root . and dune runtest --root . --force,
review bundle22 and whitespace. Exact-head hosted CI and pristine recalibration
remain ship conditions; task1 verifier/tests/evidence stay unchanged except the
explicit existing value_alias_call test reclassification in intake.

## Claims Metadata

```claims
{"record":"claims-header","schema_version":1,"namespace":"tezos-residual-targets","spec_lifecycle":"draft"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
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
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-005"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-002","FR-003"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-003","FR-004"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-006"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-007"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-005","FR-008"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-009","FR-010"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-011","FR-012","FR-013","FR-014"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-009","FR-010","FR-012","FR-015"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-013","FR-014"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-017"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-017"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-2","AC-3","AC-4","AC-5","AC-6","AC-11"]}
{"record":"check","id":"CHECK-2","for":["AC-8","AC-9","AC-10"]}
{"record":"check","id":"CHECK-3","for":["AC-7","AC-9"]}
{"record":"check","id":"CHECK-4","for":["AC-8","AC-9","AC-10","AC-12"]}
{"record":"check","id":"CHECK-5","for":["AC-13"]}
```

Claims remain draft metadata: canonical claims validator/projector is absent,
so no deterministic claims projection success is asserted.

## Entities

- `LocalStructureTarget`: an existing function-body definition selected through same-CMT structured-module binder ownership, not a runtime instance.
- `ResolutionRelation`: one canonical caller/source-line/internal-target tuple; not a unique syntactic expression.
- `ResolutionRowMultiset`: canonical stored call facts with multiplicity, excluding database surrogate IDs from identity.
- `LocalValueAliasInvocation`: supported qualified invocation whose one bare compiler-identity alias hop names a same-CMT body; not a point-free reexport edge.

Cross-spec: prior body-only and immediate-predecessor contracts remain canonical.
This spec extends only iteration1's value-member refusal at supported invocation
sites; it does not rewrite historical spec or evidence.

