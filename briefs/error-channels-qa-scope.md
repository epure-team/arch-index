# QA scope — error-channels

Sources: `specs/error-channels.md` (CHECK-5..7, AC-15..20), `briefs/error-channels-plan.md`,
`docs/exception-raise-sets-validation.md` (the baseline that must not move).

## 1. Deterministic gates

```bash
cd /tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build --root .                                   # CHECK-5
dune test --root . --force                            # tezt error_channels.ml + exn_raise_sets.ml
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
Q=./_build/default/bin/arch_query/arch_query.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
git diff origin/main --stat -- lib/arch_index/runner.ml    # empty
git diff origin/main -- architecture-schema.sql | grep '^+' | grep -viE 'IF NOT EXISTS|ALTER TABLE .* ADD COLUMN|^\+\+\+|^\+\s*--|^\+\s*$|^\+\s+'   # empty
```

## 2. Schema-version check (FR-034) — the number is contended

```bash
BASE=$(git show origin/main:lib/arch_index/arch_index_db.ml | sed -n 's/^let current_schema_version = "\(.*\)"/\1/p')
MINE=$(sed -n 's/^let current_schema_version = "\(.*\)"/\1/p' lib/arch_index/arch_index_db.ml)
echo "base=$BASE mine=$MINE"     # mine MUST be base with minor+1
grep -c "^| \`$MINE\`" docs/schema.md   # MUST be exactly 1 (no other row claims it)
```

## 3. Exception channel must not move — three corpora (the anti-regression gate)

Re-run the shipped exception channel and compare against
`docs/exception-raise-sets-validation.md` **exactly**; any drift is a NO-GO unless the impl brief
explains it.

**Read this before comparing.** arch-index is *itself* one of the corpora, and this feature adds
modules to it, so its raw counts legitimately move (measured 2026-09-03 after slices 0–1:
1 765 → 1 845 nodes, 106 → 108 scopes, 389 → 399 links, purely from `arch_errors_config.ml`).
A gate that compares arch-index's absolute numbers therefore proves nothing and would be
"fixed" by editing the expected value — the exact anti-pattern this repo has been bitten by.

**The binding assertion is on the two EXTERNAL corpora, which the feature cannot change.** They
must match *exactly*; any drift there is a real regression in the exception channel.

| corpus | build dir | expected nodes / bounded / under-hyp / scopes / links | rule |
|---|---|---|---|
| octez-manager | `~/dev/octez-manager/_build/default` | 12 317 / 24.6 % / 47.6 % / 491 / 2 245 | **exact — any drift is a NO-GO** |
| proto_alpha | `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol` | 14 452 / 23.8 % / 46.4 % / 18 / 35 | **exact — any drift is a NO-GO** |
| arch-index (whole repo) | `_build/default` | baseline 1 765 / 18.4 % / 44.4 % / 106 / 389 | may grow; every delta must be attributable to modules this branch adds — state the attribution, do not just update the number |

(Verified at slices 0–1: both external corpora reproduced the baseline to the digit.)

```bash
for c in arch-index octez-manager proto-alpha; do : ; done   # see the table for --build-dir
ARCH_QUERY_FORMAT=list $Q <db> exn-stats
ARCH_QUERY_FORMAT=list $Q <db> exn-stats --assume-externals-pure
sqlite3 <db> "SELECT count(*) FROM exn_scopes; SELECT count(*) FROM call_exn_scopes;"
```
Also: `raises`/`raisers-of`/`exn-stats` output must be **byte-identical** to the pre-change
binary on the arch-index fixture (capture both and `diff`).

## 4. Value channels on the fixture (AC-15..18)

Every scenario of `specs/error-channels.md` US-1..US-3 is a tezt assertion; QA reads the tezt
output, and additionally hand-runs:
```bash
ARCH_QUERY_FORMAT=list $Q <fixture-db> may-fail g --channel result       # BOUNDED: {}
ARCH_QUERY_FORMAT=list $Q <fixture-db> may-fail plain --channel result   # NOT_A_CARRIER(result)
ARCH_QUERY_FORMAT=list $Q <fixture-db> may-fail t4 --channel mytz        # record_trace: add
ARCH_QUERY_FORMAT=list $Q <fixture-db> error-stats --channel all
```

## 5. proto_alpha oracle (AC-19) — **write this table from source BEFORE running**

