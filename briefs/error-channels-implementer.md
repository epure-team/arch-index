# Implementer sub-brief — error-channels

**Status: VALIDATED**
**Read also (normative):** `specs/error-channels.md` (FR-021..034, AC-15..20, CHECK-5..7),
`briefs/error-channels-plan.md` (slices 0–6 + consensus resolutions),
`roster/error-channels/feasibility-probe.md` (settles the two hardest questions),
`roster/error-channels/research.md`, and the merged baseline it generalises:
`lib/arch_index/arch_index_exn.ml(i)`, `lib/arch_tools/arch_exn.ml(i)`,
`specs/exn-raise-sets.md`, `docs/exception-raise-sets.md`.

## Environment

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/31263480-e1a5-4466-ad8a-8603e6671282/scratchpad/wt-exn`, branch `feat/error-channels`, rebased on
`origin/main` (PR #54 merged — the exception channel is **baseline code**, not a stacked branch).
`eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"`; **always** `dune build
--root .` and `dune test --root . --force` (stray `dune-project` files under `/tmp` hijack the
root otherwise). `otoml.1.0.5` is already installed in the switch; still add it to
`dune-project`, `arch-index.opam` and `lib/arch_index/dune`.

## Two facts that shape the design (probe-verified, do not re-litigate)

1. **The error type argument is in the `.cmt`**: a binding's return type prints as
   `…Pervasives.result[?; …Error_monad.trace<…Error_monad.error>]` — head of argument 2 is
   `trace`, whose argument is `error`. The carrier check needs only the raw `Tconstr`; never call
   `Ctype.expand_head` or touch `Env` (the walker deliberately never does — `.cmt`-restored
   environments carry no manifests).
2. **Carrier-ness of a callee is readable at the call site** from the `Texp_apply`'s function
   expression type (`CALLEE_TYPE …Error_monad.tzresult[…]`). So an edge is stamped with its
   channel *at emission*, in the same unit — **no second pass, no cross-unit signature index**.
   The same alias appears in two spellings in one file (`tzresult[X]` with one argument, and
   `Pervasives.result[X; trace<error>]` with two), so `underlying`/`aliases` are mandatory and
   `error_arg` is **not applicable** when the head matches an alias whose arity differs — treat
   the alias's error type as implied by the declaration.

## Steps (see the plan for completion criteria and the ACs each lands)

0. Config: `lib/arch_index/arch_errors_config.ml(i)` + flags + `comment_db_meta`.
1. Schema `channel` columns + `exn_edges` + version bump (**read the base at implement time**,
   minor+1, add the `docs/schema.md` row; the base was `"1.2"` on 2026-09-03 but
   `feat/language-universe` may land first) — producer still emits only `exception`.
2. Spine: `result`/`option` carrier check, origins, scopes, sinks, propagating edges, query.
   **End with the octez-manager smoke** (`~/dev/octez-manager`, built) + three hand checks.
3. Binds (`Texp_letop`: `let_.bop_exp` and each `ands[i].bop_exp` are bound expressions, `body`
   is the continuation — separate traversals), alias chains, transforms (`add`/`replace`),
   converters, `inferred_bind`.
4. `lift`/`unwrap`/`underlying`/`aliases` + `profiles/tezos-errors.toml` (unit-component `*`
   wildcard so one file covers `alpha` and numbered protocols; add a separate channel entry for
   the shell's `Tezos_error_monad.*`) + the proto_alpha oracle run.
5. `NOT_A_CARRIER`, per-channel `NOT_ANALYSED`, `--channel all`, `[summaries]`, `--errors-strict`.
6. Docs, CHANGELOG, golden, and append the error-channel numbers to
   `docs/exception-raise-sets-validation.md`.

## Design constraints (decided; deviate only with a recorded reason)

- **Validation memory**: keep the *declared* path set with found-flags and mark entries as the
  walker meets each path. Never accumulate the corpus's paths (proto_alpha is 73 k calls).
- **Type-variable error argument**: the function *is* a carrier (polymorphic in its errors); its
  own origin set stays empty unless it constructs an error. The carrier **type** path is what
  selects the channel, so `'a option` only ever joins `option`.
- **Exception channel is frozen**: same rows, same query output, byte-identical. The `channel`
  column is never printed by `raises`/`raisers-of`/`exn-stats`. Step 1 must prove this before any
  value-channel code lands.
- **Fixtures**: two libraries in one dune project — `errch_simple` (own `type err = A | B of int`,
  `('a, err) result`, a `Res` module with `bind`/`Syntax.let*`/`map_error`/`value`, plus `option`)
  and `errch_tz` (own `type error = ..`, `'a tz = ('a, error trace) result`, `error`/`tzfail`/
  `record_trace`/`catch`/`let*`), plus the existing two-unit cross-unit case. Keeping them apart
  is deliberate (name cross-contamination was a review objection).
- `runner.ml` stays untouched; schema changes additive only.

## Quality gates

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build --root .
dune test --root . --force
BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe
$BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql
./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail
sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -
git diff origin/main --stat -- lib/arch_index/runner.ml   # must be empty
```
