# Functor catalogue calibration audit

Date: 2026-09-13. Scope: read-only audit after the first 258-test run reports two failures: the whole-repository `MUST`/NULL ceiling is `462` against `clean_measured=430` plus `headroom=25` (ceiling `455`), and the production origin-recurring consumer is not held. This report makes no calibration claim and changes no pin, reference, or allowance.

## Finding

`462` is a real breach of the current ratchet, not evidence that the pin may be raised. The test calculates the limit from `clean_measured + headroom` and fails above it (`tezt/tests/must_null_ceiling.ml:323`, `:392-403`); its own diagnostic says a row with an indexed root is not necessarily a resolver miss (`:394-402`). The metric is whole `_build/default`, not merely `lib/arch_index` (`:325-354`), and excludes only `Stdlib.*` (`:88-91`). Therefore a functor catalogue change can add ordinary source rows, alter resolver classification on pre-existing source, or do both; the reported scalar `462` cannot distinguish them.

The prior arch-guard calibration is useful as a method, not reusable evidence: it attributes a different base/product pair (`roster/guard-division-analysis/ratchet-source-growth.md:3`), then proves 34 new rows, unchanged multiplicities for every pre-existing `(module path, callee)` group, and no disappearing group (`:5-9`, `:78-80`). The current functor work has changes in the producer and its traversal (`lib/arch_index/arch_index_cmt.ml` is modified relative to manifest base; `briefs/functor-instance-resolution-manifest.txt:1,6`), precisely the situation where semantic regression must be ruled out rather than inferred away.

## Required attribution evidence

After a stable, full build, capture the following in a new reviewable calibration record before any proposed pin edit.

1. Run the existing calibration's pristine four-cell 2x2 against the manifest base `89a15afb51fa89eb0da209a3f611b08b2df31ff3`: A=base binary/base corpus, B=new binary/base corpus, C=base binary/new corpus, D=new binary/new corpus. The tool defines source delta as C-A and behaviour delta as B-A (`scripts/recalibrate.sh:20-35`), creates exactly those four cells (`:1486-1493`), and uses the same whole-build corpus and ceiling query as the Tezt (`:1426-1445`).
2. Accept a source-only attribution only when **A=B and C=D**. B=A alone is expressly insufficient because an extractor change can fire only on the new corpus (`scripts/recalibrate.sh:1719-1745`). Any B!=A or C!=D is semantic/interaction evidence: retain the breach, inspect it, and do not recalibrate it away.
3. For a source-only result, diff the **row identities**, not just totals, for `kind='MUST' AND callee_id IS NULL AND callee_name NOT LIKE 'Stdlib.%'`: `(source path, caller identity, call site, callee name)`. Show every added row belongs to a named new/changed source site, no base-only row disappears, and unchanged pre-existing path/callee groups retain multiplicity. The prior calibration explains why a row set, rather than a count, prevents additions and deletions from cancelling (`roster/guard-division-analysis/ratchet-source-growth.md:37-80`; compare the same lesson in `tezt/tests/must_null_ceiling.ml:250-269`). Also report the test's composition and resolver controls (`tezt/tests/must_null_ceiling.ml:378-391`): total calls, root-outside/root-indexed split, resolver-miss count, and non-zero name-match control.
4. Independently establish build adequacy and provenance: the Tezt rejects an empty/under-built corpus below 8,000 calls (`tezt/tests/must_null_ceiling.ml:370-377`); the calibration tool builds both trees fresh and refuses stale binaries (`scripts/recalibrate.sh:1254-1264`). Preserve the base SHA, head SHA, commands, A/B/C/D values, query, row-set SQL/output digest, changed-file list, and exact proposed delta. Do not use a dirty constant-file run as evidence: the tool documents that uncommitted source edits to `must_null_ceiling.ml` are absent from D (`scripts/recalibrate.sh:1304-1316`).
5. Keep the descriptive self-index golden separate from the normative ceiling. The former is measured over `_build/default/lib/arch_index`; the latter over all `_build/default` (`scripts/recalibrate.sh:1426-1430`). Calibrate/check both, but a valid golden update cannot justify a ceiling rise.

Even clean source-only attribution does not authorize an automatic ceiling increase. `--write` refuses a ratchet loosening and requires the human record of the delta and rationale (`scripts/recalibrate.sh:1815-1838`). Thus `462` may be proposed only after the above evidence; it must not be treated as proven source growth from the current full-suite failure.

