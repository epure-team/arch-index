# Research — implementable sidecar boundary

PR125 published the exact parsed impact input; PR126 published shared index
provenance without querying report-only tables on flat schemas. This runner can
therefore reject scope drift instead of comparing an arbitrary pair of Git
briefs. It must still require a user-supplied corpus/configuration manifest:
neither SQLite metadata nor a local DB path proves source identity.

The existing `analysis-report-consumer.js` gives the hardened package pattern:
new output directory, copied raw input, canonical scope, delta, diagnostics,
final hashes, and error packages that never publish a delta. Reuse that shape,
but do not reuse its API identity contract.

MUST plus MAY_ENUMERATED is a bounded *possible* cone. TOP is not enumerable
forward, so only the observed `top_frontier` holders can be compared; their
absence cannot mean no hidden target. A decision finding is valid only under
the identical parsed changed-line map, hence input scope is a compatibility
precondition rather than a delta field.
