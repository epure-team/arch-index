(** MCP stdio server engine (specs/arch-mcp-server.md).

    Read-only query tools over an arch-index SQLite DB. The engine is pure with
    respect to I/O: [handle_line]/[handle_message] map one inbound JSON-RPC
    document to at most one outbound document; the binary owns stdio. *)

type schema_info = {
  has_functions : bool;
  exp_col : string option;
  has_caller_name : bool;
  has_calls : bool;
  has_kind : bool;
  has_file_path : bool;
  has_line_count : bool;
  has_cq : bool;
  has_modules : bool;
  has_mod_lines : bool;
}

type ctx = {db : Sqlite3.db; si : schema_info}

val detect_schema : Sqlite3.db -> schema_info

val handle_message : ctx -> Yojson.Safe.t -> Yojson.Safe.t option
(** [None] for notifications. Tool failures are MCP [isError] results, never
    JSON-RPC errors (FR-004/005). *)

val handle_line : ctx -> string -> Yojson.Safe.t option
(** Framing wrapper: skips blank lines, strips CR, answers parse errors with
    -32700 (id null). *)

(** Exposed for tests: *)

val contract_check : ctx -> (unit, string) result

val escape_like : string -> string

val tool_names : unit -> string list
