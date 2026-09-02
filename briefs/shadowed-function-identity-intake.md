# Intake Brief — shadowed-function-identity

**Date:** 2026-09-02
**Status: VALIDATED**
**Type:** fix
**Trust boundary:** no

## Goal

Fix GitHub issue #41 / roadmap item 0.6: a compilation unit that binds the same name twice at the
same level (e.g. two top-level `let f = ...` in one `.ml`) currently produces only **one** row in
`functions`, and **both** bindings' outbound call edges resolve onto that single surviving row.

This is a soundness bug, not merely a lost row: `functions` is written with `INSERT OR REPLACE`
on `UNIQUE(module_id, name)`, so the second definition silently deletes the first (cascading to
every dependent row via `ON DELETE CASCADE`) and takes over its id. Call edges are then resolved
**post-hoc**, after all `.cmt` files are walked and `functions` is fully committed, by a
`(module_path, function_name)`-keyed hashtable (`fn_lookup`) — so both bodies' outbound calls,
recorded as name facts during the walk, land on whichever definition survived the replace. The
survivor is credited with calls it does not make, and nothing in existing reporting surfaces it
(`n_functions` is a plain `COUNT`).

The fix gives shadowed same-level bindings distinct row identities via a `#N` ordinal, mirroring
the ordinal convention `lambda_name` already uses in the same file for synthetic lambda nodes at a
colliding source position — a precedented pattern in this codebase, and (per research) one shared
by several external tools solving the identical problem (OCaml's own compiler diagnostics print
shadowed identifiers as `t/2`; LLVM's `ValueSymbolTable` appends a numeric suffix on collision).

## Scope Boundary

What is explicitly OUT of scope:
- The pre-existing, **already-accepted** cross-module homonym hazard in `bin/arch_query/arch_query.ml`
  (most subcommands resolve by bare `functions.name` with no module qualifier, documented at
  `bin/arch_query/arch_effects_queries.ml:37-58` as a known residual). This task's collision axis
  is same-module, same-level; it must not attempt to fix the cross-module axis, and must not make
  it worse.
- `functions.name`'s uniqueness contract for consumers that already key by `(name, module)` —
  `arch_index_support.ml`'s intent updater, `arch_body_compare`'s dedup sweep — is unaffected by
  this fix and needs no change.
- A durable, cross-loader stable qualified identity (roadmap item 1.6) — this fix is scoped to
  the CMT indexer's own `functions` row identity and its immediate consumers (`fn_lookup`,
  `call_graph_extractor.ml`'s sibling extraction path), not a repo-wide identity overhaul.
- Switching `functions` off `INSERT OR REPLACE` entirely — the issue's own fix direction treats
  the ordinal as the fix; revisiting the REPLACE semantics itself is explicitly named in the issue
  as a larger, alternate direction not being taken here.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml` | Where a value binding is walked and its row is written; where `lambda_name`'s ordinal precedent lives | `lambda_name`: `let base = Printf.sprintf "%s.<fun:%d:%d" (!cur).lcaller line col in let n = (try Hashtbl.find markers base with Not_found -> 0) + 1 in Hashtbl.replace markers base n ; if n = 1 then base ^ ">" else Printf.sprintf "%s#%d>" base n` (`:804-810`) |
| `lib/arch_index/arch_index_cmt.mli` | Public signature for whatever binding-identity mechanism is introduced; consumed by `call_graph_extractor.ml` | current `build_local_fn_stamps : Typedtree.structure -> (string, string * int) Hashtbl.t` |
| `lib/arch_index/arch_index_db.ml` | `insert_function`, the `INSERT OR REPLACE` call site | `insert_function` (`:184-207`) binds and executes the prepared statement built in `arch_index.ml:186-193` |
| `lib/arch_index/arch_index.ml` | `fn_lookup` build and the post-hoc call-edge resolution this fix must interact with correctly | `fn_lookup` keyed by `(mod_path, fn_name)` (`:287-297`); `resolve_local name = Hashtbl.find_opt fn_lookup (call.caller_module, name)` (`:341-342`); `resolve_qualified` (`:355-371`) |
| `lib/arch_index/call_graph_extractor.ml` | Sibling LSP/flat-schema extraction path that also calls `build_local_fn_stamps` — must stay consistent with the main indexer or the two paths name the same shadowed function differently | current call site: `Arch_index_cmt.build_local_fn_stamps structure` inside the per-unit walk |
| `architecture-schema.sql` | `functions` table definition | `UNIQUE(module_id, name)` (`:51`) |
| `tezt/tests/reported_equals_stored.ml` | Existing doc comment already flags this gap by name (from the #37 fix) | `:31-34`: "Nor does this test catch the top-level-shadowing route to the same loss; the statement-failure gate does" |
| `tezt/tests/ocaml_shapes.ml` | Closest existing precedent — toplevel-vs-nested-module homonym, NOT this task's toplevel-vs-toplevel case | `:42-50,208-209,224-234` — asserts one row each, zero cross-attribution, for `shadowed` vs `Shadow.shadowed` |
| `tezt/tests/callgraph_soundness.ml` | Closest existing precedent for stamp-level shadowing (parameter shadows outer `let`), NOT two top-level bindings | `:207-211,277-280` |

## Architecture Notes

**Write-then-resolve pipeline, and why the fix must touch both ends.** All `.cmt` files are
walked and `functions`/`modules`/`types` rows inserted inside one transaction, which is committed
before any call edge is resolved (`arch_index.ml:246-277`). Only then does a fresh transaction
build `fn_lookup` from the now-committed tables and resolve every pending call by name
(`:283-483`). This means: (a) whatever identity a shadowed binding's **row** gets must be decided
during the walk, at write time; (b) whatever identity a shadowed binding's **outbound calls** are
tagged with during the walk must exactly match the row identity chosen in (a), or `fn_lookup`
will resolve the call to nothing (a regression: a previously-MUST edge becomes unresolvable) or to
the wrong row (the original bug, unfixed). Prior investigation (research Q3) confirms `fn_lookup`
performs no ordinal-awareness of its own — whatever key is written for the row is exactly the key
that must be produced for its own outbound calls elsewhere in the same unit.

**A second, sibling consumer of the same pre-pass.** `call_graph_extractor.ml` (a different
extraction path, used by the LSP/flat-schema route) independently calls
`Arch_index_cmt.build_local_fn_stamps` to get the same same-unit function-stamp table the main
indexer's CMT walker builds. Any change to how a shadowed binding is named must be threaded
through this second call site too, or the two paths will disagree on what a shadowed function is
named — which would itself be a new soundness gap between the two producers.

**User-visible naming-contract change.** Before this fix, `arch-query`'s bare-name lookups
(`WHERE name=?`) against a shadowed function resolved to the **last** definition (the only one
`INSERT OR REPLACE` left standing). After this fix, if the first definition keeps the bare name
and only later definitions take an ordinal suffix (mirroring `lambda_name`'s own first-occurrence-
keeps-the-base-name convention), a bare-name query will resolve to the **first** definition
instead. This is a real behavior change for any external consumer relying on "the surviving
definition" semantics, and must be stated explicitly in the impl brief and PR description, not
left implicit.

**Evidence bar, per the roadmap's own soundness gate for this class of item:** build, `dune test
--force`, `arch-rules --on-vacuous fail`, a ratchet check proven red-then-green, and a whole-repo
(or self-index) measurement showing the change moves MUST/MAY_TOP counts in the expected
direction. The roadmap specifically ties this issue's own measured signature — 9629 `type_usage`
FK rejections on an Octez re-index, attributed to this same collision class — as the whole-repo
evidence to watch: a successful fix should measurably reduce that count. Re-running the full Octez
measurement is a large side operation (external checkout, external SSD); the plan phase should
decide whether the self-index-scale measurement is sufficient evidence for this PR, with the
Octez re-measurement as a documented follow-up rather than a blocking requirement, given #41 was
already independently confirmed to be that count's root cause in this session's earlier research
(the divergence between #37's fix — a different bug — and #41's continuing signature was already
established and recorded in the project's own notes prior to this task).

**Prior draft exists.** A substantial, uncommitted draft implementation exists in a worktree
(introduces a `binding_identity`/`build_binding_names` mechanism, threads it through
`build_local_fn_stamps` and the main indexing walk, updates `call_graph_extractor.ml`, and adds a
new test file). It predates ~15 commits of intervening work on `main` (including the #37 fix, the
dropped-node MAY_TOP fix, and the recently-shipped #33/#34/#35 fixes) and has not been re-verified
against current `main`. Treat it as a strong starting point for the plan/implement phases, not as
already-correct — it must be rebased and its correctness re-derived against the current code,
specifically against the two traps named in the issue itself: `fn_lookup` must resolve by the
ordinal-qualified name (not silently continue matching by bare name in a way that reintroduces
wrong-target attribution), and the ratchet must prove "two rows exist AND each keeps its own
edges," not merely "no statement failures" (the latter is already covered by the unrelated,
already-merged `statement_failures` gate from #37).

## Quality Gates

```bash
# Build (project switch is mandatory — the default octez-setup switch produces spurious
# eio/cohttp/mirage-crypto errors unrelated to this codebase)
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build

# Tests (dune test caches aggressively; --force for a real run)
dune test --force

# Format
dune fmt
```

Not documented as a single command, but required by the roadmap's soundness gate for this item
class: `arch-rules --on-vacuous fail` over a self-index, and a whole-repo/self-index measurement
of `MUST`/`MAY_TOP` counts before and after (see Architecture Notes above).

## Open Questions

_(none — the fix direction, the two interaction traps, and the scope boundary against the
cross-module hazard are all resolved above)_
