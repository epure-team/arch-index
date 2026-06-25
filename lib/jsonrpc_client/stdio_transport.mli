(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Stdio transport for the JSON-RPC 2.0 client.

    Sends JSON payloads over stdin/stdout to a child process using
    line-delimited framing. The child process is spawned once and reused
    for all requests within the switch scope.

    Uses Eio for async I/O, consistent with the HTTP transport. *)

(** Stdio transport configuration. *)
type config = {
  command : string;  (** Executable path or name *)
  args : string list;  (** Command-line arguments *)
  timeout_s : float;  (** Per-request timeout in seconds *)
}

(** [default_config ~command ?args ?timeout_s ()] creates a config with
    sensible defaults: no extra arguments, 30s timeout.

    {pre}
    [command] must be a non-empty string.

    {post}
    Returns a [config] with the given command, optional args (default [[]]), and optional timeout (default 30s).

    {violators}
    (none)

    {violates}
    (none) *)
val default_config :
  command:string -> ?args:string list -> ?timeout_s:float -> unit -> config

(** [make ~sw ~env config] spawns the child process and returns a
    {!Jsonrpc_client.transport} that sends JSON-RPC payloads over stdio.

    The child process lifetime is tied to [sw]: it is terminated when the
    switch exits. Each call to the returned transport writes one line to
    the child's stdin and reads one line from its stdout.

    Errors:
    - {!Jsonrpc_client.Connection_failed} if the process cannot be spawned
    - {!Jsonrpc_client.Timeout} if a request exceeds [config.timeout_s]
    - {!Jsonrpc_client.Transport_other} if the process exits unexpectedly

    {pre}
    The switch [sw] must be active. [config.command] must refer to an executable accessible in PATH or as an absolute path.

    {post}
    Returns a [Jsonrpc_client.transport] callback that sends each request to the child process via stdin and reads the response from stdout.

    {violators}
    (none)

    {violates}
    (none) *)
val make :
  sw:Eio.Switch.t -> env:Eio_posix.stdenv -> config -> Jsonrpc_client.transport
