# PCC v1 Contract

`pcc-index`, `pcc-dossier`, and `pcc-preflight` emit one JSON object using
`arch-index.pcc.<kind>.v1`. Shared fields are `schema`, `status`, `ok`,
`baseline_oid`, `head_oid`, `head_unchanged`, `target_digest`,
`policy_digest`, `tool_bundle_digest`, and `expected_inputs_digest`. Status is
`pass`, `fail`, `refused`, or `error`; exits are respectively 0, 1, 3, and 2.
After capture, `pcc-index` always takes a final target snapshot before returning
a build or analyzer failure. A changed target takes precedence over the
underlying failure as `refused`/3; an unchanged target emits `error`/2 with its
typed `failure_stage`. Inability before capture may report only on stderr.

`pcc-evidence` is the single request and evidence implementation. It parses the
canonical CWR stdin aliases, computes a canonical protected-tool manifest and
policy digest, and compares operator expectations without rebasing them.
An identity request supplies either all five shared identity fields or none;
partial and unknown requests are infrastructure errors. The policy digest binds
both the selected architecture rules and `.pcc/task.md` when present. Changing
either intentionally requires an operator recapture.
Detailed target/input manifests are mode-0600 temporary artifacts so stdout
stays below CWR's 64 KiB cap.

The target SHA-256 domain is `arch-index.pcc.target.v1\0`. Its deterministic
JSON manifest covers object-format-prefixed HEAD, index entries, tracked
overlays/deletions, non-ignored untracked files, Git modes, symlink bytes,
recursive submodule state, and protected HEAD/index/task metadata. Ignored
`_build` and derived `.pcc` outputs are excluded, except protected
`.pcc/task.md`. Sparse/assume-unchanged, unmerged, unreadable, special-file, and
observed per-file or whole-pass race states are refused. Two identical complete
passes reduce accidental hybrid snapshots, but are not an adversarial snapshot
guarantee; certification requires CWR to materialize or lock an immutable tree.
Untracked FIFOs, sockets, and devices are found by an ignore-aware workspace
walk and represented from `lstat` metadata only; they are never opened. This
makes their creation target-visible while `pcc-evidence` refuses a pre-existing
special-file target.

`files_unmatched` contains lowercase raw-path hex strings, not decoded path
text, so arbitrary Git filename bytes remain canonical JSON and portable
across locale/Unicode implementations.

These scripts execute repository-authored build/test/analyzer code and detect
candidate-tree mutation without cleanup. They do not provide OS isolation.
Despite its compatibility name, `tool_bundle_digest` authenticates only the
protected arch/PCC files listed by `pcc-evidence`, not the Bash, Python, Git,
Dune, SQLite, OCaml, or other runtime closure selected through `PATH`.
CWR alone owns read-only source materialization, writable build/temp space,
environment/secret filtering, and network isolation; its engine receipt is the
security attestation. Candidate-side isolation booleans therefore remain false
until CWR binds a canonical sandbox policy/image digest and isolated runtime to
the receipt.
