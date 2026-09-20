# Roster intake — Tezos defensive sentinel contract

## Authority and outcome

The user approved the defensive Tezos programme on 2026-09-20.  This first
intake is a specification-only gate for the implementation sequence.  Its
outcome is a reviewed, bounded contract for the first three structural
sentinels:

1. reachable crash and unfinished-code paths (P2/P7);
2. work performed before an explicit resource charge (P4);
3. feature/default/ACL policy evaluation (P7/P8).

It intentionally does **not** claim to identify a vulnerability, prove protocol
correctness, validate a cryptographic proof, infer gas adequacy, or turn `MAY`
or `TOP` into a safety verdict.

## Why this precedes implementation

The existing Tezos evidence has useful but incompatible scopes: the protocol
crash report is a lower-bound call-graph traversal; error channels are
partial; P1/P3/P5/P6 require semantic or temporal models; the local Tezos
checkout is dirty and must not become an implicit test fixture.  A shared
contract prevents a later implementation from silently treating omitted
artefacts, configuration, FFI, callbacks or unresolved edges as absence.

## In scope

- Define the common input manifest: exact source/artifact/build configuration,
  root set, supported language fragment, policy version and external/FFI
  assumptions.
- Freeze common statuses: `COMPUTED`, `NOT_ANALYSED`, `REFUSED`, `FRONTIER`;
  define non-vacuity and the display of `MUST`, `MAY_ENUMERATED`, and `MAY_TOP`.
- State the individual obligation shapes and their required witnesses:
  `root -> origin`, `input -> work -> charge`, and `config -> policy -> route`.
- Define the implementation order and stop criteria for the three sentinels.
- Give benign, owned fixtures and independent oracle requirements.

## Out of scope

- A generic abstract interpreter, a generic taint engine, or a global Tezos
  graph.
- Any live-network probe, exploit, vulnerability filing, private campaign
  material, or modification of the Tezos checkout.
- P1 refutation proof semantics, P3/P6 accounting, and P5 liveness.  They are
  separate later Roster tracks because their required properties cannot be
  discharged by these structural signals.
- Promotion of any sentinel to a blocking CI gate in this intake.

## Required artefacts

1. `specs/tezos-defensive-sentinels.md`, with status, provenance, fixture and
   report contracts.
2. A decision ledger mapping P1–P8 to the structural sentinel, a later
   semantic harness, or an explicit non-goal.
3. A Roster review that checks non-vacuity, uncertainty handling and the
   separation between evidence and security conclusion.
4. Documentation routing the user to the future non-blocking CI use case.

## Acceptance criteria

- Every report has a versioned manifest and identifies its roots and frontier.
- Empty selectors, missing artefacts, incompatible schema, unsupported input
  or absent policy produce a refusal/not-analysed status, never a clean result.
- A `MUST` path and a `MAY_*` path are visibly distinct; `MAY_TOP` is never
  hidden by a count or aggregation.
- Each structural sentinel names the exact local relation it can observe and
  the semantic property it cannot establish.
- Each proposed fixture has an independently specified expected result,
  including at least one incompleteness/refusal control.
- The implementation order is P2/P7, then P4, then P7/P8 policy; any next
  slice must pass its own Roster, local checks, hosted CI and guarded merge.

## Evidence consulted

- `docs/crash-surface-proto-alpha-2026-09-06.md`
- `docs/error-channels.md`
- `docs/exception-raise-sets.md`
- `/home/mathias/notes/2026-09-15-tezos-patterns-defaillance-outils-analyse.md`
- `/home/mathias/notes/tezos-pattern-variants-2026-09/{roadmap,status,patterns}.md`
- existing `roster/origin-class-precision/` and
  `roster/vuln-reachability-triage/` intakes.
