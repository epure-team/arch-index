# Reviewer round 1 / cycle 1

Historical pre-repair review of975c73b only. The later independent spec finding
disproved the legacy flat-call preservation claim below. Its bounded correction
is independently confirmed in spec-repair-confirmation.md; owner re-review on the
repaired commit is still required. This artifact is not the current final verdict.

Recommendation: **approve**. No reproducible correctness, security, or regression finding identified. Findings JSON is `[]`. This specialist recommendation does not authorize retention, merge, or attempt 3; remaining roster specialists, QA, and exact-head delivery gates remain separate.

Reviewer: `/root/residual_owner_review`, 2026-09-14. Reviewed HEAD `975c73b49def2813517b00c296006417d062d8b2` against `fb9c8f3f685d751ee07a81c17fb1ca61860a7365`, with the complete branch diff against `origin/main` also inspected. Scope admission is the coordinating agent's actual scope gate, not an inference from filenames here. No product, test, witness, baseline, or source edits were made by this reviewer. Only this report and its findings file were written after all source-state-sensitive checks completed and the coordinator granted the documentation slot.

## Review evidence

Read the reviewer agent contract, reviewer and implementation briefs, complete feature specification, spec inputs/resolutions and UID-layering rule. Inspected the complete changed product modules/interfaces, complete changed executable checks/native probe, test registration and fixture files, and the feature's supporting documents. Reviewed self-oracle collateral and the changed friction entries; historical friction-log output exceeded the tool display budget and is not claimed fully read. `.claude/patterns/` is absent, so there was no language-pattern policy to apply.

- Ownership and one-hop eligibility: `arch_index_cmt.ml:1012` builds a per-CMT Ident-keyed owner table. `:1049` masks every bound name before installing an eligible export; `:1063` admits only a bare arrow-typed Pident whose identity already occurs in the body table. Includes preserve owned provenance. Module aliases, functor applications, unpacks, computed RHSs and chains do not enter through this arm. The unchanged body-only builder at `:973` supplies existing ordinal-qualified names and syntactic arity.
- Consumer separation: `arch_index_cmt.ml:1109` retains direct-only lookup, while `:1129` adds invocation lookup. Callback emission at `:1596`, letop dispatch at `:2174`, and application classification at `:2278` use invocation lookup. Point-free emission at `:2830` continues through the existing direct-only path and immediate alias predecessor table. Config-head classification at `:1667` and CFG/scope/channel lowering remain unchanged.
- Partial/return behavior: `arch_index_cmt.ml:2203` counts supplied `Some` expressions only for owned targets; `:2233` obtains the actual body's arity; `:2242` combines supplied count and result-arrow status. The existing return-residual path at `:2322` remains one callback-param TOP at the application site. Native controls actually check both ownership contexts, required/optional holes and hidden-arrow cases, including body-table exclusion of aliases.
- Flat output: `call_graph_extractor.ml:281` keeps separate direct-only and invocation ownership sets; `:349` selects the appropriate set by edge form. An owned target receives a file only when the exact same-file symbol exists. The forced fallback checker observes both a same-file positive and an absent-local/foreign-homonym negative, and explicitly preserves the legacy point-free attribution behavior. This is not a claim to repair that pre-existing point-free limitation.
- Witness admission: `alias-witness.ml` independently uses compiler-libs and Ident/UID declaration evidence without importing product lookup. `check-witness.js:183` admits the signature/implementation split only through its narrow declaration-table rule and one plain Resolved endpoint; concrete-binding conflicts, absent/foreign/wrong-name/non-arrow declarations and Resolved_alias endpoints are exercised refusals. `witness.js:24` verifies ordinary same-site paired heads and native body/caller positions. `:72` replays the native probe before admitting evidence; distinct native locators and the comparator's counted consumption prevent duplicate reuse. Actual malformed/native-positive controls passed.
- Provenance/comparison: `baseline.js` pins producer/schema/corpus/canonical identities and uses read-only snapshots; `prepare-baseline.js:80` replays the frozen producer, not the changed product. `verify.js:50` produces a fresh candidate, rechecks inputs/provenance/source state, and always reports `retention_authorized:false`. `comparison.js` additionally refuses every changed non-null edge-form row. The imported comparator was read in full and its multiset, residual-capacity, relation-loss and new-MUST guards inspected.
- Security/test impact: no new external execution surface, dependency, network API, schema, configuration policy or cross-CMT resolver was introduced. Native tools operate on explicit local inputs and owned temporary artifacts. The deterministic refusal and rejection tests are nonvacuous: positive target rows/consumers are observed, and injected storage rejection preserves `dropped_node`. No security finding is asserted without evidence.

