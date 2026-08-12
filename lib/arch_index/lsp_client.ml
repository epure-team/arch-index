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
  await_ready : timeout:float -> grace:float -> bool;
      (** Block until the server reports its background work finished. *)
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
  let await_proc, transport, send_notify, await_ready =
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
        (* An incoming frame is one of three things, and conflating the last two
           is a bug: a server-to-client REQUEST carries both "method" and a
           non-null "id", so a predicate that only asks "is there an id?" hands
           it back to the caller as if it were the reply to their own call. *)
        let classify raw =
          match Yojson.Safe.from_string raw with
          | `Assoc fields -> (
              let has_method = List.mem_assoc "method" fields in
              match (has_method, List.assoc_opt "id" fields) with
              | false, _ -> `Response
              | true, (None | Some `Null) -> `Notification fields
              | true, Some id -> `Server_request (id, fields))
          | _ -> `Response
          | exception _ -> `Response
        in
        (* A server-to-client request must be answered or the server can block
           waiting on it.  `window/workDoneProgress/create` is the one that
           matters here: rust-analyzer sends it before every progress token, and
           progress is exactly what we came for. *)
        let answer_server_request id =
          let reply =
            Yojson.Safe.to_string
              (`Assoc
                [("jsonrpc", `String "2.0"); ("id", id); ("result", `Null)])
          in
          Eio.Mutex.use_rw ~protect:true write_mutex (fun () ->
              send_lsp reply stdin_w)
        in
        let transport payload =
          match
            Eio.Mutex.use_rw ~protect:true mutex (fun () ->
                Eio.Time.with_timeout_exn clock 30.0 (fun () ->
                    send_lsp payload stdin_w ;
                    (* Skip any interleaved notifications before the response,
                       and answer any interleaved server request rather than
                       mistaking it for the reply. *)
                    let rec read_response () =
                      let raw = recv_lsp reader in
                      match classify raw with
                      | `Notification _ -> read_response ()
                      | `Server_request (id, _) ->
                          answer_server_request id ;
                          read_response ()
                      | `Response -> raw
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
        (* Wait for the server to finish its background work, by listening to
           the work-done progress it already reports, instead of sweeping and
           hoping.

           rust-analyzer answers prepareCallHierarchy with an empty list — not
           an error — while cargo metadata and the initial index are still
           running, so an empty sweep is indistinguishable from a call-free
           program.  Progress tokens make the difference observable: [begin]
           opens one, [end] closes it, and the server is ready once every token
           it opened has closed.

           Two bounds, because neither alone is safe:
           - [grace] caps the wait for the FIRST [begin].  A server with nothing
             to do (gopls on a warm module) never opens a token, and blocking
             for the full timeout on it would be a self-inflicted stall.
           - [timeout] caps the total wait, so a server that opens a token and
             dies, or reports progress forever, cannot hang the run.

           Returns true if the server actually reported quiescence; false if a
           bound was hit.  A false is NOT fatal — the caller falls back to the
           bounded-sweep behaviour — so a server that reports no progress at all
           is no worse off than before this existed. *)
        let await_ready ~timeout ~grace =
          let active = ref 0 in
          let saw_begin = ref false in
          let deadline_first = Eio.Time.now clock +. grace in
          (* token -> title, remembered at [begin] because [end] carries neither. *)
          let titles : (string, string) Hashtbl.t = Hashtbl.create 8 in
          let progress_of fields =
            match List.assoc_opt "params" fields with
            | Some (`Assoc p) ->
                let token =
                  match List.assoc_opt "token" p with
                  | Some (`String s) -> s
                  | Some (`Int i) -> string_of_int i
                  | _ -> ""
                in
                let kind, title =
                  match List.assoc_opt "value" p with
                  | Some (`Assoc v) ->
                      ( (match List.assoc_opt "kind" v with
                        | Some (`String k) -> Some k
                        | _ -> None),
                        match List.assoc_opt "title" v with
                        | Some (`String t) -> Some t
                        | _ -> None )
                  | _ -> (None, None)
                in
                Some (token, kind, title)
            | _ -> None
          in
          (* The indexing phase announces itself. rust-analyzer opens
             `rustAnalyzer/cachePriming` with the title "Indexing", and its
             [end] is the moment the symbol index is actually usable — which is
             the fact we need and the only one that answers the original race.

             This is checked by TITLE rather than token name so it is not tied
             to one server's private token namespace. *)
          let is_index_title = function
            | Some t -> String.lowercase_ascii t = "indexing"
            | None -> false
          in
          let trace = Sys.getenv_opt "ARCH_LSP_TRACE" <> None in
          (* "All open tokens closed" is NOT readiness. rust-analyzer runs its
             startup as a SEQUENCE of tokens — Fetching, Building CrateGraph,
             Roots Scanned, Building compile-time-deps, Indexing — and closes
             each one before opening the next, so the open count returns to zero
             between every phase. Treating the first of those zeros as "ready"
             releases the client at the end of `cargo metadata`, before a single
             file has been indexed, which is the original race with extra steps.

             Readiness is therefore quiescence: no tokens open AND nothing more
             arriving for [quiet] seconds. *)
          let quiet = Float.min 2.0 grace in
          (* Cancelling a read mid-frame would desynchronise the stream, so the
             timed read is only ever taken when the buffer is empty — i.e. at a
             frame boundary with nothing pending, where a cancellation consumes
             nothing. With bytes buffered, the next frame is already on its way
             and is read normally. *)
          let next_frame_opt () =
            if Cstruct.length (Eio.Buf_read.peek reader) > 0 then
              Some (recv_lsp reader)
            else
              match
                Eio.Time.with_timeout clock quiet (fun () ->
                    Ok (recv_lsp reader))
              with
              | Ok raw -> Some raw
              | Error `Timeout -> None
          in
          let rec loop () =
            (* Bail out before blocking on a read that may never come. *)
            if (not !saw_begin) && Eio.Time.now clock > deadline_first then false
            else
              match next_frame_opt () with
              | None ->
                  (* Quiet window elapsed: ready iff the server actually did
                     something and has nothing outstanding. *)
                  !saw_begin && !active <= 0
              | Some raw -> (
                  if trace then
                    prerr_endline
                      ("[lsp-trace] "
                      ^ String.sub raw 0 (Stdlib.min 200 (String.length raw))) ;
                  match classify raw with
                  | `Server_request (id, _) ->
                      answer_server_request id ;
                      loop ()
                  | `Response -> loop ()
                  | `Notification fields -> (
                      match
                        ( List.assoc_opt "method" fields,
                          progress_of fields )
                      with
                      | Some (`String "$/progress"), Some (token, kind, title)
                        -> (
                          match kind with
                          | Some "begin" ->
                              saw_begin := true ;
                              incr active ;
                              Option.iter
                                (fun t -> Hashtbl.replace titles token t)
                                title ;
                              loop ()
                          | Some "end" ->
                              (* Clamp: rust-analyzer emits `end` for tokens it
                                 never opened on this connection (and repeats
                                 some), so an unclamped counter drifts negative
                                 and every later quiescence check reads as
                                 satisfied regardless of real work in flight. *)
                              if !active > 0 then decr active ;
                              if is_index_title (Hashtbl.find_opt titles token)
                              then true
                              else loop ()
                          | _ -> loop ())
                      | _ -> loop ()))
          in
          (* protect:false, deliberately: [~protect:true] would make the section
             uncancellable and the timeout above could never fire. *)
          match
            Eio.Time.with_timeout clock timeout (fun () ->
                Ok (Eio.Mutex.use_rw ~protect:false mutex (fun () -> loop ())))
          with
          | Ok ready -> ready
          | Error `Timeout -> false
          | exception End_of_file -> false
        in
        ((fun () -> Eio.Process.await proc), transport, send_notify, await_ready)
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
              (* Without this the server is entitled to send no $/progress at
                 all — rust-analyzer does exactly that — and [await_ready] would
                 have nothing to wait on. *)
              ("window", `Assoc [("workDoneProgress", `Bool true)]);
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
  Ok {config = jcfg; send_notify; await_proc; await_ready}

let await_ready t ~timeout ~grace = t.await_ready ~timeout ~grace

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
