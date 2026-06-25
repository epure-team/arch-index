(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

type config = {command : string; args : string list; timeout_s : float}

let default_config ~command ?(args = []) ?(timeout_s = 30.0) () =
  {command; args; timeout_s}

let make ~sw ~env config =
  let proc_mgr = Eio.Stdenv.process_mgr env in
  let clock = Eio.Stdenv.clock env in
  let stdin_r, stdin_w = Eio.Process.pipe ~sw proc_mgr in
  let stdout_r, stdout_w = Eio.Process.pipe ~sw proc_mgr in
  (match
     Eio.Process.spawn
       ~sw
       proc_mgr
       ~stdin:(stdin_r :> _ Eio.Flow.source)
       ~stdout:(stdout_w :> _ Eio.Flow.sink)
       (config.command :: config.args)
   with
  | proc ->
      Eio.Switch.on_release sw (fun () ->
          (try Eio.Flow.close stdin_w with _ -> ()) ;
          try Eio.Process.signal proc Sys.sigterm with _ -> ())
  | exception exn ->
      Eio.Flow.close stdin_r ;
      Eio.Flow.close stdin_w ;
      Eio.Flow.close stdout_r ;
      Eio.Flow.close stdout_w ;
      raise exn) ;
  (* Close the ends we don't use: the child reads from stdin_r and writes to
     stdout_w. We write to stdin_w and read from stdout_r. *)
  Eio.Flow.close stdin_r ;
  Eio.Flow.close stdout_w ;
  let reader = Eio.Buf_read.of_flow ~max_size:(10 * 1024 * 1024) stdout_r in
  let mutex = Eio.Mutex.create () in
  fun payload ->
    (* use_rw ~protect:true: if the callback raises, the mutex is permanently
       disabled.  This is intentional — after a timeout or EOF the
       reader/writer are out of sync and continued use would corrupt the
       protocol.  Callers receive a transport_error and should treat the
       transport as dead. *)
    match
      Eio.Mutex.use_rw ~protect:true mutex (fun () ->
          Eio.Time.with_timeout_exn clock config.timeout_s (fun () ->
              Eio.Flow.copy_string (payload ^ "\n") stdin_w ;
              Eio.Buf_read.line reader))
    with
    | response -> Ok response
    | exception Eio.Time.Timeout -> Error Jsonrpc_client.Timeout
    | exception End_of_file ->
        Error (Jsonrpc_client.Transport_other "child process closed connection")
    | exception exn ->
        Error (Jsonrpc_client.Connection_failed (Printexc.to_string exn))
