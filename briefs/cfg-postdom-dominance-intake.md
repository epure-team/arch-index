# Intake Brief — cfg-postdom-dominance

**Date:** 2026-07-09
**Status:** VALIDATED
**Type:** feature

## Goal

Replace `arch-callgraph-ocaml`'s syntactic dominance approximation (the `nested` counter in
`lib/arch_index/arch_index_cmt.ml collect_calls_from_expr`) with **computed post-dominance over a
per-function CFG** (R1), and **promote nested lambdas to their own graph nodes** (R2).

R1: lower each function body's Typedtree to a per-function CFG — sequences/lets in-block;
if/match/try/while/for/&&/|| as branch structures; known-noreturn heads (`raise`, `raise_notrace`,
`failwith`, `invalid_arg`, `exit`, `assert false`) as terminators with no fall-through — then
compute post-dominators (Cooper-Harvey-Kennedy / iterative fixpoint on the reversed CFG with a
virtual exit, mirroring `callgraph-go alwaysExec`). A call is MUST iff its block post-dominates
entry. Head-resolution logic (local-fn stamps, partial/over-application via `fn_arity`, `let*`
operators, arg-escapes) is unchanged; only the "conditional?" test changes. This also closes the
documented divergence residual: code after an unconditional `raise` lands in an unreachable block
and is demoted.

R2: each nested `fun …`/`function` literal becomes a synthetic function node named
**`parent.<fun:LINE>`** (maintainer-chosen convention; note: industry norm is ordinal-per-parent —
Go `func1`, Rust `{closure#0}` — but line-based was explicitly chosen for locatability; Python
cProfile is the line-based precedent) with its own CFG, so calls inside callback bodies (e.g.
`List.iter (fun x -> f x)`) become MUST edges *of the lambda node* instead of MAY_TOP of the parent.
Parent→lambda edge: MUST when the lambda is directly invoked on an always-exec path,
MAY_ENUMERATED when passed/stored/escaping.

**Value:** 2032 of 2193 self-index MAY_TOP edges have known callees (only 161 true ⊤); the blunt
~78% MAY_TOP rate makes `reaches` nearly useless through callbacks and floods `escapes` with noise.

## Scope Boundary

Explicitly OUT of scope:
- The Go backend (already has real CFG post-dominance; untouched).
- The Rust backend (designed, unbuilt).
- 0-CFA closure-flow (research R3) — future task.
- MC/DC condition analysis (research R4) — rejected by research as low leverage.
- The effects extractor (`lib/arch_effects/ocaml_effects_extractor.ml`) — confirmed independent
  (own Tast_iterator, no shared code, no kinds).
- The LSP path's *output* (`call_graph_extractor.ml` discards `kind_hint`; its `call_row` has no
  kind column) — it must keep compiling and its call attribution must stay coherent, but no new
  kind/lambda features are required there.
- A general `noreturn` inference (beyond the fixed known-noreturn head list).
- arch-query changes beyond what synthetic rows require for existing queries to stay correct.

## Relevant Files

