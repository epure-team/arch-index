# Research — mutation-campaign-313

_Generated: 2026-09-05T12:35:00+02:00_
_Mode: full (4 parallel specialists: locator, analyzer, pattern librarian, external researcher)_
_Online research: enabled_
_Working tree: `/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`, base `70cb47f`_

---

## Question 1: Where is the existing static mutation-targeting logic implemented, and what data does it currently produce or persist about mutants, sites, and functions? Include the exact input and output formats it reads and writes.

**Finding:** One binary owns it, `arch-mutants`, with two subcommands and no persistence of its own. It reads an engine report and the call graph, and writes only to stdout — nothing it computes reaches the database.

Input formats it accepts:

- **Generic NDJSON**, one object per line: `{"file","line","status","id","mutation"}` with `status ∈ SURVIVED | KILLED | TIMEOUT | ERROR`.
- **Mutaml** (`--from mutaml`), a bare JSON array of `test_result`, whose `status` is normalized into the same four values; both the integer encoding (0→SURVIVED, 124→TIMEOUT, other→KILLED) and the string encoding (passed/timeout/failed) are accepted, and anything else aborts.

Output formats of `plan`: `text`, `json` (keys `test_roots`, `targets` with `reaching_tests` and `already_vacuous_lines`, `unreached`, `test_cone_escapes`, `indexed_functions`, `sound_targeting`, `unaccounted`), and `lines` (a `file:start-end` allowlist for an engine). Output of `report`: `survivors` with per-survivor `reaching_tests`, plus `killed`, `errored`, `unmapped`, `total`.

**A naming collision exists in the schema.** `functions.mutation_sites` is already taken and means something unrelated: a count of *imperative state writes* (`:=`, incr/decr, record field `<-`, array/bytes set, container mutation), with an index `idx_functions_mutation` and a view `v_mutation_heavy` over it. Any new table or column named for mutation-testing sites would put two meanings of "mutation" in one database.

**References:**
- `bin/arch_mutants/arch_mutants.ml:25` — the four-value input status vocabulary, in the usage doc.
- `bin/arch_mutants/arch_mutants.ml:245–330` — `load_generic` and `load_mutaml`, the two adapters.
- `bin/arch_mutants/arch_mutants.ml:347–435` — `report` bucketing and survivor blame.
- `architecture-schema.sql:103–107` — `mutation_sites INTEGER`, commented as counting writes.
- `architecture-schema.sql:152` — `idx_functions_mutation`.
- `lib/arch_index/arch_index_cmt.ml` — `count_mutability`, the typedtree walk that fills it.
- `lib/arch_tools/arch_sel.ml` — the `file:` / `fn:` / `module:` selector used for `--tests`.

---

## Question 2: What database schema, tables, and migration mechanisms currently exist, and how are call-graph, symbol, and coverage data represented? State where the schema version constant is defined and how it is bumped.

**Finding:** Three separate version identities exist, and the main one is a two-part `major.minor` string in OCaml. Additive changes bump the minor; removals and type changes bump the major. Migrations are separate `.sql` files, explicitly additive, applied once, and safe to re-run because every statement is `IF NOT EXISTS`.

- `lib/arch_index/arch_index_db.ml:55` — `let current_schema_version = "1.10"`, alongside `current_flat_schema_version = "1.2"`. The two version spaces are deliberately distinct so a flat-schema consumer cannot conclude that main-schema tables exist.
- `lib/arch_index/arch_index_db.ml:75–81` — `parse_schema_version` splits on `.` into `(major, minor)` for comparison.
- `docs/schema.md:220–230` — the version table, one row per version with what it added and which migration file carries it.

Patterns available for a new table: `CREATE TABLE IF NOT EXISTS` in a dedicated migration file (`effects-schema-migration.sql:13–20`), composite `UNIQUE(...)` in the table body (`architecture-schema.sql:82–127`, `UNIQUE(module_id, name)`), `CHECK(col IN (...))` for a closed vocabulary (`architecture-schema.sql:213–218`, the `top_reason` vocabulary), and a partial-uniqueness index using `COALESCE` to make NULLs comparable (`effects-schema-migration.sql:82–84`, `fn_effects_identity`).

Two idempotent column-add helpers exist rather than one: `capability_db.ml:47–71` swallows the "duplicate column" error text, and `capability_db.ml:94–107` checks `pragma_table_info` first.

