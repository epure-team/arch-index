# Spec-compliance execution record

Executed in `/home/mathias/dev/arch-index-worktrees/functor-instance-resolution`
after the explicit Dune baton was granted. OCaml commands used the existing
`/home/mathias/dev/arch-index` switch. The review target was
`main...HEAD`; the current HEAD during execution was
`3d92e73` (brief-only EOF hygiene commit; no product change).

| Command | Exit | Compact observed result |
|---|---:|---|
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Build completed. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` | 0 | Full forced suite completed successfully; normal `arch-errors` fixture diagnostics were printed. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js inventory` | 0 | `18 apply + 1 apply_unit`; 5 contexts; external/shadowed=3. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js lifecycle` | 0 | Exact selection=3; rollback=true; all five outcomes checked. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js query` | 0 | Valid=3; six formats; 19 core corruption cases; extension successes=31/mutations=22. |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-functor-catalogue.js compatibility` | 0 | Versioned rich oracle; 16 semantic tables/contracts; three legacy queries; two indexing passes. |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | Bundle 1.6.0; 22 files present and SHA-matched. |
| `rtk proxy git diff --check` | 0 | No whitespace errors. |

No gate was skipped or remapped. `git diff --check` was deliberately run in the
brief's prescribed form; scope gate 0 had already been run by root and is not
re-reported as a scope finding.