| File | Role | Key facts (from research + prior task) |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml` | Core walker — main rewrite site | `collect_calls_from_expr` :378-694; `nested` counter :436; construct cases :510-643; peel :666-689; `fn_arity` :366-370; pre-pass `local_fn_stamps` :759-781; walker invoked per top-level binding :1020-1027 |
| `lib/arch_index/arch_index_cmt.mli` | Interface | `call_kind_hint`, `pending_call`, `collect_calls_from_expr`, `fn_arity`, `is_function_rhs` exported; will need new types for lambda nodes |
| `lib/arch_index/arch_index.ml` | kind_hint → kind resolution + function-row INSERT | resolution loop :278-352 (only consumer of kind_hint); functions INSERT :166-170; contract flag :360-363. Synthetic lambda rows must be inserted before call resolution so parent→lambda and lambda→callee edges resolve to ids |
| `lib/arch_index/call_graph_extractor.ml` | LSP path (kind discarded) | replicates pre-pass :190-208, calls walker :219-225, maps to kind-less `call_row` :231-243 — must keep compiling; lambda-node calls must not corrupt its flat output |
| `callgraph-go/main.go` | Reference post-dominator algorithm | `alwaysExec` :198-264 (virtual exit, hasExit guard, bool-matrix fixpoint), `runsAlways` :266-287 |
| `selftest-callgraph-soundness.sh` | Regression suite (extend FIRST) | P1/P2 + STRICT machinery :183-197; fixtures Cg/Crb; CI runs STRICT=1 |
| `test/fixtures/self-index-stats.txt` | Golden | `18 / 150 / 2809` — will change (new function rows, kind shifts) |
| `architecture-schema.sql` | Schema | functions table :23-45 (17 cols, module_id FK, name, line_start/end, exposed); calls :73-85; **no schema change expected** — synthetic lambdas are ordinary rows |
| `arch-query` | Query surface | 15 subcommands read functions/calls; `exported`/`find`/`dead-code`/`stats` will see synthetic rows; `%*TOP*%` name-filters exist :334,355,419 |
| `docs/edge-kind-contract.md` | Contract doc | dominance definition + shared-residuals section — update (divergence residual partially closed; lambda-node semantics) |
| `docs/research/control-flow-coverage-analysis.md` | Research grounding | R1 (CFG+postdom keystone), R2 (deferred HOF-body linking = biggest MAY_TOP cut) |

## Architecture Notes

- **kind_hint bottleneck is favorable:** only `arch_index.ml`'s resolution loop consumes
  `kind_hint`; the LSP path discards it and the effects extractor is fully independent. The
  dominance rewrite is therefore contained in `arch_index_cmt.ml` + the resolution loop.
- **CFG substrate:** `.cmt` carries Typedtree only — the CFG must be lowered from Typedtree
  expressions. Blocks can be lists of call-site records; edges from the branch constructs already
  special-cased today (if/match/try/while/for/&&/||/letop). `Texp_function`/`Texp_lazy`/
  `Texp_object`/`Tmod_functor` bodies stay out of the parent CFG (they become lambda nodes in R2,
  or stay deferred for lazy/object/functor).
- **Post-dominance algorithm:** port the Go `alwaysExec` shape — succ lists, virtual exit fed by
  terminal blocks, `hasExit` guard (a body whose every path diverges → nothing MUST), iterative
  intersection fixpoint. OCaml function bodies are small; the bool-matrix fixpoint is adequate
  (self-index max function size is modest; complexity concerns are not real here).
- **Noreturn terminators:** a fixed head list (`raise`, `raise_notrace`, `failwith`, `invalid_arg`,
  `exit`, `assert false` — Stdlib-qualified or bare) ends a block with no fall-through edge; code
  after it belongs to an entry-unreachable block → demoted. `try` bodies need care: a noreturn via
  exception inside `try … with` DOES fall through to the handlers, so within a try body, raising
  heads edge to the handler blocks, not to nothing.
- **Lambda-node identity (R2):** synthetic rows named `parent.<fun:LINE>` share the parent's
  module_id, carry the lambda's own line_start/line_end, `exposed=0`. Caller attribution changes:
  calls inside a lambda body get `caller_name = parent.<fun:LINE>`. Parent→lambda edge kind: MUST
  if directly invoked on an always-exec path (e.g. `let h () = … in h ()` where the invocation
  post-dominates entry), MAY_ENUMERATED when the lambda is passed/stored/escapes (covers
  `List.iter (fun …)`), MAY_TOP if it escapes into unknowable positions. `unreachable`'s
  MUST∪MAY_ENUMERATED closure then reaches lambda bodies without ⊤, and `reaches` stays honest
  (no MUST through a merely-passed callback).
- **Soundness invariants (inviolable):** never a false MUST; never a dropped call. Any construct
  the CFG lowering does not model must fall back to "not always-exec" (demote), never to MUST.
  Kind-monotonicity vs today is the review yardstick: each edge may only move MAY_TOP→{MUST,
  MAY_ENUMERATED} when *proven*, and any new MUST must be provable by post-dominance.
- **LSP-path coherence:** `call_graph_extractor.ml` maps walker output to kind-less rows keyed by
  caller_name. With R2, lambda-attributed calls will carry synthetic caller names there too;
  its flat table has no functions FK so this is safe, but the mapping code must be re-checked.
- **Consumers of synthetic rows:** `exported` (they're exposed=0 → filtered), `dead-code` (must not
  flag a lambda whose parent edge is MAY_ENUMERATED — closure uses MUST∪MAY_ENUMERATED∪MAY_TOP, so
  fine), `stats`/golden (counts grow), `find` (pattern `<fun:` visible — acceptable, chosen).
- **Process:** regression-first (extend soundness selftest with P2 targets before implementing);
  codex adversarial round after each phase; build under local `_opam` switch
  (`eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)` in EVERY shell);
  `rm -rf _build` before trusting golden counts.

## Quality Gates

```bash
# Switch pin (every shell — non-negotiable)
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)

# Build
dune build

# Tests (unit + integration)
dune test

# Shell integration gates (all must pass)
./selftest-contract.sh && ./selftest-load.sh && ./selftest-effects.sh && \
./selftest-callgraph-ocaml.sh && STRICT=1 ./selftest-callgraph-soundness.sh && \
./selftest-callgraph-go.sh

# Self-index golden (regenerate deliberately, never to silence a diff)
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -

# Lint/Format: not documented (repo has no fmt gate; match surrounding style)

# Cross-runtime adversarial review (mandatory per phase)
codex exec --skip-git-repo-check --sandbox workspace-write "<prompt>" >out 2>&1 </dev/null
```

## Open Questions

- [ ] **Match-arm MUST refinement**: with a real CFG, `match x with A -> f () | B -> f ()` could
  prove `f` MUST (called in every arm) — the Go backend does NOT do this (per-block only) and it
  was declared an accepted precision limitation cross-language. Implementers must NOT add
  cross-arm merging unless the maintainer opts in; default = per-block post-dominance only
  (consistent with Go).
- [ ] **Lambda nodes on the LSP path**: `call_graph_extractor.ml`'s flat output will show synthetic
  caller names. Acceptable (flat schema has no FK), but implementers must not assume the LSP
  fallback needs lambda *function rows* — it has no functions table access.
- [ ] **`lazy`/`Texp_object`/functor bodies under R2**: task scopes R2 to `fun`/`function`
  literals only. Lazy thunks/object methods/functor bodies remain plain deferred (MAY_TOP,
  attributed to parent) — do not extend node promotion to them without a maintainer decision.
