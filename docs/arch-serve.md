# arch-serve — browsing the index

`arch-serve` serves an arch-index database as a small single-page app, for the
questions that are quicker to answer by looking at a neighbourhood than by
composing a query.

```bash
./arch-serve /tmp/repo.db            # http://localhost:7371
./arch-serve /tmp/repo.db --port 8080
```

The listener binds the **loopback interface only**. There is no
authentication, no authorisation and no write path; it is a local viewer, not a
service to deploy. Serving an index over a network interface would publish your
codebase's call graph to anyone who can reach the port.

## Which indexes it reads

| Schema | Produced by | Served |
|---|---|---|
| Flat (`functions.file_path`) | `arch-index` (LSP), `arch-load` | yes |
| Main (`functions.module_id`) | `arch-callgraph-ocaml` | **no** — declined at startup |

A main-schema index is refused with exit 2 and a message pointing at
`arch-query`, rather than started and left to fail on every request. Reading the
main schema is not implemented: every endpoint selects `functions.file_path`,
which that schema does not have — a function points at a `modules` row instead.

This is a real gap, not a design decision. The repository's own self-index is a
main-schema database, so `arch-serve` cannot currently browse the project that
produces it.

## Endpoints

| Route | Answers |
|---|---|
| `/` | the SPA (HTML/JS/CSS compiled into the binary) |
| `/api/modules` | modules, synthesised from `file_path` prefixes |
| `/api/functions` | functions, filterable by module and by `exported` |
| `/api/graph/neighborhood` | the callers/callees around one function |
| `/api/graph/module` | the graph within one module |
| `/api/reaches` | whether a path exists between two functions |

Unknown routes are 404.

## What it is not

It does not implement the soundness contract. `arch-query` is the tool that
refuses to answer when the index cannot support a verdict; `arch-serve` shows
what the database contains. For anything you intend to gate a PR on, use
`arch-query` or `arch-rules`.
