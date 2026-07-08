---
name: roster-spec
type: spec
status: live
feature: metrics/compare regression gate with .metrics-accept waivers
brief: briefs/arch-metrics-gate-intake.md
date: 2026-07-08
version: 1.0.0
---

# Spec — arch-metrics-gate

## Clarifications

| Q | A |
|---|---|
| Are epure-style unwaivable hard floors in v1? | No. v1 adopts octez semantics exactly (bounds + mandatory reasons). Floors deferred; documented as future work. |
| Implementation split? | `metrics` = new branch in the bash `arch-query` (emits JSON via `sqlite3 -json`/`json_object`). `compare` = new OCaml binary `arch-compare` (port of octez `arch_compare.ml`) with an Alcotest suite. Rationale: waiver parsing/report logic is unit-testable OCaml; metric SQL follows the existing bash convention. |
| Which metrics are regression-tracked (directional)? | `worse_when_higher` = {large_files, large_functions, undocumented_exposed, may_top_edges}; `worse_when_lower` = {doc_coverage_pct}. `modules, total_functions, exported_functions, call_edges` are informational (emitted, never block). |
| doc_coverage_pct definition? | Over exposed/exported functions only: `100 × (1 − undocumented_exposed / exposed_count)` rounded to 1 decimal; `100.0` when there are no exposed functions. `undocumented_exposed` = exposed functions with `comment_quality_score IS NULL OR = 0`. Only emitted when the column exists. |
| Exposed vs exported column dualism? | Feature-detect: main schema uses `exposed`, flat schema uses `exported`. `metrics` probes `pragma_table_info('functions')` and uses whichever exists (prefer `exposed`). |
| Where does `.metrics-accept` live / how located? | `arch-compare` reads `.metrics-accept` in CWD by default; `--accept FILE` overrides. Absent file = empty policy (no waivers), not an error. |

## User Stories

### US-1: Metrics emission (Priority: P0)
As a CI job or agent, I want `arch-query <db> metrics [-o FILE]` to emit a flat JSON object of codebase metrics computed from an existing index DB so that architecture quality is machine-checkable.
**Why this priority**: Everything else consumes this output.
**Scope**: Does NOT cover comparison or waivers. No new metric collection — only schema objects that already exist; metrics whose source table/column is absent are omitted (feature-detect), never emitted as 0.
**Independent Test**: Build the self-index DB, run `metrics`, pipe to `jq`, assert flat numeric object with expected keys.
**Acceptance Scenarios**:
1. **Given** a ⊤-marked self-index DB with `functions`, `calls.kind`, and `modules.lines`, **When** `arch-query self.db metrics` runs, **Then** stdout is a single flat JSON object with numeric values including `total_functions`, `call_edges`, `may_top_edges`, `large_functions`, and keys sorted lexicographically.
2. **Given** the same DB, **When** `arch-query self.db metrics -o /tmp/m.json` runs, **Then** `/tmp/m.json` contains the same JSON and stdout carries no JSON.
3. **Given** a flat-schema DB (NDJSON path) without `comment_quality_score`, **When** `metrics` runs, **Then** `doc_coverage_pct` and `undocumented_exposed` are absent from the output (not 0) and the command exits 0.
4. **Given** a path to a non-existent DB, **When** `metrics` runs, **Then** exit code is 2 (existing arch-query behavior).
5. **Given** a DB with no `functions` table at all, **When** `metrics` runs, **Then** it refuses with exit 3 and a guidance message (existing feature-detect convention).

### US-2: Compare engine (Priority: P0)
As a CI job, I want `arch-compare <baseline.json> <current.json>` to classify each tracked metric (blocking regression / accepted regression / improvement / unchanged / missing) render a deterministic report, and exit 1 on any failure, so regressions block merges.
**Why this priority**: The gate itself.
**Scope**: Does NOT cover metric collection; does NOT include hard floors; does NOT read any DB (pure JSON+text inputs; optional detail queries are out of v1).
**Independent Test**: Alcotest suite over `Arch_compare` with synthetic JSON strings and accept-file strings; plus a CLI smoke test.
**Acceptance Scenarios**:
1. **Given** baseline `{"large_functions": 10}` and current `{"large_functions": 12}` and no `.metrics-accept`, **When** compare runs, **Then** report lists `large_functions` under blocking regressions and exit code is 1.
2. **Given** baseline `{"doc_coverage_pct": 80.0}` and current `{"doc_coverage_pct": 85.0}`, **When** compare runs, **Then** it is listed as improvement and exit code is 0.
3. **Given** baseline `{"large_files": 3}` and a current JSON without `large_files`, **When** compare runs, **Then** `large_files` is reported missing and exit code is 1.
4. **Given** an untracked metric (`total_functions`) that grew, **When** compare runs, **Then** it does not appear as a regression and does not affect the exit code.
5. **Given** a malformed baseline file (not valid flat `{string: number}` JSON), **When** compare runs, **Then** exit code is 2 with an error naming the file.

