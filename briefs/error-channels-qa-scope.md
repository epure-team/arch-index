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

| corpus | build dir | expected nodes / bounded / under-hyp / scopes / links |
|---|---|---|
| arch-index (whole repo) | `_build/default` | 1 765 / 18.4 % / 44.4 % / 106 / 389 |
| octez-manager | `~/dev/octez-manager/_build/default` | 12 317 / 24.6 % / 47.6 % / 491 / 2 245 |
| proto_alpha | `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol` | 14 452 / 23.8 % / 46.4 % / 18 / 35 |

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

| function | file:line | expected | why (from source) | actual | verdict |
|---|---|---|---|---|---|
| _(fill before running)_ | | | | | |

Record `error-stats --channel tzresult` with and without `--assume-externals-pure`,
`fixpoint_seconds`, and the rejected-row count (must be 0).

## 6. Early smoke (plan step 2, evidence carried into QA)

The octez-manager `result`-channel smoke run and its three hand checks, as executed at the end of
the spine slice — include the transcript.
