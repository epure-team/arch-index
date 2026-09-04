# Implementation brief — coverage-error-channels

mode: fast
branch: `feat/coverage-error-channels`, **stacked on `feat/error-channels`** (PR #60, open)
base: 52b74ea — NOT main, because this reads `comment_db_meta.error_contract`, which #60 introduces.

## The gap

`arch-coverage-matrix` exists for one guarantee: never let an unperformed analysis look like a
clean result. Its vocabulary is `callgraph` / `effects` / `cfg` / `types` / `coverage` /
`decisions` — and it says **nothing** about error channels. So a user asking "what has been
analysed?" gets a complete-looking matrix with no row for whether the error-channel analysis ran,
for any language. That is the honest-absence guarantee failing in the one place users look for it.

## What I found before designing, and why it changed the design

1. **`compute` never opens a database.** It probes the *filesystem* — which producers are built —
   and returns rows; `write_coverage` opens the db afterwards only to INSERT. So `error_contract`,
   which is a fact recorded *inside a produced database*, is not reachable from the current
   `compute` signature. The task's premise ("derive status from `error_contract`") needed the db
   to be threaded in.
2. **`has_gap` counts only `language <> None` rows, deliberately.** The existing comment is
   explicit: `decisions` and `coverage` are excluded because they are "nothing a run of THIS tool
   can fix", and "a gate that always fires carries no signal".

   **This is a trap for the obvious implementation.** No non-OCaml producer can emit `exn_*` rows
   yet — the NDJSON record types do not exist (documented in `docs/error-channels-porting.md`).
   A naive per-language `error_channels` row would therefore be `not_analysed` for Go and Rust
   *forever*, making `arch-coverage-matrix` exit 1 on every polyglot repository until that feature
   lands. That is precisely the always-firing gate the existing comment warns against.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Row shape | Per-language, like `callgraph` — not a single `language = None` row | Whether error channels were analysed is a fact about a *producer*, and producers are per-language. One global row would flatten "OCaml analysed three channels" and "Go cannot analyse any". |
| Emit a row for languages that cannot analyse | **Yes** | Omitting it is silence, which is the failure this whole tool exists to prevent. The row says `not_analysed` and its detail names the reason. |
| Gap counting | A row counts only if **this run could fix it** | Stated once in a named predicate rather than inferred from `language <> None` in three places. The four existing analyses keep their exact behaviour; a `not_analysed` `error_channels` row for a producer that structurally cannot emit them does not fire the gate, because no action by this run would change it. |
| `partial` | Contract present but listing **fewer channels than the producer's built-ins** | The distinction the roadmap session and I agreed must not be flattened: a database carrying only `exception` is not the same as one carrying `exception,result,option`. `covered` would overstate it and `not_analysed` would understate it — `partial` is exactly the fourth status the CHECK already allows. |
| Source of truth | `comment_db_meta.error_contract` when the target db has it; the callgraph probe otherwise | The contract is authoritative about what a producer *actually emitted*; the probe only says what it *could* emit. Prefer evidence over capability, fall back when there is no evidence. |

## Scope

`lib/arch_index/coverage_matrix.ml(i)`, `bin/arch_coverage_matrix/arch_coverage_matrix.ml`,
`tezt/tests/coverage_matrix.ml`. No schema change — `analysis_coverage` already exists and its
`status` CHECK already admits all four values, so **no version bump** (1.8 stands).

## Gates

Build; `GOFLAGS=-buildvcs=false dune test --root . --force` (126/126 before this change);
`arch-rules` 4/0; golden regenerated last with every delta attributed; the exception channel on
both external corpora unchanged — this change touches no producer, so any movement there would be
a red flag, not an expected delta.
