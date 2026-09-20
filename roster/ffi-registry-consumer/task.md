# Roster intake — recurring FFI registry consumer

Package a completed `ffi_registry_report` with an explicit corpus/artifact scope
manifest and compare only compatible packages. The consumer must refuse changed
registry digest, report schema, scope, malformed/digest-mismatched report, or
duplicate connector identity. Deltas are descriptive (`new`/`unchanged`/
`absent`), never security, correctness or gate verdicts.
