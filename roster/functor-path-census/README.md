# Functor path census

Internal, reproducible measurement tooling for `unsupported_path` functor
applications. It calls the installed checkout's real functor catalogue and
binding collectors; it does not change resolution behavior or scan beyond the
supplied manifest.

Build the checkout first, then run the native controls:

```sh
opam exec --switch=/home/mathias/dev/arch-index -- \
  node roster/functor-path-census/check.js
```

Run a census with a three-column `slice<TAB>sha256<TAB>absolute-CMT-path`
manifest. The output path must not already exist:

```sh
opam exec --switch=/home/mathias/dev/arch-index -- \
  node roster/functor-path-census/run.js --manifest MANIFEST --out REPORT.json
```

The v1 report retains every binding outcome in local catalogue ordinal order.
An `unsupported_path` row additionally retains the exact recursive `Path.t`,
display text, location, literal-application depth, artifact-local identity
class, root identity/category, and exact-name selected-unit candidates. Display
counts and compiler-identity counts are deliberately separate.

The wrapper validates manifest syntax, uniqueness, readability and hashes both
before and after measurement. Probe compilation and all generated fixture files
live in owned temporary directories. It resolves `arch-index.cmxa` from this
checkout's exact `_build/install/default/lib` staging and records source,
binary, archive, compiler, manifest and input provenance. A failure prints only
a diagnostic and never creates or replaces a success report.

Limitations are part of the report: unit-name presence is inventory, not proof
of declaration ownership; identities never cross decoded artifacts; no CMI is
loaded; and CMT locations are not a source-freshness claim. The encoder handles
both `Pextra_ty` variants, although the native source fixture cannot naturally
exercise those module-head forms.
