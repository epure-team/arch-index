# Architecture Plan — independent voice 2

## Recommended shape

Use an explicit, width-parameterized `Int_fact` abstract domain for native
`int`: `Bottom | Values of { interval; may_be_zero }`, where an interval has
finite signed-width endpoints or unbounded extrema.  `Top` is the ordinary
full signed range with `may_be_zero = true`; it is not `Bottom`.  The domain
must include intersection-based refinement for `= 0` and `<> 0`, a sound join,
and transfer functions that widen to `Top` whenever modular wrapping makes an
unbounded-integer result unsound.  Constants and immutable aliases therefore
prove `2` nonzero; `0` is zero; an unknown parameter is may-zero; conflicting
branch constraints are bottom.  A nonzero interval with no zero is sufficient
for `NONZERO`; exact zero is sufficient for `ZERO`; all other reachable facts
are `MAY_ZERO`.

This is simpler than a disjunction-heavy domain while meeting the required
literal, alias, guard, join, and overflow cases.  It must be parameterized for
small-width containment tests and 31/63-bit cases; production records the host
`Sys.int_size`.  Arithmetic is only precise when a no-wrap proof is available;
otherwise it returns `Top` (with a separately safe constant-zero result only
where applicable).  Division and remainder transfers never perform a concrete
division with a possibly-zero divisor and may simply return `Top`.

## Sequential vertical slices

1. **Freeze the public contract and component boundary.** Create the isolated
   `lib/arch_guard/`, `bin/arch_guard/`, root `arch-guard` wrapper, test-fixture,
   documentation, README, and CHANGELOG surfaces without touching existing
   extraction/rule libraries.  Before code, freeze CLI flags, resource bounds,
   input acceptance/dedup/rejection rules, closed JSON schema, deterministic
   text ordering, status/reason vocabulary, and exit mapping.  Define report
   records so syntax inventory, semantic verdict, census, artifact provenance,
   and trusted assumptions are all representable.  This slice is independently
   testable as command parsing/output-schema and empty-report behavior.

2. **Build trusted-artifact intake plus complete syntax inventory.** Accept
   only explicit canonical physical CMT implementation paths; reject symlinks,
   interfaces, packed/partial/wrong-compiler artifacts, duplicate module/source
   identities, and read instability via before/after digests.  Traverse every
   accepted typed tree for the eight compiler `Val_prim` div/mod identities,
   retaining source location and operand category, including partial applications
   as inventory-only unsupported sites.  Keep int32/int64/nativeint sites in
   the inventory with `UNSUPPORTED`; direct native-int sites are candidates for
   the next slice.  Test this end-to-end using compiled owned fixtures, stable
   JSON/text snapshots, duplicate handling, and failure-with-no-complete-JSON.

3. **Implement the numeric core as a standalone law-tested library.** Add the
   width-aware domain, environment keyed by compiler identifier identity, pure
   arithmetic transfer, restriction, join, and classification functions.
   Require bounded exhaustive concrete-to-abstract containment at small widths,
   plus 31/63-bit extrema, wrap-to-zero, bottom, join/idempotence, and monotonic
   refinement tests.  This slice cannot depend on CMT traversal and supplies
   the semantic engine with an auditable API; conservatively widening on
   overflow is a correctness requirement, not a precision regression.

4. **Add the bounded intraprocedural interpreter and attach verdicts to the
   inventory.** Interpret direct native-int expressions, immutable local
   bindings/aliases, sequencing, supported arithmetic, and pure `if` branches.
   Resolve zero equality/inequality guards through typed identities and use
   identifier identity to respect local shadowing.  Analyze nested functions as
   fresh contexts with unknown parameters/captures.  Mark calls, loops,
   recursion, handlers, effects, mutation/heap dependence, optional/default
   semantics, and unsupported structural regions with explicit `UNSUPPORTED`
   reasons; no such site may inherit `NONZERO` or `UNREACHABLE`.  Reconcile each
   raw inventory site exactly once, guaranteeing that the inventory remains
   complete even where semantic interpretation stops.  Fixture assertions cover
   aliases, guards, contradictory branches, joins `0|2`, unknown calls, nested
   captures, shadowed operators, partial application, and unsupported regions.

5. **Finish reporting, integration, and honest measurement.** Wire the CLI to
   emit sorted reports with tool/compiler/int-width metadata, path/digest/module,
   artifact scope/counts, site records, reasons, and raw-vs-semantic census;
   report useful `NONZERO`/`UNREACHABLE` distinctions separately and expose the
   unsupported denominator.  Successful reports always exit 0, including
   `ZERO`, `MAY_ZERO`, `UNSUPPORTED`, and empty inventory; only command/input/
   internal failures exit 2.  Add Tezt checks using the prescribed 0/1/>=2
   mapping, run against owned fixtures and the owned library (reporting zero
   sites if that is the result), then run the specified build, suite, baseline,
   consumer, artifact-validation, and exact-head CI gates without changing their
   corpus, rules, or references.

## Dependencies and decision points

`1 → 2` fixes observable acceptance/report semantics before artifacts are read.
`3` may proceed after the report types in `1`, and `2 + 3 → 4`; `4 → 5` completes
the vertical CLI behavior.  No new dependency is indicated: compiler-libs and
already installed project dependencies should suffice.  If that proves false,
the plan requires an explicit justification rather than a global installation.

## Assumptions and risks

- CMT provenance/freshness, compiler compatibility, and host-width/target-width
  correspondence are trusted assumptions reported to users, not verified facts.
- Typed primitive identity is the only authority for recognizing operators;
  source spelling must never create a site.
- Precision risk is deliberately traded for soundness at overflow and unknown
  calls.  The domain must never use mathematical integer arithmetic to prove a
  wrapped expression nonzero.
- Filesystem checks mitigate ordinary races but do not promise adversarial
  atomicity.  A mid-read change is a hard error, never a partial report.
- Unsupported execution constructs are semantically contagious for sites whose
  reachability/value requires them; syntax inventory still records them.

## Open questions / direction changes

There are no unresolved implementation questions in the intake.  This plan
does not recommend changing task direction, scope, dependencies, or the stated
trust boundary.
