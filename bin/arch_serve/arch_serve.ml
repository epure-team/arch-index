open Cmdliner

let index_html = [%blob "static/index.html"]
let app_js     = [%blob "static/app.js"]
let style_css  = [%blob "static/style.css"]
let d3_js      = [%blob "static/d3.min.js"]

(* ── SQLite helpers ────────────────────────────────────────────────────── *)

let json_bool b = `Bool b

let col_text stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.TEXT s -> s
  | _ -> ""

let col_int stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> Int64.to_int n
  | _ -> 0

let col_float_or_null stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> `Float (Int64.to_float n)
  | Sqlite3.Data.FLOAT f -> `Float f
  | _ -> `Null

let col_bool stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> n <> 0L
  | _ -> false

let col_string_or_null stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.TEXT s -> `String s
  | _ -> `Null

let query_rows db sql bind_fn row_fn =
  let stmt = Sqlite3.prepare db sql in
  bind_fn stmt;
  let rows = ref [] in
  (try
     while Sqlite3.step stmt = Sqlite3.Rc.ROW do
       rows := row_fn stmt :: !rows
     done
   with _ -> ());
  (try Sqlite3.finalize stmt |> ignore with _ -> ());
  List.rev !rows

(* ── HTTP helpers ──────────────────────────────────────────────────────── *)

let json_headers =
  Http.Header.of_list ["Content-Type", "application/json; charset=utf-8"]

let html_headers =
  Http.Header.of_list ["Content-Type", "text/html; charset=utf-8"]

let js_headers =
  Http.Header.of_list ["Content-Type", "application/javascript; charset=utf-8"]

let css_headers =
  Http.Header.of_list ["Content-Type", "text/css; charset=utf-8"]

let respond_json json =
  Cohttp_eio.Server.respond_string
    ~status:`OK
    ~headers:json_headers
    ~body:(Yojson.Safe.to_string json) ()

let respond_error status msg =
  Cohttp_eio.Server.respond_string
    ~status
    ~headers:json_headers
    ~body:(Printf.sprintf {|{"error":%s}|} (Yojson.Safe.to_string (`String msg))) ()

(* ── BFS: bidirectional neighborhood ──────────────────────────────────── *)

