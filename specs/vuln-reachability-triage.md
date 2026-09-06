---
name: vuln-reachability-triage
type: spec
status: live
feature: Vulnerability triage by sound reachability (roadmap 3.1)
brief: briefs/vuln-reachability-triage-intake.md
date: 2026-09-06
version: 1.0.0
---

# Spec — Vulnerability triage by sound reachability

> **Identity field.** `name:` above is this spec's own slug. Six specs on `main` carry
> `name: roster-spec` — the *skill's* name stamped into the artefact it produced. That is
> roadmap 4.9's to fix; this file does not reproduce it.

## What this is, and what it is not

A scanner reports "vulnerable dependency". A reachability tool reports "not called — PASS". This
feature reports **`UNKNOWN`, and names the unresolved edges standing between it and a proof.**

**The slice is smaller than its name.** This was scoped as though the ⊤-aware verdict lattice
needed building. It exists: `reach_verdict` (`bin/arch_rules/arch_rules.ml:589-605`) already
returns `NO_SOURCE | NO_TARGET | VIOLATION | POSSIBLE | UNKNOWN | UNKNOWN_NO_CONTRACT | PASS`
with the escaping-⊤ check evaluated **before** `PASS`; `NOT_COMPUTED` is produced at five further
sites; and ADR-002 already states normatively that a heuristic fact may never license a `PASS`.
The correction is recorded here rather than the smaller scope being presented as the original
plan. **This feature is ingestion + rule generation + a verdict record**, feeding machinery that
exists.

**It is not a discharge ledger.** `specs/reporting-and-integration.md` FR-021 reserves
`PASS_UNDER_HYP` for "the discharge ledger (**roadmap 3.2**), whose whole guarantee is that it
never collapses into `PASS`". This feature records **what was computed**; it discharges nothing,
licenses no `PASS`, and MUST NOT emit `PASS_UNDER_HYP`.

## Clarifications

| Q | A |
|---|---|
| Is the verdict lattice in scope? | No. It exists and is used unchanged. |
| Does "fail loudly on zero targets" need building? | No — `--on-vacuous` already defaults to `fail` and drives the exit code via `failing` (`arch_rules.ml:1305-1330`). The intake's claim that "a verdict in a report is not an exit code" was **wrong**, corrected by reading. |
| Then what is the real gate question? | `--on-unknown` defaults to **warn**, deliberately (`arch_rules.ml:1322-1323`: a rule that blocks every PR whose cone touches a callback teaches people to delete the rule). At 54.4 %/59.5 % unresolved edges, **every** generated rule lands on `UNKNOWN` or `NO_TARGET`. See C-9. |
| Is `NOT_COMPUTED` dead? | No. Five production sites; two tests pin it (`tezt/tests/rules.ml:505`, `tezt/tests/rules_origin.ml:479`). Its documented meaning — "the rule was never evaluated", distinct from `UNKNOWN` which is "an analysis result" — is exactly the distinction this feature needs, already argued in-repo. |
| Can we add a ninth verdict? | **No** — and the reason must be stated so it survives roadmap 4.12, which is in flight and changes the mechanism. **The stable reason:** the vocabulary carries an invariant that every member appears on every report, zero included (`arch_report.ml`), and the census is asserted to sum to the rule count. A ninth value breaks a total that consumers are promised. That holds however the vocabulary is represented. **The unstable reason, stated with its scope:** on `main` at `090f832` the vocabulary is a hand-written string list and `failing` is a disjunction of string equalities, so a value not named there evaluates `false`. **Measured, not assumed:** the vocabulary holds 8, `failing` names 7, and the omitted one is `PASS` — which must not fail. So coverage is **complete** and the gap is **latent**, not a live fail-open. Roadmap 4.12 (branch `fix/verdict-failing-exhaustive`, **unpushed, no PR**) makes the type a sum, derives the vocabulary from it, and makes `failing` exhaustive — a ninth constructor becomes a compile error rather than a silent pass. **Its own residual, which this spec must not paper over:** the enumeration list is still hand-written (OCaml cannot enumerate a variant without a ppx), so a constructor omitted from it still compiles, the census stops summing, and the existing assertion dies **loudly — not impossibly**. Do not assume the vocabulary is compile-time total in every direction. |
| Which ecosystem? | `opam` only. Symbol-level data is absent from npm (0/6), PyPI (0/38) and crates.io (0/28 over three informative packages). |
| Which ingest path? | The OSV API / per-ecosystem archive, by package name. **`osv-scanner` cannot scan opam at all** (`strings \| grep -cF opam` → 0 against working controls crates.io 1, Packagist 21, PyPI 45). |
| Is "corpus" one thing? | **No, and the brief conflated them.** There are two, drifting independently: the **advisory corpus** (26 OSV records, growing) and the **code corpus** (the index). Both are stamped separately. See C-16. |

