# Task — exn-raise-sets

Implement roadmap item 3.4 (OCaml error-handling) as a strengthened, exception-identity-aware
version — a Java-"throws"-style per-function may-raise set with honest ⊤ marking. For each OCaml
function node (top-level bindings AND the promoted lambda nodes, same attribution as calls),
record the exceptions it may raise with resolved identity, then compute transitively through the
existing `calls` edges at query time (union along MUST/MAY_ENUMERATED, ⊤ along MAY_TOP /
NULL-callee-in-index / unknown).

## Working directory and constraints

- Worktree: `/tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn`,
  branch `feat/exn-raise-sets` off `origin/main` `69e5c3d`. All briefs/ and code go there — never
  in `/home/mathias/dev/arch-index` (pre-existing dirty files `lib/arch_index/runner.ml`,
  `tezt/tests/main.ml` must not be touched).
- Build/test under `eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"`;
  `dune test --force`.
- Autonomous: ask only critical questions with no answer in the code, the roadmap
  (`~/notes/2026-09-01-arch-index-roadmap.md` items 3.4, 3.7, 1.4) or this record.
- Agreed with the parallel "arch-index roadmap handler" session (working `fix/schema-versioning`,
  touching only `arch_index_db.ml/.mli`, `arch_index.mli`, `runner.ml` schema_version sites,
  `lib/arch_index/dune`): new walker logic in NEW file `lib/arch_index/arch_index_exn.ml` (+ .mli)
  with minimal hooks in `arch_index_cmt.ml`; new additive table via `IF NOT EXISTS`; do NOT touch
  `schema_version` — after their PR merges, bump `Arch_index_db.current_schema_version` to "1.3"
  and add a `docs/schema-versions.md` entry (follow-up recorded in the ship gate).

## Producer facts (OCaml 5.3.0 Typedtree, verified this session)

- Raise sites: saturated `Texp_apply` whose head Path is persistent `Stdlib.raise`/`raise_notrace`
  (arg `Texp_construct (_, {cstr_tag = Cstr_extension (path, _); _}, _)` → resolved exception
  Path; arg a variable bound by an enclosing handler → forward the caught set; otherwise ⊤
  "unknown exn value"), `Stdlib.failwith` → `Failure`, `Stdlib.invalid_arg` → `Invalid_argument`,
  `Stdlib.exit` → not an exception. `Texp_assert (e, _)` → `Assert_failure`.
  `Texp_match`/`Tfunction_cases` with `partial = Partial` → `Match_failure`.
  `Texp_letexception` local exceptions. Existing recognizer `noreturn_head`
  (`lib/arch_index/arch_index_cmt.ml:979`, Path-based, shadow-proof) is the template.
- Handlers: `Texp_try (body, val_cases, eff_cases)` — `Tpat_construct` (resolved constructor) →
  caught set; `Tpat_any`/`Tpat_var` → catch-all; `Tpat_or` → union; guarded arm does NOT count as
  catching. `Texp_match (scrut, comp_cases, val_cases, partial)` with `Tpat_exception` catches
  exceptions raised BY THE SCRUTINEE only. Lexical nesting decides escape; a nested lambda
  literal's raises belong to the lambda node.
- Declarations: `Tstr_exception` / `Tstr_typext` — optional entities for v1.
- The CFG walker `collect_calls_from_expr` (`arch_index_cmt.ml` ~:792-1498) already promotes
  nested `Texp_function` literals to lambda nodes (~:1054-1080, per-node `lctx.lcaller`), handles
  `Texp_try` (~:1171), `Texp_assert` (~:1231), `Texp_match` (~:1149), `Texp_apply` head
  recognition (~:1267-1392). `process_cmt` (~:1510) inserts each function row then calls
  `collect_calls_from_expr` and inserts lambda rows AFTER (~:1893-1932).
- The `divergence-reachability` branch (`f9b5fbc`, worktree
  `/mnt/ssd-external-2to/arch-index-wt-divergence`) added a form-level-only `divergence_sites`
  `(kind, call_site)` third return value persisted immediately with `function_id` — mirror the
  shape, with identity + escape flag.
