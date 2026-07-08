---
name: roster-spec
type: spec
status: live
feature: code-health query pack (arch-query subcommands + compare-bodies CLI)
brief: briefs/arch-health-queries-intake.md
date: 2026-07-08
version: 1.0.0
---

# Spec — arch-health-queries

## Clarifications

| Q | A |
|---|---|
| missing-mli in scope? | Yes — `modules.has_mli` exists in the schema (`architecture-schema.sql:14`); feature-detected; `COALESCE(has_mli,0)=0` (NULL = missing). |
| type-search arg shape (bash captures only A/B)? | `type-search <field-substr|-> [type-substr]` — `-` placeholder skips the field condition; at least one real value required, else exit 2. AND-composed when both given. |
| duplicates NULL signatures? | Rows with `signature IS NULL OR signature=''` are excluded from grouping (same-name unrelated functions would false-positive). Same-module duplicates excluded (`HAVING count(DISTINCT module_id) > 1`). |
| missing-docs condition? | Exposed and `(intent IS NULL OR intent='')` — v_undocumented semantics hardened for empty strings. |
| LIKE sanitization? | Existing quote-strip + escape `%`,`_`,`\` and use `ESCAPE '\'` (metrics/arch_mcp precedent). |
| Threshold args? | `${1:-<default>}` style; must match `^[0-9]+$` else exit 2. Defaults: large-files 500, large-functions 50, god-modules 30, unsafe-strings 3. |
| compare-bodies on flat schema / missing sources? | Flat schema (no line ranges/modules) → exit 3 refuse with guidance. Missing file or NULL range → empty normalized body; CLI flags such occurrences with `(empty body — source missing?)` so identical-empty groups are not mistaken for real duplicates. |
| unsafe_params ledger? | Out of scope (item 5); `unsafe-strings` is the pure query over `type_fields` (≥N same-named string fields). |

## User Stories

### US-1: Health threshold subcommands (Priority: P0)
As a reviewer/agent, I want `large-files [N]`, `large-functions [N]`, `god-modules [N]`, `missing-docs`, `missing-mli`, `unsafe-strings [N]` in arch-query so codebase health is queryable with tunable thresholds.
**Scope**: no schema changes; no curated ledger; no metrics-gate changes.
**Independent Test**: run each on the CMT self-index and on a flat DB.
**Acceptance Scenarios**:
1. **Given** the self-index, **When** `large-functions 50` runs, **Then** boxed rows (name, module/file, line_count) sorted by line_count DESC; exit 0 (empty result = exit 0, empty table).
2. **Given** a flat DB (no modules, no line ranges), **When** `large-files` runs, **Then** exit 3 with guidance naming the missing source.
3. **Given** `large-functions abc` or `-5`, **Then** exit 2 usage.
4. **Given** a flat DB with `file_path` but no `modules`, **When** `god-modules 1` runs, **Then** grouping falls back to `file_path` (EC-7).
5. **Given** functions with `intent=''`, **When** `missing-docs` runs, **Then** they are listed (EC-8).
6. **Given** `modules.has_mli` NULL, **When** `missing-mli` runs, **Then** the module is listed (EC-9).

