(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** LSP subprocess manager. Spawns child process directly to retain the
    process handle, enabling [shutdown] to wait for clean exit. *)

module Jc = Jsonrpc_client

type t = {
  config : Jc.config;
  send_notify : string -> unit;
      (** Send a notification (fire-and-forget: writes only, no read). *)
  await_proc : unit -> Eio.Process.exit_status;
}

(* --- LSP Content-Length framing ------------------------------------------ *)

(** Write one LSP message with Content-Length header framing. *)
let send_lsp payload sink =
  let n = String.length payload in
  Eio.Flow.copy_string
    (Printf.sprintf "Content-Length: %d\r\n\r\n%s" n payload)
    sink

(** Read one LSP message, parsing the Content-Length header. *)
let recv_lsp reader =
  let content_length = ref (-1) in
  let rec read_headers () =
    let raw = Eio.Buf_read.line reader in
    (* Buf_read.line strips the trailing \n; strip \r if present *)
    let line =
      let n = String.length raw in
      if n > 0 && raw.[n - 1] = '\r' then String.sub raw 0 (n - 1) else raw
    in
    if line <> "" then begin
      (match String.index_opt line ':' with
      | Some i ->
          let key =
            String.lowercase_ascii (String.trim (String.sub line 0 i))
          in
          let value =
            String.trim (String.sub line (i + 1) (String.length line - i - 1))
          in
          if key = "content-length" then
            Option.iter (fun n -> content_length := n) (int_of_string_opt value)
      | None -> ()) ;
      read_headers ()
    end
  in
  read_headers () ;
  if !content_length < 0 then failwith "LSP: Content-Length header missing" ;
  Eio.Buf_read.take !content_length reader

let error_to_string = function
  | Jc.Transport_error (Connection_failed msg) ->
      Printf.sprintf "connection failed: %s" msg
  | Jc.Transport_error Timeout -> "transport timeout"
  | Jc.Transport_error (Http_error {status; body}) ->
      Printf.sprintf "HTTP error %d: %s" status body
  | Jc.Transport_error (Transport_other msg) ->
      Printf.sprintf "transport error: %s" msg
  | Jc.Rpc_error {code; message; _} ->
      Printf.sprintf "RPC error %d: %s" code message
  | Jc.Parse_error msg -> Printf.sprintf "parse error: %s" msg
  | Jc.Protocol_error msg -> Printf.sprintf "protocol error: %s" msg