**References:** as cited above, plus `capabilities-schema-migration.sql:1–15` for the additive-migration header convention and `docs/schema.md:74–96` for how provenance is recorded as a `producer_runs` row plus a nullable `producer_run_id` foreign key, deliberately not as per-row text (at Octez scale, ~1.4M calls, the per-row form is described as a ~200 MB mistake).

---

## Question 3: How does arch-index represent and track ⊤ (MAY_TOP) unresolved edges, and what consumes that marker? For each consumer, state whether it treats a ⊤ edge as widening or narrowing its answer.

**Finding:** `calls.kind ∈ {MUST, MAY_ENUMERATED, MAY_TOP}`, with `top_reason` and `top_anchor` constrained non-NULL only on `MAY_TOP`. At graph-load time a ⊤ edge is **never** added to the traversable adjacency maps; the holding caller is recorded in a separate `tops` frontier map, described in the source as "never dropped, never traversed".

Every consumer that reaches a verdict widens on ⊤. The table below is the answer to the question as asked.

| Consumer | Treatment of a ⊤ edge |
|---|---|
| `arch-query reaches` | Neither. MUST-only closure; a ⊤ edge is outside its analysis. |
| `arch-query unreachable` | **Widens.** `UNREACHABLE` downgrades to `UNKNOWN` when the cone touches ⊤ or an unknown-kind edge. |
| `arch-query escapes` | Reports the frontier itself; does not modify another answer. |
| `arch-query dead-code` | **Widens.** Verdict downgrades from `sound` to `candidate (MAY_TOP reachable…)`. |
| `arch-query pure-fns` | **Widens** the impure set: any caller of a ⊤ edge is seeded as impure, shrinking the positive claim. |
| `may-fail` / `fails-with` / `raisers-of` | **Widens.** ⊤ maps to the `Top` lattice element, which absorbs; verdict becomes `UNBOUNDED (⊤)`. |
| `arch-impact` | **Widens.** A separate `may_upstream` / `may_affected` / `may_tests` bucket, reported alongside and never merged into the definite sets. |
| `arch-rules` (`Reach`, `Effect`) | **Widens.** `UNKNOWN` instead of `PASS` when the cone reaches a `tops` node. |
| `arch-coverage` | **Widens** the explained-coverage bucket: `covered_via_top_only` is kept distinct from uncovered and from no-data. |
| `arch-mutants plan` | **Neither.** It filters `tops` to the test-reachable set and *reports* the escape in prose; the escape does not enter any verdict. |

`arch-rules` additionally separates two reasons for not saying `PASS`: `UNKNOWN` (the cone escaped through ⊤) and `UNKNOWN_NO_CONTRACT` (no escape, but the index is not ⊤-marked at all, so soundness was never established). Its header states the rule directly: an index that is not ⊤-marked can never yield `PASS`.

**References:**
- `architecture-schema.sql:189`, `192–218` — the `kind` column and the `top_reason` / `top_anchor` CHECK constraints.
- `lib/arch_tools/arch_graph.ml:99–113` — ⊤ edges routed into `tops`, never into `fwd` / `bwd` / `must_fwd`.
- `bin/arch_rules/arch_rules.ml:16` — "an index that is not ⊤-marked can never yield PASS: it degrades to UNKNOWN_NO_CONTRACT".
- `bin/arch_rules/arch_rules.ml:186–206`, `204`, `391` — the `Reach` verdict ladder and both UNKNOWN variants.
- `bin/arch_query/arch_query.ml:345–378`, `381–403` — `unreachable` and `escapes`.
- `bin/arch_query/arch_effects_queries.ml:139–162`, `244–263` — `pure-fns` and `dead-code`.
- `lib/arch_tools/arch_exn.ml:448–457`, `504–508` — the absorbing `Top` element and the `UNBOUNDED (⊤)` verdict.
- `bin/arch_impact/arch_impact.ml:222–241` — the separate may-bucket.
- `bin/arch_coverage/arch_coverage.ml:187–194` — `covered_via_top_only`.
- `bin/arch_mutants/arch_mutants.ml:46–53` — `escapes` filtered to the test-reachable set.

---

## Question 4: What existing mechanisms map tests to the functions they exercise, and how is that mapping stored? For each, state whether it is computed statically, observed at runtime, or both.

