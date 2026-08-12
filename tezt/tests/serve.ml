(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** arch-serve: the routes it answers, and the schema it must decline.

    arch-serve reads [functions.file_path], which only the FLAT schema has. On a
    MAIN-schema index — the shape this repository's own self-index uses — it used
    to reach its first prepare and die with an uncaught
    Sqlite3.Error("no such column: file_path"). Both halves are asserted here,
    because a server that starts and then fails every request is worse than one
    that refuses to start. *)

open Arch_tezt

let serve_bin () = locate ~env_var:"ARCH_SERVE" "bin/arch_serve/arch_serve.exe"

(* A fixed port rather than a random one: a server leaked by an earlier run would
   otherwise answer these assertions instead of the one under test, and the
   failure would be invisible. Fixed means the leak fails here. *)
let port = 7387

let flat_seed =
  {|
CREATE TABLE comment_db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE functions (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, file_path TEXT NOT NULL,
  line_start INTEGER NOT NULL DEFAULT 0, line_end INTEGER NOT NULL DEFAULT 0,
  exported INTEGER NOT NULL DEFAULT 0, signature TEXT, summary TEXT,
  comment_quality_score INTEGER, has_pre INTEGER NOT NULL DEFAULT 0,
  has_post INTEGER NOT NULL DEFAULT 0, has_violators INTEGER NOT NULL DEFAULT 0,
  has_violates INTEGER NOT NULL DEFAULT 0, violators_raw TEXT, violates_raw TEXT,
  tests_raw TEXT, quint_raw TEXT
);
CREATE TABLE calls (
  id INTEGER PRIMARY KEY, caller_name TEXT NOT NULL, caller_file TEXT NOT NULL,
  callee_name TEXT NOT NULL, callee_file TEXT, call_site TEXT, kind TEXT
);
INSERT INTO functions (id,name,file_path,line_start,line_end,exported) VALUES
  (1,'Entry','svc/main.go',3,7,1),
  (2,'helper','svc/main.go',9,11,0);
INSERT INTO calls (caller_name,caller_file,callee_name,callee_file,call_site,kind) VALUES
  ('Entry','svc/main.go','helper','svc/main.go','svc/main.go:5','MAY_ENUMERATED');
|}

let flat_db () =
  let db = temp_db "serve_flat" in
  Db.with_db_rw db (fun conn -> Db.exec conn flat_seed) ;
  db

(* Only the SHAPE matters: functions with module_id and no file_path. *)
let main_db () =
  let db = temp_db "serve_main" in
  Db.with_db_rw db (fun conn ->
      Db.exec conn
        {|
CREATE TABLE comment_db_meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE modules (id INTEGER PRIMARY KEY, name TEXT, path TEXT);
CREATE TABLE functions (
  id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, signature TEXT,
  line_start INTEGER, line_end INTEGER, exposed INTEGER
);
CREATE TABLE calls (
  id INTEGER PRIMARY KEY, caller_id INTEGER, callee_id INTEGER,
  callee_name TEXT, call_site TEXT, kind TEXT
);
INSERT INTO modules VALUES (1,'M','lib/m.ml');
INSERT INTO functions VALUES (1,1,'f',NULL,1,2,1);
|}) ;
  db

let curl args =
  let code, out = run_command (which "curl") args in
  (code, out)

(* Poll for readiness rather than sleeping a guessed interval, and give up as
   soon as the process is gone — a server that died is never going to answer. *)
let wait_ready ~pid_file =
  let url = Printf.sprintf "http://localhost:%d/" port in
  (* Liveness is `kill -0`, not the existence of the pid FILE: the file is
     written once at spawn and never removed, so testing for it is always true
     and the loop it was meant to short-circuit ran its full 10s on a server
     that had already died. *)
  let alive () =
    Sys.file_exists pid_file
    && Sys.command (Printf.sprintf "kill -0 $(cat %s) 2>/dev/null" (Filename.quote pid_file)) = 0
  in
  let rec attempt n =
    if n = 0 then false
    else
      let code, _ = curl ["-fsS"; "-o"; "/dev/null"; url] in
      if code = 0 then true
      else if not (alive ()) then false
      else (
        ignore (Sys.command "sleep 0.2") ;
        attempt (n - 1))
  in
  attempt 50

