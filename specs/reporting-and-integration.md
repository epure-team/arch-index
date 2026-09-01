---
name: roster-spec
type: spec
status: draft
feature: arch-report — unified reporting and external-analyser integration
adr: docs/adr/002-external-tool-integration.md
date: 2026-09-01
version: 0.1.0
---

# Spec — arch-report and external-analyser integration

One indexing run should yield one artifact set that a human can read, an agent can query, and
another program can consume — with the rigour of every fact, and the extent of every analysis,
visible on its face.

## Current surface (measured, not assumed)

Output formats today are `box | csv | json | line | markdown` (`ARCH_QUERY_FORMAT`), plus the
machine-output contract on `arch-impact --format json` and `arch-rules --format json`. There is
**no SARIF and no HTML** anywhere in the tree. Server surfaces are `arch-serve` (SPA over HTTP)
and `arch-mcp` (stdio JSON-RPC for agents). Ingest is `arch-load` / `arch-coverage-load` /
`arch-effects-load` / `arch-sidecar-load`.

## FR — provenance and coverage

- **FR-001** Every imported fact records `producer`, `producer_version`, `invocation_digest`, and
  `soundness_class ∈ {sound_with_top, heuristic, asserted}` (ADR 002).
- **FR-002** `analysis_coverage(language, analysis, status, producer, producer_version, ran_at)`
  with `status ∈ {covered, not_analysed, failed, partial}`. A run records one row per
  (language × analysis) pair it *could* have attempted, including the ones it could not.
- **FR-003** A query whose scope includes a language with `status = not_analysed` for the relevant
  analysis returns `NOT_ANALYSED` for that portion. Zero rows MUST NOT render as a clean result.
  This is `Arch_db.nonempty`'s discipline (`lib/arch_tools/arch_db.ml`) applied per analysis.
- **FR-004** A `heuristic` fact MUST NOT discharge a ⊤ anchor and MUST NOT license a `PASS`. A
  rule evaluated over a scope containing `heuristic` facts yields at best `PASS_UNDER_HYP`.
- **FR-005** `functions.language` and `functions.universe ∈ {internal, external}` are populated by
  every producer (FR-001 of `SPEC-sound-callgraph.md`, currently unimplemented). FR-002 depends on
  this; nothing else in this spec can ship before it.

## FR — ingest adapters

- **FR-010** `arch-sarif-load <file.sarif>` imports findings as `soundness_class = heuristic`,
  preserving rule id, level, message, and physical location. Tool name and version come from the
  SARIF `driver`.
- **FR-011** `arch-scip-load <index.scip>` imports symbols and references. Call-like references
  become `MAY_ENUMERATED` edges attributed to the SCIP producer. **Never `MUST`** — an indexer's
  reference is not a proof of unique resolution.
- **FR-012** An adapter that cannot parse its input **fails loudly and writes nothing**. A partial
  import is recorded as `status = partial` in `analysis_coverage` with the count of rejected
  records, reusing the per-table rejection attribution already in `Arch_index_db`.
- **FR-013** Adapter selection favours free/open-source and fast tools. Reference set: Semgrep OSS,
  clippy, staticcheck, gosec, osv-scanner, Trivy, tree-sitter. CodeQL is out of scope (ADR 002).

## FR — the report

- **FR-020** `arch-report <db> --out <dir>` emits, from **one** query pass:
  - `report.sarif` — findings, with `codeFlows` carrying witness paths where available.
  - `report.html` — a single self-contained file, no external assets, suitable as a CI artifact.
  - `report.json` — the machine contract, superset of the per-tool `--format json` outputs.
  - the SQLite database itself is the fourth artifact and is not regenerated.
- **FR-021** Every artifact carries the same header: producers run with versions, the
  `analysis_coverage` matrix, ⊤-frontier size, and verdict counts split
  `PASS` / `PASS_UNDER_HYP` / `UNKNOWN` / `VIOLATION`.
- **FR-022** `report.sarif` validates against the SARIF 2.1.0 schema and is accepted by GitHub code
  scanning. Findings whose `soundness_class = heuristic` carry that in their properties bag so a
  consumer can filter.
- **FR-023** `arch-mcp` exposes the report surface as tools, so an agent reads the same facts a
  human sees, with the same provenance.
- **FR-024** The report MUST render `NOT_ANALYSED` sections explicitly. A language with no adapter
  appears as an empty, labelled section — never as an absent one.

## Verification

- **CHECK-1** Import a SARIF file from Semgrep OSS; assert every finding lands with
  `soundness_class = heuristic` and that `arch-rules` over the same scope cannot return `PASS`.
- **CHECK-2** Index a polyglot fixture with an adapter available for one language only; assert the
  report renders `NOT_ANALYSED` for the other and that no query returns a bare empty result.
- **CHECK-3** Feed a malformed SARIF; assert non-zero exit, no rows written, and a `partial` or
  `failed` coverage row.
- **CHECK-4** `report.sarif` validates against the published 2.1.0 schema.
- **CHECK-5** Round-trip: every finding in `report.json` appears in `report.sarif` and in the
  rendered HTML, with identical provenance.

## Out of scope

Writing analysers. Any capability that cannot degrade to ⊤ or to `NOT_ANALYSED`. A bespoke web UI
beyond the single-file HTML — `arch-serve` already exists for interactive exploration.
