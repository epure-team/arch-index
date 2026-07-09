# Implementer Sub-Brief — cfg-postdom-dominance

**Status:** VALIDATED
**Sources of truth:** `specs/cfg-postdom-dominance.md` (contract), `briefs/cfg-postdom-dominance-plan.md` (steps), `briefs/cfg-postdom-dominance-intake.md` (context). Read all three in full.

## Goal (one line)

Replace the syntactic `nested`-counter dominance in `arch-callgraph-ocaml` with computed post-dominance over per-function CFGs; promote `fun`/`function` literals to synthetic graph nodes; demote conditional-but-resolved calls to MAY_ENUMERATED in both OCaml and Go backends.

## Non-negotiables

- **Soundness invariant:** never a false MUST; never a dropped call. Any unmodeled construct → conservative (record demoted), never skip.
- **Build env:** EVERY shell starts with `eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)`. Confirm `which dune` = `.../arch-index/_opam/bin/dune`. Wrong-switch errors (eio/cohttp/mirage-crypto) are spurious.
- **Golden discipline:** `rm -rf _build && dune build` before trusting a self-index count; regenerate `test/fixtures/self-index-stats.txt` deliberately, per step.
- **Codex adversarial round = completion criterion of steps 2–6** (`codex exec --skip-git-repo-check --sandbox workspace-write "<prompt>" >out 2>&1 </dev/null` — MUST redirect stdin). Include the switch-pin eval line in every codex prompt.
- **No cross-arm MUST merging** (per-block post-dominance only). `reaches` stays MUST-only.
- Branch: create `feat/cfg-postdom-dominance` off main. Per-step commits; branch CI may be red on STRICT until step 7; merge gate = all green.

## Key code anchors (verified)

- Walker: `lib/arch_index/arch_index_cmt.ml:378-694` (`collect_calls_from_expr`); `nested` counter `:436`; construct cases `:510-643`; peel + opt-defaults `:652-693`; `Texp_apply` head/saturation/escape logic `:561-629`; `fn_arity` `:366`; pre-pass `local_fn_stamps` `:759-781`; per-binding invocation `:1020-1027`; function-row insertion for every top-level `Tpat_var` `:830` (non-function bindings included — parents always have rows).
- Resolution loop (only kind_hint consumer): `lib/arch_index/arch_index.ml:278-352`; `fn_lookup` built from SELECT after inserts `:258-267` (⇒ lambda rows inserted via `stmt_fn` during process_cmt resolve for free); contract stamp `:360-363`.
- LSP path (kind discarded, signature-coupled): `lib/arch_index/call_graph_extractor.ml:190-243`.
- Go reference + step-4 target: `callgraph-go/main.go:198-264` (`alwaysExec`), gates `:523-528` and `:576-586`, well-known-⊤ reclassification `:589-593` (must stay MAY_TOP, must run after demotion).
- Soundness suite: `selftest-callgraph-soundness.sh` (heredoc corpus ~line 59; `chk P1|P2` machinery `:183-197`; STRICT exit `:254-256`). Go suite: `selftest-callgraph-go.sh:145-162`.

## Sequential steps (execute in order; each step ends green + committed)

### Step 0 — Regression harness
Extend the soundness corpus + assertions with P2 targets for: post-raise demotion (`raise Exit; g x` → no MUST path, not dropped); try/noreturn (`try raise Exit with Not_found -> h x` → h not MUST, recorded; raise MUST); lambda nodes (US-2 scenarios 1–5 incl. unused-lambda no-edge); `escapes lam_map` = empty; `unreachable cond_if island` = UNREACHABLE. **Re-tag** existing P1 assertions that US-4 flips (any `unreachable … = UNKNOWN` where the only ⊤ was a demoted-resolved call — e.g. cond_if/cond_match family) as P2-flip entries carrying the new expectation. Add a gated MAY_ENUMERATED-demotion expectation to `selftest-callgraph-go.sh`. Completion: `STRICT=0` green; P2 list = exactly the targets.

### Step 1 — CFG engine
New `lib/arch_index/arch_index_cfg.ml(i)`: int-indexed block arena; edges; terminator marking; virtual exit; `hasExit` guard (no exit ⇒ empty always-exec set); iterative post-dominance fixpoint (port Go `alwaysExec`: init full sets, exit={exit}, intersect-over-successors ∪ self, iterate); entry-reachability. Pure (no Typedtree). Alcotest units: single-block, diamond (merge block MUST), loop (body not MUST, code after MUST), exit-less (`hasExit=false`), terminator split (post-terminator block unreachable), unreachable tail. Completion: `dune test` green.

