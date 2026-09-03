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
| proto_alpha | `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol` | 14 452 / 23.8 % / 46.4 % / **19** / 35 | exact — the scope count is 19, not the pre-feature 18; see the attribution note below. Any OTHER drift is a NO-GO |
| arch-index (whole repo) | `_build/default` | baseline 1 765 / 18.4 % / 44.4 % / 106 / 389 | may grow; every delta must be attributable to modules this branch adds — state the attribution, do not just update the number |

(Verified at slices 0–1: both external corpora reproduced the baseline to the digit. Re-verified
after the origin/main merge — see `docs/exception-raise-sets-validation.md`.)

**Attribution for proto_alpha's 18 → 19 scopes (do not "fix" this by reverting):** the converter
rule mints one catch-all exception scope at `Script_repr.force_bytes` (`script_repr.ml:264`), the
only `catch_f` site in `lib_protocol`. It links to zero calls (the documented cross-node residual),
so no verdict changes and every other number is identical.

**Count with a channel filter.** `exn_scopes` and `call_exn_scopes` are now shared with the value
channels. A channel-blind count reads 4 346 links on octez-manager instead of 2 245 and looks like
a regression when nothing moved:
```sql
SELECT count(*) FROM call_exn_scopes l JOIN exn_scopes s ON s.id = l.scope_id
 WHERE s.channel = 'exception';
```

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
| O-1 | `Period_repr.of_seconds` | `period_repr.ml:135-139` | `BOUNDED: {….Period_repr.Malformed_period}` | `match Internal.create secs with Some v -> return v \| None -> tzfail (Malformed_period secs)` — one literal origin via `Result_syntax.tzfail`, no bind of a carrier callee, `Internal.create` returns an `option` (not a `tzresult` carrier ⇒ no `tzresult` propagation). | `BOUNDED: {Tezos_raw_protocol_alpha__Period_repr.Malformed_period}` | **MATCH** |
| O-2 | `Tez_repr.( -? )` | `tez_repr.ml:125-130` | `BOUNDED: {….Tez_repr.Subtraction_underflow}` | same shape: one `tzfail` with a literal constructor, no carrier callee. Also checks that an operator name round-trips as a function node. | `BOUNDED: {Tezos_raw_protocol_alpha__Tez_repr.Subtraction_underflow}` | **MATCH** |
| O-3 | `Time_repr.( -? )` | `time_repr.ml:72-73` | `BOUNDED: {….Time_repr.Timestamp_sub, ….Period_repr.Malformed_period}` — the `Period_repr` element marked *wrapped* | `record_trace Timestamp_sub (Period_repr.of_seconds (…))`. `record_trace` is `mode = add`: the inner set (O-1, **cross-unit**) survives and the literal argument is added. This single row exercises the transform's add-semantics, cross-unit canonical-path agreement, and the fact that the inner set is not replaced. **If `Malformed_period` is missing, the transform was implemented as `replace` — a CRITICAL omission.** | `BOUNDED: {Tezos_raw_protocol_alpha__Period_repr.Malformed_period, Tezos_raw_protocol_alpha__Time_repr.Timestamp_sub}` (the `functions` table also has an unrelated `-?` in `validate.ml` — `NOT_A_CARRIER(tzresult)` — a same-name coincidence, not this row) | **MATCH** — add-semantics preserved, cross-unit identity agrees |
| O-4 | `Contract_storage.spend_from_balance` | `contract_storage.ml:674-676` | `BOUNDED: {….Contract_storage.Balance_too_low, ….Tez_repr.Subtraction_underflow}` (second wrapped) | `record_trace (Balance_too_low …) Tez_repr.(balance -? amount)` — same add-semantics over O-2, a second cross-unit chain, and a locally-qualified operator call (`Tez_repr.( -? )` under a local open). | `BOUNDED: {Tezos_raw_protocol_alpha__Contract_storage.Balance_too_low, Tezos_raw_protocol_alpha__Tez_repr.Subtraction_underflow}` | **MATCH** |
| O-5 | `Script_repr.force_bytes` | `script_repr.ml:264-266` | `tzresult`: `BOUNDED: {….Script_repr.Lazy_script_decode}`; `exception`: `BOUNDED: {}` | `Error_monad.catch_f (fun () -> Data_encoding.force_bytes expr) (fun _ -> Lazy_script_decode)` — the **converter** case: the thunk is a catch-all handler scope on the *exception* channel (so whatever `Data_encoding.force_bytes` may raise is closed, ⊤ included) and an origin on `tzresult` named by the handler's literal return. Checks both halves of `converters` in one function. **NB (path inventory, 2026-09-03): this is the ONLY `catch_f` site in all 276 units of `lib_protocol`** — the sole real-world converter instance in the acceptance corpus, so the fixture must carry the rest of that role's coverage. | `tzresult`: `BOUNDED: {Tezos_raw_protocol_alpha__Script_repr.Lazy_script_decode}` — **MATCH** (the literal-extraction half of `converters` works: the handler's own literal return names the error, per call site, not a static config string). `exception`: `UNBOUNDED (⊤): {}`, reasons `external …Data_encoding.force_bytes` and `external …Error_monad.catch_f` — **MISMATCH, documented residual (sound, imprecise)**: the guarded thunk `fun () -> Data_encoding.force_bytes expr` is promoted to its OWN CFG/lambda node (this codebase gives every lambda literal its own lowering context, slice ≤3 design), so the `converters` scope minted on `force_bytes`'s own node cannot close a call that structurally lives in a DIFFERENT node's own scope list. Fixed the same-context case (an inline call or a single-`let` alias — `resolve_guarded_call` in `arch_index_cmt.ml`, added this slice after this exact finding) but not the cross-node lambda-literal case; reaching into a nested lambda node's scope table from the enclosing converter call is a real architectural extension, out of slice 4/5's authorized scope, and risks the frozen exception-channel numbers if rushed. The verdict is still SOUND (⊤ over-approximates), just less precise than the oracle assumed. | **PARTIAL MATCH — tzresult MATCH, exception MISMATCH (documented residual, not a soundness bug)** |
| O-6 | `Main.begin_application` | `main.ml` (exposed) | `UNBOUNDED (⊤)` on `tzresult`, with reasons naming `may_top_edge` sites in `alpha_context.ml`; the *known* part must be non-empty | An entry point behind the functor-parameter frontier: the honest answer is ⊤ with witnesses, and the known part must still be listed (the `Top (known, reasons)` shape). A `BOUNDED` verdict here would be a soundness failure — the cone provably reaches unresolved edges. | `UNBOUNDED (⊤)` with a large non-empty known part (dozens of paths incl. `Main.Cannot_apply_in_partial_validation`, `Contract_storage.Balance_too_low`, `Script_tc_errors.*`, …) and reasons incl. `may_top_edge script_ir_translator.ml:…`, `external`, `unknown_exn_value`, `inferred_bind`. `main.ml`'s `begin_application` is one of THREE same-named functions in the corpus (`apply.ml`, `main.ml`, `validate.ml`); this is the `main.ml` row, id-ordered second of three in `may-fail begin_application --channel tzresult`. | **MATCH** |
| O-7 | `Main.apply_operation`, `Main.finalize_block` | `main.ml` (exposed) | as O-6 | Same rationale; recorded so the entry-point escape set is on file for the protocol invariant "nothing escapes to the shell". | **MISMATCH, documented, non-error-channels root cause**: `main.ml` has no `finalize_block` (the real binding is `finalize_application = Apply.finalize_block`); both `apply_operation = Apply.apply_operation` and `finalize_application = Apply.finalize_block` are POINT-FREE re-exports (η-reduced: `let f = M.g`, no `Texp_apply` in the body at all). The whole-repo call-graph walker (shared by every channel, including `exception` — this is not an error-channels-specific defect) only ever records a call edge at a `Texp_apply` site; a bare identifier re-export produces NO calls row, so both nodes are (correctly, per the walker's existing model) `BOUNDED: {}` with zero edges — not the ⊤-with-witnesses the oracle predicted from reading `Updater.PROTOCOL`'s signature alone, which doesn't show that these two are forwarding aliases rather than real bodies. Confirmed by inspecting the real `Apply.apply_operation`/`Apply.finalize_block` bodies directly (`apply.ml`), which DO carry the expected ⊤ witnesses — the escape set exists, just not reachable through the alias node the oracle named. | **MISMATCH — pre-existing point-free-alias gap in the shared call-graph model, not a slice 4/5 defect; not fixed here (out of scope, whole-model change, regression risk to the frozen exception channel)** |

Filling `actual`/`verdict` is QA's job; any mismatch is a **soundness NO-GO**, not a note. O-3 and
O-4 are the load-bearing rows (transform semantics + cross-unit identity); O-5 is the only
cross-channel row.

Record `error-stats --channel tzresult` with and without `--assume-externals-pure`,
`fixpoint_seconds`, and the rejected-row count (must be 0).

## 6. Early smoke (plan step 2, evidence carried into QA)

The octez-manager `result`-channel smoke run and its three hand checks, as executed at the end of
the spine slice — include the transcript.
