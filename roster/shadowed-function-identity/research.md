# Research — shadowed-function-identity

_Generated: 2026-09-02_
_Mode: full_
_Online research: enabled_

## Question 1: Where in lib/arch_index/arch_index_cmt.ml is the `functions` table populated during compilation-unit traversal, and what SQL statement and UNIQUE constraint govern how a binding is inserted when its (module_id, name) key already exists?

**Finding:** The `functions` table is populated via `Arch_index_db.insert_function`, called from `arch_index_cmt.ml` during the value-binding traversal. The insert statement is `INSERT OR REPLACE INTO functions (module_id, name, signature, line_start, line_end, exposed, intent, comment_quality_score, has_pre, has_post, has_violators, has_violates, violators_raw, violates_raw, tests_raw, quint_raw, mutation_sites, deref_sites) VALUES (...)`, and `architecture-schema.sql` declares `UNIQUE(module_id, name)` on the table. Because the statement is `OR REPLACE`, a second insert sharing a `(module_id, name)` key deletes the first row (`ON DELETE CASCADE` on every FK referencing `functions.id`) and inserts a fresh row with a new id — this is the mechanism issue #41 is about.

**References:**
- `lib/arch_index/arch_index_cmt.ml:1636` — call to `insert_function` during value-binding traversal.
- `lib/arch_index/arch_index_cmt.ml:1595-1608` — comment already documenting the UNIQUE(module_id, name) constraint and a related wildcard-binding (`"_"`) re-insertion hazard from the same mechanism.
- `lib/arch_index/arch_index_db.ml:184-207` — `insert_function`: binds parameters and executes the prepared statement.
- `lib/arch_index/arch_index.ml:186-193` — the prepared `INSERT OR REPLACE INTO functions (...)` statement text.
- `architecture-schema.sql:51` — `UNIQUE(module_id, name)`.

---

## Question 2: Where and how does `lambda_name` construct ordinal-based synthetic identities for anonymous/lambda nodes, and what naming pattern does it produce?

**Finding:** `lambda_name` is a local closure in the CMT walker that names each anonymous function literal (`Texp_function`) it encounters. It builds a base string from the *current caller's* node name plus the literal's 1-based source line/column (`"<caller>.<fun:LINE:COL"`), then disambiguates same-position collisions (arising from ghost/PPX-generated locations sharing a position) via a `markers` hashtable keyed on that base string: the first occurrence closes the name with `">"` (no ordinal); each subsequent collision at the same base appends `"#N>"`, where N is a running per-base occurrence count.

Pattern produced: `"<caller>.<fun:LINE:COL>"` for the first lambda at a given caller+position; `"<caller>.<fun:LINE:COL#2>"`, `"#3>"`, etc. for collisions. Nested lambdas chain through the caller name recursively.

**References:**
- `lib/arch_index/arch_index_cmt.ml:801-811` — `lambda_name` definition: `base = "%s.<fun:%d:%d" (!cur).lcaller line col`, `markers` lookup/increment, `base ^ ">"` on first occurrence, `Printf.sprintf "%s#%d>" base n` on collision.
- `lib/arch_index/arch_index_cmt.ml:986-1013` — call site in the `Texp_function` case: `lambda_name expr.exp_loc` is recorded into `lam_names`, pushed onto `lambdas` with line range/arity, and a fresh context `new_ctx name` is entered for the lambda's own body.

---

## Question 3: How does `fn_lookup` in lib/arch_index/arch_index.ml resolve call edges to function rows post-hoc, what key(s) does it use, and at what point relative to `functions` table population?

**Finding:** `fn_lookup` is an in-memory `Hashtbl` built by a `SELECT` over the already-committed `functions`/`modules` tables, keyed by the pair `(module_path, function_name)`. It is a pure post-hoc resolver: pending call edges recorded during CMT walking (as `Head_local`/`Head_qualified`/`Head_enumerated` facts referencing *names*, not ids) are matched against this table to obtain the callee's row id before `calls` rows are inserted.

