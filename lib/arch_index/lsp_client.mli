(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** LSP subprocess manager built on jsonrpc_client/stdio_transport. *)

type t

(** [start ~sw ~env ~command ~args ~project_dir ?init_options ()] spawns the
    LSP server, performs the initialize/initialized handshake, returns a
    connected client.  [init_options] is forwarded as [initializationOptions]
    in the LSP initialize request (defaults to [`Null]).
    Returns [Error msg] if the server fails to start or initialize. *)
val start :
  sw:Eio.Switch.t ->
  env:Eio_unix.Stdenv.base ->
  command:string ->
  args:string list ->
  project_dir:string ->
  ?init_options:Yojson.Safe.t ->
  ?ready_timeout:float ->
  ?ready_grace:float ->
  unit ->
  (t, string) result

(** [request t ~method_ ~params ()] sends a JSON-RPC 2.0 request and returns
    the result as a Yojson value. Returns [Error msg] on failure. *)
val request :
  t ->
  method_:string ->
  ?params:Yojson.Safe.t ->
  unit ->
  (Yojson.Safe.t, string) result

(** [notify t ~method_ ~params ()] sends a JSON-RPC notification (no response). *)
val notify : t -> method_:string -> ?params:Yojson.Safe.t -> unit -> unit

(** [ready_reported t] is [true] when the server actually reported its
    background work finished during {!start}'s handshake.

    {!start} waits for that signal because a server that is still loading
    answers [prepareCallHierarchy] with an empty list rather than an error,
    making "still indexing" indistinguishable from "no calls". [ready_timeout]
    bounds the whole wait and [ready_grace] bounds the wait for the FIRST
    progress notification, so a server with no work to report does not stall
    the run.

    [false] is not an error: it means nothing was learned, and the caller should
    fall back to its own bounded retry. *)
val ready_reported : t -> bool

(** [shutdown t] sends shutdown + exit, waits for process exit. *)
val shutdown : t -> unit