**Finding:** Five mechanisms, no shared table between them.

| Mechanism | Storage | Static / runtime |
|---|---|---|
| `functions.tests_raw` | JSON array on the `functions` row | **Static, and author-declared.** Parsed from a hand-written `{tests}` doc-comment section at index time. Never executed, never cross-checked against a run. |
| `arch-coverage` | not persisted unless `--write` | **Both.** Static line span from the index, runtime `DA` hit counts from an LCOV tracefile. No data in the span is reported `no_data`, never fabricated as 0 %. |
| `arch-coverage-load` | `coverage` table, dated snapshots | **Both.** Runtime-derived numbers, resolved to the index statically by name plus optional module; ambiguous names are skipped and counted, never guessed. |
| `arch-mutants` | not persisted | **Both.** Test identity and reachability are static; kill status comes from the engine report. |
| `arch-impact` test detection | not persisted | **Static only.** The same anchored path/name heuristic, filtering a static closure. |

Test identity in both `arch-mutants` and `arch-impact` is a path and name heuristic anchored on `test` / `spec` / `_test.` and a `test` function-name prefix, not a declared registry.

**The reaching-test set is computed by the same lower-bound expression at two call sites, not one.** `SS.inter (Arch_graph.closure (SS.singleton …) g.bwd) test_keys` appears in `plan` and again in `report`.

**References:**
- `architecture-schema.sql:100` — `tests_raw`.
- `lib/arch_index/runner.ml:164–187`, `lib/arch_index/arch_index_cmt.ml:2917` — the `{tests}` doc-comment parse.
- `bin/arch_coverage/arch_coverage.ml:9–10`, `155–171`, `186` — span × hit-count, and the no-data rule.
- `bin/arch_coverage_load/arch_coverage_load.ml:1–24` — the NDJSON snapshot contract.
- `bin/arch_mutants/arch_mutants.ml:31–42` — `test_re`.
- `bin/arch_mutants/arch_mutants.ml:86` — the backward closure in `plan`.
- `bin/arch_mutants/arch_mutants.ml:370` — the same backward closure in `report`.
- `bin/arch_impact/arch_impact.ml:40–49` — `is_test`, the same heuristic.

---

## Question 5: How are language- or tool-specific adapters and profiles structured, and what interface do they expose? Name every existing profile and the mechanism that loads it.

**Finding:** Two unrelated adapter systems, one compiled in and one file-discovered.

**Language-server registry**, compiled in: `Language_registry.default()` holds ocaml/ocamllsp, typescript/typescript-language-server, rust/rust-analyzer, go/gopls, python/pylsp. `lookup : t -> language:string -> project_dir:string -> (lsp_server_config, string) result`, where the config is a command, args, and optional init options. Detection is by manifest file, with a depth-bounded tree walk pairing each language to its project directory.

**Error-channel profiles**, file-discovered under `profiles/`. **Exactly one profile ships today: `profiles/tezos-errors.toml`.** Naming convention is `<name>-errors.toml`. Discovery order is the `ARCH_ERRORS_PROFILES_DIR` environment variable, then `<project_root>/profiles/`, then `profiles/` in the executable's ancestor directories, depth-bounded to 6. Merge order is built-in, then shipped profile, then user file, field by field: unset scalars inherit, lists concatenate with deduplication, same-named channels replace. Validation tracks which declared paths actually matched, and a strict flag promotes unmatched operator-sourced paths to fatal.

**References:**
- `lib/arch_index/language_registry.ml` and `.mli` — registry, detection, install instructions.
- `lib/arch_index/arch_errors_config.ml` — `of_toml`, `merge`, `check_reachable`, `validate`.
- `lib/arch_index/arch_index.ml` — `load_errors_config`, `discover_profile`, `discover_user_config`.
- `profiles/tezos-errors.toml` — the only shipped profile.
- `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml` — the `--errors-config` / `--errors-profile` / `--errors-strict` wiring.

---

## Question 6: List every verdict or status vocabulary defined across the repository's analysis binaries, and for each value the exact condition under which it is emitted.

**Finding:** Nine of the seventeen binaries under `bin/` emit no verdict at all — they are producers and loaders that write facts, not judgments. The eight that do judge are below.

