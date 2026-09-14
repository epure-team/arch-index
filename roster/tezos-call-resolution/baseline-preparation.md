# Fixed410 call-target baseline preparation

Historical baseline record. Current status is in briefs/tezos-call-resolution-impl.md and the append-only task ledger; no baseline measurement alone authorizes retention.

## Provenance and ownership

- Arch-index checkout: ea8e5b4269985e779020a92a5054bc0678f5edb6.
- Producer SHA-256: 2a630da61bbad791a6475b6f5d099e41f55054fd7a090115aba394401d527f99.
- Tezos checkout: 1727d7e192f2374edda7ad7adceef6f4ec51f71a, 47 dirty entries unchanged.
- Original manifest: roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv.
- Manifest SHA-256: 9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1.
- All 410 original CMT hashes checked before/after; all 410 inputs collected.
- Owned retained diagnostic directory: /tmp/arch-index-resolution-baseline-OmhcEs (23 MiB at initial measurement). baseline.db, producer.log, provenance.json and guard.log are retained for the upcoming comparison. It is not a worktree. Remove this exact directory only after durable comparison evidence is exported or the loop stops.
- Temporary selection symlinks were created inside that owned directory, not in Tezos. Running with Tezos as cwd and a selection path without an _build component preserved source mapping and reproduced prior aggregate counts.
- User untracked files, existing unrelated worktrees and PR93 preserved.

Producer invocation actually used (absolute executable/schema paths, cwd Tezos):

```sh
/home/mathias/dev/arch-index/_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe --build-dir /tmp/arch-index-resolution-baseline-OmhcEs/selection --db-path /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --schema-path /home/mathias/dev/arch-index/architecture-schema.sql
```

## Measured baseline

12,373 functions; 45,018 call-table rows: MUST 13,601, MAY_ENUMERATED 23,209, MAY_TOP 8,208. This exactly matches the prior aggregate report, but the fresh DB now preserves detailed rows.

Excluding value_alias rows only (module_alias retained):

| Slice | Rows with internal callee_id | Distinct caller/file:line/target relationships |
|---|---:|---:|
| Irmin | 4,408 | 4,372 |
| Protocol | 11,878 | 11,220 |

The right column deduplicates `(caller source path, caller name, call_site, target source path, target name)`. It is NOT a count of unique syntactic call expressions: the schema has no call-site column/ordinal. 1,122 groups share `(caller_id,call_site,callee_name)` with multiplicity >1. A future comparator must preserve multisets as well as target sets and must not use an unrestricted pairwise kind join.

SQL actually run for the right column:

```sql
WITH edges AS (
 SELECT CASE WHEN m.path LIKE 'irmin/%' THEN 'irmin'
             WHEN m.path LIKE 'src/proto_alpha/%' THEN 'protocol'
             ELSE 'other' END slice,
        m.path caller_path, f.name caller, c.call_site,
        tm.path target_path, tf.name target
 FROM calls c
 JOIN functions f ON f.id=c.caller_id
 JOIN modules m ON m.id=f.module_id
 JOIN functions tf ON tf.id=c.callee_id
 JOIN modules tm ON tm.id=tf.module_id
 WHERE COALESCE(c.edge_form,'') <> 'value_alias'
)
SELECT slice,count(*) distinct_line_target_relations
FROM (SELECT DISTINCT * FROM edges) GROUP BY slice;
```

These are resolution-to-index measurements, not an oracle proving every existing target is semantically correct. Keep decisions additionally require native identity/refusal fixtures, per-target witnesses, no existing-target loss, no unexplained site/multiplicity loss and no unjustified TOP removal/MUST promotion. Name equality alone is never sufficient.

## Guards actually run

- Repeated before implementation on feat/tezos-local-module-targets, 2026-09-14: full `dune runtest --root . --force` exited 0 (session44545); Tezt reported 320/320 SUCCESS, alongside the other dune suites. Product source was unchanged. Expected injected assertion/setup/SQL rejection diagnostics remained negative-test output, not a failing aggregate exit.

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`: exit 0.
- `rtk proxy node scripts/review-bundle-verify.js`: exit 0, 22/22.
- Test collection: exit 0; not counted as execution.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force`: exit 0; full raw output retained in guard.log. Expected negative-test diagnostics appear in this log and do not replace the exit-status verdict.
- Post-merge PR104 main CI 34780807363: SUCCESS, checked separately from the earlier exact-PR-head CI.

## First scoped candidate, not a measured gain

Some module_param TOP rows have same-file stored definition names. Source checks confirm structured module declarations for `Helpers` (script_native_types.ml:13), `Inode` (irmin/lib_irmin_pack/stats.ml:19), and `Infix` (irmin/lib_irmin/merge.ml:69). Examples: Helpers.add_name 28 rows, Inode.update 9, Infix operators 15. These SQL name matches are prioritization hints only, not target evidence. The proposed slice must use Typedtree binder identity, preserve shadowing/refusal behavior and stay independent of name guessing.

## Loop setup prerequisite (subsequently completed)

Update 2026-09-14: executable comparison setup is now present. Root independently ran check-comparison.js (21 assertions, exit0) and the final verify.js fixed410 runner (session49844, exit0), report improvement/2026-09-14-tezos-resolution/2026-09-13T22-35-42-552Z-candidate-948091/report.json. Exactly45,018 canonical rows and the pinned digest, zero row/relation changes; complete selected artifact joins and input/producer/schema stability passed. `.gitignore` was updated before logs. Baseline iteration0 is now recorded in ignored results.tsv. This discharges the measurement prerequisite for starting native TDD/product attempt1, not a retention/ship gate. Current comparator conservatively refuses ordinal/name and computed-return residual changes until separately reviewed transition policies exist.

Replay confirmation (2026-09-14): read-only canonical export of baseline.db and replay.db yielded 45,018 rows each and identical SHA256 `4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd`; both SQLite quick_check results were `ok`. The original replay process handle expired before its terminal output could be recovered, so this is independently checked DB equality, not a recovered process exit-status claim. baseline-call-multiset.json is retained beside the DBs. Owned temporary directory now occupies approximately 59 MiB, still needed for comparison.

User approved five bounded iterations and autonomous roster/PR/merge handling. These baseline-before-product requirements were discharged before native TDD: narrowed scope, executable replay/comparison and improvement/ ignore before results.tsv. Baseline setup is not a retained product iteration. Subsequent candidate results and separately reviewed transition policies are recorded in setup-checks.md and uid-witness-report.md.
