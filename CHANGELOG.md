# Changelog

## [Unreleased]

### Added
- `arch-impact`: per-diff change-impact briefing over the sound call graph — touched functions,
  affected exported API, blast radius, ⊤ frontier, reaching tests, effects crossed, and findings
  on touched lines. Text / Markdown / JSON output. `--fail-on-new-findings` implements the R5
  ratchet and is off by default.
- NDJSON contract: optional `line_start` / `line_end` on `function` records, so a diff hunk maps
  to a function on the flat schema too. A **half** span aborts the load — it would mis-map every
  hunk, which is worse than no span.
- `arch-callgraph-go` emits source spans for every function that has syntax. Synthetic functions
  (wrappers, thunks, `init`) carry none by design.
- `arch-rules`: architecture fitness functions over the sound graph — layering, export-surface,
  effect and declared-dependency rules. Four verdicts (`VIOLATION` / `POSSIBLE` / `UNKNOWN` /
  `PASS`) instead of the pass-fail every declared-import checker reports; `PASS` is refused on an
  index that is not ⊤-marked, and a rule matching no code fails as VACUOUS.
- `arch-rules.txt`: arch-index's own layering rules, checked in CI.
- `lib/arch_tools`: the read model shared by every tool — schema detection, the graph (keyed
  by row id on the main schema, by name on the flat one), selectors, path resolution, the LCOV
  reader, the diff reader, and the sqlite3-compatible output formatter — so no two tools can
  drift on how the graph is keyed or which edges are in a closure. On Caqti, so a query's
  parameter arity and row shape are checked by the compiler.
- `arch-mutants`: mutation testing targeted by the call graph. `plan` decides what is worth
  mutating (test-reachable code, with the tests that must rerun for each target) and partitions
  every indexed function into exactly one bucket with a reconciliation count; `report` attributes
  each surviving mutant to the innermost enclosing function and the tests that failed to kill it.
  Generic NDJSON input plus a Mutaml adapter. No mutation engine of its own, and deliberately no
  mutation score.
- `arch-coverage`: reachability-weighted coverage from an LCOV tracefile — API-relative
  never-exercised functions, covered-but-only-⊤-reachable functions, and (with `--mutants`) the
  covered-yet-unkilled pairing that replaces a coverage percentage. `--write` finally populates
  the `coverage` table. LCOV in, so every ecosystem is covered by one parser.
- `arch_mcp`: an MCP server (stdio JSON-RPC) built on mcp-kit, exposing reachability, escapes,
  findings, change impact, architecture rules and the mutation plan to agents. Every result
  carries a `provenance` block — contract stamps, producing backend, and whether a negative is
  evidence at all. It SHELLS OUT to the command-line tools rather than reimplementing any
  verdict, so an agent and a reviewer cannot be told different things. Marked `(optional)` in
  dune because mcp-kit is not on opam yet; a dedicated `mcp` CI job pins it and asserts the
  binary was actually built rather than silently skipped.
- `selftest-impact.sh`, `selftest-rules.sh`, `selftest-mutants.sh`, `selftest-coverage.sh` and
  `selftest-mcp.sh`, wired into CI.
- `arch-impact --format json` / `arch-rules --format json`: a strict machine-output contract —
  `computed`, `contract_ok` and `verdict` fields that restate the exit-code decision for a
  stdout-only consumer (workflow gates, agents), int-only counts (`new_findings` on `arch-impact`;
  `failing`/`unknown`/`vacuous`/`not_computed` on `arch-rules`), and `findings.computed`/`reason`
  so an absent decision analysis is stated, not implied by a missing key. No floats, no `Intlit`,
  exactly one JSON object on stdout. Exit codes and text/md output are unchanged.

- `arch-serve`: the read-only HTTP browser over a flat index. A MAIN-schema index is declined at
  startup with exit 2 naming the schema, rather than reaching the first query and surfacing a raw
  `Sqlite3.Error` — that shape is not read yet, and saying so is the honest answer.

