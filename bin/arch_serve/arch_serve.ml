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

(* ── file_path → synthesized module_id ────────────────────────────────── *)
(*
   The cli schema has no modules table. We synthesize module IDs by ranking
   DISTINCT file_path values alphabetically (1-based).
*)

let build_file_path_array db =
  let paths = query_rows db
    "SELECT DISTINCT file_path FROM functions ORDER BY file_path"
    (fun _ -> ()) (fun stmt -> col_text stmt 0) in
  Array.of_list paths

let file_path_mod_id fp_arr fp =
  (* Linear scan: fp_arr is sorted and typically small (< a few hundred) *)
  let n = Array.length fp_arr in
  let rec go i = if i >= n then 0 else if fp_arr.(i) = fp then i + 1 else go (i + 1) in
  go 0

let mod_id_file_path fp_arr id =
  if id >= 1 && id <= Array.length fp_arr then Some fp_arr.(id - 1) else None

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
(*
   cli schema: calls uses (caller_name, callee_name) strings, no kind column.
   BFS traverses by name; final step fetches IDs from functions table.
*)

let neighborhood_bfs db fp_arr seed_name depth =
  let seed_exists = ref false in
  let stmt = Sqlite3.prepare db "SELECT 1 FROM functions WHERE name = ? LIMIT 1" in
  Sqlite3.bind_text stmt 1 seed_name |> ignore;
  if Sqlite3.step stmt = Sqlite3.Rc.ROW then seed_exists := true;
  Sqlite3.finalize stmt |> ignore;
  if not !seed_exists then None
  else begin
    let visited    = Hashtbl.create 64 in  (* name → () *)
    let edges_seen = Hashtbl.create 64 in  (* (caller_name, callee_name) → call_site *)
    let frontier   = ref [seed_name] in
    let truncated  = ref false in
    Hashtbl.add visited seed_name ();
    for _ = 1 to depth do
      if !frontier <> [] && not !truncated then begin
        let next = ref [] in
        List.iter (fun node_name ->
          (* Outgoing: node_name → callee *)
          let stmt_out = Sqlite3.prepare db
            "SELECT DISTINCT callee_name, call_site FROM calls WHERE caller_name = ?" in
          Sqlite3.bind_text stmt_out 1 node_name |> ignore;
          while Sqlite3.step stmt_out = Sqlite3.Rc.ROW do
            let callee_name = col_text stmt_out 0 in
            let call_site   = col_text stmt_out 1 in
            let ek = (node_name, callee_name) in
            if not (Hashtbl.mem edges_seen ek) then begin
              Hashtbl.add edges_seen ek call_site;
              if not (Hashtbl.mem visited callee_name) then begin
                Hashtbl.add visited callee_name ();
                if Hashtbl.length visited >= 2000 then truncated := true
                else next := callee_name :: !next
              end
            end
          done;
          Sqlite3.finalize stmt_out |> ignore;
          (* Incoming: caller → node_name *)
          let stmt_in = Sqlite3.prepare db
            "SELECT DISTINCT caller_name, call_site FROM calls WHERE callee_name = ?" in
          Sqlite3.bind_text stmt_in 1 node_name |> ignore;
          while Sqlite3.step stmt_in = Sqlite3.Rc.ROW do
            let caller_name = col_text stmt_in 0 in
            let call_site   = col_text stmt_in 1 in
            let ek = (caller_name, node_name) in
            if not (Hashtbl.mem edges_seen ek) then begin
              Hashtbl.add edges_seen ek call_site;
              if not (Hashtbl.mem visited caller_name) then begin
                Hashtbl.add visited caller_name ();
                if Hashtbl.length visited >= 2000 then truncated := true
                else next := caller_name :: !next
              end
            end
          done;
          Sqlite3.finalize stmt_in |> ignore;
        ) !frontier;
        frontier := !next
      end
    done;
    (* Fetch metadata only for names that exist in functions (callee_name may be external) *)
    let names = Hashtbl.fold (fun n () acc -> n :: acc) visited [] in
    let placeholders = String.concat "," (List.map (fun _ -> "?") names) in
    let node_rows = ref [] in
    let name_to_id = Hashtbl.create 64 in
    let stmt_nodes = Sqlite3.prepare db
      (Printf.sprintf
         "SELECT id, name, file_path, exported, comment_quality_score, summary \
          FROM functions WHERE name IN (%s)" placeholders) in
    List.iteri (fun i n -> Sqlite3.bind_text stmt_nodes (i + 1) n |> ignore) names;
    while Sqlite3.step stmt_nodes = Sqlite3.Rc.ROW do
      let id        = col_int stmt_nodes 0 in
      let name      = col_text stmt_nodes 1 in
      let file_path = col_text stmt_nodes 2 in
      let mod_id    = file_path_mod_id fp_arr file_path in
      Hashtbl.replace name_to_id name id;
      node_rows := (`Assoc [
        "id",                    `Int id;
        "name",                  `String name;
        "module_id",             `Int mod_id;
        "exposed",               json_bool (col_bool stmt_nodes 3);
        "comment_quality_score", col_float_or_null stmt_nodes 4;
        "intent",                col_string_or_null stmt_nodes 5;
      ]) :: !node_rows
    done;
    Sqlite3.finalize stmt_nodes |> ignore;
    let nodes = List.rev !node_rows in
    let edges = Hashtbl.fold (fun (caller_name, callee_name) call_site acc ->
      match
        Hashtbl.find_opt name_to_id caller_name,
        Hashtbl.find_opt name_to_id callee_name
      with
      | Some caller_id, Some callee_id ->
        (`Assoc [
          "caller_id", `Int caller_id;
          "callee_id", `Int callee_id;
          "kind",      `Null;
          "call_site", (if call_site = "" then `Null else `String call_site);
        ]) :: acc
      | _ -> acc
    ) edges_seen [] in
    Some (`Assoc [
      "nodes",     `List nodes;
      "edges",     `List edges;
      "truncated", `Bool !truncated;
    ])
  end

