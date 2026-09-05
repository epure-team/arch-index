# Implementation brief — error-channels

mode: full
branch: `feat/error-channels`, merged up to `origin/main` 2a82b9f
spec: `specs/error-channels.md` (FR-021..034, AC-15..20, CHECK-5..7)
plan: `briefs/error-channels-plan.md` (six vertical slices)

> Written after the fact, at review time: the implement phase ran as direct work plus two
> sub-agents rather than through `/roster-implement`, so no impl brief existed. This records what
> actually landed, from the commits — not what was planned.

## What was built

Configurable **error channels**: the shipped exception analysis generalised to any number of
ways-of-failing, declared in `arch-errors.toml` rather than hardcoded. Built-ins `exception`,
`result`, `option`; a shipped Tezos profile adds `tzresult`/`tzoption`.

## Files and their role

| File | Role |
|---|---|
| `lib/arch_index/arch_errors_config.ml(i)` | channel records, built-ins, TOML decode via `otoml`, merge (built-in < profile < user), digest, wildcard `path_matches`, declared-set-with-found-flags validation |
| `lib/arch_index/arch_index_errch.ml(i)` | carrier check at the call site, constructor + polymorphic-variant canonicalisation, value-channel closing rule, `bind_shape_channel`, lift/unwrap stripping |
| `lib/arch_index/arch_index_cmt.ml(i)` | walker hooks: per-channel origins, scopes, propagating edges, transforms, converters, sinks, alias chains |
| `lib/arch_index/arch_index.ml(i)` | config discovery/precedence, `error_*` meta keys, `discover_profile` |
| `lib/arch_index/arch_index_db.ml(i)` | `channel` params, `insert_exn_edge`, `insert_channel_carrier`, `current_schema_version` |
| `lib/arch_tools/arch_exn.ml(i)` | channel-generic solver, `summaries`, built-in Stdlib table (opt-in) |
| `bin/arch_query/arch_query.ml` | `may-fail`, `fails-with`, `error-stats`, `--channel all` |
| `architecture-schema.sql` | `channel` columns (`DEFAULT 'exception'`), `exn_edges`, `channel_carriers` — additive only |
| `profiles/tezos-errors.toml` | shipped profile, built from the verified 276-unit inventory |
| `tezt/tests/error_channels.ml` | scenarios for AC-15..18 |
| `docs/error-channels.md`, `docs/error-channels-porting.md`, `README.md`, `CHANGELOG.md` | user guide, adapter contract, entry points |

## Decisions taken during implementation

These are the five the reviewer brief's addendum asks the review to adjudicate, plus two later
ones. Each is a judgment call, not a forced move:

1. **Value-channel scopes reuse `exn_scopes`/`exn_origins`**, with `form` carrying
   channel-dependent meanings and scopes kept flat (unparented point-facts about one call's head).
   Claimed safe because the query reads `form` only for `reraise`/`unknown`.
2. **Calls to a declared `binds` path are excluded from propagating-edge candidacy** — the bind
   call is plumbing; without this, `Stdlib.Option.bind`'s own external-⊤ made ordinary option code
   spuriously `UNBOUNDED`.
3. **`head_qualified_name` widened to also match `Head_local`**, because a declared path in the
   same module is indexed under its bare name. Justified by an assumption about configs, not code.
4. **A `replace` transform with a non-lambda mapper yields ⊤** rather than resolving a named
   mapper's set. Deliberate sound over-approximation.
5. **Polymorphic-variant identity is the bare label** (`` `Msg ``) — correct OCaml structural
   semantics, no unit qualification.
6. **`[summaries]` is unconditional once configured; the built-in Stdlib table is opt-in**
   (`--builtin-summaries`), specifically so the frozen anti-regression numbers stay frozen.
7. **Channel selection is first-match-wins over carrier types**, which makes the profile's
   `tzoption` structurally unreachable behind the built-in `option`.

## Defects found and fixed in-flight

- `Arch_exn.load` read `exn_origins`/`exn_scopes` **without a channel filter**, leaking
  value-channel rows into exception-channel results. Caught only by the exact-number gate on the
  external corpora.
- A bogus `--errors-config` path crashed with an uncaught `Sys_error` (exit 125) instead of the
  clean exit 1 every other config failure gives.
- **The shipped profile was undiscoverable on any external corpus** — `<project root>/profiles` is
  rooted at the *analysed* project, and the exe-relative fallback was off by one (`dirname³` of
  `_build/default/bin/<tool>/<tool>.exe` is `_build/`). Discovery now walks the executable's
  ancestors. Found by re-running the validation rather than trusting a reported "exit 0".
- Schema version collision: `1.3` was taken by #55 mid-flight; merged `origin/main` and renumbered
  to `1.6` (base 1.5 + 1).

## Known residuals (documented in `docs/error-channels.md` §6)

`replace` with a non-lambda mapper → ⊤; `catch_f` converters close the exception channel only
within the same CFG node (O-5's exception side is ⊤, not `BOUNDED: {}`); `tzoption` unreachable;
point-free re-exports (`let f = M.g`) record no call edge so O-7 has no set (pre-existing
call-graph gap); `arch-coverage-matrix` has no `error_channels` row.

## Gates as last run

- `dune build --root .` exit 0
- `dune test --root . --force` 110/110 exit 0
- `arch-rules … --on-vacuous fail` exit 0 — **1 proved / 0 violations / 3 UNKNOWN**. Recorded here as "4 rules, 0 failing", which was the tool's own summary reporting a three-state verdict as one number; corrected in PR #70. Nothing was proved for three of the four rules.
- self-index golden re-measured: 23 modules / 733 functions / 4834 calls
- exception channel re-verified post-merge on both external corpora: every verdict-bearing number
  identical to `docs/exception-raise-sets-validation.md`; one attributed delta (proto_alpha
  exception scopes 18 → 19, the converter's catch-all at `script_repr.ml:264`, `catch_all=1`,
  zero links, no verdict change)

## Ratchet

No ratcheted checks declared this round — no HIGH+ finding has yet survived a loop-back.