let start ~sw ~env ~command ~args ~project_dir ?(init_options = `Null) () =
  let ( let* ) = Result.bind in
  let proc_mgr = Eio.Stdenv.process_mgr env in
  let clock = Eio.Stdenv.clock env in
  let stdin_r, stdin_w = Eio.Process.pipe ~sw proc_mgr in
  let stdout_r, stdout_w = Eio.Process.pipe ~sw proc_mgr in
  let await_proc, transport, send_notify =
    match
      Eio.Process.spawn
        ~sw
        proc_mgr
        ~stdin:(stdin_r :> _ Eio.Flow.source)
        ~stdout:(stdout_w :> _ Eio.Flow.sink)
        (command :: args)
    with
    | proc ->
        Eio.Switch.on_release sw (fun () ->
            (try Eio.Flow.close stdin_w with _ -> ()) ;
            try Eio.Process.signal proc Sys.sigterm with _ -> ()) ;
        Eio.Flow.close stdin_r ;
        Eio.Flow.close stdout_w ;
        let reader =
          Eio.Buf_read.of_flow ~max_size:(10 * 1024 * 1024) stdout_r
        in
        let mutex = Eio.Mutex.create () in
        let write_mutex = Eio.Mutex.create () in
        (* [is_notification raw] returns true when [raw] is a JSON-RPC
           notification (has "method" but no numeric "id").  LSP servers may
           send notifications (e.g. window/logMessage, $/progress) before or
           between responses; we must skip them when waiting for a reply. *)
        let is_notification raw =
          match Yojson.Safe.from_string raw with
          | `Assoc fields ->
              List.mem_assoc "method" fields
              && ((not (List.mem_assoc "id" fields))
                 ||
                 match List.assoc_opt "id" fields with
                 | Some `Null -> true
                 | _ -> false)
          | _ -> false
          | exception _ -> false
        in
        let transport payload =
          match
            Eio.Mutex.use_rw ~protect:true mutex (fun () ->
                Eio.Time.with_timeout_exn clock 30.0 (fun () ->
                    send_lsp payload stdin_w ;
                    (* Skip any interleaved notifications before the response. *)
                    let rec read_response () =
                      let raw = recv_lsp reader in
                      if is_notification raw then read_response () else raw
                    in
                    read_response ()))
          with
          | response -> Ok response
          | exception Eio.Time.Timeout -> Error Jc.Timeout
          | exception End_of_file ->
              Error (Jc.Transport_other "child process closed connection")
          | exception exn ->
              Error (Jc.Connection_failed (Printexc.to_string exn))
        in
        (* Notification-only send: writes without reading (no response expected). *)
        let send_notify payload =
          Eio.Mutex.use_rw ~protect:true write_mutex (fun () ->
              send_lsp payload stdin_w)
        in
        ((fun () -> Eio.Process.await proc), transport, send_notify)
    | exception exn ->
        Eio.Flow.close stdin_r ;
        Eio.Flow.close stdin_w ;
        Eio.Flow.close stdout_r ;
        Eio.Flow.close stdout_w ;
        raise exn
  in
  let jcfg = Jc.{transport} in
  (* Send initialize request *)
  let project_uri = "file://" ^ project_dir in
  let init_params =
    `Assoc
      [
        ("processId", `Null);
        ("rootUri", `String project_uri);
        ( "capabilities",
          `Assoc
            [
              ( "textDocument",
                `Assoc
                  [
                    ( "documentSymbol",
                      `Assoc [("hierarchicalDocumentSymbolSupport", `Bool true)]
                    );
                    (* rust-analyzer (and other servers) only register the
                       call-hierarchy provider when the client advertises the
                       capability with [dynamicRegistration]; an empty object
                       is not enough.  Without this, prepareCallHierarchy and
                       incoming/outgoingCalls are silently dropped → 0 edges. *)
                    ( "callHierarchy",
                      `Assoc [("dynamicRegistration", `Bool true)] );
                  ] );
              ("workspace", `Assoc [("symbol", `Assoc [])]);
            ] );
        ("initializationOptions", init_options);
      ]
  in
  let result =
    Jc.call
      jcfg
      ~method_:"initialize"
      ~params:(Jc.Named (match init_params with `Assoc kvs -> kvs | _ -> []))
      ()
  in
  let* _ = Result.map_error error_to_string result in
  (* Send initialized notification (fire-and-forget, no response expected). *)
  let notif =
    Yojson.Safe.to_string
      (Jc.encode_request ~method_:"initialized" ~params:(Jc.Named []) ())
  in
  send_notify notif ;
  Ok {config = jcfg; send_notify; await_proc}

let request t ~method_ ?params () =
  let jparams =
    match params with
    | None -> None
    | Some (`Assoc kvs) -> Some (Jc.Named kvs)
    | Some (`List lst) -> Some (Jc.Positional lst)
    | Some v -> Some (Jc.Named [("value", v)])
  in
  match Jc.call t.config ~method_ ?params:jparams () with
  | Ok resp -> Ok resp.Jc.result
  | Error e -> Error (error_to_string e)

let notify t ~method_ ?params () =
  let jparams =
    match params with
    | None -> None
    | Some (`Assoc kvs) -> Some (Jc.Named kvs)
    | Some (`List lst) -> Some (Jc.Positional lst)
    | Some v -> Some (Jc.Named [("value", v)])
  in
  (* Encode as a notification (no id) and send without reading a response. *)
  let notif =
    Yojson.Safe.to_string (Jc.encode_request ~method_ ?params:jparams ())
  in
  t.send_notify notif

let shutdown t =
  ignore (Jc.call t.config ~method_:"shutdown" ()) ;
  (* exit is a notification — send without waiting for a response. *)
  let exit_notif =
    Yojson.Safe.to_string
      (Jc.encode_request ~method_:"exit" ~params:(Jc.Named []) ())
  in
  t.send_notify exit_notif ;
  (* Wait for the LSP server process to exit cleanly after the exit notification. *)
  ignore (t.await_proc ())
