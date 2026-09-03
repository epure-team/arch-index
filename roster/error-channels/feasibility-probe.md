# Feasibility probe — carrier typing in `.cmt` (2026-09-03)

Run with `scratchpad/carrier_probe.ml` (compiler-libs, reads one `.cmt`, prints the return type
of each `value_binding` and the type of each `Texp_apply`'s function expression, after stripping
`Lwt.t`). Corpus: `proto_alpha/…/tezos_raw_protocol_alpha__Apply.cmt`.

## Q1 — Is the error TYPE ARGUMENT present? **Yes.**

```
BINDING_RET apply_delegation :
  Tezos_protocol_environment_alpha.Pervasives.result[?; Error_monad.trace<Error_monad.error>]
```

The second type argument's head is `trace`, and *its* argument is `error`. So the spec's carrier
check (`error_arg` head ∈ {`error_type`} ∪ `unwrap`-of-`error_type`) is computable from the raw
`Tconstr` alone — no `Ctype.expand_head`, no `Env`, which the walker deliberately never uses.

## Q2 — Are both spellings really needed? **Yes, in the same file.**

The alias `…Error_monad.tzresult[X]` (one type argument — the error type is fixed by the alias)
and the underlying `…Pervasives.result[X; trace<error>]` (two) both occur in `Apply.cmt`.
Consequence for the config vocabulary, to fold into the implementer brief: `error_arg` applies to
the **underlying** spelling only; for an alias carrier the error type is implied by the alias, so
`type` entries must be accepted with *either* arity and `error_arg` treated as
"not applicable" when the head matches the alias path. The `underlying`/`aliases` lists are
mandatory, not a nicety.

## Q3 — Can the producer tell a callee is a carrier WITHOUT indexing the callee's unit? **Yes.**

```
CALLEE_TYPE Tezos_protocol_environment_alpha.Error_monad.tzresult[Alpha_context.context]
CALLEE_TYPE Tezos_protocol_environment_alpha.Pervasives.result[unit; trace<error>]
```

The callee's type is available **at the call site** on the `Texp_apply`'s function expression, so
carrier-ness is a *local* property of the edge — the producer stamps
`exn_edges.channel` at emission and never needs cross-unit resolution or a second pass. This kills
the "how do you know the callee is a carrier at producer time" objection outright and removes the
only design pressure toward a post-pass in `arch_index.ml`.

## Consequences for the plan

- The carrier check is intra-file and cheap; no new resolution machinery.
- Slice ordering can put the producer's edge tagging early, since it needs nothing from the
  resolver.
- The config must accept an alias carrier whose `error_arg` is not applicable (see Q2) — a spec
  amendment, folded into the implementer brief rather than re-opening the spec.
