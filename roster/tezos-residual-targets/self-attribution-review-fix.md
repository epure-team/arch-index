# Self-attribution review after occurrence-provenance fix

Date: 2026-09-14. This is a bounded read-only C/D diagnostic over the already
built current `lib/arch_index` CMT corpus. It did not build the repository,
refresh a reference, or modify product sources. Historical A/B measurements in
`self-attribution.md` remain historical; they are not presented here as fresh
evidence. The later pristine calibration remains responsible for complete A/B
validation.

## Inputs and integrity

- frozen producer: `c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8`
- current producer: `416e52cd88a0770a0a40f01f4f7cab20305f9591051442832abcbde5ace3158e`
- frozen and current explicit schemas (equal): `1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0`
- ordered current source inventory digest: `f6614fca7e4db643a42b2e4198b8cf8fed459bdfc8008a6ce6efbb88c1c87fef`
- ordered current CMT/CMti inventory digest: `da78de8c7612e034da375ea05eacfd618d9b59ecb40c0a5ec1c2a61f4cdb5e36`

Source, CMT/CMti, producer, and schema byte manifests compared equal before and
after both measurements. Each producer wrote a separate initially absent
temporary database and received its schema through explicit `--schema-path`.

Reference-refresh source manifest for the three product sources in this fix:

```text
4114fe8124a3c7b602e31a97a23175783d7de6fb83df7bc6fa7f3addcbaf9993  lib/arch_index/arch_index_cmt.ml
6834d0c154e0e354298df3ce7af8e73a1eb5a88559969891d9b773ce8fcbc424  lib/arch_index/arch_index_cmt.mli
85d93403f0177f3fe66a85bc3847164280cefc8e4c237acae5f9e0d2143281cd  lib/arch_index/call_graph_extractor.ml
```

The full source inventory, rather than only this three-file projection, is
identified by the ordered inventory digest above.

## Actual C/D results

| Cell | Producer | Current corpus | Modules | Functions | Calls | Origins |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| C | frozen predecessor | current `lib/arch_index` CMTs | 25 | 989 | 6275 | 564 |
| D | current fix | current `lib/arch_index` CMTs | 25 | 989 | 6275 | 564 |

The exact ordered origin groups are also equal:

| Channel | Form | Escapes | Count C | Count D |
| --- | --- | ---: | ---: | ---: |
| exception | assert | 1 | 1 | 1 |
| exception | compare | 1 | 49 | 49 |
| exception | failwith | 1 | 28 | 28 |
| exception | index | 1 | 106 | 106 |
| exception | invalid_arg | 1 | 1 | 1 |
| exception | raise | 1 | 1 | 1 |
| exception | reraise | 1 | 8 | 8 |
| option | raise | 1 | 315 | 315 |
| result | raise | 1 | 4 | 4 |
| result | unknown | 1 | 51 | 51 |

Measurement JSON hashes are identical:
`d6c84819bac05291dcc6a75fc50164f959bbe28502211d5afbeea318bf93918e`.
The independently produced DB byte hashes differ, which is not used as an
equivalence claim; equality is established by the exact totals and complete
ordered origin-group query results.

## Verdict

`C = D` for every requested total and origin group on this current corpus. The
occurrence-provenance producer fix has no observed self-attribution effect on
these consumer coordinates. This C/D result supports a reference refresh only
as one marginal; it does not make the earlier A/B fresh and does not replace
the required pristine four-cell calibration.

The observed current corpus has 6,275 calls, one fewer than the earlier
incremental diagnostic's 6,276. This report does not attribute that corpus
movement because it intentionally reran only C/D. Any refresh must use the
manifest pinned above and must not infer source-only movement from this report
alone.

No reference change is self-approved by this diagnostic reviewer.
