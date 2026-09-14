# Round1 repair: authentic arity RED/GREEN

Before product correction, exact committed producer12ab1fc plus the new
self-contained check (fixture/probe created only in its owned temporary directory):

`rtk proxy node roster/tezos-call-resolution/check-labeled-arity.js`

Exit1, actual assertion, after every native slot/head premise was checked:

```text
PREMISES: four native callers, supplied slots and partial head metadata verified
ASSERTION: omitted label is not a supplied argument: partial/true

1 !== 0
```

Four callers cover a missing required label, a fully supplied labeled
overapplication, an omitted optional label and its fully supplied control, with
local-module context both disabled and enabled. Actual pending heads are checked
for partial metadata; exact returned-call counts are checked independently.

After the focused body_nargs correction and an exact checkout build
`rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`
(session85133 exit0), the unchanged assertion passed, exit0:

```text
PREMISES: four native callers, supplied slots and partial head metadata verified
PASS labeled arity: four native callers, both contexts, exact head/residual metadata
```

Setup history is not RED evidence: first Node syntax check found template
backtick escaping (exit1 parse), then compiler setup failed because the collector
is private and public-package linkage did not supply Digestif's implementation
(exit2). Corrected by linking the exact checkout's existing native libraries and
private interface with the same dependency packages as the independently executed
review reproducer. These setup errors preceded the genuine semantic RED above.
Each run cleaned its own temporary directory, including compilation artifacts.

This is manually observed exact-current-build RED/GREEN, not automated historical
worktree ratchet verification: pre_fix_sha remains null due preserved unrelated
dirt, and the review gate must report that limitation rather than inventing a SHA.
Full guard, new fixed410 measurement and downstream review/QA/CI remain separate.

Post-fix fixed410 verification subsequently passed with the identical canonical
candidate digest90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b:
+400 Irmin/+395 protocol relations, zero loss, all831 replacements/34 residuals
still covered by the exact existing witness. New producer SHA256
c953970a15b64d026f7b502ba5d61be537c3ab5b51e219435b4a3483d57764b8.
Report: improvement/2026-09-14-tezos-resolution/2026-09-14T06-26-30-653Z-candidate-2526704/report.json.
Baseline self comparison also passes with45,018 unchanged rows (06-27-04-107Z-self-2550553).

Self-analysis observation after the arity correction reports exactly four extra
call rows (6241→6245), with980 functions,561 origins and every origin group
unchanged. These correspond to the additional module_target/length/filter_map/snd
accounting expressions. The authorized reference update changes only call count
and its source-manifest provenance string; self.allow stays byte-identical.
Captured observation: improvement/2026-09-14-tezos-resolution/attempt1-arity-origin/run.json
(coverage-drift exit1 before recalibration). This observation alone is not a
passed recurring-consumer policy gate; the subsequent full test remains required.
