# FFI connector registry v1

## Purpose

An FFI connector is a user-selected, versioned proof recipe for one ABI
mechanism. It lets a project name the real build targets, artefact roots and
source anchors that belong to its boundary; it does not let configuration turn
matching strings into a call graph.

The first registry is a sidecar input to the existing FFI evidence readers.
It writes no SQLite row, call edge or reachability verdict. An unresolved FFI
site remains `MAY_TOP(ffi)` in the graph. A future graph integration must have
its own contract and consume only a complete, mechanism-specific chain.

## Why configuration is necessary

OCaml `external` declarations, C stubs, Rust `extern "C"` exports and Java/JNI
bindings have different source forms, linkage rules and callback directions.
Even one language has multiple valid forms. A global spelling heuristic would
either miss project-specific boundaries or join unrelated symbols. The registry
therefore configures *where to look* and *which declared mechanism applies*;
the tool owns proof construction and refusal rules.

## Envelope

The registry is JSON with a closed v1 envelope:

```json
{
  "schema_version": 1,
  "connectors": [
    {
      "id": "tezos-ocaml-c",
      "mechanism": "ocaml_c_primitive",
      "version": 1,
      "source_roots": ["src/lib_protocol"],
      "build_targets": ["src/lib_protocol:protocol"],
      "artifact_roots": ["_build/default/src/lib_protocol"],
      "enabled": true
    }
  ]
}
```

`id` is unique ASCII `[a-z0-9][a-z0-9._-]*`; `version` is a positive integer.
Every path is relative, normalized and must remain below the supplied corpus
root. Duplicate keys, unknown fields, absolute paths, parent traversal, empty
arrays, duplicate IDs and a disabled connector with any claimed result are
errors. A malformed registry is refused, never partially accepted.

The registry is a declared configuration input. Its digest, resolved corpus
root and connector versions are retained in each output envelope. It is not an
attestation that the sources and artefacts match a shipped binary.

## Closed mechanisms

v1 recognizes only these mechanism identifiers:

| Mechanism | Required proof chain | Ceiling |
|---|---|---|
| `ocaml_c_primitive` | OCaml external declaration → `camlprim`/declared primitive → selected Dune target → source mirror → exact symbol in selected object/archive | `RESOLVED_STRICT` sidecar binding |
| `rust_c_archive_endpoint` | selected Rust C-ABI export → selected Dune foreign archive target → source mirror → exact symbol in selected archive | `RUST_ARCHIVE_ENDPOINT` sidecar endpoint |
| `callback_registration` | declared callback type + selected registration anchor + receiver proof defined by a future mechanism version | frontier only in v1 |

The first two map to the existing attested connector readers. Their required
witness vocabulary is fixed by the implementation, not supplied by a user.
`callback_registration` intentionally has no target result in v1: registering a
function-pointer type does not establish its receiver set.

Unknown mechanisms, a connector whose selected target is absent, a missing or
ambiguous symbol, a source/artifact mismatch, ABI mismatch, callback receiver
gap or inaccessible artefact produces a named refusal/frontier status. It is
never converted to zero results or `MUST`.

## Safety boundary

A connector may narrow the corpus to audited inputs. It may not:

- declare a new witness kind or alter a mechanism's required chain;
- attach a source regex/name alias as proof of a binding;
- elevate a result ceiling, a `MAY` relation, or a graph edge to `MUST`;
- follow dynamic loading, arbitrary generated sources or outside-root paths;
- silently reuse a result from a different registry/corpus/artifact digest.

New languages/mechanisms require a new schema-compatible mechanism
implementation, fixtures and Roster review. They are additive: a client that
does not understand one refuses that connector rather than treating it as a
generic FFI match.

## Output and automation

The registry runner returns one versioned JSON envelope with per-connector
status, required/observed witnesses, bounded results, retained frontiers,
diagnostics, input digests and totals. It distinguishes `COMPUTED`,
`NOT_ANALYSED`, `REFUSED` and `FRONTIER`; an empty completed connector is not
the same as a connector that did not run.

CI may publish that envelope as review evidence. A policy gate belongs in an
explicit consumer and must reject a missing/changed registry, corpus or
artifact evidence before comparing results. A new endpoint or a disappearing
frontier is descriptive data, not a security/correctness verdict or automatic
baseline promotion.

## Delivery slices

1. Strict parser/validator and JSON schema fixtures, without a scanner.
2. Adapt the existing OCaml-C and Rust-archive sidecar readers to consume a
   registry and record its identity; preserve their current built-in behavior
   only through an explicit shipped example registry.
3. Add a read-only aggregated registry report and a recurring consumer with
   compatibility refusals.
4. Specify any callback receiver or graph integration separately, after a
   measurable corpus demonstrates a complete proof chain.