## User Stories

### US-1: Ingest opam advisories into a provenance-stamped record (Priority: P0)

As a maintainer, I want opam security advisories fetched and stored with their provenance, so a
later verdict can say which advisory data it was computed from.

**Why P0**: nothing downstream exists without it.
**Scope**: does NOT cover rule generation, verdicts, or other ecosystems.
**Independent Test**: ingest the opam archive into a fresh DB; assert 26 advisory rows and the
per-advisory binding counts (7 advisories carrying 49 bindings), with a `producer_runs` row.

**Acceptance Scenarios**
1. **Given** the opam OSV archive and an index at schema ≥ the target version, **When** ingest
   runs, **Then** every advisory in the archive gets a row — including the **19 that carry no
   `affected_bindings`** — and a `producer_runs` row records producer, version and digest.
2. **Given** an archive entry whose `affected_bindings` is present but is not a list of strings,
   **When** ingest runs, **Then** the whole document is refused before any fact row is written,
   one `analysis_coverage` row with `status='failed'` is written, and the exit code is 2 — the
   discipline `bin/arch_sarif_load/arch_sarif_load.ml` already establishes, including writing **no**
   `producer_runs` row for a failed parse.
3. **Given** an index predating the advisory tables, **When** ingest runs, **Then** it refuses with
   a `failed` coverage row and exit 2 rather than creating an orphan run.

### US-2: Generate reachability rules, classifying each binding rather than guessing (Priority: P0)

As a maintainer, I want a rule generated for each advisory binding **whose relationship to the
index is classified**, so the reader can tell a binding that is absent from one the index cannot
express at all.

**Why P0**: this is the join, and the join is where a silent wrong answer would be produced.
**Scope**: does NOT cover modifying the rule engine or the verdict lattice.
**Independent Test**: generate from the 49-binding fixture; assert the three-way classification
counts and that every generated rule parses under `Arch_sel.parse ~allow:with_ext`.

**Acceptance Scenarios**
1. **Given** a binding of the form `Cohttp.Path.resolve_local_file`, **When** generation runs,
   **Then** a rule `forbid reach from exported:** to fn:Cohttp.Path.resolve_local_file` is emitted
   and its target classification is recorded as `absent` or `present` by looking the name up.
2. **Given** the binding `Cohttp_lwt.Make().resolve_local_file`, **When** generation runs, **Then**
   **no rule is emitted** and the binding is recorded as `inexpressible`, because the index renders
   a `Papply` prefix as the literal `"<apply>"` and neither `Make()` nor `<apply>` occurs in any
   corpus (measured 0/0 on both, LIKE mechanism positive-controlled first).
3. **Given** two advisories naming the same target, **When** generation runs, **Then** each
   advisory gets its own rule with a stable, advisory-scoped identity, so one target reachable from
   two advisories is reported twice — once per advisory — and never deduplicated into one.

### US-3: Report a per-advisory verdict that cannot be misread as clean (Priority: P0)

As a reader triaging a vulnerability, I want a verdict per advisory that never collapses "could not
determine" into "not affected", and that names what blocked the proof.

**Why P0**: this is the product. Every comparable tool collapses this in one direction or the other.
**Scope**: does NOT cover resolving the ⊤ frontier.
**Independent Test**: run against arch-index's own index; assert the cohttp advisory reports
`UNKNOWN` with a non-empty blocking-edge list, and that no advisory reports `PASS`.

