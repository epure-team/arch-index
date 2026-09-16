# Pinned410 delta explanation

This accounts for the preliminary producer `e0732753…` observation, not a
universal soundness proof or final review verdict. Permanent CHECK3 subsequently
confirmed the exact same current output (exit0), report
`improvement/2026-09-15-ocaml-cfa/check3-1789552519843-3582125.json`.
Root checked its digest, complete delta counts and stability flags. Measured
wall2929.279ms, sampled Linux RSS144928KiB; no portable peak-memory claim.
Baseline45052/current45054 canonical rows; removed8/added10; relations+3/-0.

## Newly bounded rows

Protocol `raw_context.ml`: `block_gas_level` aliases `remaining_block_gas` at
line613. The two applications in `consume_gas_limit_in_block` at624 and628
change from callback TOP to the actual same-file `remaining_block_gas` target,
ordinary MAY with null TOP fields. They contribute two new protocol relations.
The immediate binding fact is not replaced by the invocation refinement.

Irmin `dot.ml`: the two `Make.fprintf` anonymous callers at90:23 and99:23 apply
a conditional function value at92 and102, respectively. The identity-function
branches have collector targets at94:15 and102:65. Each gains one ordinary MAY
row; the other branch's unknown contribution remains. The second relation key
already existed for another row at the same displayed site, so two added rows
yield only one new Irmin relation. This is why row multiplicity and relation
sets are reported separately; displayed coordinates alone do not prove physical
application identity.

## Display-only changes, not resolution gains

Six callback TOP rows retain caller/site/kind/reason/anchor and null target,
but replace the displayed unresolved name with `*TOP*`:

- `tez_repr.ml:189`, `mul_percentage`, previously `div'`;
- `script_ir_translator.ml:306` and315, two `ty_eq` anonymous callers,
  previously `record_trace_eval`;
- `sapling_repr.ml:163`, `output_in_memory_size` anonymous caller,
  previously `ciphertext_size`;
- `percentage.ml:52`, `of_q_bounded`, previously `div`;
- `apply.ml:612`, `apply_transaction_to_smart_contract`, previously `execute`.

These are explicit diagnostic-name changes, not eliminated unknowns. They
account for six of the eight removals and six of the ten additions. The two
protocol refinements account for the other removals; the two Irmin candidates
account for the remaining additions. No new MUST row was observed.

MAY_TOP falls6776→6774 solely from the two protocol refinements. Frozen inputs
and reference rows remain unchanged. Native physical-identity and metadata
fixtures provide complementary evidence; this structural accounting cannot
establish complete higher-order, capture, argument/return or functor semantics.
