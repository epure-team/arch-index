# Plan — guard-division-analysis

**Date:** 2026-09-13
**Status: VALIDATED**

## Bounded scope amendment — 2026-09-13 resume

The user's continuation after the explicit recalibration request permits one exception
to the no-pin-edit rule below: tezt/tests/must_null_ceiling.ml clean_measured383→430,
with its attribution comment, after individually attributing34 new-source calls.
Keep headroom25, query, adequacy floor, extractor, self golden and origin references
unchanged. See roster/guard-division-analysis/ratchet-source-growth.md. The manifest
adds only that file. Independent review/QA and fresh full-build gates still apply.

Decomposition source: validated intake only. Spec status gate passes (406242c); the implementation must read the frozen spec, not re-answer its questions. Independent voices ran sequentially, fresh Sol then Terra, with intake only. No codebase inspection by planning voices.

## Consensus Table

| Point | Voice 1 | Voice 2 | Resolution |
|---|---|---|---|
| Separate trusted CMT inventory and CLI | yes | yes | AGREE |
| Domain representation | constant/nonzero/top/bottom | interval plus zero exclusion | DISAGREE resolved by root under standing autonomy: constant/nonzero/top/bottom; no ordering precision required in intake. |
| Modular overflow | exact modular constants, conservative otherwise | no-wrap precision, top otherwise | Both satisfy intake; choose exact representable constants and top on overflow for simpler auditing. |
| Unknown ordinary calls | top, preserve immutable facts | step4 says unsupported calls | Correct voice2 against explicit intake: ordinary calls return top; only excluded structural ancestry is unsupported. |
| Unsupported fencing sequence | late separate step | with interpreter | Initialize all unsupported exclusions before enabling any numeric status; never temporary optimistic default. |
| Test integration | described at final step | described at final step | Wire first authentic CLI test at first executable slice; final step completes coverage rather than introducing testing. |
| Scope/direction | keep | keep | AGREE; no USER-CHALLENGE. |

## Sequential steps

1. **Attributable inventory through the CLI.** TDD a compiled owned fixture through explicit CMT intake, complete primitive inventory, closed report and errors. Add library/CLI/wrapper, initial checker and Tezt registration together. Preserve unsupported inventory first, then enable later numeric capabilities. Finish native identity/slot/dedup/empty report and malformed-input tests before next slice.
2. **Constant and immutable-value classification through the CLI.** TDD native literals/aliases/parameters and arithmetic vectors. Add the domain and a test-only batch probe for an independent JS BigInt oracle. Constants/aliases yield required statuses; unknown calls remain top. All excluded regions already default unsupported. Full suite after this vertical increment.
3. **Guards and entry boundaries through the CLI.** TDD zero restrictions, branch joins, false/contradictory branches, shadowing, simultaneous binding groups and fresh nested functions. Add interpreter support while keeping sticky unsupported ancestry. Negative fixtures cover every excluded family and opaque-call arguments. Full suite after this increment.
4. **Auditable bounded report delivery.** Complete all exact/one-over limits, metadata anomaly, failure atomicity, format equivalence and checker assertion/error controls. Finish docs and actual owned-library census. Run all existing self gates unchanged, then independent roster review/QA, exact-head green PR and rebase merge. Clean only owned scratch/build/worktree after evidence is retained.

## Dependencies

1 precedes 2: raw census must remain independent of numeric interpretation. 2 precedes 3: restriction/join require an audited domain. 4 completes all integration and regression evidence, but tests and exclusions start in step1. These are internal TDD increments in one bounded PR, not separately shippable incomplete contracts.

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Domain | `Bottom | Const of int64 | Nonzero | Top`, explicit width parameter, public domain name `constant-zero-v1` | Smallest adequate nonrelational abstraction; constants represented safely at 31/63 signed widths. |
| Concretization | Bottom=empty; Const=singleton within signed width; Nonzero=all signed values except0; Top=all signed values | Makes precision and tests explicit. |
| Join | Bottom identity; same constant preserved; distinct nonzero facts -> Nonzero; zero plus nonzero -> Top; Top absorbing | Covers required0/2 and nonzero branches. |
| Restriction | equality0: intersect with{0}; inequality0: remove0; contradiction ->Bottom | Zero exclusion without intervals. |
| Arithmetic | Exact singleton result only when representable, checked before unsafe host operations; otherwise Top; div/mod result Top | Avoid host wrap or min_int/-1 assumptions; independent modular oracle verifies containment. Non-singleton arithmetic may return Top except Bottom propagation in domain API. |
| Entry state | Reachable flag separate from abstract value; fresh supported function resets reachable/env, preserves unsupported ancestry | Prevents accidental false unreachable from ignored expressions or captures. |
| Layout | Separate domain, CMT/inventory, interpreter and report modules under lib/arch_guard; public CLI under bin/arch_guard | Existing extraction libraries untouched, no new dependency required. |
| Tests | Standalone JS checker with six independent modes; native compiled fixtures and test-only OCaml batch probe; Tezt executes checks | Independent oracle without one process per numeric vector; no new public probe API. |
| Checker batching | Bound batches to captured-output/process limits; full small-width concrete pairs and non-singleton samples | Exhaustive small-width containment fits bounded processes; 31/63 extrema are supplementary samples. |

## Files

Create lib/arch_guard/ (domain, input/inventory, interpreter, report and interfaces/dune), bin/arch_guard/ (CLI/dune), arch-guard, tezt/fixtures/arch_guard/ (owned fixtures plus test-only probe/dune), tezt/tests/guard_division_analysis.ml, scripts/check-arch-guard.js, docs/arch-guard.md.
Modify only test integration tezt/lib/dune, tezt/tests/dune, tezt/tests/main.ml and README.md/CHANGELOG.md. Pipeline artifacts briefs/, roster/guard-division-analysis/, specs/guard-division-analysis.md and skills-meta/friction.jsonl are allowed. No existing lib/arch_index or lib/arch_tools changes, no CI/reference/allow-list changes intended.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| False nonzero from overflow | medium | high | Prechecked constants, Top fallback, independent BigInt oracle for complete represented input sets. |
| Unsupported/default/capture leakage | high | high | Inventory independent; unsupported-first; fresh function entry; nested negative fixtures. |
| Incomplete syntax traversal | medium | high | Full compiler traversal plus inventory-to-result reconciliation; defaults/unsupported still counted. |
| Compiler patch/magic assumptions | medium | high | Linked reader checks; exposed diagnostic granularity; trusted-build assumptions, no invented producer version. |
| Large fixture/control tests exceed process cap | medium | medium | Batch independent probe requests, avoid huge single stdout; deterministic bounded setup; record setup failures >=2. |
| Vacuous owned corpus | high | medium | Report measured0 honestly; fixture precision not Tezos impact. |
| Existing baseline perturbation | low | high | Separate component and unchanged self gates; no golden/reference rewrite. |

## Assumptions and validation

All voice1 product questions concern fields already frozen by the completed spec; no re-opened product ambiguity. Root selects domain under explicit autonomous engineering authority; neither voice asks to change direction. Source bound intake sha256 ef51fd545c3112823dda4aa42e09c92c5b33d08fad2f0fd24a8d07d9bbd274b8; neutral question manifest digest rechecked8056e06cda5882b53effb1218c03e2c6922a8e6f25a6356b58528048c721b5a0.
No installed claims reconciler/KB/hooks; no simulated checks. No new global installation. Human plan quiz/repeated validation replaced by standing autonomy, not represented as answers obtained. Exact technical gates remain mandatory.