**Acceptance Scenarios**
1. **Given** arch-index's own index (54.4 % unresolved) and advisory OSEC-2026-16, **When** the
   report runs, **Then** the verdict is `UNKNOWN`, the blocking `top_reason` values are listed, and
   the output nowhere reads as "not affected".
2. **Given** an advisory with **no** `affected_bindings` (19 of 26), **When** the report runs,
   **Then** it appears in the report with an explicit "no binding data" outcome — **omission is
   forbidden**, because an advisory absent from a report reads as one that was cleared.
3. **Given** a run where every rule is `NO_TARGET` (the situation today: 49 of 49), **When** the
   report runs, **Then** the summary states that no binding resolved and therefore **nothing about
   reachability was established** — distinct in wording from a run where targets resolved and no
   path was found.

### US-4: Make a stored verdict re-derivable, or say that it is not (Priority: P1)

As a reviewer reading a months-old verdict, I want to know the two corpora and the tool version it
was derived under, and to be told when it can no longer be re-derived.

**Why P1**: the record is useful before staleness detection exists; the reverse is not true.
**Scope**: does NOT cover automatic re-running.
**Independent Test**: write a verdict, mutate the recorded advisory-corpus identity, assert the
verdict renders as `superseded` rather than as current.

**Acceptance Scenarios**
1. **Given** a stored verdict, **When** a reader inspects it, **Then** it carries the advisory-corpus
   identity, the code-corpus identity, the tool version, and a per-value note of what produced each.
2. **Given** a stored verdict whose advisory corpus has since changed, **When** the report renders,
   **Then** the verdict is shown as `superseded`, never as current.
3. **Given** a stored verdict whose code corpus can no longer be reconstructed, **When** the report
   renders, **Then** it is shown as **`superseded-and-unrecoverable`** — a third state beside
   right and wrong, distinct from a verdict that merely needs re-running.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | What is "provenance" — OSV `modified`, an advisories-repo commit, an ETag, a fetch time? Which is US-4's re-derivation key? | The **archive's own identity** (its published digest) is the re-derivation key; `modified` per advisory is recorded but is **not** the key, because an edit that does not bump it would be invisible. Fetch time is recorded as metadata, never as identity. |
