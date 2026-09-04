# Research — qualified-unit-resolution

**Date:** 2026-09-04
**Mode:** full
**Status:** COMPLETED
**Roadmap:** Phase 1, the resolver half of item 1.6 (stable function identity)

## Why this task exists (and why it is a reimplementation)

A prior branch, `rebase/sound-qual`, attacked this same defect and failed review **twice**
(rounds 1 and 2, both NO-GO, both for regressions no automated gate could see). Its round-2
verdict approved a round-3 design: "disambiguate on `cmt_imports` interface digests". Rather
than implement that decision on faith, this research phase tested its premise first.

**The premise is false.** See Finding 3 below. Implementing round 3 as approved would have
produced a third failed round.

The decision taken (with the human, 2026-09-04) is therefore to **reimplement against current
`main`** rather than rebase the old branch: round 3 was a redesign anyway, `main` has since
evolved the same file (`dropped_node`/`top_reason` tracking from roadmap 1.4), and merging two
independently-evolved versions of soundness-critical resolution logic is exactly the failure mode
that produced both prior NO-GOs. The old branch's **test fixtures and check scripts** are worth
porting; its resolver code is not.

## Method

All findings are empirical — real dune projects built with the project's own opam switch, indexed
with the real `arch-callgraph-go`-equivalent OCaml producer
(`bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe`) built from `origin/main@cde3aad`, and
inspected via SQL against the resulting database. No finding here rests on reading code alone.

## Finding 1 — the motivating defect is REAL on current `main`, and it is stamped MUST

Fixture (`scratchpad/qnd3`): two libraries `liba` and `libb`, each owning a module of the **same
basename** `api.ml`; an executable linking both and calling `Liba.Api.run` and `Libb.Api.run`.

```
caller       | callee_name    | kind | resolved_to
app/main.ml  | Liba.Api.run   | MUST | libb/api.ml      <-- WRONG
app/main.ml  | Libb.Api.run   | MUST | libb/api.ml      <-- right, by luck
```

`Liba.Api.run` is attributed to **the wrong library's file**, and the edge is stamped `MUST` —
asserted as proven fact, with no ⊤ marker. Root cause: resolution keys on the capitalised file
basename (`Api`) in a project-wide table with last-writer-wins semantics, so the last `api.ml`
indexed wins for every library. This is the defect behind #41 / #35 / #26 and the roadmap's
"every loader that keys on a bare name is a silent mis-attribution waiting for a homonym".

## Finding 2 — `.cmt` files DO carry imported-unit names with interface digests

Verified with `ocamlobjinfo` on real artifacts. Every `.cmt` carries a `Cmt interfaces imported`
table of `(digest, unit-name)` pairs using the **exact mangled unit names** dune produced:

```
835e041be07f6a6a5bd8bdad4e1a3f35  Arch_index__
e4d240c8cd6cda681271a7613c53360a  Arch_index__Arch_index_db
6f4dc880395f53ea69d84472bdfb71c4  Arch_index__Call_graph_extractor
```

So the prior branch's load-bearing code comment — "a .cmt carries no link information, so nothing
here can say which library the caller was linked against" — is indeed **false**, exactly as the
round-2 review claimed. That much of round 2 is confirmed.

## Finding 3 — but digests do NOT decide the case round 3 was approved to fix (PREMISE DISPROVED)

The round-2 verdict claimed digests "make all three open resolution defects soundly decidable".
Tested directly against the hardest of the three — the *both-readings-live* case.

Fixture (`scratchpad/qnd2`): one wrapped library `foo` containing **both** `bar.ml` (→ unit
`Foo__Bar`) and a main module `foo.ml` whose entire content is `module Bar = Bar` (→ unit `Foo`).
A reference `Foo.Bar.baz` then has two structurally valid readings:

- **(a)** `Foo` is the library wrapper, `Bar` a unit inside it → unit `Foo__Bar`
- **(b)** `Foo` IS the compilation unit, `Bar` a module nested inside that file

Both units exist, so both readings are live. What does the **caller** import?

```
b5573c27bbe5c288f59a8748ab10b3c9  Foo
1a82e98f375fa6e0bbecf5e3211d88a2  Foo__
86c36084e9b18f71a8b7bce26d8d8b93  Foo__Bar
```

