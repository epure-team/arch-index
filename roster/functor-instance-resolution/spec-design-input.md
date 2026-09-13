# Resolved clarification and story input

Operator decisions under standing autonomous implementation authorization. These
are proposed behavioral contracts for adversarial review, not a validated spec.
Step2 user questions asked: 0. All five OPEN design areas are resolved below;
the original clarifier report is retained unchanged for traceability.

## Clarification resolutions

- Q2 (nesting): inventory every immediate `Tmod_apply`/`Tmod_apply_unit` visited
  in the selected implementation Typedtree, including functor bodies, nested
  structures, anonymous arguments, unnamed bindings, and expression-local modules.
  Use one-based application-only preorder ordinals scoped by input artifact;
  functor operand precedes argument operand. Nested applications refer to their
  own ordinals; do not flatten a chain or count it as one runtime instance.
- Q3 (shapes): descriptors distinguish `path`, `structure`, `functor`, `unpack`,
  `constraint`, `application`, and `unit`. A path retains compiler-rendered and
  source-rendered names as display provenance, not resolved binding identity.
  Constraints retain a nested descriptor (no type/coercion interpretation).
  Structures/unpacks/functor literals remain shallow tagged descriptors rather
  than serialized bodies; nested application inventory still traverses them.
  A functor literal records parameter kind `unit` or `named` and optional name.
  `application` references a local occurrence ordinal. Unit is the synthetic
  argument only for `Tmod_apply_unit`. Diagnostics explicitly distinguish opaque
  functor head, anonymous argument, unpacked expression and unusable location;
  shape visibility is not a claim of target resolution. Exact code spelling is
  frozen by the challenged spec before implementation.
- Q4 (observable row): expose artifact path, source path, compiler unit,
  occurrence ordinal, ordinary/unit kind, source location including ghost flag,
  head descriptor, argument descriptor and diagnostic codes. Persist producer-run
  provenance and per-input collection outcome separately. SQL relational names
  and private helper interfaces are plan choices, not language semantics.
  Query is `arch-query DB functor-applications [limit]`, default50, strict decimal
  nonnegative limit, no other arguments. Use existing ARCH_QUERY_FORMAT modes.
  Emit a one-row summary followed by application rows sorted artifact/ordinal;
  JSON mode is two documented JSON arrays, as existing multi-table commands.
  Summary exposes contract, selected input count, collected input count, total
  applications, returned applications, truncation and selected-input-only scope.
  A limit of0 still emits the summary; it does not mean unlimited. Head/argument
  descriptors and diagnostics are JSON-valued text cells in all table formats.
- Q5 (identity): key is artifact identity within this run plus preorder ordinal,
  never visible binder name or location alone. Keep ghost positions; invalid
  start/end coordinates become null with `unusable_location`. No compiler stamp
  or DB surrogate id appears as public occurrence identity. Same artifacts and
  paths produce identical ordered catalogue output on reindex; moving/rebuilding
  artifacts is outside that identity guarantee. Shadowed names may share display
  strings but cannot collapse occurrences. This slice does not resolve those names.
- Q6 (coverage): per selected `.cmt` record collected, unreadable,
  unsupported_annotation, missing_source, dropped_module, or collection_failed.
  Only collected inputs contribute application rows. No absent annotation,
  swallowed read exception, missing source or rejected persistence may earn a
  successful catalogue claim. A marker `functor_catalogue_contract=v1` is earned
  after committed catalogue persistence only for nonempty selection with every
  selected input collected and all required provenance/rows stored. It is cleared
  through the central marker lifecycle before rebuilding. Zero applications in
  successfully decoded selected inputs is valid; zero selected inputs is not.
  Opaque expression diagnostics do not imply failed syntactic collection.
  Absent marker, old/flat/missing schema, incomplete input coverage or inconsistent
  required data => query refuses exit3 with stderr diagnostic and no stdout.
  Malformed CLI arguments or operational errors => exit2. Valid catalogue => exit0
  regardless of number of applications. Never read the marker as project closure.

## User stories for challenge

### US-1: Inspect source-backed application composition (P0)

As an OCaml index maintainer, I want to query persisted syntactic applications and
their argument structure so I can distinguish composition shapes without guessing
from unresolved call names.

Why P0: these facts do not exist in the current DB and are a prerequisite to
separately justified parameter substitution. Scope: no target inference, body
cloning, runtime instance count or call-graph change.

Independent test: compile a native fixture, index it, and inspect the catalogue
tables directly with SQLite, without the new query command.

1. Given `F(X)` and `F(struct let n=1 end)` in an owned CMT, when indexed, then
   two occurrence records preserve path versus structure arguments and locations,
   while the functions/calls snapshot retains the previous graph semantics.
2. Given `F(A)(B)`, `H(F(A))`, unit application, constrained expressions and an
   application inside a functor body/local module, when indexed, then each immediate
   application appears once and head/argument references preserve tree order.
3. Given two same-spelled local module bindings, `module _ = F(A)`, and synthetic
   ghost/same-position locations, when indexed, then distinct preorder identities
   retain every occurrence, with explicit unusable-location diagnostics where needed.
4. Given one successful CMT and one malformed or source-less selected CMT, when
   indexed, then per-input outcomes expose the gap and no successful catalogue
   marker is stored; no graph edge is promoted by catalogue observations.
5. Given the same database is indexed twice, when reading ordered catalogue facts,
   then no duplicate/stale rows survive and public identities/output are stable.

### US-2: Read an honest, bounded catalogue report (P0)

As an architecture reviewer, I want a read-only command with explicit collection
scope and limits so I can inspect available composition facts without confusing a
missing analysis, truncated listing or empty result with complete project knowledge.

Why P0: SQL storage alone does not provide a usable or consistently guarded report.
Scope: no MCP, UI, graph verdict, new executable or publication workflow.

Independent test: build a small hand-authored catalogue DB and invoke the query,
without the CMT collector. A separate native test covers end-to-end integration.

1. Given a valid two-input catalogue with three applications, when queried with
   limit2, then ordered rows are capped at2 and summary reports total3/returned2/
   truncated=true, with source/artifact provenance and selected-input-only scope.
2. Given one collected input and zero applications, when queried with limit0,
   then exit0 and the nonempty summary identifies a completed empty catalogue;
   JSON/table views agree and database bytes are unchanged by the read.
3. Given legacy/flat DB, absent marker, partial input coverage or missing required
   schema/data, when queried, then exit3, no stdout and a named refusal distinguish
   not-collected/incomplete from zero occurrences.
4. Given `-1`, `0x10`, an overflowing integer or an extra argument, when queried,
   then exit2 and no catalogue output rather than a silent default/unlimited scan.

## Candidate runnable checks (not written or run yet)

Standalone `scripts/check-functor-catalogue.js` groups `inventory`, `lifecycle`,
`query`, `compatibility`, with 0/pass, 1/Node assertion, >=2/setup/read/compile/error.
Compile owned native fixtures and invoke real producer/query; independent assertions
inspect results, not producer-supplied expected values. Missing binary is error2,
not an assertion; native fixture compilation must finish before product assertions.
No test-runner exit remapping. Wire all groups into deterministic tests. Include
premise assertions ensuring every fixture actually reaches the intended boundary.