| C-2 | US-1 | The source is two-stage (`ocaml/security-advisories` Markdown → `hannesm/advisories` OSV). If they disagree, which is "the" record? | The OSV output is the record — it is what is machine-readable. The converter's identity is **not** currently exposed in the OSV output, so it **cannot** be recorded. Stated as a known gap, not silently omitted. |
| C-3 | US-1 | Store the raw blob, or parse `affected_bindings` into rows? | **Both.** The raw `ecosystem_specific` object is stored verbatim (it has no spec and may gain fields), *and* the bindings are parsed into rows. A parse failure on a present field refuses the document (US-1 scenario 2); an absent field is not a failure. |
| C-4 | US-1 | Is re-ingest additive, or must it detect an edited advisory? | Additive-append, never update in place. An advisory whose content digest differs from a stored one is a **new row**; verdicts pointing at the old row keep pointing at what they were computed from. This is what makes C-16's supersession detectable at all. |
| C-5 | US-2 | What is emitted for a binding with no representable target? | **Nothing is emitted, and the binding is recorded as `inexpressible`.** Emitting a rule guaranteed vacuous forever would produce a `NO_TARGET` indistinguishable from an advisory whose function is genuinely absent. |
| C-6 | US-2 | How does an advisory with several bindings become rules, and is the rule id stable? | One rule per (advisory, binding). Rule identity is `<advisory-id>/<binding>` — content-derived, **never positional**, so a re-ingest produces a diffable id rather than a fresh one. |
| C-7 | US-2 | Every one of the 49 bindings today generates a rule that is `NO_TARGET` by construction. Is that "a rule the engine can evaluate"? | Resolved by C-5's classification: `inexpressible` bindings generate no rule. A binding that is expressible but **absent** does generate a rule, and its `NO_TARGET` is then a real finding about this program. The two must not share an outcome. |
| C-8 | US-2 | **Prior art:** govulncheck resolves uncertainty *toward reachable*; the stories assume an explicit `UNKNOWN` tier. Justify or adopt. | **Divergence justified and deliberate.** govulncheck's rule is sound *for its purpose* (over-report) but it also documents that `reflect`-only reachability "will not be reported" — a false negative that is **silent in its output**. This feature's whole claim is that incompleteness is reported, not resolved by fiat in either direction. Adopting assume-reachable would make every advisory `VIOLATION` at 54.4 % unresolved — as uninformative as assume-unreachable, and dishonest in the opposite direction. |
| C-9 | US-3 | `--on-unknown` is **warn** by default, and every generated rule lands on `UNKNOWN` or `NO_TARGET`. Does US-3 require changing that default, which US-3's own scope arguably forbids? | **The advisory report does not reuse the architecture gate's default, and does not change it either.** Changing `--on-unknown` globally would alter every existing architecture rule — out of scope and wrong. Instead the advisory report has its **own** exit-code contract (FR-014): the exit code answers *"did the analysis run and report honestly"*, not *"is anything reachable"*. Gating on reachability is an explicit opt-in flag. A gate that always fails is as uninformative as one that always passes, and today the run is 49/49 vacuous. |
| C-10 | US-3 | Must `UNKNOWN` and `UNKNOWN_NO_CONTRACT` stay distinct in the per-advisory report? | **Yes.** `arch_report.ml:33-36` states that collapsing exactly these pairs is what the toolchain exists to prevent. Collapsing them here would violate US-3 by its own wording. |
| C-11 | US-3 | What verdict for a scope containing only `heuristic` facts, given `PASS_UNDER_HYP` is reserved? | **`UNKNOWN`**, with the reason recorded as heuristic-only. Not a new value (see the `failing` trap), and **never** `PASS_UNDER_HYP` — that belongs to roadmap 3.2. |
| C-12 | US-3 | **Prior art:** Snyk ships an explicit disclaimer beside "No Path Found"; the stories rely on the verdict enum alone. Justify. | **Adopted, not diverged.** Each non-`PASS` verdict in the advisory report carries a one-line caveat in prose beside the enum. The reader is a human triaging, and an enum value is not self-explanatory to someone who has not read this spec. |
| C-13 | US-3 | Five non-`PASS` values; is the reader expected to distinguish all five or treat them as one "not clean"? | Both, deliberately: the report renders a **binary headline** (nothing here is cleared) over a **five-way detail**. The headline is what stops a misreading; the detail is what makes the finding actionable. |
| C-14 | US-4 | "Index commit" is exactly the field the schema does not have, and `invocation_digest` is documented as invocation-scoped, not content-scoped. | Follow the documented intent: **extend the digest** rather than add a parallel column. The schema comment states that "a future item that needs content-sensitivity extends this digest". A new table still needs a `current_schema_version` bump *and* an entry in `schema_tables_to_drop` — `tezt/tests/schema_drop_list.ml` enforces it. |
| C-15 | US-4 | Is the staleness check automatic or advisory metadata? | **Automatic at render time**, against the stored identities only — never against a live network fetch, which would make rendering non-deterministic and offline-hostile. |
| C-16 | US-4 | "Corpus" is used for two things that drift independently. | Split, throughout: **advisory corpus** and **code corpus**, stamped separately. The brief conflated them; this is the correction. |
| C-17 | US-4 | **Prior art:** no listed tool stamps an index commit or exposes a staleness contract — all assume re-scan-on-demand. | **Named as a novel design burden rather than borrowed.** The operating model here (long-lived stored verdicts consulted months later) has no prior art to copy, which is itself a reason to keep US-4 at P1 and to prefer the smallest record that is honest. |

## Functional Requirements

#### Ingest (US-1)
- **FR-001** [US-1]: Ingest MUST parse the whole advisory document before writing any fact row, and MUST write no `producer_runs` row for a document it refuses.
- **FR-002** [US-1]: Ingest MUST refuse — never default — a present-but-malformed `affected_bindings`, and MUST NOT treat an absent one as an error.
- **FR-003** [US-1]: Ingest MUST store the raw `ecosystem_specific` object verbatim in addition to any parsed rows.
- **FR-004** [US-1]: Ingest MUST record every advisory in the source, including those carrying no bindings.
- **FR-005** [US-1]: Ingest MUST be append-only; a changed advisory MUST become a new row and MUST NOT mutate one an existing verdict points at.
- **FR-006** [US-1]: Ingest MUST record the advisory-corpus identity as the archive's published digest, and MUST NOT use per-advisory `modified` as the identity.

