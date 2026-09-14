# Attempt 2 independent semantic-evidence review

Verdict: **GO for the 124 paired semantic witnesses only.**

Reviewer: `/root/residual_evidence_review`, independently assigned by the coordinating agent, 2026-09-14. I did not author the product change, native probe, admission helpers, or draft. This review does not authorize retention, merge, or attempt 3; full product roster review, QA, guards, and delivery remain separate gates. No draft review annotations were changed.

## Exact reviewed artifacts

All paths below are relative to `/home/mathias/dev/arch-index`.

| Artifact | SHA-256 |
|---|---|
| `improvement/2026-09-14-tezos-resolution/attempt2-draft-witness.json` | `50106b9e22cb67270fc275740c5aa60519ce6821b77819c38ed8a9ae05c05f8f` |
| `improvement/2026-09-14-tezos-resolution/attempt2-alias-native-v2.json` | `f307dfdd2ea00e0d0706e788ee042058c4619071899fd36be5127c9fe128b6c4` |
| `roster/tezos-residual-targets/alias-witness.ml` | `13d941b75bea72d4a2eea3395e5c6a075249e1d2a5fbcfda217a9f5b6f2998d7` |
| Baseline canonical snapshot | `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b` |
| Candidate canonical snapshot | `00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b` |

The reviewed delta and positioned rows are in `improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T08-35-50-576Z-3164680/changes.json`. Its original report correctly says REFUSE because it was produced without reviewed witnesses. This scoped GO does not rewrite that report.

## Findings

No blocking semantic-evidence finding for these exact artifacts.

All 124 before/after rows were individually checked, including source file, stored caller name and line span, call site, native occurrence location, alias identity, body identity, and actual target span/name. Every native locator is used once. The draft before and after canonical multisets equal the entire removed and added multisets, respectively; there is no set-based reuse that hides duplicate consumption.

Every admitted occurrence has exactly one plain `Resolved` shape result. Each endpoint selects exactly one same-CMT alias binding. Its RHS is one nonpersistent local `Pident`, arrow typed, with a unique actual syntactic function body. The RHS Ident, value UID, shape UID, target binding and actual-body UID agree. The alias remains a non-function binding. The stored target's native span identifies exactly one body, and its leaf name agrees with that body's actual name after the stored ordinal suffix is removed; names were not used to recover a missing or conflicting identity.

Of the 124 invocations, 114 are letop operators and 10 are applications; none is a callback in this candidate. There are 113 signature/implementation UID differences. In every such case, the occurrence value UID names one arrow-typed `Typedtree.Value` declaration of the matching operator name, names no concrete binding, and the single plain `Resolved` endpoint names the concrete alias. The other 11 occurrences have matching value and endpoint UIDs. This distinction is supported by the CMT declaration table and native source, not an inference that differently numbered UIDs must agree.

The live constrained Monad source confirms the signature/implementation split: wasm signature line 200, alias line 219, body lines 213–216; arith signature line 217, alias line 240, body lines 234–237. The independent compiler probe obtains binding identity with `Ident.same` and declaration classes from `cmt_uid_to_decl`. It does not import the product's resolver or body table.

| Native source / actual stored target | Pairs | Alias line | Body lines |
|---|---:|---:|---|
| `sc_rollup_wasm.ml` / `V2_0_0.Make_pvm.State.Monad.bind` | 11 | 219 | 213–216 |
| `sc_rollup_arith.ml` / `Make.State.Monad.bind` | 103 | 240 | 234–237 |
| `cache_repr.ml` / `Cache_costs.cache_update` | 1 | 44 | 38–40 |
| `irmin/lib_irmin/store.ml` / `Make.head` | 2 | 638 | 564–576 |
| `irmin/lib_irmin/merge.ml` / `bind` | 7 | 70 | 52 |

All changes are ordinary null-edge-form `MAY_TOP/module_param` heads without a target becoming same-file `MAY_ENUMERATED` heads with null TOP fields. Caller, site and caller positions stay fixed. There are no residual additions, new MUST rows, reexport movements, unconsumed changed rows or relation losses. Distinct incremental gains are 9 Irmin and 115 protocol, with 0 other gains. Both canonical snapshots contain 45,052 rows.

## Checks actually run

