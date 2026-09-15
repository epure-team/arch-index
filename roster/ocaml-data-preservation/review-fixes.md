# Same-round review fix: nullable source candidates

At126a008, root reproduced the alternative schema containing
`functions(id,name,file_path)` rows `(1,'f',NULL),(2,'f','a.ml')`.
The native loader given effect `f/a.ml` exited1, empty stdout, stderr
`arch-effects-load: non-text function path`. An initial diagnostic used invalid
SQLite double-quoted strings and was a setup error; the corrected fixture
reproduced the loader failure independently. Both reviewers confirmed the defect.

Added CHECK1 assertions for main and alternative schemas:
1. Nullable homonym plus exact source -> ID2, successful persistence.
2. Delete exact candidate and reload -> unmatched diagnostic, NULL association,
   same one retained payload, no name-only fallback.

Genuine RED: `node roster/ocaml-data-preservation/check-effects.js` exit1,
`NULL-path homonym must not hide exact match: ... non-text function path`.
Fix: filter NULL candidate paths in the two supplied-path SQL queries. Missing
effect paths retain their existing unique-name behavior. No spec relaxation.

After fix: build0, CHECK1/2/3=0, hygiene0. Architect personally ran full forced
suite344/344 exit0 plus all gates and pinned corrected file hashes:
- effects_db.ml: `1ed1e65d291920ec2f7c3f14da30e9f2893e7582a6c65ca138493183f6b671a7`
- CHECK1: `e70131ae7b12acd1d638300d77b3a8a707a59b18f71fc597cd29fd37b6489071`

This issue was found and fixed within the first review round, not carried across
a NO-GO loop. The manual RED is genuine; no convergence-tool `red_verified`
claim is made. Globally clean pre-fix SHA is unavailable because the seven
foreign untracked files were preserved;126a008 identifies tracked product code.

Cross-runtime OpenCode probe timed out after120s: degraded/timeout, never a
passed independent review. Its journal is retained. Three native specialist
roles execute their own gates. Original pre-fix reports remain historical;
addenda must state which corrected-source validations they actually performed.
