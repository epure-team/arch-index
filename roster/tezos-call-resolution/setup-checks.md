# tezos-call-resolution comparison setup

Status: comparison prerequisite complete; product iterations remain 0/5. This
setup never authorizes retention.

## TDD evidence

- RED: `rtk proxy node roster/tezos-call-resolution/check-comparison.js`
  exited 1 with the observed assertion `reordering identical rows must be
  neutral`. This was not an import, command, or fixture setup failure.
- GREEN: the same command exits 0 with `PASS comparison checker (21
  assertions)`. It covers neutral reorder, duplicate loss, target swap, kind
  mutation/new MUST, ambiguous same-line changes, unreviewed and unrelated
  same-file targets, cross-file and callback refusals, alias metric exclusion,
  malformed rows, missing/wrong databases, missing identities, canonical DB
  joins, positions, and digest creation.

## Baseline and replay evidence

- `verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self`
  exits 0: 45,018 rows, digest
  `4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd`,
  zero row/relation changes, classification `self`.
- `verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db`
  exits 0 after a fresh absolute-producer fixed410 run from the Tezos cwd:
  45,018 rows, the same digest, zero changes, classification `neutral_replay`.
- Pointing `--baseline` at the sibling `replay.db` exits 2 because
  `provenance.json` binds `baseline.db`; a naked or merely equivalent DB is
  deliberately untrusted.

The runner checks the pinned provenance and baseline producer, exact manifest
digest and 410 artifact destination set, input hashes before/after, catalogue
run cardinality, catalogue/binding `collected` join through referenced modules,
SQLite integrity and complete call joins. It snapshots producer, schema, active
scope, arch-index status, Tezos revision/status, and corpus inputs before the
run and rejects changes afterward. Symlinks and the candidate DB live in an
owned `mkdtemp` outside Tezos `_build`; the producer uses absolute paths and the
Tezos cwd. Per-run evidence is under ignored
`improvement/2026-09-14-tezos-resolution/`; root recorded baseline iteration0 in `results.tsv` after setup passed.

## API and witness boundary

`comparison.js` exports `snapshotDatabase(dbPath, options)` and
`compareSnapshots(oldSnapshot, newSnapshot, options)`. Canonical multisets keep
all rows (including `value_alias`), nulls, display callee, kind/form and TOP
metadata. The primary relation set alone excludes `value_alias` and is
deduplicated. Reports retain complete changed groups and caller/target line
positions; SQLite IDs are never cross-run identity.

Candidate verification accepts `--witness FILE`. The JSON object must bind
`baseline_digest` and `candidate_digest` and contain `transitions`; every item
must provide exact positioned `before` and `after` facts plus non-empty
`reviewed_by`, `reviewed_at`, and `source_evidence`. Without that exact reviewed
witness, even a same-file `module_param`-to-body shape refuses. A witness only
permits comparison; `retention_authorized` remains false.

The first candidate added seven regression assertions (28 total): exact reviewed
display changes, duplicate occurrence consumption and separately witnessed
overapplication residuals. No generic name-change/TOP allowance exists. Residuals
must consume a reviewed ordinary head and prove supplied arguments exceed body
arity. Root replay on 2026-09-14 passed with831 exact transitions,34 residuals,
795 new distinct relations and zero losses. Report:
`improvement/2026-09-14-tezos-resolution/2026-09-14T05-46-32-165Z-candidate-2339422/report.json`.
This is comparison approval, not a keep; native/full/roster/CI remain separate gates.
