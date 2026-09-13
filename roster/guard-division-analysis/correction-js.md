# R1 JavaScript checker correction evidence

Date: 2026-09-13. Scope: independent checker, private fixture helpers/data,
exact Tezt dependencies, and the coordinated two-selector repair in the already
owned private fixture probe. No production analyzer semantics changed.

## Authentic RED / GREEN

- Wrong-reason RED: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js report` exited 1 because an authentic `MAY_ZERO` report changed to vocabulary-valid `divisor_nonzero_if_reached` was accepted by the old validator (`Missing expected exception`). GREEN requires exactly the status's one semantic reason, metadata only; UNSUPPORTED requires an actual exclusion and forbids numeric reasons.
- Selector RED 1: inventory exited 1 after `--identifier-bytes 257 --operand-slot 1`; the actual CLI retained slot-2 spelling `divisor` instead of null. GREEN fixes identifier spelling mutation to original slot 2.
- Selector RED 2: inventory exited 1 after `--operand-type unresolved --operand-slot 1`; independent post-mutation observation was `[int, unresolved]`, expected `[unresolved, int]`. GREEN makes the type selector honor the requested slot. Both controls now pass.

## R1 coverage

| Obligation | Source/seam and assertion |
|---|---|
| Native binding/entry/exclusion matrix | `r1_cases.ml`; 36 stable IDs, exact status/reason arrays and exact census 19 covered/17 unsupported/6 precision gain |
| Existing numeric baseline | 26 independent source snippets with exact reasons; original `inventory.ml` remains 12 sites and its line/status oracle is unchanged |
| Application eligibility | Private rewrite seam: later saturation, overapplication, labels, missing slot, and overapplied-all ancestry; exact site counts, slot-2 metadata and accumulated reasons |
| Type eligibility/guards | Both operand slots × non-native/unresolved; both guard slots × non-native/unresolved; mutation flags and exact reports |
| Opaque/method/effect dispatch | Native R1 ordinary/unlisted/indirect/method cases plus four declared effect-primitive seams; exact reasons and no invented indirect site |
| Ordering/identity | Distinct accepted artifacts reversed produce byte-identical JSON; canonical repeat dedups; copy collision rejects; duplicate coordinates retain 12 IDs |
| UTF-8/location/output | Exact 256/257 multibyte identifier bytes, no truncation; invalid/ghost/cross-file/backwards/max-column text+JSON projections; 16 MiB inclusive/one-over |
| Text/JSON context | Actual 12-site all-five-status fixture: every artifact, ID, status, primitive, source coordinate, reason and census value plus every assumption/limitation; same oracle rejects omitted and duplicate site fields |
| Package/wrapper | Direct and wrapper help/version exit 0; isolated copied wrapper missing binary exits 2 and creates nothing; fresh manifest has public CLI and no private library; four probes exist |

`scripts/check-arch-guard.js` is 490 lines after extracting the closed report
oracle and numeric table into auditable private helpers. Both helpers are exact
Tezt runtime dependencies. Child executions retain 120-second and 16-MiB
combined-output caps; assertion/setup controls remain 1/>=2.

## Verification

- `rtk proxy git diff --check`: exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`: exit 0.
- Six independent checker modes (`inventory`, `numeric`, `domain`, `inputs`, `report`, `owned`): all exit 0. Domain: 640734 probe results and 23219242 law assertions. Owned census: 23 artifacts, 0 sites (reported honestly).
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-guard-report-context.js`: exit 0, empty/classified JSON/text PASS.
- `--assertion-control`: exit 1; `--execution-control`: exit 2.
- Final `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`: exit 0, 256/256 Tezt and 64 Alcotest (3+8+17+10+7+19).
- The known `opam lint` exit 1 is pre-existing non-gating metadata debt; optional `odoc` is absent. Neither is claimed as a pass and neither authorized metadata/dependency changes.

No numeric-analysis product mismatch was found. The private selector defect was fixed
without weakening the oracle. The fixture selector is private postorder; flat
seed ordering happens to coincide with public preorder IDs, which remain tested
as public output rather than inferred from the seam selector.

Follow-up RED found a real FR-043 text projection defect: raw newlines in an
accepted CMT path/source split one site across physical lines. The maintained
positive report check failed at `missing exact text projection`; production was
then minimally corrected to JSON-quote artifact paths and non-null source names.
Space, newline, and delimiter-like ` id=` paths now project faithfully as one
line. Persistent negative controls reject duplicated site lines and exclusion
reasons attached to numeric statuses.
