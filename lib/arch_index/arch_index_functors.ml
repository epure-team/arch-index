open Typedtree

let selected_inputs paths = List.sort_uniq String.compare paths

type application_kind = Apply | Apply_unit

type occurrence = {
  ordinal : int;
  application_kind : application_kind;
  location : string;
  head : string;
  argument : string;
  diagnostics : string;
}

let json_string s = Yojson.Safe.to_string (`String s)

let path_contains_apply path =
  let rec loop = function
    | Path.Pident _ -> false
    | Path.Pdot (p, _) -> loop p
    | Path.Papply _ -> true
    | Path.Pextra_ty (p, _) -> loop p
  in
  loop path

let path_descriptor path lid =
  Printf.sprintf
    {|{"kind":"path","compiler":%s,"source":%s,"contains_apply":%s}|}
    (json_string (Path.name path))
    (json_string (Format.asprintf "%a" Pprintast.longident lid.Location.txt))
    (string_of_bool (path_contains_apply path))

let location_json loc =
  let s = loc.Location.loc_start and e = loc.Location.loc_end in
  let scol = s.Lexing.pos_cnum - s.Lexing.pos_bol in
  let ecol = e.Lexing.pos_cnum - e.Lexing.pos_bol in
  let valid =
    s.Lexing.pos_fname <> "" && s.Lexing.pos_fname = e.Lexing.pos_fname
    && s.Lexing.pos_lnum >= 1 && e.Lexing.pos_lnum >= 1 && scol >= 0 && ecol >= 0
    && (s.Lexing.pos_lnum < e.Lexing.pos_lnum
       || (s.Lexing.pos_lnum = e.Lexing.pos_lnum && scol <= ecol))
  in
  if valid then
    ( Printf.sprintf
        {|{"file":%s,"start_line":%d,"start_col":%d,"end_line":%d,"end_col":%d,"ghost":%s}|}
        (json_string s.Lexing.pos_fname) s.Lexing.pos_lnum scol e.Lexing.pos_lnum ecol
        (string_of_bool loc.Location.loc_ghost),
      false )
  else
    ( Printf.sprintf
        {|{"file":null,"start_line":null,"start_col":null,"end_line":null,"end_col":null,"ghost":%s}|}
        (string_of_bool loc.Location.loc_ghost),
      true )

let collect structure =
  let next = ref 0 and rows = ref [] in
  let fresh () = incr next ; !next in
  let rec strip_constraint = function
    | `Constraint d -> strip_constraint d
    | d -> d
  and descriptor_json = function
    | `Path (p, lid) -> path_descriptor p lid
    | `Structure -> {|{"kind":"structure"}|}
    | `Functor (parameter, name) ->
        Printf.sprintf {|{"kind":"functor","parameter":%s,"name":%s}|}
          (json_string parameter)
          (match name with None -> "null" | Some n -> json_string n)
    | `Unpack -> {|{"kind":"unpack"}|}
    | `Constraint d -> Printf.sprintf {|{"kind":"constraint","expression":%s}|} (descriptor_json d)
    | `Application n -> Printf.sprintf {|{"kind":"application","ordinal":%d}|} n
    | `Unit -> {|{"kind":"unit"}|}
  and walk_module self m =
    match m.mod_desc with
    | Tmod_apply (head, arg, _) ->
        let ordinal = fresh () in
        let head_d = walk_module self head in
        let arg_d = walk_module self arg in
        add_row ordinal Apply m.mod_loc head_d arg_d ;
        `Application ordinal
    | Tmod_apply_unit head ->
        let ordinal = fresh () in
        let head_d = walk_module self head in
        add_row ordinal Apply_unit m.mod_loc head_d `Unit ;
        `Application ordinal
    | Tmod_constraint (inner, _, constraint_, _) ->
        let inner_descriptor = walk_module self inner in
        (match constraint_ with
        | Tmodtype_implicit -> ()
        | Tmodtype_explicit module_type -> self.Tast_iterator.module_type self module_type) ;
        `Constraint inner_descriptor
    | Tmod_ident (path, lid) -> `Path (path, lid)
    | Tmod_structure _ ->
        Tast_iterator.default_iterator.module_expr self m ; `Structure
    | Tmod_functor (parameter, _) ->
        Tast_iterator.default_iterator.module_expr self m ;
        (match parameter with
        | Unit -> `Functor ("unit", None)
        | Named (_, name, _) -> `Functor ("named", name.Location.txt))
    | Tmod_unpack _ ->
        Tast_iterator.default_iterator.module_expr self m ; `Unpack
  and add_row ordinal application_kind loc head argument =
    let location, bad_location = location_json loc in
    let diagnostics = ref [] in
    (match strip_constraint head with `Path _ | `Application _ -> () | _ -> diagnostics := "opaque_functor_head" :: !diagnostics) ;
    (match strip_constraint argument with `Structure -> diagnostics := "anonymous_argument" :: !diagnostics | _ -> ()) ;
    (match strip_constraint head, strip_constraint argument with
    | `Unpack, _ | _, `Unpack -> diagnostics := "unpacked_expression" :: !diagnostics
    | _ -> ()) ;
    if bad_location then diagnostics := "unusable_location" :: !diagnostics ;
    let diagnostics = List.sort_uniq String.compare !diagnostics in
    rows :=
      { ordinal; application_kind; location; head = descriptor_json head;
        argument = descriptor_json argument;
        diagnostics = Yojson.Safe.to_string (`List (List.map (fun s -> `String s) diagnostics)) }
      :: !rows
  in
  let iterator =
    { Tast_iterator.default_iterator with
      module_expr = (fun self m -> ignore (walk_module self m)) }
  in
  iterator.structure iterator structure ;
  List.sort (fun a b -> Int.compare a.ordinal b.ordinal) !rows

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> failwith (Printf.sprintf "functor catalogue SQL: %s: %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))

let quote s = "'" ^ String.concat "''" (String.split_on_char '\'' s) ^ "'"

let store_collected db ~producer_run_id ~artifact ~source ~compiler_unit ~module_id occurrences =
  exec db "SAVEPOINT functor_catalogue_input" ;
  try
    let count = List.length occurrences in
    exec db (Printf.sprintf
       "INSERT INTO functor_catalogue_inputs(producer_run_id,artifact,source,compiler_unit,module_id,outcome,expected_applications) VALUES(%d,%s,%s,%s,%d,'collected',%d)"
       producer_run_id (quote artifact) (quote source) (quote compiler_unit) module_id count) ;
    List.iter (fun o -> exec db (Printf.sprintf
           "INSERT INTO functor_applications(producer_run_id,artifact,ordinal,application_kind,location,head,argument,diagnostics) VALUES(%d,%s,%d,%s,%s,%s,%s,%s)"
           producer_run_id (quote artifact) o.ordinal
           (quote (match o.application_kind with Apply -> "apply" | Apply_unit -> "apply_unit"))
           (quote o.location) (quote o.head) (quote o.argument) (quote o.diagnostics))) occurrences ;
    exec db "RELEASE functor_catalogue_input"
  with exn ->
    ignore (Sqlite3.exec db "ROLLBACK TO functor_catalogue_input") ;
    ignore (Sqlite3.exec db "RELEASE functor_catalogue_input") ;
    raise exn

let store_outcome db ~producer_run_id ~artifact ~outcome =
  exec db (Printf.sprintf
    "INSERT INTO functor_catalogue_inputs(producer_run_id,artifact,outcome,expected_applications) VALUES(%d,%s,%s,0)"
    producer_run_id (quote artifact) (quote outcome))

let clear_contract db =
  ignore (Sqlite3.exec db
    "DELETE FROM comment_db_meta WHERE key='functor_catalogue_contract'")

let scalar db sql =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    match Sqlite3.step stmt with Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0 | _ -> -1)

let finalize_contract db ~selected_inputs =
  let complete =
    selected_inputs > 0
    && scalar db "SELECT count(*) FROM functor_catalogue_runs" = 1
    && scalar db (Printf.sprintf "SELECT count(*) FROM functor_catalogue_runs r JOIN producer_runs p ON p.id=r.producer_run_id WHERE r.selected_inputs=%d" selected_inputs) = 1
    && scalar db "SELECT count(*) FROM functor_catalogue_inputs" = selected_inputs
    && scalar db "SELECT count(*) FROM functor_catalogue_inputs i JOIN functor_catalogue_runs r ON r.producer_run_id=i.producer_run_id JOIN modules m ON m.id=i.module_id AND m.path=i.source WHERE i.outcome='collected' AND i.source IS NOT NULL AND i.source<>'' AND i.compiler_unit IS NOT NULL AND i.compiler_unit<>''" = selected_inputs
    && scalar db "SELECT COALESCE(sum(expected_applications),0) FROM functor_catalogue_inputs"
       = scalar db "SELECT count(*) FROM functor_applications"
    && scalar db "SELECT count(*) FROM functor_catalogue_inputs i WHERE i.expected_applications<>(SELECT count(*) FROM functor_applications a WHERE a.producer_run_id=i.producer_run_id AND a.artifact=i.artifact)" = 0
    && scalar db "SELECT count(*) FROM functor_applications a LEFT JOIN functor_catalogue_inputs i ON i.producer_run_id=a.producer_run_id AND i.artifact=a.artifact WHERE i.artifact IS NULL" = 0
  in
  if complete then
    exec db "INSERT OR REPLACE INTO comment_db_meta(key,value) VALUES('functor_catalogue_contract','v1')" ;
  complete