let with_server db k =
  let log = Temp.file "serve.log" in
  let pid_file = Temp.file "serve.pid" in
  (* Backgrounded through the shell, with the pid recorded so cleanup can reach
     it: Sys.command waits for its child, so the server has to outlive the call
     that starts it. *)
  ignore
    (Sys.command
       (Printf.sprintf "%s %s --port %d > %s 2>&1 & echo $! > %s"
          (Filename.quote (serve_bin ()))
          (Filename.quote db) port (Filename.quote log) (Filename.quote pid_file))) ;
  Fun.protect
    ~finally:(fun () ->
      if Sys.file_exists pid_file then
        ignore (Sys.command (Printf.sprintf "kill $(cat %s) 2>/dev/null" (Filename.quote pid_file))))
    (fun () -> k ~log ~pid_file)

let register_refusal () =
  Test.register ~__FILE__ ~title:"serve: a main-schema index is declined, not crashed on"
    ~tags:["serve"]
  @@ fun () ->
  let db = main_db () in
  (* Wrapped in `timeout`: this command is expected to EXIT, and if the guard
     regresses it does the opposite — it binds the port and serves. Without a
     deadline the assertion below would never be reached and the suite would
     hang rather than report the regression it exists to catch. *)
  let code, output =
    run_command (which "timeout") ["20"; serve_bin (); db; "--port"; string_of_int port]
  in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"a main-schema index must be declined at startup" ~expected:2
        (code, output) ;
      Batch.contains b ~msg:"the refusal must name the schema it cannot read" ~haystack:output
        "MAIN schema" ;
      (* The regression this guards: an uncaught Sqlite3.Error where the honest
         answer is "this tool does not read that shape yet". *)
      Batch.not_contains b ~msg:"the refusal must not be an internal error" ~haystack:output
        "internal error" ;
      Batch.not_contains b ~msg:"the refusal must not surface a raw Sqlite3 exception"
        ~haystack:output "Sqlite3.Error") ;
  Lwt.return_unit

let register_routes () =
  Test.register ~__FILE__ ~title:"serve: the flat schema is served over HTTP"
    ~tags:["serve"]
  @@ fun () ->
  let db = flat_db () in
  with_server db @@ fun ~log ~pid_file ->
  if not (wait_ready ~pid_file) then
    Test.fail "server did not answer on port %d:\n%s" port
      (if Sys.file_exists log then read_file log else "(no log)") ;
  let base = Printf.sprintf "http://localhost:%d" port in
  (* One request, not two: the body goes to a file and curl writes the status
     code to stdout, which run_command hands back. Issuing the request twice to
     read the two halves would also double every side effect. *)
  let get path =
    let out = Temp.file "serve_body" in
    let _, status = curl ["-sS"; "-o"; out; "-w"; "%{http_code}"; base ^ path] in
    (String.trim status, if Sys.file_exists out then read_file out else "")
  in
  Batch.run (fun b ->
      let status, body = get "/" in
      Batch.eq_string b ~msg:"GET / must be 200" status "200" ;
      (* The SPA is a compiled-in blob, so an empty one would still be 200. *)
      Batch.check b ~msg:"GET / must return a non-empty body" (String.length body > 0) ;
      Batch.check b ~msg:"GET / must return HTML"
        (let lowered = String.lowercase_ascii body in
         let contains needle =
           let n = String.length needle and h = String.length lowered in
           let found = ref false in
           for i = 0 to h - n do
             if (not !found) && String.sub lowered i n = needle then found := true
           done ;
           !found
         in
         contains "<html" || contains "<!doctype") ;

      let _, functions = get "/api/functions" in
      Batch.contains b ~msg:"/api/functions must list Entry" ~haystack:functions {|"name":"Entry"|} ;
      Batch.contains b ~msg:"/api/functions must list helper" ~haystack:functions
        {|"name":"helper"|} ;

      let _, modules = get "/api/modules" in
      Batch.contains b ~msg:"/api/modules must derive a module from svc/main.go" ~haystack:modules
        "svc" ;

      let status, _ = get "/api/nope" in
      Batch.eq_string b ~msg:"an unknown route must be 404, not a 200 with a plausible body" status
        "404") ;
  Lwt.return_unit
