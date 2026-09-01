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

(** Forget every node recorded as dropped so far.

    {pre}
    None. Safe before any run.

    {post}
    [is_dropped_node] answers [false] for every argument and
    [dropped_unit_paths ()] is [[]], until the next rejected insert. The
    registry is process-global, so {!Arch_index.run} calls this at entry for the
    same reason it resets the rejection tally: a second run must not inherit the
    first's frontier.

    {violators}
    (none)

    {violates}
    (none) *)
val reset_dropped : unit -> unit

(** Is [name] in [module_path] a body this run analysed but could not store?

    {pre}
    [module_path] is a module's rel_path as stored in [modules.path], and [name]
    a function name as it would appear in [functions.name].

    {post}
    [true] when that function's own [functions] row was rejected, or when the
    whole compilation unit's [modules] row was — in the latter case nothing from
    the unit was indexed, so every name in it is dropped. [false] otherwise,
    which for a name absent from the index means it is a genuine external.

    The distinction is a soundness one: an unresolved callee that is external is
    a leaf and a MUST edge to it is honest, while an unresolved callee that is
    dropped has an unanalysed body and must be recorded as MAY_TOP so
    reachability does not terminate on it.

    {violators}
    (none)

    {violates}
    (none) *)
val is_dropped_node : module_path:string -> name:string -> bool

(** Rel_paths of the compilation units whose [modules] row was rejected.

    {pre}
    None.

    {post}
    Sorted, one entry per dropped unit, empty when nothing was dropped. Nothing
    at all was indexed from these units, so they carry no per-function entries
    and a caller resolving a name against one of them must consult this list.

    {violators}
    (none)

    {violates}
    (none) *)
val dropped_unit_paths : unit -> string list

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

(** What is statically known about a call's TARGET, independent of whether the
    call is conditional (see the .ml for the full taxonomy). *)
type call_head =
  | Head_local of string  (** same-module top-level fn — MUST candidate *)
  | Head_qualified of string option * string
      (** resolved qualified [(module, name)] — MUST candidate / external leaf *)
  | Head_enumerated of string
      (** named local fn passed as a callback → bounded candidate set *)
  | Head_unknown of string
      (** unknowable target (param / computed / dynamic root / residual) *)

(** Collected call information before resolution. [cond] is computed by CFG
    post-dominance: [false] iff the call's basic block runs on EVERY execution
    of the enclosing function. [partial] marks under-saturated applications. *)
type pending_call = {
  caller_module : string;
  caller_name : string;
  head : call_head;
  partial : bool;
  cond : bool;
  dead : bool;
      (** call block is UNREACHABLE from the CFG entry: this call can never
          execute (R2). Under-approximate — unmodelled constructs stay
          reachable, so this never over-claims. *)
  call_site : string;
}

(** Flat [(name, module)] display of a pending call's callee, for kind-less
    consumers (the LSP fallback path). *)
val pending_display : pending_call -> string * string option

(** A synthetic function node for a nested [fun …]/[function] literal
    ([parent.<fun:LINE:COL>], chained through enclosing nodes, [#N] in-marker
    ordinal on a same-position collision). Its body's calls are attributed to
    this node under its own CFG. *)
type lambda_node = {
  lam_name : string;
  lam_line_start : int;
  lam_line_end : int;
  lam_arity : int;
}

(** [is_function_rhs e] is [true] iff [e] is a syntactic function body — the
    only binding shape treated as a statically-callable (MUST) node. *)
val is_function_rhs : Typedtree.expression -> bool

(** [fn_arity e] is the syntactic arity (leading parameter count) of a function
    binding's RHS — used to detect partial (under-saturated) applications. A
    non-function expression has arity 0. *)
val fn_arity : Typedtree.expression -> int

(** Shared pre-pass: top-level function-binder stamps ([Ident.unique_name]) →
    syntactic arity, over a whole structure (covers forward references and
    [let rec … and …] groups). Used by both the main indexer and the LSP
    fallback so the two paths cannot drift. *)
(** [build_local_fn_stamps structure] maps each same-unit function binding's
    [Ident.unique_name] to the definition path it is indexed under and its
    arity.  Nested bindings are included, under their qualified path, so a call
    site inside a functor names its target the way the target is registered. *)
val build_local_fn_stamps :
  Typedtree.structure -> (string, string * int) Hashtbl.t

(** [collect_calls_from_expr ~src_path ~caller_module ~caller_name
    ~local_fn_stamps expr] lowers [expr] onto per-node CFGs and returns the
    collected call edges plus the promoted lambda nodes. [local_fn_stamps] maps
    same-module top-level function-binder stamps ([Ident.unique_name]) to their
    syntactic arity. *)
val collect_calls_from_expr :
  src_path:string ->
  caller_module:string ->
  caller_name:string ->
  local_fn_stamps:(string, string * int) Hashtbl.t ->
  Typedtree.expression ->
  pending_call list * lambda_node list

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
