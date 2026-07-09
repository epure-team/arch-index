# Research — cfg-postdom-dominance

_Generated: 2026-07-09_
_Mode: full (4 specialists: locator, analyzer, pattern-finder, external researcher)_
_Online research: enabled_

## Question 1: How does `collect_calls_from_expr` classify call edges?

**Finding:** The walker (`lib/arch_index/arch_index_cmt.ml:378-694`) returns `pending_call list`; each
call carries a `kind_hint` (`Resolve | May_top | May_enumerated`, `:255-266`). Conditionality is a
single `nested : int ref` counter (`:436`): any call recorded while `!nested > 0` is forced MAY_TOP.
Increment/decrement sites: `walk_deferred` (`:498-502`), `Texp_function|Texp_lazy|Texp_object`
(`:511-518`), `Tmod_functor` (`:637-642`), root `Tfunction_cases` (`:682-688`), optional-arg
defaults (`:691-693`).

Construct treatment: `Texp_ifthenelse` cond eager / branches deferred (`:519-523`); `Texp_match`
scrutinee eager / arms+guards deferred (`:524-528`); `Texp_try` body eager / handlers deferred
(`:529-533`); `Texp_while`/`Texp_for` cond/bounds eager, body deferred (`:534-542`); `Texp_assert`
deferred (`:543-545`); `&&`/`||` first operand eager, rest deferred (`short_circuit_arity` `:484-489`,
apply-site `:620-629`); `Texp_letop` emits bind-operator calls via `add_path_call` (`:466-482`) +
operands eager + body deferred (`:546-560`).

Saturation: `fn_arity` syntactic arity (`:366-370`), `arrow_arity` on raw type (`:405-408`),
`is_arrow` (`:397-399`); `partial = is_arrow expr.exp_type || nargs < head_arity` (`:585`);
over-application emits residual MAY_TOP `*TOP*` (`:610-616`). Head classification `:586-609`.
`add_arg_escapes` (`:440-461`): function-typed args → May_enumerated (named local fn) / May_top.
Peel step strips the binding's own param lambdas (`:666-689`); collects `Tparam_optional_default`
expressions for deferred walking (`:652-664`).

Pre-pass (`:759-781`): `local_fn_stamps : (Ident.unique_name, fn_arity) Hashtbl` over all
`Tstr_value` bindings whose pattern is `Tpat_var` and RHS `is_function_rhs` (`:354-358`).

## Question 2: Who consumes the shared walker?

**Finding — blast radius is smaller than assumed:**

- **(a) Main indexer** (`arch_index.ml`): calls the walker per top-level binding
  (`arch_index_cmt.ml:1020-1027`); resolution loop (`arch_index.ml:278-352`) maps `kind_hint` →
  final kind via `fn_lookup` (May_top→MAY_TOP `:299`; May_enumerated `:300-306`; Resolve→MUST or
  MAY_TOP `:307-341`); `insert_call` `:343-350`; contract flag stamped `:360-363`. **This is the
  only consumer that uses `kind_hint`.**
- **(b) LSP path** (`call_graph_extractor.ml`): LSP callHierarchy first, cmt fallback second
  (`:157-246`); replicates the pre-pass (`:190-208`) and calls the walker (`:219-225`) — but maps
  results to `call_row` (`:231-243`) which **discards `kind_hint` entirely** (no kind field,
  `.mli:9-15`); `runner.ml:159-176` writes a flat calls table with **no kind column**.
- **(c) Effects extractor** (`lib/arch_effects/ocaml_effects_extractor.ml:149-188`): does **not**
  share the walker — its own `Tast_iterator` with no nesting/kind logic; no reference to
  `Arch_index_cmt`.

## Question 3: Go backend dominance (reference implementation)

**Finding:** `alwaysExec` (`callgraph-go/main.go:198-264`): index map, `succ [][]int` with terminal
blocks (no successors: return/panic) → virtual exit `n`; **`hasExit` guard** returns empty set for
`for {}` (all demote, sound); post-dominance fixpoint over a `(n+1)×(n+1)` bool matrix — real blocks
initialised full, exit `{exit}`, iterate `next = ∩_{s∈succ} pdom[s] ∪ {i}` to fixpoint; result =
blocks with `pdom[entry]` true. Memoised per function (`alwaysExecCache`/`runsAlways` `:266-287`,
nil-safe false). Gates MUST→MAY_TOP in both the CHA edge-visitor (`:576-586`) and the generics
fallback SSA walk (`:523-528`).

## Question 4: How are anonymous functions represented today?

**Finding:** Nested/anonymous functions get **no graph node**. Only top-level `Tpat_var` bindings
with `Texp_function` RHS become function rows. Every call inside a lambda body is attributed to the
enclosing **top-level** binding's `caller_name` (fixed at walker entry, `:378-386`) with kind
MAY_TOP (via the `nested` counter). The peel step (`:646-651` comment) distinguishes the binding's
own params from genuinely nested literals.

## Question 5: What does the soundness selftest cover?

