# R1 OCaml correction evidence

Date: 2026-09-13. Scope: private `lib/arch_guard` implementation, private fixture
seams/data, and component documentation. No existing extraction, rule, database,
origin, reference, or numeric-domain semantics changed.

## TDD and package boundary

- Integrated RED before production edits: forced suite exit 1; only new Tezt
  report-context case 147/256 failed, while the other 255 Tezt and 64 Alcotest
  cases passed. Actual empty and classified CLI text omitted compiler context.
- Minimal GREEN: the shared analysis value now contains explicit indirect-operation
  and omitted-artifact limitations. Text projects linked compiler version, host
  width, and every shared assumption/limitation. The no-argument actual-CLI ratchet
  passed for empty and classified artifacts.
- Fresh package RED after `dune build --root . @install`: an assertion over
  `_build/default/arch-index.install` exited 1 with
  `RED: public arch_guard library artifacts remain installed`.
- Package GREEN: removing only `(public_name arch-index.guard)` retained the
  installed `bin/arch_guard`; no `lib/arch-index/*arch_guard` artifact remained,
  and the private domain/changed-read probes built.
- Root independently archived the ratchet: `red_verified=true`, blob
  `8108aa657905871c8693120bb3168ce40b9d6c0f`, corrected green, not weakened.

## Native fixture oracle for the JS checker

Compile `tezt/fixtures/arch_guard/r1_cases.ml` with the configured `ocamlc
-bin-annot -c`, then invoke the actual CLI. The current authentic result is one
artifact, 36 sites: numeric covered 19, NONZERO 6, ZERO 2, MAY_ZERO 11,
UNREACHABLE 0, UNSUPPORTED 17, precision gain 6. Keep the original 12-site
`inventory.ml` oracle unchanged.

| IDs | Source cases | Exact expected status/reasons |
|---|---|---|
| 1 | alias copied before guard | MAY_ZERO / `divisor_may_be_zero` |
| 2 | alias copied inside guard | NONZERO / `divisor_nonzero_if_reached` |
| 3 | same-spelling shadow binder | ZERO / `divisor_zero_if_reached` |
| 4,5 | simultaneous RHSs in pre-group env | NONZERO, ZERO with matching conditional reasons |
| 6 | nested capture below nonzero parent | MAY_ZERO / `divisor_may_be_zero` |
| 7 | nested fresh local constant | NONZERO / `divisor_nonzero_if_reached` |
| 8 | nested function below contradiction | MAY_ZERO / `divisor_may_be_zero` |
| 9,10 | immediately-applied and curried capture below nonzero | MAY_ZERO / `divisor_may_be_zero` |
| 11,12 | alpha-renamed equivalent guards | NONZERO / `divisor_nonzero_if_reached` |
| 13,14 | immediately-applied and curried functions below contradiction | MAY_ZERO / `divisor_may_be_zero` |
| 15 | optional default containing target | UNSUPPORTED / `unsupported_function_parameters` |
| 16,20 | function-case targets | UNSUPPORTED / `unsupported_function_cases` |
| 17 | recursive binding subtree | UNSUPPORTED / `unsupported_recursive_binding` |
| 18,19 | compound and alias local patterns | UNSUPPORTED / `unsupported_binding_pattern` |
| 21 | try nested in while | UNSUPPORTED / sorted `[unsupported_expression:Texp_try, unsupported_expression:Texp_while]` |
| 22–24 | nested, immediate, curried entries under while | UNSUPPORTED / `unsupported_expression:Texp_while` |
| 25,26 | unsupported loop then independent sibling | UNSUPPORTED/while, then NONZERO/nonzero reason |
| 27 | target in while condition | UNSUPPORTED / `unsupported_expression:Texp_while` |
| 28–30 | for lower bound, upper bound, body | UNSUPPORTED / `unsupported_expression:Texp_for` |
| 31 | opaque call result as divisor | MAY_ZERO / `divisor_may_be_zero` |
| 32 | target as ordinary-call argument | MAY_ZERO / `divisor_may_be_zero` |
| 33 | target under short circuit | UNSUPPORTED / `unsupported_short_circuit` |
| 34 | target under unlisted `%ignore` application | MAY_ZERO / `divisor_may_be_zero` |
| — | indirect `( / )` alias call | no invented inventory site |
| 35 | target as method-call argument, outside `Texp_send` subtree | MAY_ZERO / `divisor_may_be_zero` |
| 36 | target inside method receiver expression | UNSUPPORTED / `unsupported_expression:Texp_send` |

## Private seam modes and exact assertions

