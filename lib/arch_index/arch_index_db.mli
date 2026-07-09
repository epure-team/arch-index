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
    [docs/architecture-schema.sql]).

    {pre}
    (none)

    {post}
    Returns the resolved default path string for the architecture schema file.

    {violators}
    (none)

    {violates}
    (none) *)
val schema_path : string

(** Execute SQL directly, exit on error.

    {pre}
    The SQL string must be valid SQLite syntax.

    {post}
    Executes the SQL statement; exits the process on any error.

    {violators}
    (none)

    {violates}
    (none) *)
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
val exec_stmt : Sqlite3.db -> Sqlite3.stmt -> unit

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

(** Insert a module record, return its ID.

    {pre}
    (none)

    {post}
    Returns the integer rowid of the newly inserted module record.

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
  unit ->
  int

(** Insert a function record, return its ID.

    {pre}
    [module_id] must reference an existing module row.

    {post}
    Returns the integer rowid of the newly inserted function record.

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
  unit ->
  int

(** Insert a type record, return its ID.

    {pre}
    [module_id] must reference an existing module row.

    {post}
    Returns the integer rowid of the newly inserted type record.

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
  int

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
