(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Database helpers for architecture indexing.

    Low-level SQLite utilities and insert functions for populating
    the architecture database. *)

(** Default database path (from ARCH_DB_PATH env or [docs/architecture.db]).

    {pre}
    (none)

    {post}
    Returns the resolved default path string for the architecture database.

    {violators}
    (none)

    {violates}
    (none) *)
val db_path : string

(** Default schema path (from ARCH_SCHEMA_PATH env or
    [architecture-schema.sql]).

    {pre}
    (none)

    {post}
    Returns the resolved default path string for the architecture schema file.

    {violators}
    (none)

    {violates}
    (none) *)
val schema_path : string

(** Current MAIN schema version, ["<major>.<minor>"] — describes
    [architecture-schema.sql]/[schema_path]/[schema_sql] below (the CMT-based
    path, [Arch_index.run]), bumped by hand at every schema change (minor for
    additive, major for breaking). History: [docs/schema.md]. NOT the version
    of the flat schema — see {!current_flat_schema_version}, a structurally
    different 3-table shape that must never be stamped with this value. *)
val current_schema_version : string

(** Version of the flat schema (the LSP-based path's own inline 3-table
    [comment_db_meta]/[functions]/[calls] shape, distinct from the main
    schema above) — has never changed, stays ["1.0"] until it does. Written
    by [runner.ml]'s two [comment_db_meta.schema_version] call sites, never
    by {!current_schema_version}. *)
val current_flat_schema_version : string

(** [schema_version_at_least ~major ~minor] — whether the current schema
    version is at least [major.minor], using proper numeric comparison
    (unlike a naive [current_schema_version = "1.2"] string check, this
    correctly orders e.g. [1.10] above [1.2]). Returns [false], not an
    exception, if [current_schema_version] is ever malformed — a consumer
    asking "is this compatible" should get a conservative no, not a crash. *)
val schema_version_at_least : major:int -> minor:int -> bool

(** [architecture-schema.sql]'s contents, embedded at compile time. Lets a
    consumer of the [arch-index] library diff against the exact schema text a
    given build promises without opening a database or resolving an
    install-time filesystem path. Independent of [schema_path] above, which
    still reads from a file at run time. *)
val schema_sql : string

(** Execute SQL directly, exit on error.

    {pre}
    The SQL string must be valid SQLite syntax.

    {post}
    Executes the SQL statement; exits the process on any error.

    {violators}
    (none)

    {violates}
    (none) *)
val statement_failures : unit -> int
(** Count of prepared-statement steps that did not return [DONE].

    [exec_stmt] prints such a failure and continues, so a run can reject rows
    and still exit 0 — which is how 238 rejected type_usage inserts went
    unnoticed while the summary reported them as written. Callers that own a
    run's exit status must consult this and fail when it is non-zero.

    Read-only on purpose. This is the number the CMT CLI's completeness gate
    exits 1 on, so a writable counter is a way for any library consumer to zero
    it and turn a truncated index into a silent success. Clearing it is
    {!reset_all}, which a run performs on itself. *)

val exec_exn : Sqlite3.db -> string -> unit

