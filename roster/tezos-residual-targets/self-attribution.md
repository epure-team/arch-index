# Residual-target self-attribution diagnostic

Date: 2026-09-14 (UTC evidence directory timestamp `20260914T162525Z`)

This is a bounded diagnostic over `lib/arch_index`, not a product or reference
update.  It separates producer behavior from corpus/source movement with four
fresh databases and the count/group queries used by
`scripts/origin-consumer.js` (lines 210-211).

## Inputs

- frozen predecessor revision: `fb9c8f3f685d751ee07a81c17fb1ca61860a7365`
- frozen producer SHA-256: `c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8`
- current producer SHA-256: `d050a6c6ac2e9a141cf55eeb0604cf72e8694b8d1678ae43d2d40b6251a23a15`
- frozen and current schema SHA-256 (equal): `1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0`
- pristine baseline CMT inventory digest: `d26e00ce445396a361fddc9c35dbd3970bca3bed84123b928ec03640a4d061a1`
- current-root source inventory digest: `fd785fcde2fa3446b36fdf8f329bd953459723f089ad8d820ef241198ecbc36a`
- current-root CMT inventory digest: `32921b90c8812abf383d370c1837e1d04545110bb942714085932291f6127a0e`

The baseline corpus was built in an owned detached worktree at the frozen
revision with exactly:

```text
opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy dune build --root .
```

Each cell used a separate absent database path.  The frozen producer was paired
with its frozen schema and the current producer with the current schema via
their explicit `--schema-path`; the schema hashes are equal.  Only
`_build/default/lib/arch_index` was indexed.

## Actual 2x2 measurements

| Cell | Producer | Corpus | Modules | Functions | Calls | Origins |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| A | frozen predecessor | pristine frozen worktree | 25 | 980 | 6245 | 561 |
| B | current | pristine frozen worktree | 25 | 980 | 6245 | 561 |
| C | frozen predecessor | current-root incremental build | 25 | 989 | 6276 | 564 |
| D | current | current-root incremental build | 25 | 989 | 6276 | 564 |

The origin-group result is also producer-invariant within each corpus.  The
only A/B to C/D group movement is:

```text
channel=option, form=raise, escapes=1: 312 -> 315 (+3)
```

All nine other `(channel, form, escapes)` group counts are identical.  The
complete ordered group output for every cell is retained in the evidence
directory.

## Attribution

Verdict: **SOURCE_ONLY** for this self-index calibration.

`A = B` and `C = D` for modules, functions, calls, total origins, and every
origin group.  Therefore this experiment observes no producer-behavior effect
and no producer/corpus interaction.  The complete movement is attributable to
the current corpus: `+9` functions, `+31` calls, and `+3` origins, with the
origin delta entirely in escaping option raises.

The current-root corpus is explicitly an incremental, pre-commit build.  This
diagnostic does not replace the required final full pristine rebuild and
measurement after commit.

## Integrity and retained evidence

Before/after byte inventories compare equal for the current producer, all
current `lib/arch_index` `.ml`/`.mli` sources, and all current corpus
`.cmt`/`.cmti` files.  Thus none changed during the experiment.

Evidence is retained under ignored directory
`improvement/2026-09-14-tezos-resolution/self-attribution-20260914T162525Z/`:

- `commands-and-results.log`: shell trace, producer output, measurement and DB hashes, and successful `cmp` checks;
- `A.measurements.json` through `D.measurements.json`: exact count and ordered origin-group query results;
- `input-files.sha256`, inventory listings/digests, and before/after hashes.

The temporary databases and detached build worktree were removed after the
small measurement artifacts and hashes were retained.  No foreign worktree or
the preserved `/tmp/arch-index-resolution-baseline-OmhcEs` directory was
touched.

## Root reference refresh

Root read this complete report and independently compared the consumer's
`attempt2-origin-coordinate-refresh/run.json` coverage observations. The exact
reference totals/groups and golden were refreshed only after the SOURCE_ONLY
result. Reference revision suffix is SHA-256 of UTF-8
`JSON.stringify(run.provenance.sources)` (no trailing newline), after each listed
source was rehashed against its recorded hash:
`2f6feeb50adb5e0eef1898e83be623685afcc5529dbdbe8ffcf09eddc386b284`.
The revision prefix names pre-product HEAD; the suffix names the exact changed
source manifest, not a claim that HEAD already contained the change.

The user's additional approval covers only the one `self.allow` source position.
Its unchanged rule now exits0 with no uncovered site (the rule's evidence remains
UNKNOWN, not a formal proof). Prior to the counter refresh the consumer correctly
returned coverage-drift. No threshold or allowed-site cardinality was changed.