Pipeline order: (1) all `.cmt` files are walked inside one transaction, inserting `functions`/`modules`/`types` rows and collecting pending-call lists (`arch_index.ml:246-276`); (2) that transaction is **committed** (`:277`); (3) only then is a new transaction opened (`:283`) and `fn_lookup` populated from the now-fully-committed tables (`:287-297`); (4) pending calls are resolved against `fn_lookup` and inserted into `calls` (`:319-483`), committed at `:495`. Resolution happens strictly after `functions` is fully populated for the entire run.

Keys used: build — `Hashtbl.replace fn_lookup (mod_path, fn_name) fn_id` (`:295`); caller lookup — `(call.caller_module, call.caller_name)` (`:322`); same-module callee lookup (`resolve_local`) — `(call.caller_module, name)` (`:341-342`); cross-module callee lookup (`resolve_qualified`), tried most- to least-qualified — `(mod_path, qualified_name)` (`:366`).

**References:**
- `lib/arch_index/arch_index.ml:246-277` — CMT scan loop, transaction commit.
- `lib/arch_index/arch_index.ml:283-297` — `fn_lookup` build.
- `lib/arch_index/arch_index.ml:319-483` — pending-call resolution and `calls` insertion.

---

## Question 4: What other modules or files depend on the `functions` table's (module_id, name) uniqueness assumption, and how do they consume function identity/names?

**Finding:** Multiple consumers depend on `(module_id, name)` identity:

1. **Call graph resolution** (`arch_index.ml:287-297`) — `fn_lookup`, keyed by `(mod_path, fn_name)`, assumes exactly one row per key (see Q3).
2. **Intent preservation across re-indexing** (`arch_index_support.ml:92-115`) — `UPDATE functions SET intent = ? WHERE name = ? AND module_id = (SELECT id FROM modules WHERE path = ?)`.
3. **Graph construction for `arch_tools`** (`lib/arch_tools/arch_graph.ml:1-12`) — explicitly documents that keying by bare name "silently merges same-named functions from different modules and inflates every closure," and keys nodes by `(module_id, name)`/row id instead.
4. **Dead-code tracking** and **type-usage tracking** (`architecture-schema.sql:144-152`, `:242-248`) — both FK to `functions.id`, so they inherit whatever row identity `functions` assigns.

**References:**
- `lib/arch_index/arch_index.ml:287-297`, `:355-371` — `fn_lookup` build and `resolve_qualified`.
- `lib/arch_index/arch_index_support.ml:92-115` — intent UPDATE keyed by `(name, module_id)`.
- `lib/arch_tools/arch_graph.ml:1-12`, `:55-56` — module doc on why per-module keying matters; node loading query.
- `architecture-schema.sql:105-113`, `:144-152`, `:242-248` — `calls`, `type_usage`, `dead_code_sites`, all FK'd to `functions.id`.

---

## Question 5: What existing tests exercise same-name bindings, shadowing, or duplicate-name scenarios in a single module, and what do they currently assert about row count or call-edge attribution?

**Finding:** Several existing tests cover *adjacent* but not identical territory to issue #41. None exercises two **top-level, same-module** bindings sharing one name — the exact shape #41 describes.

