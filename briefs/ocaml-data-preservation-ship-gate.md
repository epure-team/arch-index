# Ship gate — ocaml-data-preservation

Stage1 of the approved five-stage sequence. Branch `fix/ocaml-data-preservation`,
target `main`; origin/main a8114dc after fresh fetch. Rebase reports up to date.

Roster review GO (three independent gate-running roles), QA GO (full344/344,
CHECK1–3, exact pre/post source/binary identity), convergence gates exit0.
Three MEDIUM coverage debts and one INFO wording advisory remain documented;
OpenCode timed out and QA respected its shared breaker. No full formal proof,
OCaml completeness or Tezos resolution gain claimed.

Changes: source-aware effects identity/path persistence and reload repair;
safe run-local reuse for byte-identical CMT copies with independent artifact
inventories. Independently compiled variants remain stage4; #68 remains partial.
The implementation addresses both root causes of #26.

Commits before this ship record: c10d1a4 (prior-loop delivery documentation),
126a008 (implementation),10d75e2 (NULL candidate fix),298196e/7febb24 (review),
e377efd (QA). No unrelated product work or PR93 changes are included.
Seven preexisting untracked files remain outside staging; user-authorized
dirty-tree exception, not a global clean-tree claim. No new worktree.

Human push/merge/quiz gates: covered by explicit user authorization for autonomous
Roster per stage, PR creation, required-green CI and merge. No fabricated answers.
Only a guarded rebase merge matching the exact verified PR head is authorized.

PR not yet created at this record. Required remote check: `build`; strict branch
protection enabled. Local QA does not substitute for this remote result.

## Summary

- Preserve complete effect payloads, bind only exact source/name matches, and repair stale associations atomically.
- Reuse exact-copy CMT graph extraction while retaining each artifact's catalogue/binding collection; keep nonidentical variants out of this stage.
- Add native regressions and measured source-growth references with unchanged headroom and policy allowlist.

## Test plan

- [x] Three independent reviewer build/full344/CHECK1–3 passes on corrected source.
- [x] Final QA full344/344 and CHECK1–3, source/binary identity stable.
- [x] Fixed410 Tezos replay:45052 canonical rows; Irmin4849/protocol12171 unchanged.
- [x] Scope, bundle, review/QA convergence and diff hygiene.
- [ ] Required GitHub CI `build` on exact final PR head, before guarded merge.

Closes #26

Related #68 (partial only; independent compilations deferred to stage4).