## Actual commands and exits

Every command below was personally executed sequentially with the `rtk proxy` prefix and the specified local opam switch where applicable. No failed gate was retried or omitted.

| Gate | Command after `rtk proxy` | Exit | Observed result |
| --- | --- | ---: | --- |
| Build | `opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Build completed. |
| Full guard | `opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | 332/332 Tezt successes, 16:34:03–16:37:50; unit suites also succeeded. |
| Bundle | `node scripts/review-bundle-verify.js` | 0 | 22 files sha-matched, bundle 1.6.0. |
| Whitespace | `git diff --check` | 0 | No diagnostic. |
| CHECK1 | `node roster/tezos-residual-targets/check-native.js` | 0 | Both native contexts, body-only/partial/residual assertions; all five Tezt cases succeeded. |
| CHECK2 | `node roster/tezos-residual-targets/check-comparison.js` | 0 | 38 assertions; three native consumers/12 refusals and paired admission positive/10 refusals. |
| CHECK3 | `node roster/tezos-residual-targets/prepare-baseline.js --check` | 0 | Frozen replay: 45,052 rows, Irmin 4,772/protocol 11,615. |
| CHECK4 | `node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json` | 0 | 124 paired gains, +9 Irmin/+115 protocol; zero losses/errors, unchanged row count 45,052. |
| CHECK5 | `node roster/tezos-call-resolution/check-self-index-smoke.js` | 0 | Exact 25 modules/989 functions/6,276 calls. |

CHECK4 durable output: `improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T16-40-54-725Z-638640/`. Baseline digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`; candidate digest `00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b`. Its classification is candidate, not retained.

The full-guard raw stream is in this reviewer's execution transcript (exec session 14389), with tool-display truncation disclosed; no new raw log file was created. An additional non-gate attempt to read `_build/log` exited 1 with ENOENT. No test result was inferred from that absent file. Missing language-pattern directory inspection exited 2. The suite's controlled assertion/setup-error diagnostics and pre-existing Tezt temporary-directory warnings did not make the suite fail. No foreign temporary directories were cleaned.

## Requirement and acceptance coverage

| Requirements | Acceptance criteria | Evidence assessed |
| --- | --- | --- |
| FR-001, FR-005 | AC-1 | Exact same-file ordinary enumerated invocation/callback/letop targets, CHECK1. |
| FR-002, FR-003 | AC-2 | Structural owner/form/Ident checks, native positive and disagreement refusals, CHECK1/2/4. |
| FR-004 | AC-3 | Original ordinal body after shadowing and later export masking, CHECK1. |
| FR-006 | AC-4 | Native supplied-count, actual-arity, partial and return residual controls, CHECK1. |
| FR-007 | AC-5 | Consumer/config/CFG source audit, conditional/dead fixtures, unchanged point-free oracles and full guard. |
| FR-008, FR-005 | AC-6 | Forced flat same-file/foreign-homonym controls and actual injected storage rejection, CHECK1. |
| FR-009, FR-010 | AC-7 | Frozen pins and actual neutral replay, CHECK3; historical pre-edit freeze record reviewed. |
| FR-011, FR-012 | AC-8 | Native-replayed positioned pair admission, UID-layering checks and counted duplicate controls, CHECK2/4. |
| FR-013, FR-014 | AC-10 | Point-free movement, duplicate deletion, new MUST and residual-capacity refusals; actual zero-loss comparison. |
| FR-015 | AC-9 | Assertion/setup classification in runners and exercised malformed-input/refusal controls, CHECK2. |
| FR-016 | AC-11 | Body-only native table and unchanged unqualified alias-call refusal, CHECK1. |
| FR-017 | AC-12, AC-13 | No automatic keep authorization; exact self golden CHECK5; downstream gates explicitly outstanding. |

The coordinator's independently executed committed-tree pristine calibration report was read: both self-golden and unchanged ceiling controls are SOURCE_ONLY and passed. This reviewer did not execute that separate calibration and does not count it among personally run gates. Semantic-witness review alone is not product approval. No formatter, coverage collector or managed claims projection is configured here, and none is marked PASS. Open questions: none for this specialist; required downstream approvals remain as above.
