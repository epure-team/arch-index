# Measured self-reference attribution

Root executed the archive-based diagnostic on2026-09-16. Report:
`improvement/2026-09-16-cfa/self-2x2-3588668-1789552672545/report.json`
SHA256 `affd5cdc16f63411fca987c948028778d5b5967bf3343e3f35b014f1a7903b79`.

S0 is exact committed c397efd; S1 is its manifest-owned overlay, excluding
foreign pre-task dirt. Both fresh archive builds use OCaml5.3. Source/CMT/tool
pins are stable before/after; copied S1 library sources equal the active source.
No extra Git worktree was created. Root verified the owned build parent
`/tmp/arch-cfa-self-2x2-VBjo21` no longer exists after successful measurement.

| Cell | Engine | Corpus | Modules | Functions | Calls | Origins |
|---|---|---|---:|---:|---:|---:|
| A | E0 | C0 | 25 | 1013 | 6425 | 583 |
| B | E1 | C0 | 25 | 1013 | 6425 | 583 |
| C | E0 | C1 | 27 | 1082 | 6804 | 603 |
| D | E1 | C1 | 27 | 1082 | 6804 | 603 |

Root independently compared full canonical call and origin arrays, origin
groups, module populations and totals: A=B and C=D, not merely equal counts.
The self-reference change is source-only on these two corpora. This conclusion
does not say the engine is unchanged on Tezos or all inputs.

The source delta has1413 removed/1792 added call rows and132 removed/152 added
origin rows, including location/name shifts; exact multiplicities are retained
in the diagnostic. New origin-group counts versus old: exception/compare52→54,
exception/invalid_arg1→4, option/raise331→346. Other groups are unchanged.

## The existing assertion exemption

Both A/B contain exactly one assertion origin:
`collect_calls_from_expr_with_open_bodies.<fun:1617:21>.<fun:1628:36>` at1631:27.
Both C/D contain exactly one assertion origin:
`collect_calls_from_expr_with_open_bodies.<fun:1708:21>.<fun:1719:36>` at1722:27.
Form/channel/exception/multiplicity remain assert/exception/Assert_failure/x1.
The exact `alias_rewrite` source block containing this assertion is byte-equal
between c397efd and current source, SHA256
`9591b8afe8cf97b371909fee7369a339ce5b5eea934d49781704fd9324f7da1b`.

The script deliberately does not infer semantic identity by stripping anonymous
function coordinates: its descriptor-only relocation result is false. Root's
separate source-block equality and the two engine/corpus comparisons ground the
proposed coordinate-only migration. This is reviewed source evidence, not a
formal proof of the assertion's unreachability.

Unchanged policy holds on A/B with UNKNOWN (open frontier), not a proof PASS;
it fails on C/D because its sole old coordinate no longer matches. No rule or
allowlist was changed. The proposed edit moves exactly this one entry and adds
no exemption. The user explicitly approved the exact-file scope below with
"oui!" on2026-09-16; it is now recorded in the implementation manifest:

- `test/fixtures/self-index-stats.txt`
- `test/fixtures/origin-consumer/reference.json`
- `checks/origin-recurring-consumer.js`
- `test/fixtures/origin-consumer/self.allow`

## Diagnostic corrections, not hidden successes

First execution failed before builds because opam's exec/switch argument order
was wrong. Second execution built both archives but rejected Dune's irrelevant
public CMI symlinks as if they were selected CMT inputs. Both owned temporary
trees were cleaned by finally; neither attempt qualified the matrix.
Root added a behavioral failing assertion for the CMI case, then accepted only
irrelevant file links while still refusing selected-input/directory links.
The corrected pure test and third full diagnostic passed. The earlier agent's
module-absent exit2 was setup failure, not behavioral RED.
