# QA scope — exn-raise-sets

**Sources:** `specs/exn-raise-sets.md` (CHECK-1..4, AC-1..14), `briefs/exn-raise-sets-plan.md` (Slice H).

## Deterministic gates (all must pass)

```bash
cd /tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build 2>&1 | tail -5
dune test --force 2>&1 | tail -30                       # CHECK-1 (tezt exn_raise_sets + all existing)
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -   # CHECK-2
git diff origin/main --stat -- lib/arch_index/runner.ml                                   # CHECK-4: empty
git diff origin/main -- architecture-schema.sql | grep '^+' | grep -viE 'IF NOT EXISTS|^\+\+\+|^\+\s*--|^\+\s*$|^\+\s+' # CHECK-4: empty
./_build/default/bin/arch_query/arch_query.exe /tmp/self.db exn-stats                      # self-index measurement
```

## Corpus measurement (CHECK-3, Slice H) — required

```bash
DB=/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db; rm -f "$DB"
time $BIN --build-dir=/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol --db-path="$DB" --schema-path=architecture-schema.sql 2>&1 | tail -15
Q=./_build/default/bin/arch_query/arch_query.exe
time $Q "$DB" exn-stats
time $Q "$DB" exn-stats --assume-externals-pure
```
Then spot checks (record full output in `briefs/exn-raise-sets-qa.md`):
1. Find a direct raiser: `sqlite3 "$DB" "SELECT f.name, m.path, o.form, o.exn_path, o.escapes FROM exn_origins o JOIN functions f ON f.id=o.function_id JOIN modules m ON m.id=f.module_id WHERE o.form='raise' AND o.escapes=1 LIMIT 5"`; pick one; `$Q "$DB" raises <name>`; open the source line and confirm.
2. Find a `try` wrapper: `sqlite3 "$DB" "SELECT f.name, s.form, s.catch_all, group_concat(c.exn_path) FROM exn_scopes s JOIN functions f ON f.id=s.function_id LEFT JOIN exn_scope_catches c ON c.scope_id=s.id GROUP BY s.id LIMIT 10"`; pick one whose covered call has a known raiser; confirm `raises` excludes it.
3. Find a callback caller: a function with a `MAY_TOP` edge (`SELECT cf.name FROM calls c JOIN functions cf ON cf.id=c.caller_id WHERE c.kind='MAY_TOP' LIMIT 5`); confirm `UNBOUNDED (⊤)` with `may_top_edge`.
4. `Main` entry points (exposed functions of the `main.ml` module): `raises` each; list every non-⊤ escape as a finding; list ⊤ reasons.
5. One cross-unit case: an `exn_scope_catches.exn_path` whose exception is declared in another unit — confirm string equality with an `exn_origins.exn_path` from the declaring unit.

Any contradiction between a `raises` answer and the source is a soundness NO-GO.

## Behaviours to validate by reading output

- `raises` on the tezt fixture matches spec US-2 wording exactly (BOUNDED / UNBOUNDED (⊤) / BOUNDED_UNDER_HYP).
- Flat DB → exit 3 with `NOT_ANALYSED`; un-⊤-marked DB → exit 3 `REFUSED`.
- `exn-stats` reports wall-clock of the fixpoint; on proto_alpha record it.
- Rejected-row count of the corpus run (`rejections_by_table`) — any `exn_*` rejection is a finding.
