# Research — recurring analysis report runner

`scripts/origin-consumer.js` establishes the project’s useful publication
pattern: reject an existing output, write diagnostics, emit a final `run.json`
last, and use hashes to detect incomplete/tampered packages.  Its fixed
self-index rule and build/index execution are deliberately *not* copied: this
runner receives a report path and has no authority to build or choose a corpus.

The Stage7 `api-review` profile is the first safe comparison surface.  It
contains producer-published `functions.exposed` inventory facts, so
`file:function` is a stable semantic key within one identical selected scope.
No current stored provenance can separate every `MAY_ENUMERATED` origin by CFA
stage, and `MAY_TOP` must not become an absence.  The first runner therefore
does not compare reachability or treat any API delta as a risk verdict.

Stage7 has producer information but no corpus/scope fingerprint.  A runner
cannot honestly infer one from `db_path`, the list of API facts, or a Git diff.
It therefore requires a version-1 JSON scope manifest on every run and stores
its canonical SHA-256 in `run.json`.  A baseline is a prior `run.json`, not a
bare report, and a differing scope manifest refuses the comparison.  This is
explicit provenance rather than automatic corpus discovery.

Compatibility is deliberately narrow: schema version, profile, producer
identity (name, version, soundness class), API section availability and the
scope manifest must match after canonical JSON normalization. Invocation
digests are retained in each package but are not compared: the current indexer
digest contains its database path and therefore legitimately changes per run.
This detects changed tool/corpus/contracts
before any semantic rows are compared.  Duplicate keys are an invalid producer
output rather than a first-wins choice.  A future `change-review` profile can
provide a richer identity only through a separately versioned contract.