`arch-rules` carries the richest ladder. For a `Reach` rule: `NO_SOURCE` (source selector matches nothing), `NO_TARGET` (target matches nothing), `VIOLATION` (MUST closure hits), `POSSIBLE` (MAY closure hits, no MUST hit), `UNKNOWN` (no hit, cone reaches a `tops` node), `UNKNOWN_NO_CONTRACT` (no hit, no escape, index not ⊤-marked), `PASS` (no hit, no escape, index sound). `Effect` adds `NOT_COMPUTED` when the table is absent; `Dep` has the same plus `PASS` / `VIOLATION`. Display remaps `NO_SOURCE` and `NO_TARGET` to `VACUOUS`, which names the vacuous-pass case rather than hiding it.

`arch-query unreachable`: `REACHABLE (may-reach)`, `UNKNOWN` (unresolved kind in the cone), `UNREACHABLE` (neither, index sound). `may-fail` and its relatives: `NOT_A_CARRIER`, `BOUNDED`, `BOUNDED_UNDER_HYP(externals_pure)`, `UNBOUNDED (⊤)`. `dead-code` emits a per-row verdict string that names its own caveat. `arch-impact` has `pass` / `fail` / `refused`, where `refused` is emitted when the flag is given but the `decisions` table is absent, rather than passing. `arch-mcp` re-parses `arch-query`'s text and adds `REFUSED` and `UNPARSED`. `arch-serve` has `PATH_EXISTS` / `NO_MUST_PATH`. `arch-coverage` has a bucket vocabulary rather than a verdict: `never`, `no_data`, `covered_via_top_only`, `covered_outside_api_cone`, `covered_but_mutants_survive`, plus `mutants_ambiguous_names` for name collisions.

`arch-mutants` is the outlier: its vocabulary is the four input values it reads from the engine, and it buckets them into killed (KILLED or TIMEOUT), errored (anything not SURVIVED), and survivors. It defines no verdict of its own and has no value expressing an unresolved analysis.

**References:** `bin/arch_rules/arch_rules.ml:186–206`, `274–299`, `320–390`, `393–460`, `471–477`, `715`; `bin/arch_query/arch_query.ml:330–344`, `345–378`, `381–403`, `1236–1270`; `lib/arch_tools/arch_exn.ml:504–508`; `bin/arch_query/arch_effects_queries.ml:244–263`; `bin/arch_impact/arch_impact.ml:260–269`; `bin/arch_mutants/arch_mutants.ml:25`, `286–305`, `347–349`; `bin/arch_mcp/arch_mcp.ml:265–282`; `bin/arch_serve/arch_serve.ml:397–411`; `bin/arch_coverage/arch_coverage.ml:155–267`; `bin/arch_load/arch_load.ml:280–298`.

---

## Question 7: Where does the repository establish that an identifier is unique over a real corpus rather than a fixture, and what commands or queries does it use?

**Finding:** One tool does exactly this today. `arch-body-compare` runs `SELECT name FROM functions GROUP BY name HAVING count(*) > 1` over the indexed corpus, then compares bodies to separate genuine duplicates from same-name-different-body, and reports an `unverifiable` bucket when a body is empty rather than counting it either way.

Uniqueness is otherwise enforced rather than measured, by `UNIQUE` constraints declared in the table body and by `CREATE UNIQUE INDEX` with `COALESCE` for nullable components. `arch-query stats` and `fan-in` report aggregate `GROUP BY` counts over the real index but do not test a key.

**References:**
- `bin/arch_body_compare/arch_body_compare.ml:82` — the `GROUP BY … HAVING count(*) > 1` probe.
- `bin/arch_body_compare/arch_body_compare.ml:95–107` — the duplicate / unverifiable / differs three-way split.
- `bin/arch_query/arch_query.ml:267–289`, `342–361` — `stats` and `fan-in` aggregates.
- `architecture-schema.sql:633–641` — the `v_most_called` view, a `GROUP BY … HAVING` over the corpus.
- `effects-schema-migration.sql:82–84` — `fn_effects_identity`, uniqueness by unique index with `COALESCE`.

---

## Question 8 [ecosystem]: How do existing mutation engines structure generation, test selection, and reporting, and what conventions identify kills versus survivors?

