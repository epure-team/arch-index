# Roster doctor preflight — ocaml-cfa-foundation

2026-09-15, source HEAD 5120e8a (only Roster documentation changes uncommitted).
Verdict: **READY**.

- `rtk proxy opam exec -- ocamlc -version`: 5.3.0, exit0.
- `rtk proxy opam exec -- dune --version`: 3.24.2, exit0.
- `rtk proxy opam exec -- dune build`: exit0 (265ms).
- `rtk proxy _build/default/tezt/tests/main.exe --list`: exit0, registered
  tests listed; collection only, not a full test-suite execution claim.
- `rtk proxy node scripts/review-bundle-verify.js`: exit0, 22 hashes match,
  bundle1.6.0; manifest tracked as verified by git ls-files.
- No configured independent formatter/linter; no missing configured gate.
- No project harness/code-intel resolver installed; manual pipeline retained.

Test collection warned about ten old /tmp/tezt-* directories. They were not
created by this preflight and ownership is not established; none removed.
No source edits, new worktree, installs or environment changes.