### Fixed
- **A qualified call could bind to a same-named module in another library.** The resolver mapped a
  reference's module component to a source path through a table keyed by capitalised basename and
  built with `Hashtbl.replace` — one path per basename, last writer wins, silently. Two libraries
  each containing `api.ml` collapsed to one entry, so every qualified reference to `Api` resolved
  to whichever was scanned last. That is not a missing edge but a **MUST edge pointing at the wrong
  function**: reachability forged toward the survivor, lost from every loser, and the verdict still
  reading `sound`.

  The resolver now collects every module sharing the basename that actually DEFINES the name and
  binds the reference to that whole **candidate set** — one `MAY_ENUMERATED` edge per candidate,
  the contract's own word for a bounded candidate set, never one arbitrary member and never `MUST`.
  `reaches` walks MUST edges only, so a candidate set can never forge a must-path, while
  `unreachable`/`escapes`/`arch-rules` traverse all of them and stay correct. Most references are
  not ambiguous at all: two libraries with an `api.ml` where only one defines `run` leave exactly
  one candidate and resolve to `MUST` as before.

  Two other answers were tried and both were worse than the bug. **Refusing** to bind produces a
  row that is encoded bit-for-bit like an external leaf (`kind = MUST`, `callee_id = NULL`), so
  `arch-rules` answered `pass` ("proved unreachable in a closed universe") and `unreachable`
  answered `sound` on a fixture whose caller literally calls the other library. **Narrowing by
  directory segment** — reading `Sublib` in `Sublib.Api.run` as the directory `sublib/` — then
  binding the survivor as `MUST` looked like free precision, and is not: dune laying a library out
  under a directory of its name is a convention, not a guarantee, and a library `q` in `alt/` beside
  a library `qq` in `q/` makes the filter elect the wrong library and stamp it `MUST`. That is the
  original defect re-created by its own fix, so no directory heuristic ships. The cost is real and
  paid deliberately: in the common layout where the convention holds, a cross-library call that
  could have been proved is now only enumerated.

  The same collapse existed **three** times in one function — calls, module dependencies, and type
  usages — and the module-dependency copy kept the refusal for a round after the call path had
  dropped it. Calls and deps now enumerate; a type usage has a single FK and no enumerated kind, so
  an ambiguous one stays NULL (under-approximate, and `type_usage` feeds no soundness closure).

  Ambiguity here is a permanent state, not scaffolding: two `(wrapped false)` libraries, or two
  vendored copies of one library, are ambiguous at the compilation-unit level too. Resolving by
  unit identity (dune's `Rootlib__Api`) would collapse most sets to one member and recover the
  precision given up above; it needs the alias tables from the wrapper modules and is a separate
  change.
- **`arch-query effects-of`, `mutators-of` and `pure-fns` stopped at every module boundary too** —
  same root cause as `dead-code` below. On a two-module fixture where the mutation lives one module
  away from its caller: `effects-of` returned NOTHING, `mutators-of` lost the transitive caller,
  and `pure-fns` reported the caller as **pure** while it reaches a `Hashtbl.replace`. That last
  one is a claim consumers act on.

  The first fix moved only the join to `calls.callee_id` and left the recursion SET keyed by name
  — which made the closures cross module boundaries and then conflate homonyms on arrival:
  calling the pure namesake of a mutator read as reaching the mutation. An adversarial review
  proved it before it shipped anywhere. Both the join and the set are ids now. The endpoints
  touching `function_effects` cannot be id-keyed (that table has only `function_name, file_path`),
  so seeds and projections narrow same-named candidates by module path — and the first version of
  THAT narrowing was broken twice over, caught by a further review round before shipping: it
  compared paths with LIKE, where `_` in a filename matches `/` (so `foo_bar.ml` claimed an
  effect recorded in `foo/bar.ml`), and a basename-only match could suppress the fallback and
  DROP the true mutator entirely — an under-report, the one direction worse than conflation.
  The comparison is now substr arithmetic (no wildcards), prefers the longest matching path, keeps
  all same-named candidates when nothing matches, and effect rows with no `functions` row at all
  are listed as direct mutators instead of vanishing through the id join. `pure-fns` deliberately
  skips the narrowing — over-seeding withholds purity claims (for the namesake and its whole
  caller cone) rather than forging one, the only safe direction for that verdict. Residual,
  documented in the code: when extractor and indexer disagree about the source-relative root, a
  basename collision can still hand the row to the wrong homonym; the cure is resolving effects
  to ids at load time.
- **`arch-query dead-code` could still report the whole index as dead through its DEFAULT
  invocation.** The unmatched-root guard checked the name list, but the failure lives in the root
  SET: bare `dead-code` on an index where nothing is exported (a library with no `.mli`, a Go
  package with only lowercase names) rooted at nothing, reported every function dead, exited 0 —
  and stamped the report with the strongest soundness the index supports, since an empty reach
  cone touches no degrading edge. An empty root set now refuses with exit 2, as does `--roots`
  with a missing or empty value. On the flat schema both the guard and the root lookup now use
  functions ∪ callers — a legitimate root without a `functions` row was being refused, the exact
  mistake `arch-query`'s `known` had already documented and fixed. NOT callees: a first version
  included them, and a review showed `--roots '*TOP*'` or `--roots fmt.Println` then rooted at a
  leaf with no outgoing edges — every function dead, exit 0, stamped sound — resurrecting the
  precise report the guard exists to refuse.
- **`dead-code`'s `sound` verdict ignored unresolved callees.** "Unresolved" does not mean
  "outside the index", and the two shapes it covers land in different branches: module aliases
  are demoted to MAY_TOP by the CMT producer (observed, not assumed) and were already caught by
  the ⊤ degradation; qualified heads the resolver cannot place — `Stdlib.+`, cross-library names
  — carry MUST/MAY_ENUMERATED, the ⊤ branch never fires on them, and the callee may perfectly
  well be an indexed function. The verdict now degrades to
  `candidate (unresolved callees in the cone — the reach set is a lower bound)` for those. Stated
  cost: any cone that calls the stdlib degrades; `sound` remains reachable exactly for cones
  whose every edge resolves, and the corpus pins both directions.
- **`arch-query dead-code` stopped at every module boundary on the MAIN schema.** The reachability
  closure walked callee NAMES: a caller records its callee as dune spells it
  (`Arch_index__.Lsp_client.start`) while that function's own `functions.name` is `start`, so the
  chain broke at each cross-module call and everything reachable only across one was reported
  deletable. `calls.callee_id` already held the correct resolution — the query was not using it.
  The closure now walks ids on the main schema (the flat schema keeps names, where the name is
  the key). Walking names also *invented* edges through homonyms, since distinct functions
  sharing a short name in different modules were conflated; both directions are fixed. Found by
  running arch-index on its own test suite, which reported 129 of its own shared helpers dead;
  it now reports 3, all of them `let`-bound constants that are referenced but never applied.
- **`arch-query dead-code --roots` reported the entire index as dead.** The flag its own usage
  documents was never parsed: the raw argument became the roots list, so `--roots entry` searched
  for a function literally named `--roots`, matched nothing, and left the reachable set empty —
  every function in the index came back as deletable, for anyone following the documented
  interface. Both `--roots X` and `--roots=X` are parsed now (the bare positional form still
  works), and a root matching no function is refused with exit 2 instead of silently producing
  that report: an unmatched root makes every function unreachable, so a typo in a root name would
  otherwise read exactly like a correct answer.
- **The LSP indexing path forged must-reach paths.** `arch-index --language go|rust|typescript`
  wrote a `calls` table with no `kind` column, and a missing `kind` reads as the literal `'MUST'`
  in `Arch_db.kind_sql` — so every callHierarchy edge, including the deferred and conditional
  ones the protocol cannot distinguish, entered the MUST closure and `reaches` reported must-reach
  paths that path does not support. Every edge it writes is now tagged `MAY_ENUMERATED`, and the
  index deliberately does **not** stamp `callgraph_contract`: callHierarchy never reports the call
  sites it failed to resolve, so the ⊤ frontier is unknown rather than empty and
  `unreachable`/`escapes` must keep refusing.
- **A race against the language server's background indexing.** rust-analyzer answers
  `prepareCallHierarchy` with an empty list — not an error — while `cargo metadata` and the
  initial index are still running, so "still indexing" and "no calls" were indistinguishable and
  a cold checkout indexed to zero edges. The handshake now consumes `$/progress` and waits for
  the work-done tokens the server already reports. The wait reports which of four outcomes it
  reached, because they are not interchangeable: the indexing phase closing is authoritative,
  quiescence is a heuristic that can fire in an inter-phase gap (rust-analyzer runs startup as a
  sequence of tokens and closes each before opening the next), and no-progress and timed-out are
  neither. Only the first is a fact about the index; the rest fall back to the previous
  bounded-sweep behaviour, so a server that reports nothing is no worse off than before.
- A language-server request that timed out with its reply unread left the connection
  desynchronised, and every later call then failed with its own id-mismatch `Protocol_error` —
  N confusing errors, none of them naming the single event that caused them all. (Not a
  soundness bug: `Jsonrpc_client` stamps each request with a monotonic id and rejects a reply
  whose id does not match, so a desynced stream never returned a wrong answer.) The connection
  is now retired on the first such failure and every later call reports that reason, instead of
  the same refusal arriving by accident as an `Eio.Mutex.Poisoned` wrapped in
  `Connection_failed`.
- A legacy index with no `calls.kind` column crashed the closure queries — the column cannot be
  named in SQL when it does not exist. Every edge now reads as MUST there, as `arch-query` does.
- `arch-impact`'s `contract_ok`/`sound_reachability` used a weaker check (`t.contract <> None &&
  t.kinded`) than `arch-rules`'s (the full `require_contract` scan, which also rejects a
  NULL/invalid `kind` on a real edge — a flag set on a malformed index is worse than no flag at
  all: see `Arch_db.require_contract`'s doc comment). The same index could read `contract_ok:true`
  from one tool and `false` from the other. Both tools now derive it from one new shared helper,
  `Arch_db.contract_ok`, so they can never disagree. New selftest fixture (the same
  stamped-but-NULL-kind index `selftest-contract.sh` already uses) confirms both tools agree
  `contract_ok:false` on it. `arch-impact`'s text-mode output is unaffected — no existing fixture
  had a NULL-kind edge, so the stricter check changes nothing already covered, only what was
  previously miscategorized.
- `arch-rules --format json`: added `results[].detail_total`, the untruncated count each
  `detail` list (capped at 20) was cut from — previously a consumer could not tell "20 shown, 20
  total" from "20 of 200" without recounting from text output.
- `arch-coverage` and `arch-mutants` still computed `sound`/`sound_reachability` via the same
  weak `t.contract <> None && t.kinded` check `arch-impact` was just fixed to stop using
  (round-2 review, follow-up to the `contract_ok` unification above). Both now call the shared
  `Arch_db.contract_ok` helper too, so a NULL-kind edge reads `sound:false` consistently across
  all four tools instead of only the two that gate the `proof-carrying-change` workflow.

## [0.2.0] - 2026-06-25

### Added
- `arch-serve`: local HTTP server serving a D3 force-graph SPA from a SQLite DB
  - Neighborhood BFS view (depth 1/2/3), Module view, Reachability query
  - Function search and module filter sidebar
- CMT-based call graph extraction fallback for OCaml projects
  - Walks `_build/default/**/*.cmt` typed ASTs when LSP call hierarchy is unavailable
  - ocamllsp ≤1.23.1 does not implement `textDocument/prepareCallHierarchy`

### Fixed
- OCaml projects producing 0 functions — 5 root causes:
  - `language_id_of_uri` always returned `"typescript"` for `.ml` files
  - `scan_ts_files` used as fallback for OCaml (0 `.ts` files found)
  - `_opam/` local switch (~30k `.ml` files) not excluded from scan
  - `workspace/symbol` cold-start corruption on ocamllsp (stale response in read buffer)
  - `symbol_kind_of_int` table had kinds 6↔12 and 7↔13 swapped vs LSP spec
- LSP call hierarchy bugs: wrong method name, missing `callHierarchy` client capability, `character:0` pointing at `let` keyword instead of function name token
- Timeout in `runner.ml` discarded already-collected function rows

## [0.1.0] - 2026-06-25

### Added
- Initial release extracted from epure
- Sound ⊤-marked call-graph index for Go (go/ssa + CHA) and OCaml (cmt typedtree)
- `arch-index` CLI: build symbol + call-graph database from source
- `arch-query` CLI: query reachability (reaches/unreachable/callers-of/fan-in/exported/find/escapes)
- Three-verdict reachability: REACHABLE / UNKNOWN: MAY_TOP / UNREACHABLE: no path
- Standalone dune project + arch-index.opam
