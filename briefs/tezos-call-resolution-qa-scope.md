# QA Scope — tezos-call-resolution

**Status: VALIDATED**

Run every command in briefs/tezos-call-resolution-plan.md Quality gates against the reviewed checkout, including full forced dune tests, bundle and whitespace checks, native fixture, comparator mutations, self comparison and current fixed410 run. No TUI/web scenarios apply. Standard roster-qa deterministic and evidence gates also apply.

Validate all fifteen FR and eleven AC in specs/tezos-call-resolution.md against implementation evidence. Exact internal target identities/kinds/refusals are essential; aggregate-only success is insufficient. Treat missing baseline/corpus/hash/DB/caller/target and incomplete reports as setup failure, forbidden transitions as assertion failure, zero-gain replay as neutral not keep. Confirm both slices independently, duplicate-row preservation, source/target witnesses, existing target retention and no unjustified MUST/TOP changes.

Positive permitted relation gain plus native/full/review/QA/exact-head hosted CI is required to retain and ship. The comparator alone cannot certify semantic correctness. Do not modify Tezos or widen corpus. Keep owned baseline evidence for remaining attempts; cleanup only owned transient runner outputs after durable reports. No worktree creation is needed.