### US-3: `.metrics-accept` waiver protocol (Priority: P1)
As a reviewer, I want per-metric bounds with mandatory reasons in `.metrics-accept` so intentional regressions are accepted explicitly and auditably.
**Why this priority**: The escape hatch that makes a hard gate socially viable.
**Scope**: Does NOT auto-expire waivers; does NOT support hard floors.
**Independent Test**: Alcotest cases over `parse_accept_file_string` and `evaluate`.
**Acceptance Scenarios**:
1. **Given** `.metrics-accept` containing `large_functions <= 12  # refactor of parser pending, issue #42` and current `large_functions = 12` vs baseline 10, **When** compare runs, **Then** the regression is listed as accepted with bound and reason, exit code 0.
2. **Given** the same entry but current `large_functions = 13`, **When** compare runs, **Then** the regression is blocking (exceeds reviewed bound), exit 1.
3. **Given** an entry `large_functions <= 12` with no reason anywhere (no inline `#`, no trailing text, no preceding comment block), **When** compare runs, **Then** the entry is reported invalid and exit code is 1.
4. **Given** an entry `doc_coverage_pct <= 70` (wrong operator for a worse-when-lower metric), **When** compare runs, **Then** the entry is invalid, exit 1.
5. **Given** an entry naming an untracked metric (`total_functions <= 999 # x`), **When** compare runs, **Then** the entry is invalid, exit 1.
6. **Given** two entries for the same metric, **When** compare runs, **Then** the duplicate is reported invalid, exit 1.

### US-4: Self-applied CI gate + docs (Priority: P1)
As an arch-index maintainer, I want the repo to dogfood the gate — committed `metrics-baseline.json`, committed `.metrics-accept` (empty policy), a CI step running metrics+compare over the self-index — plus ADR-style docs covering baseline regeneration and the consumer wiring pattern (baseline pinned via `git show HEAD:`).
**Why this priority**: Proves the gate end-to-end and gives consumers a copyable pattern.
**Scope**: Does NOT install hooks in consumer repos; does NOT gate on informational counts (they change every commit — only ratchet metrics are tracked, so routine growth cannot fail CI).
**Independent Test**: Run the CI commands locally; then artificially inflate a tracked metric in the baseline copy and confirm compare fails.
**Acceptance Scenarios**:
1. **Given** the committed baseline matches the current self-index, **When** the CI step runs `metrics` then `arch-compare`, **Then** it prints OK and the job passes.
2. **Given** a source change that pushes a function past 50 lines (large_functions +1) with no waiver, **When** CI runs, **Then** the compare step fails the job with `large_functions` listed as blocking.
3. **Given** the docs, **When** a consumer follows the regeneration procedure, **Then** it produces a valid baseline committed alongside the change, mirroring `docs/adr/001-self-index-golden.md` style.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Int vs float JSON formatting; locale decimal separators | Emit via `sqlite3 -json`/`json_object()` — locale-independent; counts are ints, `doc_coverage_pct` is `ROUND(x,1)` float. Parser accepts any JSON number. |
| C-2 | US-1 | `doc_coverage_pct` denominator ambiguous | Defined in Clarifications: exposed functions only; 100.0 when none. |
| C-3 | US-1 | `exposed` (main) vs `exported` (flat) column dualism | Feature-detect via `pragma_table_info`; prefer `exposed`. |
| C-4 | US-1 | Empty/foreign DB (no `functions` table) | Refuse exit 3 with guidance (existing convention), never emit `{}`. |
| C-5 | US-1×US-2 | Feature-detected omission (US-1) collides with "missing tracked metric → fail" (US-2): baseline built on main schema vs current from flat schema | Intended: baseline defines the tracked set; a schema downgrade IS a regression signal. Missing cannot be waived; recovering requires deliberate baseline regeneration. Documented in ADR. |
| C-6 | US-2 | octez's direction lists name different metrics | Direction table redefined for arch-index metric set (see Clarifications). |
| C-7 | US-2 | Float comparison tolerance (epure used 0.5; octez none) | Strict octez semantics; equality within 1e-9 counts as unchanged. Bounds are the escape hatch, not tolerances. |
| C-8 | US-3 | Reason-source priority ambiguity | Adopt octez rules verbatim: inline `#` > trailing text after bound > accumulated preceding comment block; blank line clears pending comments. |
| C-9 | US-3 | Duplicate entries for one metric | Invalid entry (fail loud) — stricter than octez, which is silent on this. |
| C-10 | US-4 | Does the CMT self-index populate `modules.lines`? | Not assumed. Baseline contains exactly the metrics emitted for the self-index; omission is by design. Runnable check verifies actual emission. |
| C-11 | US-4 | Baseline churn burden (like the golden file) | Tracked metrics are ratchets (large_functions, may_top_edges, …) that change rarely; informational counts never block. ADR gives one regeneration procedure covering golden + baseline. |
| C-12 | US-1,US-2 | Determinism of output ordering | JSON keys and report rows sorted lexicographically by metric name. |
| C-13 | US-1 | `-o` to unwritable path | Exit 2 (usage/IO), message on stderr. |
| C-14 | US-2 | Malformed JSON inputs must not read as regressions | Exit 2 (malformed input), distinct from exit 1 (gate failure) — mirrors loader ABORT convention. |

