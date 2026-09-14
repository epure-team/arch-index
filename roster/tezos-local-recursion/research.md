# Research — tezos-local-recursion

_Generated: 2026-09-14 (UTC)_
_Mode: full — independent analyzer, combined locator/pattern finder, external documentarian_
_Online research: enabled; OCaml5.3.0 official versioned interfaces_

Neutral manifest only was provided to the research workers. Source/behavior
facts below do not prescribe changes. Three available worker slots combined
locator/pattern roles. New-thread quota prevented a fourth fresh thread; a
previously completed agent answered only the neutral external API question,
without the current task description. No builds or writes by researchers.

## Question1: CMT representations

**Finding:** Binder maps use `Ident.unique_name`; display names use `Ident.name`.
The source-order-final structural binder retains its unsuffixed name and earlier
same-level binders use ordinals. Direct literal arity is structural. Nested
function literals have location-derived names under the current caller, with
collision ordinals, their own CFG and retained line span.

**References:**
- `lib/arch_index/arch_index_cmt.ml:901` — structural binding-name convention.
- `lib/arch_index/arch_index_cmt.ml:924` — Tpat_var binder discovery.
- `lib/arch_index/arch_index_cmt.ml:935` — source-order ordinal assignment.
- `lib/arch_index/arch_index_cmt.ml:895` — fn_arity traverses function parameters/body.
- `lib/arch_index/arch_index_cmt.ml:1495` — lambda naming and collision counters.
- `lib/arch_index/arch_index_cmt.ml:1920` — lambda-node creation and separate context.

## Question2: retained, discarded and ambiguous bodies

**Finding:** Structural open-body descriptors separately record expected physical
expression, indexed name, arity, matching count, observed identity and successful
storage. Literal rows are inserted separately; failures enter the dropped-node
registry. Descriptor finalization distinguishes known dropped bodies, uniquely
observed/stored bodies and missing/ambiguous identity. General target resolution
also distinguishes an external leaf from multiple indexed candidate units.

**References:**
- `lib/arch_index/arch_index_cmt.ml:967` — open_body_target fields.
- `lib/arch_index/arch_index_cmt.ml:1918` — physical-expression match observations.
- `lib/arch_index/arch_index_cmt.ml:3555` — actual lambda insertion.
- `lib/arch_index/arch_index_cmt.ml:3851` — descriptor finalization after traversal.
- `lib/arch_index/arch_index.ml:1479` — target resolution and refusal classes.

## Question3: existing invocation-resolution flow

**Finding:** Local literal stamps are populated after visiting each Texp_let
binding RHS. The pattern/expression predicate is Tpat_var/Texp_function; the
recursion flag is ignored in this traversal branch. Direct Pident invocations
consult the structural function table, the separate open-body table, then the
local literal table; remaining heads become Callback_param. Qualified owned
structures use a different identity-rooted map. Non-invocation lookup excludes
one-hop value aliases accepted by invocation lookup. Syntactic arity, application
result type and supplied arguments determine partiality; overapplication adds
an unknown returned-call residual.

**References:**
- `lib/arch_index/arch_index_cmt.ml:1946` — Texp_let branch, RHS traversal before stamp insertion.
- `lib/arch_index/arch_index_cmt.ml:1963` — exact local pattern/RHS and recorded node/arity.
- `lib/arch_index/arch_index_cmt.ml:2322` — direct head selection order.
- `lib/arch_index/arch_index_cmt.ml:1157` — local-module owner lookup.
- `lib/arch_index/arch_index_cmt.ml:1175` — invocation-only one-hop aliases.
- `lib/arch_index/arch_index_cmt.ml:2263` — supplied-argument counting.
- `lib/arch_index/arch_index_cmt.ml:2281` — arity/partial selection.
- `lib/arch_index/arch_index_cmt.ml:2394` — overapplication residual.

## Question4: effects, CFG, flat and non-head facts

**Finding:** Each callable context is solved separately for always-executed and
may-run blocks. Missing context demotes rather than asserting execution/deadness.
Call insertion preserves scope links, propagation channels and dead-site facts.
Non-head bound-literal uses have their own occurrence branch. Public collector
wrapping keeps the open-body descriptor table empty for legacy flat extraction.
Native controls compare predecessor/current pending calls, stored shape facts,
configured value-channel facts and duplicate-sensitive flat rows.