#### Rule generation (US-2)
- **FR-007** [US-2]: The generator MUST classify each binding as `present`, `absent`, or `inexpressible`, and MUST record the classification.
- **FR-008** [US-2]: The generator MUST NOT emit a rule for an `inexpressible` binding.
- **FR-009** [US-2]: The generator MUST derive rule identity from `(advisory-id, binding)` content and MUST NOT derive it from position or ordinal.
- **FR-010** [US-2]: The generator MUST NOT deduplicate two advisories that name the same target into one rule.
- **FR-011** [US-2]: Every emitted rule MUST parse under the existing selector grammar with the existing allow-lists; the generator MUST NOT extend `Arch_sel`.

#### Reporting (US-3)
- **FR-012** [US-3]: The report MUST list every ingested advisory; an advisory MUST NOT be omitted for any reason.
- **FR-013** [US-3]: The report MUST NOT collapse `UNKNOWN` with `UNKNOWN_NO_CONTRACT`, nor `NO_TARGET` with `inexpressible`.
- **FR-014** [US-3]: The advisory report's exit code MUST reflect whether the analysis ran and reported honestly, MUST NOT be a reachability gate by default, and MUST NOT alter the global `--on-unknown` default.
- **FR-015** [US-3]: A run in which no binding resolved MUST state that nothing about reachability was established, in wording distinct from a run that resolved targets and found no path.
- **FR-016** [US-3]: Each non-`PASS` verdict MUST carry a prose caveat beside the enum value.
- **FR-017** [US-3]: The report MUST NOT emit `PASS_UNDER_HYP`, and MUST NOT introduce a verdict value outside `verdict_vocabulary`.
- **FR-018** [US-3]: A verdict computed over a scope containing only `heuristic` facts MUST be `UNKNOWN` with the reason recorded, and MUST NOT be `PASS`.

#### Record (US-4)
- **FR-019** [US-4]: Every stored verdict MUST carry the advisory-corpus identity, the code-corpus identity, and the tool version, as **fields required at write time** — never as values a later pass fills in.
- **FR-020** [US-4]: Every stored verdict MUST record, per value, what produced it; a field a tool can compute MUST NOT accept a hand-written value.
- **FR-021** [US-4]: Rendering MUST mark a verdict `superseded` when a stored identity no longer matches, and `superseded-and-unrecoverable` when the code corpus cannot be reconstructed.
- **FR-022** [US-4]: Staleness detection MUST operate on stored identities only and MUST NOT perform a network fetch at render time.
- **FR-023** [US-4]: Evidence linking a verdict to what produced it MUST be matched structurally; the record MUST NOT establish any relationship by substring or prose matching.
- **FR-024** [US-4]: A new producer-written table MUST appear in `schema_tables_to_drop` and MUST be accompanied by a `current_schema_version` bump.

#### Interface to roadmap 3.2 — cheap now, expensive later (US-4)
- **FR-025** [US-4]: A verdict record whose reach verdict is `UNKNOWN` MUST name **the ⊤ anchors
  that blocked the proof**, not merely the verdict. Roadmap 3.2's `discharges` table is keyed on
  `top_anchor`; a record saying only `UNKNOWN` gives it nothing to key on, and reconstructing the
  anchors later would mean re-deriving every verdict against a corpus that has since moved.
  `top_reasons` — which `reach_verdict` already returns for the escaping node set — is the carrier.
- **FR-026** [US-4]: Anchors MUST be recorded in a form that preserves **which function owns each
  anchor**, so that 3.2 can compute its `anchor_digest` (the content hash of the owning function)
  later. This feature MUST NOT compute that digest itself.
- **FR-027** [US-4]: The record MUST NOT carry a hypothesis field, an author-justification field,
  an expiry, or any other discharge affordance, and MUST NOT emit `PASS_UNDER_HYP`. Building those
  early is precisely how a record becomes a ledger by accident — the failure
  `specs/reporting-and-integration.md` FR-021 names.

## Acceptance Criteria