All `fixture_probe rewrite` requests must assert JSON mutation flags, so a missing
mutation is a setup error rather than a vacuous pass. `--target-site` is a one-based
private postorder traversal selector: the mapper visits children before counting
the current target. Root corrected the original handoff's erroneous "preorder"
label after reading the implementation. The prescribed flat target seeds have
the same order as public site IDs; do not generalize that equality to nested
primitive expressions. Public report IDs remain preorder as required by FR-013.
`--operand-slot` and `--guard-operand-slot` accept 1 or 2.

| Mode / seed | Assertions for the actual CLI |
|---|---|
| `--application-shape later-saturation --target-site 2`, `inventory.ml` partial seed | mutation true; still exactly 12 sites; site 2 original slot is missing; UNSUPPORTED with sorted `[missing_operand, unsupported_arity]`; outer saturation adds no site |
| `overapplied`, saturated site | original slot 2 retained; UNSUPPORTED / `[unsupported_arity]` |
| `labelled-operand`, saturated site | original slot 2 retained; UNSUPPORTED / `[unsupported_labels]` |
| `missing-second-slot`, saturated site | slot 2 is category missing/null; UNSUPPORTED / sorted `[missing_operand, unsupported_arity, unsupported_operand_type]`; later argument is not shifted into slot 2 |
| `overapplied-all`, `inventory.ml` | sites under loop/try/effect retain ancestry and add `unsupported_arity`; e.g. site 3 `[unsupported_arity, unsupported_expression:Texp_while]` |
| `--operand-type non-native|unresolved --operand-slot 1|2 --target-site N` | `operand_type_changed=true`; either bad operand makes the native site UNSUPPORTED / `[unsupported_operand_type]` |
| `--guard-operand-type non-native|unresolved --guard-operand-slot 1|2`, `r1_cases.ml` | `guard_operand_type_changed=true`; changing either side disables refinement; guarded site 2 becomes MAY_ZERO / `[divisor_may_be_zero]` |
| `--identifier-bytes 256|257`, `inventory.ml` | mutation true; 256 UTF-8 bytes retained exactly with no omission reason; 257 bytes becomes null with `operand_spelling_omitted`; never truncate |
| `--duplicate-coordinates`, `inventory.ml` | all 12 sites remain, one shared coordinate, 12 distinct per-artifact IDs; no rejection/coalescing |
| `effect_fixture_probe --primitive NAME`, `effect_fixture.ml` | for each `%perform`, `%resume`, `%runstack`, `%reperform`: `changed=true`, declared seam-only scope, one nested target, UNSUPPORTED / `[unsupported_effect_primitive]` |

The application/type/location mutations are deliberately trusted CMT seams for
Typedtree shapes not reliably expressible in source. They are not claims about an
authentic compiler producing malformed applications.

## Verification

- Full build: exit 0.
- Forced full suite after the correction and fixture additions: exit 0,
  256/256 Tezt and 64 Alcotest.
- `git diff --check`: exit 0.
- Targeted native/seam runs above: all mutation flags and exact current outputs
  observed; no semantic mismatch required a production change.
- Two later seam-selector controls produced authentic RED before correction. The
  257-byte identifier check exited 1 because `--operand-slot 1` incorrectly moved
  spelling mutation away from original slot 2. The independent final-tree type
  observer exited 1 with `[int, unresolved]` instead of requested
  `[unresolved, int]`. After the two selector fixes, the complete inventory mode
  exited 0: spelling always targets slot 2 and type mutation honors the selected
  slot. The observer, not the shared UNSUPPORTED result, proves which type changed.
- A later authentic FR-043 RED used a source filename containing a newline and a
  CMT path containing spaces, a newline, and ` id=`. JSON remained valid, but raw
  text paths split one logical site across physical lines. Maintained command
  `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node
  scripts/check-arch-guard.js report` exited 1 at
  `checker_report_oracle.js:53`, missing the exact text projection. The minimal
  renderer correction JSON-quotes artifact paths and non-null source filenames;
  missing source remains `?`. The JS owner rebuilt and reran the same maintained
  command: exit 0. Its full build, all six checker modes plus context check, and
  forced suite also passed (256/256 Tezt and 64 Alcotest). After the final
  diagnostic-only fixture wording edit, its rebuild, inventory/report modes, and
  `git diff --check` each exited 0; root owns the final exact-tip full capture.
- `opam lint arch-index.opam`: exit 1 on pre-existing metadata omissions
  (`maintainer`, `authors`, `homepage`, `bug-reports`, `license`). Generated opam
  metadata was not edited outside scope.
- `dune build @doc`: unavailable because optional `odoc` is not installed in the
  configured switch. No global dependency was installed.