**Finding:** All surveyed engines generate a mutant batch up front, then run tests against each. They differ sharply on two axes that matter here: whether the report is machine-readable against a published schema, and whether "not killed" is distinguished from "not covered".

| Engine | Machine-readable report | Per-mutant test subsetting | Distinguishes not-covered from not-killed |
|---|---|---|---|
| Stryker | Yes, a published versioned JSON schema shared across language implementations | via coverage analysis | **Yes** — `NoCoverage` is a first-class status, alongside `Pending` for generated-not-yet-run |
| PIT | Yes, XML / HTML / CSV | Yes, coverage-based, down to test-case level | **Yes** — `NO_COVERAGE` distinct from `SURVIVED` |
| cargo-mutants | Yes, but the format is explicitly marked unstable across releases | Package-level only | **No** — everything undetected folds into `missed` |
| mutmut | Cache plus console; no documented JSON or XML report | Coverage can restrict which mutants run | Partial — uncovered mutants are excluded rather than labelled |
| go-mutesting | No structured format found; console text and diffs | None documented | No evidence found |
| mutaml | `mutaml-report.json`, structure undocumented in the README | Its targeting flag selects **which mutants run**, not which tests are run against a mutant | No evidence found |

**References:**
- https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/ — Stryker Mutator docs — `NoCoverage` defined as "not covered by any test, and survived as a result".
- https://github.com/stryker-mutator/mutation-testing-elements/blob/master/packages/report-schema/src/mutation-testing-report-schema.json — the shared schema; status enum Killed, Survived, NoCoverage, CompileError, RuntimeError, Timeout, Ignored, Pending.
- https://github.com/stryker-mutator/mutation-testing-elements/issues/2424 — the addition of `Pending` for generated-but-not-run.
- https://pitest.org/ — PIT — four-phase pipeline, reports combine line and mutation coverage.
- https://github.com/hcoles/pitest/issues/1059 — confirms `NO_COVERAGE` in `mutations.xml`, and notes an inconsistency where some uncovered lines are still mutated and reported.
- https://mutants.rs/using-results.html — cargo-mutants — Caught / Missed / Unviable / Timeout; JSON format explicitly unstable.
- https://mutants.rs/workspaces.html — cargo-mutants test selection is package-scoped.
- https://github.com/boxed/mutmut — mutmut — cache-based results, coverage used to exclude rather than label.
- https://github.com/jmid/mutaml — mutaml — `mutaml-report.json` undocumented; the `--muts` flag scopes mutants, not tests.
- https://github.com/zimmski/go-mutesting — go-mutesting — console output only.

Source caveat reported by the researcher: the cargo-mutants, mutmut and PIT findings rest on current first-party documentation sites; the mutaml and go-mutesting findings rest on lower-traffic READMEs with no recent third-party corroboration, and should be re-checked against the live repositories if precision matters.

---

## Question 9 [ecosystem]: How do established test runners expose per-test invocation and per-test coverage data?

**Finding:** All five can run one named test. **None attributes coverage to an individual test natively, except pytest.**

| Runner | Run one test | Per-test coverage |
|---|---|---|
| alcotest | `binary test '<regex>' ['<numbers>']` — by group regex plus test-number list. Filtering by exact test-case name is documented as not supported. | No. Requires one process per test, collecting one bisect_ppx file per invocation. |
| tezt | `--test <title>`, `--file <source>` | No. Coverage under tezt needs extra wiring: parallel workers are killed with SIGTERM, which skips the at-exit coverage flush unless bisect_ppx's SIGTERM handler is enabled. |
| cargo test | `cargo test name` (substring), `-- --exact name` | No. Passing the same `--exact` filter through `cargo llvm-cov` is a documented workaround, not a feature. |
| go test | `-run '^TestName$'` | No. `-coverprofile` is one aggregate profile per invocation; per-test requires one run per test. |
| pytest | node ID, `path::test_func` or `path::Class::method` | **Yes.** `--cov-context=test`, built on coverage.py dynamic contexts, records which lines each individual test exercised within one run. |