- AC-1 [US-1 happy path]: ingest the opam archive → 26 advisory rows, 7 carrying bindings, 49 binding rows, one `producer_runs` row.
- AC-2 [US-1, C-3]: a present-but-malformed `affected_bindings` → exit 2, zero fact rows, one `failed` coverage row, **no** `producer_runs` row.
- AC-3 [US-1, C-4]: re-ingesting a changed advisory → a new row; the old row is byte-unchanged.
- AC-4 [US-2, C-5]: `Cohttp_lwt.Make().resolve_local_file` → classified `inexpressible`, no rule emitted.
- AC-5 [US-2, C-7]: an expressible-but-absent binding → a rule IS emitted, and its `NO_TARGET` is reported distinctly from `inexpressible`.
- AC-6 [US-2, C-6]: regenerating from an unchanged advisory → byte-identical rule ids.
- AC-7 [US-3 happy path]: OSEC-2026-16 against arch-index's own index → `UNKNOWN`, blocking reasons listed, no "not affected" wording anywhere.
- AC-8 [US-3, C-13]: an advisory with no bindings → present in the report with an explicit no-binding-data outcome.
- AC-9 [US-3, C-9]: a 49/49-vacuous run → exit code is not a reachability failure, and the summary says nothing about reachability was established.
- AC-10 [US-3, C-11]: a heuristic-only scope → `UNKNOWN`, never `PASS`, never `PASS_UNDER_HYP`.
- AC-11 [US-4, C-16]: a verdict carries advisory-corpus and code-corpus identities as separate fields.
- AC-12 [US-4, C-15]: a mutated stored identity → rendered `superseded`, with no network access during rendering.
- AC-13 [US-4, FR-025/FR-026]: an `UNKNOWN` verdict record names its blocking ⊤ anchors, and each anchor resolves back to the function that owns it.
- AC-14 [US-4, FR-027]: the record's field set contains no hypothesis, justification, expiry or discharge field, and no output path can emit `PASS_UNDER_HYP`.

## Edge Cases

- EC-1 [US-1]: malformed `affected_bindings` → whole document refused, exit 2 (FR-001/FR-002).
- EC-2 [US-1]: feed unreachable mid-fetch → no partial write; the run is refused as a whole.
- EC-3 [US-1]: same advisory id, different content → new row, old row untouched (FR-005).
- EC-4 [US-2]: binding names a `MAY_ENUMERATED`/heuristic-only node → rule emitted; verdict can never be a sound `PASS` (FR-018, ADR-002).
- EC-5 [US-2]: two advisories, same target → two rules, reported twice (FR-010).
- EC-6 [US-2]: module resolves but the symbol does not → `absent`, not `inexpressible`. Does not occur today (0/49) but the generator must define it.
- EC-7 [US-3]: index carries no ⊤ contract → `UNKNOWN_NO_CONTRACT`, rendered distinctly (FR-013).
- EC-8 [US-3]: advisory with zero bindings → listed, never omitted (FR-012).
- EC-9 [US-4]: identical corpus, different tool version → `superseded`; bit-identical reproduction is **not** claimed, because `invocation_digest` is invocation-scoped and cannot certify determinism.
- EC-10 [US-4]: an advisory withdrawn upstream → the verdict is marked `superseded-and-unrecoverable`; the row is never deleted, because deleting it would make the verdict's provenance dangle.

## Runnable Checks

Exit convention: **0 = check passes, 1 = assertion fired, ≥2 = error.** Checks are tezt tests in
the repository's own idiom, registered in `tezt/tests/main.ml`, run scoped as
`dune build && ./_build/default/tezt/tests/main.exe --file <path>` — never `dune exec`.

**Every check that can return zero MUST carry a positive control** demonstrating the probe returns
non-zero on a known-present input. Three near-misses during this task's research were broken probes
reporting real absences.