(** Execute a prepared statement, reset on completion.

    {pre}
    The statement must be fully bound before calling.

    {post}
    Executes and resets the statement; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val exec_stmt : Sqlite3.db -> what:string -> Sqlite3.stmt -> unit

(** Execute an insert whose rowid other rows will reference, returning that
    rowid only when the row was really stored.

    {pre}
    The statement must be a fully bound INSERT.

    {post}
    [Some id] when the insert succeeded, where [id] is this connection's
    [last_insert_rowid]; [None] when it was rejected. Never returns an id after
    a rejection: [last_insert_rowid] is per-connection and across all tables,
    so it survives a failed step and would otherwise hand back the previous
    successful insert's rowid — possibly a valid row of the same table
    belonging to a different entity, which dependent inserts would then satisfy
    their foreign key against, silently.

    {violators}
    (none)

    {violates}
    (none) *)
val exec_stmt_rowid : Sqlite3.db -> what:string -> Sqlite3.stmt -> int option

(** Rejected-row counts per destination table, sorted by table name. Empty when
    the run rejected nothing.

    {pre}
    None.

    {post}
    The returned association list has one entry per table that rejected at
    least one row, with a strictly positive count; the sum of counts equals the
    scalar reported by the run's [n_statement_failures].

    {violators}
    (none)

    {violates}
    (none) *)
val rejections_by_table : unit -> (string * int) list

(** Clear the per-table rejected-row tally.

    {pre}
    None. Safe to call whether or not a run has happened yet.

    {post}
    [rejections_by_table ()] returns [[]] immediately after this call, until
    the next call to [exec_stmt] that rejects a row. Does not touch the scalar
    [statement_failures], so the two disagree afterwards; use {!reset_all}
    unless a test is deliberately isolating the breakdown.

    {violators}
    (none)

    {violates}
    (none) *)
val reset_rejections : unit -> unit

(** Clear both the scalar failure count and the per-table breakdown.

    {pre}
    None. Safe before any run.

    {post}
    [statement_failures () = 0] and [rejections_by_table () = []]. This is the
    only way to clear the scalar: the two are one tally seen two ways, and
    resetting them together is what keeps [rejections_by_table]'s documented
    "counts sum to the scalar" true.

    {violators}
    (none)

    {violates}
    (none) *)
val reset_all : unit -> unit

(** Get the last inserted row ID.

    {pre}
    A row must have been inserted in this session.

    {post}
    Returns the integer rowid of the most recently inserted row.

    {violators}
    (none)

    {violates}
    (none) *)
val last_insert_rowid : Sqlite3.db -> int

(** Bind a text value to a statement parameter.

    {pre}
    (none)

    {post}
    Binds [string] to the given parameter index; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val bind_text : Sqlite3.stmt -> int -> string -> unit

(** Bind an integer value to a statement parameter.

    {pre}
    (none)

    {post}
    Binds [int] to the given parameter index; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val bind_int : Sqlite3.stmt -> int -> int -> unit

(** Bind a boolean value to a statement parameter (as 0/1).

    {pre}
    (none)

    {post}
    Binds 0 or 1 to the given parameter index; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val bind_bool : Sqlite3.stmt -> int -> bool -> unit

(** Bind an optional text value to a statement parameter.

    {pre}
    (none)

    {post}
    Binds the string or SQL NULL to the given parameter index; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val bind_text_opt : Sqlite3.stmt -> int -> string option -> unit

(** Insert one [producer_runs] row (roadmap 1.2, ADR 002), return its ID, or
    [None] if the row was rejected. Exactly one call per producer invocation
    — not a per-source-row insert like the rest of this module.

    {pre}
    (none)

    {post}
    [Some id] with the rowid of the newly inserted producer_runs record, or
    [None] when the row was rejected.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_producer_run :
  Sqlite3.db ->
  producer:string ->
  ?producer_version:string option ->
  ?invocation_digest:string option ->
  ?soundness_class:string ->
  unit ->
  int option

(** [invocation_digest ~producer ~producer_version ~argv] — an MD5 identity
    fingerprint over the invocation (Stdlib [Digest], not a SHA-256 library:
    this compares invocations, it is not a security boundary). Does not hash
    project content — see the [.ml] comment for why.

    {pre}
    (none)

    {post}
    Returns a hex digest string deterministic in its inputs.

    {violators}
    (none)

    {violates}
    (none) *)
val invocation_digest :
  producer:string -> producer_version:string option -> argv:string array -> string

(** Insert a module record, return its ID, or [None] if the row was rejected.

    {pre}
    (none)

    {post}
    [Some id] with the rowid of the newly inserted module record, or [None]
    when the row was rejected — in which case nothing was stored and the
    caller must not index anything under this module.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_module :
  Sqlite3.db ->
  Sqlite3.stmt ->
  path:string ->
  lines:int ->
  has_mli:bool ->
  ?quint_module_raw:string option ->
  ?language:string option ->
  unit ->
  int option

(** Insert a function record, return its ID, or [None] if the row was rejected.

    {pre}
    [module_id] must reference an existing module row.

    {post}
    [Some id] with the rowid of the newly inserted function record, or [None]
    when the row was rejected — in which case the caller must drop this
    function's dependent rows rather than attribute them to another id.

    {violators}
    (none)

    {violates}
    (none) *)
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
  ?language:string option ->
  ?producer_run_id:int option ->
  unit ->
  int option

(** Insert a type record, return its ID, or [None] if the row was rejected.

    {pre}
    [module_id] must reference an existing module row.

    {post}
    [Some id] with the rowid of the newly inserted type record, or [None] when
    the row was rejected — in which case its fields and constructors must be
    dropped rather than attached to another type's id.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_type :
  Sqlite3.db ->
  Sqlite3.stmt ->
  module_id:int ->
  name:string ->
  kind:string ->
  line_start:int ->
  line_end:int ->
  exposed:bool ->
  manifest:string option ->
  intent:string option ->
  int option

(** Insert a record field.

    {pre}
    [type_id] must reference an existing type row.

    {post}
    Inserts the field row and returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_field :
  Sqlite3.db ->
  Sqlite3.stmt ->
  type_id:int ->
  field_name:string ->
  field_type:string ->
  position:int ->
  unit

(** Insert a variant constructor.

    {pre}
    [type_id] must reference an existing type row.

    {post}
    Inserts the constructor row and returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_constructor :
  Sqlite3.db ->
  Sqlite3.stmt ->
  type_id:int ->
  constructor_name:string ->
  position:int ->
  arg_types:string option ->
  unit

(** Insert a call graph edge.

    {pre}
    [caller_id] must reference an existing function row.

    {post}
    Inserts the call edge row and returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_call :
  Sqlite3.db ->
  Sqlite3.stmt ->
  caller_id:int ->
  callee_id:int option ->
  callee_name:string ->
  call_site:string option ->
  kind:string ->
  ?top_reason:string option ->
  ?top_anchor:string option ->
  ?producer_run_id:int option ->
  unit ->
  unit

(** Insert a module dependency.

    {pre}
    [source_module] must reference an existing module row.

    {post}
    Inserts the dependency row and returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_module_dep :
  Sqlite3.db ->
  Sqlite3.stmt ->
  source_module:int ->
  target_module:int option ->
  target_path:string ->
  dep_kind:string ->
  alias_name:string option ->
  line_number:int ->
  unit

(** Insert a type usage record.

    {pre}
    [function_id] must reference an existing function row.

    {post}
    Inserts the type usage row and returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_type_usage :
  Sqlite3.db ->
  Sqlite3.stmt ->
  function_id:int ->
  type_id:int option ->
  type_name:string ->
  usage_role:string ->
  position:int option ->
  unit

(** {2 Exception-identity rows (specs/exn-raise-sets.md)} *)

(** [insert_call] with the rowid handed back ([None] on rejection), so a
    dependent [call_exn_scopes] row can reference this call and never another.

    {pre}
    Same as {!insert_call}.

    {post}
    Same row as {!insert_call}; returns its rowid, or [None] if rejected.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_call_rowid :
  Sqlite3.db ->
  Sqlite3.stmt ->
  caller_id:int ->
  callee_id:int option ->
  callee_name:string ->
  call_site:string option ->
  kind:string ->
  ?top_reason:string option ->
  ?top_anchor:string option ->
  ?producer_run_id:int option ->
  unit ->
  int option

(** Link a call to the innermost handler scope enclosing its site.

    {pre}
    [call_id] and [scope_id] reference existing rows.

    {post}
    One [call_exn_scopes] row, or a counted rejection.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_call_exn_scope : Sqlite3.db -> Sqlite3.stmt -> call_id:int -> scope_id:int -> unit

(** Insert a handler scope; returns its rowid ([None] on rejection).

    {pre}
    [function_id] references an existing functions row; [parent_id], when
    given, an existing [exn_scopes] row of the same function; [form] is
    ["try"] or ["match_exception"]; [channel] names the error channel this
    scope belongs to (specs/error-channels.md — the producer writes only
    ["exception"] as of schema 1.3, FR-029's byte-identical requirement).

    {post}
    One [exn_scopes] row and its rowid, or [None] and a counted rejection.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_exn_scope :
  Sqlite3.db ->
  Sqlite3.stmt ->
  function_id:int ->
  parent_id:int option ->
  form:string ->
  line:int ->
  col:int ->
  catch_all:bool ->
  channel:string ->
  int option

(** One caught canonical path of a scope's closing arms.

    {pre}
    [scope_id] references an existing [exn_scopes] row.

    {post}
    One [exn_scope_catches] row, or a counted rejection.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_exn_scope_catch : Sqlite3.db -> Sqlite3.stmt -> scope_id:int -> exn_path:string -> unit

(** One raise origin.

    {pre}
    [function_id] references an existing functions row; [form] is one of the
    [exn_origins.form] CHECK values; [channel] names the error channel this
    origin belongs to (specs/error-channels.md — the producer writes only
    ["exception"] as of schema 1.3, FR-029's byte-identical requirement).

    {post}
    One [exn_origins] row, or a counted rejection.

    {violators}
    (none)

    {violates}
    (none) *)
val insert_exn_origin :
  Sqlite3.db ->
  Sqlite3.stmt ->
  function_id:int ->
  scope_id:int option ->
  form:string ->
  exn_path:string option ->
  escapes:bool ->
  line:int ->
  col:int ->
  channel:string ->
  unit

(** [exception Alias = Target], both canonical.

    {pre}
    None.

    {post}
    One [exn_rebinds] row, or a counted rejection (duplicate alias).

    {violators}
    (none)

    {violates}
    (none) *)
val insert_exn_rebind : Sqlite3.db -> Sqlite3.stmt -> alias_path:string -> target_path:string -> unit
