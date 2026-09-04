# checks/ — runnable regression checks

Standalone, directly-runnable checks for defects that the tezt suite and the
self-index golden **provably cannot see**.

They exist because `rebase/sound-qual` shipped green-and-wrong twice: its tezt
suite passed, its mutation check was KILLED, and the self-index golden was
byte-identical — while 582 previously-resolved call edges had been silently
dropped into `MUST`-with-NULL-callee. A gate that cannot see a defect class is
not a gate for it.

## Convention

Each check is a single self-contained file, runnable directly:

```
node checks/<name>.js
```

Exit codes (roster ratchet convention A-6):

| code | meaning |
|---|---|
| `0` | the property holds — pass |
| `1` | the assertion fired — the defect is present |
| `>= 2` | setup failure (toolchain missing, fixture build broke) — **not** a verdict on the code |

The `>= 2` band matters: a check that cannot distinguish "the bug is present"
from "I could not run" is one that goes green when the toolchain breaks. Never
collapse them.

Fixtures are assembled at **runtime**, never committed, so a check cannot drift
from the project it claims to build.

## Non-negotiable: `dune --root .`

Every dune invocation passes `--root .`. Dune searches *upward* for its project
root; these checks build under a temp dir, and a stray `dune-project` anywhere
above it makes a bare `dune build` silently root itself elsewhere and behave
nonsensically. This was misdiagnosed as flaky CI for an entire task before it was
understood. See `briefs/qualified-unit-resolution-research.md` Finding 6.

## Current checks

| check | spec | state on `main@cde3aad` |
|---|---|---|
| `qualified-homonym-resolution.js` | FR-001 | **RED** — `Liba.Api.run` resolves into `libb/api.ml`, stamped `MUST` |
| `alias-resolution-guard.js` | FR-002 | **GREEN** — regression guard; the abandoned branch broke this while fixing FR-001 |

### Pending

- **CHECK-3** (FR-006, MUST-with-NULL ratchet) and **CHECK-4** (the peer-coupling
  identity diff) are specified but **not yet implemented**, deliberately. Both
  need a metric decision that is only sound to make with the resolver in hand:
  CHECK-3's "root resolves to an *indexed* unit" predicate needs the real unit-name
  table, which does not exist until the fix builds it. Implementing it now would
  mean approximating that predicate by basename — reintroducing, inside the gate,
  the very guessing the fix removes.

  The abandoned branch's `no-must-null-regression.js` is **not** ported: its
  `BASELINE = 1975` was measured on another machine and another tree, and the
  check never rebuilt before measuring. A ratchet whose baseline cannot be
  reproduced is a ratchet that fires on the weather.

## Wiring

Checks must run in CI. The abandoned branch's two checks were wired **nowhere**
(`grep -rn 'checks/' .github/` returned nothing), which is why they could not
prevent the second gate-invisible regression. An unwired ratchet is not a ratchet.
