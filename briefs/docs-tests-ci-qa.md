# QA Brief — docs-tests-ci

**Date:** 2026-06-25
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Deps | `opam install --deps-only --yes .` | ✅ PASS (Nothing to do — already satisfied) | 6.4s |
| Build | `opam exec -- dune build` | ✅ PASS | 0.2s |
| Tests | `opam exec -- dune test --force` | ✅ 10 alcotest PASS (forced rerun for visibility) | 0.2s |
| Shell: contract | `./selftest-contract.sh` | ✅ PASS | 0.2s |
| Shell: load | `./selftest-load.sh` | ✅ PASS | 0.3s |
| Self-index golden | raw sqlite3 diff (see below) | ✅ PASS | 0.2s |
| No suppression | `grep '|| true' .github/workflows/ci.yml` | ✅ PASS (none found) | — |

## Tests: detail

- Alcotest (10 tests, all PASS):
  - `Comment_parser 0–9`: empty comment, JSDoc @tag syntax, OCaml {tag} syntax, violators, score, summary, score ordering, parse_violators_json (×3)
- Inline tests (43 tests) — run silently within `dune test`, all PASS:
  - `comment_parser.ml`: 18 tests (make_body, make_body_simple, score, find_jsdoc_tags, find_ocaml_tags, parse_violators_json)
  - `arch_index_comment_parser.ml`: 15 tests (make_body, find_substring, split_on_em_dash, parse_violator_entries, find_tag_positions, section_present)
  - `arch_index_db.ml`: 7 tests (bind_text, bind_int, bind_bool×2, bind_text_opt×2, last_insert_rowid)
- **Regression detected:** NO

## Self-index gate

The QA scope had a stale command (`./arch-callgraph-ocaml` positional args + `arch-query stats`) that is incompatible with the architecture DB schema. Used CI-equivalent approach instead:

```bash
BIN="./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
opam exec -- "$BIN" --build-dir=_build/default/lib/arch_index \
  --db-path=/tmp/qa-self.db --schema-path=architecture-schema.sql
sqlite3 /tmp/qa-self.db "SELECT 'modules: ' || count(*) FROM modules; ..."
diff test/fixtures/self-index-stats.txt /tmp/qa-self-stats.txt
```

Result: **DIFF OK** — 18 modules, 144 functions (≥ 50 ✅), 2376 calls.

## Behavioral checks

| Check | Criterion | Result |
|---|---|---|
| B1: README length | `wc -l README.md` ≤ 70 | ✅ 68 lines |
| B2: docs/ links | all `docs/*.md` refs in README resolve | ✅ docs/install.md, docs/edge-kind-contract.md, docs/schema.md |
| B3: ADR exists | `docs/adr/001-self-index-golden.md` present | ✅ |
| B4: Golden file non-trivial | functions ≥ 50 | ✅ 144 |
| B5: CI steps | shell test step + self-index step present | ✅ |
| B6: No `|| true` | grep CI | ✅ none found |
| B7: Go setup step | out of scope per intake brief (selftest-callgraph-go.sh requires live LSP, left as local test) | N/A |

## Verdict

**GO** — ready for `/roster-ship`
