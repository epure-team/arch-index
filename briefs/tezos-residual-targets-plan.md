# Plan — tezos-residual-targets

**Date:** 2026-09-14
**Status: VALIDATED**

## Sequential steps

1. **Freeze and exercise predecessor verification** — new task-prefix scripts
   prepare-baseline.js, comparison helpers and negative checker; import task1
   comparison routines read-only. Store a hash-checked producer/schema copy and
   fresh45052-row DB under ignored attempt2-baseline/, verify all410 input/run
   provenance and exact canonical/slice metrics; frozen-producer replay neutral.
   Refuse overwrite, never replace old baseline. Completion: CHECK2/3 and --self
   pass, positive/negative controls exercise actual validators. Setup is not gain.
2. **Native RED, then one end-to-end product change** — new self-contained
   check-native.js and local_value_targets.ml fixtures/probe; register only at
   controlled integration point. Prove actual compiler/collector assertion RED.
   Implement one-hop value provenance in owned context and qualified invocation/
   callback/letop consumption; body table and point-free lookup remain unchanged.
   Update exactly the existing value_alias_call expectation and relevant docs.
   Completion: actual native GREEN, old body/point-free/refusal tests still pass,
   same-file flat attribution and storage rejection tested. No layered commits
   leaving provenance installed but consumers unverified.
3. **Exact candidate witnesses and comparison** — fresh fixed410 current binary
   against frozen predecessor, independent compiler call->alias->body evidence
   with full positions/arity/multiplicity; new witness version, old direct-UID
   evidence refused. Only ordinary module_param-to-same-file-body heads and
   separately witnessed overapplication residuals allowed. Completion: positive
   incremental relation gain, no losses/unexplained rows/point-free movement.
4. **Full delivery gates** — full build/tests, all5 checks and baseline replay,
   exact self oracle (recalibrate named files only if actually necessary),
   pristine CI recalibration. Commit owned round, independent roster review then
   QA, exact-head green hosted CI, rebase merge before attempt3. Update results/
   roadmap only after actual merge. Clean only owned temporary selections/builds.

## Dependencies

1 before product edits;2 needs genuine RED before GREEN;3 needs built candidate;
4 needs positive permitted delta and all earlier gates. No speculative stacking.
Mixed-scope skill order adapted only for required comparison setup: JS prerequisite
first because intake explicitly forbids product changes before verified baseline;
then OCaml capability, then remaining witness/report scripts.

## Consensus Table

| Point | Sol voice1 | Terra voice2 | Status |
|---|---|---|---|
| Distinct immutable predecessor before product | required | required | AGREE |
| One-hop identity; body-only table | required | required | AGREE |
| Invocation gain vs exact point-free preservation | separate gates | separate gates | AGREE |
| Independent new alias witness class | required | required | AGREE |
| Flat modifications only if needed | conditional | conditional | AGREE |
| Precise self recalibration and full sequential delivery | required | required | AGREE |

Voices ran sequentially with fresh contexts, intake only. No USER-CHALLENGE or
unresolved design disagreement. Root groups their provenance+consumer proposals
into one tested vertical slice, not separately shipped horizontal layers.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Current producer contaminates predecessor | medium | invalid gain | frozen hash-checked executable/schema, distinct immutable record |
| Shared helper rewrites point-free links | high | changed meaning | distinguish alias-derived invocation lookup from direct-only reexport lookup |
| Arity0 or label-hole regression | medium | false certainty/residual | body-only table and native exact pending metadata |
| UID witness confused with alias-chain proof | medium | false target | explicit one-hop class, exact call/alias/body native identities |
| Mask/homonym capture | medium | wrong target | typed identity/ordinals, cross-file/refusal fixtures |
| Comparator drops duplicates or offsets losses | medium | false gain | canonical multiset consumption and positive/negative controls |

## Decisions made

Frozen artifacts rather than another persistent worktree allow replay after the
candidate changes without disk-heavy dual builds. --check uses frozen executable;
verify uses current executable. Raw DB bytes are not identity. Native fixtures
cover all required consumer forms; corpus witnesses cover only actual changed
occurrences, no requirement that every form occurs in Tezos. Complete canonical
point-free multiset and native immediate-predecessor canary remain unchanged.

## Assumptions

No new product assumptions: compiler identity and existing body arity are the
bounded prerequisites; absent identity refuses. Tools/claims/KB absent are not
passing gates. No new schema, public CLI, Tezos edits or third-party installs.
Routine human quizzes use explicit standing autonomy; no answers invented.