**Finding:** `selftest-callgraph-soundness.sh` builds a two-module corpus (Cg + Crb) with labelled
fixtures (direct chain, unused/invoked closures, HOF lambda/named/param/computed callbacks, FCM
param, cond_if/match/try/andalso/assert/functor, root_fun/root_guard, letop, partial/alias-partial,
over-application, lazy, opt-default, mutual recursion). Helpers: `verdict` (greps arch-query output
tokens), `refuses` (exit 3), `chk P1|P2` (`:183-197`). P1 = must pass; P2 = redesign targets (XFAIL
allowed unless `STRICT=1`) (`:25-33`, exit logic `:254-256`). CI runs `STRICT=1` plus
`selftest-callgraph-go.sh` (`.github/workflows/ci.yml:29-35`). The Go selftest asserts a
conditionally-called static callee is demoted (no MUST path, UNKNOWN not UNREACHABLE,
`selftest-callgraph-go.sh:145-158`) and edge-kind integrity (`:159-162`).

## Question 6: Edge kinds, schema, naming, golden

**Finding:**
- Kinds validated in three layers: schema comment + `calls.kind TEXT`
  (`architecture-schema.sql:73-85`); OCaml loader `valid_kinds` (`lib/arch_db/arch_load.ml:31`,
  `:58-67`); Python `arch-load:21,70-73`; arch-query refuses NULL/invalid kinds (`arch-query:92-96`)
  and detects the contract flag (`:66-69`).
- `functions` table: 17 columns incl. `id PK`, `module_id FK`, `name`, `signature`, `line_start`,
  `line_end`, `exposed`, `intent`, comment-quality fields (`architecture-schema.sql:23-45`).
  Main INSERT: `arch_index.ml:166-170`; flat-schema variants `runner.ml:73-76`,
  `arch_load.ml:118`.
- 15 arch-query subcommands read functions/calls (labels at `arch-query:101-361`; notably
  `reaches:106`, `unreachable:130`, `escapes:164`, `dead-code:361`, `stats:188`).
- Golden: `test/fixtures/self-index-stats.txt` = `modules: 18 / functions: 150 / calls: 2809`;
  ADR `docs/adr/001-self-index-golden.md`.

## Question 7-internal: noreturn handling today

**Finding:** **None in the OCaml extractors.** `raise`/`failwith`/`exit` are ordinary `Texp_apply`
calls; code after them is walked at the same depth (`arch_index_cmt.ml:561-609`). `Texp_assert` is
special-cased only for `-noassert` conditionality (`:543-545`), no `assert false` recognition. The
effects extractor has no noreturn concept. On the Go side, panic is modeled *implicitly*: a panic
block is terminal (no successors) and feeds the virtual exit (`main.go:212-214`).

## Question 7-external: synthetic closure-node naming in mature tools

**Finding (full citations in the specialist output, key facts here):** The dominant industry
convention is **parent-qualified ordinal**, not line numbers:

| Ecosystem | Convention | Basis |
|---|---|---|
| Go gc / go/ssa | `main.main.func1` / `parent$N` (AnonFuncs index) | ordinal-per-parent |
| Java javac / Soot / WALA | `lambda$method$N` / thunk classes / `wala/lambda$cls$bootstrapIdx` | ordinal / bootstrap index |
| C++ Itanium/Clang | `main::{lambda()#1}::operator()`; blocks `__f_block_invoke_N` | ordinal-per-context |
| Rust v0 | `foo::{closure#0}` | ordinal-per-parent (legacy `{{closure}}` had none) |
| Python cProfile | `(filename, lineno, <lambda>)` | **line-based** (the one exception) |
| JS/V8 | inferred name or `<anonymous>` @ url:line:col | position-based fallback |
| **OCaml compiler itself** | `camlModule__fun_<stamp>` (Ident stamp, module-wide counter) | **stamp-based — least stable**; practitioners call these frames "opaque" |

OCaml tooling mostly *omits* anonymous functions: merlin's outline drops non-`Tpat_var` items
(`outline.ml` `name_of_patt`); odoc never sees them; Landmarks auto-instruments top-level bindings
only. Parent linkage is universally expressed by embedding the parent name as a prefix.

**Stability note relevant to naming:** ordinal-per-parent renumbers only when sibling lambdas are
added/removed/reordered within the same parent; line-based renames whenever any earlier line in the
file shifts; OCaml's stamp-based renames on nearly any edit to the module.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| `nested` counter demotion | `lib/arch_index/arch_index_cmt.ml` | 436–693 | single source of "conditional?" today |
| kind_hint → kind resolution | `lib/arch_index/arch_index.ml` | 278–352 | only place kind_hint is consumed |
| kind discarded on LSP path | `lib/arch_index/call_graph_extractor.ml` | 231–243 | `call_row` has no kind field |
| post-dominance fixpoint | `callgraph-go/main.go` | 198–264 | reference algorithm, hasExit guard |
| P1/P2 assertion machinery | `selftest-callgraph-soundness.sh` | 183–197 | chk/verdict/refuses, STRICT |
| function row INSERT | `lib/arch_index/arch_index.ml` | 166–170 | module_id FK + 16 params |

## Coverage gaps

- The exact per-construct breakdown of the 2032 recoverable MAY_TOP edges (which fraction sits in
  lambda bodies vs conditional arms) is not statically readable from the code — it requires
  instrumenting an index run.
- Whether arch-query consumers besides `reaches`/`unreachable`/`escapes`/`dead-code`/`stats` make
  assumptions that would break with synthetic function rows (e.g. `exported`, `find`) is knowable
  only by reading each query's WHERE clauses — partially covered by Q6c list; per-query semantics
  not exhaustively traced.
