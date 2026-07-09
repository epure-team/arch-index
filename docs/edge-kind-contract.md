# Edge-kind contract & soundness

arch-index tags every `calls` row with a `kind` value that encodes what is statically knowable about the call:

| `calls.kind` | Meaning | Use |
|---|---|---|
| `MUST` | Uniquely-resolved static call | `reaches` (a positive path = must-reach ground truth) |
| `MAY_ENUMERATED` | Dynamic call bounded to a candidate set (e.g. all interface implementers) | Over-approx closure for `unreachable` |
| `MAY_TOP` | Unresolvable / dynamic / reflective / FFI call — **could call anything** | Forces `UNKNOWN`; never silently dropped |

When a backend produces a ⊤-marked index it sets `callgraph_contract = v1` in `comment_db_meta`. Backends that cannot tag edges must not produce a DB at all — the loader aborts on missing or invalid `kind` values (exit 2) to prevent a silent false-confidence index.

### Backends

| Backend | Edge kinds | Notes |
|---|---|---|
| Go SSA (`callgraph-go` → `arch-load`) | ✅ | static callee → `MUST`; CHA candidate set → `MAY_ENUMERATED`; interface/closure/reflection/cgo → `MAY_TOP` |
| OCaml CMT (`arch-callgraph-ocaml`) | ⚠️ partial | direct top-level call → `MUST`; qualified/external → `MUST` leaf; applied parameter/closure or computed head → `MAY_TOP`; named local function passed as a callback → `MAY_ENUMERATED`. Resolution is `Ident`-stamp-based, so a parameter/local that shadows a top-level name is correctly `MAY_TOP` (not a spurious `MUST`). |

**OCaml MUST-soundness is being hardened (execution-sound redesign in progress).** The current
walker still attributes calls inside *un-invoked* nested function/lambda bodies as `MUST` of the
enclosing function (a false `MUST`), and drops a computed-function callback / a first-class-module
parameter call to a `MUST` leaf instead of `MAY_TOP` (a false `UNREACHABLE`). These exact cases are
pinned as `PHASE2` targets in `selftest-callgraph-soundness.sh`; the redesign models nested/lambda
bodies as deferred and links them only when invoked or passed. Until it lands, treat OCaml
`reaches`/`unreachable` as sound for the `PHASE1`-covered cases and best-effort for the rest.

## Reachability semantics

**`reaches A B`** — MUST-only under-approximation.
A positive result (`PATH EXISTS (must-reach)`) is ground truth: there is a definite static call chain from A to B. A negative result does not prove unreachability — dynamic edges may exist.

**`unreachable A B`** — sound over-approximation (requires ⊤-marking).
Returns one of three verdicts:

- `REACHABLE (may-reach)` — B is in the MUST ∪ MAY_ENUMERATED closure of A (not definitely reachable, but plausibly so).
- `UNREACHABLE` — B is outside the full closure AND no MAY_TOP edge is reachable from A. This is a sound negative: the closed-universe assumption holds.
- `UNKNOWN` — A can reach a MAY_TOP edge; the universe is open and the verdict cannot be determined.

**`escapes A`** — lists the MAY_TOP edges reachable from A: the frontier that forces `UNKNOWN`.

## Agents and code-quality enforcement

arch-index makes call-graph reachability answerable as a SQL query. This makes it suitable for use by both AI agents and human reviewers to enforce invariants:

- **Reachability gates**: "does `paymentHandler` reach any `log_plaintext` sink?" → `reaches paymentHandler log_plaintext`. Block a PR if the answer is PATH EXISTS.
- **Attack surface audits**: `arch-query db.sqlite exported` lists every externally-callable function. An agent can cross-reference this against an allowlist.
- **Panic/error-exit reachability**: "is `os.Exit` reachable from `ServeHTTP`?" → `reaches ServeHTTP os.Exit`. Useful for detecting accidental shutdown paths in handlers.
- **Variant analysis**: find all callers of a fixed function to check for siblings: `arch-query db.sqlite callers-of vulnerableHelper`.
- **Documentation quality gate**: every function row carries a `comment_quality_score`. An agent can query `SELECT name FROM functions WHERE comment_quality_score < 50 AND exposed = 1` to find underdocumented public API.
- **Test coverage linking**: `{tests}` sections in doc-comments are parsed and stored. An agent can verify that every exported function has at least one linked test case.

For the formal soundness proof see [SPEC-sound-callgraph.md](../SPEC-sound-callgraph.md).
