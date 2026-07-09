# Task — cfg-postdom-dominance

Precision redesign of arch-index call-graph edge kinds.

Goal: replace arch-callgraph-ocaml's syntactic dominance approximation (the `nested` counter in
`lib/arch_index/arch_index_cmt.ml` `collect_calls_from_expr`) with computed post-dominance, and
promote nested lambdas to their own graph nodes.

**(R1) Per-function CFG + post-dominators.** Lower each function body's Typedtree to a per-function
CFG — sequences/lets in-block; if/match/try/while/for/&&/|| as branch structures; known-noreturn
heads (`raise`, `raise_notrace`, `failwith`, `invalid_arg`, `exit`, `assert false`) as terminators
with no fall-through — then compute post-dominators (Cooper-Harvey-Kennedy on the reversed CFG,
virtual exit). A call is MUST iff its block post-dominates entry. Head-resolution logic (local-fn
stamps, partial/over-application via `fn_arity`, `let*` operators, arg-escapes) is unchanged; only
the "conditional?" test changes. This also closes the accepted divergence residual for unconditional
raises (code after `raise Exit;` lands in an unreachable block → demoted).

**(R2) Nested lambdas as graph nodes.** Each nested `fun …`/`function` literal becomes a synthetic
function node named `parent.<fun:LINE>` with its own CFG, so calls inside callback bodies (e.g.
`List.iter (fun x -> f x)`) become MUST edges of the lambda node instead of MAY_TOP of the parent.
Parent→lambda edge: MUST when the lambda is directly invoked on an always-exec path, MAY_ENUMERATED
when passed/stored/escaping.

**Prize:** 2032 of 2193 self-index MAY_TOP edges have known callees (only 161 are true ⊤).

**Constraints:**
- `.cmt` files carry Typedtree only (no Lambda IR).
- The walker is shared with `call_graph_extractor.ml` (LSP path) and the effects extractor — both
  must stay correct.
- Soundness contract inviolable: never a false MUST, never a dropped call — `reaches` = MUST-only
  under-approximation, `unreachable` = over-approximation per `docs/edge-kind-contract.md`.
- Regression-first per repo practice: extend `selftest-callgraph-soundness.sh` with P2-style
  targets before implementing.
- Codex adversarial review rounds after each phase.
- The Go backend already has real CFG post-dominance (`callgraph-go` `alwaysExec`) and is the
  reference for the post-dominator algorithm.
- Research grounding: `docs/research/control-flow-coverage-analysis.md` (recommendations R1+R2).

**Schema note:** synthetic lambda function rows change the self-index golden
(`test/fixtures/self-index-stats.txt`) and are visible in arch-query output.

**Additional research burden:** how mature analyzers (Soot/WALA/LLVM) name and link synthetic
closure/lambda nodes, and how OCaml's own tools (merlin/odoc) identify anonymous functions, where
not already covered by the existing research report.

**Maintainer decisions already made:** scope = R1+R2 together on one branch, phased (tests-first);
lambda node naming = `parent.<fun:LINE>` (line-number based, chosen over ordinal `<anon-N>`);
pipeline mode = Full with additional research as needed.
