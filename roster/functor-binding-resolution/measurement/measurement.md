# Binder census measurement

This directory contains a standalone OCaml 5.3 compiler-libs census.  It reads
only `Implementation` CMT annotations and reports raw `Tmod_apply` and
`Tmod_apply_unit` syntax.  It has no dependency on product libraries, writes no
database, and performs no target substitution, call-edge creation, or
resolvability decision.

## Reproduction

The captured run is [`run-2026-09-13.tsv`](run-2026-09-13.tsv), against the
410-row manifest with SHA-256
`9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1`.

```bash
measure_tmp=$(mktemp -d /tmp/functor-binding-measurement.XXXXXX)
trap 'rm -rf -- "$measure_tmp"' EXIT
cp roster/functor-binding-resolution/measurement/binder_census.ml \
   roster/functor-binding-resolution/measurement/shadow_fixture.ml "$measure_tmp/"
opam exec --switch=/home/mathias/dev/arch-index -- ocamlfind ocamlc \
  -package compiler-libs.common,unix -linkpkg -o "$measure_tmp/binder_census.exe" \
  "$measure_tmp/binder_census.ml"
"$measure_tmp/binder_census.exe" --manifest \
  roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv
```

Before it calls `Cmt_format.read`, the program hashes every manifest CMT and
fails on a mismatch.  The manifest’s recorded content SHA-256 is
`5eb82c1b042df623688e4310c36b43dfed3282491d586044e79724f7e9953e4c`.
The temp directory is owned by this command and removed by its exit trap;
no compiler output is written beside a repository source.

## Categories and assumptions

For a `Tmod_ident`, the census peels `Path.Pdot`, `Path.Pextra_ty`, and the
left side of `Path.Papply` to find the root `Ident.t`.  It classifies that root
as `persistent_unit`, `named_functor_parameter`, a locally bound module whose
RHS is `structure`, `alias`, `application`, `functor`, or `unpack`, or
`unknown_nonpersistent`.  The binding and parameter maps are reset per CMT,
indexed by `Ident.unique_name`, and confirm lookups with `Ident.same`; visible
spelling is not an identity key.

Other immediate operand forms are `application`, `structure`, `functor`,
`unpack`, or the synthetic unit argument.  Default `Tast_iterator` recursion
visits children, so a nested application is counted once as its own node and
may also be the operand descriptor of its parent.

Top-level and recursive module bindings are registered when the iterator visits
their `module_binding`; `Texp_letmodule` is registered in the expression hook.
This is a single traversal, so a use before its binder has been visited remains
`unknown_nonpersistent`; the census does not infer a forward or external
binding.  Before output, it checks that the total application denominator is
the sum of all per-slice ordinary and unit counters.

These are Typedtree shape/binder observations only.  In particular, a local
`bound_rhs_alias` does not prove its RHS target, and a persistent root does not
prove that a callable target is indexed or resolvable.

## Fixture check

`shadow_fixture.ml` has an outer `A`, an inner shadowing `A`, an alias, and a named
functor parameter. After the copies above, compile and read it in the same
temporary directory before the shell exits:

```bash
opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -bin-annot -c \
  -o "$measure_tmp/shadow_fixture.cmo" "$measure_tmp/shadow_fixture.ml"
"$measure_tmp/binder_census.exe" --cmt "$measure_tmp/shadow_fixture.cmt"
```

The observed fixture
output was: four ordinary applications; heads all
`path:bound_rhs_functor`; arguments two `path:bound_rhs_structure`, one
`path:bound_rhs_alias`, and one `path:named_functor_parameter`.  The
`After_inner = F (A)` use is outside the inner shadow scope and supplies the
second structure category.

`fixture-identity-check.tsv` preserves both the exact passing census and a
temporary name-key mutation. The mutation replaces `Ident.unique_name id` with
`Ident.name id` only in a copied temporary source, compiles it in that same
directory, and is discarded. It changes one outer/inner-`A` argument from
`bound_rhs_structure` to `unknown_nonpersistent`: the retained `Ident.same`
check rejects a same-spelled but different binder. This demonstrates binder
identity separation, not target resolution.

The captured total is 1,275 raw ordinary syntax nodes (zero unit nodes), equal
to the manifest’s 1,275 syntax applications. Its 658 application-headed nodes
and 149 `path:bound_rhs_functor` heads are descriptor counts only; neither is a
resolved target.

Deviation recorded: the first compile command omitted an explicit output path,
so OCaml wrote `binder_census.cmi` and `binder_census.cmo` beside the source.
Their exact paths were verified and removed before the final runs.  All later
compiles use a source copy inside the owned `mktemp` directory.
