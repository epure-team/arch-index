# Preflight — tezos-recursive-typed-bodies

READY. Actual checks on 2026-09-15, before any fifth-attempt product edit:

- `opam exec -- dune build`: exit 0 (0.23 s).
- `opam exec -- dune exec tezt/tests/main.exe -- --list --no-color`: exit 0; collection only, not a test pass.
- `node scripts/review-bundle-verify.js`: exit 0, 22 SHA-matched files, bundle 1.6.0.
- opam, node, git, gh and sqlite3 resolve. Local compiler reports 5.3.0.
- `.ocamlformat` and project harness manifest absent; formatter and coverage are not configured, not represented as passing checks.
- `code-intel-resolve.js orient fan-in --root .`: `DEGRADED: no installed research-orientation packs`; advisory fallback to live source research.

Collection warned about ten pre-existing `/tmp/tezt-*` directories. They are not established as owned by this task and were not removed. No installs, environment changes or new worktrees. Full pre-product guard and distinct frozen PR108 baseline still required before implementation.

Subsequently completed before product edits: full guard340/340 exit0 in297880ms,
source hash unchanged. Distinct attempt5 baseline create and check/replay exit0,
45052rows and4849/12157 relations, exact PR108 digest. Evidence is under the
existing ignored loop directory; no replay build/selection worktree retained.

The first unsealed baseline was subsequently invalidated by a main-file hash
change after a WAL checkpoint. Sealed attempt5-baseline-v2 now supersedes it:
create/check/replay, complete SQL sealing equality and disposable-copy writable
SELECT stability all pass. The original remains audit evidence, not a valid pin.
