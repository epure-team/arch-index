# OCaml signature/implementation UID layering

This is a narrow compiler-evidence rule, not a name fallback or an expansion of
the product's supported aliases. An occurrence `val_uid` may differ from its
shape-resolved alias UID only when the same CMT proves all of the following:

- `val_uid` names exactly one `Typedtree.Value` signature declaration, with the
  same leaf name and an arrow type, and names no concrete value binding;
- the located occurrence has exactly one plain `Shape_reduce.Resolved` result
  naming the concrete alias `Value_binding` (never `Resolved_alias`);
- the alias remains one bare local `Pident`, and its Ident, UID, RHS and actual
  syntactic function body evidence all agree as before.

Any competing concrete binding, missing/foreign declaration, wrong name/type,
ambiguous shape result or alias/body disagreement still refuses.

## Native source evidence

In `src/proto_alpha/lib_protocol/sc_rollup_wasm.ml`, the constrained module
signature declares `Syntax.( let* )` at line 200. Its CMT declaration table maps
UID `.114` to `Typedtree.Value`; the implementation alias at line 219 is
`Value_binding` `.98`, and its bare `bind` RHS/body at lines 213–216 is `.92`.
The affected letop occurrences carry value UID `.114` and uniquely resolve by
shape to `.98`.

In `src/proto_alpha/lib_protocol/sc_rollup_arith.ml`, the corresponding signature
declaration is line 217 (`Typedtree.Value` `.198`), the implementation alias is
line 240 (`Value_binding` `.133`), and the `bind` body is lines 234–237
(`Value_binding` `.126`).

OCaml 5.3 defines these as distinct declaration classes in
`compiler-libs/typedtree.mli`: `item_declaration` contains both `Value` and
`Value_binding`. Therefore the differing UIDs above do not constitute two
competing body endpoints. The exception is admitted only with the declaration
table proof recorded by the native probe.