- CHECK-1 [AC-1] (authentic-success-path): `./_build/default/tezt/tests/main.exe --file tezt/tests/vuln_ingest.ml` → ingests a fixture archive; asserts advisory/binding row counts; **positive control**: a probe for a binding known to be in the fixture returns non-zero.
- CHECK-2 [AC-2] (fail-closed-path): same file → malformed-`affected_bindings` fixture yields exit 2, zero fact rows, one `failed` coverage row, zero `producer_runs` rows.
- CHECK-3 [AC-3]: re-ingest of a mutated advisory yields a second row and leaves the first byte-identical.
- CHECK-4 [AC-4, AC-5]: `--file tezt/tests/vuln_rulegen.ml` → the `Make()` binding classifies `inexpressible` with no rule emitted; an expressible-but-absent binding emits a rule; the two outcomes render differently. **Positive control**: an expressible-and-present binding emits a rule that resolves.
- CHECK-5 [AC-6]: two generations over an unchanged advisory produce byte-identical rule ids.
- CHECK-6 [AC-7, AC-8] (authentic-success-path): `--file tezt/tests/vuln_report.ml` → against a fixture index with a ⊤ edge on the cone, the verdict is `UNKNOWN` with non-empty reasons; a zero-binding advisory is present in the output. **Positive control**: the same fixture with the ⊤ edge removed yields a non-`UNKNOWN` verdict, proving the assertion can fail.
- CHECK-7 [AC-9]: a 49/49-vacuous run's exit code is not a reachability failure, and the summary wording differs from a resolved-but-no-path run.
- CHECK-8 [AC-10]: a heuristic-only scope yields `UNKNOWN`; the output contains no `PASS` and no `PASS_UNDER_HYP`. **Positive control**: `PASS` appears in the output of a fixture where it is legitimate, so the absence assertion is not vacuous.
- CHECK-9 [AC-11, AC-12]: a stored verdict carries both corpus identities; mutating one renders `superseded`; the render performs no network access.
- CHECK-11 [AC-13]: an `UNKNOWN` verdict record's anchor list is non-empty and every entry resolves to an owning function row. **Positive control**: a fixture whose cone is ⊤-free yields a verdict with an empty anchor list, so a non-empty assertion is not vacuous.
- CHECK-12 [AC-14]: the record's declared field set is asserted **structurally** against an explicit expected set — not by grepping for absent words — and the assertion fails if a hypothesis/expiry/discharge field is ever added. **Positive control**: adding a known field to the expected set makes the check fail.
- CHECK-10 [FR-017, FR-024]: the emitted verdict set is a subset of `verdict_vocabulary`, **and** any new producer-written table appears in `schema_tables_to_drop` — the latter is already enforced by `tezt/tests/schema_drop_list.ml`, so this check asserts the new table is covered by it rather than re-implementing the scan.

**Authentic path**: CHECK-1 and CHECK-6 reach the real consumer boundary — a real index, the real
`reach_verdict`, the real report renderer. CHECK-2 is the fail-closed path.

## Entities

- `advisory record`: one row per OSV advisory as published, carrying its raw `ecosystem_specific`
  object verbatim plus parsed binding rows; append-only.
- `binding`: one fully-qualified OCaml value path from `ecosystem_specific.affected_bindings`.
  **The field has no specification anywhere** — OSV declares `ecosystem_specific` out of normative
  scope, and the producing tool declares the field optional with no doc comment. `Make()` is one
  observed precedent, not a rule.
- `binding classification`: `present` | `absent` | `inexpressible` — where `inexpressible` means
  the index's naming scheme cannot express the target at all, distinct from the target being
  missing from this program.
- `reach verdict`: the value `reach_verdict` returns. **Deliberately not named `verdict`** —
  `specs/exn-raise-sets.md:212` already defines `verdict` as
  `BOUNDED / UNBOUNDED (⊤) / BOUNDED_UNDER_HYP(externals_pure)`, a different vocabulary.
- `advisory corpus`: the ingested advisory set, identified by the source archive's digest.
- `code corpus`: the index the verdict was computed over. Drifts independently of the advisory
  corpus; conflating the two was a defect in the brief.
- `verdict record`: a durable row pairing an advisory, a rule and a reach verdict with both corpus
  identities, per-value provenance, and — for an `UNKNOWN` — the ⊤ anchors that blocked the proof
  with their owning functions. **Explicitly not a discharge ledger** (roadmap 3.2): it records what
  an analysis answered and discharges nothing. Roadmap 3.2's object is
  `discharges(top_anchor, hypothesis, author, justification, anchor_digest, created_at, expires_at)`
  plus `arch-rules --assume <ledger>` — a mechanism for a human to admit a hypothesis so a ⊤ anchor
  stops blocking. The only thing this feature owes it is FR-025/FR-026: name the anchors, keep
  their owners. Nothing else.

