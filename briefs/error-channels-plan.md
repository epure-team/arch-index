# Plan — error-channels

**Date:** 2026-09-03
**Status: VALIDATED**
_(autonomous: quiz and final gate recorded as pre-approved per the user's instruction. Every
DISAGREE was settled by a reachability probe, not by argument — see
`roster/error-channels/feasibility-probe.md`.)_

## Sequential steps (vertical slices)

0. **Config plumbing, end to end.** `otoml` in `dune-project`/`arch-index.opam`/`lib/arch_index/dune`;
   new `lib/arch_index/arch_errors_config.ml(+.mli)` (built-ins `exception`/`result`/`option`,
   TOML parse, merge order built-in < profile < user, digest of the *effective* config,
   discovery + precedence, `--errors-config`/`--errors-profile`/`--errors-strict` on
   `arch_callgraph_ocaml`), validation harness wired to a `Paths_seen` collector, and the three
   `comment_db_meta` keys. **Done when:** no-config run stamps
   `error_contract = "v1:exception,result,option"`; a bogus `--errors-config` path exits 1; a
   channel whose carrier type is unseen exits 1; digest stable across reformatting.
   **Lands:** FR-021..024, AC-15 (1,3,5,6).
1. **Schema + re-tag, no behaviour change.** `channel` columns (`DEFAULT 'exception'`) on
   `exn_origins`/`exn_scopes`, new `exn_edges(call_id, channel, role)`, `current_schema_version`
   = base+1 with its `docs/schema.md` row. Producer still emits only `exception` rows.
   **Done when:** `exn_raise_sets.ml` green **unchanged**, self-index golden diff empty, the
   three-corpus numbers of `docs/exception-raise-sets-validation.md` reproduce exactly.
   **Lands:** FR-029, FR-034, AC-17, AC-20, CHECK-6. *Early on purpose — highest blast radius.*
2. **Spine slice: `result`/`option`, monomorphic.** Carrier check (probe-confirmed: read the
   callee/binding type at the site, strip `lift`, match `type`/`underlying`/`aliases`, check the
   `error_arg` head), literal origins, `match … Error p ->` scopes with the closing-arm rule,
   plain propagating edges, sinks; `may-fail`/`fails-with`/`error-stats --channel result|option`
   through `Arch_exn` generalised by channel. **Done when:** AC-16 scenarios 1–6, 10 green, and
   the **early real-corpus smoke** below is clean. **Lands:** FR-025 (partial), 026, 027, 030.
