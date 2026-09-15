_Generated: 2026-09-15_
_Routine question gate covered by explicit autonomous Roster authorization; no task text included._

1. How does the codebase currently represent function identities, value-producing expressions, call targets, and unknown or unresolved contributions?

2. What data flow currently carries literals, aliases, and their source provenance from CMT extraction through persistence and query results?

3. Where are constraints or dependency relationships presently created, stored, and propagated, and what termination or deduplication mechanisms exist in the analysis loop?

4. How does the current implementation combine independently derived known and unknown target information at joins, assignments, and call sites?

5. What support currently exists for parameters, return values, captured variables, recursion, and partial application in the extractor, intermediate representation, and database schema?

6. How are module and functor applications represented today, and what target-resolution information survives compilation-unit boundaries?

7. Which existing queries, fixtures, and end-to-end tests characterize call-target precision, provenance, unresolved targets, and behavior on Tezos-derived inputs?

8. [ecosystem] How do existing finite-domain 0CFA implementations define lattice joins, unknown values, worklist convergence, and provenance tracking?

9. [ecosystem] What information do current OCaml compiler-libs CMT APIs expose for closures, aliases, applications, partial applications, modules, and functors?
