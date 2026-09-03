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
