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
machine-output contract on `arch-impact --format json` and `arch-rules --format json`.
~~There is **no SARIF and no HTML** anywhere in the tree.~~ **Stale as of roadmap 2.1
(amended 2026-09-05):** `lib/arch_tools/arch_sarif.ml` exists and `arch-rules --format sarif`
ships. HTML is still absent, and 2.2 adds it. Corrected because this section is titled *measured,
not assumed* and had stopped being either — the same drift the three clauses below carried. Server surfaces are `arch-serve` (SPA over HTTP)
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
  every producer (FR-001 of `SPEC-sound-callgraph.md`). **Satisfied — amended 2026-09-05.** The
  original text called this "currently unimplemented" and added *"nothing else in this spec can
  ship before it"*. Both columns exist and are fully populated: on proto_alpha `lib_protocol`
  (500 `.cmt`, indexed from `origin/main` `0982a42` with `--errors-profile=tezos`),
  `universe = internal` for all 14 452 functions and `language = ocaml` for all 14 452.

  The blocking sentence outlived its truth for a reason worth recording rather than excusing: it
  sits in the provenance half of this document, and every reader since has opened the report half.
  A blocking clause nobody reads blocks nothing, which is the failure mode, not the mitigation.

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
  `analysis_coverage` matrix, ⊤-frontier size, and verdict counts split across **the whole
  vocabulary the tools actually emit** — `PASS`, `VIOLATION`, `POSSIBLE`, `UNKNOWN`,
  `UNKNOWN_NO_CONTRACT`, `NO_SOURCE`, `NO_TARGET`, `NOT_COMPUTED`.

  **Amended 2026-09-05, and the original was wrong in two directions.** It named four buckets:
  `PASS` / `PASS_UNDER_HYP` / `UNKNOWN` / `VIOLATION`.

  - It **omitted five** real verdicts. Bucketing eight values into four collapses distinctions the
    tools are built to keep — `UNKNOWN` (the cone escapes through a ⊤ edge) against
    `UNKNOWN_NO_CONTRACT` (the index never marked ⊤ at all), and `NOT_COMPUTED` (the analysis never
    ran) against `NO_SOURCE` (it ran over nothing). That is the defect roadmap 2.1's review found
    in the SARIF writer, which flattened five verdicts into one `note`; implementing this clause
    literally would have reintroduced it in the report header, citing the spec.
  - It named **`PASS_UNDER_HYP`, which no tool can emit today.** Verified: two occurrences in this
    document, zero anywhere in the code.

  **`PASS_UNDER_HYP` is RESERVED, not removed.** It is FR-004's verdict for a rule evaluated over
  `heuristic` facts, and those arrive only through the FR-010/FR-011 ingest adapters, neither of
  which exists (zero files on `main`). It belongs to the discharge ledger (roadmap 3.2), whose
  whole guarantee is that it never collapses into `PASS`. Deleting the name here would let 3.2
  reinvent it without the constraint that makes it safe; so it is named, dated, and explained as
  unreachable rather than dropped. A report emitting it before 3.2 lands would be claiming a
  hypothesis it has no way to have.
- **FR-022** `report.sarif` validates against the SARIF 2.1.0 schema and is accepted by GitHub code
  scanning. Findings whose `soundness_class = heuristic` carry that in their properties bag so a
  consumer can filter.
- **FR-023** `arch-mcp` exposes the report surface as tools, so an agent reads the same facts a
  human sees, with the same provenance.
- **FR-024** The report MUST render `NOT_ANALYSED` sections explicitly. A language with no adapter
  appears as an empty, labelled section — never as an absent one.

## Verification

- **CHECK-1** *(roadmap 2.3, the ingest slice — NOT verifiable by 2.2.)* Import a SARIF file from
  Semgrep OSS; assert every finding lands with `soundness_class = heuristic` and that `arch-rules`
  over the same scope cannot return `PASS`. Requires FR-010, which does not exist.
- **CHECK-2** Index a polyglot fixture with an adapter available for one language only; assert the
  report renders `NOT_ANALYSED` for the other and that no query returns a bare empty result.
- **CHECK-3** *(roadmap 2.3, the ingest slice — NOT verifiable by 2.2.)* Feed a malformed SARIF;
  assert non-zero exit, no rows written, and a `partial` or `failed` coverage row. Requires FR-012,
  which does not exist.

**Which checks 2.2 owns.** CHECK-2, CHECK-4 and CHECK-5 exercise the report; CHECK-1 and CHECK-3
exercise the ingest adapters. This list previously read as five obligations on one slice, in a
document that declares the adapters unwritten a few paragraphs above — the kind of contradiction a
long document sustains because nobody reads it end to end. Stated here so the next reader is not
the one who discovers it at review time.
- **CHECK-4** `report.sarif` validates against the published 2.1.0 schema.
- **CHECK-5** Round-trip: every finding in `report.json` appears in `report.sarif` and in the
  rendered HTML, with identical provenance.

## Out of scope

Writing analysers. Any capability that cannot degrade to ⊤ or to `NOT_ANALYSED`. A bespoke web UI
beyond the single-file HTML — `arch-serve` already exists for interactive exploration.
