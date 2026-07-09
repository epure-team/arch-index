# Implementation Brief — cfg-postdom-dominance

**Date:** 2026-07-09
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_index/arch_index_cfg.ml(i)` | addition | Pure CFG engine: block arena, diverging terminators, virtual exit, hasExit guard, iterative post-dominance, entry-reachability (port of Go alwaysExec) |
| `lib/arch_index/arch_index_cmt.ml` | modification | Walker lowered onto per-node CFGs; `kind_hint` → `{head; partial; cond}`; noreturn terminators + try dispatch; lambda-node promotion with per-occurrence edges; local-lambda stamp table |
| `lib/arch_index/arch_index_cmt.mli` | modification | `call_head`/`pending_call`/`lambda_node`/`pending_display` API |
| `lib/arch_index/arch_index.ml` | modification | Resolution loop: (head × cond × partial) → kinds; enumerated demotion; qualified resolution for demoted calls; `Arch_index_cfg` re-export; lambda-row insertion in `process_cmt` |
| `lib/arch_index/arch_index.mli` | modification | `Arch_index_cfg` re-export |
| `lib/arch_index/call_graph_extractor.ml` | modification | LSP fallback adapted (`pending_display`, lambda names flow through kind-less rows) |
| `callgraph-go/main.go` | modification | Enumerated demotion in both gates; cgo `_Cfunc_*`/`_cgo*` wrapper detection (⊤ anchors) |
| `test/test_cfg.ml`, `test/dune` | addition | 7 CFG unit tests |
| `selftest-callgraph-soundness.sh` | modification | 52 P1 + 19 (flipped) P2 assertions; R1/R2/US-4 fixtures + negatives |
| `selftest-callgraph-go.sh` | modification | DOM_ENUM enumerated-demotion assertions (default on); cgo-wrapper ⊤ fixture (CC-guarded) |
| `scripts/callgraph-diff.sh` | addition | Exhaustive no-drop/kind-monotonicity gate (R2-aware normalization) |
| `test/fixtures/self-index-stats.txt` | modification | Golden: 19 modules / 367 functions / 3111 calls |
| `docs/edge-kind-contract.md` | modification | CFG model, lambda nodes, enumerated demotion, narrowed residuals |

## Decisions made

- **Per-node lowering contexts** (`lctx` record): each function AND each promoted lambda gets its own CFG/current-block/handler-stack; deferred non-promoted bodies (lazy/object/functor) walk in isolated entry-unreachable blocks — demotion falls out of reachability, no counter.
- **Match partiality** (codex step-2 finding): `Partial` matches get a Match_failure bypass edge; a single TOTAL unguarded arm is legitimately MUST (sound precision gain over the old walker, zero occurrences in the self-index population).
- **Head-after-args recording** (codex step-3 finding): a call's head is recorded in the block reached after descending fn+args, so `h (raise A)` never forges a MUST to `h`.
- **Persistent-root noreturn** (codex step-3 finding): a local module named `Stdlib` cannot terminate blocks.
- **cgo wrappers as ⊤** (codex step-4 finding): `_Cfunc_*`/`_cgo*` prefixes reclassify to MAY_TOP after enumerated demotion.
- **Any non-head occurrence = escape edge** (step-7 audit finding): a stored lambda (record/tuple/ref/return) emits a MAY_ENUMERATED occurrence edge via a generic `Texp_ident` case; apply heads are loc-marked against double emission. Fixed a dead-code false positive (`recv_lsp`).
- **Flat stamp table is scope-correct**: `Ident.unique_name` is unique per binder, so shadowing/rebinding need no eviction (verified by negative fixtures + adversarial round).
- **Cross-runtime substitution**: codex hit its workspace spend cap after the step-4 round; steps 5–6 adversarial rounds ran as isolated Claude sub-agents (maintainer-approved). Codex re-verification when the cap resets is a follow-up.

## Quality Gates

- [x] Build: `dune build` ✅ (clean rebuild)
- [x] Tests: `dune test` ✅ (incl. 7 new CFG unit tests)
- [x] Shell: contract/load/effects/callgraph-ocaml/callgraph-go ✅; `STRICT=1 selftest-callgraph-soundness` ✅ (52 P1, 0 fail; all 19 P2 targets flipped)
- [x] Population diff vs main: zero dropped edges; movements only MAY_TOP→{MAY_ENUMERATED,MUST(9 λ-related)} and MUST→MAY_ENUMERATED(123 divergence) ✅
- [x] Golden: 19/367/3111, deterministic (two runs identical) ✅; kinds valid; contract v1 stamped
- [x] Go: `go build && go vet` ✅
- [x] Format: not documented (matched surrounding style)

## Self-index kind distribution (CHECK-6)

| kind | count | share | pre-branch |
|---|---|---|---|
| MUST | 1001 | 32.2% | 21% |
| MAY_ENUMERATED | 1989 | 63.9% | ~0% |
| MAY_TOP | 121 | **3.9%** | **79%** |

## arch-query subcommand audit (CHECK-7 / FR-023)

| Subcommand | Verdict vs synthetic rows |
|---|---|
| reaches / unreachable / escapes | ✅ correct (id-based; lambda edges resolve; verified on corpus + self) |
| dead-code | ✅ correct after step-7a fix (closure includes MAY edges; orphan lambdas = genuinely dead; zero false positives on self) |
| callers-of | ✅ (calls-table only) |
| exported | ✅ (exposed=0 filters lambdas) |
| unresolved | ✅ |
| find / stats / fan-in / callees-of / reachable-from | ⚠️ PRE-EXISTING main-schema breakage (reference flat-only columns `file_path`/`exported`/`caller_name`; parse errors identical on main before this branch) — not caused by synthetic rows; out of scope, follow-up candidate |
| mutators-of / effects-of / pure-fns / capabilities-of | ✅ refuse cleanly without effects tables (unchanged) |
| LSP fallback path | ✅ compiles + selftest-callgraph-ocaml green; synthetic caller names flow through kind-less rows |

## Points of attention for review

- The generic `Texp_ident` occurrence case + `head_idents` loc-marking (double-emission guard) — newest code, one adversarial pass only.
- Go reclassification ordering (wellKnownTop/cgo AFTER enumerated demotion) — asserted in selftest.
- The R2-aware population-diff normalization (root-stripping + two sanctioned-replacement rules) — review the awk filter logic.

## Identified out-of-scope

- Pre-existing flat-only subcommand breakage on main schema (find/stats/fan-in/callees-of/reachable-from) — follow-up.
- 0-CFA closure-flow (research R3); Rust backend convergence; codex re-verification of steps 5–6 when spend cap resets.
