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
```

Both run in CI as the `Soundness ratchets (checks/)` step in `.github/workflows/ci.yml`,
after `Build` and before `Self-index smoke test`. A `node checks/<name>.js` step fails on
any non-zero exit, so exit `1` (bug present) and exit `>=2` (setup failure) both fail the
build — a missing binary never reads as green.

These are ratchets, not a test suite: each one is linked to a specific review finding in
`briefs/sound-qualified-name-resolution-impl.md` (`## Ratchet`) and was proven RED before
the fix that made it green.
