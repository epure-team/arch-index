# Tezos defensive sentinels — contract v1

This document specifies a small family of defensive review signals.  It is not
a vulnerability scanner and does not change Tezos protocol semantics.

## Common result envelope

Every future sentinel result is one versioned object containing:

- `sentinel`, `schema_version`, `availability` and `reason`;
- a manifest of source revision, artefact digests, producer version, selected
  roots, configuration/policy digest and declared external/FFI assumptions;
- `scope`, `results`, `frontier` and `limitations`.

`availability` is one of:

| Value | Meaning |
| --- | --- |
| `COMPUTED` | The declared fragment ran against the manifest inputs. |
| `NOT_ANALYSED` | The requested property or input is outside the supported fragment. |
| `REFUSED` | A required input, identity, schema, non-vacuity condition or policy is invalid or absent. |
| `FRONTIER` | A required relation crosses an unresolved call, external, FFI, callback or other named boundary. |

An empty `results` list is meaningful only with `COMPUTED`, a non-empty declared
scope and an explicit frontier census.  It never means absence of defects.

Call-path evidence retains its edge kinds.  `MUST` is a proven relation in the
indexed graph; `MAY_ENUMERATED` is a finite candidate relation; `MAY_TOP` is an
open frontier.  None is a statement that a runtime input reaches the path or
that a crash/security outcome occurs.

## Sentinel S1 — crash and unfinished-code paths (P2/P7)

### Observed obligation

An S1 row is an attributed path from a declared root to an explicit origin:

```text
root -> call-path -> origin(form, guard-class, source-location)
```

`form` is a producer-defined exception or unfinished-code form.  `guard-class`
must distinguish at least unconditional `assert false`, checked assertions,
and statically impossible literal division origins when that fact is proven by
the typed tree.  The source surface (protocol/PVM/environment/baker/RPC/etc.)
is configured by an explicit mapping; unclassified paths are reported as such.

### Does not establish

S1 does not establish that a guard is satisfiable, an assertion is wrong, an
exception escapes a runtime boundary, or that an unavailable feature is
reachable in a supported deployment.  Missing CMT, external calls and `TOP`
must remain a frontier/refusal rather than suppressing a row.

### Required controls

Owned fixtures cover: a reachable `assert false`; a checked assertion; a
non-zero literal divisor omitted only after typed-tree proof; an unknown
divisor retained; a disabled-feature entry rejected at its boundary; and a
missing-artifact refusal.  Each fixture’s expected row or status is specified
without invoking the producer under test.

## Sentinel S2 — work before resource charge (P4)

### Observed obligation

S2 is target-specific.  A policy declares source APIs, bounded work APIs,
charge/admission APIs and dimensions such as `bytes`, `depth` or `items`.  A
row has the shape:

```text
input/source -> declared work -> declared charge/admission | named frontier
```

The report records the policy rule, source locations, path edge kinds and which
dimension is present or absent.  It is an obligation for review, not proof of
an unmetered denial of service.

### Does not establish

S2 cannot infer asymptotic complexity, allocation, upstream admission,
effective gas price, or adequacy of a charge.  If ordering cannot be derived in
the supported local fragment, it is `FRONTIER`/`NOT_ANALYSED`, never
`COMPUTED`-safe.

### Required controls

Fixtures include an admitted bounded decode, a decode before a declared charge,
an external decoder frontier, an unknown dimension, and an absent policy
refusal.  The policy vocabulary is closed and unknown keys refuse.

## Sentinel S3 — feature/default/ACL policy (P7/P8)

### Observed obligation

S3 evaluates a finite, pure policy model over explicit configuration inputs:

```text
configuration -> effective feature/ACL decision -> declared route/entry action
```

It reports the selected rule, precedence trace and configuration digest.

### Does not establish

S3 does not discover deployment topology, proxy behaviour, identity
authentication, route registration or undocumented configuration semantics.
Those inputs must be supplied by a target-owned adapter and otherwise produce
`NOT_ANALYSED` or `REFUSED`.

### Required controls

The fixture matrix covers deny-by-default, explicit allow, exact override over
a wildcard, feature-disabled entry rejection, ambiguous/duplicate precedence,
and missing deployment policy.  A route not in the model is not a pass.

## Sequencing and gates

1. Land/reuse `origin-class-precision`, then implement S1 as a non-blocking
   report with paths and visible frontiers.
2. Qualify its reproducible corpus/manifest and add a recurring consumer only
   after stable semantic identities exist.
3. Implement S2 as a separate policy-driven checker; do not share a database
   schema until a second consumer proves the need.
4. Implement S3 as a pure evaluator with target-owned adapters.
5. Start separate semantic harnesses for P1, P3/P6 and P5 only with their own
   models and independent oracles.

Every step requires Roster review, local green controls, hosted CI on the exact
PR head and a guarded merge.  Worktrees and build artefacts owned by a step are
removed after merge.  The dirty Tezos checkout is never an implementation
target.

## P1–P8 disposition

| Pattern | First handling |
| --- | --- |
| P1 proof/refutation | Separate semantic refinement and binding harness. |
| P2 exceptions | S1. |
| P3 arithmetic | Separate exact numeric/property model. |
| P4 resource bounds | S2. |
| P5 liveness | Separate automaton/timeout model. |
| P6 staking/slashing | Separate transition/accounting model. |
| P7 unfinished features | S1 plus S3 entry-policy model. |
| P8 defaults/ACLs | S3. |
