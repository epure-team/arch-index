(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Architecture index generator.

    Scans [.cmt]/[.cmti] files produced by dune build and populates an SQLite
    database with modules, functions, types, call graph, module dependencies,
    and type usage information. *)

(** Result of an indexing run. *)
type result = {
  n_modules : int;
  n_functions : int;
  n_types : int;
  n_fields : int;
  n_constructors : int;
  n_calls : int;
  n_calls_resolved : int;
  n_deps : int;
  n_deps_resolved : int;
  n_type_usages : int;
  n_type_usages_resolved : int;
  db_path : string;
}

(** [run ~build_dir ()] scans the given build directory for [.cmt]/[.cmti]
    files and indexes them into an SQLite database.

    @param db_path Path to the SQLite database (default: from ARCH_DB_PATH env
      or [docs/architecture.db])
    @param schema_path Path to the SQL schema file (default: from
      ARCH_SCHEMA_PATH env or [docs/architecture-schema.sql])
    @param build_dir Directory to scan (e.g., [_build/default])
    @return Statistics about what was indexed

    {pre}
    [build_dir] must contain [.cmt]/[.cmti] files produced by a prior [dune build].

    {post}
    Returns a [result] record with counts of indexed modules, functions, types, calls, deps, and type usages.

    {violators}
    (none)

    {violates}
    (none) *)
val run :
  ?db_path:string -> ?schema_path:string -> build_dir:string -> unit -> result

(** [run_lsp ~sw ~env ~project_dir ~language ~output ()] runs the LSP-based
    arch_index pipeline, writing a [comment_db] SQLite file to [output].

    @param language Language to use ("auto" for auto-detection, or "ocaml",
      "typescript", "rust", "go", "python")
    @param output Path to write the output SQLite file (written atomically)
    @param no_enrich Skip language enrichment (CMT / ts-morph)
    @param verbose Log progress to stderr

    {pre}
    [project_dir] must be an absolute path to the project root.

    {post}
    On success, [output] is a valid SQLite file with [comment_db_meta.schema_version=1].
    On LSP failure or timeout, returns [Ok ()] with an empty symbol set.
    Output path is written atomically — no partial file exists on failure.

    {violators}
    (none)

    {violates}
    (none) *)
val run_lsp :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  project_dir:string ->
  language:string ->
  output:string ->
  ?no_enrich:bool ->
  ?verbose:bool ->
  unit ->
  (unit, string) Stdlib.result

(** LSP subprocess manager.
    See {!Lsp_client} for the full API. *)
module Lsp_client = Lsp_client

(** LSP wire types, re-exported so consumers can pin the protocol's own
    numbering rather than this library's behaviour.

    The [SymbolKind] table this exposes was transposed once — 6 mapped to
    [Property] instead of [Method], 13 to [Property] instead of [Variable] —
    and the indexer silently produced zero OCaml functions for four months as a
    result: top-level [let]s are kind 13, which the wrong table filtered out.
    TypeScript kept working by accident, since its functions are kind 12 and
    landed on another accepted kind. A test asserting the numbering against the
    LSP specification is the only thing that catches this class of defect, and
    it cannot be written against an unexported module. *)
module Lsp_types = Lsp_types

(** OCaml CMT-based enrichment pass.
    See {!Ocaml_enricher} for the full API. *)
module Ocaml_enricher = Ocaml_enricher

(** Comment quality tag parser (JSDoc and OCaml syntax).
    See {!Comment_parser} for the full API. *)
module Comment_parser = Comment_parser

(** Language → LSP server configuration registry.
    See {!Language_registry} for the full API. *)
module Language_registry = Language_registry

(** Function body comparison across modules.
    See {!Arch_index_compare} for the full API. *)
module Arch_index_compare = Arch_index_compare

(** Cross-commit OCaml function body extraction and move verification.
    See {!Arch_index_git} for the full API. *)
module Arch_index_git = Arch_index_git

(** Pure per-function CFG with post-dominance (dominance-MUST engine). *)
module Arch_index_cfg = Arch_index_cfg

(** [run_lsp_multi ~languages] indexes a project holding several languages into
    a single database. *)
val run_lsp_multi :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  project_dir:string ->
  languages:(string * string) list ->
  output:string ->
  ?no_enrich:bool ->
  ?verbose:bool ->
  unit ->
  (unit, string) Stdlib.result