## Accepted limits, stated rather than implied

- **An explicit field makes a claim deliberate, not truthful.** Requiring provenance at write time
  removes the paragraph that happened to contain a package name; it cannot remove an agent that
  writes the field for work it did not do. This spec does not claim otherwise.
- **`affected_bindings` is an unspecified convention** and can change without notice. FR-003 stores
  the raw object so a later reader can see what the field looked like when the verdict was made.
- **Today every verdict is `UNKNOWN` or vacuous**, on both corpora, by measurement. The feature's
  value in this state is that it says so. Converting those to `PASS` is the ⊤-frontier work's job,
  and that dependency is measured, not assumed.

## A trap this spec names so no implementer reuses it

Two closure disciplines coexist:

| closure | ⊤ handling | site |
|---|---|---|
| `Arch_graph.closure` + `g.tops` consulted for escaping nodes | ⊤-aware | `arch_graph.ml:129-146`, used by `arch_rules.ml:589-605` |
| `WITH RECURSIVE … WHERE c.kind IN ('MUST','MAY_ENUMERATED')` | **silently drops ⊤ edges** | `arch_effects_queries.ml:78, 114, 123` |

The second stops at every unresolved edge and reports what it found, with nothing recording the
truncation. Correct for effects queries; here it would manufacture the exact false negative this
feature exists to prevent. **Nothing marks it as unsuitable at its call site.** Any implementation
of FR-013 or FR-015 that reaches for a ready-made SQL closure must use the first, not the second.

---

## Sequencing — a recorded position, not a pending action (2026-09-06)

This section exists because the argument below was made **against this spec's own
implementation**, and it evaporates if it stays in a conversation. It is a finding whether or not
anyone acts on it.

**The position.** Roadmap 3.7 (closed-world enumeration), **functor half specifically**, has a
claim to precede 3.1's implementation. Grounds:

- The dominant limit is measured: on proto_alpha the exported cone reaches **5 282 of 14 452
  nodes** (rebuilt 2026-09-06). Two thirds are out of view, and the closure stops at every
  unresolved edge.
- The frontier's composition — *measured 2026-09-05 on `main` `70cb47f` by two independent
  sessions, roadmap item 0.8, NOT re-derived here*: `callback_param` 153 157, `module_param`
  117 048, `ambiguous_unit` 16 151. The single largest concentration is ~26 000 edges reaching
  `Saturation_repr` through one functor parameter.
- 3.7's prerequisites (1.1, 1.4) are **shipped**, so it is unblocked, unassigned and sized `L`
  with no evidence behind the letter. The roadmap says of its functor half: *"No roadmap item
  covered it… the single biggest ⊤ class."*

**The counter-argument, which is stronger than it first looked.** Measured 2026-09-06: a rule
whose target does not resolve returns `NO_TARGET` **before any cone is walked**, and all 49
bindings resolve to nothing today. So **resolving ⊤ edges converts nothing until ingestion
works** — 3.1's current blocker is its own ingest, not the frontier. The earlier framing
("every answer would be I-don't-know, so defer") rested on a figure that was projected rather than
measured, and is corrected in the intake.

**The number that would decide it, and which was NOT run.** *How many of the ~26 000 functor-param
edges resolve if one enumerates only functor applications whose argument is inside the index?* That
bounds the **benefit** of 3.7's functor half. It does not bound its **cost**, which remains
unmeasured — the `L` is a label. A decision needs both; this spec has neither.

**What is settled and worth carrying regardless:** ⊤ is evaluated **per rule**, not per corpus
(`escaping` is filtered over that rule's own source-set closure), so a corpus-wide unresolved rate
never licenses a claim about any particular verdict. On targets that DO resolve, the measured
distribution over 30 proto_alpha rules is 26 `UNKNOWN` / 3 `POSSIBLE` / 1 `VIOLATION` — so even a
fully-working ingest returns an actionable verdict about **13 %** of the time on this corpus.
