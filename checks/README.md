# checks/

Standalone, node-runnable invariant checks. Each file is run as `node checks/<name>.js`
and honours a three-way exit code:

| exit | meaning |
|---|---|
| `0` | pass — the invariant holds |
| `1` | the assertion fired — the bug this check guards is present |
| `>= 2` | error / setup failure (missing binary, build failure, no `_build/default`) — the check could not decide |

They shell out to `dune`, the OCaml indexer binary and `sqlite3`, so they must be run
from a shell where the project's opam switch is active:

```bash
eval "$(opam env --switch=/path/to/arch-index --set-switch)"
dune build
node checks/nested-module-resolution.js
node checks/no-must-null-regression.js
node checks/baseline-has-headroom.js
```

`baseline-has-headroom.js` is the exception — it reads `no-must-null-regression.js` as text
and needs neither `dune build` nor `sqlite3`, only Node.

All three run in CI as the `Soundness ratchets (checks/)` step in `.github/workflows/ci.yml`,
right after `Build` and before `Unit and integration tests`. A `node checks/<name>.js` step
fails on any non-zero exit, so exit `1` (bug present) and exit `>=2` (setup failure) both fail
the build — a missing binary never reads as green.

These are ratchets, not a test suite: each one is linked to a specific review finding — either
raised during the sound-qualified-name-resolution task (see
`briefs/sound-qualified-name-resolution-{intake,plan}.md` for the surviving trail; the finding
text itself is preserved in each check's own header comment) or during review of the
wire-checks-into-ci task that wired these into CI (`briefs/wire-checks-into-ci-review.json`) —
and was proven RED before the fix that made it green.

**When you recalibrate `no-must-null-regression.js`'s baseline:** always measure from a clean
checkout (`git worktree add --detach <tmp> <sha>`), never from the ambient working tree — round
1 of wire-checks-into-ci got this wrong once, inflating the baseline by 9 because pre-existing
unrelated uncommitted files were present in `_build/default` at measurement time.
