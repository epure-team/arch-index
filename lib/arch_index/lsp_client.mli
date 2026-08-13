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
  ?ready_quiet:float ->
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

(** What {!start}'s handshake learned about the server's background work.

    {!start} waits for it because a server that is still loading answers
    [prepareCallHierarchy] with an empty list rather than an error, making
    "still indexing" indistinguishable from "no calls".

    The four outcomes are NOT interchangeable, which is why this is not a bool:

    - [Reported] — the server's indexing phase closed. Authoritative.
    - [Quiescent] — every token it opened has closed and nothing has arrived for
      [ready_quiet] seconds. A HEURISTIC: a server whose next phase begins after
      a longer gap than that window is indistinguishable from one that has
      finished, and rust-analyzer has exactly that shape. Do not treat it as a
      fact about the index.
    - [No_progress] — [ready_grace] elapsed with no progress at all. Expected
      from a server with nothing to do, or one that does not report progress.
    - [Timed_out] — [ready_timeout] elapsed with work still in flight. The
      budget was too small, or the server is much slower than expected.
    - [Stream_ended] — the server closed its output during the handshake. No
      budget would have helped; kept distinct from [Timed_out] because the two
      send an operator to opposite fixes.

    None of these is an error. Anything other than [Reported] means the caller
    learned nothing it can rely on and should fall back to its own bounded
    retry. *)
type readiness =
  | Reported
  | Quiescent
  | No_progress
  | Timed_out
  | Stream_ended

val readiness : t -> readiness
val readiness_to_string : readiness -> string

(** [shutdown t] sends shutdown + exit, waits for process exit. *)
val shutdown : t -> unit