let neighborhood_bfs db seed_name depth =
  (* Resolve name → id *)
  let seed_id = ref None in
  let stmt = Sqlite3.prepare db "SELECT id FROM functions WHERE name = ? LIMIT 1" in
  Sqlite3.bind_text stmt 1 seed_name |> ignore;
  if Sqlite3.step stmt = Sqlite3.Rc.ROW then
    seed_id := Some (col_int stmt 0);
  Sqlite3.finalize stmt |> ignore;
  match !seed_id with
  | None -> None
  | Some seed ->
    let visited = Hashtbl.create 64 in
    let edges_seen = Hashtbl.create 64 in
    let frontier = ref [seed] in
    let truncated = ref false in
    Hashtbl.add visited seed ();
    for _ = 1 to depth do
      if !frontier <> [] && not !truncated then begin
        let next = ref [] in
        List.iter (fun node_id ->
          (* Outgoing edges *)
          let stmt_out = Sqlite3.prepare db
            "SELECT callee_id, kind, call_site FROM calls WHERE caller_id = ?" in
          Sqlite3.bind_int stmt_out 1 node_id |> ignore;
          while Sqlite3.step stmt_out = Sqlite3.Rc.ROW do
            let callee_id = col_int stmt_out 0 in
            let kind = col_text stmt_out 1 in
            let call_site = col_text stmt_out 2 in
            let ek = (node_id, callee_id, kind) in
            if not (Hashtbl.mem edges_seen ek) then begin
              Hashtbl.add edges_seen ek call_site;
              if not (Hashtbl.mem visited callee_id) then begin
                Hashtbl.add visited callee_id ();
                if Hashtbl.length visited >= 2000 then truncated := true
                else next := callee_id :: !next
              end
            end
          done;
          Sqlite3.finalize stmt_out |> ignore;
          (* Incoming edges *)
          let stmt_in = Sqlite3.prepare db
            "SELECT caller_id, kind, call_site FROM calls WHERE callee_id = ?" in
          Sqlite3.bind_int stmt_in 1 node_id |> ignore;
          while Sqlite3.step stmt_in = Sqlite3.Rc.ROW do
            let caller_id = col_int stmt_in 0 in
            let kind = col_text stmt_in 1 in
            let call_site = col_text stmt_in 2 in
            let ek = (caller_id, node_id, kind) in
            if not (Hashtbl.mem edges_seen ek) then begin
              Hashtbl.add edges_seen ek call_site;
              if not (Hashtbl.mem visited caller_id) then begin
                Hashtbl.add visited caller_id ();
                if Hashtbl.length visited >= 2000 then truncated := true
                else next := caller_id :: !next
              end
            end
          done;
          Sqlite3.finalize stmt_in |> ignore;
        ) !frontier;
        frontier := !next
      end
    done;
    (* Fetch node metadata *)
    let ids = Hashtbl.fold (fun id () acc -> id :: acc) visited [] in
    let id_list = String.concat "," (List.map string_of_int ids) in
    let nodes = query_rows db
      (Printf.sprintf "SELECT id, name, module_id, exposed, comment_quality_score, intent \
                       FROM functions WHERE id IN (%s)" id_list)
      (fun _ -> ())
      (fun stmt ->
        `Assoc [
          "id",                    `Int (col_int stmt 0);
          "name",                  `String (col_text stmt 1);
          "module_id",             `Int (col_int stmt 2);
          "exposed",               json_bool (col_bool stmt 3);
          "comment_quality_score", col_float_or_null stmt 4;
          "intent",                col_string_or_null stmt 5;
        ]) in
    let edges = Hashtbl.fold (fun (caller_id, callee_id, kind) call_site acc ->
      (`Assoc [
        "caller_id", `Int caller_id;
        "callee_id", `Int callee_id;
        "kind",      (if kind = "" then `Null else `String kind);
        "call_site", (if call_site = "" then `Null else `String call_site);
      ]) :: acc
    ) edges_seen [] in
    Some (`Assoc [
      "nodes",     `List nodes;
      "edges",     `List edges;
      "truncated", `Bool !truncated;
    ])

(* ── BFS: MUST-only reaches ────────────────────────────────────────────── *)

let reaches_bfs db from_name to_name =
  let resolve name =
    let r = ref None in
    let stmt = Sqlite3.prepare db "SELECT id FROM functions WHERE name = ? LIMIT 1" in
    Sqlite3.bind_text stmt 1 name |> ignore;
    if Sqlite3.step stmt = Sqlite3.Rc.ROW then r := Some (col_int stmt 0);
    Sqlite3.finalize stmt |> ignore;
    !r
  in
  match resolve from_name, resolve to_name with
  | None, _ -> `From_not_found
  | _, None -> `To_not_found
  | Some from_id, Some to_id ->
    let visited = Hashtbl.create 64 in
    Hashtbl.add visited from_id ();
    let queue = Queue.create () in
    Queue.add (from_id, [from_id]) queue;
    let result = ref `Not_found in
    (try
       while not (Queue.is_empty queue) do
         let (current, path) = Queue.pop queue in
         if current = to_id then begin
           result := `Found path;
           raise Exit
         end;
         let stmt = Sqlite3.prepare db
           "SELECT callee_id FROM calls WHERE caller_id = ? \
            AND (kind = 'MUST' OR kind IS NULL)" in
         Sqlite3.bind_int stmt 1 current |> ignore;
         while Sqlite3.step stmt = Sqlite3.Rc.ROW do
           let callee_id = col_int stmt 0 in
           if not (Hashtbl.mem visited callee_id) then begin
             Hashtbl.add visited callee_id ();
             Queue.add (callee_id, path @ [callee_id]) queue
           end
         done;
         Sqlite3.finalize stmt |> ignore
       done
     with Exit -> ());
    !result

(* ── API request handler ────────────────────────────────────────────────── *)

let handle_request db req =
  let resource = req.Http.Request.resource in
  let uri = Uri.of_string resource in
  let path = Uri.path uri in
  let qp key = Uri.get_query_param uri key in
  match path with
  | "/" ->
    Cohttp_eio.Server.respond_string ~status:`OK ~headers:html_headers ~body:index_html ()
  | "/static/app.js" ->
    Cohttp_eio.Server.respond_string ~status:`OK ~headers:js_headers ~body:app_js ()
  | "/static/style.css" ->
    Cohttp_eio.Server.respond_string ~status:`OK ~headers:css_headers ~body:style_css ()
  | "/static/d3.min.js" ->
    Cohttp_eio.Server.respond_string ~status:`OK ~headers:js_headers ~body:d3_js ()

  | "/api/modules" ->
    let rows = query_rows db
      "SELECT id, path, lines, has_mli FROM modules ORDER BY path"
      (fun _ -> ())
      (fun stmt ->
        `Assoc [
          "id",      `Int (col_int stmt 0);
          "path",    `String (col_text stmt 1);
          "lines",   `Int (col_int stmt 2);
          "has_mli", json_bool (col_bool stmt 3);
        ]) in
    respond_json (`List rows)

  | "/api/functions" ->
    let clauses = ref [] in
    let binds = ref [] in
    (match qp "module_id" with
     | Some mid -> clauses := "module_id = ?" :: !clauses; binds := `Int (try int_of_string mid with _ -> -1) :: !binds
     | None -> ());
    (match qp "exposed" with
     | Some "1" | Some "true" -> clauses := "exposed = 1" :: !clauses
     | Some "0" | Some "false" -> clauses := "exposed = 0" :: !clauses
     | _ -> ());
    (match qp "min_score" with
     | Some s ->
       let score = (try int_of_string s with _ -> 0) in
       clauses := "COALESCE(comment_quality_score, 0) >= ?" :: !clauses;
       binds := `Int score :: !binds
     | None -> ());
    let where = if !clauses = [] then "" else " WHERE " ^ String.concat " AND " (List.rev !clauses) in
    let sql = "SELECT id, module_id, name, signature, line_start, line_end, exposed, \
               comment_quality_score, intent, has_pre, has_post, has_violators \
               FROM functions" ^ where ^ " ORDER BY name" in
    let bind_list = List.rev !binds in
    let rows = query_rows db sql
      (fun stmt ->
        List.iteri (fun i v ->
          match v with
          | `Int n -> Sqlite3.bind_int stmt (i + 1) n |> ignore
          | _ -> ()
        ) bind_list)
      (fun stmt ->
        `Assoc [
          "id",                    `Int (col_int stmt 0);
          "module_id",             `Int (col_int stmt 1);
          "name",                  `String (col_text stmt 2);
          "signature",             col_string_or_null stmt 3;
          "line_start",            `Int (col_int stmt 4);
          "line_end",              `Int (col_int stmt 5);
          "exposed",               json_bool (col_bool stmt 6);
          "comment_quality_score", col_float_or_null stmt 7;
          "intent",                col_string_or_null stmt 8;
          "has_pre",               json_bool (col_bool stmt 9);
          "has_post",              json_bool (col_bool stmt 10);
          "has_violators",         json_bool (col_bool stmt 11);
        ]) in
    respond_json (`List rows)

  | "/api/graph/neighborhood" ->
    let name = Option.value (qp "name") ~default:"" in
    let depth = (match qp "depth" with Some s -> (try int_of_string s with _ -> 2) | None -> 2) in
    let depth = max 1 (min depth 5) in
    if name = "" then respond_error `Bad_request "missing 'name' parameter"
    else begin
      match neighborhood_bfs db name depth with
      | None -> respond_error `Not_found (Printf.sprintf "unknown function: %s" name)
      | Some json -> respond_json json
    end

  | "/api/graph/module" ->
    (match qp "module_id" with
     | None -> respond_error `Bad_request "missing 'module_id' parameter"
     | Some mid_s ->
       let mid = (try int_of_string mid_s with _ -> -1) in
       let nodes = query_rows db
         "SELECT id, name, module_id, exposed, comment_quality_score, intent \
          FROM functions WHERE module_id = ? ORDER BY name"
         (fun stmt -> Sqlite3.bind_int stmt 1 mid |> ignore)
         (fun stmt ->
           `Assoc [
             "id",                    `Int (col_int stmt 0);
             "name",                  `String (col_text stmt 1);
             "module_id",             `Int (col_int stmt 2);
             "exposed",               json_bool (col_bool stmt 3);
             "comment_quality_score", col_float_or_null stmt 4;
             "intent",                col_string_or_null stmt 5;
           ]) in
       let ids = List.filter_map (function
         | `Assoc l -> (match List.assoc_opt "id" l with Some (`Int i) -> Some i | _ -> None)
         | _ -> None) nodes in
       let edges =
         if ids = [] then []
         else
           let id_list = String.concat "," (List.map string_of_int ids) in
           query_rows db
             (Printf.sprintf "SELECT caller_id, callee_id, kind, call_site FROM calls \
                              WHERE caller_id IN (%s) AND callee_id IN (%s)" id_list id_list)
             (fun _ -> ())
             (fun stmt ->
               `Assoc [
                 "caller_id", `Int (col_int stmt 0);
                 "callee_id", `Int (col_int stmt 1);
                 "kind",      col_string_or_null stmt 2;
                 "call_site", col_string_or_null stmt 3;
               ]) in
       respond_json (`Assoc ["nodes", `List nodes; "edges", `List edges]))

  | "/api/reaches" ->
    let from_name = Option.value (qp "from") ~default:"" in
    let to_name   = Option.value (qp "to")   ~default:"" in
    if from_name = "" || to_name = "" then
      respond_error `Bad_request "missing 'from' or 'to' parameter"
    else begin
      match reaches_bfs db from_name to_name with
      | `From_not_found ->
        respond_error `Not_found (Printf.sprintf "unknown function: %s" from_name)
      | `To_not_found ->
        respond_error `Not_found (Printf.sprintf "unknown function: %s" to_name)
      | `Found path ->
        respond_json (`Assoc [
          "result", `String "PATH_EXISTS";
          "path",   `List (List.map (fun id -> `Int id) path);
        ])
      | `Not_found ->
        respond_json (`Assoc [
          "result", `String "NO_MUST_PATH";
          "path",   `List [];
        ])
    end

  | _ ->
    respond_error `Not_found "not found"

(* ── Server entry point ─────────────────────────────────────────────────── *)

let serve db_path port =
  Eio_posix.run (fun env ->
    let db =
      match Sqlite3.db_open ~mode:`READONLY db_path with
      | db ->
        (match Sqlite3.exec db "SELECT 1" with
         | Sqlite3.Rc.OK -> db
         | rc ->
           Printf.eprintf "arch-serve: cannot open database: %s: %s\n%!"
             db_path (Sqlite3.Rc.to_string rc);
           exit 1)
      | exception Sqlite3.Error msg ->
        Printf.eprintf "arch-serve: cannot open database: %s: %s\n%!" db_path msg;
        exit 1
      | exception _ ->
        Printf.eprintf "arch-serve: cannot open database: %s: No such file or directory\n%!" db_path;
        exit 1
    in
    let stop_p, stop_r = Eio.Promise.create () in
    let resolve_stop () =
      try Eio.Promise.resolve stop_r () with Invalid_argument _ -> ()
    in
    Sys.set_signal Sys.sigint  (Sys.Signal_handle (fun _ -> resolve_stop ()));
    Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> resolve_stop ()));
    Eio.Switch.run (fun sw ->
      let addr = `Tcp (Eio.Net.Ipaddr.V4.loopback, port) in
      let socket = Eio.Net.listen ~sw ~backlog:5 ~reuse_addr:true
        (Eio.Stdenv.net env) addr in
      Printf.printf "Serving at http://localhost:%d — press Ctrl-C to stop\n%!" port;
      let server = Cohttp_eio.Server.make
        ~callback:(fun _conn req _body -> handle_request db req) () in
      Cohttp_eio.Server.run socket server ~stop:stop_p ~on_error:(fun _ -> ());
      Sqlite3.db_close db |> ignore))

(* ── CLI ────────────────────────────────────────────────────────────────── *)

let db_arg =
  Arg.(required & pos 0 (some string) None &
       info [] ~docv:"DB" ~doc:"Path to SQLite architecture DB")

let port_arg =
  Arg.(value & opt int 7371 &
       info ["port"; "p"] ~docv:"PORT" ~doc:"HTTP port (default 7371)")

let serve_cmd =
  let doc = "Serve call-graph SPA from a SQLite architecture DB" in
  Cmd.v (Cmd.info "arch-serve" ~doc)
    Term.(const serve $ db_arg $ port_arg)

let () = exit (Cmd.eval serve_cmd)
