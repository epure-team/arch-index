# Tranche2 integration notes — read-only design

Implementation remains required. This supplements, not replaces, the validated
spec and plan. Derived from independent Terra collector examination and root
corrections; no new behavior or passing test is claimed here.

## Cells and ownership

Extend the existing deferred session with physical-expression cells and binder
metadata. Only eligible structure binders have Unit visibility. Local binders
belong to an opaque callable or initializer owner. A local let in a top-level
initializer is NOT a Unit binder: moving into its returned lambda crosses an
owner boundary. Read a binder's value only if Unit-visible or same-owner;
otherwise retain callback_param as an unsupported capture contribution.

For a nested literal there are two roles: its value is constructed in the
parent evaluation owner, while its body is visited in a fresh callable owner.
Do not equate those roles when reconciling literal observations and captured
binders. The collector's actual context transitions can allocate opaque tokens;
an owner token is not a display name or a source coordinate.

Do not identify owners, literals or application occurrences by source positions
or display names. Positions can collide; collector names carry ordinals.

## Transfers

- Plain nonrecursive local lets copy RHS values into binder cells.
- If and match join every normally-returning RHS; match exception-case RHSs
  participate, guards and scrutinees do not become result values.
- Pattern-bound values are unknown, not general pattern transfer.
- Sequence returns its last expression value; prefix calls/effects remain the
  authoritative collector's responsibility.
- Applications as values, returned functions, argument transfer, captures,
  recursive groups, general destructuring and new module transfer stay excluded.
- Do not add a Texp_try transfer merely because it resembles a branch join;
  the specified exception-case coverage is for Texp_match.

## Authoritative literals

A physical literal descriptor starts without an accepted target name. Reconcile
with the existing collector's assigned name/owner, then the producer's actual
storage/availability outcome. Main lambda insert success and failure are the
authorities, not the prepass's predicted spelling. Missing/rejected/wrong-owner
known body evidence stays dropped_node; unsupported captured binder flow stays
callback_param. Finalize after the entire CMT, as in the repaired lifecycle.

Flat cannot pretend to have main's successful DB insertion. Its own faithful
unique representation guard governs bounded output; otherwise exact TOP/null.

### Concrete integration seams (inspected 2026-09-16)

The existing collector's `Texp_function` branch assigns the final synthetic
name before entering a new `lctx`. Observe the literal there with its physical
expression, parent evaluation owner and newly allocated body owner. Keep these
descriptors internal to the CFA session; no `lambda_node` record expansion is
needed. Main's existing lambda insertion loop can acknowledge the actual name
only when exactly one observed descriptor has it. A storage success is not an
invitation to synthesize a descriptor for an unknown name. Rejection, missing
observation, conflicting owner or ambiguous name must never seed a target.

`expr_cell` must obtain the same descriptor-backed cell for the same physical
literal and evaluation owner. The legacy `lam_names` and `binding_literals`
tables are location-keyed: they are not CFA identity authorities. A physical
expression map must compare keys physically; source positions can be used for
hash buckets only if equality still distinguishes colliding expressions.

OCaml 5.3's installed `compiler-libs/typedtree.mli:214-222` confirms the exact
match layout: the second field contains computation cases (ordinary and
exception patterns), while the third contains effect cases. Join RHS values
from both lists. Calling the third list the ordinary cases is incorrect and
would silently discard normal match branches.

Flat has no stored synthetic lambda rows to acknowledge. Keeping these literal
targets unbounded there is intentional; root named targets remain eligible
under the existing unique same-file guard. Main and flat need not report the
same precision.

## Minimal authentic fixtures to implement test-first

```ocaml
let root x = x
let a = root
let run x = let b = a in b x
```

Main run reaches actual root as ordinary MAY_ENUMERATED; alias predecessor
facts remain separate. Flat bounds only when its representation is faithful.

```ocaml
let run choose x =
  let f = if choose then (fun y -> y) else (fun y -> y + 1) in
  f x
```

Require two actual stored collector identities and no lost frontier; do not
hard-code a guessed synthetic name. Add equal/ghost-position controls later.

```ocaml
let root x = x
let outer =
  let captured = root in
  fun tag x ->
    let picked = match tag with true -> captured | false -> root in
    (ignore (root x); picked x)
```

The direct prefix call survives. The picked head retains root plus unknown
capture, rather than closing through a local initializer binder. Native checks
must distinguish the prefix from the picked physical occurrence.
