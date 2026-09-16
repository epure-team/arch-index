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

## Review-round1 opaque-alias correction (2026-09-16)

Fresh report `improvement/2026-09-15-ocaml-cfa/check3-1789556661043-27428.json`
passes after the two-line unknown-source seeding correction. Producer hash:
`2f2d3f72c7ad8572ed8ea596b6c82d49e833fb664e7eedcc4f230a05073f844b`.
Rows remain45054; canonical digest is now
`08f491da61809c59401529be1373c5be3c61dc4c5de6c5269ee7b885e5467a18`.
Relation gains remain Irmin+1/protocol+2, losses0. Exact baseline-relative row
changes are now11 removed/13 added. Compared with the prior report, the only
additional changes are three diagnostic-name replacements with `*TOP*`:

- `sc_rollup_tick_repr.ml:62`, caller `<>`, formerly `=`;
- `staking_pseudotoken_repr.ml:34`, caller `of_z_exn`, formerly `of_int64_exn`;
- `staking_pseudotoken_repr.ml:36`, caller `to_z`, formerly `to_int64`.

All other canonical fields of these three rows match; none is a resolution
gain or removed uncertainty. Inputs and frozen baseline remained stable.
This replay measured48448.710771ms wall and sampled RSS145040KiB, much slower
than earlier runs. No causal performance conclusion is drawn from this single
observation; retain it and repeat qualification rather than substitute an old
timing for the corrected producer.
# Post-correction repeat

Root repeated CHECK3 after the final345/345 full suite. Report
`improvement/2026-09-15-ocaml-cfa/check3-1789557473557-290403.json`
is measured/ok, with identical producer `2f2d3f72…`, canonical output
`08f491da…`,45054 rows and +1 Irmin/+2 protocol relations, no losses or new MUST.
Wall time2760.487028ms and sampled RSS145068KiB. The earlier48448.710771ms
observation remains valid evidence of that run; this repeat does not establish
its cause or a statistical performance bound. Both pinned inputs and baseline
are unchanged. No stage3 or functor-resolution claim follows from these gains.