**References:**
- https://github.com/mirage/alcotest/blob/main/README.md — the regex-plus-numbers addressing model and the explicit note that exact test-case name filtering is unavailable.
- https://octez.tezos.com/docs/developer/tezt.html — tezt `--test` and `--file`.
- https://gitlab.com/tezos/tezos/-/merge_requests/8022 — the SIGTERM / bisect flush problem in tezt's parallel workers.
- https://github.com/aantron/bisect_ppx — one `bisectNNNN.coverage` file per process at exit.
- https://doc.rust-lang.org/cargo/commands/cargo-test.html — the test filter argument.
- https://github.com/taiki-e/cargo-llvm-cov/issues/347 — per-test coverage as a filter-passthrough workaround.
- https://pkg.go.dev/cmd/go, https://pkg.go.dev/cmd/cover — `-run` regexp; aggregate profile per invocation.
- https://docs.pytest.org/en/7.1.x/how-to/usage.html — node ID syntax.
- https://pytest-cov.readthedocs.io/en/latest/reporting.html — `--cov-context=test`.

Source caveat reported by the researcher: the Go and Rust answers rest on community issues rather than first-party documentation, because neither toolchain supports per-test coverage splitting. That is a documented absence, not an unresearched one.

---

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| ⊤ frontier kept out of traversal | `lib/arch_tools/arch_graph.ml` | 99–113 | ⊤ edges go to a `tops` map, "never dropped, never traversed" |
| Verdict ladder with two distinct unknowns | `bin/arch_rules/arch_rules.ml` | 186–206 | `UNKNOWN` (escaped via ⊤) vs `UNKNOWN_NO_CONTRACT` (index not ⊤-marked) |
| Vacuous-pass named, not hidden | `bin/arch_rules/arch_rules.ml` | 471–477 | `NO_SOURCE`/`NO_TARGET` display as `VACUOUS` |
| Refusal instead of a pass on missing data | `bin/arch_impact/arch_impact.ml` | 260–269 | `refused` when the flag is set but the table is absent |
| No-data distinguished from zero | `bin/arch_coverage/arch_coverage.ml` | 9–10, 186 | absent instrumentation is `no_data`, never 0 % |
| Key probe over the real corpus | `bin/arch_body_compare/arch_body_compare.ml` | 82, 95–107 | `GROUP BY … HAVING count(*) > 1`, with an `unverifiable` third bucket |
| Additive migration file | `effects-schema-migration.sql` | 1–20 | `CREATE TABLE IF NOT EXISTS`, applied once, re-runnable |
| Uniqueness over nullable columns | `effects-schema-migration.sql` | 82–84 | unique index with `COALESCE(col,'')` |
| Closed vocabulary enforced in SQL | `architecture-schema.sql` | 213–218 | `CHECK(col IS NULL OR col IN (…))` |
| File-discovered TOML profile | `lib/arch_index/arch_index.ml` | `discover_profile` | env var, then project `profiles/`, then executable ancestors; merge built-in < shipped < user |
| Provenance as a row, not per-row text | `docs/schema.md` | 74–96 | `producer_runs` plus a nullable FK; the per-row form is ~200 MB at Octez scale |

## External prior art

| Tool / approach | Source | Key finding |
|---|---|---|
| Stryker Mutation Testing Elements | stryker-mutator.io | A published, versioned, cross-language JSON report schema whose status enum already separates `NoCoverage` and `Pending` from `Survived` |
| PIT | pitest.org | `NO_COVERAGE` as a first-class status; test selection by coverage down to individual test case |
| cargo-mutants | mutants.rs | Package-level test scoping; no covered/uncovered subdivision; JSON format declared unstable |
| mutaml | github.com/jmid/mutaml | Report structure undocumented; scoping selects mutants, not tests |
| coverage.py dynamic contexts | pytest-cov.readthedocs.io | The only surveyed runner ecosystem with native per-test coverage attribution |

## Coverage gaps

- **Q1** — the exact NDJSON and JSON field sets were read from the usage documentation and the loaders, not from a golden-file test; no fixture in the repository pins the `plan --format json` key set, so the shape is documented by code rather than by contract.
- **Q7** — `arch-body-compare` proves *name* duplication over the corpus. No probe in the repository tests a *composite* key over a corpus, so there is no in-repo precedent for the composite case.
- **Q8** — the mutaml and go-mutesting rows rest on project READMEs with no recent third-party corroboration; both should be re-verified against the live repositories before being relied on.
- **Q9** — the Go and Rust per-test-coverage rows rest on community issues rather than first-party documentation, because the capability does not exist in either toolchain.
