# Implementer — tezos-residual-targets

**Status: VALIDATED**

Goal: attempt2 of five improves only qualified invocation/callback/letop through
one bare arrow-typed Pident value alias within an already-owned same-CMT structure
to a known existing body. Ordinary new heads MAY_ENUMERATED, null TOP/form;
body table stays body-only, actual syntactic arity/Some supplied count retained.
Every existing point-free output and immediate-predecessor edge remains unchanged.
No alias chains, module aliases, persistent/qualified RHS, applications/unpacks,
parameter, computation/closure/partial RHS, cross-CMT resolution or config/CFG
policy changes. Unsupported stays old refusal; rejected actual body is dropped_node.

Writable files: lib/arch_index/arch_index_cmt.ml and .mli;
lib/arch_index/call_graph_extractor.ml only if flat threading required;
tezt/tests/local_module_targets.ml exact value_alias_call reclassification;
new tezt/tests/local_value_targets.ml; tezt/tests/main.ml; tezt/tests/dune.
Supporting: roster/tezos-residual-targets/, briefs/tezos-residual-targets-*,
specs/tezos-residual-targets.md, docs/edge-kind-contract.md, ignored improvement/,
skills-meta/friction.jsonl, external named roadmap.
Conditional exact self-oracle collateral only:
test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
checks/origin-recurring-consumer.js assertion coordinates.
User approved on 2026-09-14 the additional exact coordinate-only refresh in
test/fixtures/origin-consumer/self.allow: line1509 to1557, then1559 after the bounded repair, and corresponding
enclosing lambda coordinates; preserve the sole assert/Assert_failure x1 entry.
No new allowance or rule relaxation is authorized.
No other files, no old task1 verifier/spec/witness edits; existing task1 scripts
may be imported read-only. Preserve user dirt, PR93, Tezos and foreign worktrees.

Predecessor: PR105 merged ace388f7a598dc762a6df6a3bac55de8d162361c;
docs-only handoff8f309bc. Current pre-product executable SHA
c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8;
schema1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0;
canonical45052 rows SHA90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b;
distinct relations Irmin4772/protocol11615. Fixed manifest
roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv SHA
9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1;
Tezos revision1727d7e192f2374edda7ad7adceef6f4ec51f71a, read-only
/home/mathias/dev/tezos/tezos. Keep original /tmp/arch-index-resolution-baseline-OmhcEs
untouched; it is not the new predecessor.
New record: improvement/2026-09-14-tezos-resolution/attempt2-baseline/provenance.json,
with distinct frozen producer/schema and DB. Refuse overwrite. --check uses that
frozen binary, never the current changed product. Freeze and neutral replay before
product edit. Candidate verify uses current binary against frozen DB.

Quality commands (every shell command starts rtk proxy):
opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force
node scripts/review-bundle-verify.js
git diff --check
CHECK1 node roster/tezos-residual-targets/check-native.js
CHECK2 node roster/tezos-residual-targets/check-comparison.js
CHECK3 node roster/tezos-residual-targets/prepare-baseline.js --check
CHECK4 node roster/tezos-residual-targets/verify.js --witness improvement/2026-09-14-tezos-resolution/attempt2-reviewed-witness.json
CHECK5 node roster/tezos-call-resolution/check-self-index-smoke.js
Preparation first uses --create; neutral self uses verify.js --self, no witness.
Assertion/valid forbidden movement1; malformed/setup/tool/native compile failure>=2.
No formatter/coverage configured; never label an absent tool PASS.
Full spec: specs/tezos-residual-targets.md plus spec-input/resolutions documents.


Sequence: (1) fail-closed predecessor/comparison setup and positive/negative
controls; (2) genuine native RED, then one tested OCaml provenance+consumer
change and exact old-case update; (3) independent one-hop native witnesses,
candidate comparison; (4) all checks/full guard, exact self collateral only if
required, scoped commit then independent review/QA/CI/merge.
New alias provenance must be distinguishable from direct body membership so the
point-free consumer uses old direct-only behavior. Do not add aliases to
local_fn_stamps. Mask before installing eligible exports. Reuse binding_name
and body arity from actual target. Test optional/required holes, callback/letop,
conditional/dead, same-file flat absent and storage rejection explicitly.
Independent corpus probe must trace occurrence->alias declaration->RHS body
without product table reuse. Multiset matching consumes every occurrence once,
including duplicates; only non-value_alias module_param heads and separately
witnessed overapplication residuals may move. No new MUST or relation loss.
Use apply_patch for edits/control files; active manifest means shared checkout,
not hidden worktree. Root serializes producer runs and source-state writes.