- Both-schemas rule: Flat schema / NDJSON producers (`lib/arch_db/arch_load.ml`) must read
  NOT_ANALYSED, never an empty set presented as "raises nothing".

## HARD REQUIREMENT (user, 2026-09-03): handler-aware propagation at CALL sites

Propagation must subtract exceptions caught by handlers enclosing the **call site**, not only
handlers enclosing raise sites. `let g () = try f () with Not_found -> 0` gives
`raises(g) = raises(f) − {Not_found}`. Rules:

- Each call edge must carry the innermost enclosing try-scope of its own function node (scope
  chain for nested tries); each scope carries its caught set: resolved constructor paths, or
  catch-all (`_`, a variable, unguarded), with guarded arms not counting. Column-level, decided
  during the walk — `call_site` is `file:line` only, and `try f () with E -> g ()` puts `g ()`
  in the handler on the same line.
- A catch-all scope closes everything crossing it, including ⊤ from a MAY_TOP/external edge,
  unless the handler re-raises the bound variable (then the caught set is forwarded).
- `match f () with exception E -> …` covers only the scrutinee `f ()`.
- Transitive rule: `raises(n) = direct_escapes(n) ∪ ⋃_{edge n→m in scope s} (raises(m) −
  caught(chain(s)))`, ⊤ propagated unless a catch-all covers the edge; fixpoint over recursion.
- Data model consequence: `pending_call`/`calls` need a scope reference (new nullable column or
  a side table keyed by call id), and the sites table needs scope rows with `parent` links.
  Both are additive.

## HARD REQUIREMENT (user, 2026-09-03): validate on complex real code — Tezos `proto_alpha`

Fixture-scale tests are necessary, not sufficient (roadmap operating rule). The analysis MUST be
run and measured on `src/proto_alpha/lib_protocol` of the Tezos checkout at
`/home/mathias/dev/tezos/tezos` (HEAD `1727d7e192f`, already built: `.cmt` files under
`_build/default/src/proto_alpha/lib_protocol/.*objs/`). It is large but compiled as a sealed
unit behind the protocol environment (closed world — roadmap 3.7 / ambition F), so the ⊤ share
of raise-sets there is a meaningful number. Evidence to produce and record in the ship gate:
number of function nodes, share with a fully-resolved (non-⊤) raise-set, top ⊤ reasons, and a
handful of spot-checked functions (e.g. a storage accessor known to raise, a `try ... with`
wrapper known to close it) verified by hand against the source. Any Octez-scale DB goes on
`/mnt/ssd-external-2to/arch-index-runs/`, never under `/home` (roadmap rule). Whole-Octez is
optional; `proto_alpha` is the required corpus.

## Deliverables

- Producer: `error_sites`-style table (proposed `error_sites(function_id, kind ∈ {origin,
  handler}, form, exn_path TEXT NULL, escapes BOOLEAN, line, col?)`), rows per node.
- Query: `arch-query raises <fn>` — transitive may-raise set with provenance (direct | via
  <callee>) and ⊤ reasons (MAY_TOP edge / unknown exn value / external callee not in index).
  Optional `raisers-of <Exn>`. Stdlib/external callees ⊤ except a small hand table (v1).
- tezt test (red-then-green), registered in `tezt/tests/main.ml`; self-index golden
  `test/fixtures/self-index-stats.txt` regenerated per `docs/adr/001-self-index-golden.md`.
- Docs: roadmap 3.4 implementer notes + claim line under "In-flight branches and worktrees";
  residuals documented (unknown exn value, HOF callbacks/functor params ⊤ until 3.7, stdlib
  summaries, effects `perform` out of scope) in `docs/edge-kind-contract.md` or a new
  `docs/exception-raise-sets.md`.
- Soundness evidence gate: build, `dune test --force`, red-then-green test, whole-repo
  self-index measurement of the ⊤ share of raise-sets.
