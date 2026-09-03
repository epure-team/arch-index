# Reviewer sub-brief — error-channels

**Status: VALIDATED**
**Normative:** `specs/error-channels.md` (FR-021..034, AC-15..20), `briefs/error-channels-plan.md`.
**Gate: soundness.** Omitting an error a function can return is CRITICAL; over-approximation
(extra elements, ⊤ with a reason) is at most MEDIUM. A handler that "closes" something it does
not catch is CRITICAL.

## What was implemented (expected)

`lib/arch_index/arch_errors_config.ml(i)` (TOML via `otoml`, built-ins, merge, digest, discovery,
validation), `channel` columns + `exn_edges` + version bump, per-channel recording in
`arch_index_exn.ml` + hooks in `arch_index_cmt.ml`, generalised `lib/arch_tools/arch_exn.ml`,
`may-fail`/`fails-with`/`error-stats` in `bin/arch_query`, `profiles/tezos-errors.toml`,
`tezt/tests/error_channels.ml` (two fixture libraries), docs/CHANGELOG/golden.

## Audit first, in this order

1. **`arm_is_closing` for value channels** — the rule is *unguarded ∧ the pattern's bound
   variables do not occur in the RHS*. `Error e -> Error e` and `Error e -> log e; Ok 0` must be
   non-closing; `Error _ -> Error A` closing (and `A` an ordinary origin). Check the occurrence
   test descends into nested lambdas/lets/matches in the RHS.
2. **Head-call-only coverage** — a scope or sink covers the *head* call of the matched/ignored
   expression and its single-`let` alias chain, never nested carrier calls in argument position
   (`match wrap (f ()) with Error … ` must NOT close `f`'s errors). This is the deliberate sound
   direction; verify it is implemented as such and tested (spec US-2 scenario 9).
3. **Carrier check** — reads the local type at the site (probe-confirmed), strips `lift`, matches
   `type`/`underlying`/`aliases`, and handles the alias-arity case (`tzresult[X]` vs
   `result[X; trace<error>]`). No `Ctype.expand_head`, no `Env`. A tyvar error argument ⇒ carrier
   with an empty own set.
4. **`Texp_letop`** — `let_.bop_exp` and each `ands[i].bop_exp` treated as bound expressions,
   `body` as the continuation; both propagate (spec `h`/`h2`). `Lwt_syntax.let*`/`let*!` bind a
   non-carrier ⇒ contribute nothing.
5. **Transforms/converters** — `add` unions the literal argument and marks wrapped; `replace`
   discards the inner set and takes the mapping function's literal returns (⊤ if unknown);
   `converters` close the `from` channel (catch-all, ⊤ included) and open one origin on `to`.
6. **Exception channel frozen** — no row, no query-output, no numeric change on the three corpora.
   This is the regression that matters most; check it before believing any new-channel result.
7. **Validation memory** — the declared-set-with-found-flags design, not a corpus-wide path set.
8. **Config** — merge order built-in < profile < user; digest over the *effective* config; unknown
   key = parse error; per-path miss = warning, carrier-type miss = exit 1, `--errors-strict`
   promotes; precedence of the three profile locations, printed.
9. **Schema** — additive only, `channel DEFAULT 'exception'`, version = base+1 with a unique
   `docs/schema.md` row, `runner.ml` untouched.

## Risks to verify

Propagation model on real code (the octez-manager smoke and the proto_alpha oracle are the
evidence — read the transcripts, do not take "green" on faith); profile portability (unit-component
wildcard); fixture cross-contamination between the two libraries; `otoml` decoding of
array-of-tables; and whether any `NOT_A_CARRIER` is being emitted where a real carrier was meant
(a silent way to under-report).

---

## Addendum — what the implementation actually did (written 2026-09-03, after slices 0–3)

The audit list above was written before any code existed. These are the decisions the
implementers actually took, each of which the review must reach a verdict on. They are recorded
here so the reviewer does not have to reconstruct them from the diff.

### Decisions to accept or reject explicitly

1. **Value-channel scopes reuse `exn_scopes`/`exn_origins` with the `form` column carrying
   channel-dependent meanings** (`'match_exception'`, `'raise'`, `'unknown'` reused for value
   channels; scopes are flat, unparented "point facts" about one call's head, with no lexical
   nesting). Rationale given: the query only reads `form` for `reraise`/`unknown`. **Verify that
   claim by grep** — if anything else ever branches on `form`, this is a latent bug, and even if
   not, judge whether a `kind` column or distinct form values would be worth the migration now
   rather than after a second consumer appears.
2. **Calls to a declared `binds` path are excluded from propagating-edge candidacy** (slice 2,
   deliberately narrow). Without it `Stdlib.Option.bind`'s own external-⊤ status made ordinary
   option-bind code spuriously `UNBOUNDED`. Check this is implemented as "the bind call itself is
   plumbing" and not as "anything named like a bind is ignored".
3. **`head_qualified_name` was widened to also match `Head_local`** (slice 3), because a declared
   path in the same module is indexed under its bare name. Justified as safe "since no existing
   declared path is spelled that way" — **that is an assumption about configs, not about code**.
   Check what happens when a user declares a bare name that collides with a same-module function.
4. **The `replace` transform with a non-lambda mapper always yields ⊤**, rather than resolving a
   named mapper whose set is Known. A deliberate, sound over-approximation — confirm it is
   documented in the spec/doc and not silently narrower than FR-025.
5. **Polymorphic-variant identity is the bare label** (`` `Msg ``), with no unit qualification.
   This is correct OCaml semantics (structural typing), but confirm the query's canonicalisation
   does not accidentally send it through the rebind table.

### Regression found and fixed in-flight — check it cannot recur

`Arch_exn.load` read `exn_origins`/`exn_scopes` **without a channel filter**, so slice-2's new
value-channel rows leaked into the exception channel's results. It was caught only because the
anti-regression gate asserts exact numbers on the two external corpora. **Grep every SQL statement
in `lib/arch_tools/arch_exn.ml` for a missing `channel` predicate**, and check the same class of
bug in `bin/arch_query` and anywhere `exn_edges` is read.

### Environment caveat for whoever re-runs the gates

A sub-agent symlinked `_build` to `/var/tmp`, which silently broke the four tests that search
upward from the build directory for repository files (`curation_doc`, `pcc`); the failures were
then reported as "pre-existing". They were not. If tests fail in those four, check
`ls -ld _build` before believing any diagnosis. With `_build` inside the worktree the suite is
94/94, exit 0.

### Stale-golden caveat

`test/fixtures/self-index-stats.txt` records modules **and functions and calls**: any added code
invalidates it, not just an added module. One slice skipped regenerating it on the wrong
reasoning and left CI red.
