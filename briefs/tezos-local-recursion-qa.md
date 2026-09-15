# QA Brief — tezos-local-recursion

**Date:** 2026-09-15T01:30:05Z
**Status:** GO ✅
**Round:** 2 (qualifying 0/5)

## Quality gates

Main personally executed every gate serially on reviewed implementation76fe1b7
plus report-only QA/investigation changes. Source state remained unchanged for
each command. Raw logs/results:
`improvement/2026-09-14-tezos-resolution/attempt4-main-qa2-y16BGq/`.

| Gate / exact command | Exit | Duration |
|---|---:|---:|
| `opam exec -- dune build` | 0 | 352ms |
| `opam exec -- dune exec tezt/tests/main.exe -- --no-color` | 0,340/340 | 269748ms |
| `node scripts/review-bundle-verify.js` | 0 | 29ms |
| `git diff --check origin/main` | 0 | 7ms |
| `node roster/tezos-local-recursion/check-native.js` | 0 | 28451ms |
| `node roster/tezos-local-recursion/check-witness-inputs.js` | 0 | 3900ms |
| `node roster/tezos-local-recursion/check-baseline.js` | 0 | 4008ms |
| `node roster/tezos-local-recursion/check-comparison.js` | 0 | 52652ms |
| `node roster/tezos-local-recursion/check-compatibility.js` | 0 | 28806ms |
| `node roster/tezos-local-recursion/check-residual-capacity.js` | 0 | 3882ms |

Four new native Tezt cases and336 prior cases pass. No gate/filter/assertion or
timeout was relaxed. Formatter/coverage are not configured, not PASS.
CHECK1–6 cover AC1–19 plus the local comparison/preservation part of AC20;
full code-to-contract matrix is in the spec-compliance report. AC20 delivery
still requires exact-head CI and guarded merge before retention.

Fixed410:45052rows both sides,181 independently witnessed head replacements,
179 new relations (+68Irmin/+111protocol),zero lost relations/unexplained
changes/new MUST/removed legacy TOP residual. Fresh native evidence replay
and single-use head/residual capacities pass. Public API/schema/flat unchanged;
four exact source-only references remain bound to immutable attribution.

## First QA round retained

Round1 was NO-GO, qualifying1/5: build0 then full suite stopped at test5 after
the existing TypeScript polyglot path hung with `No Project.` and a zombie child.
Main terminated only the identified owned CLI after >200seconds, inducing143;
Tezt returned1. Later QA gates did not run. Raw error log is preserved verbatim:
`improvement/2026-09-14-tezos-resolution/attempt4-main-qa-2FxqyG/full340.log`.
The unchanged focused reproduction passed10105ms before this single full retry.
See tezos-local-recursion-investigation.md: exact race cause is unresolved;
no LSP fix or repaired root cause is claimed. This is a residual intermittent
LSP risk, not evidence of a recursive-resolution regression. Both round events
remain in qa-state.json; GO does not erase the first failure.

## Code-intel and unavailable tooling

Actual `node /home/mathias/dev/agent-roster/scripts/code-intel-resolve.js gate --timeout 120`:
`SKIP: no code-intel block`, `RESULT: skip`, exit0.
TUI: N/A, no interface scope. Hooks/managed context/KB absent.
Actual global claims check again exits2 on pre-existing
specs/functor-binding-resolution.md:375 (unmatched-record). No managed projection
is used, no global freshness PASS claimed; isolated new-spec validation is
separate evidence.

## Cross-runtime QA

Actual shared availability check with --phase qa --check-availability --write
returned skipped-degraded: unchanged runtime version, source review-go,
digest opencode:76f897c73342fdbf. No second runtime was launched and no external
QA PASS claimed. Review's non-conforming response remains discarded.

## Verdict

GO for roster-ship. QA convergence passed with no warning, round2/cycle1.
Standing user autonomy covers routine continuation; no quiz answers fabricated.
PR/CI/merge/KEEP remain pending. Preserve seven unrelated user files.
