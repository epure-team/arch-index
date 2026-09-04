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
result scopes), so a channel-blind `SELECT count(*) FROM call_exn_scopes` reads 4 386 rather than
2 245 and looks like a regression when nothing moved:

```sql
SELECT count(*) FROM call_exn_scopes l JOIN exn_scopes s ON s.id = l.scope_id
 WHERE s.channel = 'exception';
```

The channel-blind octez-manager figure was **4 346** before review round 2 and is **4 386** after,
which is not drift: `call_exn_scopes` used to key on `call_id` alone, so a call site covered by
both an exception scope and a value-channel scope could store only one link and the value-channel
one was discarded. With `PRIMARY KEY (call_id, scope_id)` both are stored, and exactly **40**
octez-manager call sites carry two — 4 346 + 40 = 4 386. On `proto_alpha` no call site carries
two, so its blind figure stays **487**. The `channel = 'exception'` counts in the table above
(2 245 and 35) are byte-identical either way, which is the point: the recovered links are all
value-channel ones.

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

---

## Re-validated after qualified-unit resolution (roadmap 1.6, 2026-09-04)

Gate G-2 of `specs/qualified-unit-resolution.md` §8: any movement in the numbers above is
attributed here; the expected values themselves are never edited. Both corpora were re-measured
with the pre-change binary FIRST, and both reproduced the table above to the digit before any
delta was read — octez-manager 12 317 nodes / 58 553 calls / 353 modules, proto_alpha 468 modules /
14 452 functions / 73 588 calls, bounded 3 436 (23.8 %), tzresult 585/2 137 (27.4 %).

**Nothing in the table above moves**, with one clarification the first version of this appendix
owed and did not pay: the table above is the EXCEPTION channel, and this change moves the
**tzresult** channel too. That movement is recorded in §"The second channel" below rather than
left out because the table does not mention it. The exception channel's own inputs are bit-identical on both
corpora — octez-manager 491 scopes / 2 245 links / 18 758 origins / 31 identities / 1 158
`exn_edges`, proto_alpha 19 scopes / 35 links / 11 exception identities / 377 tzresult identities /
6 `exn_rebinds` **content-identical, not merely equal in count**. That is the expected result:
identities come from `Arch_index_exn.canonical_path ~unit_declared ~cmt_modname`, computed in the
cmt pass, which never consults the resolver this change touches.

Read the counts above with their scope attached, because two of them are channel-filtered and two
are not: octez-manager's 491 scopes and 2 245 links are `WHERE channel='exception'`, while its
18 758 origins and 31 identities are **all channels** (its exception-channel identity count is 6).
The "1 of 31" headline below is therefore an exception-channel numerator over an all-channel
denominator; as a like-for-like it is 1 of 6. `exn_scopes`/`call_exn_scopes` have been shared
across channels since #60, and a channel-blind link count reads 4 386 on octez-manager against
2 245 filtered.

What moves is **which functions a `fails-with` query returns**, because raise sets propagate along
`calls` edges and this change moves where some calls resolve to.

| corpus | identities moved | removed | added |
|---|---|---|---|
| octez-manager | 1 of 31 (`Invalid_argument` 2 439 → 2 520) | **0** | 81 |
| proto_alpha | 3 of 11 (`Assert_failure` +31, `Division_by_zero` +35, `Invalid_argument` +35) | **0** | 101 |

**Zero removals on either corpus.** No function stopped being reported as possibly raising
anything. Every movement is a false negative corrected.

### Why, read against the source

`octez-manager` has two `snapshots.ml` — `src/snapshots.ml` (library `octez_manager_lib`) and
`src/ui/pages/snapshots.ml`. Resolution keyed the capitalised basename in a last-writer-wins table,
so `Octez_manager_lib.Snapshots.slug_of_network` resolved to **nothing** and was emitted as an
external leaf:

```
before  network_short: UNBOUNDED (⊤): {}
        reason: external Octez_manager_lib.Snapshots.slug_of_network
after   network_short: UNBOUNDED (⊤): {Invalid_argument}
        Invalid_argument | slug_of_network | transitive
        reason: external Stdlib.String.sub, …
```

