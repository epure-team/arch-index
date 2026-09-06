---
task: mutation-campaign-313
type: spec
status: live
feature: Executed mutation campaign (roadmap item 3.13)
brief: briefs/mutation-campaign-313-intake.md
date: 2026-09-05
version: 1.0.0
---

# Spec — Executed mutation campaign

## Clarifications

| Q | A |
|---|---|
| How is a campaign identified across re-runs? | A campaign is a row with a surrogate id. Re-running always inserts a **new** campaign; campaigns are never resumed by identity. This follows the repository's append-only precedent (dated `coverage` snapshots, the pipeline ledger). |
| Is `seed` mandatory, and what does a seedless engine record? | `seed` is nullable TEXT. NULL means the engine declares no seed concept, and the report says so in words rather than printing an empty value — the same discipline as `arch-coverage`'s `no_data`, which is never rendered as 0 %. |
| Does a mutant the index cannot map to a function get persisted? | Yes, with `function_name` NULL. `docs/mutation-testing.md` already requires that an unmapped survivor be reported and never dropped; dropping it one layer lower, in storage, would contradict that rule where nobody would see it. **Amended in review round 3**: the column was `function_id INTEGER REFERENCES functions(id)` and the only writer passed `None` unconditionally. It was removed rather than populated, because it cannot work: this tool reads both `Arch_db.Flat` and `Arch_db.Main`, and the flat schema `arch-load` writes has a `functions` table with no `id` column — measured, with `PRAGMA foreign_keys = ON` SQLite then rejects the INSERT with "foreign key mismatch" even when the bound value is NULL. `mutant_campaigns.producer_run_id` was removed for the same measured reason (no `producer_runs` table on a flat index). The name is what the reader needs and what the writer actually populates. |
| What identifies a test across campaigns? | The resolved test **name** string. Positional addressing (alcotest's group-plus-index) is an invocation detail, re-resolved from the profile each campaign, never part of identity. A name present in an earlier campaign and absent from the current index is a deleted test. |
| Must the driver resume a partial campaign? | No. A partial campaign is valid and readable: `completed_at` stays NULL, and a mutant with no run row in an incomplete campaign is **PENDING**, which is derived from the absence of the row, not stored. |
| What does a new test that reaches nothing produce? **[DEFERRED — slice 4; FR-021 is not implemented in this deliverable.]** | It *will be* reported in its own bucket, "reaches no indexed function", never in the killed-nothing defect list. Reporting it as a defect would be the same false accusation the ⊤ rule exists to prevent. **This row states FR-021, which slice 4 implements; nothing in this deliverable's binary produces the bucket.** The marker is here rather than only at FR-021 because this table PRECEDES every other deferral marker in the document, so a reader arriving in order is told the behaviour holds before anything has told them it does not. |
| May a profile over-select? | Yes. A superset of the reaching set is still a superset, so over-selection preserves the admissibility of `SURVIVED`. The actually-executed set — what the wrapper's trace line says ran, not what the plan said should run — is recorded, so the cost is visible. **The second half of the original answer, "and it must declare `granularity = case \| group \| suite`", is FR-023 and is DEFERRED to slice 5; profile loading is not implemented in this deliverable.** |
| What if no engine is installed? | Abort, exit 2, naming the engine and the profile that asked for it, following the existing `die` convention. An empty campaign must never read as "no survivors". |
| Where does PENDING live, given the engine-status vocabulary is closed to four values? | Nowhere in a column. PENDING is the **absence** of a `mutant_runs` row inside an incomplete campaign. Storing it would require widening a closed vocabulary the whole codebase depends on — search for the `type status = Killed \| Survived \| Timeout \| Errored` binding in `bin/arch_mutants/arch_mutant_db.ml`, `:60` at the time of writing. **The coordinate is a hint and the binding text is the anchor**: the previous citation here, `arch_mutants.ml:348-349`, was correct when written and now lands in the middle of the wrapper-refusal comment block in a different file, which is worse than no citation because a reader believes it. |
| Do we know **which** test killed a mutant? | Usually not. Engines report per mutant, not per (mutant, test). Attribution is recorded only when it is actually known — a singleton executed set, or an engine that names the killing test. Otherwise the campaign records the attempted set and the aggregate outcome, and any question needing attribution answers `UNKNOWN`. |

## User Stories

### US-1: Execute a campaign with per-mutant test selection (Priority: P0)

As a maintainer running a mutation campaign, I want `arch-mutants run` to drive the engine with,
per mutant, only the tests that reach the mutated function, so that a campaign costs the selected
subset rather than the whole suite times the mutant count.

**Why this priority**: nothing executes today. Every other story consumes the facts this one produces.
**Scope**: This story does NOT generate mutants, rewrite source, launch a build, or install an engine.
**Independent Test**: with a stub engine that records its argv and a fixture index, the recorded
per-mutant invocation names exactly the executed set the plan declared, and the campaign records
that set.

**Acceptance Scenarios**:
1. **Given** a fixture index whose test cone is closed and a stub engine, **When** `arch-mutants run` is invoked over a two-mutant plan, **Then** the stub is invoked twice and each invocation carries only the tests the plan lists as reaching that mutant's function.
2. **Given** a profile declaring `granularity = group`, **When** the reaching set is a strict subset of a group, **Then** the executed set is the whole group, `executed_superset` is true, and the campaign records both the intended and the executed sets.
3. **Given** no engine binary on PATH, **When** `arch-mutants run` is invoked, **Then** it exits 2 naming the engine and the profile, and writes no campaign row.

### US-2: Persist campaign facts (Priority: P0)

As a maintainer, I want each campaign's mutants, per-mutant outcomes and any known per-test
attribution persisted, so that a later campaign can answer questions about an earlier one.

**Why this priority**: the deleted-test rule and the per-added-test verdict are queries over these tables.
**Scope**: This story does NOT persist engine stdout, mutant diffs, or source snapshots.
**Independent Test**: after two runs differing only in seed, the mutant site rows are unchanged in
number while campaign and run rows have doubled.

**Acceptance Scenarios**:
1. **Given** an empty database, **When** a campaign of three mutants completes, **Then** `mutant_campaigns` has one row, `mutants` three, `mutant_runs` three, and `mutant_kills` has a row only for pairs whose attribution is known.
2. **Given** that same database, **When** a second campaign runs the same mutants with a different seed, **Then** `mutants` still has three rows and `mutant_runs` has six.
3. **Given** a campaign interrupted after one of three mutants, **When** the tables are read, **Then** `completed_at` is NULL, `mutant_runs` has one row, and the two absent mutants are reported PENDING rather than SURVIVED.

### US-3: A survivor under a bounded selection is UNKNOWN (Priority: P0)

As a reviewer reading a mutation report, I want a survivor found under a selection that may have
been incomplete reported as unknown rather than as a test gap, so that I am not sent to strengthen
a test that was never run.

**Why this priority**: this is the correctness core. Without it the output is unsound in the one
direction that produces false accusations against real tests.
**Scope**: This story does NOT decide whether a survivor is an equivalent mutant.
**Independent Test**: one engine report replayed over three fixture indexes — closed cone, ⊤ edge
in the test cone, and an index carrying no soundness contract — publishes `SURVIVED`, `UNKNOWN`
and `UNKNOWN_NO_CONTRACT` respectively, while the stored engine status is `SURVIVED` in all three.

**Acceptance Scenarios**:
1. **Given** an index whose test cone holds no ⊤ edge and which carries a soundness contract, **When** the engine reports SURVIVED, **Then** the published verdict is `SURVIVED` and `selection_provenance` is `proved_superset`.
2. **Given** an index with a ⊤ edge inside the test cone, **When** the engine reports SURVIVED for a mutant in the escaped region, **Then** the published verdict is `UNKNOWN` and the report names the ⊤ anchor.
3. **Given** an index carrying no soundness contract at all, **When** the engine reports SURVIVED, **Then** the published verdict is `UNKNOWN_NO_CONTRACT`, distinct from the ⊤ case.
4. **Given** any of the three indexes, **When** the engine reports KILLED or TIMEOUT, **Then** the published verdict is `KILLED` — a kill is a proof and selection provenance does not weaken it.

### US-4: Diff-scoped selection, in both directions (Priority: P1)

As a CI job on a pull request, I want the campaign restricted to mutants of what the diff touched
and of everything a modified or added test reaches, so that cost is proportional to the change
while a weakened test cannot pass unnoticed.

**Why this priority**: the value proposition for machine-written change, but it needs US-1 to US-3 first.
**Scope**: This story does NOT detect a semantic change with no line change — a constant, an
interface signature, a dependency bump. Those remain the ordinary suite's job.
**Independent Test**: a diff touching only a test file still selects mutants, in the code that test reaches.

**Acceptance Scenarios**:
1. **Given** a diff modifying one production function, **When** selection runs, **Then** the selected mutants are those whose site falls inside that function's span.
2. **Given** a diff modifying only a test helper, **When** selection runs, **Then** the selected mutants are those of every function reached by every test case that traverses the helper.
3. **Given** a diff deleting a test, **When** selection runs, **Then** every mutant that the previous campaign attributed to that test alone is re-selected, and any mutant whose attribution was never known is reported as un-recheckable rather than silently skipped.

### US-5: A test that kills nothing is a defect (Priority: P1) — DEFERRED to slice 4

**DEFERRED — NOT IN THIS DELIVERABLE.** None of US-5 is implemented. It lands in **slice 4**; until it does, nothing in this section describes behaviour the code has. Kept in the spec rather than deleted so slice 4 inherits the analysis, but a reader of this live spec must not take any of it as holding today.

As the judge rejecting a generated test, I want the list of added tests that killed no mutant of
anything they reach, so that a vacuous test is rejected without a human reading it.

**Why this priority**: high value, and it depends on US-2's tables.
**Scope**: a defect LIST. No ratio, no percentage, no threshold — `docs/mutation-testing.md` refuses
the mutation score on record and this story does not reopen it.
**Independent Test**: a test asserting only a tautology appears in the list; one asserting a real
postcondition of the same function does not.

**Acceptance Scenarios**:
1. **Given** an added test whose reachable mutants all came back SURVIVED under `proved_superset`, **When** the verdict runs, **Then** the test appears in the defect list.
2. **Given** an added test whose reachable mutants all came back UNKNOWN, **When** the verdict runs, **Then** the test does NOT appear in the defect list and is reported separately as unproven.
3. **Given** an added test that reaches no indexed function, **When** the verdict runs, **Then** it appears in a third bucket, "reaches nothing indexed", never in the defect list.
4. **Given** an empty defect list, **When** the report is printed, **Then** it states how many added tests were examined and what would have placed one on the list.

### US-6: Per-framework test-invocation profiles (Priority: P2) — DEFERRED to slice 5

**DEFERRED — NOT IN THIS DELIVERABLE.** None of US-6 is implemented: `known_profiles` in `bin/arch_mutants/arch_mutants.ml` is a built-in registry for slice 1, not a `<name>-tests.toml` loader. It lands in **slice 5**; until it does, nothing in this section describes behaviour the code has.

As a maintainer of a project in another language, I want the mapping from a test node to its
invocation declared in a profile, so that a new framework needs no code change.

**Why this priority**: alcotest alone unblocks the pilot; other frameworks are additive.
**Scope**: This story does NOT install, detect or configure test runners.
**Independent Test**: a profile declaring a template renders the expected command for a known test
node; a language with no profile yields `not_analysed` rather than an empty campaign.

**Acceptance Scenarios**:
1. **Given** a profile `alcotest-tests.toml` declaring `granularity = "group"` and a command template, **When** the driver renders an invocation for a known test node, **Then** the rendered command matches the expected string exactly.
2. **Given** a profile file missing the `granularity` key, **When** it is loaded, **Then** loading aborts with exit 2 naming the file and the missing key — it is not silently defaulted.
3. **Given** a project whose language has no profile, **When** a campaign is attempted, **Then** the run reports `mutation: not_analysed` for that language and exits without inventing an empty result.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | "Once per mutant with exactly the reaching tests" is unsatisfiable when the profile's granularity is `group` or `suite`. | The acceptance criterion is restated in terms of the **executed** set, not the reaching set. The profile declares granularity; the driver records intended and executed sets separately and sets `executed_superset`. Over-selection is sound; under-selection is not. |
| C-2 | US-1 | No argument grammar is given for `run`, so "the stub records its argv" asserts against nothing. | Grammar fixed as `arch-mutants run <db> --plan <plan.json> --engine <cmd> --test-cmd <cmd> --catalogue <file> [--tests <selector>] [--profile <name>] [--report <file>] [--from generic\|mutaml] [--seed S] [--engine-version V] [--diff <range>] [--repo DIR] [--format text\|json] [--max-list N]`, matching the existing subcommand-first, DB-positional shape. Each of the four mandatory flags REFUSES rather than defaulting. **Widened from three flags to four in review round 3**: `--engine` and `--test-cmd` name two different programs (the driver invokes the engine once; the engine invokes the wrapper once per mutant), and `--catalogue` is what lets the wrapper resolve the engine's mutant id to a test set instead of running the whole suite. |
| C-3 | US-1 | `plan` emits targets (functions with spans), not mutants; `run` cannot iterate mutants that do not exist yet. | `run` consumes a **mutant list** the engine's own generation phase produced (the `--format lines` allowlist is what constrains that generation). The site → function mapping is computed once, before execution, and reused for the verdict; it is not run twice. |
| C-4 | US-1 | Under-selection can produce a KILLED-by-omission... no: it can produce a **survivor** an excluded test would have killed. Does `run` refuse to execute when `top_bounded`? | It executes. Refusing would make the tool useless on any real index (Octez has 286 356 ⊤ edges). The shortfall is labelled, not avoided: this is precisely why `UNKNOWN` exists. Refusal is reserved for the case where the profile cannot address the tests at all. |
| C-5 | US-2 | Is a mutant's identity stable across campaigns, and what is its natural key? | Stable. `mutants` is a site table keyed by `(file_path, line, col_start, col_end, replacement, source_hash)`, unique. Engine-assigned ids are not trusted for identity, consistently with the same refusal for tests. A re-run of unchanged code adds no `mutants` rows. |
| C-6 | US-2 | What does a mutant with an empty attempted set write, given kills are keyed per test? | Nothing in `mutant_kills`. The per-mutant outcome lives in `mutant_runs` (campaign × mutant); `mutant_kills` holds only pairs whose attribution is known. This is why the two tables are separate. |
| C-7 | US-3 | The story conflates stored status with published verdict. | Restated: the stored `engine_status` is `SURVIVED` in all three fixtures; only the published verdict differs. The independent test now asserts both, so a change that stores the verdict would fail it. |
| C-8 | US-3 | Does US-3 apply to mutants of `unreached` functions? | No. `run` is only ever handed mutants inside `plan`'s targets. `unreached` needs a dead-code report, not a mutant, and `docs/mutation-testing.md` already says so. |
| C-9 | US-3 | The fixture pair covers only the ⊤ boundary, not `no_contract`. | A third fixture is added, reusing `Fixture.malformed_contract`, which `tezt/lib/arch_tezt.ml` already provides — search that file for `let malformed_contract`, `:807` at the time of writing — and which four existing suites share. |
| C-10 | US-4 | A modified test's reach set is itself a lower bound, so US-4 is a bound of a bound. | Yes, and it inherits US-3's semantics unchanged: mutants selected through a bounded test reach are labelled with the same `selection_provenance`. There is no separate accounting. |
| C-11 | US-4 | Is test-diff selection keyed at file, function or line granularity? | Function. A diff is mapped to touched functions through `arch-impact`'s existing machinery; a comment-only change inside a function still selects it, and that over-selection is sound and cheap relative to the alternative of parsing intent. |
| C-12 | US-4 | What is "the diff" scoped against? | An explicit `--diff <range>` argument, same shape as `arch-impact --diff`. No implicit default; an absent range means whole-index selection, stated in the report. |
| C-13 | US-5 | A test whose reachable mutants all came back UNKNOWN is indistinguishable from one that failed to kill. | Resolved in the acceptance scenarios: only mutants whose verdict is `SURVIVED` under `proved_superset` can place a test on the defect list. UNKNOWN mutants move it to an "unproven" bucket instead. |
| C-14 | US-5 | "Killed nothing" needs a denominator, which is threshold-like. | The denominator is the mutants **attempted in this campaign** that the test's reach set contains. A test whose reach set contains no attempted mutant lands in the "nothing attempted" bucket, not the defect list. |
| C-15 | US-6 | `not_analysed` borrows `analysis_coverage`'s vocabulary; a second writer to that table would break its single-writer invariant. | The mutation layer does **not** write `analysis_coverage`. It reports the string in its own output and, when persisted, writes its own column. The single-writer invariant of `arch-coverage-matrix` is preserved. |
| C-16 | US-6 | Is a profile without `granularity` invalid or defaulted? | Invalid, exit 2, named in scenario 2. Defaulting would silently decide the soundness question the field exists to answer. |
| C-17 | US-6 | Alcotest cannot filter by exact case name, so "no code change" may hide a per-framework shim. | Acknowledged and resolved by C-1's granularity mechanism, not hidden: the alcotest profile declares `granularity = "group"`. No shim; the declared coarseness is the answer. |
| C-18 | Prior art (Stryker) | Stryker stores `NoCoverage` as a sibling of `Survived`; this design keeps four values plus an orthogonal column, so a naive reader of raw rows can misread a bounded SURVIVED. And PENDING has no slot in a closed four-value vocabulary. | Divergence justified and mitigated. Stryker's `NoCoverage` means "no test covers this", a fact about coverage; our `top_bounded` means "the analysis may have missed a covering test", a fact about the analysis. They are not the same state and merging them would lose the distinction. Mitigation: no view or query returns `engine_status` without `selection_provenance`, enforced by CHECK-7. PENDING is derived from the absence of a run row in an incomplete campaign, never stored. |
| C-19 | Prior art (PIT) | PIT establishes real per-test-case coverage before scoring; this design labels a static shortfall after the fact. | Divergence justified: PIT owns its runtime and can instrument per test case on the JVM. arch-index is language-agnostic and static by construction, and the research found per-test coverage native only in one of five surveyed runners. The limitation is not merely accepted, it is **printed**: every campaign report states its selection provenance. |
| C-20 | Prior art (cargo-mutants) | cargo-mutants scopes tests at package level only and folds all non-kills into "missed". | A cargo-mutants profile declares `granularity = "suite"`. The abstraction does not paper over the engine's limit; it records it, and the resulting executed set is a superset, which stays sound. |
| C-21 | Prior art (mutmut) | mutmut excludes uncovered mutants; this design would run and label them. | The two agree more than they differ: `plan` already refuses to target `unreached` functions, which is mutmut's exclusion. The remaining case, a target with a **provably empty** reaching set inside a closed cone, is run and recorded `SURVIVED` with an empty executed set — it is a genuine, provable test gap, which is exactly what the tool should say. |
| C-22 | Prior art (mutaml) | mutaml has no per-mutant test scoping, and it is the only OCaml engine. | **RESOLVED by reading the engine's source, 2026-09-05** — it was recorded as an open risk on the strength of a README; the runner settles it. `src/runner/runner.ml:123-130` builds, per mutant, the command `MUTAML_MUTANT=<mut_id> timeout <n> <test_cmd>` and runs it with `Sys.command`. The test command is a single fixed string, so mutaml indeed cannot vary the test set itself — but it exports the active mutant's identity into the environment of every invocation, and `src/ppx/mutaml_ppx.ml:40` shows the instrumented code reading exactly that variable via `Sys.getenv_opt "MUTAML_MUTANT"`. So per-mutant test selection is achievable **without modifying mutaml**: the driver passes a wrapper as the test command, and the wrapper reads `MUTAML_MUTANT`, resolves that mutant to its reaching tests through the plan, and invokes only those. CHECK-8 remains, demoted from "does the mechanism exist" to "does the wrapper behave at runtime". The same reading confirms, for the record, why this engine cannot serve Tezos `lib_protocol`: the selector is `Sys.getenv_opt`, and the protocol environment exposes no `Sys`. |
| C-23 | Prior art (coverage.py) | For Python, `--cov-context=test` would give an exact reaching set, making UNKNOWN unnecessary for that profile. | In bounds and welcome. A profile may declare `reach_source = "graph" \| "dynamic"`. A dynamic source may only **add** tests to the selection, never remove any (P2), so it can promote a selection to `proved_superset` but never demote one. This is the one place where the additive-only rule does observable work. |
| C-24 | Prior art (tezt/bisect) | A timed-out mutant killed with SIGTERM may lose its coverage flush, corrupting attribution. | Attribution is not derived from coverage files, so a lost flush cannot corrupt a kill row. It can lose a dynamic reach measurement, which under C-23's additive-only rule can only shrink the selection back to the graph bound — a loss of precision, never of soundness. Stated in the report when a dynamic source returns less than the graph. |

## Functional Requirements

#### Campaign execution (US-1)

- **FR-001** [US-1]: `arch-mutants run` MUST accept `<db> --plan <file> --engine <cmd> --test-cmd <cmd> --catalogue <file>`, MUST refuse (exit 2, naming the missing flag) when any of the four is absent, and MUST NOT generate mutants, rewrite source files, or invoke a build. `--tests`, `--profile`, `--report`, `--from`, `--seed`, `--engine-version`, `--diff`, `--repo`, `--format` and `--max-list` are optional. **Amended in review round 3 to match the implementation, which is the correct one.** The original three-flag grammar was unimplementable: `--engine` names the program the DRIVER runs once, while `--test-cmd` names the per-mutant command the WRAPPER runs — conflating them makes a campaign run the whole suite N times and call it selection — and without `--catalogue`, the engine's own list of the mutants it will attempt, the wrapper cannot resolve `MUTAML_MUTANT` to a test set and falls back to running everything, which is the same failure wearing a different name. None of the four is defaulted, for the reason FR-030 gives: a guessed value drives a campaign the operator never asked for and its output is indistinguishable from a correct one.
- **FR-002** [US-1]: For each mutant, the driver MUST invoke the engine with a test set that is a superset of the reaching set the plan declares for that mutant's function, and MUST record both the intended and the executed sets. The executed set is the set the wrapper **observed** running, never the planned set restated. **Round 2's open finding against this requirement — "`executed_tests` records what the wrapper INTENDED to run, so the second set is a second copy of the first" — is closed by round 3's work and re-verified here rather than taken on report.** Search `bin/arch_mutants/arch_mutants.ml` for the `executed_by_id` hashtable, filled from `read_lines trace_file` (`:1993-2001` at the time of writing — a hint; the anchor is `executed_by_id`). A mutant with a trace line is ATTEMPTED and carries that observed list into `insert_run`'s `~executed` and into the JSON's `executed_tests`; a mutant with none is UNOBSERVED, gets no run row, no attribution, and publishes `"executed_tests": null` with the planned set kept separately under `intended_tests` — because there is no defensible number to record for a set nobody saw. `intended_tests_not_executed` names the difference rather than denying it with a bare boolean. Also record what a test-name string may be: a name the driver cannot pass to the runner safely MUST be refused rather than written, and an apostrophe — an ordinary OCaml identifier character (`aux'`, `loop'`) — is not one of those (AC-40).
- **FR-003** [US-1]: The driver MUST NOT invoke the engine with a **subset** of the intended reaching set under any circumstances. Round 3 implemented it — inclusion, not a length comparison, checked before the engine runs and naming the tests that would not have run (search `bin/arch_mutants/arch_mutants.ml` for `missing_from_executed`, defined near `:136` and enforced near `:1880` at the time of writing) — and added a tezt case, while giving it neither acceptance criterion nor CHECK row, so a round-2 finding was closed in code and left open in traceability. Both now exist: **AC-39 / CHECK-45**.
- **FR-004** [US-1]: When the engine command cannot be resolved, the driver MUST exit 2 naming the engine and the profile, and MUST NOT write a campaign row.

#### Persistence (US-2)

- **FR-005** [US-2]: The schema MUST gain `mutant_campaigns`, `mutants`, `mutant_runs` and `mutant_kills`, and MUST NOT reuse the name `mutation_sites`, which already denotes imperative writes.
- **FR-006** [US-2]: `mutants` MUST be unique on `(file_path, line, col_start, col_end, replacement, source_hash)` and MUST accept a NULL `function_name` for a mutant the index cannot map. **Amended in review round 3** — see the clarification table: the `function_id` foreign key and its index were removed because a `functions(id)` reference cannot resolve on the flat schema this tool must also read, and a column whose declared referential action can never fire is a schema documenting a transition no run can produce. `Arch_mutant_db.open_and_migrate` now issues `PRAGMA foreign_keys = ON` (OFF by default, per connection), which is meaningful precisely because every remaining foreign key points at a table the migration itself creates.
- **FR-007** [US-2]: `mutant_kills` MUST hold a row only for a (campaign, mutant, test) pair whose attribution is actually known; the system MUST NOT infer attribution from an executed set of size greater than one.
- **FR-008** [US-2]: A re-run MUST insert new `mutant_campaigns` and `mutant_runs` rows and MUST NOT update or delete any prior row.
- **FR-009** [US-2]: The schema version MUST be bumped by one minor step at implementation time, read from `lib/arch_index/arch_index_db.ml` rather than hard-coded from this spec, and `docs/schema.md` MUST gain the corresponding row.

#### Verdict soundness (US-3)

- **FR-010** [US-3]: Each `mutant_runs` row MUST carry `selection_provenance ∈ {proved_superset, top_bounded, no_contract}`, constrained by a CHECK.
- **FR-011** [US-3]: The published verdict MUST be computed, never stored, as: KILLED or TIMEOUT → `KILLED`; ERROR → `ERROR`; SURVIVED with `proved_superset` → `SURVIVED`; SURVIVED with `top_bounded` → `UNKNOWN`; SURVIVED with `no_contract` → `UNKNOWN_NO_CONTRACT`.
- **FR-012** [US-3]: `selection_provenance` MUST be `proved_superset` only when the test cone holds no ⊤ edge **and** the index carries a soundness contract, reusing the `proof` binding — `let proof = escapes = [] && sound` — rather than recomputing it. **Search `bin/arch_mutants/arch_mutants.ml` for the literal `let proof = escapes = [] && sound`, one line below the `sound` half; `:221` at the time of writing.** The row said "cite the binding" and then supplied `:122` anyway, which by review round 3 was stale by 99 lines. The coordinate is now a HINT and the binding text is the ANCHOR: the next insertion above it makes the hint imprecise rather than wrong, and imprecise is recoverable — a wrong line number sends a reader to real code that is not the code meant, and they believe it.
- **FR-013** [US-3]: No report, view, or JSON output MUST expose the **stored** `engine_status` without the accompanying `selection_provenance` in the same record. **THE CARVE-OUT IS RETRACTED IN REVIEW ROUND 3; its premise is now false.** It read: `arch-mutants report`'s `unmapped` records carry a status read straight out of the engine's own file, there is no campaign behind them and "therefore no provenance in existence to accompany them", so the path is excluded. Round 3's own fix to `report` gave those records one. Search `bin/arch_mutants/arch_mutants.ml` for the `("unmapped",` key inside `report`'s JSON emitter (`:654` at the time of writing — a hint, not the anchor): each unmapped record now carries `selection_provenance`, `verdict` and `verdict_basis` beside its `status`, and the text rendering prints the verdict too. There is no longer a record in this system that cannot carry its provenance, so **FR-013 applies without exception** and the unmapped path is inside it, not outside. **What this leaves open, recorded here rather than fixed, because `scripts/` is another block's scope this round:** the exclusion is still written into `scripts/check-status-provenance.sh`'s header (search for "emits (\"status\", …) read straight out of the ENGINE's own report file", `:24-27` at the time of writing) and the guard's key regex still names `engine_status` while the unmapped record's key is `status` — so the record the requirement now covers is invisible to CHECK-7, CHECK-22 and CHECK-30, the three checks bound to AC-10. A positive control was executed here, not quoted from a summary: a copy of `bin/arch_mutants/*.ml` with `selection_provenance`, `verdict` and `verdict_basis` deleted from the unmapped record leaves `scripts/check-status-provenance.sh` at **exit 0**, printing `inspected 26 JSON record(s) … PASS — 0 offending emitter(s)`. CHECK-22 and CHECK-30 are worse than blind to it: both build their own fixtures and neither reads `bin/arch_mutants/` at all, so no edit to the driver can move either one. Only `checks/unmapped-survivor-carries-its-verdict.js` — which drives the real `report` — can fire. **This is an open finding for a later round: the guard must widen its regex and drop the header exclusion.** Until it does, the property is traceable through CHECK-43, which is bound to AC-10 for exactly that reason — an AC whose only checks cannot see the record is an AC with no check.
- **FR-014** [US-3]: A mutant with no `mutant_runs` row in a campaign whose `completed_at` is NULL MUST be reported PENDING, and MUST NOT be reported SURVIVED.
- **FR-015** [US-3]: The system MUST NOT emit any mutation score, ratio, percentage, or threshold.

#### Diff scoping (US-4)

- **FR-016** [US-4]: With `--diff <range>`, selection MUST be the union of mutants inside functions the range touches and mutants inside every function reached by a test the range modified or added.
- **FR-017** [US-4]: For a test the range deletes, selection MUST include every mutant a prior campaign attributed to that test alone, and MUST report separately every mutant whose attribution was never known.
- **FR-018** [US-4]: Mutants selected through a bounded test reach MUST carry the same `selection_provenance` rules as any other mutant; there is no separate accounting.

#### Per-added-test verdict (US-5) — DEFERRED to slice 4

None of FR-019..FR-022 is implemented. They are requirements on slice 4 and MUST NOT be read as
statements about this deliverable's binary.

- **FR-019** [US-5]: A test added by the range MUST appear on the defect list only when every mutant in its reach that was attempted in this campaign published `SURVIVED`. **[DEFERRED — slice 4; not implemented in this deliverable.]**
- **FR-020** [US-5]: A test whose attempted reachable mutants all published `UNKNOWN` MUST NOT appear on the defect list and MUST be reported as unproven. **[DEFERRED — slice 4; not implemented in this deliverable.]**
- **FR-021** [US-5]: A test reaching no indexed function MUST be reported in its own bucket and MUST NOT appear on the defect list. **[DEFERRED — slice 4; not implemented in this deliverable.]**
- **FR-022** [US-5]: When the defect list is empty, the report MUST state how many added tests were examined and what would have placed one on the list. **[DEFERRED — slice 4; not implemented in this deliverable.]**

#### Profiles (US-6) — FR-023..FR-025 DEFERRED to slice 5

FR-023, FR-024 and FR-025 are not implemented; they are requirements on slice 5. FR-026 is a
prohibition and is not deferred: the mutation layer writes no `analysis_coverage` row today.

- **FR-023** [US-6]: A test-invocation profile MUST declare `granularity ∈ {case, group, suite}`; a profile missing it MUST abort loading with exit 2 naming the file and the key. **[DEFERRED — slice 5; not implemented in this deliverable.]**
- **FR-024** [US-6]: A profile MAY declare `reach_source ∈ {graph, dynamic}`. A dynamic source MUST only add tests to a selection and MUST NOT remove any. **[DEFERRED — slice 5; not implemented in this deliverable.]**
- **FR-025** [US-6]: A language with no profile MUST report `mutation: not_analysed` and MUST NOT produce an empty campaign result. **[DEFERRED — slice 5; not implemented in this deliverable.]**
- **FR-026** [US-6]: The mutation layer MUST NOT write to `analysis_coverage`, whose rows are owned and replaced wholesale by `arch-coverage-matrix`. It holds today — `grep -rn analysis_coverage bin/arch_mutants/ mutants-schema-migration.sql` returns nothing, re-run in review round 3 with the same empty result — and it now has an acceptance criterion, **AC-46**. **AC-46 has NO CHECK row, and that is stated rather than papered over**: the guard it needs is a grep of the same shape as `scripts/check-no-score.sh`, and `scripts/` and `checks/` were another block's scope this round. A prohibition verified only by a grep somebody remembers to run is exactly the structural gap AC-29 diagnoses as the reason FR-015's guard could read PASS while scanning a third of the file. **Open for a later round: write the guard, give it a CHECK-N, red-verify it against a fixture that inserts an `analysis_coverage` row.**

#### Campaign self-certification (US-1, US-3)

- **FR-027** [US-1]: A campaign in which **no** mutant was killed MUST be reported as
  **self-uncertified**, and the report MUST state that such a campaign cannot distinguish a weak
  test suite from a stale or wrong binary. A campaign containing at least one kill is
  self-certifying, because a stale binary is unmutated and therefore cannot produce a kill.
- **FR-034** [US-3]: `PENDING` is derived from the absence of a `mutant_runs` row, but **no table
  records which mutants a given campaign catalogued**, so the only derivable universe is the global
  `mutants` site table. On a database holding one campaign that is exactly right; on a database
  holding two campaigns over different mutant sets, an open campaign would report the **other**
  campaign's sites as `PENDING`. Until a catalogue link exists, the verdict surface MUST **refuse**
  — exit 3, refused, naming the ambiguity — when it is asked for an open campaign in a database
  that holds more than one campaign. It MUST NOT answer a question it cannot answer correctly.
  Closing this properly needs a `campaign_id` on a catalogue table or a `mutant_campaign_sites`
  join, which is a schema change and therefore a version bump.
- **FR-033** [US-3]: A published verdict MUST carry the `selection_provenance` **of the run row that
  produced it**, joined by identity, never the first provenance available in any collection. Where
  the schema carries no link between a reported finding and the run that produced it, the honest
  answer is `null` — never the first row. Measured precedent in this repository the same day: a
  `match producers with p :: _` labelled every finding with the **first** run's soundness class, so
  a heuristic finding carried `sound_with_top` merely because the sound run happened to sort first.
  Positional attribution is indistinguishable from correct attribution on any fixture whose
  collection has one element, which is every fixture anyone writes first.
- **FR-031** [US-2, US-3]: Wherever the campaign consumes a closed vocabulary that a schema `CHECK`
  constraint declares — `selection_provenance`, the engine status set, `top_reason`, edge `kind` —
  the OCaml consumer MUST use a **total** match with no `| _ ->` catch-all, so the compiler fails
  when a member is added later. A value added to an existing column's vocabulary is dropped by a
  filtering consumer **with no error at all**: no crash, no log, only a smaller answer. Every
  defence built for the missing-column case is blind to this one — a column-existence guard, a
  capability record and a refusal all see a column that is present and a match arm whose domain no
  longer covers it. Measured precedents in this repository: `top_reason = 'ambiguous_unit'` arrived
  at schema 1.9 and `form = 'inferred_bind'` at 1.8. Where the filter must live in SQL rather than
  in OCaml, the migration gesture is to grep for the **members**, never for the column name.
- **FR-032** [US-1]: The driver MUST treat a subprocess **exit code 3 as "refused"** — the callee
  declined to answer — and MUST NOT collapse it into a failure or into an empty result. This is the
  transport for FR-029's distinction: `Arch_db.ok` is being changed to return 3 rather than 2 on a
  missing column, so "did not really run" arrives as a distinct code the campaign can propagate
  instead of confusing it with "ran and found nothing".
- **FR-030** [US-1]: The campaign MUST refuse to run when a binary it resolves lies **outside** the
  working tree it was invoked from, unless an environment override names a path that exists. This
  is a structural guard, not a documented precaution: on 2026-09-05 an agent briefed specifically
  about this hazard worked inside the checkout anyway, because the warning was one paragraph inside
  a long brief. A refusal that fires is worth more than a paragraph that is read.
- **FR-029** [US-1]: A campaign with no kills MUST distinguish "ran and everything survived" from
  "nothing meaningfully ran" — a campaign composed entirely of `ERROR` outcomes, or of mutants
  never attempted, has zero kills for a different reason and MUST NOT be reported in the same
  words as an all-survivor campaign.
- **FR-028** [US-1]: The campaign record MUST carry the resolved engine binary path and the
  resolved test-runner binary path, so a reader can tell which artefact actually ran.

## Acceptance Criteria

- AC-1 [US-1 happy path]: a two-mutant plan drives exactly two stub invocations, each carrying the declared executed set → recorded argv matches.
- AC-2 [US-1, C-1]: a `group`-granularity profile executes a superset and records both sets → `executed_superset` true, intended set preserved.
- AC-3 [US-1, C-2]: engine absent → exit 2, no campaign row written.
- AC-4 [US-2 happy path]: a completed three-mutant campaign writes 1 campaign, 3 mutants, 3 runs → counts match.
- AC-5 [US-2, C-5]: a second campaign over unchanged code adds campaign and run rows but no `mutants` rows → site count unchanged.
- AC-6 [US-2, C-6]: a mutant with an executed set of size > 1 that is killed writes no `mutant_kills` row → attribution not invented.
- AC-7 [US-3 happy path]: closed cone plus contract, SURVIVED → published `SURVIVED`, provenance `proved_superset`.
- AC-8 [US-3, C-9]: ⊤ in the test cone → published `UNKNOWN`; no contract → published `UNKNOWN_NO_CONTRACT`; stored status `SURVIVED` in both.
- AC-9 [US-3, C-18]: a KILLED under `top_bounded` still publishes `KILLED` → a kill is not weakened by provenance.
- AC-10 [US-3, C-7]: no output path exposes a status without its provenance → grep of every emitter finds no lone status field.
- AC-11 [US-2/US-3, D7]: an interrupted campaign reports its unattempted mutants PENDING → never SURVIVED.
- AC-12 [US-4 happy path]: a diff touching only a test helper selects mutants in the code that helper's tests reach.
- AC-13 [US-4, C-11]: a comment-only change inside a production function still selects that function's mutants → over-selection, stated.
- AC-14 [US-5 happy path]: a tautological added test appears on the defect list; a real-postcondition test does not. **[DEFERRED — slice 4; no check runs today.]**
- AC-15 [US-5, C-13]: an added test whose reachable mutants are all UNKNOWN is reported unproven, not defective. **[DEFERRED — slice 4; no check runs today.]**
- AC-16 [US-5, FR-022]: an empty defect list prints the examined count and the criterion → no bare zero. **[DEFERRED — slice 4; no check runs today.]**
- AC-17 [US-6, C-16]: a profile without `granularity` aborts with exit 2 naming the file and the key. **[DEFERRED — slice 5; no check runs today.]**
- AC-18 [US-6, FR-025]: a language with no profile yields `not_analysed`, not an empty result. **[DEFERRED — slice 5; no check runs today.]**
- AC-19 [P4]: the `mutants` uniqueness key is probed on the largest available population, and the probe counts rejected rows because the key is a UNIQUE constraint.
- AC-20 [C-22]: the mutaml integration is exercised against a real mutaml, or the report states it is unverified — never silently assumed.
- AC-21 [FR-027]: an all-survivor campaign prints "self-uncertified" and names the reason → an entirely green campaign never reads as evidence.
- AC-22 [FR-028]: the campaign record names the resolved engine and runner paths → a reader can tell which binary ran.
- AC-28 [FR-034]: asked for an open campaign in a two-campaign database, the verdict surface exits 3 naming the ambiguity → it never reports another campaign's sites as pending.
- AC-27 [FR-033]: a report over two runs of differing provenance labels each finding with its own run's provenance → swapping the collection order changes no label.
- AC-25 [FR-031]: adding a member to a CHECK-declared vocabulary without updating its consumer fails the build → the next addition cannot be dropped silently.
- AC-26 [FR-032]: a subprocess exiting 3 is reported as refused, distinctly from a failure and from an empty result → "did not really run" survives the process boundary.
- AC-24 [FR-030]: a binary resolved through an ancestor directory outside the tree makes the campaign refuse, exit 1 → the stale-parent-binary case cannot silently produce a page of survivors.
- AC-23 [FR-029]: an all-ERROR campaign and an all-survivor campaign print different reasons for having no kills → "didn't really run" is never dressed as "ran and found nothing".
- AC-30 [FR-031]: the wrapper refuses with a reserved exit code, and the driver maps exactly that code — no range, no catch-all — to a NOT-ATTEMPTED outcome that is never a kill, never eligible for attribution, and leaves `completed_at` NULL → a wholly broken selection can no longer be reported as a campaign of clean kills. Reserved code: **99**. The codes already spoken for are 0 (mutaml "passed" = SURVIVED), 124 (GNU `timeout`, which mutaml wraps every test in), 126 (found, not executable), 127 (command not found, fatal to mutaml) and 128+n (killed by signal). 99 is outside all of them and below 126.
- AC-31 [FR-007]: a mutant for which the wrapper wrote no trace line has an **unobserved** executed set — no run row, no kill row under any attribution, its count published in BOTH output formats, and the campaign not stamped `completed_at` → a per-test attribution can never name a test that was not observed running.
- AC-32 [FR-013, FR-011]: `report` prints no survivor without its selection provenance — in the document AND on every survivor record, in both formats — and `--fail-on-survivors` exits 1 only when the derived verdict is `SURVIVED`; the same engine report over a ⊤-bounded index publishes `UNKNOWN` and does not fail the gate.
- AC-33 [FR-031]: a generic NDJSON record whose `status` is outside `KILLED | SURVIVED | TIMEOUT | ERROR | REFUSED` aborts (exit 2) naming the string, and is counted in no bucket; the five legal values still load and still bucket.
- AC-34 [FR-013, FR-018]: a prior campaign's `engine_status` is never read without its `selection_provenance`; a SURVIVED recorded under `top_bounded` is reported UN-RECHECKABLE by `--diff`, while a SURVIVED under `proved_superset` is not.
- AC-29 [FR-015]: no output path emits a score, ratio, percentage or threshold, and the check that says so reports the lines it actually scanned → a guard that stopped scanning cannot report the coverage it did not have. FR-015 had no acceptance criterion and no CHECK-N at all until review round 1; the gap is why its guard could read PASS while scanning 789 of `arch_mutants.ml`'s 2215 lines (measured; the repaired scanner reaches 1813).

**AC-35..AC-46 were added in review round 3.** Round 3 fixed a CRITICAL and five HIGHs, added seven
tezt cases and six ratchet checks, and gave none of them an acceptance criterion — so the work that
defends this deliverable's worst failure modes was reachable from no row of the traceability graph.
Seven requirements also stood with no criterion at all (FR-003, FR-009, FR-010, FR-017, FR-021,
FR-024, FR-026); each now has one, and where the criterion has no runnable check that fact is
written down rather than left as an absence a reader would have to notice.

- AC-35 [FR-006, FR-007]: an engine outcome reaches the catalogued site it actually belongs to — matched by the engine's own id cross-checked against file and line, failing that by the full site key (path, line, column span, replacement), and where two candidates survive both, REFUSED → two mutants on one line keep their own verdicts, and no `mutant_kills` row names a test for a site chosen by list order.
- AC-36 [FR-016, FR-029]: a `--diff` whose narrowing leaves zero mutants is REFUSED before any campaign row is written; a report entry matching no catalogued site leaves `completed_at` NULL; a wrapper refusal whose entry matched nothing is still counted → an empty read is never a clean read.
- AC-37 [FR-016]: `arch-impact` entries whose `name` field the reader cannot understand are COUNTED and refused, never dropped by a filter into a silently smaller touched set → a set shrunk from twelve to three is distinguishable from a correct three.
- AC-38 [FR-032]: a test command that genuinely exits 99 reaches the database as an OUTCOME, while a wrapper refusal — 99 with no trace line — is still a refusal → the reserved code cannot turn a real test failure into a mutant that can never be killed. The discriminator is the trace line, and it applies to the mutaml path only, where REFUSED is inferred from a raw code rather than written explicitly.
- AC-39 [FR-003]: a selection whose executed set omits any intended test is REFUSED before the engine runs, naming the tests that would not have run → FR-003 is enforced by inclusion, never by comparing two lengths.
- AC-40 [FR-002]: a test name carrying a comma, tab or newline is refused rather than written, and a prime-suffixed name (`aux'`) runs to completion → the safety allowlist refuses what it cannot pass, and nothing else.
- AC-41 [FR-009]: the schema version is read from `lib/arch_index/arch_index_db.ml` rather than restated from this spec, and `docs/schema.md` carries the row for it, saying what the version does and does not gate. **No CHECK row: nothing in this repository verifies that the doc row exists or that it is honest.** Open for a later round.
- AC-42 [FR-010]: every `mutant_runs` row a completed campaign writes carries a `selection_provenance` inside the CHECK-constrained set → a stored status without a stored provenance is not representable.
- AC-43 [FR-017]: a range that deletes a test re-selects every mutant a prior campaign attributed to that test alone, keyed on the full site key, and names separately every mutant whose attribution was never known → a deletion's blast radius is never silently skipped.
- AC-44 [FR-021]: a test reaching no indexed function is reported in its own bucket and never on the defect list. **[DEFERRED — slice 4; no check runs today.]**
- AC-45 [FR-024]: a `dynamic` reach source only ADDS tests to a selection and removes none, and a source returning less than the graph is stated in the report. **[DEFERRED — slice 5; no check runs today.]**
- AC-46 [FR-026]: the mutation layer writes no `analysis_coverage` row. **No CHECK row** — see FR-026 for why, and for what closing it needs. Open for a later round.

## Edge Cases

- EC-1 [US-1]: a target with a provably empty reaching set inside a closed cone → the engine runs with an empty test set and the result is a genuine, provable test gap, recorded `SURVIVED` under `proved_superset`.
- EC-2 [US-1]: the engine disappears mid-campaign → the campaign stays open (`completed_at` NULL), completed mutants keep their rows, the rest are PENDING, exit 2.
- EC-3 [US-2]: two campaigns write concurrently → each holds its own campaign id; SQLite's write lock serialises them; no row is shared, so no reconciliation is needed.
- EC-4 [US-2]: a mutant's function is deleted between campaigns → the `mutants` row is retained, its `function_name` no longer resolves against the index, and it is reported as stale rather than deleted or errored. (Amended in review round 3 from `function_id`, a column removed as unpopulatable; the staleness is the same fact, read off the name.)
- EC-5 [US-3]: `no_contract` is produced by an index whose producer never stamped a soundness contract, distinct from a contract that exists and whose cone escapes.
- EC-6 [US-3]: KILLED under `top_bounded` → published KILLED, and the report notes the guarantee rests on an incomplete selection, since a stronger selection could only have killed it too.
- EC-7 [US-4]: a brand-new test with no campaign history → its full reach set is in scope on its first campaign.
- EC-8 [US-4]: a deleted test whose mutants had unknown attribution → reported as un-recheckable, never silently skipped.
- EC-9 [US-5]: an added test whose reachable mutants all came back ERROR → not defect-eligible; ERROR is inconclusive, reported in the unproven bucket. **[DEFERRED — slice 4.]**
- EC-10 [US-6]: a malformed profile → exit 2, distinct from the absent-profile `not_analysed` path. **[DEFERRED — slice 5.]**
- EC-11 [US-6]: a test node the profile's template cannot render → exit 2 naming the node and the profile, never a silently skipped test. **[DEFERRED — slice 5.]**
- EC-12 [US-2]: a partial campaign read by reporting tooling → included, labelled partial, with its PENDING count stated.

## Runnable Checks

Exit convention: **0** = check passes · **1** = an assertion fired · **2** = harness error, the
check could not run · **3** = REFUSED — the check declined to answer, or selected nothing to
answer about. 3 is not folded into "error", and the distinction is the one FR-032 exists to carry
across the process boundary: `scripts/check-mutaml-integration.sh` exits 3 when the real engine is
absent, and `tezt` exits 3 when `--title` matches no test. **A row whose command exits 3 is a check
nobody can run from this spec** — it is how CHECK-1 came to name a tezt title that does not exist
and still read as green, since a stale title selects nothing and tezt reports 3, not a failure.
Every row below was executed at the head of this branch and its exit code recorded in
`briefs/mutation-campaign-313-impl.md`'s Group C outcome.

Tests are tezt cases in `tezt/tests/mutants.ml`, following the existing
`Test.register ~__FILE__ ~title ~tags` pattern and the shared `Fixture.flat` /
`Fixture.malformed_contract` helpers.

**The runnable command for a tezt case is the built binary with `--title`, never `dune test
--force`.** `dune test` aborts at the first failure: this branch's own brief records a run
reporting 156 of 217 with 61 never executed and nothing saying so, which is a gate that reads a
partial run as a whole one. Nine rows named it before review round 3; they now name
`./_build/default/tezt/tests/main.exe --title "<exact title>"`, which runs the one case and
returns 0, 1 or 3. Run `dune build` first — the rows do not repeat it.

**Node ratchet checks take NO argument.** `checks/tree-boundary-non-git-checkout.js` resolves the
repository root from `process.argv[2]` and then spawns `_build/default/bin/arch_mutants/…` with a
different working directory, so a RELATIVE argument — `node checks/tree-boundary-non-git-checkout.js .`
— fails to spawn and the check exits **2** while reporting `plan failed … undefined`. Measured, and
the argument-less form exits 0. The other ten node checks tolerate `.` today only because they
never change directory before spawning; the argument-less form is correct for all of them.
**Open for a later round: `path.resolve` that argument at the point it is read.**

- CHECK-1 [AC-1, AC-4, AC-5, AC-6, AC-42] (authentic-success-path): `./_build/default/tezt/tests/main.exe --title "mutants: run drives the wrapper once per mutant with the declared set"` → exit 0 — asserts the stub's recorded argv. **The title was wrong until review round 3, and wrongly in the direction that hides it**: the row said "drives the ENGINE", the case says "drives the WRAPPER" — the distinction FR-001 turns on — and a `--title` that matches nothing makes tezt exit **3**, so following this row produced no red and no failure, just a check that ran nothing. Its case also carries the only assertions for AC-4 (1 campaign, 3 mutants, 3 runs), AC-5 (a re-run adds campaign and run rows and no `mutants` rows), AC-6 (a kill under a non-singleton executed set writes no `mutant_kills` row) and AC-42 (every run row carries a provenance in the constrained set); all four were asserted here and traced nowhere.
- CHECK-2 [AC-2]: `./_build/default/tezt/tests/main.exe --title "mutants: a group-granularity profile executes a superset and says so"` → exit 0.
- CHECK-3 [AC-3] (fail-closed-path): `./_build/default/tezt/tests/main.exe --title "mutants: run with no engine exits 2 and writes no campaign"` → exit 0.
- CHECK-4 [AC-7, AC-8, AC-9]: `./_build/default/tezt/tests/main.exe --title "mutants: one engine report, three indexes, three published verdicts"` → exit 0, reusing `Fixture.malformed_contract` for the `no_contract` arm. **Each arm must be proved reachable by its own fixture, and red-verified separately**: removing the expected verdict from ONE arm must fail that arm's assertion and no other. A three-arm assertion over a fixture that can only produce one arm passes while checking one third of what it claims — this failure mode was observed the same day in a peer's gate, where a closed-cone fixture made the `UNKNOWN` branch, the one every real index produces, unreachable by the test that claimed to cover it.
- CHECK-5 [AC-11]: `./_build/default/tezt/tests/main.exe --title "mutants: an interrupted campaign reports PENDING, never SURVIVED"` → exit 0.
- CHECK-6 [AC-14, AC-15, AC-16, AC-44] — **DEFERRED to slice 4, NOT RUNNING TODAY**: `./_build/default/tezt/tests/main.exe --title "mutants: the killed-nothing list excludes unproven tests and states its criterion when empty"` → exit **3** today, because the title selects nothing. No such tezt case exists; US-5 is unimplemented, so this row describes a check slice 4 will add, not one that passes now.
- CHECK-7 [AC-10]: `scripts/check-status-provenance.sh` — scans every emitter in `bin/arch_mutants/` for a status field written without a provenance field in the same record; exit 1 on any hit. Self-contained, no test runner. **Its repair reintroduced its own vacuity in a new form, and that is now guarded too.** The character tokenizer that replaced the line-oriented scan had no end-of-file guard: a single OCaml char literal holding a double quote — `'"'`, ordinary code, ordinary in a doc comment — opened a string that never closed, so the rest of the file was consumed as string content, the check inspected ZERO records and printed PASS. Measured against a fixture carrying `engine_status` with no provenance: exit 0 with `inspected 0 JSON record(s)`, while the byte-identical fixture minus the comment exited 1. Fixed by tokenizing a char literal as one token (in code AND inside comments, where OCaml also lexes them) and by emitting a hit when the comment depth is non-zero or a string is open at end of file — exactly the two diagnostics `scripts/check-no-score.sh` already emitted, an omission that was inconsistent inside one fix. Ratcheted by CHECK-30.
- CHECK-8 [AC-20]: `scripts/check-mutaml-integration.sh` — runs a real `mutaml-runner` over a two-function fixture and asserts the wrapper resolved `MUTAML_MUTANT` to the right test set. Exit 3 (not 1) when the integration cannot be exercised, so an unverified integration stays distinguishable from a failed one. **The mechanism itself is no longer in doubt** — it was established by reading `src/runner/runner.ml:123-130` and `src/ppx/mutaml_ppx.ml:40`. **AC-20 IS NOW VERIFIED, NOT UNVERIFIED, AND IT TOOK ONE FLAG.** `mutaml-runner` 0.3 resolves `--muts` INSIDE its `--build-context`, which defaults to `_build/default`, so `--muts lib/x.muts` against a scratch fixture was read as `_build/default/lib/x.muts` and the runner exited before the wrapper was ever spawned. Adding `--build-context .` makes the check pass against the real installed engine: with `MUTAML_RUNNER=/mnt/ssd-external-2to/mutaml-pilot/_opam/bin/mutaml-runner` it exits 0 — `runner exited 0 · wrapper invocations : 2 · lib/x:1 resolved to : t_alpha · lib/x:2 resolved to : t_beta,t_gamma`. This was never a fixture limitation. The refusal arm survives the engine becoming available, which is the point of keeping it: exit 3 is now reached two ways, no mutaml at all, or a mutaml this fixture cannot drive (one that does not declare `--build-context`, probed from `--help` before the run), while exit 2 is reserved for an engine whose interface matches and which failed anyway. Before this, naming a real engine could only produce 0, 1 or 2, so an unexercisable integration came back as a harness error.
- CHECK-9 [AC-19]: `scripts/check-mutant-key.sh <db>` — inserts the campaign's mutants and reports the count of rows **rejected** by the UNIQUE constraint, not a `GROUP BY` count, because under a constraint a duplicate never becomes a group. Run against the largest population available and print the population size and the working tree with the count. **It was vacuous and could not go red.** All three of its statements still named `function_id`, a column round 2 deleted from `mutants-schema-migration.sql`, so sqlite3 aborted each INSERT with `no column named function_id` BEFORE the constraint was consulted — and the script read the resulting zero-rows-inserted as the constraint rejecting the row, printing `the key is live and discriminating`. Positive control executed: against a probe schema whose UNIQUE line had been deleted, so `sqlite_master` showed no UNIQUE at all, it exited 0 with the same sentence. Fixed by dropping the stale column AND, the half that survives the next schema change, by checking sqlite3's own exit status on every INSERT: `INSERT OR IGNORE` swallows a constraint violation and nothing else, so a non-zero status means the probe never ran and is exit 2 — a harness error, never a rejection and never a pass. Re-verified red: with the UNIQUE line removed from the probe schema it now exits 1 (`a row identical on (file_path, line, col_start, col_end, replacement, source_hash) was ACCEPTED`), and with a bogus column name it exits 2. Ratcheted by CHECK-31.
- CHECK-19 [AC-28]: `./_build/default/tezt/tests/main.exe --title "mutants: the verdict refuses an open campaign it cannot scope"` → exit 0. The fixture MUST hold two campaigns over different mutant sets; a single-campaign fixture cannot distinguish the refusal from the correct answer.
- CHECK-18 [AC-27]: `./_build/default/tezt/tests/main.exe --title "mutants: provenance follows the run, not the collection order"` → exit 0. The fixture MUST contain **at least two** runs of differing provenance, and the test MUST assert that reversing their order changes no published label. A single-run fixture cannot distinguish positional attribution from correct attribution.
- CHECK-17 [AC-25]: `scripts/check-total-matches.sh` — greps the campaign's consumers for a `| _ ->` arm on any vocabulary a schema `CHECK` declares, and fails naming the site. Self-contained. This is a lint, not a proof: the real defence is the total match itself, which the compiler enforces.
- CHECK-16 [AC-12, AC-13]: `./_build/default/tezt/tests/main.exe --title "mutants: a diff touching only a test helper selects mutants in the code that helper's tests reach"` → exit 0. Added because the runnable-check table had no entry for US-4 at all: the story had acceptance criteria and no automated check, which the architect voice caught. A story whose only verification is an AC read by a human is a story that ships unverified.
- CHECK-15 [AC-24]: `scripts/check-binary-provenance.sh` → builds two nested-checkout fixtures and runs the REAL driver inside each: an inner tree with no `scripts/mutaml-wrapper.sh` inside an outer directory that has one, and an inner tree with no `_build` inside an outer directory whose `_build/default/bin/arch_impact/arch_impact.exe` the ancestor walk reaches. Each must make `arch-mutants run` exit 1 AND name the outside path; an exit code alone cannot tell a fired guard from an unrelated failure. **The earlier claim on this line — "already implemented and red-verified on both detection branches" — was false.** The script probed four hardcoded `_build` paths from the tree root and never invoked `arch-mutants`, so it could not observe FR-030's absence, and FR-030 was absent: `locate_wrapper` and `locate_impact` both walked ancestors with no tree-boundary check. **The rewritten check FAILED (exit 1) until the driver implemented FR-030 in review round 2; it now PASSES both probes.** Search `bin/arch_mutants/arch_mutants.ml` for `let locate_wrapper` and `let locate_impact` — `:1184` and `:1276` at the time of writing, and the coordinates are HINTS: this row previously carried `:787` and `:875`, which were correct when written and are now stale by roughly four hundred lines, landing a reader in unrelated code they have no reason to disbelieve. **The boundary this row described was retracted by round 3 and is restated here from the implementation, not from the earlier sentence.** It is no longer `git rev-parse --show-toplevel` with a working-directory fallback. It is the NEARER of two anchors, plus a third that claims nothing: (a) the git toplevel; (b) the checkout's own root, found as the nearest `dune-project` above the working directory — search for `let marker_root` and `let working_tree_root`; and (c) where neither answers, the invocation directory, whose refusal message explicitly DISCLAIMS any nesting rather than asserting one. Anchoring on git alone made `git init` — not the layout — decide whether the guard fired at all, since a checkout that is not itself a repository resolves its toplevel to the OUTER repo and the boundary then spans both trees; the old sentence described that benign configuration and asserted it of the hazardous one. Both anchors being ancestors of the working directory, "nearer" is the longer path — but **the marker narrows only when the git repository does NOT TRACK it**, and that clause was absent until review round 4. Without it the deeper boundary does not merely narrow what the campaign may reach; it refuses the repository's OWN artefact whenever a checkout carries a tracked nested `dune-project`. This repository carries one, `poc/decision-lint/dune-project`, so `arch-mutants run` invoked from that directory exited 1 against its own `scripts/mutaml-wrapper.sh` and reported that the wrapper "belongs to a different tree" — a false refusal carrying a false reason, git tracking both paths and saying so. A tracked marker is a sub-project of THIS checkout; an untracked one is the unpacked tarball or out-of-tree copy FR-030 exists for. Search for `let tracked_by`. The untracked answer is the conservative one, so a `git` that cannot be run at all can only make the guard refuse more, never less. Ratcheted by CHECK-51. Refusal is exit 1 naming the outside path, and the DIAGNOSIS is chosen by which anchor answered — see `type tree_anchor`. Only the ancestor walk is guarded: a PATH hit for `arch-impact` is an installed binary the operator put there, which is the same kind of explicit choice as an override. An environment override naming a path that exists is deliberately not probed: FR-030 exempts it. Requires `sqlite3`, `git`, and `dune build`. Ratcheted by CHECK-23.
- CHECK-14 [AC-21, AC-22, AC-23]: `./_build/default/tezt/tests/main.exe --title "mutants: a campaign with no kills is self-uncertified, and says WHY it has none"` → exit 0. AC-23 is added to this row in review round 3: the case asserts the all-ERROR and all-survivor reasons on hand-counted per-status numbers, which is AC-23 entire, and it was traced nowhere. **AC-22's half was declared here and asserted nowhere until review round 3**: the test checked the certification tag and the counts, and nothing read `engine_path` or `test_runner_path` at all. It now asserts that the report names the fixture's OWN engine stub (compared against the path, not merely checked non-empty, which a hardcoded `/usr/bin/false` would satisfy), that the test runner is what `command -v` independently resolves, and that the STORED campaign row agrees with the report — because a reader who opens the database gets the row, not the report. Positive control, on a copy: rewriting the resolved path to `/usr/bin/false` fires `the report names the engine binary that actually ran: got "/usr/bin/false"`, and passing a different value to `insert_campaign` fires `the stored campaign row carries the same engine_path as the report: got "/nope"`. This closes the failure mode issue #77 describes: `tezt/lib/arch_tezt.ml`'s `locate` walks ancestors from the working directory, so an incomplete `_build` silently runs the parent checkout's binary. That binary is unmutated, every mutant survives, and the report becomes a page of false test gaps that looks exactly like a real finding.
- CHECK-11 [P1, P2, P3]: `quint typecheck specs/mutation-campaign-313.qnt && quint run specs/mutation-campaign-313.qnt --invariant=allInvariants --max-samples=20000 --max-steps=12` → no violation. Executed on quint 0.32.0; the ITF trace is committed so `ocaml-quint-connect` can replay without quint present at CI time.
- CHECK-12 [P2]: `yes | quint verify specs/mutation-campaign-313.qnt --temporal=p2ExecutedIsMonotoneOverTime --max-steps=6` → no violation. **Bounded and caveated**: Apalache documents its temporal support as experimental, and TLC rejects this shape because a `[]` over an action requires the `[A]_v` subscripted form, which Quint does not emit here.
- CHECK-13 [P1, P2, P3]: `scripts/check-quint-red.sh` → 6/6 injected defects must turn a NAMED invariant red. A `sed` that matches nothing counts as a failure, so a stale mutation cannot pass as a green check. **This check is why the others are trustworthy**: on its first run it exposed one invariant as vacuous.
- CHECK-10 [AC-17, AC-18, AC-45] — **DEFERRED to slice 5, NOT RUNNING TODAY**: `./_build/default/tezt/tests/main.exe --title "mutants: a profile without granularity aborts; a language without a profile reads not_analysed"` → exit **3** today, because the title selects nothing. No such tezt case exists; US-6 is unimplemented, so this row describes a check slice 5 will add, not one that passes now.
- CHECK-20 [AC-29]: `scripts/check-no-score.sh` — scans every `.ml` under `bin/arch_mutants/` for a literal `%%`, for score/ratio/percent/threshold inside a string literal, and for float arithmetic; exit 1 on any hit. Self-contained, no test runner. **FR-015 had no CHECK-N at all** — the script existed and the spec never pointed at it, which is how nobody noticed it had stopped working. Its comment stripper treated `(*` inside a SQL string literal as a comment opener (search `bin/arch_mutants/arch_mutants.ml` for `count(*) FROM mutant_kills`, `:1521` at the time of writing — the coordinate this row carried, `:1024`, is stale by roughly five hundred lines), leaving end-of-file depth 3 and 1426 of that file's 2215 lines with no code left to scan; a scoring `Printf.printf` injected at line 1685 — a literal `%%` AND the word `score`, the two hits the guard's own header names — produced exit 0 and "PASS — 0 offending site(s)". Fixed by consuming string literals before recognising comment delimiters, and the summary now reports lines SCANNED at depth 0 rather than physical lines read. Ratcheted by CHECK-21.
- CHECK-21 [AC-29]: `checks/no-score-scans-sql-strings.sh` — builds a fixture holding a SQL literal with `count(*)` followed by a scoring `Printf.printf`, runs `scripts/check-no-score.sh` over it, and requires exit 1 naming the percent sign. Red-verified: against the pre-fix guard restored from HEAD it exits 1, and the guard it invokes reports "inspected 11 line(s)" while passing.
- CHECK-22 [AC-10]: `checks/status-provenance-per-record.sh` — builds a fixture whose OUTER `` `Assoc `` carries the provenance and whose nested `` `Assoc `` carries a lone `engine_status`, runs `scripts/check-status-provenance.sh` over it, and requires exit 1 naming the INNER record's line. This is the ratchet for CHECK-7, whose record scanner opened a record only at bracket depth 0 and therefore judged the whole outermost blob as ONE record: deleting the per-run record's provenance key still produced PASS — search `bin/arch_mutants/arch_mutants.ml` for the comment `FR-013: this key travels with engine_status, always.` and the `("selection_provenance", …)` line under it, `:2408-2409` at the time of writing; the coordinate this row carried, `:1584`, now lands on an `| Impact_refused ->` arm in an unrelated match, which is exactly the failure mode a bare number has and a content anchor does not. Fixed with a record STACK — a frame at every `` `Assoc ``, each judged on the keys between its own brackets. Red-verified against the pre-fix guard.
- CHECK-24 [AC-30]: `checks/wrapper-refusal-not-a-kill.sh` — asserts that every refusal path of `scripts/mutaml-wrapper.sh` exits exactly 99 (MUTAML_MUTANT unset, an uncatalogued mutant, an unreadable selection file) while a catalogued mutant still exits 0, and then drives a real campaign whose engine stub is a faithful miniature of mutaml's runner: it names an uncatalogued mutant, invokes the test command, and persists the **raw exit code**, which is what mutaml 0.3 actually stores (`src/runner/runner.ml:109-110` saves `{ status = ret; mutant }` over the `status : int` of `src/common/mutaml_common.ml:74` — the strings "passed"/"failed"/"timeout" at `runner.ml:130-135` are PRINTED ONLY and never reach the report). The campaign must end with killed=0, one refusal counted, zero `mutant_runs` rows, zero `mutant_kills` rows and `completed_at` NULL. Self-contained; needs `sqlite3` and `dune build`. **Verified against the real engine, not only the miniature**: mutaml 0.3's own `mutaml-runner` (`/mnt/ssd-external-2to/mutaml-pilot/_opam/bin/mutaml-runner`) was run with the wrapper as its test command over a hand-written `.muts` file, and it PRINTED `Testing mutant lib_x:1 ... failed` while WRITING `[{"status":99,…}]` to `mutaml-report.json` — the printed label and the persisted value disagreeing is exactly the gap the old adapter fell into. Feeding that real report to `arch-mutants run` produces `1 mutant(s) REFUSED by the wrapper (exit 99)`, `0 KILLED`, `1 PENDING` and no attribution. **Red-verified**: against `bin/arch_mutants/arch_mutants.ml` and `scripts/mutaml-wrapper.sh` restored from HEAD it exits 1 with `the wrapper's raw code is what mutaml would persist — expected "status":99, got "status":2` and `a refusal is not a kill — expected 0, got 1`. This is the ratchet for the HIGH found in review round 2: the wrapper refused with `exit 2`, mutaml persisted 2, and the adapter's `Int _ -> KILLED` arm turned a total failure of the selection into self-certifying proof.
- CHECK-25 [AC-31]: `checks/unobserved-executed-set-is-not-an-attribution.sh` — builds an index in which `other` (lib/y.ml) is reached by exactly ONE test, so the planned set for its mutant is the singleton the defect needed, then runs a campaign whose engine exits 0 without ever invoking the wrapper. Requires zero `mutant_runs` rows, zero `mutant_kills` rows, `t_gamma` named nowhere as a killer, `mutants_unobserved_executed_set` = 2, `killed` = 0 and `completed` false. The singleton is asserted as a precondition, not assumed: without it every assertion would pass vacuously. Self-contained; needs `sqlite3` and `dune build`. **Red-verified**: against HEAD it exits 1 with `no kill row is persisted — expected 0, got 1` and `completed_at stays NULL — expected 0, got 1`. This is the ratchet for the HIGH where `Option.value ~default:sel.sel_executed` — three sites, at `arch_mutants.ml:1425-1427`, `:1575` and `:1703` when the finding was written — substituted the PLANNED set for the observed one and wrote `t_gamma / singleton_executed_set` out of zero observed test runs. **The expression no longer exists**: `grep -n 'default:sel.sel_executed' bin/arch_mutants/arch_mutants.ml` returns nothing at the head of this branch, and the observed set now comes from `executed_by_id`, filled from the wrapper's trace file. The three coordinates are kept as a record of where the defect WAS, not as a pointer to live code — a distinction a reader cannot make from a number alone, which is why it is written out.
- CHECK-26 [AC-24]: `checks/tree-boundary-refusal.sh` — the ratchet for CHECK-15, probing the three things `scripts/check-binary-provenance.sh` cannot see, each of which is a way to implement FR-030 wrongly and still pass it. (1) DEPTH: the driver invoked from a SUBDIRECTORY of the nested inner tree must still refuse and name the outer wrapper — a guard anchored on the working DIRECTORY rather than the working TREE gets this wrong. (2) THE EXEMPTION: `ARCH_MUTANTS_WRAPPER` naming an existing path outside the tree must still be honoured, because FR-030 exempts a path the operator named and this repo's own tezt suite depends on it. (3) THE NEGATIVE: a wrapper INSIDE the tree must be accepted — without which "refuse everything" passes CHECK-15 and probe 1 alike. Probes 2 and 3 are the half that matters: a refusal is easy, a refusal that fires exactly when it should is not. Self-contained; needs `git`, `sqlite3` and `dune build`. **Red-verified**: against HEAD it exits 1 on probe 1 (`got exit 0`) while probes 2 and 3 correctly stay green, which is what makes probe 1's failure attributable.
- CHECK-23 [AC-24]: `checks/binary-provenance-invokes-driver.sh` — hands `scripts/check-binary-provenance.sh` a tree whose driver is a stub with no FR-030 refusal, and requires exit 1. This is the ratchet for CHECK-15, whose previous implementation probed four hardcoded `_build` paths and never invoked `arch-mutants` at all, so it exited 0 on a tree where FR-030 had never been written — and it had not been. Red-verified against the pre-fix guard, which reported "0 of 1 resolved binaries lie outside the tree" and exited 0.
- CHECK-27 [AC-32]: `checks/report-survivor-carries-its-provenance.sh` — replays ONE byte-identical engine report over two indexes that differ in exactly one edge (the ⊤-holding function outside the test cone, then inside it) and requires: the JSON names `selection_provenance` at the document level AND on the survivor record; the survivor's `verdict` is `SURVIVED` on the closed cone and `UNKNOWN` on the escaping one; the text rendering prints the provenance in its header AND beside the survivor line, and never a bare `SURVIVED`; and `--fail-on-survivors` exits 1 on the closed cone and 0 on the escaping one. The contrast between the two indexes is asserted as a PRECONDITION off `plan --format json`'s `unreached_is_proof` — a field that predates the fix — so the check cannot be satisfied by the code it tests. The exit-1 arm is the negative control: without it, "never fail" would pass everything else. Self-contained; needs `dune build`. **Red-verified**: against `bin/arch_mutants/arch_mutants.ml` restored from HEAD it exits 1 with 9 assertions fired (`the report names its selection provenance — expected proved_superset, got <absent>`, `--fail-on-survivors does NOT fail on a ⊤-bounded UNKNOWN — expected 0, got 1`) while the negative control stays green. This is the ratchet for the MEDIUM where `report` bypassed the whole soundness rule this branch introduces.
- CHECK-28 [AC-34]: `checks/prior-status-read-with-its-provenance.sh` — seeds a completed prior campaign holding all three polarities (KILLED with one kill row naming a since-deleted test; SURVIVED under `top_bounded` with no kill row; SURVIVED under `proved_superset` with no kill row), then runs a real `--diff` campaign over a range that edits README.md only, so rules 1 and 2 contribute nothing and every site in the answer arrived through the deleted-test rule alone. Requires `rechecked_for_deleted_tests` = `lib/x.ml:15` and `unrecheckable` = `lib/y.ml:35` exactly — the proved survivor's absence from that list is the negative control, without which "call every survivor un-recheckable" would pass. The provenance contrast is asserted as a precondition against the database itself. Self-contained; needs `sqlite3`, `git`, `python3` and `dune build`. **Red-verified**: against HEAD it exits 1 with `a ⊤-bounded survivor is UN-RECHECKABLE, a proved one is not — expected lib/y.ml:35, got` (empty), the other five assertions staying green so the failure is attributable. This is the ratchet for the MEDIUM where `prior_mutants` projected a status with no provenance and collapsed it to a boolean.
- CHECK-29 [AC-33]: `checks/generic-status-vocabulary-is-closed.sh` — feeds `report` a generic NDJSON record whose status is one keystroke off (`SURVIVE`), then one a future schema `CHECK` might add (`SKIPPED`), and requires exit 2 naming the string, with no report printed at all — including under `--fail-on-survivors`, so the gate cannot pass on a report it did not understand. The negative control replays all four engine statuses plus the wrapper's `REFUSED` and requires killed=2, errored=1, refused=1 and exactly one survivor; without it, refusing every input would pass. This is code and not lint on purpose: `scripts/check-total-matches.sh` is structurally blind here, as its own header documents in excluding `if x = "KILLED"`. Self-contained; needs `dune build`. **Red-verified**: against HEAD it exits 1 with `a misspelled status aborts rather than being counted — expected 2, got 0` and `nothing was counted as an engine error instead — expected 0, got 1`, the five negative-control assertions staying green.
- CHECK-30 [AC-10]: `checks/status-scan-eof-is-not-a-pass.js` — seven fixtures through `scripts/check-status-provenance.sh`, pinning the general rule rather than the one literal that exposed it: A SCAN THAT LOST ITS PLACE MUST NOT REPORT COVERAGE. An unterminated string, an unclosed comment and an unclosed `` `Assoc `` must each be a hit; a char literal holding a double quote must be tokenized rather than mistaken for a delimiter, in code and inside a comment; and the two ordinary answers must still hold, because a guard that fails on everything is as useless as one that passes on everything. Every case asserts a NEEDLE as well as an exit, so a case cannot be satisfied by the right exit for the wrong reason — which is how the fourth case earns its place. Self-contained; needs nothing but `bash`. **Red-verified**: against the guard restored from HEAD it exits 1 with 4 of 7 cases failing, including `a clean record behind a quote-char literal in code — output never said: inspected 1 JSON record`, an exit-0 case caught only by its needle.
- CHECK-31 [AC-19]: `checks/mutant-key-parse-error-is-not-a-rejection.js` — builds a 200-row population and runs `scripts/check-mutant-key.sh` over three probe schemas: the real migration (exit 0, and the output must carry NO `Parse error` at all, because a pass printed over a parse error is the original defect); the migration with the UNIQUE line deleted (exit 1 — if this arm does not fire the check cannot fail and every 0 it printed was worth nothing); and a script whose INSERT column list names a column that does not exist (exit 2 — a statement that never reached the constraint is a harness error, neither a rejection nor a pass). The bogus column is injected by POSITION, not by name, so the arm survives the column being renamed again — naming it is what let the original defect hide. Refuses with exit 2 rather than passing if either mutation can no longer be built. Self-contained; needs `sqlite3`. **Red-verified**: against `scripts/check-mutant-key.sh` and `mutants-schema-migration.sql` restored from HEAD it exits 1 with all three arms failing — `exit 0, wanted 1`, `exit 0, wanted 2`, and `output contained what it must not: Parse error`.
- CHECK-32 [meta]: `checks/ratchet-is-wired-into-ci.js` — the ratchet was wired into nothing. CI ran `dune build` and `dune test`; no workflow step, no dune rule and no script referenced `checks/` or `scripts/check-*`, so every check in this table was a file someone had to remember to run. Measured, not assumed: `grep -n 'scripts/check' .github/workflows/ci.yml`, `grep -rn checks --include=dune .` and `git diff --stat origin/main...HEAD -- .github/` all returned nothing. This asserts two things, because the wiring can rot from either end: that some CI step's `run:` body — not a comment, not prose — invokes `checks/run-ratchet.js`, and that the runner still COVERS every check file on disk, compared against `--list`. The second is the half that rots silently: a check added under `checks/` that the runner does not discover is a check CI does not run, and the table would still count it as coverage. It deliberately pins neither the step's name nor the runner's identity — those are decisions, not invariants. Self-contained. **Red-verified twice**: against `.github/workflows/ci.yml` restored from HEAD it exits 1 with `NO CI step invokes checks/run-ratchet.js`; against a runner whose discovery had been narrowed to `.js` it exits 1 naming all nine uncovered bash checks.
- CHECK-33 [meta]: `checks/ratchet-is-node-executable.js` — the review-convergence gate resolves a linked check as `node <path>`, and nine of these checks are bash, so the gate recorded six `green-failure` violations for six checks that all exit 0 under bash while independently marking the same six red-verified. It could neither green- nor red-verify any of them. `checks/run-ratchet.js` is the one node-runnable path that runs the whole ratchet — a narrower answer than nine node shims, and an honest one, because a link to it really does execute every check behind it. This check carries its OWN positive control rather than asserting the property: it runs `node` against a bash check and requires that to FAIL, then requires `node checks/run-ratchet.js --list` to exit 0 and name a non-empty set. A control that stops controlling is itself a failure, reported as such. It uses `--list`, not a full run, so a genuine ratchet regression arrives under `run-ratchet.js`'s name rather than disguised here as an interface problem. Self-contained. **Red-verified twice**: with no entrypoint present it exits 2 (a missing fixture, refusing rather than passing); with an entrypoint that is node-runnable but reaches nothing it exits 1 with `An entrypoint that reaches no check is not an entrypoint`.
- CHECK-34 [AC-35]: `./_build/default/tezt/tests/main.exe --title "mutants: two mutants on one line keep their own verdicts, and an ambiguous entry is refused"` → exit 0.
- CHECK-35 [AC-35]: `node checks/outcome-join-is-site-identity.js` → exit 0. The ratchet for CHECK-34, and for review round 3's CRITICAL: the outcome join was `Filename.basename` plus line, consuming duplicates in list order and never refusing, while both discriminators — the schema's own UNIQUE key and the engine's id, carried by BOTH records — were present and discarded. Four probes: inversion, wrong file under a shared basename, a refusal on an indistinguishable pair, and an ordinary campaign as the negative control. Red-verified in round 3 at exit 1, 8 of 12 assertions, with probe 4 green throughout — which is what makes the other three attributable.
- CHECK-36 [AC-36]: `./_build/default/tezt/tests/main.exe --title "mutants: a --diff narrowed to zero is refused, and an unmatched report entry blocks completion"` → exit 0.
- CHECK-37 [AC-36]: `node checks/empty-scope-and-unmatched-block-completion.js` → exit 0. Four probes: an empty scope refused before any row is written, an unmatched entry leaving `completed_at` NULL, an unmatched REFUSAL still counted — refusals are partitioned out of `matched`, so two real ones previously reached `n_refused` by no path — and a non-empty narrowing that still completes, without which "refuse every `--diff`" passes the first three. Red-verified at exit 1, 7 of 14.
- CHECK-38 [AC-37]: `./_build/default/tezt/tests/main.exe --title "mutants: arch-impact entries the reader cannot understand are counted, never dropped"` → exit 0.
- CHECK-39 [AC-37]: `node checks/arch-impact-boundary-refuses-empty.js` → exit 0. The ratchet for the `List.filter_map` that dropped entries with a renamed `name` field, silently shrinking a touched set from twelve to three. **The empty-array refusal deliberately does NOT live at the process boundary**, and probe 4 is what holds it downstream: refusing `Impact_ok []` at the boundary breaks the deleted-test rule, which selects mutants with no touched function at all, and turned three tezt cases red when it was tried. Red-verified at exit 1, 2 of 13 — the two message assertions, the refusal itself having already moved.
- CHECK-40 [AC-24]: `node checks/tree-boundary-non-git-checkout.js` → exit 0. **Pass NO argument** — see the preamble: a relative `.` makes this one check exit 2 without checking anything. The ratchet for CHECK-15's blind spot, and for the boundary CHECK-15's row described wrongly: `checks/tree-boundary-refusal.sh`'s `make_inner` always runs `git init`, so all three of its probes are inside a repository and neither polarity here is visible to it. Four probes: a non-git inner checkout inside an outer repo must still refuse the outer wrapper; the same layout WITH `git init` must still refuse, so the guard is not traded for one that only fires without git; a non-git tree with no repository above it must ACCEPT its own wrapper from a subdirectory; and where the boundary genuinely fell back to the invocation directory the refusal must NOT assert a nesting. Red-verified at exit 1, 6 of 9, with probe 2 green.
- CHECK-41 [AC-24]: `./_build/default/tezt/tests/main.exe --title "mutants: a checkout that is not itself a repository still refuses the outer wrapper"` → exit 0.
- CHECK-42 [AC-38]: `node checks/genuine-99-is-not-a-refusal.js` → exit 0. `scripts/mutaml-wrapper.sh` reserves 99 for REFUSED and then forwards the test command's own code, so a runner legitimately exiting 99 lost its run row, could never be KILLED, and blocked completion for ever. The discriminator was free and unused: a genuine 99 reaches the end of the wrapper and writes its trace line; a refusal exits before it. Three probes, run through the real chain with the engine stub persisting the WRAPPER's raw code the way mutaml does. Red-verified at exit 1, 3 of 8.
- CHECK-43 [AC-32, AC-10]: `node checks/unmapped-survivor-carries-its-verdict.js` → exit 0. **Bound to AC-10 as well as AC-32, and the reason is a defect in AC-10's other checks rather than a preference.** FR-013's carve-out is retracted, so the `unmapped` record is now inside the requirement — but `scripts/check-status-provenance.sh` still excludes that path in its header and still keys on `engine_status` while the record's key is `status`, and CHECK-22 and CHECK-30 run the guard over fixtures of their own and never read `bin/arch_mutants/` at all. Positive control executed: with the unmapped record's `selection_provenance`, `verdict` and `verdict_basis` deleted, the guard reports `inspected 26 JSON record(s) … PASS` at exit 0. This check drives the real `report` and is the only one of the four that can fire. Four probes: JSON, text, the headline count, and a MAPPED survivor as the negative control. Red-verified at exit 1, 8 of 14.
- CHECK-44 [AC-32]: `./_build/default/tezt/tests/main.exe --title "mutants: an unmapped survivor carries its verdict and is counted in the headline"` → exit 0.
- CHECK-45 [AC-39]: `./_build/default/tezt/tests/main.exe --title "mutants: an executed set that is not a superset of the intended set is refused"` → exit 0. FR-003's first check. It was proven red in round 3 by deleting the guard in place and restoring it — not with `git stash`, whose foreign entries are live in this working tree — and fired 3 assertions.
- CHECK-46 [AC-40]: `./_build/default/tezt/tests/main.exe --title "mutants: a prime-suffixed test name runs to completion; a comma is still refused"` → exit 0. Proven red by removing `'` from the allowlist in place; 3 assertions fired.
- CHECK-47 [AC-40]: `./_build/default/tezt/tests/main.exe --title "mutants: a test name carrying shell metacharacters is refused, not written"` → exit 0.
- CHECK-48 [AC-26]: `./_build/default/tezt/tests/main.exe --title "mutants: arch-impact exiting 3 is REFUSED, distinct from a failure and from an empty scope"` → exit 0. AC-26 is FR-032's criterion and had no CHECK row until review round 3, in a table whose exit convention FR-032 is the reason for.
- CHECK-49 [AC-43]: `./_build/default/tezt/tests/main.exe --title "mutants: a deleted test re-selects what it alone killed and names what cannot be re-checked"` → exit 0. FR-017's first check; the recheck matches on the full site key, not on basename plus line, which was the same conflation CHECK-35 ratchets.
- CHECK-50 [meta]: `node checks/dispatch-covers-open-findings.js mutation-campaign-313 .` → exit 0. Every OPEN finding in `briefs/mutation-campaign-313-review.json` must be NAMED in `briefs/mutation-campaign-313-impl.md`, at every severity and not merely at HIGH and above. Three of round 1's HIGHs were never dispatched while the brief claimed all nine fixed, and nothing in the convergence gate expressed the state "an open finding has no owner": it is not blocked, not rejected, not in progress, and no state anywhere says so, so it does not move. Naming is not fixing, and the output says which is which — a finding named under a heading matching /defer/i counts as DEFERRED. **This same absence is why the spec-traceability group of round 3 was planned, given a worktree, and never dispatched at all.**
- CHECK-51 [AC-24]: `node checks/tree-boundary-tracked-marker.js` → exit 0. **Pass NO argument** — same reason as CHECK-40. A **RULE**, not a regression test: it pins the property that decides the boundary — a `dune-project` narrows it only where the enclosing git repository does not track it — in both polarities and on the DIAGNOSIS, not on the one working directory that motivated it. CHECK-40 cannot see this: all four of its probes build the marker at the tree ROOT, where no marker is ever nested under a repository that tracks it. Four probes: (1) an UNTRACKED nested checkout inside an outer repo must still have the outer wrapper refused, with the foreign-tree diagnosis, which is true there — this is issue #77 and the negative control against a fix that simply stops narrowing; (2) the same layout with the nested `dune-project` TRACKED and committed must ACCEPT the repository's own wrapper — the negative control against "refuse everything"; (3) with no git and no marker the refusal must name the FALLBACK and must not assert a nesting — the probe that separates a right verdict from a right reason; (4) this repository itself, invoked from `poc/decision-lint`, must accept `scripts/mutaml-wrapper.sh`, and is SKIPPED with a printed line rather than passing vacuously where the tree does not have that shape. **Red-verified twice**, both times by `git checkout d98277e -- bin/arch_mutants/arch_mutants.ml` and rebuilding, never by `git stash`: exit 1, 4 of 10 assertions, with probes 1 and 3 green in both the red and the green run — which is what makes the failure attributable to the property rather than to the check telling two trees apart. **The diagnosis matchers key on the AFFIRMATIVE wording only and match against whitespace-COLLAPSED output.** Both were earned: the honest fallback message contains the sentence "This is NOT a claim that this checkout is nested inside another one", so a matcher for that phrase fires on the message written to deny it; and the diagnoses are multi-line OCaml literals whose continuation padding lands space runs inside the sentence. CHECK-40's probe-4 assertion uses that phrase against the RAW text and passes only because the padding breaks the adjacency — re-wrapping that literal would make it vacuous with no signal. Requires `git`, `sqlite3` and `dune build`; needs a `TMPDIR` outside any checkout, and says so at exit 2 rather than passing vacuously.
- CHECK-52 [meta]: `node checks/one-engine-id-two-sites-is-refused.js` → exit 0. A **RULE**, not a regression test: no engine id may address more than one SELECTED site. Step 5a's own comment claims the catalogue is "an injection from ids to site keys" and 5a's code checks one direction only — no two entries sharing a site key. The other direction was reachable, because a generic catalogue's `id` is author-supplied and required. **Measured at 664e0d8** on two entries at `lib/x.ml:15` (cols 3-9 → `true`, SURVIVED; cols 11-15 → `false`, KILLED) both claiming the id `"1"`: two `mutants` rows written, `Hashtbl.replace mutant_ids s.s_id id` overwrote so both selections resolved to the col-11 row, ONE `mutant_runs` row persisted holding the col-3 site's SURVIVED against the col-11 mutant — a false attribution — and the KILLED verdict was rejected by UNIQUE(campaign_id, mutant_id) with a raw SQLite constraint message as the only diagnostic. **What did not happen, so the finding is not read as bigger than it is:** the campaign did not read as complete — the reconciliation guard saw 1 row against 2 attempts and withheld `completed_at`. Three refusing arms (NUMBERED `1`/`1`, NAMED `m1`/`m1`, AMONG-THREE) state the property under vocabularies sharing no lexical shape, so a fix special-casing digits reads red; a CONTROL arm runs the identical catalogue with distinct ids and must still complete, so a blanket refusal reads red rather than green. Each refusing arm asserts the database is left as it was found — no `mutant_campaigns`, `mutant_runs` or `mutants` row — and that the diagnostic NAMES the shared id. **Red-verified** by `git checkout 664e0d8b9f970df59cf926da176014d60854a5b1 -- bin/arch_mutants/arch_mutants.ml` and rebuilding, never by `git stash`: exit 1, 12 assertions across the three refusing arms, control green in both runs. **What it does not cover, stated rather than inferred:** it cannot stop a future author comparing two engine handles in code — both legitimate uses require rendering to a string, so `to_display_string a = to_display_string b` reconstitutes any comparison an abstract type would forbid, and the channel-naming in `arch_mutants.ml` makes that read as wrong at the call site without preventing it; it looks only at SELECTED sites, so duplicate ids among entries no target reaches are not refused; and it says nothing about ids colliding only after some future normalisation, of which there is none today.


**CHECK-32, CHECK-33 and CHECK-50 carry no AC**, and the reason given for it until review round 3 was a false dichotomy, corrected here. It ran: an AC invented to hold them "would be a dangling reference of exactly the shape review round 3 found four of." That is not what a dangling reference is. A dangling reference is a pointer to an id with no record; writing the AC into both the body and the claims block creates a record and therefore creates no dangle — the four real dangles this spec carried (CHECK-23 and CHECK-26 pointing at an absent AC-24, AC-30 and AC-33 pointing at an absent FR-031) were closed in exactly that way, by adding the records. The argument proved that inventing an AC and NOT recording it would be wrong, and was used to conclude something else.

The honest reason is narrower and is the one that holds: **these three verify a property of the SPEC DOCUMENT and its harness, not of the product.** CHECK-32 asserts that what this table lists is reachable from CI; CHECK-33 that it is executable by the gate that reads it; CHECK-50 that every open finding is owned by the brief. None is a criterion a user could accept or reject the deliverable on, and the claims schema has record types for requirements, acceptance criteria and checks — none for an obligation on the document itself. `for":[]` is therefore an accurate statement of the schema's shape rather than a gap in the graph. **CHECK-11, CHECK-12 and CHECK-13 carry `for":[]` for a second, distinct reason**: they verify the Quint model's properties P1, P2 and P3, and P-ids are not AC-ids. The formal properties are traced in `specs/mutation-campaign-313.qnt`, not here.

**And CHECK-32's coverage is narrower than a reader would assume.** It asserts that the RUNNER covers every check on disk; nothing asserts that this SPEC does. Until review round 3 the table listed 13 of the 20 checks in `checks/`, and the seven it omitted were precisely the ones defending round 3's CRITICAL and five HIGHs — so the table read as complete while the newest and most load-bearing half of the ratchet was reachable from no row of it. CHECK-34..CHECK-50 close that gap by enumeration, which is not the same as closing it structurally: nothing yet fails when the next check is added and not listed here.

**Authentic path**: CHECK-1 reaches the real driver through the real CLI with a stub engine at the
process boundary. CHECK-8 is the only check that reaches a real external engine; it now PASSES
against mutaml 0.3 rather than reporting the integration as unverified, and it still reports exit
3 rather than passing when that engine is absent or cannot be driven by this fixture.

## Claims Metadata

Deterministic validation is **unavailable** in this repository: neither `scripts/claims-reconcile.js`
nor `.harness/bin/claims-reconcile.js` exists, so the block below is validated by no tool that
ships with this branch, and no validation result is simulated.

**What WAS executed, in review round 3, and what it found.** The block was reconciled against the
document body with a throwaway parser — every `FR-nnn` heading, every `- AC-n [` line and every
`- CHECK-n ` row on one side, every record on the other. Before: 26 requirement records against 34
in the body (FR-027..FR-034 absent), 21 acceptance-criterion records against 34 (AC-21..AC-28
absent), 24 check records against 33 (CHECK-11..CHECK-19 absent) — two thirds coverage — and four
DANGLING references: CHECK-23 and CHECK-26 declaring `for":["AC-24"]` with no AC-24 record, AC-30
and AC-33 declaring `for":["FR-031"]` with no FR-031 record. FR-030, the one requirement round 1
found wholly unimplemented, had no record at all, so the machine-readable graph could not say
whether it was asserted, deferred or done. After: **34 requirement, 46 acceptance-criterion and 50
check records, matching the body exactly in both directions; zero dangling references; every
requirement reachable from at least one acceptance criterion.** Two acceptance criteria, AC-41 and
AC-46, are reachable from no check, and each says so in its own row rather than being quietly
dropped from the graph — the graph's job is to make that visible, not to hide it.

`spec_lifecycle` is `live`, matching the front matter's `status: live`; the two disagreed until
review round 3, which is the human-readable and machine-readable answers to one question
contradicting each other in the document whose central round-2 repair was making a live spec stop
asserting the unimplemented. The per-record `lifecycle` field is a different axis — it marks which
slice a requirement belongs to, and `deferred` there means slice 4 or 5 — and is left as it was.

```claims
{"record":"claims-header","schema_version":1,"namespace":"mutation-campaign-313","spec_lifecycle":"live"}
{"record":"requirement","id":"FR-001","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-002","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-003","lifecycle":"draft","external_sources":[],"depends_on":["FR-002"]}
{"record":"requirement","id":"FR-004","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-005","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-006","lifecycle":"draft","external_sources":[],"depends_on":["FR-005"]}
{"record":"requirement","id":"FR-007","lifecycle":"draft","external_sources":[],"depends_on":["FR-005"]}
{"record":"requirement","id":"FR-008","lifecycle":"draft","external_sources":[],"depends_on":["FR-005"]}
{"record":"requirement","id":"FR-009","lifecycle":"draft","external_sources":[],"depends_on":["FR-005"]}
{"record":"requirement","id":"FR-010","lifecycle":"draft","external_sources":[],"depends_on":["FR-005"]}
{"record":"requirement","id":"FR-011","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-012","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-013","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-014","lifecycle":"draft","external_sources":[],"depends_on":["FR-008"]}
{"record":"requirement","id":"FR-015","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-016","lifecycle":"draft","external_sources":[],"depends_on":["FR-002"]}
{"record":"requirement","id":"FR-017","lifecycle":"draft","external_sources":[],"depends_on":["FR-007"]}
{"record":"requirement","id":"FR-018","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-019","lifecycle":"deferred","external_sources":[],"depends_on":["FR-011"]}
{"record":"requirement","id":"FR-020","lifecycle":"deferred","external_sources":[],"depends_on":["FR-011"]}
{"record":"requirement","id":"FR-021","lifecycle":"deferred","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-022","lifecycle":"deferred","external_sources":[],"depends_on":["FR-019"]}
{"record":"requirement","id":"FR-023","lifecycle":"deferred","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-024","lifecycle":"deferred","external_sources":[],"depends_on":["FR-002"]}
{"record":"requirement","id":"FR-025","lifecycle":"deferred","external_sources":[],"depends_on":["FR-023"]}
{"record":"requirement","id":"FR-026","lifecycle":"draft","external_sources":[],"depends_on":[]}
{"record":"requirement","id":"FR-027","lifecycle":"draft","external_sources":[],"depends_on":["FR-011"]}
{"record":"requirement","id":"FR-028","lifecycle":"draft","external_sources":[],"depends_on":["FR-001"]}
{"record":"requirement","id":"FR-029","lifecycle":"draft","external_sources":[],"depends_on":["FR-027"]}
{"record":"requirement","id":"FR-030","lifecycle":"draft","external_sources":[],"depends_on":["FR-001"]}
{"record":"requirement","id":"FR-031","lifecycle":"draft","external_sources":[],"depends_on":["FR-010"]}
{"record":"requirement","id":"FR-032","lifecycle":"draft","external_sources":[],"depends_on":["FR-004"]}
{"record":"requirement","id":"FR-033","lifecycle":"draft","external_sources":[],"depends_on":["FR-011"]}
{"record":"requirement","id":"FR-034","lifecycle":"draft","external_sources":[],"depends_on":["FR-014"]}
{"record":"acceptance-criterion","id":"AC-1","for":["FR-001","FR-002"]}
{"record":"acceptance-criterion","id":"AC-2","for":["FR-002"]}
{"record":"acceptance-criterion","id":"AC-3","for":["FR-004"]}
{"record":"acceptance-criterion","id":"AC-4","for":["FR-005"]}
{"record":"acceptance-criterion","id":"AC-5","for":["FR-006","FR-008"]}
{"record":"acceptance-criterion","id":"AC-6","for":["FR-007"]}
{"record":"acceptance-criterion","id":"AC-7","for":["FR-011","FR-012"]}
{"record":"acceptance-criterion","id":"AC-8","for":["FR-011"]}
{"record":"acceptance-criterion","id":"AC-9","for":["FR-011"]}
{"record":"acceptance-criterion","id":"AC-10","for":["FR-013"]}
{"record":"acceptance-criterion","id":"AC-11","for":["FR-014"]}
{"record":"acceptance-criterion","id":"AC-12","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-13","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-14","for":["FR-019"]}
{"record":"acceptance-criterion","id":"AC-15","for":["FR-020"]}
{"record":"acceptance-criterion","id":"AC-16","for":["FR-022"]}
{"record":"acceptance-criterion","id":"AC-17","for":["FR-023"]}
{"record":"acceptance-criterion","id":"AC-18","for":["FR-025"]}
{"record":"acceptance-criterion","id":"AC-19","for":["FR-006"]}
{"record":"acceptance-criterion","id":"AC-20","for":["FR-002"]}
{"record":"check","id":"CHECK-1","for":["AC-1","AC-4","AC-5","AC-6","AC-42"]}
{"record":"check","id":"CHECK-2","for":["AC-2"]}
{"record":"check","id":"CHECK-3","for":["AC-3"]}
{"record":"check","id":"CHECK-4","for":["AC-7","AC-8","AC-9"]}
{"record":"check","id":"CHECK-5","for":["AC-11"]}
{"record":"check","id":"CHECK-6","for":["AC-14","AC-15","AC-16","AC-44"]}
{"record":"check","id":"CHECK-7","for":["AC-10"]}
{"record":"check","id":"CHECK-8","for":["AC-20"]}
{"record":"check","id":"CHECK-9","for":["AC-19"]}
{"record":"check","id":"CHECK-10","for":["AC-17","AC-18","AC-45"]}
{"record":"acceptance-criterion","id":"AC-29","for":["FR-015"]}
{"record":"check","id":"CHECK-20","for":["AC-29"]}
{"record":"check","id":"CHECK-21","for":["AC-29"]}
{"record":"check","id":"CHECK-22","for":["AC-10"]}
{"record":"check","id":"CHECK-23","for":["AC-24"]}
{"record":"acceptance-criterion","id":"AC-30","for":["FR-031"]}
{"record":"acceptance-criterion","id":"AC-31","for":["FR-007"]}
{"record":"check","id":"CHECK-24","for":["AC-30"]}
{"record":"check","id":"CHECK-25","for":["AC-31"]}
{"record":"check","id":"CHECK-26","for":["AC-24"]}
{"record":"acceptance-criterion","id":"AC-32","for":["FR-013","FR-011"]}
{"record":"acceptance-criterion","id":"AC-33","for":["FR-031"]}
{"record":"acceptance-criterion","id":"AC-34","for":["FR-013","FR-018"]}
{"record":"check","id":"CHECK-27","for":["AC-32"]}
{"record":"check","id":"CHECK-28","for":["AC-34"]}
{"record":"check","id":"CHECK-29","for":["AC-33"]}
{"record":"check","id":"CHECK-30","for":["AC-10"]}
{"record":"check","id":"CHECK-31","for":["AC-19"]}
{"record":"check","id":"CHECK-32","for":[]}
{"record":"check","id":"CHECK-33","for":[]}
{"record":"acceptance-criterion","id":"AC-21","for":["FR-027"]}
{"record":"acceptance-criterion","id":"AC-22","for":["FR-028"]}
{"record":"acceptance-criterion","id":"AC-23","for":["FR-029"]}
{"record":"acceptance-criterion","id":"AC-24","for":["FR-030"]}
{"record":"acceptance-criterion","id":"AC-25","for":["FR-031"]}
{"record":"acceptance-criterion","id":"AC-26","for":["FR-032"]}
{"record":"acceptance-criterion","id":"AC-27","for":["FR-033"]}
{"record":"acceptance-criterion","id":"AC-28","for":["FR-034"]}
{"record":"acceptance-criterion","id":"AC-35","for":["FR-006","FR-007"]}
{"record":"acceptance-criterion","id":"AC-36","for":["FR-016","FR-029"]}
{"record":"acceptance-criterion","id":"AC-37","for":["FR-016"]}
{"record":"acceptance-criterion","id":"AC-38","for":["FR-032"]}
{"record":"acceptance-criterion","id":"AC-39","for":["FR-003"]}
{"record":"acceptance-criterion","id":"AC-40","for":["FR-002"]}
{"record":"acceptance-criterion","id":"AC-41","for":["FR-009"]}
{"record":"acceptance-criterion","id":"AC-42","for":["FR-010"]}
{"record":"acceptance-criterion","id":"AC-43","for":["FR-017"]}
{"record":"acceptance-criterion","id":"AC-44","for":["FR-021"]}
{"record":"acceptance-criterion","id":"AC-45","for":["FR-024"]}
{"record":"acceptance-criterion","id":"AC-46","for":["FR-026"]}
{"record":"check","id":"CHECK-11","for":[]}
{"record":"check","id":"CHECK-12","for":[]}
{"record":"check","id":"CHECK-13","for":[]}
{"record":"check","id":"CHECK-14","for":["AC-21","AC-22","AC-23"]}
{"record":"check","id":"CHECK-15","for":["AC-24"]}
{"record":"check","id":"CHECK-16","for":["AC-12","AC-13"]}
{"record":"check","id":"CHECK-17","for":["AC-25"]}
{"record":"check","id":"CHECK-18","for":["AC-27"]}
{"record":"check","id":"CHECK-19","for":["AC-28"]}
{"record":"check","id":"CHECK-34","for":["AC-35"]}
{"record":"check","id":"CHECK-35","for":["AC-35"]}
{"record":"check","id":"CHECK-36","for":["AC-36"]}
{"record":"check","id":"CHECK-37","for":["AC-36"]}
{"record":"check","id":"CHECK-38","for":["AC-37"]}
{"record":"check","id":"CHECK-39","for":["AC-37"]}
{"record":"check","id":"CHECK-40","for":["AC-24"]}
{"record":"check","id":"CHECK-41","for":["AC-24"]}
{"record":"check","id":"CHECK-42","for":["AC-38"]}
{"record":"check","id":"CHECK-43","for":["AC-32","AC-10"]}
{"record":"check","id":"CHECK-44","for":["AC-32"]}
{"record":"check","id":"CHECK-45","for":["AC-39"]}
{"record":"check","id":"CHECK-46","for":["AC-40"]}
{"record":"check","id":"CHECK-47","for":["AC-40"]}
{"record":"check","id":"CHECK-48","for":["AC-26"]}
{"record":"check","id":"CHECK-49","for":["AC-43"]}
{"record":"check","id":"CHECK-50","for":[]}
```

## Entities

- `campaign`: one execution of a mutation engine over a selected mutant set, against one index, with one seed. Never resumed; a re-run is a new campaign.
- `mutant site`: a location plus a replacement, identified by file, line, column span, replacement text and source content hash. Stable across campaigns.
- `mutant run`: the outcome of one campaign for one mutant site — the engine status plus how the test selection was obtained.
- `selection provenance`: `proved_superset`, `top_bounded`, or `no_contract` — how the executed test set relates to the true set of tests reaching the mutated function.
- `published verdict`: the derived, never-stored value a reader sees — `KILLED`, `SURVIVED`, `UNKNOWN`, `UNKNOWN_NO_CONTRACT`, `ERROR`, or `PENDING`.
- `attribution`: knowing which individual test killed a mutant. Known only when the executed set was a singleton or the engine names the killer; otherwise absent, never inferred.
- `intended set` / `executed set`: the tests the plan says reach a mutant, and the tests the profile could actually address. The second is always a superset of the first, never a subset.
