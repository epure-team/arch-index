# QA Scope — arch-metrics-gate

**Status:** VALIDATED
**Contract:** specs/arch-metrics-gate.md — runnable checks CHECK-1..7 are the QA floor.

## Quality gates (exact commands)

```bash
opam exec -- dune build
opam exec -- dune test                                  # includes test_arch_compare
./selftest-contract.sh && ./selftest-load.sh && ./selftest-effects.sh
```

## Behaviors to validate (from spec Runnable Checks)

```bash
# CHECK-1 (AC-1): metrics emits valid flat numeric JSON on the self-index
opam exec -- dune build
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
opam exec -- "$BIN" --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./arch-query /tmp/self.db metrics | jq -e 'type=="object" and (to_entries|all(.value|type=="number"))'

# CHECK-2 (AC-3): unwaived regression → exit 1
echo '{"large_functions":10}' >/tmp/b.json; echo '{"large_functions":12}' >/tmp/c.json
./arch-compare /tmp/b.json /tmp/c.json; test $? -eq 1

# CHECK-3 (AC-5): covered waiver → exit 0 + reason in output
printf 'large_functions <= 12  # test waiver\n' >/tmp/acc
./arch-compare --accept /tmp/acc /tmp/b.json /tmp/c.json && ./arch-compare --accept /tmp/acc /tmp/b.json /tmp/c.json | grep -q 'test waiver'

# CHECK-4 (AC-6): reasonless waiver → exit 1, 'invalid' reported
printf 'large_functions <= 12\n' >/tmp/acc2
./arch-compare --accept /tmp/acc2 /tmp/b.json /tmp/c.json; test $? -eq 1

# CHECK-6 (AC-4): missing tracked metric → exit 1
echo '{"large_files":3}' >/tmp/b2.json; echo '{}' >/tmp/c2.json
./arch-compare /tmp/b2.json /tmp/c2.json; test $? -eq 1

# CHECK-7 (AC-2): flat-schema DB → exported_functions present, doc_coverage_pct absent
# build a flat DB with NDJSON like selftest-load.sh, then:
./arch-query /tmp/flat.db metrics | jq -e 'has("exported_functions") and (has("doc_coverage_pct")|not)'

# AC-7 dogfood: clean pass, then artificial regression fails
./arch-query /tmp/self.db metrics -o /tmp/m.json
./arch-compare metrics-baseline.json /tmp/m.json                          # expect 0
jq '.large_functions = (.large_functions + 1)' /tmp/m.json >/tmp/m2.json 2>/dev/null || true
# (only if large_functions is emitted; otherwise regress another tracked metric)
./arch-compare metrics-baseline.json /tmp/m2.json; test $? -eq 1
```

## Extra QA probes

- Exit-code taxonomy: nonexistent DB → 2; DB w/o functions table → 3; malformed baseline JSON → 2 (not 1).
- EC-4 inclusive bound: current == bound → exit 0.
- Determinism: run metrics twice → byte-identical output.
- No TUI scenarios in scope.
