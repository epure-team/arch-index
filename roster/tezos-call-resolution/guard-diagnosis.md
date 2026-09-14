# Attempt 1 guard diagnosis — 2026-09-14

Status: scope approval required; no keep, review GO, PR or merge.

The first post-product `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` terminated with exit 1 (session 8451): Tezt 321/324 passed. Raw Dune trace is preserved at ignored `improvement/2026-09-14-tezos-resolution/attempt1-guard-trace.csexp`. Negative-test stderr alone is not failure evidence; the three explicit FAILURE results are.

## Shared compatibility oracle (two failures)

`functor catalogue independent checker: compatibility` fails at `scripts/check-functor-catalogue.js:222`. Its fixture declares a real same-CMT structure `A` with function `run` (line 213). The previous JSON oracle expects unresolved `A.run` rows at fixture lines 7 and 9. The candidate selects body ID 1 as MAY_ENUMERATED, with null TOP fields. Deterministic ordering also exchanges call IDs 9/10 for the two line-9 rows. These are expected precision changes, but must be checked explicitly, not hidden by dropping columns or assertions.

`functor bindings independent checker: compatibility` invokes the same checker at `scripts/check-functor-bindings.js:1080–1087`; it is not an independent binding-table regression.

Required proposed scope extension:

- `roster/functor-instance-resolution/compatibility-rich-baseline.json`: review the exact changed rows and preserve all other table checks.
- `scripts/check-functor-catalogue.js`: review query verdict literals at lines 201–204. A.run no longer contributes the line-7 TOP reason, while the unresolved application-result M.run at line 8 must remain.
- `roster/functor-instance-resolution/compatibility-baseline.md`: preserve historical observations and append the explicit capability-specific change to the old preservation contract; do not retroactively rewrite past QA evidence.

## Origin recurring consumer (one failure)

`origin recurring consumer: authentic` fails first on production exit status at `checks/origin-recurring-consumer.js:54`. Both the Sol diagnostic agent and root independently reproduced `rtk proxy node checks/origin-recurring-consumer.js authentic` → exit 1, assertion `1 !== 0`.

The agent's read-only diagnostic reports current self-analysis totals 25 modules / 980 functions / 6241 calls / 561 origins versus reference 25 / 956 / 6145 / 554. The seven added origins are option/raise. Review these differences before changing the reference.

The current allow entry targets the former `split_last` assertion at line 1388 and lambda locations 1374/1385. Source inspection now locates the same nonempty-segment recursive case at `lib/arch_index/arch_index_cmt.ml:1495–1509`, assertion line 1509. This is an evidence-coordinate change, not permission to blanket-allow new origins. The reviewer must recheck the nonempty-list premise.

Required proposed scope extension:

- `test/fixtures/origin-consumer/self.allow`: update only the reviewed assertion witness.
- `test/fixtures/origin-consumer/reference.json`: regenerate with current provenance and inspect all changed totals/origin groups.
- `checks/origin-recurring-consumer.js`: update the corresponding hardcoded reference assertions at lines 55–58 only after evidence review; keep all failure-injection checks intact.

None of these six paths is in the validated implementation scope. None was edited. Existing historical gate-result files must remain historical. No additional worktree was created. Full implementation completion, exact fixed410 witness approval, independent roster review/QA and hosted CI remain pending.
