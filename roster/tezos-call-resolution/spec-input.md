# Spec design input — iteration 1

This is pre-spec working material, not a validated spec or implementation plan.

## Clarifications resolved against source and intake

1. Eligible ownership requires the actual same-CMT structured-module binder and the actual final exported function-body binder. String equality is only a member selector inside a proven owner, never root identity.
2. Existing binding_name supplies the stored target name, including #N for shadowed values/module scopes. Per-CMT tables cannot leak between artifacts.
3. Only syntactic function bodies qualify. A later nonfunction/alias/pattern-bound binding must mask an earlier same-name function rather than expose it.
4. The researcher's traversal description is NOT a resolution rule. Indexing inside a functor/include/recursive declaration does not prove a path refers to that definition. Resolve each module hop only when its ownership is established. Literal included structures can contribute proven members under the enclosing scope; opaque includes must mask the exported names they introduce. Constraints preserve underlying structure identity but must not create members or bypass abstract/unavailable ownership. Recursive structure bodies may be admitted if their identity is established without chasing cycles; parameter/alias/application/unpack bindings are not owned structures.
5. Functor body definitions may contain independently declared local structures; their own direct paths can name those definitions without argument substitution or per-instance expansion. Functor parameter paths cannot.
6. Newly resolved call targets remain MAY_ENUMERATED; no CFG, partiality or error-configuration matching change is required. Existing over-application TOP residuals and unrelated metadata survive. Point-free emission retains value_alias and its existing ordinary-head/kind-matrix contract; it does not count in the metric.
7. Both collector entry paths must pass equivalent identity input while the flat fallback keeps its existing definition coverage and caller-name conventions. Kindless output is not evidence of rich-schema certainty.
8. Corpus metric alone is not semantic truth. Native positive/negative identity fixtures plus explicit real-corpus before/after witnesses and independent review justify the supported transformation. No change may be kept on model consensus/counts alone. The lack of arbitrary-program ground truth is an explicit limit, not an unanswered product choice.

## User stories

### US-1: Follow known local-module calls (P0)

As an arch-index consumer inspecting Irmin or protocol call chains, I want calls through actual local structured modules to reach their indexed function bodies without mistaking a caller-supplied module for one.

Why P0: measured TOP rows already have candidate bodies in the fixed corpus. Scope excludes module-alias chasing, functor instantiation and general value flow. Independent test: a native compiled fixture queries exact caller/target identities and edge kinds.

1. Given `module Local = struct let f x = x end`, when a function calls `Local.f`, then the rich graph links that exact stored body as MAY_ENUMERATED.
2. Given nested/renamed-shadowed structured module binders and same-named value bindings, when calls use their typed paths, then each reaches its own final exported body using its actual stored ordinal-qualified name, never a sibling or earlier shadowed member.
3. Given a functor parameter named Local, its alias, an application result or an unpacked module, when its member is called, then existing TOP/refusal behavior remains even if a real Local.f exists elsewhere.
4. Given a later nonfunction binding or opaque include masking f, when M.f is called, then the previous body is not selected. Literal structure inclusion is eligible only with actual member identity.
5. Given an eligible member used as an applied head, let operator, callback argument or point-free RHS, when indexed, then the corresponding existing emission is resolved without losing metadata; only point-free rows retain value_alias and remain excluded from call counts.
6. Given a target row rejected by the storage layer, when its caller is emitted, then it remains TOP/dropped_node, never an enumerated external leaf.

### US-2: Compare real-corpus resolution changes (P0)

As the maintainer deciding whether to retain an iteration, I want a replayable fixed410 relation/multiset comparison with concrete changed-target witnesses, so a diagnostic gain or dropped call cannot masquerade as improved resolution.

Why P0: existing aggregate scripts delete detailed DBs. Scope excludes new general benchmark product/CLI. Independent test: self-comparison and deliberately changed fixture snapshots exercise a standalone comparator.

1. Given two snapshots of the same binary and unchanged 410 CMT hashes, when compared, then zero gains/losses/movements are reported despite duplicate same-line calls.
2. Given a candidate with additional exact internal relations and unchanged existing targets/sites/multiplicities, when compared, then gains are enumerated separately for Irmin and protocol, excluding value_alias rows only.
3. Given a missing artifact, changed hash, incomplete collection, missing DB/table, missing caller/target, lost existing target, unexplained TOP loss or new MUST promotion, when verified, then the run refuses with a nonzero exit and does not report a keep.
4. Given two same-line rows with different kinds, when compared against reordered identical rows, then no phantom kind movement is reported. Swapping targets or removing one duplicate must be detected.
5. Given a neutral diagnostic-only change, when measured, then it does not count as a retained iteration. Given genuine gain and passing native/full/roster/CI guards, retain and merge before the next improvement attempt.

## Prior art

OCaml5.3 Path/Ident/Typedtree interfaces require structural/binder identity; this direction uses it. Printed paths are presentation, not identity. CMT compiler-version acceptance is delegated to the linked reader, not a new version-string check. Source URLs and access limits are recorded in research.md Q8.