Pick ≥ 4 `tzresult` functions covering: one `record_trace` transform, one `catch` converter, one
cross-unit `let*` chain, and `main.ml`'s `begin_application` / `apply_operation` /
`finalize_block`. For each, read the source and write the expected set/verdict and the reason
*first*; then run `may-fail … --channel tzresult` and compare. A mismatch is a soundness NO-GO,
not a note.

**Written 2026-09-03 from source, before any `may-fail` run** (unit prefix
`Tezos_raw_protocol_alpha` elided as `…`; canonical paths per the exception channel's rule).

| # | function | file:line | expected `may-fail … --channel tzresult` | why (read from source) | actual | verdict |
|---|---|---|---|---|---|---|
| O-1 | `Period_repr.of_seconds` | `period_repr.ml:135-139` | `BOUNDED: {….Period_repr.Malformed_period}` | `match Internal.create secs with Some v -> return v \| None -> tzfail (Malformed_period secs)` — one literal origin via `Result_syntax.tzfail`, no bind of a carrier callee, `Internal.create` returns an `option` (not a `tzresult` carrier ⇒ no `tzresult` propagation). | | |
| O-2 | `Tez_repr.( -? )` | `tez_repr.ml:125-130` | `BOUNDED: {….Tez_repr.Subtraction_underflow}` | same shape: one `tzfail` with a literal constructor, no carrier callee. Also checks that an operator name round-trips as a function node. | | |
| O-3 | `Time_repr.( -? )` | `time_repr.ml:72-73` | `BOUNDED: {….Time_repr.Timestamp_sub, ….Period_repr.Malformed_period}` — the `Period_repr` element marked *wrapped* | `record_trace Timestamp_sub (Period_repr.of_seconds (…))`. `record_trace` is `mode = add`: the inner set (O-1, **cross-unit**) survives and the literal argument is added. This single row exercises the transform's add-semantics, cross-unit canonical-path agreement, and the fact that the inner set is not replaced. **If `Malformed_period` is missing, the transform was implemented as `replace` — a CRITICAL omission.** | | |
| O-4 | `Contract_storage.spend_from_balance` | `contract_storage.ml:674-676` | `BOUNDED: {….Contract_storage.Balance_too_low, ….Tez_repr.Subtraction_underflow}` (second wrapped) | `record_trace (Balance_too_low …) Tez_repr.(balance -? amount)` — same add-semantics over O-2, a second cross-unit chain, and a locally-qualified operator call (`Tez_repr.( -? )` under a local open). | | |
| O-5 | `Script_repr.force_bytes` | `script_repr.ml:264-266` | `tzresult`: `BOUNDED: {….Script_repr.Lazy_script_decode}`; `exception`: `BOUNDED: {}` | `Error_monad.catch_f (fun () -> Data_encoding.force_bytes expr) (fun _ -> Lazy_script_decode)` — the **converter** case: the thunk is a catch-all handler scope on the *exception* channel (so whatever `Data_encoding.force_bytes` may raise is closed, ⊤ included) and an origin on `tzresult` named by the handler's literal return. Checks both halves of `converters` in one function. | | |
| O-6 | `Main.begin_application` | `main.ml` (exposed) | `UNBOUNDED (⊤)` on `tzresult`, with reasons naming `may_top_edge` sites in `alpha_context.ml`; the *known* part must be non-empty | An entry point behind the functor-parameter frontier: the honest answer is ⊤ with witnesses, and the known part must still be listed (the `Top (known, reasons)` shape). A `BOUNDED` verdict here would be a soundness failure — the cone provably reaches unresolved edges. | | |
| O-7 | `Main.apply_operation`, `Main.finalize_block` | `main.ml` (exposed) | as O-6 | Same rationale; recorded so the entry-point escape set is on file for the protocol invariant "nothing escapes to the shell". | | |

Filling `actual`/`verdict` is QA's job; any mismatch is a **soundness NO-GO**, not a note. O-3 and
O-4 are the load-bearing rows (transform semantics + cross-unit identity); O-5 is the only
cross-channel row.

Record `error-stats --channel tzresult` with and without `--assume-externals-pure`,
`fixpoint_seconds`, and the rejected-row count (must be 0).

## 6. Early smoke (plan step 2, evidence carried into QA)

The octez-manager `result`-channel smoke run and its three hand checks, as executed at the end of
the spine slice — include the transcript.
