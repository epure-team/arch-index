(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** JSON-RPC 2.0 client library.

    A spec-compliant JSON-RPC 2.0 client that supports requests, notifications,
    and batch operations over abstract transports. The client exposes a
    consistent [Result.t]-based API and cleanly separates protocol errors from
    transport errors.

    The transport layer is abstracted behind a callback, allowing HTTP, stdio,
    mock, or any other transport to be plugged in via the [config.transport]
    field. *)

(** {1 Protocol types} *)

(** JSON-RPC 2.0 parameters: positional (array) or named (object). *)
type params =
  | Positional of Yojson.Safe.t list
  | Named of (string * Yojson.Safe.t) list

(** A JSON-RPC 2.0 structured error from the server. *)
type rpc_error = {code : int; message : string; data : Yojson.Safe.t option}

(** A successful JSON-RPC 2.0 response. *)
type response = {id : Yojson.Safe.t; result : Yojson.Safe.t}

(** Transport-level errors (network, timeout, HTTP status). *)
type transport_error =
  | Connection_failed of string
  | Timeout
  | Http_error of {status : int; body : string}
  | Transport_other of string

(** All client errors. Transport and protocol failures are distinguished. *)
type error =
  | Transport_error of transport_error
  | Rpc_error of rpc_error
  | Parse_error of string
  | Protocol_error of string

(** {1 Encoding and decoding} *)

(** [encode_request ~method_ ?params ?id ()] builds a JSON-RPC 2.0 request
    object. If [id] is [None], a notification (no response expected) is
    produced.

    Stories: #1, #4, #7.

    {pre}
    [method_] must be a non-empty string.

    {post}
    Returns a JSON object conforming to JSON-RPC 2.0; omits the [id] field
    when [id] is [None] (notification).

    {violators}
    (none)

    {violates}
    (none) *)
val encode_request :
  method_:string -> ?params:params -> ?id:Yojson.Safe.t -> unit -> Yojson.Safe.t

(** [decode_response json] parses a JSON-RPC 2.0 response envelope.
    Returns either a success {!response} or a structured {!error}.
    Validates that [jsonrpc = "2.0"].

    Stories: #2, #3, #11, #15.

    {pre}
    [json] must be a JSON object.

    {post}
    Returns [Ok response] for a successful result or [Error e] for a
    protocol-level error; returns [Error (Parse_error _)] if [json] does
    not conform to JSON-RPC 2.0.

    {violators}
    (none)

    {violates}
    (none) *)
val decode_response : Yojson.Safe.t -> (response, error) result

(** [encode_batch requests] wraps a list of JSON-RPC request objects into
    a JSON array for batch submission.

    Story: #5.

    {pre}
    [requests] must be a non-empty list of JSON-RPC request objects (as
    produced by [encode_request]).

    {post}
    Returns a JSON array containing all request objects.

    {violators}
    (none)

    {violates}
    (none) *)
val encode_batch : Yojson.Safe.t list -> Yojson.Safe.t

(** [decode_batch_response json] parses a JSON-RPC 2.0 batch response (array).
    Returns a list of individual results paired with the response id.

    Story: #5.

    {pre}
    [json] must be a JSON array of JSON-RPC 2.0 response objects.

    {post}
    Returns a list of [(result, id option)] pairs, one per response element,
    in the order they appear in [json].

    {violators}
    (none)

    {violates}
    (none) *)
val decode_batch_response :
  Yojson.Safe.t -> ((response, error) result * Yojson.Safe.t option) list

(** {1 ID generation} *)

(** [next_id ()] returns a unique integer ID for request correlation.

    Story: #6.

    {pre}
    (none)

    {post}
    Returns a JSON integer that is strictly greater than all previously
    returned IDs in the current process lifetime.

    {violators}
    (none)

    {violates}
    (none) *)
val next_id : unit -> Yojson.Safe.t

(** [reset_id_counter ()] resets the ID counter to zero.

    {b Warning:} This function exists solely for deterministic test assertions.
    It must not be called in production code — doing so would break request ID
    uniqueness guarantees required by Story #6.

    {pre}
    Must only be called from test code, never in production paths.

    {post}
    Resets the internal counter so the next [next_id ()] call returns [0].

    {violators}
    (none)

    {violates}
    (none) *)
val reset_id_counter : unit -> unit

(** {1 Transport abstraction}

    Story: #13. *)

(** The transport callback sends a JSON payload string and returns the raw
    response string, or a transport error. *)
type transport = string -> (string, transport_error) result

(** {1 Client API}

    All public operations return [(_, error) result].

    Story: #12. *)

(** Client configuration. *)
type config = {transport : transport}

(** [call config ~method_ ?params ()] sends a JSON-RPC 2.0 request and returns
    the parsed result on success.

    Stories: #1, #2, #3, #6, #7, #11, #12, #15.

    {pre}
    [config.transport] must be a functioning transport callback. [method_]
    must be a non-empty string.

    {post}
    Returns [Ok response] with the server's result on success, or
    [Error e] on transport failure or a JSON-RPC error response.

    {violators}
    (none)

    {violates}
    (none) *)
val call :
  config -> method_:string -> ?params:params -> unit -> (response, error) result

(** [notify config ~method_ ?params ()] sends a JSON-RPC 2.0 notification
    (fire-and-forget, no response expected).

    Story: #4.

    {pre}
    [config.transport] must be a functioning transport callback. [method_]
    must be a non-empty string.

    {post}
    Returns [Ok ()] after successfully sending the notification, or
    [Error e] on transport failure.

    {violators}
    (none)

    {violates}
    (none) *)
val notify :
  config -> method_:string -> ?params:params -> unit -> (unit, error) result

(** [batch config requests] sends multiple JSON-RPC 2.0 requests as a batch
    and correlates responses. Each element is [(method_, params)] — an ID
    is assigned automatically to each. Returns results in the same order as
    the input.

    Story: #5.

    {pre}
    [config.transport] must be a functioning transport callback. [requests]
    must be a non-empty list.

    {post}
    Returns [Ok results] with one [(response, error) result] per input
    request in the same order, or [Error e] on a transport-level failure
    that prevents the entire batch.

    {violators}
    (none)

    {violates}
    (none) *)
val batch :
  config ->
  (string * params option) list ->
  ((response, error) result list, error) result