## Functional Requirements

#### Metrics emission (US-1)
- **FR-001** [US-1]: `arch-query <db> metrics` MUST emit exactly one flat JSON object `{string: number}` on stdout (or to FILE with `-o FILE`), keys sorted lexicographically.
- **FR-002** [US-1]: The metric set MUST be: `modules`, `total_functions`, `exported_functions`, `call_edges` (always, given core tables); `may_top_edges` (iff `calls.kind` exists); `large_files` (iff `modules.lines` exists; `lines > 500`); `large_functions` (iff `functions.line_count` exists; `> 50`); `undocumented_exposed` and `doc_coverage_pct` (iff `comment_quality_score` exists and an exposed/exported column exists).
- **FR-003** [US-1]: A metric whose source table/column is absent MUST be omitted from the output, and MUST NOT be emitted as 0.
- **FR-004** [US-1]: `metrics` MUST exit 3 with a guidance message when the `functions` table is absent, and MUST exit 2 on a non-existent DB path or unwritable `-o` target.
- **FR-005** [US-1]: `metrics` MUST work on both main-schema and flat-schema DBs, detecting `exposed` vs `exported` columns.

#### Compare engine (US-2)
- **FR-006** [US-2]: `arch-compare <baseline.json> <current.json>` MUST classify every tracked metric present in both files as regression, improvement, or unchanged according to its direction, and MUST list tracked metrics present in baseline but absent from current as missing.
- **FR-007** [US-2]: `arch-compare` MUST exit 1 iff there is ≥1 blocking regression, ≥1 missing tracked metric, or ≥1 invalid `.metrics-accept` entry; otherwise exit 0.
- **FR-008** [US-2]: `arch-compare` MUST NOT let untracked metrics affect classification or exit code.
- **FR-009** [US-2]: `arch-compare` MUST exit 2 with a file-naming error on inputs that are not flat `{string: number}` JSON.
- **FR-010** [US-2]: The report MUST render sections: blocking regressions, missing metrics, improvements, accepted regressions (with bound + reason), invalid entries, and a final `OK`/`FAILED` line; rows sorted by metric name.
- **FR-011** [US-2]: Value equality within 1e-9 MUST classify as unchanged.

#### Waiver protocol (US-3)
- **FR-012** [US-3]: A waiver entry MUST have the form `<metric> <op> <bound>` with a reason, where `<op>` is `<=` for worse-when-higher metrics and `>=` for worse-when-lower metrics.
- **FR-013** [US-3]: Reason resolution MUST follow priority: inline `#` comment > trailing text after bound > immediately-preceding `#` comment block; a blank line MUST clear the pending comment block.
- **FR-014** [US-3]: An entry MUST be invalid when: metric is untracked, operator mismatches the metric's direction, bound is not a number, reason is absent, or the metric already has an earlier entry.
- **FR-015** [US-3]: A regression MUST be accepted iff a valid entry exists for that metric AND the current value is within the bound (`current <= bound` for worse-when-higher; `current >= bound` for worse-when-lower); otherwise it MUST be blocking.
- **FR-016** [US-3]: An absent `.metrics-accept` file MUST behave as an empty policy (no waivers, no error); `--accept FILE` MUST override the default CWD location.
- **FR-017** [US-3]: Invalid entries MUST NOT be silently skipped — each MUST be reported with its line number and MUST fail the gate.

