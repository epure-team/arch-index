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
