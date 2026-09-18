# CI cache acceleration research

## Observed bottleneck

The current workflow is slow, but mostly because it performs real integration
work rather than because all dependency caching is absent. Across the six
successful PR runs listed in `task.md`, the median `build` job was 13m18s and
the median test step alone was 7m18s. The slowest sampled job (20m34s) spent
14m42s in tests. Recent logs show deliberate external-process work in that
step, including LSP readiness/timeouts and temporary Go/OCaml projects; a cache
must not turn those tests into previously recorded verdicts.

## Existing cache behaviour

### opam

`ocaml/setup-ocaml@v3` already has `cache: true` by default. Run
`35313819059` restored the exact 123 MB opam cache key, then deliberately ran
`opam update` and rebuilt project dependencies. This is expected: the action's
v3 documentation states that it caches the opam root and initial local switch,
but intentionally does not cache `opam install . --deps-only` results when the
project has no lock file. `arch-index` has generated `arch-index.opam` but no
`opam.locked`; caching the resolved switch under only that manifest would let a
continuously hot key freeze repository resolution and reuse stale packages.

Decision: keep the existing setup-ocaml cache. Do not add a custom `_opam`
cache until a separately reviewed lock-file workflow exists; then require OS,
architecture, exact compiler, opam version and lock digest in the key, followed
by `opam install . --deps-only --locked` even on hits.

### Dune

The repository build step has a median cost of only about 15s. Most of the test
step is runtime integration behaviour, not compilation. Persisting `_build`
would allow Dune to consider test aliases already built and is therefore not an
acceptable optimisation. The setup-ocaml `dune-cache` input is deprecated in
v3, uses a broad workflow/job/compiler restore prefix, and would add cache
transfer/trim cost to every job.

The recalibration step already opts into `DUNE_CACHE=enabled` with copy storage
for safe sharing between its two pristine worktrees *within the same run*.
That step has a median cost of about 30s, so adding a potentially large
cross-run cache has no evidenced positive payoff and increases eviction and
stale/non-reproducible-rule risk.

Decision: no cross-run Dune cache and no `_build` cache. A later experiment
would need rule-level proof that every cached target is a build artefact, never
a test or measurement result, plus before/after transfer timings.

### npm

The repository has no root `package.json` or npm lock file. setup-node therefore
cannot derive a supported dependency key for the two global language-server
installs. Caching the global prefix would be unsafe: it would restore executable
trees without reinstalling/probing their declared versions, and `typescript@5`
is a major-range request rather than an exact package lock.

The npm content cache (`~/.npm`) is safer than the global prefix, but the whole
language-server step has a median cost of about 43s including Go downloads and
the rust-analyzer component. There is not yet evidence that npm tarball transfer
is material enough to justify custom cache lifecycle and invalidation.

Decision: keep installing and probing both Node tools. If this becomes a target,
first introduce a small lock-file-backed CI tools package, use `npm ci`, and key
setup-node's download cache from that lock file; never cache global executables.

### Go

`actions/setup-go@v5` enables module/build caching by default, but every sampled
log warns that it cannot find `/go.sum` at the repository root. The real module
locks are:

- `callgraph-go/go.sum`
- `callgraph-go/effects/go.sum`

Consequently every run downloads the gopls module graph and gets no persisted
`GOMODCACHE`/`GOCACHE`, despite appearing to have caching enabled. Supplying
both paths is the smallest safe repair. setup-go's implementation keys the
cache by runner OS/image, architecture, configured Go version, and the combined
hash of those files. It stores only the module and compiler caches, not
`~/go/bin/gopls`; `go install golang.org/x/tools/gopls@v0.23.0` and all version
probes still execute. A changed gopls version cannot silently reuse an old
binary because the binary is rebuilt and the Go build cache itself is
content-addressed by compilation inputs.

Expected gain is deliberately modest: less module transfer and recompilation
during the language-server install and temporary Go builds. The acceptance gate
is an observed exact hit on a PR rerun, not a promised wall-clock percentage.

## Proposed change

Add this input to the existing setup-go step:

```yaml
cache-dependency-path: |
  callgraph-go/go.sum
  callgraph-go/effects/go.sum
```

No restore prefix is used, so a checksum change is a miss rather than a partial
reuse under an older dependency graph. Cache service failure remains advisory;
the existing install commands provide the uncached fallback.

## Verification plan

1. Run `actionlint` against `.github/workflows/ci.yml`.
2. Confirm the diff touches only the workflow and this intake.
3. Push a dedicated PR based on current `origin/main`.
4. Inspect the first setup-go log for resolved dependency files and save/miss
   evidence; require the complete CI job to pass.
5. Rerun the same PR workflow once and require `Cache restored from key` plus
   the same build/test/probe gates. Compare setup and language-server timings,
   but report runner variance rather than claiming causality from one pair.

## Evidence sources

- GitHub Actions run/job timestamps and logs for the six run IDs in `task.md`.
- `ocaml/setup-ocaml@v3` `action.yml`, README caching section, and cache source.
- `actions/setup-go@v5` README and `src/cache-restore.ts`.
- The tracked workflow and dependency manifests in this repository.