#### Self-applied gate + docs (US-4)
- **FR-018** [US-4]: The repo MUST commit `metrics-baseline.json` and `.metrics-accept` (documented empty policy), and CI MUST run `metrics` on the self-index and `arch-compare` against the committed baseline, failing the job on gate failure.
- **FR-019** [US-4]: An ADR-style doc MUST describe: baseline regeneration procedure, waiver workflow, the missing-metric semantics (C-5), and the consumer pre-commit pattern with the baseline read via `git show HEAD:` to prevent same-commit loosening.
- **FR-020** [US-4]: The self-gate MUST NOT track informational counts (`modules`, `total_functions`, `exported_functions`, `call_edges`) — routine code growth MUST NOT fail CI.

## Acceptance Criteria

- AC-1 [US-1 happy]: `arch-query self.db metrics | jq -e 'type=="object" and (to_entries|all(.value|type=="number"))'` → passes.
- AC-2 [US-1, C-3]: flat-schema DB → `exported_functions` present, `doc_coverage_pct` absent.
- AC-3 [US-2 happy]: regressed tracked metric, no waiver → exit 1, listed blocking.
- AC-4 [US-2, C-5]: tracked metric absent from current → exit 1, listed missing.
- AC-5 [US-3]: valid waiver covering regression → exit 0, listed accepted with reason.
- AC-6 [US-3]: waiver without reason → exit 1, listed invalid with line number.
- AC-7 [US-4]: CI self-gate passes on clean tree; fails when baseline is artificially lowered on a tracked metric.

## Edge Cases

- EC-1 [US-1]: zero exposed functions → `doc_coverage_pct = 100.0`, `undocumented_exposed = 0`.
- EC-2 [US-2]: untracked metric in baseline absent from current → ignored (not "missing").
- EC-3 [US-2]: identical files → all unchanged, exit 0.
- EC-4 [US-3]: current exactly equals bound → within bound (inclusive), accepted.
- EC-5 [US-3]: waiver for a metric that did not regress → entry valid, unused; reported nowhere except (optionally) accepted-unused note; exit unaffected.
- EC-6 [US-2]: baseline value equals current ± <1e-9 → unchanged.
- EC-7 [US-1]: DB with `calls` table but zero rows → `call_edges = 0`, `may_top_edges = 0` (columns exist).

## Runnable Checks

- CHECK-1 [AC-1]: `opam exec -- dune build && ./arch-callgraph-ocaml --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql && ./arch-query /tmp/self.db metrics | jq -e 'type=="object"'` → exit 0.
- CHECK-2 [AC-3]: `echo '{"large_functions":10}' > /tmp/b.json; echo '{"large_functions":12}' > /tmp/c.json; ./arch-compare /tmp/b.json /tmp/c.json; test $? -eq 1` → passes.
- CHECK-3 [AC-5]: same files + `.metrics-accept` = `large_functions <= 12 # test waiver`; `./arch-compare --accept <file> /tmp/b.json /tmp/c.json` → exit 0, output contains `test waiver`.
- CHECK-4 [AC-6]: accept file `large_functions <= 12` (no reason) → exit 1, output contains `invalid`.
- CHECK-5 [US-2 unit]: `opam exec -- dune test` → new `test_arch_compare` Alcotest suite passes.
- CHECK-6 [AC-4]: baseline `{"large_files":3}`, current `{}` → exit 1, output contains `missing`.
- CHECK-7 [AC-2]: build flat DB via `selftest-load.sh`-style NDJSON → `metrics` exits 0; output has `exported_functions`, lacks `doc_coverage_pct`.

## Entities

- `MetricsObject`: flat JSON object `{metric_name: number}` emitted by `arch-query metrics`; the only interchange format between emission and comparison.
- `TrackedMetric`: a metric with a declared direction (worse-when-higher or worse-when-lower); the only kind that can regress, block, or be waived.
- `AcceptEntry`: one validated `.metrics-accept` line — metric, operator, bound, mandatory reason, source line number.
- `CompareVerdict`: per-metric classification ∈ {blocking-regression, accepted-regression, improvement, unchanged, missing}.
- `arch-compare`: standalone OCaml binary implementing parse → classify → evaluate → render, exit ∈ {0,1,2}.