Shell commands were prefixed with `rtk` per `/home/mathias/.codex/RTK.md`. All checks below exited 0. No Dune invocation, product producer, full guard, worktree operation, or product write was performed.

1. `rtk proxy node roster/tezos-residual-targets/draft-witness.js --check` reported: `DRAFT ONLY: paired 124 transitions; independent review fields intentionally null`. This checks exact reproducible draft bytes, not independent approval.
2. `rtk proxy node <<'NODE'` (native replay check; execution session 7966) loaded the exact draft and raw evidence, printed the three artifact hashes above, called `require('./roster/tezos-residual-targets/run-probe.js').probeRecords(records.map(r => r.cmt))`, and required `JSON.stringify(replayed) === JSON.stringify(records)`. It compiled compiler-libs-only probe code in its own temporary directory and reproduced all five CMT records exactly. It did not invoke the root producer.
3. `rtk proxy node <<'NODE'` (independent per-pair/multiset audit; execution session 13497) used `node:assert/strict` to check every predicate described in Findings directly against the raw JSON. This loop did **not** use `validateNativePair` or `validateOneHop` to decide the endpoint. It independently selected occurrence, shape result, alias and body, checked the layered declarations, native containment, target span uniqueness and names, and unique locator consumption. It compared before/after multisets and exact positioned snapshot membership. It then opened `attempt2-baseline/baseline.db` read-only, checked its canonical digest, removed the 124 old instances with counted consumption, added the 124 new instances, and required the reconstructed full candidate digest above. `compareSnapshots` with these exact pairs returned no errors and the 124/9/115/0 counts reported above.
4. `rtk proxy node <<'NODE'` (layering refusal check) first accepted the real first wasm pair through `validateOneHop`, then independently cloned its raw record for eight in-memory corruptions: `Resolved_alias`, duplicate shape result, competing concrete binding, `Value_binding` instead of signature `Value`, wrong declaration UID, wrong signature name, non-arrow signature, and missing declaration. Every corruption threw as required. No mutated evidence was written.
5. `rtk proxy node <<'NODE'` (input-pin check) read the exact 410-input TSV, SHA-256 hashed all five live CMT files, and asserted equality with their manifest entries. It also printed each used alias/body UID and source span for inspection. All five matched:

   - wasm: `69114fdb3007ffdd9a34cf44fa041f841e128602992ca13ab1c59788b853c374`
   - arith: `8768869c1c3ad125959200fe0082c259e6a50aa2db53e978f6dd4830c9435849`
   - cache: `0522c856e0b7338d7c5c4a1a5576ae99cbd475158da6a7663213a1cab97c651d`
   - store: `a285e1aa09a0161847dad278f667538e8a3d2790949293cff0ef75c6668a58f3`
   - merge: `90d43bf60122f75b06b8ac17575e666744060de0ae7cbd61c8715e466536d7f0`

The stdin programs above were executed as transient review commands; they were not installed as additional repository scripts. Their exact tool-call bodies are in the review-agent execution transcript. Read-only source inspections additionally used `rtk proxy sed -n` for wasm 188–223, arith 205–245, cache 30–48, store 560–578 and 632–642, and merge 48–73 under `/home/mathias/dev/tezos/tezos`.

## Scope and assumptions

Read in full: `specs/tezos-residual-targets.md`, `spec-resolutions.md`, `uid-layering.md`, `alias-witness.ml`, `check-witness.js`, `witness.js`, `draft-witness.js`, `run-probe.js`, and the comparison implementation used here. The coordinating agent strengthened target-name checking and repaired temporary-directory compiler selection during this review; draft and raw evidence hashes stayed fixed.

The comparison audit reconstructs the full candidate from the frozen read-only baseline and the saved exact delta, and checks the candidate digest. It does not reproduce candidate production or certify the current executable. The native CMT replay independently authenticates all five evidence inputs; complete 410-input source provenance, producer reproducibility, pending partial/return metadata, callback behavior, CFG/channel/configuration semantics, flat-output behavior, generic negative cases, and full integration remain the responsibility of the separate required gates. The absence of such occurrence classes in these 124 rows cannot prove those product behaviors.

The coordinating agent may now record this review identity and artifact as the independent source review for these exact 124 transitions, then run the normal reviewed-witness verifier. A changed draft/raw/probe or changed canonical endpoints requires renewed assessment; this review does not authorize guessing replacement endpoints.
