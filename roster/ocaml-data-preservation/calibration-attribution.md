# Stage1 source-growth recalibration

User explicitly approved the manifest extension and reference524 ->554 on
2026-09-15. Headroom25, SQL queries and minimum floors are unchanged.

Fresh pristine 2x2 run: `node roster/ocaml-data-preservation/calibrate.js`.
Base: `c10d1a4f2bee4f72907fe6ce88cdc0338153398d`.
Candidate snapshot SHA256:
`fcd229ef7cbeb165e9178c204c19eb76155c692109eb0e540c7e1b6739c69ec6`.
Full generated local evidence: `improvement/2026-09-15-ocaml-cfa/calibration/evidence.json`.
Verdict: SOURCE_ONLY. A/B use base CMTs; C/D use candidate CMTs;
A/C use the base engine, B/D the candidate engine.

| Corpus | Cells | Modules | Functions | Calls | Origins | MUST-null |
|---|---|---:|---:|---:|---:|---:|
| Whole build, base | A=B | 127 | 4014 | 23109 | 1230 | 545 |
| Whole build, candidate | C=D | 128 | 4060 | 23329 | 1251 | 554 |
| Producer, base | A=B | 25 | 1004 | 6389 | 580 | 169 |
| Producer, candidate | C=D | 25 | 1013 | 6425 | 583 | 171 |

Equality is checked on complete grouped call-row digests, module and origin
coverage and external groups, not just counts. Source growth adds nine measured
rows; another21 were already present at base versus the old524 reference.
This is not a resolution gain. No attribution of the pre-existing21 to individual
merges is claimed. At the initial implementation handoff, subsequent changes were
limited to approved references/comments and documentation/checkers. The later
review correction to product logic is qualified separately below.

Review subsequently added only two SQL NULL-candidate filters in effects_db and
their CHECK1 cases. After that fix, fresh same-current-corpus old/new-engine
comparison passes:23329 canonical call rows, SHA256
`afb93ae5fe948981382b42b9ba5776487324a31cbae4a4fc64a69ebfce3d591a`,
MUST-null554. This is a fresh single-corpus equality check, not a new pristine
2x2 run. The architect's full forced suite also passes344/344 on the fixed source.

The full integrated suite subsequently exposed the two pre-existing self-index
references still pinned to1004 functions/6389 calls/580 origins. Their updates are
already within the implementation manifest's measured-source-growth permission:
1013 functions/6425 calls/583 origins, with only option/raise/escapes=1 growing
328 ->331 in origin groups. Both engines independently agree on these values in
the pristine producer corpus above. No policy allowlist change is required.

Whole-build external-group attribution (union diff, not merely total subtraction):
`effects_db.ml`: Sqlite3.bind -2, reset -1, step +5, Rc.to_string +1,
db_close +2, errmsg +1, finalize +1; `arch_index_cmt.ml`:
Digestif.SHA256.digest_string +1 and to_hex +1. Sum: +9.

Both owned temporary worktrees and their builds were removed after the run
(`/tmp/arch-data-calibration-sW59B8`). No foreign worktree was removed.