### Step 2 — Walker onto CFG (kinds behavior-preserving)
Rewrite `collect_calls_from_expr` to lower bodies onto the CFG with a *current-block ref* (split at branch/terminator points; conditional regions = new blocks with proper edges; deferred regions (lazy/object/functor) = separate not-always-exec context as today). Replace `pending_call.kind_hint` with independent facts: `{cond : bool (call block ∉ always-exec); head : Resolved of (module option * name) | LocalFn of … | Param | Computed | …}` — preserve the callee module for demoted qualified calls (today it collapses into a display string at `:599-605`; that collapse must go). Arg-escapes + letop consume block-conditionality instead of `!nested > 0`. Construct matrix checklist (each explicitly lowered or FR-006 conservative): ifthenelse, match (arms+guards conditional), try (body eager, handlers conditional), while/for, assert, `&&`/`||` (right operands conditional), letop (operators+operands eager, continuation conditional), root `Tfunction_cases` (arms conditional), optional-arg defaults (conditional), peel, partial/over-application (unchanged semantics incl. residual `*TOP*`), lazy/object/functor (deferred). Adapt `.mli` and `call_graph_extractor.ml`. Resolution loop maps the new model to **today's exact kinds** (demoted-resolved → MAY_TOP still).
**Hard gate:** population-diff script (keep as `scripts/callgraph-diff.sh`): index self twice (old binary from main via git worktree or stash, new binary), compare `(caller,callee,site)` sets — zero drops; kinds only move within {same, MUST→demoted}. Plus all selftests + STRICT-P1 + golden + codex round GO.

### Step 3 — Noreturn + try model
Noreturn = saturated `Texp_apply` whose head Path resolves to `Stdlib.raise|raise_notrace|failwith|invalid_arg|exit`, or `Texp_assert` of literal `false`. Terminator block → edge to virtual exit only. Inside a try body: terminator → edges to handler-dispatch AND virtual exit; handlers branch from dispatch, flow to post-try join; handlers never post-dominate. Shadow-proof by construction (Path-based). `raise` as argument/partial/eta → NOT a terminator. Flips the corresponding P2s. Codex round GO.

### Step 4 — Enumerated demotion (OCaml + Go)
OCaml resolution loop: `cond=true` + uniquely-resolved head → `MAY_ENUMERATED` with callee_id (extend resolution to qualified callees — reuse the Resolve-path lookup, keep display name). MAY_TOP reserved: computed heads, params/locals-not-fn, `qualified_is_dynamic`, over-application residual, deferred-region calls without known target. Go: both gates demote to `MAY_ENUMERATED` instead of MAY_TOP; verify well-known-⊤ reclassification still runs after and yields MAY_TOP. Flips re-tagged P2s + Go assertion. `selftest-load.sh` confirms loader path. Golden. Codex round GO (cover both backends).

### Step 5 — Lambda nodes (literal occurrences)
Walker returns lambda descriptors alongside calls (new return record): name = enclosing chain + `<fun:LINE:COL>` (1-based col from `loc_start`; on intra-module collision append `#N` inside the marker: `<fun:LINE:COL#2>`), loc range, syntactic arity, signature when cheap. `process_cmt` inserts via `stmt_fn` (exposed=0, parent module_id, comment fields NULL). Lambda bodies lowered with their own CFG; body calls attributed to the lambda node (caller_name = lambda name). Literal argument occurrence → parent→lambda MAY_ENUMERATED **replacing** the `*TOP*` arg-escape row for literals. Returned/stored literal → MAY_ENUMERATED at that site. Lazy/object/functor NOT promoted. LSP path: destructure the new return shape; flat rows carry synthetic caller names; no function rows there. Determinism check: index twice, byte-diff DB dumps. Flips lam_map/escapes P2s. Golden. Codex round GO.

### Step 6 — Local lambda invocation MUST
Scoped stamp→(node-name, arity) table for `Texp_let` with `Tpat_var` + single-literal RHS; push/pop with scope; shadowing/rebinding evicts; `let rec` self-reference allowed. At head application of a recorded stamp: saturated + block always-exec → MUST; saturated + conditional → MAY_ENUMERATED; under-saturated → MAY_ENUMERATED; any non-head occurrence → MAY_ENUMERATED escape edge at that site; zero occurrences → no edge. NOT recorded: conditional bindings, tuple patterns, rebound values. Negative fixtures mandatory (rebound/conditional/tuple/partial). Flips invoked_closure P2s. Codex round GO.

### Step 7 — Audit + docs + ship hygiene
Audit all 15 arch-query subcommands vs synthetic rows (incl. name-conflation of main-schema `unreachable:151` and `dead-code:399` roots — document findings; fix only demonstrated breakage). LSP smoke. Update `docs/edge-kind-contract.md`: computed post-dominance (drop "no CFG" phrasing), lambda-node semantics, enumerated demotion (both backends), narrowed divergence residual (closed for syntactic noreturn heads outside try; termination/exception-insensitivity for ordinary calls remains). Record self-index kind distribution (expect MAY_TOP well under 40%). `rm -rf _build`, full gates, final golden, STRICT=1 green.

## Quality Gates (run at every step)

```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build && dune test
./selftest-contract.sh && ./selftest-load.sh && ./selftest-effects.sh && \
./selftest-callgraph-ocaml.sh && ./selftest-callgraph-go.sh
STRICT=1 ./selftest-callgraph-soundness.sh   # red until step 7 is acceptable ON THE BRANCH ONLY for P2 targets
# golden
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
```

## Risks to watch (from dual-voice analysis)

1. Step 2 dropped calls in implicit-traversal constructs (letop continuations, opt-defaults, root cases) — the population diff is the gate.
2. Try/noreturn: handler-dispatch must never let a handler post-dominate; post-try join must stay reachable via handlers.
3. Scoped table leaks across shadowing → false MUST — eviction + negative fixtures.
4. Ghost/ppx duplicate locs → ordinal determinism — traversal-order ordinals + double-index diff.
5. Go reclassification ordering — reflection edges must stay MAY_TOP.