2b. **Polymorphic-variant errors (inserted 2026-09-03 after the slice-2 smoke).** `Texp_variant`
   origins and `Tpat_variant` handler arms, identity = the bare label. Cheap, and without it the
   `result` channel is ⊤ on ~85 % of octez-manager's error sites (394 `Error \`X` vs 71 ordinary).
   **Done when:** the three smoke functions (`run_out_silent_blocking`, `run_out_silent`,
   `download_file`) report `` `Msg `` instead of ⊤ `unknown_error_value`, and their sources agree.
3. **Binds, transforms, converters, alias chains.** `Texp_letop`: walk `let_.bop_exp` (bound
   expression) and each `and*` separately from `body` (continuation) — structurally explicit, no
   ambiguity; `Res.bind`-style applications; single-`let` alias chains; `transforms.mode`
   add/replace; `converters`; `inferred_bind` ⊤. **Done when:** AC-16 5,7,8,13.
   **Lands:** FR-025 (rest), FR-028.
4. **`lift`/`unwrap`/`underlying`/`aliases` + the Tezos profile.** Then `proto_alpha` with
   `--errors-profile tezos` against the **pre-written oracle**. **Done when:** AC-16 9,11,12 on
   the fixture and AC-19 on proto_alpha. **Lands:** FR-027 (full), FR-033, US-4.
5. **Query completeness + summaries.** `NOT_A_CARRIER`, per-channel `NOT_ANALYSED`,
   `--channel all`, `[summaries]`, strict mode. **Lands:** FR-023 (strict), 030–032, AC-15/18.
6. **Docs, CHANGELOG, golden, three-corpus re-validation.** Extend
   `docs/exception-raise-sets.md` (or new `docs/error-channels.md`), CHANGELOG, regenerate the
   golden, append the error-channel numbers to `docs/exception-raise-sets-validation.md`.

**Early real-corpus smoke (adopted from Voice 1's HIGH/HIGH risk):** at the *end of step 2*, run
the `result` channel over `~/dev/octez-manager` (built, 480 `.cmt`, ordinary `result` idiom) and
hand-check three answers. This surfaces a wrong propagation model six slices before the
proto_alpha oracle would.

## Dependencies

0 → 1 (version read) → 2 (spine) → {3, 4} → 5 → 6. Steps 3 and 4 are independent of each other;
do 3 first (cheaper, and 4's fixture reuses its binds).

## Consensus Table

| Point | Voice 1 (architect) | Voice 2 (skeptic) | Status |
|---|---|---|---|
| Vertical slices, schema re-tag early | ✅ | — | AGREE |
| **Cross-unit carrier knowledge is circular / needs a 2-pass index** | ⚠️ | ⚠️ (#3, "largest hidden architecture change") | **RESOLVED BY PROBE — REFUTED.** The callee's type is on the `Texp_apply`'s function expression: `CALLEE_TYPE …Error_monad.tzresult[…]`, `…Pervasives.result[unit; trace<error>]`. Carrier-ness is a *local* property of the edge, stamped at emission. No second pass, no signature index. |
| **Is the error type argument even in the `.cmt`?** | ⚠️ (assumption) | ⚠️ (#1) | **RESOLVED BY PROBE — PRESENT.** `result[?; trace<error>]`: head of arg 2 is `trace`, its arg is `error`; `unwrap` handles it with the raw `Tconstr`, no `Ctype.expand_head`. |
| Type-variable error arg over-fires (C-8) | — | ⚠️ (#1 tail) | **AGREE, amended.** A tyvar in the error position means the function is *polymorphic in its errors*: it is a carrier, but contributes only what flows through it (its own origin set is empty unless it constructs one). The carrier *type* path (`result`/`tzresult`) is what selects the channel, so `'a option` only ever joins the `option` channel — intended, not over-firing. Recorded in the implementer brief. |
| `Texp_letop` bound-expr vs continuation | ⚠️ | ⚠️ (#2, "asserted solved, isn't") | **AGREE — new traversal, but unambiguous.** `let_.bop_exp` and each `ands[i].bop_exp` are the bound expressions; `body` is the continuation. Step 3 owns it; scenario `h`/`h2` is its test. |
| Corpus-wide "paths seen" set memory | — | ⚠️ (#5, unbounded) | **AGREE, design fixed.** Do not store the corpus: keep the *declared* set (tens of entries) with a found-flag, and mark entries as the walker meets each path — O(declared), not O(corpus). |
| Profile is single-protocol (alpha/V17) | — | ⚠️ (#6) | **AGREE.** Profile paths accept a `*` wildcard in the unit component (`Tezos_protocol_environment_*.Error_monad.error`) so one file covers `alpha` and numbered protocols; the shell's `Tezos_error_monad.*` gets its own channel entry in the same profile. |
| `otoml` vs the pinned switch | — | ⚠️ (#7) | **RESOLVED — already installed** in the project switch (`otoml.1.0.5`, `menhirLib`+`uutf`) before planning; `dune build` green after. |
| "byte-identical" under shared schema | — | ⚠️ (#4) | **AGREE — that is what step 1 and the three-corpus re-run are for**; the exception channel must reproduce the recorded numbers, not merely pass its tezt. |
| One fixture library mixing three monads | — | ⚠️ (#8, cross-contamination) | **AGREE.** Split: `errch_simple` (result/option, own `err` variant) and `errch_tz` (own `type error = ..`, `let*`, `record_trace`, `catch`) as two libraries in one dune project, plus the existing two-unit cross-unit case. |
| Oracle mismatch found only at step 4 | ⚠️ (HIGH/HIGH) | ⚠️ (#8 tail) | **AGREE — early octez-manager smoke at end of step 2.** |
| Schema-version race | ⚠️ | — | AGREE — the rule (base+1 at implement time, uniqueness checked in QA) already covers it; no polling. |

No DISAGREE, no USER-CHALLENGE.

## Identified risks

| Risk | P | I | Mitigation |
|---|---|---|---|
| Propagation model wrong on real code | M | H | octez-manager smoke at end of step 2; proto_alpha oracle at step 4 |
| Exception channel regresses under the shared, genericised core | M | H | step 1 re-tag with zero behaviour change; three-corpus numbers re-asserted in QA |
| `otoml` array-of-tables needs hand-rolled decoding | M | L | decode explicitly (no ppx); unknown key = parse error is a hand-written check anyway |
| Profile rots per protocol version | M | M | unit-component wildcard; QA runs the profile on proto_alpha only, residual documented |
| Schema-version collision | M | M | read base at implement time; QA asserts base+1 and history-row uniqueness |
| Fixture passes, real corpus fails (abstraction barriers, aliases) | M | M | two fixture libraries + two real corpora |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| Carrier detection | at the call/binding site from the local type | probe: cross-unit info not needed |
| Validation set | declared-set with found flags | O(declared) memory, kills the scale objection |
| Profile portability | `*` wildcard in the unit component + a shell `Tezos_error_monad` channel | one profile, many protocols |
| Fixture | two libraries (`errch_simple`, `errch_tz`) | avoid name cross-contamination |
| Smoke corpus | octez-manager after the spine slice | ordinary `result` idiom, already built |

## Assumptions

- `otoml` 1.0.5's API is adequate for nested tables + array-of-tables (to be confirmed in step 0;
  fallback is a hand-written decoder over `Otoml.value`, no new dependency).
- The walker's existing `Texp_ident`/`Tconstr` visits cover every path a declaration can name;
  step 0 adds the collector and step 4's profile run is the real test of that.
