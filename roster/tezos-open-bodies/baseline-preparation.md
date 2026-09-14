# PR106 retained-state baseline preparation

No product edits. New distinct frozen directory:
`improvement/2026-09-14-tezos-resolution/attempt3-baseline`.

Actual --create performed fresh copied-producer production then another replay,
both45052rows/00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b,
Irmin4781/protocol11730. --check repeated neutral replay, exit0. Bounded independent
Sol review found cwd-relative phase paths and incomplete stored-state validation.
Both fixed: ROOT-anchored paths and exact state shape/phase/hash validation.
Actual positive record,12 malformed-state refusals and root-versus-/tmp equality
pass; real --check invoked from /tmp passes on the existing frozen record.
Sol read-only re-review confirms both fixes; not a full roster review/QA GO.

All410 input hashes, producer/schema and DB hash plus canonical snapshot checked;
live source/phase state unchanged across production. Historical attempts untouched.
Owned selection/replay staging directories cleaned by runner, no new worktree.
Frozen producer/schema/DB/provenance retained because later comparison needs them.
Candidate admission and native implementation RED/GREEN are still pending.

Persisted preparation check `node roster/tezos-open-bodies/check-baseline.js`
passes positive frozen artifact hashes,17 malformed-record/state refusals and
root-independent phase hashing. These are preparation checks, not product gains.

Integrated `check-baseline.js --replay` now actually passes the above controls,
an attempted --create refusal against the existing baseline, another neutral
replay and explicit unchanged frozen-record/artifact bytes. Invalid flag returns
setup exit2. The retained baseline occupies56MiB; disposable staging/build artifacts
were cleaned, while the four replay-essential frozen files remain.
