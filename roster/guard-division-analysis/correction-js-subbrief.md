# R1 JavaScript checker integration sub-brief

Execute only after OCaml specialist handoff and explicit Dune ownership release.
Use the existing active worktree, no new worktree. Read RTK, roster-implement,
tdd-workflow, `.claude/agents/implementer.md`, the complete normative spec and
validated implementer brief, R1 findings and `correction-ocaml.md` handoff.

## Ownership

Own `scripts/check-arch-guard.js`; owned test data/helper files within
`tezt/fixtures/arch_guard/`; and exact Tezt dependencies in `tezt/tests/dune`.
Do not edit production OCaml, the frozen standalone report-context ratchet,
pins, reference data, existing extraction or unrelated scripts. Root owns
phase summaries/ledger, commits and final gates. Share the active checkout;
preserve root/specialist edits. All commands `rtk proxy`; all compiler/Dune-backed
commands use `opam exec --switch=/home/mathias/dev/arch-index --`.

Keep test code auditable: use fixture tables/private helper modules in the
already scoped fixture directory if necessary, not a monolithic checker or a
new broad scripts prefix. Declare every required runtime helper/data file as a
Dune dependency so incremental tests cannot silently reuse stale results.

## Required behavior

- Inventory: actual CLI over owned native and specialist-generated seam artifacts;
  immediate cardinality, original slot2 metadata, later saturation/overapplication/
  labelled/missing-slot cases, all accumulated exact reasons and type eligibility.
  Label seam-only malformed compiler-tree shapes honestly, never compiler-native.
- Numeric: retain original26 cases and original12-site inventory expectations.
  Add all specialist native/seam cases and assert exact sorted reasons as well
  as statuses, cardinality and census. Expectations come from spec/source
  reasoning, not observed producer output. Unknown/unlisted/indirect calls are
  opaque Top; sticky unsupported ancestry survives fresh function entries.
- Status-aware report oracle: numeric statuses require exactly their conditional
  semantic reason, plus any applicable metadata reasons. UNSUPPORTED needs at
  least one actual exclusion reason and cannot carry a numeric semantic reason.
  Keep the closed vocabulary and sorted/deduplicated reasons. First demonstrate
  the current validator accepts a wrong semantic reason using an authentic
  produced report; then fix the validator and retain negative sensitivity checks.
- On one actual multi-site all-five-status fixture, compare each text site's
  artifact, ID, status, primitive, reasons and source location, plus every census
  value, with JSON. Check every shared context statement. Include an omitted-field
  negative control that exercises the same oracle, not an unrelated assertion.
- Reversed distinct accepted artifacts must yield byte-identical outputs, not
  merely equal parsed objects; retain canonical dedup and duplicate identity
  rejection. Duplicate coordinates retain separate stable IDs and ordering.
- Exercise exact256/257 UTF-8-byte identifier boundaries with no truncation,
  including multibyte strings, from the specialist seam; preserve ghost/invalid/
  cross-file/backwards/max-column and output-boundary controls.
- Help/version must exit0. Wrapper must dispatch an existing binary; missing
  binary control uses an owned isolated copied wrapper so the live binary is
  never moved/deleted. Verify no build/install side effect. Fresh installation
  manifest contains public arch_guard but no private library payload; probes
  still exist/work. Do not nest Dune under the Tezt checker.
- Preserve six independent mode entrypoints, 0/assertion1/setup>=2 semantics,
  120-second and16-MiB combined child-output caps. Test failures are not setup
  successes. No Tezos/external corpus scans, formal proof or precision claim.

## Verification / handoff

Capture authentic validator sensitivity RED before its correction. Do not force
new coverage-only native cases to fail if existing production already meets the
spec: record preexisting PASS and improve oracle coverage. If a real semantic
mismatch appears, stop and give root the exact minimal fixture/status/reasons;
do not silently weaken expected behavior or alter out-of-owned production.

Run full build before the full forced suite, all six standalone checker modes,
the new standalone context ratchet and both exit controls. No concurrent Dune.
Keep compact exact commands/results and a coverage table mapping every R1
missing case to source/seam mode/assertion. Clean only owned scratch. Write
`roster/guard-division-analysis/correction-js.md`, then return files, outcomes and
remaining risks. Do not commit or update review dispositions yourself.