(* ── BFS: reachability ──────────────────────────────────────────────────── *)
(*
   cli schema: no kind column — all calls treated as MUST.
   BFS by name; path returned as integer IDs for SPA highlighting.
*)

let name_to_id db name =
  let r = ref None in
  let stmt = Sqlite3.prepare db "SELECT id FROM functions WHERE name = ? LIMIT 1" in
  Sqlite3.bind_text stmt 1 name |> ignore;
  if Sqlite3.step stmt = Sqlite3.Rc.ROW then r := Some (col_int stmt 0);
  Sqlite3.finalize stmt |> ignore;
  !r

let reaches_bfs db from_name to_name =
  match name_to_id db from_name, name_to_id db to_name with
  | None, _ -> `From_not_found
  | _, None -> `To_not_found
  | Some from_id, Some _to_id ->
    let visited = Hashtbl.create 64 in
    Hashtbl.add visited from_name ();
    let queue = Queue.create () in
    Queue.add (from_name, [from_name]) queue;
    let result = ref `Not_found in
    (try
       while not (Queue.is_empty queue) do
         let (current, path) = Queue.pop queue in
         if current = to_name then begin
           result := `Found path;
           raise Exit
         end;
         let stmt = Sqlite3.prepare db
           "SELECT DISTINCT callee_name FROM calls WHERE caller_name = ?" in
         Sqlite3.bind_text stmt 1 current |> ignore;
         while Sqlite3.step stmt = Sqlite3.Rc.ROW do
           let callee_name = col_text stmt 0 in
           if not (Hashtbl.mem visited callee_name) then begin
             Hashtbl.add visited callee_name ();
             Queue.add (callee_name, path @ [callee_name]) queue
           end
         done;
         Sqlite3.finalize stmt |> ignore
       done
     with Exit -> ());
    match !result with
    | `Found name_path ->
      (* Convert names to IDs; skip any not indexed in functions *)
      let id_path = List.filter_map (name_to_id db) name_path in
      (* Restore from_id as first element if name_to_id dropped it *)
      let id_path = if id_path = [] then [from_id] else id_path in
      `Found id_path
    | _ -> `Not_found

(* ── API request handler ────────────────────────────────────────────────── *)

let handle_request db fp_arr req =
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
    (* Synthesize modules from DISTINCT file_path — cli schema has no modules table *)
    let rows = Array.to_list (Array.mapi (fun i fp ->
      `Assoc [
        "id",   `Int (i + 1);
        "path", `String fp;
      ]
    ) fp_arr) in
    respond_json (`List rows)

  | "/api/functions" ->
    let clauses = ref [] in
    let binds   = ref [] in
    (match qp "module_id" with
     | Some mid ->
       let mid_int = (try int_of_string mid with _ -> -1) in
       (match mod_id_file_path fp_arr mid_int with
        | Some fp -> clauses := "file_path = ?" :: !clauses; binds := `Text fp :: !binds
        | None    -> clauses := "1 = 0" :: !clauses)  (* no match → empty result *)
     | None -> ());
    (match qp "exposed" with
     | Some "1" | Some "true"  -> clauses := "exported = 1" :: !clauses
     | Some "0" | Some "false" -> clauses := "exported = 0" :: !clauses
     | _ -> ());
    (match qp "min_score" with
     | Some s ->
       let score = (try int_of_string s with _ -> 0) in
       clauses := "COALESCE(comment_quality_score, 0) >= ?" :: !clauses;
       binds := `Int score :: !binds
     | None -> ());
    let where    = if !clauses = [] then "" else " WHERE " ^ String.concat " AND " (List.rev !clauses) in
    let sql      = "SELECT id, file_path, name, signature, line_start, line_end, exported, \
                    comment_quality_score, summary, has_pre, has_post, has_violators \
                    FROM functions" ^ where ^ " ORDER BY name" in
    let bind_list = List.rev !binds in
    let rows = query_rows db sql
      (fun stmt ->
        List.iteri (fun i v ->
          (match v with
           | `Int n  -> Sqlite3.bind_int  stmt (i + 1) n  |> ignore
           | `Text s -> Sqlite3.bind_text stmt (i + 1) s  |> ignore)
        ) bind_list)
      (fun stmt ->
        let fp     = col_text stmt 1 in
        let mod_id = file_path_mod_id fp_arr fp in
        `Assoc [
          "id",                    `Int (col_int stmt 0);
          "module_id",             `Int mod_id;
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
    let name  = Option.value (qp "name") ~default:"" in
    let depth = (match qp "depth" with Some s -> (try int_of_string s with _ -> 2) | None -> 2) in
    let depth = max 1 (min depth 5) in
    if name = "" then respond_error `Bad_request "missing 'name' parameter"
    else begin
      match neighborhood_bfs db fp_arr name depth with
      | None      -> respond_error `Not_found (Printf.sprintf "unknown function: %s" name)
      | Some json -> respond_json json
    end

  | "/api/graph/module" ->
    (match qp "module_id" with
     | None -> respond_error `Bad_request "missing 'module_id' parameter"
     | Some mid_s ->
       let mid = (try int_of_string mid_s with _ -> -1) in
       (match mod_id_file_path fp_arr mid with
        | None ->
          respond_error `Not_found (Printf.sprintf "unknown module_id: %s" mid_s)
        | Some fp ->
          let nodes = query_rows db
            "SELECT id, name, file_path, exported, comment_quality_score, summary \
             FROM functions WHERE file_path = ? ORDER BY name"
            (fun stmt -> Sqlite3.bind_text stmt 1 fp |> ignore)
            (fun stmt ->
              let fp2    = col_text stmt 2 in
              let mod_id = file_path_mod_id fp_arr fp2 in
              `Assoc [
                "id",                    `Int (col_int stmt 0);
                "name",                  `String (col_text stmt 1);
                "module_id",             `Int mod_id;
                "exposed",               json_bool (col_bool stmt 3);
                "comment_quality_score", col_float_or_null stmt 4;
                "intent",                col_string_or_null stmt 5;
              ]) in
          (* Intra-module edges: join calls against functions on both sides,
             filtering to only calls where both caller and callee are in this file *)
          let edges = query_rows db
            "SELECT f1.id, f2.id, c.call_site \
             FROM calls c \
             JOIN functions f1 ON f1.name = c.caller_name AND f1.file_path = ? \
             JOIN functions f2 ON f2.name = c.callee_name AND f2.file_path = ?"
            (fun stmt ->
              Sqlite3.bind_text stmt 1 fp |> ignore;
              Sqlite3.bind_text stmt 2 fp |> ignore)
            (fun stmt ->
              `Assoc [
                "caller_id", `Int (col_int stmt 0);
                "callee_id", `Int (col_int stmt 1);
                "kind",      `Null;
                "call_site", col_string_or_null stmt 2;
              ]) in
          respond_json (`Assoc ["nodes", `List nodes; "edges", `List edges])))

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
    let fp_arr = build_file_path_array db in
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
        ~callback:(fun _conn req _body -> handle_request db fp_arr req) () in
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