### US-2: duplicates + type-search (Priority: P0)
As a refactoring agent, I want signature-duplicate groups and type-shape search so cross-module duplication and newtype candidates are discoverable.
**Scope**: signature-level only (body-level is US-3); main-schema only (feature-detected).
**Acceptance Scenarios**:
1. **Given** two modules with the same non-empty (name, signature), **When** `duplicates` runs, **Then** one group row: name, signature (truncated ~70 chars), count, module list.
2. **Given** same-name functions with NULL signatures, **Then** not grouped (EC-11); same-module repeats not reported (EC-12).
3. **Given** `type-search instance_name`, **Then** types having a field name LIKE %instance_name% with their `field: type` lists.
4. **Given** `type-search - string`, **Then** types having a string-typed field. **Given** `type-search - `(no args)`, **Then** exit 2.
5. **Given** input `100%`, **Then** literal match (escaped, EC-15); single quotes stripped (EC-16).
6. **Given** a flat DB (no type_fields), **Then** exit 3 with guidance.

### US-3: compare-bodies CLI (Priority: P1)
As a reviewer, I want a CLI over the existing `Arch_index_compare.compare_bodies` so per-name body-hash comparison (epure-proven, currently zero consumers) is usable: `arch-body-compare --db DB --project-root DIR <name>`.
**Scope**: per-name only (no global scan); requires sources on disk (documented).
**Acceptance Scenarios**:
1. **Given** a name occurring twice with identical normalized bodies, **Then** output states IDENTICAL with digest + both locations; exit 0.
2. **Given** differing bodies, **Then** DIFFERS with one group per digest; exit 0 (informational, not a gate).
3. **Given** a name absent from the DB, **Then** NOT FOUND, exit 1.
4. **Given** a missing source file (EC-19/20/21), **Then** the occurrence is flagged `(empty body — source missing?)`.
5. **Given** a flat-schema DB, **Then** exit 3 refuse (EC-24). **Given** missing args, **Then** exit 2 usage.
6. **Given** an operator name `(>>=)` (EC-22), **Then** exact-match lookup works (bound parameter).

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | bash A/B two-arg limit vs flag-style thresholds | positional `[N]` args only (fan-in convention); regex-validated |
| C-2 | US-1 | flat-schema behavior per command | per-command feature-detect table (below); exit 3 guidance |
| C-3 | US-1 | god-modules grouping source | modules join when present; `functions.file_path` fallback; else refuse |
| C-4 | US-2 | octez sprintf injection | escape+ESCAPE for LIKE; quote-strip retained (house style) |
| C-5 | US-2 | NULL-signature false groups | excluded (Clarifications) |
| C-6 | US-3 | empty-body identical groups mislead | flagged in output (Clarifications) |
| C-7 | US-3 | zero tests for Arch_index_compare | Alcotest suite added with fixture source files (tmpdir) |
| C-8 | US-3 | exact-match SQL from bash would need interpolation | CLI is OCaml with bound parameter (safe for `(>>=)`) |
| C-9 | all | output stability | deterministic ORDER BY on every query |

## Functional Requirements

#### Health subcommands (US-1)
- **FR-001** [US-1]: arch-query MUST provide `large-files [N=500]`, `large-functions [N=50]`, `god-modules [N=30]`, `missing-docs`, `missing-mli`, `unsafe-strings [N=3]` as documented case branches.
- **FR-002** [US-1]: Each command MUST feature-detect its source tables/columns (xinfo/sqlite_master) and exit 3 with guidance when absent; empty result sets MUST exit 0.
- **FR-003** [US-1]: Threshold arguments MUST be validated `^[0-9]+$`; violations exit 2.
- **FR-004** [US-1]: `god-modules` MUST group by module when `modules` exists, else by `functions.file_path` when that column exists, else exit 3.
- **FR-005** [US-1]: `missing-docs` MUST treat `intent NULL` and `''` as undocumented and filter on the detected exposed/exported column; `missing-mli` MUST treat `has_mli NULL` as 0.
- **FR-006** [US-1]: `unsafe-strings [N]` MUST report field_name, occurrence count, and the distinct type list for string-typed fields repeated ≥N times, ordered by count DESC.
- **FR-007** [US-1]: All result queries MUST have deterministic ORDER BY.

#### duplicates + type-search (US-2)
- **FR-008** [US-2]: `duplicates` MUST group by (name, signature) over non-empty signatures with `HAVING count(DISTINCT module) > 1`, reporting name, truncated signature, count, module paths.
- **FR-009** [US-2]: `type-search <field|-> [type]` MUST AND-compose the given conditions over `type_fields`, require ≥1 real value (else exit 2), and escape LIKE wildcards.
- **FR-010** [US-2]: Both MUST exit 3 on DBs lacking `signature`/`type_fields` respectively.

#### compare-bodies (US-3)
- **FR-011** [US-3]: A new `arch-body-compare` binary + wrapper MUST expose `Arch_index_compare.compare_bodies` with `--db`, `--project-root`, and a function-name argument; exits: 0 verdict rendered, 1 name not found, 2 usage, 3 flat-schema refuse.
- **FR-012** [US-3]: Occurrences with empty normalized bodies MUST be visibly flagged in the output.
- **FR-013** [US-3]: The `Arch_index_compare` module MUST gain Alcotest coverage (identical, differs, not-found, missing-file cases).
- **FR-014** [US-3]: The function-name lookup MUST use a bound SQL parameter (operator names like `(>>=)` are valid input).

#### Docs (cross)
- **FR-015** [all]: arch-query header block and README MUST document the new subcommands and the compare-bodies CLI (incl. sources-on-disk requirement).

## Acceptance Criteria

- AC-1 [US-1]: all six health commands produce correct rows on the self-index; refusals on flat DB where applicable.
- AC-2 [US-1]: threshold validation (non-numeric/negative → 2).
- AC-3 [US-2]: duplicates and type-search correct on a synthetic main-schema fixture; exit 3 on flat.
- AC-4 [US-3]: compare-bodies verdicts on a tmpdir fixture project; empty-body flag shown for missing sources.
- AC-5 [all]: existing tests, selftests, and the metrics gate stay green (no tracked-metric drift).

## Edge Cases

EC-7 flat+file_path god-modules fallback; EC-8 `intent=''`; EC-9 `has_mli NULL`; EC-11 NULL signatures excluded; EC-12 same-module repeats excluded; EC-13/14 arg shape (A/B only); EC-15/16 wildcard/quote input; EC-18 single occurrence → reported as single (identical trivially); EC-19/20/21 empty-body flag; EC-22 operator names; EC-23 relative project_root accepted; EC-24 flat schema refuse.

## Runnable Checks

- CHECK-1 [AC-1]: `./arch-query /tmp/self.db large-functions 50 | head -5` → boxed rows, exit 0; `./arch-query <flat.db> large-files; test $? -eq 3`.
- CHECK-2 [AC-2]: `./arch-query /tmp/self.db god-modules abc; test $? -eq 2`.
- CHECK-3 [AC-3]: synthetic fixture → `duplicates` shows 1 group; `type-search - string` lists the fixture type; `./arch-query <flat.db> type-search x; test $? -eq 3`.
- CHECK-4 [AC-4]: fixture project in tmpdir → `./arch-body-compare --db X --project-root Y dup_fn` prints IDENTICAL; unknown name → exit 1.
- CHECK-5 [AC-5]: `opam exec -- dune test` (incl. new test_arch_index_compare) + `./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh` + metrics gate self-compare → all pass.
- CHECK-6 [US-1]: `./arch-query /tmp/self.db unsafe-strings 1` → exit 0 (table possibly empty), deterministic across two runs.

## Entities

- `HealthQuery`: a read-only, feature-detected arch-query subcommand with optional numeric threshold.
- `duplicate group`: functions sharing (name, non-empty signature) across >1 module.
- `unsafe string field`: a `type_fields` row with field_type='string' whose field_name recurs ≥N times across types.
- `arch-body-compare`: CLI over `Arch_index_compare.compare_bodies`; informational (never a gate).