`src/snapshots.ml:64 slug_of_network` → `strip_date_suffix` → `String.sub` ⇒ `Invalid_argument`,
confirmed at source. The callee was in the index the whole time and was reported as outside it.

### The second channel — proto_alpha's `tzresult`

Undisclosed in the first version of this appendix, which discussed only the exception channel
while G-2 asks for *any* movement. Found by review, not by me.

| metric | before | after |
|---|---|---|
| bounded | 585 / 2 137 (27.4 %) | **581 / 2 137 (27.2 %)** |
| identities whose answer set moved | — | **41 of 377** |
| members added | — | **1 435** |
| members removed | — | **0** |

Same shape and same direction as the exception channel: `tzresult` sets propagate along the same
`calls` edges, so re-attributing an edge moves them too, and nothing stopped being reported. The
four nodes that lost `bounded` had **empty** bounded sets — that is what zero removals across all
377 identities means — so no function that named a `tzresult` error stopped naming it. I did not
enumerate those four individually: `arch-query` exposes no per-node bounded listing, and inferring
them from a closure the way the exception channel's three were identified would be a guess dressed
as a measurement.

### The one place precision is lost, and its exact cost

`proto_alpha` bounded goes **3 436 → 3 433** on the exception channel. Three nodes, all in
`lib_protocol/test/helpers/script_big_map.ml`, whose line 8 is

```ocaml
let update k v m ctxt = Protocol.Script_big_map.update ctxt k v m
```

Both the protocol's `Script_big_map` and the helper's own answer to that segment and both define
`update`, so the reference is genuinely ambiguous and degrades to `MAY_TOP` /
`top_reason='ambiguous_unit'` rather than being guessed. The previous behaviour "resolved" it to
the helper itself — a self-recursive call that does not exist in the source.

The three are identified by two independent measurements agreeing: the transitive caller closure of
the newly-⊤ node is exactly `{update, of_list, of_list.<fun:12:5>}`, and the bounded count fell by
exactly 3. **No node with a non-empty bounded set lost boundedness** — that is what the zero
removals above mean — so nothing that named an exception stopped naming it.

### What the same change corrected in the other direction

Three `proto_alpha` call sites were resolving **production protocol code to a test helper** of the
same basename, the first stamped `MUST`, i.e. asserted as proof:

| call site | was | now |
|---|---|---|
| `lib_protocol/script_interpreter.ml:842` | `test/helpers/script_big_map.ml:8` (MUST) | `lib_protocol/script_big_map.ml:90` |
| `lib_protocol/clst_contract_storage.ml:93` | same (MUST) | same |
| `lib_protocol/clst_contract_storage.ml:247` | same (MAY_ENUMERATED) | same |

Edge accounting, classified rather than diffed — a set diff counts a re-target as one loss plus
one gain, which reads as a regression it is not:

| corpus | unchanged | NULL → resolved | resolved → NULL | re-targeted |
|---|---|---|---|---|
| octez-manager | 58 477 | 76 | **0** | 0 |
| proto_alpha | 73 514 | 70 | **1** | 3 (the three rows above) |

Classification is by `calls.id`, joined across the two databases. Keying on
`(caller, callee_name, call_site, kind)` instead — as a first pass here did — silently drops every
row whose `kind` changed, which is exactly how that single proto_alpha loss was first reported as
zero. It is call id 37255,
`test/helpers/script_big_map.ml:update` → `Tezos_protocol_alpha.Protocol.Script_big_map.update`:
`MUST` onto the helper's own `update` before, `MAY_TOP`/`ambiguous_unit` now. The loss is the
desirable half of the same correction as the three re-targets — the previous answer was a
self-recursive call that does not exist in the source — but a stated zero that is really one is a
number a reader cannot check against, so it is corrected rather than explained away.

Same class, also corrected: `Tezos_dal_alpha.RPC_directory.directory`, attributed to
`lib_sc_rollup_node/RPC_directory.ml` and now landing in `lib_dal/RPC_directory.ml`.

A `MUST` edge from the Michelson interpreter into test scaffolding is the defect this roadmap item
exists to remove, and it was present on the protocol corpus, not only on a fixture.
