# Candidate stories — guard-division-analysis

## US-1: attributable primitive inventory (P0)

As an OCaml library maintainer, I want explicit CMT inputs turned into a stable syntax inventory
so that I know which native integer division/remainder occurrences were inspected and which were not.
Why P0: an empty or silently partial inventory would make every later semantic result misleading.
Scope: no numeric proof, call expansion, source scanning or existing DB mutation.
Independent test: compile a native fixture and validate inventory/metadata without depending on numeric precision.

1. Given maintainer-compiled fixture with native div/mod,int32/int64/nativeint variants and partial (/)1, when --cmt fixture.cmt --format json runs, then every immediate primitive application appears with original slot2 syntax/category and artifact attribution.
2. Given a locally shadowed (/) returning addition, when the same inventory runs, then its nonprimitive application is not classified as native division; a genuine Stdlib.( / ) occurrence still is.
3. Given the same artifacts in reversed/repeated argument order, when both runs execute, then canonical JSON bytes match and each physical artifact is counted once.
4. Given one valid artifact and one missing/incompatible/interface input, when run together, then exit2, stderr diagnostic and no complete stdout report; valid prefixes do not become a success.
5. Given an implementation with no matching primitive occurrences, when inspected, then empty inventory/census explicitly scoped to supplied artifacts, no safety claim.

## US-2: bounded numeric classification (P0)

As an OCaml library maintainer, I want a separate semantic status for each inventoried operation
so that local values and guards can distinguish routine nonzero divisors from unresolved or zero cases.
Why P0: closes the current syntax-only precision gap while preserving existing rule semantics.
Scope: native int acyclic fragment only; loops/handlers/defaults/other integer families and interprocedural execution are excluded.
Independent test: domain laws and a compiled behavioral fixture validate classifications independently of origin-rule or SQLite results.

1. Given functions dividing by literal2 and by let d=2, when analyzed, then each divisor is NONZERO; literal0 is ZERO and an unrestricted parameter is MAY_ZERO.
2. Given if d=0 then 0 else 10/d and if d<>0 then10/d else0, when analyzed, then division sites are NONZERO; an alias created inside the refined branch copies its current facts but a new shadowing binder does not. No retroactive relational propagation to an alias created before the guard is required.
3. Given let d=if b then0 else2 in10/d, when analyzed, then MAY_ZERO; given nested contradictory d=0 and d<>0 branch, then contained supported division is UNREACHABLE.
4. Given possible modular overflow yielding zero, when transferred, then zero remains in the abstract result (possibly top), never false NONZERO; bounded concrete containment and31/63 edge tests pass.
5. Given nested fun()->10/d created under d<>0, when analyzed, then captured d is fresh top/MAY_ZERO, not inherited NONZERO; nested local let x=2 still permits NONZERO outside unsupported regions.
6. Given division under loop/try/default/function-case or partial application/int64 divisor, when analyzed, then UNSUPPORTED with reason, retained in census even under a contradictory outer branch.
7. Given ordinary opaque call returning d, when d is used as divisor, then MAY_ZERO; successful command remains exit0, not a safety acceptance.
8. Given existing arch-index self golden/rules/reference, when full regression gates run after adding component, then original semantics and counts remain unchanged.

## US-3: interpretable experiment result (P1)

As a reviewer of this experiment, I want a report separating inventory size, numeric coverage and observed precision
so that I can judge whether extending the analysis is useful without treating fixture success as production impact.
Why P1: required delivery evidence and usability, independent of a chosen domain's internals.
Scope: no CI policy enforcing semantic statuses, no new artifact publication service, no source-to-CMT proof.
Independent test: validate report census equality/status distinctions, text/JSON agreement and real owned-library execution.

1. Given native fixture outputs, when rendered text and JSON, then all five statuses and reasons/census agree, supported/unsupported denominator visible.
2. Given compiler inputs, when report generated, then compiler version,int width,scope,input digests,analysis limitations and report-only exit contract present; no timestamp-induced nondeterminism.
3. Given owned lib/arch_index artifacts, when run during QA, then actual site/status counts recorded even if0; no automatic corpus expansion to manufacture benefit.
4. Given a configured deterministic input/traversal/output limit is exceeded, when run, then error2 and no complete stdout, not truncated successful evidence.
