# Install

## Build from source

Requires OCaml ≥ 5.3 and opam.

```sh
git clone https://github.com/epure-team/arch-index
cd arch-index
opam install --deps-only --yes .
opam exec -- dune build
```

The binary is at `_build/default/bin/arch_index_cli/arch_index_cli.exe`. The `arch-index` wrapper calls it via `$HERE/bin/arch_index_cli` — copy the binary there for the wrapper to work. `arch-query` (bash) and `arch-load` (Python 3) are self-contained scripts requiring no build artifact. `arch-callgraph-ocaml` is a separate compiled binary:

```sh
cp _build/default/bin/arch_index_cli/arch_index_cli.exe bin/arch_index_cli
cp _build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe bin/arch-callgraph-ocaml
```

## LSP backends (per language)

arch-index uses the language server to extract call graphs. Install the server for each language you want to index:

| Language | Install |
|---|---|
| Go | `go install golang.org/x/tools/gopls@latest` |
| Rust | `rustup component add rust-analyzer` |
| TypeScript | `npm i -g typescript-language-server` |
| Python | `pip install pyright` or `pip install python-lsp-server` |
| OCaml | `opam install ocaml-lsp-server` |

## Notes

**Go**: point `arch-index` at the **module root** (the directory containing `go.mod`). gopls needs a warm-up period before `workspace/symbol` returns results; if you get 0 functions on a large module, the LSP warm-up timeout in the binary may need tuning.

**OCaml (CMT path)**: `arch-callgraph-ocaml` uses compiled `.cmt` files produced by `dune build` — no live LSP needed. Run `dune build` first, then point at `_build/default`.

## Quick verification

```sh
# Index this repo's OCaml library
./arch-callgraph-ocaml --build-dir=_build/default/lib/arch_index \
  --db-path=/tmp/self.db --schema-path=architecture-schema.sql
sqlite3 /tmp/self.db "SELECT count(*) AS functions FROM functions;"
# Should print ≥ 100
```
