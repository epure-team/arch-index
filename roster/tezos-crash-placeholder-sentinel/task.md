# Roster intake — reachable crash and unfinished-code sentinel

## Objective

Deliver a non-blocking, reproducible P2/P7 review signal over an explicitly
qualified index.  Its rows must let a reviewer answer: which declared root can
reach which explicit crash/unfinished-code origin, through what edge kinds,
under what source/guard classification, and where does the graph stop being
complete?

## Reuse and dependencies

This intake composes, rather than replaces:

- `origin-class-precision`: typed-tree proof that a non-zero literal divisor
  cannot fail, and `assert false` versus checked assertion vocabulary;
- `arch-query escaping-origins`: origin inventory rooted at an explicit entry
  set;
- `arch-rules forbid origin`: policy verdicts and graph witness-path machinery.

The origin-precision change must land first or be carried as an explicitly
reviewed dependency.  This intake must not reimplement its producer logic.

## Required product contract

1. A versioned report has manifest, declared root selector, result rows and a
   frontier census.  A root selector that is empty, unsupported or incompatible
   with the index refuses rather than reporting no findings.
2. A row has origin form, source location, source-surface classification,
   guard class, reachability class and a source-to-origin witness when the
   graph establishes one.  `MUST`, `MAY_ENUMERATED` and `MAY_TOP` remain
   distinguishable.
3. `assert false` is distinct from a checked assertion.  Only typed-tree-proven
   non-zero literal divisions are absent; variable and unsupported divisors
   remain origins/frontiers.
4. Unfinished feature paths require an explicit target-owned entry/configuration
   policy.  An absent policy never turns into "unreachable".
5. The first consumer is informational CI/reporting only.  It cannot gate on a
   count, absence, MAY path or frontier; promotion requires a later stable
   policy intake.

## Non-goals

No proof that an assertion is satisfiable, a feature is exploitable, an
exception reaches a consensus boundary, or Tezos deployment configuration is
complete.  No live Tezos action, target modification or external-source scan.

## Acceptance controls

- owned compiled fixtures for `assert false`, checked `assert`, literal
  non-zero/zero and unknown divisors, a MUST path, a MAY path, and a TOP path;
- refusal fixtures for empty roots, flat/old index and missing source policy;
- independent witness/path and report-order oracle; report formatting cannot
  compute its own expected result;
- an exact pinned Tezos corpus replay is observational only: it publishes
  scope/frontier/deltas and never a defect count as a security metric.

## Delivery sequence

1. Research/specification and compatibility inventory.
2. Land the prerequisite origin-class precision changes with their own tests.
3. Implement the report/consumer and owned controls.
4. Requalify a pinned corpus; add docs and non-blocking CI example.
