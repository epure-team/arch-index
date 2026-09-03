# Validation of the exception channel on three corpora (2026-09-03)

Purpose: check that the may-raise analysis (`docs/exception-raise-sets.md`, PR #54) is not
over-specialised to Tezos. Same binary, same defaults, three unrelated OCaml codebases.

| corpus | nodes | bounded | bounded under `--assume-externals-pure` | origins | handler scopes | call↔scope links |
|---|---|---|---|---|---|---|
| arch-index (whole repo) | 1 765 | 325 (18.4 %) | 784 (44.4 %) | 227 | 106 | 389 |
| trilitech/octez-manager `739d49d4` | 12 317 | 3 024 (24.6 %) | 5 858 (47.6 %) | 765 | 491 | 2 245 |
| Tezos `proto_alpha/lib_protocol` `1727d7e192f` | 14 452 | 3 436 (23.8 %) | 6 705 (46.4 %) | 1 219 | 18 | 35 |

Index + fixpoint: 1.7 s / 0.16 s (octez-manager, 353 modules, 58 553 calls), 3 s / 0.38 s
(proto_alpha), 0.02 s (arch-index). Zero rejected rows on all three.

**The bounded share is stable across the three (18–25 % raw, 44–48 % under the hypothesis)** even
though the codebases share nothing but the language: an application (Bos/Unix/Lwt-free shell
tooling), a protocol (functor-heavy, `tzresult`), and a static-analysis tool (compiler-libs,
Sqlite3). The residual ⊤ is the same two classes everywhere — `external` (callees outside the
index) and `may_top_edge` (calls through parameters/functor arguments) — which is roadmap 3.7's
target, not a Tezos artefact.

**Where the corpora differ is which half of the feature they exercise**, and the difference is the
opposite of over-specialisation:

- `octez-manager` and `arch-index` exercise **handler subtraction** heavily — 491 and 106 `try`
  scopes, 2 245 and 389 call↔scope links — because ordinary OCaml uses `try … with`.
- `proto_alpha` barely does (18 scopes, 35 links): the protocol signals errors as `tzresult`
  values, so its 1 219 origins are almost all implicit (`assert` 585, `compare` 262, `division`
  150, `index` 124) with only 20 literal `raise`s. This is what motivates roadmap item 3.4-bis
  (error channels), and it means Tezos was the *weakest* validation of the user-required rule.

## Spot checks (octez-manager, read against source)

1. `lib/common/cmd_runner.ml:83-99` — nested `try … with End_of_file -> ()` around `input_line`:
   `raises run_blocking` does **not** list `End_of_file` (closed at the call site), keeps a direct
   `Invalid_argument` and one honest `may_top_edge lib/common/cmd_runner.ml:65` (a call through a
   local `let rec loop` binding). ✔
2. `src/ui/metrics.ml:439` — `raise_notrace Not_found`: reported `Not_found | - | direct`,
   proving the primitive-keyed recogniser catches `raise_notrace`, not just `raise`. ✔
3. `src/installer/import.ml:1622-1663` — `raise (Failure …)` inside the lambda passed to
   `List.iteri`, the whole `List.iteri` wrapped in `try … with e ->` (catch-all): `Failure` is
   **absent** from `import_cascade`'s set — the lambda's origin belongs to the lambda node, its
   occurrence edge carries the parent's scope, and the catch-all closes it. This is the user's
   hard requirement (subtraction at the *call site*, lambda attribution) verified on third-party
   code the analysis has never seen. ✔

No answer contradicted the source on any corpus.

---

## Re-validation after the error-channels merge (2026-09-03)

Re-run of the **exception** channel on the two external corpora after merging `origin/main`
(schema 1.6) and landing the error-channels feature. These corpora are the binding gate precisely
because this repository's own counts move whenever code is added to it.

| measure | octez-manager | proto_alpha | vs. baseline |
|---|---|---|---|
| nodes | 12 317 | 14 452 | exact |
| bounded | 3 024 (24.6 %) | 3 436 (23.8 %) | exact |
| bounded under `--assume-externals-pure` | 5 858 (47.6 %) | 6 705 (46.4 %) | exact |
| ⊤ external | 2 834 | 3 273 | exact |
| ⊤ may_top_edge | 6 459 | 7 743 | exact |
| origins | 765 | 1 219 | exact |
| exception-channel scopes | 491 | **19** | +1 on proto_alpha — attributed below |
| exception-channel links | 2 245 | 35 | exact |

Every verdict-bearing number is unchanged. **Count scopes and links with a `channel` filter**: both
tables are now shared with the value channels (octez-manager also holds 1 104 option and 1 063
result scopes), so a channel-blind `SELECT count(*) FROM call_exn_scopes` reads 4 346 rather than
2 245 and looks like a regression when nothing moved.

### The one delta, attributed

`proto_alpha` gains exactly one exception-channel scope: id 258, `catch_all = 1`, on
`Script_repr.force_bytes` at `script_repr.ml:264`, covering **zero** calls. This is the converter
rule doing what it is specified to do — `Error_monad.catch_f` closes the exception channel and
opens `tzresult` — at the only `catch_f` site in all 276 units of `lib_protocol`. It covers no
call because of the documented residual: the guarded thunk becomes its own lambda node and the
scope minted on the enclosing node cannot reach into it. So the scope exists, closes nothing, and
changes no verdict, which is why every other number is identical.

Oracle row O-5 confirms both halves: `may-fail force_bytes --channel tzresult` →
`BOUNDED: {…Script_repr.Lazy_script_decode}` (expected exactly); `--channel exception` → ⊤ with
`external Data_encoding.force_bytes` / `external Error_monad.catch_f` rather than the hoped-for
`BOUNDED: {}` — the residual, not a rule gap.

### Fixed while re-validating: the shipped profile was undiscoverable

`--errors-profile tezos` failed on `proto_alpha` with "no profiles/tezos-errors.toml found". Two
compounding causes: the `<project root>/profiles` candidate is rooted at the **analysed** project
(`/home/mathias/dev/tezos/tezos`), not at arch-index, and the exe-relative fallback was off by one
— `dirname³` of `_build/default/bin/<tool>/<tool>.exe` is `_build/`, not the repository root. The
shipped profile was therefore unreachable in exactly the situation it exists for: analysing an
external corpus. Discovery now walks the executable's ancestors looking for `profiles/`, which
also survives an installed layout. The resolved path is printed on every run.
