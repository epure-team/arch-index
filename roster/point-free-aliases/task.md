# Task — point-free-aliases

Point-free alias propagation in the OCaml call-graph walker.

## The defect

`let f = M.g` — an η-reduced re-export with no `Texp_apply` anywhere in the body —
produces a `functions` row with **zero** outgoing call edges. The walker records an
edge only at a `Texp_apply` site, so a bare-identifier re-export produces no `calls`
row at all.

## Severity — stated precisely, not overclaimed

Both verdicts *are* emitted. `may-fail apply_operation --channel exception` on
proto_alpha answers, in one output:

```
apply_operation: UNBOUNDED (⊤): {Assert_failure, Division_by_zero}   ← apply.ml:2868, the real body
  via apply_operation.<fun:2870:23>  transitive
apply_operation: BOUNDED: {}                                          ← main.ml:393, the alias
```

`raises` agrees with `may-fail` on both nodes. So this is a **disambiguation**
defect — the tool gives the right answer and a dead answer side by side without
saying which to read — **not** a soundness or false-negative defect. Any framing
that presumes a false negative is the wrong framing.
`briefs/error-channels-qa-scope.md` row O-7 already recorded this correctly, calling
it a "pre-existing point-free-alias gap in the shared call-graph model".

## Measured extent (proto_alpha, r2-pa.db, 14452 nodes)

| Stratum | Count |
|---|---|
| nodes with zero outgoing edges | 3021 |
| … one-line AND arrow-typed | 620 |
| … of which qualified aliases (`M.g`) | 248 |
| … of which local aliases (`g`) | 87 |
| … of which genuine leaves / identities / η | 285 |
| homonym names (≥2 nodes) | 540 |
| … with a zero-edge node AND a live node simultaneously | **117** |

Concentration by file: `alpha_context.ml` 56, `storage.ml` 26,
`storage_functors.ml` 14, `dal_slot_repr.ml` 10, `main.ml` 5 — the protocol API
facade. The two protocol entry points are themselves aliases:
`main.ml:393 let apply_operation = Apply.apply_operation` and
`main.ml:395 let finalize_application = Apply.finalize_block`.

## Central design decision to resolve

- **A MUST call edge alias→target.** Trivial; every consumer works immediately.
  But it misrepresents the relation — the alias does not *call* the target, it *is*
  it — and pollutes fan-out/fan-in metrics and arch-rules layering verdicts.
- **An alias relation outside the call graph.** Honest. But every consumer must
  learn to follow it: `may-fail`, `raises`, `reachable-from`, `reaches`, `fan-in`,
  `arch-rules`, `arch-impact`, `arch-coverage`, `arch-mutants`, MCP.

## Hard external constraint

The peer session's roadmap-1.6 qualified-unit resolver (branch
`feat/qualified-unit-resolution` @8c1cad0, implemented, **not merged**) has an S4
disambiguator resting on the premise *"exactly one reading touches the functions
table"*. That premise assumes a point-free alias defines no `functions` row — which
is **false** on this corpus: `main.ml:393` IS a `functions` row today, which is
precisely why a second verdict exists.

The spec must record this in both directions:
1. our change must **not add** a `functions` row (the alias already has one), and
2. the peer must re-verify the S4 premise against this corpus before merging.

Implementation is sequenced **after** the peer's resolver merges (alias target
resolution goes through it). The spec phase runs in parallel.
