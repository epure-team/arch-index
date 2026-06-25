# arch-index — LSP-backed call-graph + symbol index for codebase analysis

Cross-campaign, target-agnostic recon tool (rung-0 floor). Extracted from epure's `arch_index`
(epic e63: LSP-generic multi-language backend). Builds a queryable **SQLite call-graph + symbol +
doc-comment index** of any codebase a language server understands — Go (gopls), Rust (rust-analyzer),
TypeScript, Python, OCaml — turning manual recon code-reading into deterministic, *complete* queries.

## Why it exists (security-recon motivation)
Most hunt recon is a **call-graph reachability question** done by hand:
- *Recovery-ceiling*: "is this `panic()` reachable without crossing a `recover` boundary?" →
  `arch-query reaches <recover-fn> <panic-fn>`.
- *Variant analysis*: "unfixed siblings of a fixed call-site" → `callers-of` / `find` on the shape.
- *Attack surface*: exported entrypoints → `exported`; shared sinks → `fan-in`.
- *External/dynamic edges* gopls can't resolve (interfaces, reflection, cgo) → `unresolved`
  (verify these by hand — they are the tool's blind spots).

## Layout
- `bin/arch_index_cli` — the indexer (vendored build; gitignored, machine-specific — see `build.sh`).
- `arch-index` — wrapper: builds an index DB for a project (`arch-index <proj> <out.db> [lang]`).
- `arch-query` — canned call-graph queries over an index DB (`arch-query <db> <subcmd> [args]`).
- `architecture-schema.sql` — the CMT-path schema (reference). LSP output is a `comment_db`:
  `functions(name,file_path,line_start/end,exported,signature,comment_quality_score)` +
  `calls(caller_name,caller_file,callee_name,callee_file,call_site)`.
- `build.sh` — rebuild the binary from an epure checkout (`EPURE_SRC=~/dev/epure ./build.sh`).

## Install LSP backends (per target language)
- Go: `go install golang.org/x/tools/gopls@latest`
- Rust: `rustup component add rust-analyzer`
- TS: `npm i -g typescript-language-server`; OCaml: `opam install ocaml-lsp-server`

## Usage
```sh
# build the index (point Go at the MODULE ROOT — the dir with go.mod)
./arch-index /path/to/repo /tmp/repo-arch.db go
# query it
./arch-query /tmp/repo-arch.db stats
./arch-query /tmp/repo-arch.db exported
./arch-query /tmp/repo-arch.db callers-of SomeFunc
./arch-query /tmp/repo-arch.db reachable-from FinalizeBlock
./arch-query /tmp/repo-arch.db reaches runTx somePanicHelper   # recovery-ceiling test
./arch-query /tmp/repo-arch.db fan-in 25
./arch-query /tmp/repo-arch.db unresolved                       # gopls call-graph blind spots
```

## Edge-kind contract + unreachability (PR-A)

`reaches` proves **reachability** (a positive path = ground truth) but cannot prove **un**reachability —
a resolution-based call-graph is an *under-approximation* that silently omits dynamic/interface/reflection
edges. The edge-kind contract fixes that. A ⊤-marking backend tags every `calls` row:

| `calls.kind` | meaning | use |
|---|---|---|
| `MUST` | uniquely-resolved static call | `reaches` (trust a POSITIVE) |
| `MAY_ENUMERATED` | dynamic call bounded to a candidate set (e.g. all interface implementers) | over-approx closure |
| `MAY_TOP` | unresolvable/dynamic/reflective/FFI call — **could call anything**, never dropped | forces `UNKNOWN` |

…and sets a `callgraph_contract` flag in `comment_db_meta`. Then:

```sh
arch-query db.sqlite reaches      A B   # MUST-only: PATH EXISTS (must-reach) | no MUST path
arch-query db.sqlite unreachable  A B   # REACHABLE | UNREACHABLE | UNKNOWN  (requires ⊤-marking)
arch-query db.sqlite escapes      A     # the MAY_TOP edges reachable from A (why UNKNOWN)
```

`unreachable` returns **UNREACHABLE** only when B is outside the `MUST∪MAY_ENUMERATED` closure of A
*and* no `MAY_TOP` edge is reachable from A (a closed universe) — then the lead **fails G2 by
construction** and can be killed. If A can reach a ⊤ edge → **UNKNOWN** (never kill). **Soundness guard:**
on a legacy / un-⊤-marked DB (no `callgraph_contract` flag), `unreachable`/`escapes` **REFUSE** (exit 3)
rather than give a false-sound answer — because "no path" there may merely hide a dropped dynamic edge.

**Producing a ⊤-marked DB (`arch-load`, PR-B write-side).** A producer emits NDJSON of function + call
records (each call carries a `kind`); `arch-load` builds the DB and is the **enforcement point** — it
sets `callgraph_contract` only after validating every edge's kind, and ABORTS on a missing/invalid
kind (so a ⊤-marked DB is never a lie). stdlib python3, no deps:

```sh
producer ... | arch-load out.db          # NDJSON on stdin (or: arch-load out.db stream.ndjson)
arch-query out.db unreachable A B         # now sound
```
Point `arch-load` at a **fresh** DB path: it owns its three tables (drops + rebuilds them idempotently)
but leaves any foreign tables from an LSP-path index untouched, so reusing an LSP DB path yields a
half-converted DB. A 0-edge load warns (a silently-failed producer would otherwise read as all-UNREACHABLE).
NDJSON: `{"type":"function","name":"f","file_path":"x","exported":true}` and
`{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:12","kind":"MUST|MAY_ENUMERATED|MAY_TOP"}`.
Any Tier-0 (tree-sitter shim) or Tier-1 (Go `go/ssa`+CHA, OCaml typedtree) producer feeds the same loader.
Validate with `./selftest-load.sh` (NDJSON → load → sound query, end-to-end).

The contract + query + loader are language-agnostic (PR-A/B); per-language backends populate `kind` (Tier-0
tree-sitter ⊤-marking universally; Tier-1 precise resolvers per language — Go `go/ssa`+CHA, OCaml
typedtree, …). See `SPEC-sound-callgraph.md`. Validate with `./selftest-contract.sh` (hand-built DBs).
**Honest scope:** this is *soundy*, not sound — macro/`eval`/reflection/FFI/`#cfg` call sites that never
appear in the AST are recorded as `MAY_TOP` anchors, never asserted across.

**Go Tier-1 producer (`arch-callgraph-go`, PR-C).** Uses `go/packages`+`go/ssa`+`go/callgraph/cha` —
no gopls needed, no large-module enumeration bug. Kind assignment:
- `MUST` — static call with a uniquely-resolved callee
- `MAY_ENUMERATED` — interface/func-value call; CHA enumerates all concrete implementers
- `MAY_TOP` — `reflect.Value.Call*`, `plugin.Open`, cgo/external; reclassified even if CHA resolves them statically

```sh
./build.sh go                                         # one-time build (Go 1.21+, no extra deps)
arch-callgraph-go /path/to/go-module | arch-load out.db
arch-query out.db unreachable pkg.EntryFn pkg.SuspectFn
```
Validate with `./selftest-callgraph-go.sh` (builds the producer, runs MUST/MAY_ENUMERATED/MAY_TOP
assertions end-to-end including REACHABLE/UNREACHABLE/UNKNOWN verdicts).

**Known limitations:** Function names use the last import-path component as the package prefix
(`x/keeper` → `keeper.Foo`); two packages with the same last component collide. For whole-module
analysis of a single campaign target this is rarely a problem, but be aware when a module has sibling
packages sharing a short name (e.g. `internal/keeper` + `external/keeper`). The collision direction
is toward false-REACHABLE (safe for G2 kills) not false-UNREACHABLE. `//go:linkname` hidden incoming
edges are not detected (soundiness hole — see `SPEC-sound-callgraph.md` FR-004).

**OCaml Tier-1 producer (`arch-callgraph-ocaml`, PR-D).** Walks `.cmt` typedtree files from
a dune build directory. Kind assignment:
- `MUST` — `Texp_apply(Texp_ident(Pdot...), _)`: globally-qualified static call; OR `Pident` matching
  a top-level locally-defined function in the same module (two-pass: collected before walk)
- `MAY_TOP` — `Texp_apply(fn_expr, _)` where `fn_expr` is NOT a resolvable ident: function parameter,
  lambda-bound variable, closure, `Texp_send` (object method); plus well-known holes: `Obj.magic`,
  `Marshal.from_*`, `Dynlink.loadfile*`, `Callback.register*`
- `MAY_ENUMERATED` — reserved for structural CHA on `Texp_send` (TODO upgrade from MAY_TOP)

```sh
./build.sh ocaml-callgraph                          # one-time build (needs EPURE_SRC + opam)
opam exec -- dune build                             # build your OCaml project to get .cmt files
arch-callgraph-ocaml _build/default | arch-load out.db
arch-query out.db unreachable Mod.entry_fn Mod.suspect
```
Validate with `./selftest-callgraph-ocaml.sh` (builds a controlled module via dune, asserts
MUST/MAY_TOP edge kinds, and all three verdicts REACHABLE/UNREACHABLE/UNKNOWN).

**Known limitations:** Only top-level `let` bindings are emitted as function records (nested `let`
inside functions become callee stubs). Function parameters used as callees are MAY_TOP (correct —
they're not statically resolvable). `Texp_send` (object methods) is MAY_TOP pending structural CHA.

## bounty-recon integration (intended)
`bounty-recon` builds the index once per campaign (cartography is recon's job); `bounty-hunt` /
`bounty-variants` query it instead of (or to focus) agent code-reading. The `reaches` / `reachable-from`
queries make recovery-ceiling and goroutine-escape analysis deterministic; `fan-in` / `exported` rank
attack surface; `find` + `callers-of` drive variant-sibling enumeration.

## Status / honest caveats
- **Query layer: validated** (recursive-CTE reachability + path-exists confirmed against the schema).
- **Binary runs; multi-language via LSP** (auto-detects language from `go.mod`/`Cargo.toml`/etc.).
- **KNOWN INTEGRATION ITEM (Go, large modules):** on a large single-module Go tree (e.g. sei-chain),
  `gopls` `workspace/symbol` returned 0 functions in testing — the LSP extractor likely queries before
  gopls finishes indexing, or needs a non-empty-query / documentSymbol-per-file warm-up. Point at the
  module root and, if still empty, the warm-up/timeout in the binary needs tuning (epure src
  `lsp_extractor.ml` / `runner.ml`). Validated structurally on small inputs; **large-Go population is
  the open toolsmith iteration** before this is load-bearing on sei/cosmos.
- **Call graph is LSP-resolution-bound**, not a sound over-approximation: dynamic dispatch, interface
  methods, reflection, and cgo edges may be missing. Use `unresolved` to see edges that didn't resolve;
  never treat "no path" as a soundness guarantee without manual confirmation.
- Binary is dynamically linked / machine-specific — rebuild with `build.sh` on a new host. A clean
  standalone opam-lib extraction (epic e63 #419) would remove the epure-checkout dependency.