## Origin-recurring consumer

The authentic checker is a production contract, not a fixture-only smoke test: it runs the consumer on this checkout, requires exit 0/`held`, exact totals, no coverage deltas, and the one exact allowance (`checks/origin-recurring-consumer.js:50-59`). The consumer compares totals, origin groups, indexed modules, and source-module population (`scripts/origin-consumer.js:89-107`, `:210-217`), then keeps policy failure separate from coverage drift (`:230-234`).

Required evidence is therefore its emitted `run.json`, `gate.json`, report trio and diagnostics from a rebuilt head, plus the directional coverage deltas and policy verdict. A mere reference-total match cannot clear a newly uncovered origin: the checker deliberately proves that matching a changed reference still leaves `policy-failed` (`checks/origin-recurring-consumer.js:75-91`). Establish whether the present failure is `policy-failed`, `coverage-drift`, or `error` before considering any versioned input change.

The reference and an allowance are different decisions:

- A legitimate source-population change may update `reference.json` autonomously under the standing implementation/CI-fix authorization, provided the captured evidence supplies the new revision, module inventory, totals/groups, and explicit reviewed rationale required by `docs/origin-consumer.md:131-136`. This is an observational coverage decision; it does not exempt a finding.
- A newly uncovered origin needs separate source review. An allowance, if justified, must name its exact identity/count and why (`docs/origin-consumer.md:137-142`). The current allowance is explicitly reviewed evidence rather than a proof (`test/fixtures/origin-consumer/self.allow:1-3`; `docs/origin-consumer.md:74-77`). An exemption change is materially different from calibrating an observation and must be escalated separately if the evidence shows it is necessary.

The documentation requires separate rationales and says that a reference update never changes what the evaluator exempts (`docs/origin-consumer.md:140-142`). Thus a reference update cannot waive a `policy-failed` result, but it is not subject to an invented human-only hold.

## Manifest gap

The implementer brief authorizes only `test/fixtures/self-index-stats.txt` and `tezt/tests/must_null_ceiling.ml` for measured self-index calibration (`briefs/functor-instance-resolution-implementer.md:142-159`; manifest entries `briefs/functor-instance-resolution-manifest.txt:26-27`). That is insufficient if evidence shows legitimate origin-observation drift. Add this exact, coupled collateral proposal to the manifest before an observational calibration edit:

- `test/fixtures/origin-consumer/reference.json` — source/module/totals/group observation used by the consumer (`scripts/origin-consumer.js:157-160`; `test/fixtures/origin-consumer/reference.json:1-29`).
- `checks/origin-recurring-consumer.js` — its authentic production assertion pins the exact current totals (`:50-59`, especially `:55`), so a legitimate reviewed reference calibration must update that assertion consistently rather than weakening checker semantics.
- `docs/origin-consumer.md` — durable revision/totals and reviewed-rationale documentation for the new observation, following its deliberate-change procedure (`:131-142`).

`test/fixtures/self-index-stats.txt` and `tezt/tests/must_null_ceiling.ml` are already present, so they are not missing. `test/fixtures/origin-consumer/self.allow` is **not** collateral absent demonstrated need: its pinned location remains unchanged, and a reference calibration cannot alter exemptions. Do not add or edit `scripts/origin-consumer.js` or `scripts/recalibrate.sh` merely to alter expected results; no evidence supports a contract/mechanics change.

## Commands for root after the build is stable

Run read-only evidence first (the first two commands build isolated 2x2 trees themselves; do not run `--write`):

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --explain --base 89a15afb51fa89eb0da209a3f611b08b2df31ff3 --only golden
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --explain --base 89a15afb51fa89eb0da209a3f611b08b2df31ff3 --only ceiling
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js failures
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js package
```

If the authentic check fails, retain its temporary/package diagnostics or run the production consumer into a new dedicated temporary parent and inspect `run.json` before deciding scope:

```bash
rtk proxy bash -lc 'origin_audit_parent="$(mktemp -d)"; opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer.js --out "$origin_audit_parent/report"; opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer-artifacts.js "$origin_audit_parent/report"; printf "evidence directory: %s\\n" "$origin_audit_parent"'
```

The consumer exit must be preserved: artifact validation checks package integrity, not that the policy held (`docs/origin-consumer.md:12-22`). Do not delete the evidence parent until root has copied the result into the review record.
