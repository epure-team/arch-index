(******************************************************************************)

(* A [file://] URI must carry an absolute path. The project directory arrives as
   a Cmdliner [dir] argument, which returns the string exactly as typed, so
   `--project .` produced `file://./src/foo.ml`. That is not a valid file URI:
   the server cannot open the document, every documentSymbol comes back empty,
   and the run writes an empty index while reporting success.

   These two live here rather than in a new module because [Lsp_client] is
   already a dependency-free leaf that every URI-building caller
   ([Lsp_extractor], [Call_graph_extractor]) already depends on, and it is
   already re-exported — so this adds no dependency edge and no public module. *)

let normalise_absolute path =
  let abs =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
    else path
  in
  (* Collapse "." segments and doubled separators; keep the leading "/". *)
  "/"
  ^ (String.split_on_char '/' abs
    |> List.filter (fun seg -> seg <> "." && seg <> "")
    |> String.concat "/")

let file_uri_of_path path = "file://" ^ normalise_absolute path

(* The mirror of the URI defect on the way back in: this compared a possibly
   relative [project_dir] against an absolute path from the server, so it never
   matched and every file_path was stored absolute — machine-specific, and
   unusable for any lookup keyed on a repo-relative path. It was also the third
   duplicated copy of the same function. *)
let relative_path ~project_dir abs_path =
  let root = normalise_absolute project_dir in
  let plen = String.length root in
  if
    String.length abs_path > plen
    && String.sub abs_path 0 plen = root
    && abs_path.[plen] = '/'
  then String.sub abs_path (plen + 1) (String.length abs_path - plen - 1)
  else abs_path

let path_of_file_uri uri =
  let prefix = "file://" in
  let plen = String.length prefix in
  if String.length uri > plen && String.sub uri 0 plen = prefix then
    String.sub uri plen (String.length uri - plen)
  else uri

(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** LSP subprocess manager. Spawns child process directly to retain the
    process handle, enabling [shutdown] to wait for clean exit. *)

module Jc = Jsonrpc_client

(* What the readiness wait LEARNED, not merely whether it succeeded.

   The distinction is load-bearing and a bool hid it. [Reported] is the server
   saying so: its indexing phase closed. [Quiescent] is a GUESS — every token it
   opened has closed and nothing has arrived since — and that guess is beatable,
   because a server whose next phase starts after a longer gap than the quiet
   window looks identical to one that has finished. rust-analyzer, the server
   this exists for, has exactly that shape: a sequence of phases with real gaps
   between them. So a caller that needs to trust the answer must be able to tell
   the two apart, and a caller that cannot tell should not treat a guess as a
   fact. *)
type readiness =
  | Reported  (** The indexing phase closed. Authoritative. *)
  | Quiescent  (** All opened tokens closed and nothing since. A heuristic. *)
  | No_progress  (** Nothing ever started: the server reports no progress. *)
  | Timed_out  (** The budget ran out while work was still in flight. *)
  | Stream_ended  (** The server closed its output mid-handshake. *)

(* [Timed_out] and [Stream_ended] were one case, printed as "budget exhausted".
   They are the two things an operator most needs told apart: one means raise
   the budget, the other means the server died and no budget would have helped.
   Naming the wrong one in the single line printed after an empty index sends
   the reader to the wrong fix. *)
let readiness_to_string = function
  | Reported -> "reported complete"
  | Quiescent -> "quiescent (heuristic, no indexing phase seen)"
  | No_progress -> "not reported (server sent no progress)"
  | Timed_out -> "not reported (budget exhausted)"
  | Stream_ended -> "not reported (server closed the connection)"

type t = {
  config : Jc.config;
  send_notify : string -> unit;
      (** Send a notification (fire-and-forget: writes only, no read). *)
  await_proc : unit -> Eio.Process.exit_status;
  readiness : readiness;
      (** What the handshake actually learned about the server's background work. *)
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

let start ~sw ~env ~command ~args ~project_dir ?(init_options = `Null)
    ?(ready_timeout = 60.) ?(ready_grace = 5.) ?(ready_quiet = 2.) () =
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
        (* Once a request has been written and its reply not read, the stream
           is desynchronised: every subsequent reply is off by one relative to
           the request that is waiting for it.

           That does NOT silently return a wrong answer — [Jsonrpc_client]
           stamps each request with a monotonic id and rejects any reply whose
           id does not match, so a desynced stream yields one [Protocol_error]
           per call, naming both ids. What it does produce is N confusing
           errors, each blaming an id mismatch, none of them naming the single
           event that caused all of them.

           So the first failure retires the connection and every later call
           reports that reason instead. This is stated here rather than left to
           [Eio.Mutex]'s own poisoning, which reaches the same refusal by
           accident and reports it as [Eio.Mutex.Poisoned] wrapped in
           [Connection_failed] — an implementation detail standing in for a
           diagnosis. The failures are caught inside the lock, so the mutex
           stays usable and the reason is the one recorded below. *)
        let retired = ref None in
        let transport payload =
          match !retired with
          | Some why -> Error (Jc.Transport_other why)
          | None ->
              let outcome =
                Eio.Mutex.use_rw ~protect:true mutex (fun () ->
                    match
                      Eio.Time.with_timeout_exn clock 30.0 (fun () ->
                          send_lsp payload stdin_w ;
                          (* Skip any interleaved notifications before the
                             response, and answer any interleaved server request
                             rather than mistaking it for the reply. *)
                          let rec read_response () =
                            let raw = recv_lsp reader in
                            match classify raw with
                            | `Notification _ -> read_response ()
                            | `Server_request (id, _) ->
                                answer_server_request id ;
                                read_response ()
                            | `Response -> raw
                          in
                          read_response ())
                    with
                    | response -> Ok response
                    | exception Eio.Time.Timeout ->
                        retired :=
                          Some
                            "the connection was retired: a request timed out \
                             with its reply unread, so the stream is \
                             desynchronised" ;
                        Error Jc.Timeout
                    | exception End_of_file ->
                        retired :=
                          Some
                            "the connection was retired: the child process \
                             closed it" ;
                        Error (Jc.Transport_other "child process closed connection")
                    | exception exn ->
                        let why = Printexc.to_string exn in
                        retired :=
                          Some
                            ("the connection was retired after a transport \
                              failure: " ^ why) ;
                        Error (Jc.Connection_failed why))
              in
              outcome
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

           Returns which of the four {!readiness} outcomes was reached. Only
           [Reported] is a fact about the index; the other three are NOT fatal —
           the caller falls back to the bounded-sweep behaviour — so a server
           that reports no progress at all is no worse off than before this
           existed. *)
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

             The indexing phase closing is the authoritative signal. Quiescence
             — no tokens open and nothing arriving for [quiet] seconds — is only
             the FALLBACK for a server that reports work but never names an
             indexing phase, and it is reported as [Quiescent] rather than
             [Reported] because it can fire in an inter-phase gap longer than
             the window. It is a guess, and it says so. *)
          let quiet = ready_quiet in
          let deadline = Eio.Time.now clock +. timeout in
          (* No cancellation is ever allowed to land INSIDE a frame.
             [Buf_read] consumes as it parses, so a read interrupted between the
             Content-Length header and the body leaves the body in the buffer
             and desynchronises the stream permanently — every later request
             would then read the wrong reply, which is the failure this whole
             function exists to prevent, arrived at from the other side.

             So the only thing under a timeout is [ensure], which FILLS the
             buffer without consuming from it: cancelling it is a no-op on the
             stream. Once at least one byte is buffered, the frame is read
             without a deadline. A server that emits a partial frame and then
             stalls is left to the pipeline-level timeout in the runner, which
             abandons the whole connection rather than reusing a desynced one. *)
          let next_frame_opt () =
            let now = Eio.Time.now clock in
            let remaining = deadline -. now in
            (* Every deadline this wait owes, as ONE bound. Checking [grace] only
               between iterations was not enough: each iteration blocks for a
               whole [quiet] first, so the effective bound on the wait for the
               first [begin] became [quiet * ceil (grace / quiet)] — grace
               rounded UP, the mirror image of the [min (quiet, grace)] bug this
               replaced, and just as far from what the interface promises.
               ~ready_grace:1. ~ready_quiet:30. waited thirty seconds. *)
            let until_grace =
              if !saw_begin then infinity else deadline_first -. now
            in
            if remaining <= 0. then `Deadline
            else if until_grace <= 0. then `Quiet
            else
              match
                Eio.Time.with_timeout clock
                  (Float.min quiet (Float.min remaining until_grace))
                  (fun () ->
                    Eio.Buf_read.ensure reader 1 ;
                    Ok ())
              with
              | Ok () -> `Frame (recv_lsp reader)
              | Error `Timeout -> `Quiet
              | exception End_of_file -> `Eof
          in
          let rec loop () =
            (* [grace] bounds the wait for the FIRST begin, and it has to be
               checked HERE rather than inferred from a quiet window: silence
               before anything starts is the normal case for a server with no
               work, and returning on the first quiet window made the effective
               bound min(quiet, grace) while the interface promised grace. *)
            if (not !saw_begin) && Eio.Time.now clock > deadline_first then
              No_progress
            else
              match next_frame_opt () with
              | `Deadline -> Timed_out
              | `Eof -> Stream_ended
              | `Quiet ->
                  (* Silence with a token still open is a phase in flight —
                     cargo fetching, a build script running — so keep waiting.
                     Silence with nothing open is quiescence, which is a GUESS:
                     reported as such, never as the server having said so. *)
                  if !active > 0 || not !saw_begin then loop () else Quiescent
              | `Frame raw -> (
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
                              then Reported
                              else loop ()
                          | _ -> loop ())
                      | _ -> loop ()))
          in
          (* Deliberately NOT under the request mutex.

             An earlier version wrapped this in [Eio.Mutex.use_rw ~protect:false]
             so an outer timeout could still cancel it. That is worse than no
             lock at all: Eio POISONS a mutex whose critical section is left by
             an exception, so one readiness timeout made every subsequent
             [transport] call raise Poisoned, and the run wrote 0 functions and 0
             calls — the emptiness this change exists to prevent, now caused by
             it.

             No lock is needed instead of a safer lock, because this runs during
             the handshake: [start] has not returned the client yet, so no other
             fiber can hold the connection. The deadline is enforced by the loop
             itself rather than by cancelling it from outside. *)
          try loop () with End_of_file -> Stream_ended
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
  (* The handshake root: a relative --project made this the malformed
     [file://./…], which every subsequent document URI then inherited. *)
  let project_uri = file_uri_of_path project_dir in
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
  (* Waited for HERE rather than by the caller: during the handshake the client
     has not escaped yet, so the readiness loop provably owns the connection and
     needs no lock around it. Making it the caller's job would turn that into a
     convention that a future caller could break by issuing a request first. *)
  let readiness = await_ready ~timeout:ready_timeout ~grace:ready_grace in
  Ok {config = jcfg; send_notify; await_proc; readiness}

let readiness t = t.readiness

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
