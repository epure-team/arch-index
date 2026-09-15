# Architect report — ocaml-data-preservation

**Specialist:** architect  
**Reviewed head:** `126a0086d1a7016139ac26fa466d676ad889e292` plus the two authorized NULL-path corrections  
**Overall architecture risk:** LOW

## Findings

No CRITICAL, HIGH, MEDIUM, or LOW architecture finding remains.

One INFO contract-wording ambiguity is recorded in `architect-findings.json`: FR-012 says “successfully stored representative graph,” while the frozen C11 boundary defines eligibility at successful `process_cmt` extraction return without increased SQL failures. The implementation follows that explicit boundary. Deferred call/dependency/type-usage persistence is not what the independent functor catalogue or binding markers certify, so no borrowed-success defect is established.

The exact-copy path remains bounded to one run/root/source/compiler-unit key and full immutable artifact-byte equality. It rereads both representative and candidate bytes, preserves selected artifact spelling, independently invokes catalogue/binding collection for each path, and leaves nonidentical same-source artifacts on the existing rejection path. The effects change keeps raw payload spellings distinct while normalizing only association lookup. The authorized NULL filters prevent nullable homonym candidates from aborting exact supplied-path resolution without adding name fallback.

## Personal verification

All commands ran against the corrected working tree; no prior specialist pass was inherited.

| Gate | Actual result |
|---|---|
| `opam exec -- dune runtest --force` | exit 0; 344/344 Tezt successful; native effects 13/13 |
| `opam exec -- dune build` | exit 0 |
| `node roster/ocaml-data-preservation/check-effects.js` | exit 0 |
| `node roster/ocaml-data-preservation/check-cmt-copies.js` | exit 0 |
| `node roster/ocaml-data-preservation/check-tezos.js` | exit 0; 45,052 canonical rows; digest `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`; Irmin 4,849; protocol 12,171; 360 effects emitted, 139 distinct stored, 63 bound, 76 unbound |
| `node scripts/review-bundle-verify.js` | exit 0; 22 files SHA-matched; bundle 1.6.0 |
| `git diff --check` | exit 0 |

Logs are stored under `improvement/2026-09-15-ocaml-cfa/architect-*.log`.

Final inspected hashes:

- `lib/arch_effects/effects_db.ml`: `1ed1e65d291920ec2f7c3f14da30e9f2893e7582a6c65ca138493183f6b671a7`
- `roster/ocaml-data-preservation/check-effects.js`: `e70131ae7b12acd1d638300d77b3a8a707a59b18f71fc597cd29fd37b6489071`
- `lib/arch_index/arch_index_cmt.ml`: `3d633815cd728532535ed7151436b58c58307ca6026d1dd8ebacc85ade3085d3`

No product source, Tezos source, commit, or worktree was created or changed by this review. The unrelated untracked manifest was preserved; review-trace and other specialist report artifacts created by the root/review pipeline were also left untouched.
