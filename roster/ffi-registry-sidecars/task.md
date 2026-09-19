# Roster intake — registry-gated FFI sidecars

Add an explicit registry-only adapter over the existing strict OCaml-C and Rust
archive evidence readers. It must carry registry identity, filter source/target/
artefact evidence to that declared scope, preserve refusal/frontier states and
provide no default registry, database mutation or graph result.
