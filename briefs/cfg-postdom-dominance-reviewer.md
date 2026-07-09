# Reviewer Sub-Brief — cfg-postdom-dominance

**Status:** VALIDATED
**Contract:** `specs/cfg-postdom-dominance.md`. Plan: `briefs/cfg-postdom-dominance-plan.md`.

## What was implemented (expected)

1. New pure CFG engine `lib/arch_index/arch_index_cfg.ml(i)` (blocks, virtual exit, hasExit guard, iterative post-dominance) with unit tests.
2. `collect_calls_from_expr` rewritten onto the CFG; `kind_hint` replaced by independent facts (block-conditionality × preserved head resolution); arg-escapes/letop consume block-conditionality.
3. Noreturn terminators (Path-resolved `Stdlib.{raise,raise_notrace,failwith,invalid_arg,exit}` saturated head; `assert false`) with the try model (terminator in try body → handler-dispatch + virtual exit; handlers never post-dominate).
4. Enumerated demotion in BOTH backends: conditional + uniquely-resolved → MAY_ENUMERATED with callee_id; MAY_TOP only for unknowable targets. Go gates changed at `callgraph-go/main.go:523-528`, `:576-586`; well-known-⊤ reclassification must remain last and MAY_TOP.
5. Lambda nodes: `<chain>.<fun:LINE:COL>` (1-based col; `#N` in-marker ordinal on collision), exposed=0, own CFG, body-call attribution, per-occurrence parent→lambda edges (MUST only for saturated always-exec head invocation; MAY_ENUMERATED otherwise; none for zero occurrences), literal-arg edge REPLACES `*TOP*` escape row.
6. Scoped local-lambda stamp table with shadowing eviction (step 6).
7. Query audit (15 subcommands), `docs/edge-kind-contract.md` update, goldens.

## Audit first (in order)

1. `lib/arch_index/arch_index_cmt.ml` — the construct matrix: verify EVERY case previously special-cased still records its calls (ifthenelse/match/try/while/for/assert/&&/||/letop/root-cases/opt-defaults/peel/partial/over-app/lazy/object/functor). The FR-006 fallback must record-demoted, never skip.
2. `scripts/callgraph-diff.sh` output (step-2 hard gate): zero dropped `(caller,callee,site)`; kind movement only {same, MUST→demoted}. Demand the artifact, do not take the claim.
3. `lib/arch_index/arch_index_cfg.ml` — fixpoint init/termination; hasExit; terminator-in-try edges (handler must NOT post-dominate; post-try join reachable via handlers).
4. `lib/arch_index/arch_index.ml` resolution loop — demoted-resolved path keeps callee_id + display name (voice-2 #3: the old code collapsed module into a display string at demotion; that must be gone).
5. `callgraph-go/main.go` — demotion gates and reclassification ORDER (reflection/cgo must still end MAY_TOP).
6. `call_graph_extractor.ml` — adapted to new walker signature; no kind logic added; flat rows coherent.
7. `selftest-callgraph-soundness.sh` — every spec AC has an assertion; re-tagged P1→P2 flips carry the US-4 expectations; STRICT green at completion.

## Risks to verify (each must have evidence)

| Risk | Evidence demanded |
|---|---|
| Dropped calls in rewritten walker | population-diff artifact + STRICT suite + codex GO transcripts |
| False MUST via try handler post-domination | EC-1 fixture assertion + CFG unit test for the dispatch shape |
| Stale scoped-table entry across shadowing → false MUST | negative fixtures (rebound/conditional/tuple) in the suite |
| Lambda name nondeterminism (ghost locs, ordinals) | double-index byte-diff evidence |
| Go reflection edge accidentally MAY_ENUMERATED | Go selftest assertion + reading the reclassification order |
| reaches semantics drift | grep arch-query: `reaches` still MUST-only filter |
| Contract doc honesty | edge-kind-contract.md diff matches shipped behavior |

## Expected behaviors to confirm (spot-run)

- `reaches invoked island` = PATH EXISTS (local lambda invoked); `reaches lam_map island` = no MUST path.
- `unreachable cond_if island` = UNREACHABLE (enumerated demotion, no fake ⊤).
- `escapes lam_map` = empty frontier.
- `try raise Exit with Not_found -> h x`: h edge exists, kind ≠ MUST; raise edge MUST.
- Unused bound lambda: node exists, no parent edge.
- No NULL/invalid kinds; `callgraph_contract=v1` stamped; golden matches clean rebuild.

## Mode

full — all conditional specialists apply; cross-runtime (codex) review mandatory.
