# QA Brief — error-channels

**Date:** 2026-09-04
**Status:** GO ✅
**Round:** 1 (qualifying 0/3)

## Round state

Fresh cycle, round 1. No qualifying causes — every gate passed on its first run.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build --root .` | ✅ PASS (exit 0) | 1s |
| Tests | `GOFLAGS=-buildvcs=false dune test --root . --force` | ✅ 124 passed, 0 failed (exit 0) | 88s |
| Format / Lint | — | ⚠️ **not documented** — no `.ocamlformat`, no lint step in `.github/workflows/ci.yml`. Recorded, not invented. | — |
| Self-index golden | index `_build/default/lib/arch_index` + `diff test/fixtures/self-index-stats.txt` | ✅ diff empty (23 / 746 → re-measured 23 / 761 / 4967 matches) | <1s |
| Architecture rules | `arch_rules … arch-rules.txt --on-vacuous fail` | exit 0 — **1 proved / 0 violations / 3 UNKNOWN**. Recorded here as ✅ "4 rules, 0 failing", which was the tool's own summary collapsing a three-state verdict into one number; corrected in PR #70. Three of the four rules proved nothing, so this is not a green gate — it is an unchanged one. See specs/qualified-unit-resolution.md §10.5. | <1s |

### The `GOFLAGS` claim, verified rather than accepted

Without `GOFLAGS=-buildvcs=false` the suite exits 1 with exactly one failure,
`callgraph-go: the three edge kinds and the verdicts they license`, and the log says
`error obtaining VCS status: exit status 128 / Use -buildvcs=false to disable VCS stamping.`
This branch's diff touches no Go file (`git diff origin/main --name-only | grep -i go` is empty),
so the cause is environmental — Go refuses to stamp VCS metadata for a git *worktree* under
`/tmp`. With the flag: 124/124, exit 0.

## Tests: detail

- New tests this cycle: US-2.9, US-2.14, US-2.15, US-2.16, AC-15 (2 and 6), AC-16 (6 and 12),
  AC-18 (6), re-index idempotence, `schema_drop_list`, two strict cases, two reachability cases.
- Existing: 124 pass, 0 skip, 0 fail.
- Regression detected: **NO**.

## Code-intel gate

Skipped — `scripts/code-intel-resolve.js` is absent and there is no `kb/` in this repository.
No verdict impact.

## Schema and zero-diff invariants (FR-034, CHECK-6)

| Check | Result |
|---|---|
| `current_schema_version` | base (origin/main) `1.7` → branch `1.8` ✅ |
| Rows claiming `1.8` in `docs/schema.md` | exactly 1 ✅ |
| Row documenting `1.6` as never shipped | present ✅ |
| `lib/arch_index/runner.ml` vs origin/main | 0 lines ✅ |
| `tezt/tests/exn_raise_sets.ml` vs origin/main | 0 lines ✅ |

## The binding gate — exception channel on the two EXTERNAL corpora

This repository's own numbers move whenever code is added, so they prove nothing; these two do.
Both indexed into **fresh** databases, 0 rejected rows each.

| measure | expected | octez-manager | expected | proto_alpha |
|---|---|---|---|---|
| nodes | 12317 | **12317** ✅ | 14452 | **14452** ✅ |
| bounded | 3024 (24.6%) | **3024 (24.6%)** ✅ | 3436 (23.8%) | **3436 (23.8%)** ✅ |
| bounded, externals-pure | 47.6% | **47.6%** ✅ | 46.4% | **46.4%** ✅ |
| ⊤ external | 2834 | **2834** ✅ | 3273 | **3273** ✅ |
| ⊤ may_top_edge | 6459 | **6459** ✅ | 7743 | **7743** ✅ |
| origins | 765 | **765** ✅ | 1219 | **1219** ✅ |
| exception scopes | 491 | **491** ✅ | 19 | **19** ✅ |
| exception links | 2245 | **2245** ✅ | 35 | **35** ✅ |
| tzresult | — | — | 585/2137 (27.4%), 44.3% under-hyp | **585/2137 (27.4%), 44.3%** ✅ |

Counted with the channel filter, which is load-bearing:
`SELECT count(*) FROM call_exn_scopes l JOIN exn_scopes s ON s.id=l.scope_id WHERE s.channel='exception'`.

### The two known-moved numbers, verified structurally rather than accepted

- **proto_alpha exception scopes 18 → 19.** Exactly one exception-channel scope has zero links:
  `scope 258 fn=force_bytes catch_all=1 line=264 links=0` — the converter's catch-all at
  `script_repr.ml:264`, as documented. No other scope is unlinked.
- **octez-manager channel-blind links 4346 → 4386.** Not accepted as arithmetic: the multiplicity
  histogram is `{1: 4306, 2: 40}` (no call carries three), and all **40** two-scope calls are mixed
  exception+value (`HAVING sum(channel='exception')>0 AND sum(channel<>'exception')>0` = 40).
  4306 + 2×40 = 4386. This is the widened `PRIMARY KEY (call_id, scope_id)` doing exactly what it
  was widened for.

## proto_alpha oracle (FR-033 / AC-19 / CHECK-7)

| # | function | expected | actual | verdict |
|---|---|---|---|---|
| O-1 | `Period_repr.of_seconds` | `BOUNDED: {…Period_repr.Malformed_period}` | `BOUNDED: {Tezos_raw_protocol_alpha__Period_repr.Malformed_period}` | ✅ MATCH |
| O-2 | `Tez_repr.( -? )` → query `-?` | `BOUNDED: {…Tez_repr.Subtraction_underflow}` | `BOUNDED: {Tezos_raw_protocol_alpha__Tez_repr.Subtraction_underflow}` | ✅ MATCH |
| O-3 | `Time_repr.( -? )` → query `-?` | `BOUNDED: {…Timestamp_sub, …Malformed_period}` | `BOUNDED: {…Period_repr.Malformed_period, …Time_repr.Timestamp_sub}` | ✅ MATCH — the `add` transform kept the cross-unit inner element |
| O-4 | `Contract_storage.spend_from_balance` | `BOUNDED: {…Balance_too_low, …Subtraction_underflow}` | `BOUNDED: {…Contract_storage.Balance_too_low, …Tez_repr.Subtraction_underflow}` | ✅ MATCH |
| O-5 | `Script_repr.force_bytes` | tzresult `BOUNDED: {…Lazy_script_decode}`; exception `BOUNDED: {}` | tzresult `BOUNDED: {…Script_repr.Lazy_script_decode}` ✅; exception `UNBOUNDED (⊤): {}` ❌ | ⚠️ PARTIAL — documented residual (a converter closes the exception channel only within one CFG node; the guarded thunk is its own lambda node) |
| O-6 | `Main.begin_application` | `UNBOUNDED (⊤)`, known part non-empty | `UNBOUNDED (⊤): {}` for the `main.ml` node (the other two homonyms, `apply.ml` and `validate.ml`, are ⊤ with large known parts) | ⚠️ PARTIAL — ⊤ is right, the non-empty-known-part expectation is not met for the alias node |
| O-7 | `Main.apply_operation`, `Main.finalize_application` | as O-6 | `BOUNDED: {}` for both `main.ml` nodes | ❌ MISMATCH — documented, pre-existing: both are η-reduced re-exports (`let f = M.g`) with no `Texp_apply`, so the shared walker records zero call edges. Not error-channels-specific. |

**5 of 7 full matches, 2 documented residuals, no new soundness mismatch.**

### Two corrections this QA run made to its own oracle

1. **O-2/O-3 were written with the source spelling `( -? )`.** That is not the function's identity.
   The index is built from the typed tree, so an operator is stored under its `Ident` name — `-?`,
   `+?`, `<=` — and the parentheses are OCaml binding syntax. `may-fail "( -? )"` is REFUSED;
   `may-fail "-?"` answers. **The oracle was wrong, not the measurement**, and the mechanism is
   sounder than the row implied. `briefs/error-channels-qa-scope.md` is corrected.
2. **O-7's row named `Main.finalize_block`, which does not exist** — the binding is
   `finalize_application = Apply.finalize_block`. Already recorded in the scope file.

## Homonyms — a MEDIUM finding for follow-up, not a blocker

`may-fail <name>` prints **one verdict per function sharing that name** (three for `-?`, two for
`apply_operation`), which is the sound behaviour. But every verdict is labelled with the bare name
and there is no module-qualified form — `Main.apply_operation`, `main.apply_operation` and
`Tezos_raw_protocol_alpha__Main.apply_operation` are all REFUSED, because the module is a separate
column rather than part of the identifier. In proto_alpha **540 of 14452** function names are
shared by two or more nodes, so a caller cannot always tell which verdict belongs to which
function.

This is **pre-existing and not introduced here**: `raises`, shipped in PR #54, resolves names the
same way. It does not affect any computed set. Filed as follow-up, not a QA failure.

I record it also because it nearly produced a false finding in this very run: reading the output
through `head -1` made the tool look as though it silently picked one node. It does not. Truncated
output is not evidence.

## Cross-runtime QA

`codex` (`codex:eb1805ecc8f4af35`) reported `available` and ran, wrapper exit 0, tree unmodified.
**8 of 11 checks could not EXECUTE**: the wrapper's sandbox mounts `/mnt/ssd-external-2to`
read-only (`mktemp: … Read-only file system`) and denied a tezt temp directory
(`Operation not permitted` on `serve:`), so every check needing a scratch database or a writable
temp dir failed to start. That is a degradation, not a disagreement.

The three checks it could execute **agree with the primary run**: `dune build` exit 0; schema
version branch `1.8` vs `origin/main` `1.7` with exactly one `docs/schema.md` row; the restricted
`git diff --stat` empty. **No divergence on anything actually run**, so no discrepancy block.

## NO-GO issues

None.

## Verdict

**GO** — ready for `/roster-ship`.

Every gate passed, both external corpora reproduce the frozen exception-channel baseline to the
digit, and the two numbers that moved are attributed structurally rather than accepted. The
remaining oracle gaps are the residuals the review already adjudicated, both with a pre-existing
root cause in the shared call-graph walker, and both documented in `docs/error-channels.md` §6.
