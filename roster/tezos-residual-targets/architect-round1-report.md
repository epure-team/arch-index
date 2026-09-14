# Architect review — round 1 / cycle 1

Date: 2026-09-14. Reviewed repaired commit
`436cbfc667a5f01880fd9c11f53242c8fffb6ed3` against predecessor
`fb9c8f3f685d751ee07a81c17fb1ca61860a7365`; the complete branch delta against
`origin/main` was also inspected. Scope admission is the coordinator's actual
scope-gate result (exit 0), not a finding inferred from filenames here.

No critical, warning, or optional architecture finding was identified. Findings
JSON is `[]`. Overall architecture risk for the reviewed change is **low**. This
is a specialist structural assessment only; it is not an aggregate GO,
retention, shipping, merge, or attempt-advance decision.

## Independence disclosure

This Sol agent previously supplied the brief-only planning Voice 1 and later
performed the bounded C/D self-attribution diagnostic. It did not author the
product implementation or reference changes. Reuse caused by the fresh-Terra
spawn/thread limit means this is not claimed to be a fresh, planner-blind
review. The architecture analysis and all gates below were nevertheless
performed personally rather than borrowed from the owner or spec reviewers.
This reviewer does not approve its own diagnostic as authority for any
reference refresh.

## Architecture assessment

- **Body provenance remains body-safe.** `build_local_fn_stamps` remains the
  sole body/arity table. `local_module_value` represents `Direct_body` and
  `One_hop_alias` distinctly, and alias admission only reuses an already-known
  same-CMT body's stored name and syntactic arity. Alias declarations therefore
  do not acquire body status, zero arity, or MUST eligibility.
- **Ownership and identity remain local.** The target context is constructed
  per CMT, rooted by compiler `Ident`, and never persisted across compilation
  units. Member lookup occurs only after owner resolution. Source-order masks,
  ordinal-qualified body names, opaque owners, applications, unpacks,
  qualified/persistent RHSs, and alias chains retain their refusal paths. The
  separate compiler-native witness validates UID/declaration layering without
  feeding a name fallback into the product.
- **Consumers are structurally separated.** Direct-only
  `local_module_target` remains the point-free consumer; invocation-only
  `local_module_invocation_target` admits the one-hop variant for application,
  callback, and letop sites. The repaired `pending_call.local_module_invocation`
  flag is occurrence provenance: it defaults false and is set only when that
  row actually used owned invocation lookup. The flat consumer selects the
  alias-expanded ownership set only for such rows, so unrelated direct,
  parameter, bare-callback, point-free, and return-residual rows cannot inherit
  alias ownership merely by sharing a displayed target name.
- **Flat attribution stays fail-closed.** Even a marked owned invocation gains
  `callee_file` only when the actual same-file symbol exists; a foreign homonym
  cannot fill the gap. The repaired native control pins both the supported
  positive/absent-symbol cases and the previously regressed legacy forms.
- **The added coupling is bounded and explicit.** One boolean crosses the
  pending-call API to the only downstream consumer that needs occurrence-level
  provenance. This is less ambiguous than deriving provenance from
  `Head_enumerated`, target-name membership, or `edge_form`, all of which cover
  broader pre-existing behavior. No schema, dependency, public CLI, or
  cross-CMT registry was added.
- **Comparison setup remains separate from product gain.** CHECK3 invokes the
  pinned frozen producer and validates its canonical predecessor; CHECK4 runs
  the current producer against that predecessor, accounts for the exact
  multiset movement and native witness multiplicity, and explicitly reports
  `retention_authorized: false`. Point-free movement and new MUST facts remain
  independent refusals rather than being inferred from relation totals.

## Personally executed gates

Every command was run sequentially with the required `rtk proxy` prefix. No
failed command was retried or replaced with another reviewer's result.

| Gate | Command after `rtk proxy` | Exit | Observed result |
| --- | --- | ---: | --- |
| Build | `opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Completed with no output. |
| Full suite | `opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | 332/332 Tezt successes plus unit suites; controlled negative-path diagnostics did not fail the suite. |
| Bundle | `node scripts/review-bundle-verify.js` | 0 | 22 files present and SHA-matched, bundle 1.6.0. |
| Whitespace | `git diff --check` | 0 | No diagnostic. |
| CHECK1 | `node roster/tezos-residual-targets/check-native.js` | 0 | Pending metadata/body-only assertions passed; all 5 feature Tezt cases succeeded. |
| CHECK2 | `node roster/tezos-residual-targets/check-comparison.js` | 0 | 3 native positives, 12 refusal controls, paired admission positive plus 10 refusals; 38 assertions. |
| CHECK3 | `node roster/tezos-residual-targets/prepare-baseline.js --check` | 0 | Frozen replay: 45,052 rows; Irmin 4,772; protocol 11,615. |
| CHECK4 | `node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json` | 0 | Candidate PASS: 124 removed/124 added, 0 relation loss, 124 gains (Irmin 9, protocol 115), no errors; retention unauthorized. |
| CHECK5 | `node roster/tezos-call-resolution/check-self-index-smoke.js` | 0 | 25 modules, 989 functions, 6,275 calls. |

CHECK4 produced the candidate evidence directory
`improvement/2026-09-14-tezos-resolution/attempt2-2026-09-14T17-25-24-471Z-889267/`.
Baseline digest is
`90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`;
candidate digest is
`00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b`.
These are candidate-review facts, not a retention claim.

No product, spec, brief, reference, manifest, commit, PR, or worktree was
modified by this architecture review. Only this report and its findings file
were written after the personal gates completed.
