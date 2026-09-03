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
  n_statement_failures : int;
      (** Rejected rows per destination table, sorted by table name, empty when
          nothing was rejected. The counts sum to [n_statement_failures]. *)
  rejections_by_table : (string * int) list;
      (** Prepared-statement steps that did not return [DONE] during this run.

          [exec_stmt] prints such a failure and continues, so a run can reject
          rows and still exit 0. When this is non-zero the other counts in this
          record are ATTEMPTS, not stored rows, and a caller that owns an exit
          status must fail. Measured before this field existed: indexing
          épure's src/ rejected 238 type_usage inserts on a stale
          [function_id] and reported them as written. *)
  db_path : string;
}

(** [run ~build_dir ()] scans the given build directory for [.cmt]/[.cmti]
    files and indexes them into an SQLite database.

    @param db_path Path to the SQLite database (default: from ARCH_DB_PATH env
      or [docs/architecture.db])
    @param schema_path Path to the SQL schema file (default: from
      ARCH_SCHEMA_PATH env or [architecture-schema.sql])
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
    On success, [output] is a valid SQLite file with [comment_db_meta.schema_version] set to
    {!schema_version}.
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

(** Minimal re-export of the per-table rejected-row accounting from
    {!Arch_index_db} (a [private_modules] library-internal module, invisible
    outside this library). Exposed so a test can drive [exec_stmt] directly
    against a hand-built SQLite fixture and assert the per-table breakdown it
    produces, without duplicating [exec_stmt]'s logic. Deliberately narrow: it
    is the accounting surface only, not the whole insert API. *)
module Db : sig
  val statement_failures : unit -> int
  (** Count of prepared-statement steps that did not return [DONE]. Read-only:
      it is the value the CMT CLI's exit-1 completeness gate reads, so it is not
      a consumer's to zero. See {!Arch_index_db.statement_failures}. *)

  val exec_stmt : Sqlite3.db -> what:string -> Sqlite3.stmt -> unit
  (** Execute a prepared statement, reset on completion; on failure records
      the rejection against [what] in both [statement_failures] and
      [rejections_by_table]. See {!Arch_index_db.exec_stmt}. *)

  val rejections_by_table : unit -> (string * int) list
  (** Rejected-row counts per destination table, sorted by table name. See
      {!Arch_index_db.rejections_by_table}. *)

  val reset_rejections : unit -> unit
  (** Clear the per-table tally. See {!Arch_index_db.reset_rejections}. *)

  val reset_all : unit -> unit
  (** Clear both the scalar failure count and the per-table breakdown — the
      only way to clear the scalar. See {!Arch_index_db.reset_all}. *)

  val insert_function :
    Sqlite3.db ->
    Sqlite3.stmt ->
    module_id:int ->
    name:string ->
    signature:string option ->
    line_start:int ->
    line_end:int ->
    exposed:bool ->
    intent:string option ->
    ?comment_quality_score:int option ->
    ?has_pre:bool ->
    ?has_post:bool ->
    ?has_violators:bool ->
    ?has_violates:bool ->
    ?violators_raw:string option ->
    ?violates_raw:string option ->
    ?tests_raw:string option ->
    ?quint_raw:string option ->
    ?mutation_sites:int option ->
    ?deref_sites:int option ->
    unit ->
    int option
  (** Insert a function row, returning its id — [None] when the row was
      rejected. Exposed alongside [exec_stmt] so a test can check that a
      rejected insert yields no id rather than the previous insert's, which
      [last_insert_rowid] would happily supply. See
      {!Arch_index_db.insert_function}. *)

  val insert_type_usage :
    Sqlite3.db ->
    Sqlite3.stmt ->
    function_id:int ->
    type_id:int option ->
    type_name:string ->
    usage_role:string ->
    position:int option ->
    unit
  (** Insert a type-usage row against [function_id]. The dependent insert whose
      misattribution is the point of the check above. See
      {!Arch_index_db.insert_type_usage}. *)
end

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

(** Current schema version, ["<major>.<minor>"] — what
    [comment_db_meta.schema_version] is stamped with by every run above.
    History and the table/column set each version added:
    [docs/schema.md]. (#51 part 1.) *)
val schema_version : string

(** [schema_version_at_least ~major ~minor] — whether the running library's
    schema version is at least [major.minor], via proper numeric comparison
    (not a brittle [schema_version = "1.2"] string check). Returns [false]
    rather than raising if [schema_version] is ever malformed. *)
val schema_version_at_least : major:int -> minor:int -> bool

(** [architecture-schema.sql]'s contents, embedded at compile time — lets a
    consumer of this library diff against the exact schema text a given build
    promises without opening a database or resolving an install-time
    filesystem path. (#51 part 1.) *)
val schema_sql : string
