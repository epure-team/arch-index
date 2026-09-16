# Specification working input — not a validated spec

2026-09-15. Intake VALIDATED under explicit autonomous Roster authorization.
Independent research: cfa_spec_research (Sol); clarifier: cfa_spec_clarifier (Sol).
No implementation or specification completion is claimed by this working file.

## Clarifications

| Q | A |
|---|---|
| Which old TOP forms change? | Only nonrecursive single-variable alias chains, same-CMT top-level aliases visible inside a callable, known-function/literal values and if/match/sequence result joins. Returned-function flow, general patterns, captures, recursive transfer and partial closures remain excluded. Existing direct support remains. |
| Does unknown absorb candidates? | No: finite target set and independent finite unknown-reason set, joined by componentwise union; explicit bottom. The exception worklist is closer prior art than scalar guard Top. |
| How are identities distinguished? | Per-CMT compiler binder identity and physical expression occurrence, never location-only lookup. Existing collector remains authoritative for literal display names and collision ordinals. |
| What is the batch boundary? | Entire CMT, including eligible value-only bindings, with finalization after all actual literal names are observed. Shared semantics in main and flat. |
| Must flat adopt main caller names? | No: retain the established flat bare caller namespace; main preserves stored shadow names. Candidate identity must not silently collapse when flat cannot faithfully represent an identity; this boundary needs adversarial examination. |
| What survives expansion? | Every occurrence's caller/site/partial/cond/dead/scopes/channel facts, plus independent residuals. Dedup within occurrence only; point-free predecessor edges unchanged; ordinary CFA edge_form NULL. |
| Is a proof-chain schema required? | No: source/run/actual target-origin provenance only. No new kind or edge_form token. Bounded internal diagnostics are not certificates. |

No user questions asked at clarification. These answers derive from intake and
live code, not fabricated human responses. Clarifier wording “values produced by
named known functions” means function identities as values, NOT results of calls.

## User stories

### US-1: trustworthy finite value propagation (P0)

As an analysis developer, I want function candidates and unknown contributions
propagated to closure so I can consume a deterministic conservative result.
Priority: incorrect joins would invalidate all downstream absence conclusions.
Scope: no OCaml evaluator, public embedding API, numeric domain changes or proof graph.
Independent test: a pure finite-cell solver probe checked against independent
set-closure enumeration, with no compiler or database dependency.

1. Given cells a,b,c and target f seeded at a with copies a→b→c,
   when the solver runs, then c contains f and no unknown contribution.
2. Given branches containing f and opaque reason r, when joined into c,
   then c contains both f and r; neither contribution absorbs the other.
3. Given a finite copy cycle a→b→a seeded with f, when constraints are
   reordered/duplicated and solved, then closure terminates with identical sets.
4. Given two unseeded cells in a cycle, when solved, then the pure solver returns
   bottom; a consumer must not mistake that for a closed impossible callable.

### US-2: authentic CMT targets without lost facts (P0)

As a graph-query consumer, I want supported function-value applications linked
to actual source targets so unresolved heads shrink without concealing uncertainty.
Priority: a detached solver does not improve Irmin/protocol callgraph data.
Scope: same-CMT explicit stage2 fragment, no argument/return/capture/recursive
transfer, partial closure flow, functor substitution or independent variant reuse.
Independent test: compile benign synthetic OCaml fixtures, run actual main and
flat producers, inspect their consumer outputs and query verdicts.

1. Given top-level `let f x = x`, `let a = f`, `let b = a`, and
   `let run x = b x`, when indexed, then run's supported indirect occurrence
   names the actual f target as MAY_ENUMERATED, not MUST; alias declarations
   retain their immediate predecessor value_alias facts.
2. Given a callable selecting between two collector-promoted literals and
   applying that selection, when indexed, then both actual distinct literal
   identities are candidates even under equal/ghost source locations.
3. Given a branch selecting known f or an opaque callback parameter, when
   indexed, then the occurrence keeps f plus an explicit unknown frontier;
   unsupported captures/returned values cannot become closed by unit visibility.
4. Given conditional, dead, partial and overapplied supported occurrences with
   exception/value-channel scopes, when expanded, then each occurrence retains
   its metadata and independent residuals, including two calls on one source line.
5. Given an unobserved/rejected body or a candidate that cannot be represented
   faithfully by a producer, when finalized, then it remains explicitly unknown
   rather than becoming a silently bounded missing target.

## Load-bearing prior art and consistency

Read research.md external sources: Might's finite abstract-state saturation;
Darais et al. joined stores/cache iteration; OCaml5.3 compiler identity vs5.5 API.
Neither prescribes universal unknown closure or derivation provenance. A sparse
copy worklist is an intentional stage2 subset, not full higher-order 0CFA.
Guard's absorbing numeric Top cannot replace the product target/unknown domain.
Existing exception worklist retains known paths with unknown reasons
(`specs/exn-raise-sets.md:35,164`).
Historical opposite assertions: residual-targets FR005–007/016 and AC11,
local_value_targets121–124, callgraph_soundness197–203. Refine only the new
supported subset, never redefine prior measured results or weaken MUST/TOP rules.
SQL edge_form and kind vocabularies stay closed. Flat caller namespace differs
from main (`call_graph_extractor.ml:303-338`), requiring an explicit identity test.

## Candidate runnable check boundaries

Planned, not implemented/run: standalone scripts in this roster directory for
domain closure, authentic extraction/query + metadata, and pinned Tezos replay.
Each returns 0 pass, 1 assertion, >=2 setup/error. Native fixtures registered in
CI; pinned external corpus may be unavailable in CI and must report that honestly.
Frozen stage1 baseline remains unchanged; gains/losses separately accounted for.
