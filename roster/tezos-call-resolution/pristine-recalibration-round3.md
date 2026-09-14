# Pristine CI recalibration diagnostic

Executed by root after commit8bc4fb054cbf9997ed10cbf3519ce18194252093.
`git fetch origin` succeeded; origin/main remained
0ca025bf520132b287aade93aa35e1177e7d99aa, also the computed merge-base.
Outer clean detached checkout: /tmp/arch-index-ci-check.iQVJeG/checkout.
The unchanged script created its own two pristine committed worktrees, built
both and measured all four cells for each metric. No tracked files were changed.

Exact command (cwd = outer checkout):

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- env TMPDIR=/tmp/arch-index-ci-check.iQVJeG DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy bash scripts/recalibrate.sh --check --base 0ca025bf520132b287aade93aa35e1177e7d99aa
```

Actual process session10433: exit0. Output:

```text
recalibrate: baseline 0ca025bf520132b287aade93aa35e1177e7d99aa = 0ca025bf5201
recalibrate: head              = 8bc4fb054cbf
recalibrate: building baseline…
recalibrate: building head…

── golden (descriptive, measured over _build/default/lib/arch_index)
   pinned in tree               modules: 25 functions: 980 calls: 6245
   A base bin/base src          modules: 25 functions: 956 calls: 6145
   B  NEW bin/base src          modules: 25 functions: 956 calls: 6145
   C base bin/ NEW src          modules: 25 functions: 980 calls: 6245
   D  NEW bin/ NEW src          modules: 25 functions: 980 calls: 6245
   → attributable to source change only (B = A).
   ✓ pinned value is current.

── ceiling (ratchet, measured over _build/default)
   pinned in tree               524
   A base bin/base src          534
   B  NEW bin/base src          534
   C base bin/ NEW src          537
   D  NEW bin/ NEW src          537
   → attributable to source change only (B = A).
   • within headroom: measures 537 against pinned 524 (+/-25) — advisory, not stale
   ✓ pinned value is current.
```

Trailing display spaces omitted in this transcription; counts and messages are
unchanged. The script itself checked the golden artifact byte-for-byte.
Both binary/corpus marginals agree: the self-index golden change is source-only
on this self corpus, not evidence that the new resolver changes no Tezos rows.
The ceiling remains within its existing bound; no ceiling constant was edited.
This is local CI-readiness evidence, not hosted-CI/QA/review approval.

Postrun inspection found both internal worktrees removed, outer checkout clean,
and no internal stale registrations. Outer checkout cleanup is recorded below
after successful non-force removal.

Cleanup completed: outer `git worktree remove` exit0 (without force), outer
`rmdir` exit0, registration absence check exit0. All three newly owned worktrees
and their build/DB artifacts are gone; no existing worktree was pruned.
