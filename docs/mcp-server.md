# MCP server (`arch-mcp`)

Exposes arch-index's verdicts to an agent over the Model Context Protocol (stdio,
line-delimited JSON-RPC). Built on [mcp-kit](https://github.com/epure-team/ocaml-mcp).

```sh
opam pin add mcp-kit https://github.com/epure-team/ocaml-mcp.git -y
dune build bin/arch_mcp
./_build/default/bin/arch_mcp/arch_mcp.exe --db /tmp/repo.db --repo . --tools-dir .
```

Register it with a client, e.g. Claude Code:

```json
{
  "mcpServers": {
    "arch-index": {
      "command": "/path/to/arch-index/_build/default/bin/arch_mcp/arch_mcp.exe",
      "args": ["--db", "/tmp/repo.db", "--repo", "/path/to/repo",
               "--tools-dir", "/path/to/arch-index"]
    }
  }
}
```

## Why bother — the space is crowded

codebase-memory-mcp (158 languages), CodeIndexer, Sourcegraph MCP, Claude Context. arch-index
cannot compete on breadth — two sound backends against 158 heuristic ones — and does not try.

**None of them offers a sound verdict.** They do tree-sitter/LSP structural indexing: who calls
what, best-effort, with dropped dynamic edges and no way to say *I don't know*. That is exactly
what an agent most needs and most lacks. An agent asking "can this handler reach `os.Exit`?" and
getting

```
UNKNOWN — no resolved path, but the cone escapes through a ⊤ edge at handleRequest
```

is far better served than one getting a confident, wrong "no".

## Every answer carries its own trust level

Each structured result includes a `provenance` block:

```json
{
  "db": "/tmp/repo.db",
  "callgraph_contract": "v1",
  "decision_contract": null,
  "built_by": "arch-load",
  "reachability_is_sound": true,
  "caveat": "This index is ⊤-marked: an UNREACHABLE verdict is a proof in a closed universe…"
}
```

This is the difference between "UNREACHABLE, proved over a ⊤-marked index" and "UNREACHABLE on
an index that never marked ⊤ at all" — the same three words carrying completely different
weight. The server's `instructions` field tells the agent to call `index_status` first for
exactly that reason.

## Tools

| tool | answers |
|---|---|
| `index_status` | what this index is and what it can answer — **call first** |
| `reachability` | `REACHABLE` / `UNREACHABLE` / `UNKNOWN` / `REFUSED`, plus the MUST-only ground-truth answer |
| `escapes` | the ⊤ edges reachable from a function — what the analysis could not see |
| `callers_of`, `callees_of` | one-hop neighbours |
| `useless_branches` | dead-logic findings: proofs that code cannot matter |
| `dead_blocks` | call sites in CFG-unreachable blocks |
| `mutation_density` | mutation-site ranking (diagnostic, never a gate) |
| `change_impact` | per-diff briefing (touched, affected API, blast radius, ⊤ frontier, tests) |
| `architecture_rules` | evaluate a rules file — `VIOLATION` / `POSSIBLE` / `UNKNOWN` / `PASS` |
| `mutation_plan` | what is worth mutating, and which tests must rerun |

Resource `arch-index://contract` explains how to read a verdict, so an agent can fetch the
semantics rather than infer them from the words.

## Two deliberate design decisions

**The server shells out.** It does not reimplement reachability; every verdict comes from the
same `arch-query` / `arch-impact` / `arch-rules` / `arch-mutants` a human runs. A second
implementation of `unreachable` in OCaml would mean two definitions of soundness in one
repository, and the first time they disagreed the MCP answer would be the one nobody had
checked. The cost is a subprocess per call; the benefit is that an agent and a reviewer cannot
be told different things. Arguments are passed as a literal argv array, never interpolated into
a shell string.

The subprocess runs with `ARCH_QUERY_FORMAT=list`. `arch-query` defaults to sqlite3's `-box`
output, which is right for a human at a terminal and wrong here: a one-line verdict would reach
the agent wrapped in ~400 box-drawing characters, spending its context on borders.

A non-zero exit is **not** folded into an error, because several of these tools use exit codes
as verdicts — `arch-query unreachable` exits 3 to REFUSE, `arch-rules` exits 1 on a violation.
Collapsing that would turn a meaningful refusal into "the tool broke".

**Paths are fixed at startup.** `--db` and `--repo` are process arguments; no tool takes a path.
An agent-supplied path would be an arbitrary-file-read surface, and there is no reason for a
session to roam. The server also refuses to start on a missing database rather than answering
every question with an error — an agent cannot distinguish "the server is broken" from "the
answer is no".

## Build status

mcp-kit is not on opam — it lives in the private repo `epure-team/ocaml-mcp` — so the server is
**not part of the default build**. `bin/arch_mcp/dune` gates it on an environment variable:

```sh
opam pin add -y --no-action mcp-kit https://github.com/epure-team/ocaml-mcp.git
opam install --yes mcp-kit
ARCH_MCP=yes dune build bin/arch_mcp
```

Without `ARCH_MCP=yes`, `dune build` does not see the target at all and a checkout with no pin
builds clean.

An earlier version used `(optional)` instead, on the belief that dune skips an optional target
whose library is missing. It does not: `(optional)` suppresses only the *install* entry, while
the executable stays in the directory's `@all` alias, which `@default` depends on — so
`dune build` still failed with `Library "mcp-kit.stdio" not found`. (`%{lib-available:...}` in
`enabled_if` would auto-detect and need no flag, but dune rejects that variable in an
executable's `enabled_if` at every language version up to 3.20.)

The cost of an explicit flag is that a missing pin now looks the same as a deliberate skip, so
CI does not rely on the build to catch rot: the `mcp` job sets `ARCH_MCP=yes`, then asserts the
`.exe` exists — a false `enabled_if` makes `dune build <target>` exit 0 having produced nothing.
That job needs the private pin, so it runs only when `OCAML_MCP_TOKEN` is set; when it is not,
CI emits a warning saying in as many words that a green run is **not** evidence the server still
compiles.
# Provenance And Paths

MCP `reachability_is_sound` is derived from `Arch_db.contract_ok`, including
the presence and validity of every `calls.kind`; a raw metadata stamp is not
trusted. Repository file arguments are resolved canonically and accepted only
when their real path remains within the canonical repository root on a path
component boundary. Absolute paths, traversal, missing targets, and symlinks
resolving outside the root are refused without reading external contents.
