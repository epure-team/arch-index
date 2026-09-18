# Unified architecture reports

`arch-report INDEX.db --out DIR [--rules RULES] [--profile api-review|architecture]` writes `report.json`, SARIF 2.1.0
(`report.sarif`), and self-contained HTML (`report.html`) from one assembled report value.
The database is read, not regenerated or copied.

## Review profiles

`--profile api-review` adds a labelled `api_surface` section. It inventories only
functions whose producer-published `functions.exposed` fact is true; it never
guesses exports from naming or reachability. Each inventory entry is a SARIF
note, not a finding severity or risk score. The existing `top_frontier` count
remains visible and means reachable uncertainty is possible; it does not turn
the API inventory into an alert list.

`--profile architecture` requires `--rules RULES`. It is an explicit named
architecture review using the same evaluator and evidence as the optional
rules section below. A profile name, when supplied, is recorded in JSON, SARIF
properties and HTML so the three artifacts cannot be mistaken for a default
report.

`change-review` is deliberately not available yet. Comparing row IDs or raw
Git text would confuse a changed corpus or unavailable analysis with a code
finding. It will require a semantic baseline and input/tool/configuration
fingerprints before it is offered.

## Recurring API-review packages

`scripts/analysis-report-consumer.js` makes an existing `api-review`
`report.json` reviewable over time. It never builds an index or decides a gate.
Give it the report and a small, versioned scope manifest that names the corpus
and configuration used to create that report:

```json
{"version":1,"corpus":"tezos-proto-alpha@<pinned-input>","configuration":"api-review"}
```

Create a first-run package, inspect it, then compare a later report against the
reviewed package:

```sh
node scripts/analysis-report-consumer.js \
  --report current/report.json --scope api-review-scope.json --out reviews/base

node scripts/analysis-report-consumer.js \
  --report later/report.json --scope api-review-scope.json \
  --baseline reviews/base/run.json --out reviews/later
```

The output directory must be new. A complete package contains `report.json`,
`scope.json`, `delta.json`, `diagnostics.txt`, and a final `run.json` whose
hashes cover the preceding files. Keep or promote a baseline only after human
review; the runner never rewrites one.

The first package has `status: first-run`; its delta says `no_baseline` rather
than inventing changes. A compatible comparison has `status: compared` and
classifies exported API identities as `new`, `unchanged`, or `absent`, using
only the producer-published `api_surface|file|function` identity. A line move
does not change that identity. An absent API is not a fix, severity, or risk
verdict; the runner does not compare reachability, MUST/MAY paths, or `MAY_TOP`
frontiers.

The runner exits 2 rather than compares if either report is incomplete, the API
section is unavailable, an identity is duplicated, or the schema/profile,
producer identity, analysis coverage, or scope manifest differ. Invocation
digests are retained as provenance but may change with an index database path,
so they do not themselves make a recurring comparison incompatible. Stage7
reports do not contain a corpus fingerprint, which is why the scope manifest is
mandatory and compared exactly. This refusal is intentional: a changed corpus
must not be represented as an API change.

## Optional rule evaluation

With `--rules`, `arch-report` parses and evaluates the rules once through the same evaluator as
`arch-rules`, using the report invocation's already-open read-only database. The resulting rule
entries carry the existing verdict evidence: verdict, exactness where applicable, selector sizes,
detail and its total, note, top reasons, and ordered witness. They identify the evaluator as
`arch-rules`; they do not borrow a version or soundness class from an index producer or imported
finding. Producer metadata remains a separate fact.

`arch-report` is a reporting command, not the CI gate. A report whose rules contain a
`VIOLATION`, `POSSIBLE`, `UNKNOWN`, or another non-PASS verdict still exits 0 once all artifacts
are written. Use `arch-rules` when its policy-controlled exit status is required. Empty,
malformed, or unreadable supplied rule files are errors: the command exits 2 with a diagnostic
before opening any output artifact, rather than silently producing a no-rules report.

Without `--rules`, the eight compatibility verdict counts remain zero placeholders and the report
marks their availability `NOT_COMPUTED` with an explanation. With supplied, successfully evaluated
rules, the census availability is `COMPUTED`, even when a particular rule is `NOT_COMPUTED`.
Census availability, individual rule verdicts, analysis coverage, operand syntax, and producer
soundness are independent facts; none proves or upgrades another.

Each successfully parsed rule receives a one-based declaration ordinal; comments and blank lines
do not consume one. It distinguishes duplicate display names only within that invocation. Complete
rule-result lists retain declaration order. Alert lists use this review order:

1. `VIOLATION`
2. `POSSIBLE`
3. uncertainty: `UNKNOWN`, `UNKNOWN_NO_CONTRACT`, `NOT_COMPUTED`
4. vacuity: `NO_SOURCE`, `NO_TARGET`

Declaration ordinal is the only order within a tier. `PASS` remains in the census and complete
rule-results contract, but is not an alert. This is serialized artifact order for review, not a
confidence, severity, rank, or prediction; SARIF viewers are free to reorder results.

Witnesses are ordered paths and are the only rule evidence represented as SARIF `codeFlows`.
Repeated and logical-only labels are retained as such. In particular, an `UNKNOWN` witness stops
at the observed uncertainty frontier; it is not a claimed path to a forbidden target. Divisor
contexts described below are supporting data, never path steps, flow edges, or fabricated file
locations.

The shared read handle binds evaluation to this invocation only. It is not a transactional
snapshot, a content/freshness certificate, or a guarantee about source files on disk. Run against
a quiescent index; concurrent writers are unsupported.

## Divisor operand context

Native OCaml CMT indexing records syntax-only context only for recognized integer
division/remainder primitive origins. It reads original typed-AST argument slot 2, never the
second argument that happens to be present. The context retains primitive identity, slot number,
and one of `integer_literal`, `identifier`, `other`, or `missing`; integer literals retain their
compiler-recorded kind. Literal and identifier representations are typed-AST display data, not
current-source excerpts or semantic symbol identities.

This feature performs no value inference: no constant folding, range analysis, path feasibility,
or suppression of nonzero literal origins. `other` and `missing` never invent exact source text.
Other origin forms and value channels are unsupported for this context in this release. On old or
flat indexes without metadata, and on SQL `NULL` metadata, context is explicitly unavailable;
missing slot 2 remains missing. Malformed non-NULL metadata, an unknown category, or an invalid
field type is refused diagnostically rather than normalized into unavailable data.

Contexts are supporting data attached to the existing aggregate origin-site identity and an
occurrence position. They preserve row multiplicity but never enter allow-list identity or counts,
alter an allowance, change a verdict, or suppress an origin. The existing 200 displayed offender
site limit remains independent. Per rule result, at most 200 contexts from displayed offender
sites are emitted; `context_total` counts all matching offender-origin rows and
`context_omitted` reports the difference. Context order is site identity, then source line,
column, and row id. A literal or identifier representation is limited to 256 UTF-8 bytes; an
oversized representation is omitted whole with its limit reason while category, primitive, and
slot remain available.

The same structured context, totals, omissions, and availability state are supporting data in
`arch-rules` JSON and in the unified report formats. Consult the generated JSON contract for exact
field layout; it remains the machine-readable authority.

## Publication failures

Publishing the three artifacts is not an atomic transaction. A write failure exits 2 and prints no
success summary; any partial output from that run is unusable. HTML escapes rendered report text.
