# FFI build attribution v1

The Stage-2 reader consumes the Stage-1 candidate inventory and direct Dune
source declarations. It emits target stanzas with path and start line plus
candidate associations. It supports only `library`, `executable`, `executables`
and `test` stanzas and reads `name`, `public_name`, `foreign_stubs` and
`libraries` fields.

For every candidate, `ATTRIBUTED` means one or more target stanzas occur in its
exact source directory; `UNATTRIBUTED` is a successful, explicit result. A C
candidate whose basename appears in a C `foreign_stubs.names` list gets
`foreign_stub_source`; every other same-directory association gets
`same_dune_directory`.

Neither association is a symbol, ABI, object-file or linker claim. Rust
dependency target records explicitly say that they are not Rust symbol links.
Malformed/unreadable Dune forms contribute no target rather than an inferred
one. Output remains deterministic and contains no timestamp.
