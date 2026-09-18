# Roster intake — CI cache acceleration

## Objective

Reduce repeat GitHub Actions setup cost with caches whose keys are derived from
the inputs that actually determine their contents, without weakening any build,
test, tool-probe, or measurement gate.

This intake is independent of the FFI roadmap and changes only CI/cache
configuration plus its own evidence package.

## Baseline

Six successful pull-request runs sampled on 2026-09-17/18
(`35279505841`, `35282676105`, `35285235501`, `35312584514`,
`35313819059`, `35314923899`) put the median `build` job at about 13m18s.
The median dominant steps were:

- `Unit and integration tests`: about 7m18s (55% of the job), with one 14m42s
  outlier;
- `Install deps`: about 2m50s (21%);
- `ocaml/setup-ocaml`: about 51s;
- `Install language servers`: about 43s;
- repository `Build`: about 15s;
- `Recalibration gate (self)`: about 30s.

The target is therefore not a claim that caching can remove the seven-minute
test workload. It is a bounded setup optimisation, with cache hit/miss evidence
kept separate from test execution time.

## In scope

1. Repair the currently ineffective built-in Go cache by pointing
   `actions/setup-go` at both tracked Go checksum files.
2. Preserve every existing installation command and executable probe on both a
   cache miss and a cache hit.
3. Record why opam, Dune and npm receive no broader cache in this change.
4. Validate workflow syntax, a cold/miss run, a warm/hit rerun, and the complete
   unchanged test suite before merge.

## Acceptance evidence

1. The setup-go log no longer says that a root `go.sum` is missing.
2. The first run either restores an existing exact cache or reports a clean
   miss and saves `GOMODCACHE`/`GOCACHE`; a rerun on the same PR ref reports an
   exact cache hit.
3. The Go key is invalidated by either `callgraph-go/go.sum` or
   `callgraph-go/effects/go.sum`, as well as the runner image/architecture and
   configured Go version already included by `actions/setup-go`.
4. `gopls version`, `typescript-language-server --version`,
   `rust-analyzer --version`, `ocamllsp --version`, the build, and all unit and
   integration tests still run and pass.
5. The PR diff contains only this Roster intake and CI cache configuration.

## Non-goals

- Skipping, selecting, sharding, or parallelising tests.
- Caching test verdicts, `_build`, generated databases, release artefacts, or
  recalibration measurements.
- Freezing opam resolution without a reviewed lock file.
- Replacing global npm language-server installation without first introducing
  a lock file for those tools.
- Enabling the deprecated `ocaml/setup-ocaml` Dune-cache input.

## Rollback

Remove `cache-dependency-path` from the setup-go step. The install and test
commands are otherwise unchanged, and cache failures are already non-fatal in
`actions/setup-go`.
