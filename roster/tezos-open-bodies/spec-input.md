# Specification input — not yet a validated spec

## Clarifications

| Q | A |
|---|---|
| Admitted definitions? | Structural single-variable bindings, exactly one path-only open immediately containing a literal function; existing module/functor-definition traversal, no instances. |
| Admitted uses? | Same-CMT Pident application heads only; all callback/letop/alias/qualified/local-let/escape paths unchanged. |
| Target identity? | Actual existing root lambda, not binding parent; existing shadow-aware binding name. |
| Collision ordinal? | Fresh collector marker table, open not peeled, Tmod_ident has no expression children, so direct root literal is first allocation and ordinal1. Share canonical formatter with existing allocator, preserve later collisions; native ghost-location/shadow controls must validate this premise. |
| Missing body? | New path requires actual body registration or explicit refusal. Parent rejection skips collection, so expected body must also be treated unavailable. Known rejected body -> dropped_node TOP; descriptor/actual-name mismatch -> callback_param TOP. Never create a dangling enum leaf; do not alter legacy missing-enum behavior globally. |
| Partial/residual? | Inner syntactic arity, count supplied Some expressions, preserve partial flag; accepted head remains enumerated. Overapplication has exactly one independently evidenced unknown returned-call residual. |
| Effects and flat? | Existing callers, parent-to-lambda relation, CFG, effect ownership and flat output unchanged. |

Fresh Sol clarifier initially left ordinal allocation OPEN and described legacy
missing-enum fallback as behavior; main inspected allocation/parent rejection,
resolved the ordinal1 premise and required explicit new-path missing-body refusal.
Clarifier confirmed no remaining OPEN. No user answer fabricated.

## User stories

### US-1: Identify callable bodies (P0)

As a protocol callgraph consumer, I want direct invocations of supported wrapped
bindings to identify the actual indexed body, so graph queries can follow that
body rather than stopping at an avoidable unknown.
Priority: measured Raw.step gap. Scope excludes callbacks, local lets, qualified
members, nested/computed opens and general value analysis.
Independent test: index a compiled recursive wrapped-function fixture and query
exact caller/site/target/kind rows against independently extracted compiler IDs.

1. Given structural step = let open M in fun x -> step x and another caller,
   when indexed, both admitted application sites target the actual synthetic step
   body, MAY_ENUMERATED, no new MUST, same pre-existing caller names.
2. Given a two-parameter wrapped body, a labeled omitted slot and an overapplication,
   when collected, supplied Some count determines partial metadata and exactly one
   unknown returned-call residual occurs only on the overapplication.
3. Given shadowed structural binders and ghost/same-location nested literals,
   when indexed, each admitted application reaches its exact root-body identity,
   not the later shadow or nested closure sharing its location.

### US-2: Preserve honest boundaries (P0)

As an index consumer, I want unsupported/missing-body cases and existing facts
preserved, so improved resolution cannot misattribute calls or manufacture certainty.
Priority: resolution must not invalidate retained graph/effect facts. Scope
excludes global enum fallback changes and any flat feature addition.
Independent test: index refusal/rejection fixtures and compare unchanged rich
and flat facts with frozen predecessor, independent of positive target assertions.

1. Given a parameter, local-let wrapped binding, nested/computed open and
   callback/letop/alias/value occurrences, when indexed, their previous rows and
   refusal reasons remain unchanged.
2. Given an admitted definition whose parent or synthetic body is rejected,
   when another caller invokes it, that new-path site is TOP/dropped_node,
   not an external/dangling enumerated leaf or an unrelated homonym.
3. Given unchanged fixed410 inputs, when candidate and predecessor are compared,
   every changed invocation requires native identity/site/body evidence; no old
   relation, point-free fact or caller/effect ownership is lost, and flat output
   remains equal on paired fixtures. Tampered/reused/wrong-body witnesses refuse.

## Prior art

Use corrected immutable OCaml5.3.0 source/manual/API table from research.md.
Typedtree arity preserves syntactic function parameters; argument options distinguish
supplied/omitted; generalized opens may be effectful, while admitted opens are paths.
No whole-program effect safety, closure target completeness or CFA is inferred.

## Proposed runnable check boundaries

CHECK-1 native authentic consumer + refusal/arity/shadow/ghost/drop + flat/effect
paired fixtures. CHECK-2 comparator and witness-admission negative controls.
CHECK-3 existing prepare-baseline.js --check plus check-baseline.js controls.
CHECK-4 fixed410 candidate comparison with independent reviewed per-site witness.
CHECK-5 exact self smoke and full Tezt guard/pristine attribution. New checker
programs still to implement under frozen plan; no check is claimed passed yet
except the separately documented preparation controls/replays and baseline332.