**All three.** The caller genuinely depends on `Foo` (to reach the alias) *and* on `Foo__Bar` (the
implementation the alias forwards to). Both are real, recorded dependencies, so the import set
cannot say which reading the reference "means" — the honest answer is that it goes *through* one
to reach the other. Digest disambiguation would have left this case exactly as broken as round 2
left it, while adding a whole new mechanism to maintain.

**This is the single most important result of this research phase**: it kills the approved round-3
design before any code was written.

## Finding 4 — the function table DOES decide it, using data already collected

Indexing the same `qnd2` fixture yields these function rows:

```
app/main.ml    | run
libfoo/bar.ml  | baz
```

There is **no `libfoo/foo.ml | Bar.baz` row**. A module alias (`module Bar = Bar`) defines no
function of its own, so reading (b) has nothing to resolve against, while reading (a) resolves
cleanly. The disambiguator is therefore:

> Evaluate both readings. Look each one up **in the function table with the name it implies**
> (reading (a): `baz` in `libfoo/bar.ml`; reading (b): `Bar.baz` in `libfoo/foo.ml`). Exactly one
> hit → resolve to it. Two hits → a genuine homonym → ⊤. No hits → fall through to the existing
> external/unknown handling.

This needs **no new data source**: `fn_lookup` is already built before call resolution runs. It is
strictly more informative than digests here, and it degrades honestly rather than guessing.

Confirmed: current `main` already answers this fixture correctly (`Foo.Bar.baz` → `MUST` →
`libfoo/bar.ml`). The prior branch **regressed** it to `MAY_TOP`/NULL — which is precisely what
the round-2 review measured repo-wide as MAY_TOP 660 → 875.

## Finding 5 — the residual case with no function name to check

`resolve_module_root` is called from three sites, not one: call resolution, **module-dep
resolution**, and **type-usage resolution**. Findings 3–4's disambiguator needs a referenced
*value name* to look up, which the module-dep site does not have (it resolves a module path alone).
For that site the both-readings ambiguity is not decidable this way, and digests may genuinely help
there (a module dep on a unit the caller never imported is refutable). This is a real open design
question for the spec phase — flagged, not silently ignored, and explicitly NOT assumed solved.

## Finding 6 — environmental: `dune` must always be invoked with `--root .`

Not a product finding, but it explains failures previously misattributed to the environment.
`dune` searches *upward* for its project root; this session's worktrees live under `/tmp`, where
other concurrent sessions leave stray `dune-project` files, so a bare `dune build` silently roots
itself at `/tmp` and then behaves nonsensically ("Leaving directory '/tmp'", scanning unrelated
fixtures, shelling out with a wrong cwd). This is the true root cause of the `callgraph-go` VCS
failure and the `pcc` "blank JSON" failure recorded as "environmental" during the witness-paths
task. **Every dune invocation in this task must pass `--root .`**, and the QA phase should re-check
whether those two tests pass once it does.

## What carries forward from the abandoned branch

Port (low risk, additive, encode real regression scenarios):
- `tezt/tests/qualified_unit_names.ml` fixtures — the tricky shapes, including the two-executable
  `Dune__exe` collision.
- `checks/nested-module-resolution.js` and `checks/no-must-null-regression.js` — but the latter's
  hard-coded `BASELINE = 1975` is a one-machine artifact (round-2 finding) and must be recomputed,
  or better, re-narrowed to "MUST-with-NULL rows whose root resolves to an INDEXED unit", ratcheted
  at 0.

Do NOT port: the resolver implementation, its tri-state, or the digest plan.

## Open questions for intake/spec

1. The module-dep / type-usage sites (Finding 5) — accept ⊤ there, or use digests only there?
2. Does the fix need to change `functions.qualified_name` (the roadmap's own framing of item 1.6),
   or is resolver correctness separable and shippable on its own? Research suggests separable.
3. Peer coupling: session `arch-index-96` reports that exception-channel identity strings and two
   external-corpus validation counts key on qualified-name spelling. Any change here must be
   diffed against those counts and attributed, not absorbed by updating expectations.
