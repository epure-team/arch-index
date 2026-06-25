(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** HTTP/HTTPS transport for the JSON-RPC 2.0 client.

    Sends JSON payloads over HTTP POST to a configured endpoint with
    configurable timeout and headers. Uses Cohttp-eio for the underlying
    HTTP implementation.

    Stories: #8, #9, #10, #13. *)

(** HTTP transport configuration. *)
type config = {
  base_url : string;
  headers : (string * string) list;
  timeout_s : float;
}

(** [default_config ~base_url ?extra_headers ()] creates a config with sensible
    defaults: content-type application/json, 30s timeout. Extra headers are
    merged additively — they do not replace the default Content-Type header.

    {pre}
    [base_url] must be a non-empty HTTP or HTTPS URL string.

    {post}
    Returns a [config] with the given base URL, Content-Type application/json, optional extra headers merged in, and a 30s timeout.

    {violators}
    (none)

    {violates}
    (none) *)
val default_config :
  base_url:string -> ?extra_headers:(string * string) list -> unit -> config

(** [make ~sw ~env config] creates a {!Jsonrpc_client.transport} that sends
    JSON-RPC payloads over HTTP POST to [config.base_url].

    Returns a transport callback suitable for {!Jsonrpc_client.config}.

    Stories: #8, #9, #10.

    {pre}
    The switch [sw] must be active. [config.base_url] must be a reachable HTTP or HTTPS endpoint.

    {post}
    Returns a [Jsonrpc_client.transport] callback that POST-sends each JSON payload to [config.base_url] and returns the response body.

    {violators}
    (none)

    {violates}
    (none) *)
val make :
  sw:Eio.Switch.t -> env:Eio_posix.stdenv -> config -> Jsonrpc_client.transport