- `tezt/tests/callgraph_soundness.ml:207-211,277-280` — a *parameter* shadowing an outer `let` of the same name (`shadow_bind`); asserts the rebound name (a fresh `Ident` stamp) prevents a MUST edge to the shadowed outer binding. This is stamp-level shadowing within one function body, not two top-level definitions.
- `tezt/tests/ocaml_shapes.ml:42-50,208-209,224-234` — a toplevel `shadowed` function versus a **nested-module** `Shadow.shadowed` function (different qualified paths); asserts exactly one row each and zero cross-attribution. This is toplevel-vs-nested homonymy, not two toplevel bindings at the same level.
- `tezt/tests/coverage.ml:271-326` (`register_ambiguity`) — two functions named `dup` in **different modules**; asserts the ambiguous name is reported and excluded from attribution. Cross-module, not same-module.
- `tezt/tests/reported_equals_stored.ml:54-104` — wildcard (`"_"`) bindings are dropped, not recorded as functions; a related but distinct hazard from the same `INSERT OR REPLACE` mechanism (already fixed, per prior session context).
- `tezt/tests/insert_rowid_attribution.ml:22-98` — a rejected `functions` insert (FK violation) does not leak its dependent rows onto an unrelated neighbor. Different failure mode (rejection, not shadowing-triggered replace).
- `tezt/tests/callgraph_ocaml.ml:118-184` — a function *parameter* shadows a top-level function of the same name; asserts no forged MUST edge. Parameter-vs-toplevel, not toplevel-vs-toplevel.

**References:** as listed inline above, each with the specific line ranges.

---

## Question 6: What downstream consumers query the `functions` table by bare name, and what contract exists today on uniqueness/meaning of `name`?

**Finding:** `bin/arch_query/arch_query.ml` resolves most subcommands' input/seed by **bare** `functions.name`, with no module qualifier: `known`/`need_known`, `reachable-from`, `reaches`, `unreachable`, `escapes`, `unresolved`, `find`, and `exported` all filter or seed via `WHERE name=?` (or a `WITH RECURSIVE` seeded the same way). If more than one row shares a bare name, these queries silently union reachability from all of them as if they were one entity.

This is a **documented, already-accepted** hazard, distinct from #41: `bin/arch_query/arch_effects_queries.ml:37-58` states outright that "a name is unique only within its module, and a name-keyed closure also conflates homonyms," and that module switched its own effects propagation to id-keyed joins specifically to avoid it — implying the *other* `arch_query.ml` commands retain the hazard as a known residual for cross-module homonyms. `arch_body_compare` and its tests treat cross-module name reuse as an expected case to search for, not a bug. `arch_index_support.ml`'s intent updater keys by `(name, module_id)` when single-row correctness actually matters.

**Consequence for this task:** #41 is a same-*module* collision (two bindings, one module), which is a different axis from this already-accepted cross-module hazard. A fix must not conflate the two: giving shadowed same-module bindings distinct row names (e.g. `f`, `f#2`) does not touch the cross-module case at all, and should not attempt to.

**References:**
- `bin/arch_query/arch_query.ml:138,142,230-232,251-253,280-283,323,345,348` — bare-`name=?` queries across multiple subcommands.
- `bin/arch_query/arch_effects_queries.ml:37-58` — explicit documentation of the accepted cross-module hazard.
- `bin/arch_body_compare/arch_body_compare.ml:82` — `GROUP BY name HAVING count(*) > 1` as the duplicate-candidate signal (cross-module by design).
- `tezt/tests/duplicates.ml:19-27,47-51` — fixture with two same-named rows in different modules, used as valid test data.
- `lib/arch_index/arch_index_support.ml:68,95` — intent read/write keyed by `(name, module)`.

---

## Question 7 [ecosystem]: How do other static-analysis or call-graph tools represent multiple same-named bindings/shadowed definitions within one scope, and what identifier scheme do they use to keep them distinct?

**Finding:** There is no single dominant convention across the tools surveyed, and several widely-used real-world tools have documented, sometimes-unfixed bugs in exactly this area. Three broad approaches recur:

1. **Opaque unique IDs/stamps attached to each binding, independent of textual name** — OCaml's own `Ident.t` (`name` + integer `stamp`), LLVM's SSA value symbol table, rust-clippy's `HirId`-based shadow lint (scans "same-named bindings, most recently seen first," identified by `HirId` rather than name).
2. **Hierarchical/scoped-path signatures folding enclosing scope into the identifier** — Kythe's `VName{signature, corpus, root, path, language}` (the `signature` field is explicitly documented as opaque and indexer-defined, "permitted to encode ... arbitrarily ... including via one-way hashes"); SCIP's dedicated `local <local-id>` namespace, scoped to be unique only within one document, plus a `disambiguator` field for global symbols.
3. **AST/pointer or source-span identity instead of any serialized textual ID** — Swift/SourceKit's editor tooling bypasses Clang's USR for exactly this reason; GHC's `.hie` files key identifier information by `SrcSpan` rather than by any synthesized shadow-aware name.

