# Roster intake — FFI connector registry parser

Implement delivery slice 1 of `specs/ffi-connector-registry.md`: a strict,
standalone JSON reader/validator and test gate. It parses neither source nor
artefact and cannot create graph data. It must reject duplicate JSON keys,
unknown fields, unsafe roots, duplicate IDs and unsupported mechanisms, while
normalizing valid output deterministically.
