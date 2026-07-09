# Plan — cfg-postdom-dominance

**Date:** 2026-07-09
**Status:** VALIDATED

## Consensus Table

| Point | Voice 1 (architect) | Voice 2 (codex) | Status |
|---|---|---|---|
| Regression-first step, incl. re-tagging P1s that US-4 legitimately flips (`cond_if` UNKNOWN→UNREACHABLE) | ✅ | ✅ (#10) | AGREE |
| `pending_call` must carry conditionality × resolvability as independent facts (not a pre-collapsed hint) — else US-4 forces a second rewrite and loses cross-module callee_ids | ✅ (structural finding) | ✅ (#3) | AGREE |
| US-4 (enumerated demotion) reordered BEFORE R2 | ✅ | no objection; #3 supports | AGREE |
| CFG lowering must preserve default-iterator-total coverage; the construct matrix (letop/opt-defaults/root-cases/short-circuit/arg-escapes) is the real cost, not the postdom algorithm | ✅ (risk 1) | ✅ (#4, #5, #12) | AGREE |
| Post-noreturn demotion needs ordered lowering with unreachable-block retention (block splitting) | ✅ (1a design) | ✅ (#6) | AGREE |
| Local-lambda MUST needs a shadowing-aware scoped table with occurrence accounting — not a flat Hashtbl | ✅ (4b risk) | ✅ (#7) | AGREE |
| LSP fallback (`call_graph_extractor.ml`) must be adapted with any walker signature change; semantic-drift audit explicit | ✅ | ✅ (#11) | AGREE |
| Go backend changes are IN scope for US-4 (intake's "Go out of scope" line is stale — spec supersedes; maintainer chose OCaml+Go) | ✅ | ✅ (#1, flags contradiction) | AGREE (intake line annotated) |
| Spec C-15 factually wrong: every top-level `Tpat_var` gets a row → parent→lambda edge resolves fine | not caught | ✅ (#9, verified) | AGREE (spec erratum applied) |
| Synthetic rows via existing `stmt_fn` during process_cmt; `fn_lookup` built by SELECT afterward → no insertion-ordering problem | ✅ (verified :258-267) | #2 warns only against emitting calls without rows | AGREE (descriptor-return design satisfies both) |
| Name-conflation of main-schema `unreachable`/`dead-code` (name-keyed roots) made more visible by synthetic rows | not raised | ✅ (#8) | AGREE (added to US-3 audit checklist) |
| CFG engine in a new module (`arch_index_cfg.ml`) for unit-testability | proposed | silent | Decided (see Decisions) |

No USER-CHALLENGE items — neither voice disputes the validated direction.

## Sequential steps

0. **Regression harness extension** — Extend the heredoc corpus + assertions in `selftest-callgraph-soundness.sh`: P2 targets for every AC (post-raise demotion AC-2/EC-3; try/noreturn AC-1/EC-1; lambda nodes AC-3/4; `escapes lam_map` empty AC-5; `unreachable cond_if island` UNREACHABLE AC-6); **re-tag** existing P1 assertions that US-4 legitimately flips (`cond_if`/`cond_functor`-style UNKNOWN verdicts → new expected UNREACHABLE/REACHABLE) as P2-flip entries with both old and new expectations documented. Extend `selftest-callgraph-go.sh` with a MAY_ENUMERATED-demotion expectation (initially failing, gated like P2). Completion: `STRICT=0` run green; P2 xfail list = exactly the target behaviors. *Note: branch CI (STRICT=1) stays red until step 7 — the merge gate is final green (same discipline as the previous soundness branch).*
1. **CFG engine module** — New `lib/arch_index/arch_index_cfg.ml(i)`: block/edge arena (int-indexed), terminal + noreturn terminator marking, virtual exit, `hasExit` guard, iterative post-dominance fixpoint (port of `callgraph-go/main.go:198-264`), `always_exec : t -> BlockSet.t`, plus entry-reachability (blocks unreachable from entry). Pure — no Typedtree dependency. Alcotest unit tests: single-block, diamond, loop, exit-less, terminator-split, unreachable-tail. Completion: `dune test` green.
2. **Walker rewrite onto the CFG (kinds behavior-preserving)** — Rewrite `collect_calls_from_expr` (`arch_index_cmt.ml:378-694`): ordered lowering with a current-block ref (block splitting at branch/terminator points); every construct in today's matrix explicitly lowered or hitting the FR-006 conservative default (subcalls demoted, fall-through preserved); `pending_call` redesigned to carry `{block_conditional : bool; head : resolved-path facts (module preserved)}` replacing the collapsed `kind_hint`; arg-escapes/letop consume block-conditionality instead of `!nested > 0`; `.mli` + `call_graph_extractor.ml:190-243` adapted; resolution loop (`arch_index.ml:278-352`) maps the new model to today's exact kinds (demoted-resolved still MAY_TOP at this step). Completion: `dune test` + all selftests + `STRICT=1`-P1 green; golden regenerated; **old-vs-new callee-population diff shows kind-monotonicity + zero drops (hard gate, script kept in `scripts/`)**; codex adversarial round GO.
3. **Noreturn terminators + try model** — Path-based saturated-head detection (`Stdlib.{raise,raise_notrace,failwith,invalid_arg,exit}`, `assert false`); terminator blocks edge to virtual exit; inside a try body: noreturn head gets handler-dispatch + virtual-exit successors, handlers flow to the post-try join, handlers never post-dominate. Flips the corresponding P2s. Completion: those assertions P1-green; codex round GO.
4. **US-4 enumerated demotion (OCaml + Go)** — OCaml: resolution loop emits demoted+uniquely-resolved as MAY_ENUMERATED with callee_id (extending resolution to qualified callees — voice-2 #3); MAY_TOP reserved for computed heads/params/`qualified_is_dynamic`/over-application residuals. Go: both gates (`main.go:523-528`, `:576-586`) demote to MAY_ENUMERATED; well-known-⊤ reclassification (`:589-593`) stays MAY_TOP and runs after. Flips re-tagged P2s + the Go assertion. Completion: green; golden regen; codex round GO (both backends).
5. **R2a — lambda nodes for literal occurrences** — Walker returns lambda-node descriptors (name chain `<parent>.<fun:L:C>` w/ collision handling, loc range, arity, signature-if-cheap) alongside calls; `process_cmt` inserts them via `stmt_fn` (exposed=0, parent module_id); lambda bodies get their own CFG (own entry, own postdom); body calls attributed to the lambda node; literal-argument occurrences emit parent→lambda MAY_ENUMERATED replacing the `*TOP*` arg-escape row; LSP path destructures the new return shape (names flow through flat rows). Completion: AC-3(part)/AC-5 P2s flip; golden regen; codex round GO.
6. **R2b — local lambda invocation MUST** — Scoped stamp→(node,arity) table for single-literal `Tpat_var` lets, with shadowing/rebinding eviction; occurrence accounting: saturated head invocation on always-exec block → MUST, any other occurrence → MAY_ENUMERATED escape edge at that site, zero occurrences → no edge; negative fixtures (rebound, conditional binding, tuple pattern, partial application). Completion: AC-3/AC-4 P1-green; codex round GO.
7. **US-3 audit + docs + ship hygiene** — One-time audit table of all 15 functions/calls-reading arch-query subcommands vs synthetic rows (incl. voice-2 #8 name-conflation check on main-schema `unreachable:151`/`dead-code:399` roots); LSP smoke; `docs/edge-kind-contract.md` update (computed post-dominance, lambda nodes, enumerated demotion, narrowed divergence residual); self-index kind distribution recorded in QA brief (expect MAY_TOP well under 40%); `rm -rf _build` clean rebuild → final golden; `STRICT=1` + full gate set green. Completion: everything green, docs updated.

## Dependencies

0 → 1 → 2 → {3, 4} → 5 → 6 → 7. Step 3 and 4 are independent of each other (both depend on 2). Step 5 depends on 4 (lambda-edge kinds consume enumerated semantics, C-16/C-17). Codex rounds are completion criteria of steps 2–6, not separate steps.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Step-2 big-bang rewrite of the 320-line classifier drops calls in implicit-traversal constructs (letop conts, opt-defaults, root cases) | High | High (soundness) | Population-diff hard gate; FR-006 conservative default; construct-matrix checklist in implementer brief; codex round |
| Try/noreturn model forges MUST via handler-dispatch or drops post-try code | Medium | High | EC-1/EC-3 fixtures land in step 0 before the code; explicit CFG shape in brief |
| Scoped stamp table leaks a stale literal across shadowing/rebinding → false MUST | Medium | High | Eviction semantics specified; negative fixtures mandatory in step 6 |
| Ghost/ppx duplicate LINE:COL → nondeterministic ordinal → golden instability | Low-Med | Medium | Deterministic traversal-order ordinal; determinism check (index twice, diff) in step 5 |
| LSP-path semantic drift (duplicated pre-pass) | Medium | Medium | Signature change forces compile-time adaptation; step-7 audit re-checks semantics |
| Go soundiness reclassification ordering vs enumerated demotion (reflection edge accidentally enumerated) | Low | High | Ordering pinned in step 4; Go selftest assertion |
| MAY_TOP share doesn't fall under 40% | Medium | Low | CHECK-6 is a manual QA record, not a CI gate |
| Branch CI red (STRICT P2 xfails) mid-branch confuses reviewers | Low | Low | Documented here + in PR description; merge gate = final green |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| US-4 ordered before R2 | Adopted (step 4 before 5) | Both voices: data model makes it near-free; R2 edge kinds consume it |
| CFG engine location | New `lib/arch_index/arch_index_cfg.ml(i)` | Pure, unit-testable via dune test; keeps the walker readable |
| `pending_call` model | Carries block-conditionality + preserved resolution facts; `kind_hint` collapse removed | AGREE point; avoids double rewrite and callee_id loss |
| Population-diff script | Kept in-repo (`scripts/callgraph-diff.sh` or similar) | Strongest no-drop evidence; reusable for the Rust backend |
| Landing granularity | Per-step commits on one feature branch, single PR, branch CI red on STRICT until step 7 | Matches previous soundness-branch discipline |
| Collision ordinal format | `<fun:LINE:COL#N>` — ordinal inside the marker (quiz-bound) | Unambiguous vs the `.` chain separator; greppable |

## Assumptions

- `pending_call`/`kind_hint` are internal API (verified: only `arch_index.ml` + `call_graph_extractor.ml` consume; no unit test references).
- "Extend fixtures" = the heredoc corpus inside `selftest-callgraph-soundness.sh`; `test/fixtures/` holds only the golden.
- Lambda signature strings reuse the existing type-printing helper where cheap, else NULL.
- Argument subexpressions evaluate in the call's own block (unconditional); OCaml's unspecified arg order irrelevant to block membership.
- Loader accepts MAY_ENUMERATED from the OCaml producer (it already emits it; `selftest-load.sh` confirms in step 4).
- Golden regenerated per step; the branch merges only when all-green.