**References:**
- `lib/arch_index/arch_index_cmt.ml:2944` — CFG certainty/deadness calculation.
- `lib/arch_index/arch_index_cmt.ml:1995` — non-head local-lambda occurrence handling.
- `lib/arch_index/arch_index_cmt.ml:3008` — public wrapper around private collector.
- `lib/arch_index/arch_index_cmt.ml:3698` — scope-ID mapping.
- `lib/arch_index/arch_index.ml:1561` — pending-call fields persisted after resolution.
- `roster/tezos-open-bodies/check-native.js:191` — paired legacy/rich comparison.
- `roster/tezos-open-bodies/check-native.js:235` — nonempty preservation requirements.
- `roster/tezos-open-bodies/check-native.js:284` — counted flat comparison.

## Question5: MAY/MUST creation and validation

**Finding:** Head_unknown always becomes MAY_TOP; Head_enumerated always becomes
MAY_ENUMERATED. Resolved local/qualified heads require both unconditionality and
saturation for MUST. Alias edge forms force demotion. Missing local bodies and
ambiguous indexed units become explicit TOP. Schema/query/NDJSON validation checks
the closed kind vocabulary rather than trusting a marker alone.

**References:**
- `lib/arch_index/arch_index.ml:944` — documented kind matrix.
- `lib/arch_index/arch_index.ml:1456` — demotion predicate.
- `lib/arch_index/arch_index.ml:1481` — enumerated heads cannot become MUST.
- `lib/arch_index/arch_index.ml:1493` — local missing/dropped behavior.
- `lib/arch_index/arch_index.ml:1511` — qualified ambiguity behavior.
- `architecture-schema.sql:281` — callgraph kind vocabulary.
- `architecture-schema.sql:307` — TOP reason constraints.
- `lib/arch_tools/arch_db.ml:425` — query contract checks.
- `lib/arch_db/arch_load.ml:54` — NDJSON kind parsing.

## Question6: existing fixtures/assertions

**Finding:** Soundness fixtures cover structural mutual recursion, conditional,
tuple and shadowed literal bindings, partial applications, escapes, unused
literals and beta-redex calls. Other tests cover structural shadowing and actual
SQL refusal of open-wrapped bodies/parents. Fixed410 controls use pinned artifacts,
counted canonical changes and independent native occurrence evidence; historical
baseline numbers differ by task and are not interchangeable.

**References:**
- `tezt/tests/callgraph_soundness.ml:153` — ping/pong structural recursion.
- `tezt/tests/callgraph_soundness.ml:187` — local/lambda fixtures.
- `tezt/tests/callgraph_soundness.ml:278` — kind/occurrence assertions.
- `tezt/tests/ocaml_shapes.ml:73` — even/odd recursive fixtures.
- `tezt/tests/ocaml_shapes.ml:298` — directional-edge assertions.
- `tezt/tests/escaping_origins.ml:88` — recursive loop fixture.
- `tezt/tests/shadowed_definitions.ml:75` — retained shadow identity tests.
- `tezt/tests/open_body_targets.ml:78` — actual SQL body/parent refusals.
- `roster/tezos-open-bodies/check-witness-inputs.js:44` — fixed410 membership.
- `roster/tezos-open-bodies/check-witness-inputs.js:110` — actual316 positioned pairs.

## Question7: [ecosystem] OCaml compiler APIs

**Finding:** OCaml5.3.0 represents local groups using Texp_let with a recursion
flag, binding list and continuation. Tpat_var carries Ident and UID; Texp_ident
carries the resolved Path as well as syntax and type metadata. Function literals
contain parameters and either an expression body or cases with a terminal
argument. Applications retain omitted slots as None. Expression locations are
metadata, not binder identity. Ident.same distinguishes fresh nonpersistent
binders, including homonyms. Cmt_format exposes complete or partial annotations;
it does not define arch-index database node identity. Local stamps are not
documented as persistent identities across separately produced CMT artifacts.

**References:** OCaml compiler distribution,5.3.0, INRIA/contributors:
- [Typedtree](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/typing/typedtree.mli)
- [Ident](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/typing/ident.mli)
- [Path](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/typing/path.mli)
- [Cmt_format](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/file_formats/cmt_format.mli)
- [Location](https://raw.githubusercontent.com/ocaml/ocaml/5.3.0/parsing/location.mli)

Main checked exact versioned Typedtree/Ident/CMT interfaces against the external
report; installed compiler reports5.3.0. No trunk interface is substituted.

## Patterns found

- Stamp-keyed structural/local bindings; indexed names remain separate from source text.
- Per-literal caller/CFG contexts with collision-aware naming.
- Separate invocation lookup and non-head occurrence emission.
- Stored-node refusal distinguished from missing and ambiguous target identity.
- Counted native predecessor/current comparisons and fixed-corpus witnesses.

## Coverage gaps

- No configured formatter or coverage threshold in the available project gates.
- No installed acknowledged research-orientation pack; source reads used instead.
- No new native experiment or candidate gain is asserted by this documentary research.
