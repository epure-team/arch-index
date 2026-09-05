# QA scope — mutation-campaign-313

**Date:** 2026-09-05T14:45:00+02:00

Worktree `/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`.

## Environment

```
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
```

The default switch produces spurious eio/cohttp/mirage-crypto failures. `dune` caches aggressively,
so `--force` is required for the suite to actually run.

## Gates

```bash
# Build
dune build

# Tests — --force is mandatory
dune test --force

# Lint / format
# NOT DOCUMENTED for this project: no .ocamlformat file and no ocamlformat in the switch.
# There is no format gate to satisfy and none to break. Do not invent one.
```

Baseline measured on `879fedb` in this worktree with a full build: **188 tezt cases, 0 failures.**
Re-measure; do not carry that number forward. A regression is any case that stops passing or any
new failure.

## Standing gates, independent of any slice

```bash
scripts/check-quint-red.sh            # 6 injected defects, each must turn a NAMED invariant red
scripts/check-binary-provenance.sh    # every resolved binary must be inside this tree
quint typecheck specs/mutation-campaign-313.qnt
quint run specs/mutation-campaign-313.qnt --invariant=allInvariants --max-samples=20000 --max-steps=12
```

`check-quint-red.sh` reports a `sed` that matches nothing as a **failure**, so a stale mutation
cannot pass for a green check. If a new Quint invariant was added without its mutation, that is a
defect: an invariant with no mutation has not been shown capable of failing.

## Behaviours to validate

- A campaign with **no kills at all** is reported self-uncertified, and says why. A campaign that is
  entirely `ERROR` says something different from one that is entirely survivors.
- An **interrupted** campaign reports its unattempted mutants as pending, never as survivors.
- The same engine report over three indexes — closed cone, ⊤ inside the test cone, no soundness
  contract — publishes three different verdicts while the stored status stays the same in all three.
- A `KILLED` under a bounded selection still publishes as killed.
- A missing engine exits 2 and writes no campaign row.
- A profile without `granularity` aborts with exit 2 naming the file and the key.
- A language with no profile reports `not_analysed` rather than an empty result.
- A subprocess exiting **3** is reported as refused, distinctly from a failure.

## Verdicts QA must refuse to give

- **Do not pass a green run that contains no red anywhere.** A campaign with at least one kill
  self-certifies, because a stale binary is unmutated and cannot produce a kill. An entirely green
  campaign cannot distinguish a weak suite from the wrong binary having run.
- **Do not accept a measurement without its corpus, its commit and its build state.**
- **Do not accept a bare zero.** The report must say what would have made it non-zero.
- **Do not accept a mutation score, ratio or threshold** in any output or any prose.

## Out of scope for QA

Pushing, opening a pull request, or any remote operation. This repository is public and only
Mathias authorises that.
