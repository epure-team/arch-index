_Generated: 2026-09-15T16:36:38Z_
_Neutral input; task description intentionally omitted._

1. What identity schemas are currently used for functions, modules, executables, CMT artifacts, and effect records, and where do name-only or path-derived identifiers participate in joins, deduplication, or persistence?
2. How are OCaml effects currently extracted from CMT data, serialized, loaded, associated with functions, and propagated through the indexing pipeline?
3. How does ingestion currently detect and handle duplicate CMT modules within each executable, especially when artifacts share a module name but differ by source path, build path, digest, or executable provenance?
4. Which counters, diagnostics, warnings, and error paths currently record missing effects, unmatched identities, duplicate modules, ambiguous artifacts, skipped records, or failed CMT loads?
5. Which existing tests and fixtures cover function identity, effect extraction and loading, source/build path normalization, duplicate per-executable modules, and non-conflation of same-named artifacts?
6. [ecosystem] What provenance and identity information do current OCaml compiler-libs CMT/CMI artifact formats expose for module names, source paths, compilation units, digests, and typed-tree effect information?
7. [ecosystem] How does the current Dune build system lay out, duplicate, wrap, or transform CMT artifacts across libraries and executables, and which metadata can associate each artifact with its originating source and build target?
