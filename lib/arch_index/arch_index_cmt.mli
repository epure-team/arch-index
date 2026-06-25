(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** CMT file processing for architecture indexing.

    Parses .cmt/.cmti files to extract module structure, functions, types,
    call graph, and module dependencies. *)

(** Convert a type to its string representation.

    {pre}
    (none)

    {post}
    Returns a human-readable string representation of the OCaml type expression.

    {violators}
    (none)

    {violates}
    (none) *)
val type_to_string : Types.type_expr -> string

(** Extract doc comment from OCaml attributes.

    {pre}
    (none)

    {post}
    Returns [Some text] if a doc comment attribute is present, [None] otherwise.

    {violators}
    (none)

    {violates}
    (none) *)
val extract_doc : Parsetree.attributes -> string option

(** Find all .cmt and .cmti files in a build directory.

    {pre}
    (none)

    {post}
    Returns a list of absolute paths to all [.cmt] and [.cmti] files found recursively.

    {violators}
    (none)

    {violates}
    (none) *)
val find_cmt_files : string -> string list

(** Collect names exposed in .cmti (interface) files.
    Returns (exposed_tbl, doc_tbl, module_quint_tbl) where:
    - exposed_tbl: (module_name, name) -> true
    - doc_tbl: (module_name, name) -> doc string
    - module_quint_tbl: module_name -> quint-module body string

    {pre}
    (none)

    {post}
    Returns a triple of hashtables mapping (module_name, name) to exposure flag,
    doc string, and quint-module body respectively.

    {violators}
    (none)

    {violates}
    (none) *)
val collect_exposed :
  string list ->
  (string * string, bool) Hashtbl.t
  * (string * string, string) Hashtbl.t
  * (string, string) Hashtbl.t

(** Extract (relative_source_path, function_name, type_signature) triples from
    a list of [.cmti] files.

    The relative source path is relative to [project_dir] and matches the
    [file_path] column populated by the LSP extractor.
    Silently skips unreadable or malformed files.

    {pre}
    [project_dir] is the absolute path to the project root.

    {post}
    Returns a list of (file_path_rel, name, type_sig) triples extracted from
    [.cmti] interface files.  May be empty if no CMT files exist or none are
    parseable.

    {violators}
    (none)

    {violates}
    (none) *)
val extract_signatures_from_cmti_files :
  project_dir:string -> string list -> (string * string * string) list

(** Collected module dependency information. *)
type pending_dep = {
  source_module : string;
  target_path : string;
  dep_kind : string;
  alias_name : string option;
  line_number : int;
}

(** Collected call information before resolution. *)
type pending_call = {
  caller_module : string;
  caller_name : string;
  callee_name : string;
  callee_module : string option;
  call_site : string;
}

(** [collect_calls_from_expr ~src_path ~caller_module ~caller_name expr]
    walks [expr] and returns all function-application call edges. *)
val collect_calls_from_expr :
  src_path:string ->
  caller_module:string ->
  caller_name:string ->
  Typedtree.expression ->
  pending_call list

(** Collected type usage information. *)
type pending_type_usage = {
  function_id : int;
  type_path : string;
  usage_role : string;
  position : int option;
}

(** Process a .cmt file: index modules, functions, types.
    Returns (pending_calls, pending_deps, pending_type_usages) for later resolution.
    
    @param project_root Project root directory for relativizing paths
    @param source_path_of_cmt Function to resolve source path from cmt info
    @param count_code_lines Function to count code lines in a source file

    {pre}
    The [.cmt] file path must be readable and valid.

    {post}
    Returns a triple of pending call edges, module dependencies, and type usages for later resolution.

    {violators}
    (none)

    {violates}
    (none) *)
val process_cmt :
  Sqlite3.db ->
  project_root:string ->
  source_path_of_cmt:(Cmt_format.cmt_infos -> string option) ->
  count_code_lines:(string -> int) ->
  exposed_tbl:(string * string, bool) Hashtbl.t ->
  doc_tbl:(string * string, string) Hashtbl.t ->
  module_quint_tbl:(string, string) Hashtbl.t ->
  stmt_mod:Sqlite3.stmt ->
  stmt_fn:Sqlite3.stmt ->
  stmt_ty:Sqlite3.stmt ->
  stmt_fld:Sqlite3.stmt ->
  stmt_ctor:Sqlite3.stmt ->
  string ->
  pending_call list * pending_dep list * pending_type_usage list
