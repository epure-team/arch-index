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

(** Set (or clear, with [None]) the [Arch_errors_config.seen] collector every
    value/type path the walker visits at its existing recording sites is
    reported to, for error-channels declaration validation
    (specs/error-channels.md slice 0).

    {pre}
    None.

    {post}
    Every subsequent [note_seen_value_path]/[note_seen_type_path] call (fired
    from the walker's own recording sites, not a new traversal) forwards to
    [Arch_errors_config.note_value_path]/[note_type_path] on the given [seen]
    when [Some], or is a no-op when [None]. Process-global like
    {!reset_dropped}; {!Arch_index.run} sets it before walking and clears it
    (passing [None]) right after, so a run's collector cannot leak into the
    next one or into a caller that never sets it.

    {violators}
    (none)

    {violates}
    (none) *)
val set_seen_collector : Arch_errors_config.seen option -> unit

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

(** Roadmap 1.4 (⊤-anchor taxonomy): why a [Head_unknown] target is
    unknowable — see the .ml for which reasons this walker can and cannot
    yet distinguish. *)
type top_reason =
  | Callback_param
      (** parameter / local closure / genuinely computed function value with
          no binding site — see .ml for the full caveat *)
  | Module_param  (** functor argument or first-class module *)
  | Dropped_node  (** the callee's own row/unit was intentionally rejected *)

(** [top_reason_to_string r] — the exact string this reason is stored as in
    [calls.top_reason].

    {pre}
    (none)

    {post}
    Returns ["callback_param"], ["module_param"], or ["dropped_node"].

    {violators}
    (none)

    {violates}
    (none) *)
val top_reason_to_string : top_reason -> string

(** What is statically known about a call's TARGET, independent of whether the
    call is conditional (see the .ml for the full taxonomy). *)
type call_head =
  | Head_local of string  (** same-module top-level fn — MUST candidate *)
  | Head_qualified of string option * string
      (** resolved qualified [(module, name)] — MUST candidate / external leaf *)
  | Head_enumerated of string
      (** named local fn passed as a callback → bounded candidate set *)
  | Head_unknown of string * top_reason
      (** unknowable target (param / computed / dynamic root / residual), plus WHY *)

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
  exn_scope : int option;
      (** innermost EXCEPTION-handler scope enclosing the call site in the
          caller node — a walker-local id inside [collect_calls_from_expr],
          the [exn_scopes] row id once [process_cmt] has stored the scope
          (specs/exn-raise-sets.md). *)
  errch_scope : int option;
      (** innermost VALUE-CHANNEL handler scope covering this call's head
          (specs/error-channels.md "Handler scopes"), in its own local id
          space, rewritten to an [exn_scopes] row id the same way.
          Independent of {!exn_scope}: a call site can carry both, and
          [call_exn_scopes] keys on [(call_id, scope_id)] so both are
          stored. *)
  errch_propagates : string option;
      (** [Some channel]: this call is a propagating edge on [channel]
          (specs/error-channels.md "Propagating edges") — an [exn_edges]
          role='propagates' row once resolved to a real [calls] row id. *)
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

(** [build_binding_names structure] maps each top-level value binding's
    [Ident.unique_name] (issue #41) to the name its [functions] row is
    written under: the LAST (source-order-final) binding at a colliding
    position keeps the bare qualified name; every earlier one takes a [#N]
    suffix. This direction is required for correctness: a cross-module
    caller can only reference the bare name, so it must denote the
    definition that is actually reachable. A binding with no same-level
    collision maps to its plain qualified name. *)
val build_binding_names : Typedtree.structure -> (string, string) Hashtbl.t

(** [binding_name names ~prefix id] looks up [id]'s assigned name in [names]
    (from {!build_binding_names} over the same structure). *)
val binding_name : (string, string) Hashtbl.t -> prefix:string -> Ident.t -> string

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
  ?canon_exn:(Path.t -> string) ->
  ?value_channels:Arch_errors_config.channel list ->
  src_path:string ->
  caller_module:string ->
  caller_name:string ->
  local_fn_stamps:(string, string * int) Hashtbl.t ->
  Typedtree.expression ->
  pending_call list
  * lambda_node list
  * (string * (Arch_index_exn.scope list * Arch_index_exn.origin list)) list
  * (string * Arch_errors_config.channel option * (Arch_index_errch.scope list * Arch_index_errch.origin list))
    list
(** The third component holds each node's exception facts (handler scopes and
    raise origins), keyed by the node name its calls are attributed to. The
    fourth holds each node's value-channel facts and its own carrier channel
    (specs/error-channels.md), same keying. [canon_exn] canonicalises
    exception constructor paths (default: [Path.name] — the LSP fallback
    path, which stores no exception rows). [value_channels] are the declared
    value channels (i.e. [Arch_errors_config.t.channels] minus [exception]);
    default [[]] — no value-channel analysis. *)

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
  stmt_scope:Sqlite3.stmt ->
  stmt_catch:Sqlite3.stmt ->
  stmt_origin:Sqlite3.stmt ->
  stmt_rebind:Sqlite3.stmt ->
  ?value_channels:Arch_errors_config.channel list ->
  ?stmt_carrier:Sqlite3.stmt ->
  ?producer_run_id:int option ->
  string ->
  pending_call list * pending_dep list * pending_type_usage list
