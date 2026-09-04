# QA scope — reexport-resolution

**Status: VALIDATED**

## Gates

```
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
dune build
dune runtest --force
```

Never `dune exec tezt/tests/main.exe`.

## Behaviours to validate

| # | Behaviour | Expected |
|---|---|---|
| CHECK-1 | Two files, `module S = <different target>` each, both calling `S.f` | Each resolves to its own target; `callee_id` differs |
| CHECK-1b | Same pair, file processing order reversed | Byte-identical result |
| CHECK-1c | Alias used from inside a nested submodule | Resolves |
| CHECK-2 | Alias target's basename is shared by two modules | `callee_id IS NULL`, ambiguity counter +1, **no** candidate chosen |
| CHECK-3 | `SELECT count(*) FROM calls WHERE callee_id IS NOT NULL AND kind …` | Per the spec's stated invariant; `kind` distribution unchanged by the chase |
| CHECK-4 | Bounded-node counts per channel, both corpora, before and after | Reported; **judge the work by bounded nodes, not by ⊤ rate** — ⊤ is absorbing, so a large ⊤ reduction can bound almost nothing |
| CHECK-5 | Resolved + four decline outcomes | Sums to total fallback attempts, both corpora |
| S3 | Final hop lands on a dropped unit | `MAY_TOP` / `dropped_node`, not a no-candidate decline |

## Measurement protocol — non-negotiable ordering

1. **A=A first.** Run the pre-change binary twice against the same corpus and confirm
   identical output. `mod_name_to_path` is built with `Hashtbl.replace` over an unordered
   `SELECT`, so the baseline can legitimately differ run to run. Until A=A holds, an A≠B is
   uninterpretable.
2. Then the 2×2 (A/B pre-change, C/D post-change), both corpora.
3. The ratchet (`must_null_ceiling` / `clean_measured`) is updated **only** when A=B and C=D.

## Retarget audit

Diff `calls.callee_id` before/after on octez-manager and proto_alpha; list every changed
target. This is a **hard stop for human review**, not an automated revert — the FK a retarget
corrects was already wrong under last-writer-wins, so a change here is as likely to be a fix
as a regression, and only a reader can tell which.
