# FFI Stage 5 research

The existing staged readers already deliberately emit JSON envelopes and
digests.  Their correct first integration is a read-only report, not a SQLite
writer: putting endpoint evidence into `calls` would falsely imply that an
OCaml caller invokes the Rust function and would corrupt `arch-query`'s graph
semantics.

The report is therefore the stable interface for users and future connector
configuration.  It names the connector versions, returns all component counts
and treats unavailable build artefacts as `NOT_ANALYSED` rather than an empty
endpoint population.  A later, separately specified graph feature can consume
only a full chain from OCaml anchor through C bridge to a Rust endpoint.