Critically, several of these schemes are documented as **not actually solving** the problem in practice: Clang's USR is explicitly reported non-unique for two same-named shadowed locals in different scopes within one file (Swift Forums thread, bug SR-7205) — Apple's own tooling avoids USR for this reason and falls back to AST/Decl-pointer identity instead, which "only works because it is limited to a single file." OCaml's own `Ident.rename` stamp-freshness guarantee is separately documented as violated **across module-compilation boundaries** (ocaml/ocaml#13036, closed not-planned) — each module's stamp generator resets, so stamps collide between identifiers from different modules even though within one module they are fresh. OCaml's own compiler diagnostics, however, already use a directly analogous convention to the one under consideration here: shadowed same-named identifiers are printed with a synthetic suffix like `t/2` ("the n-th most recent identifier `t` in scope"), and error-message code has an explicit shadower/shadowed index convention (0/1) for pretty-printing two same-named items. LLVM's `ValueSymbolTable` uses a comparable renames-on-insert scheme, appending a numeric suffix on collision (e.g. `_Z1fv` vs `_Z1fv.1`).

**Contradictions flagged:** Kythe's and SCIP's own specs leave shadow disambiguation as an implementation detail delegated to the indexer, not a mandated rule — despite an intuitive expectation that a mature graph standard would prescribe one. Clang's USR is documented as intended to "uniquely identify a symbol... across all translation units" yet is concretely acknowledged non-unique for shadowed locals, a direct contradiction between stated intent and observed behavior that the tool's own maintainers have not resolved.

**References:**
- https://github.com/sourcegraph/scip/blob/main/scip.proto and /docs/scip.md — SCIP symbol grammar, `local <local-id>` namespace, `disambiguator` field, `IdentifierShadowed` syntax kind.
- https://kythe.io/docs/schema/ and /docs/kythe-uri-spec.html — Kythe VName five-tuple, opaque `signature` field.
- https://github.com/ocaml/ocaml/issues/13036 — "Stamps of identifiers are not unique" (cross-module stamp collision, closed not-planned).
- https://github.com/ocaml/ocaml/pull/11910 — "simpler names for shadowed identifiers": the `t/2` diagnostic suffix and shadower/shadowed index convention.
- https://forums.swift.org/t/unified-symbol-resolution-giving-non-unique-resolution-of-variables/10812 — Clang USR non-uniqueness for shadowed locals (bug SR-7205); Apple's AST-pointer-identity workaround.
- https://llvm.org/doxygen/classllvm_1_1ValueSymbolTable.html — `ValueSymbolTable`/`makeUniqueName` renames-on-insert.
- https://github.com/rust-lang/rust-clippy/blob/master/clippy_lints/src/shadow.rs — `HirId`-based shadow scan.
- https://www.haskell.org/ghc/blog/20190626-HIEFiles.html — GHC `.hie` files keyed by `SrcSpan`.
- https://codeql.github.com/query-help/csharp/cs-local-shadows-member/ — CodeQL shadowing-detection query (underlying dbscheme mechanics not publicly documented).
- https://glean.software/docs/schema/basic/ — Glean predicate/key-uniqueness model (no explicit shadowing convention found).

**Relevance to this repo, stated factually:** the project's own `lambda_name` (Q2) already implements the "opaque-ordinal-suffix-on-collision" approach — the same shape OCaml's own diagnostics (`t/2`) and LLVM's `ValueSymbolTable` (`.1` suffix) use for the identical problem. This is a precedented pattern, not a novel one, and one instance of it already exists in this codebase for a structurally identical collision (synthetic lambda nodes at the same source position).
