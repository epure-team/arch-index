open Typedtree

type formal_kind = Named | Unit

type formal = {
  position : int;
  kind : formal_kind;
  binder_key : string option;
  name : string option;
}

type declaration = {
  declaration_key : string;
  name : string;
  location : string;
  formals : formal list;
}

type result = {
  ordinal : int;
  status : string;
  reason : string option;
  declaration_key : string option;
  formal_position : int option;
  head_application_ordinal : int option;
  actual_root_key : string option;
}

type collection = {
  declarations : declaration list;
  results : result list;
}

type matched_actual = {
  application_ordinal : int;
  declaration_key : string;
  formal_position : int;
  formal_key : string;
  formal_id : Ident.t;
  actual_root_key : string;
  actual_path : Path.t;
}

type collection_with_actuals = {
  bindings : collection;
  matched_actuals : matched_actual list;
}

type binder = {
  id : Ident.t;
  name : string;
  expr : module_expr;
  loc : Location.t;
}

let rec peel m =
  match m.mod_desc with Tmod_constraint (inner, _, _, _) -> peel inner | _ -> m

let ident_key id = Ident.unique_name id

let register_named_binder binders id name expr loc =
  match id, name.Location.txt with
  | None, None -> ()
  | Some id, Some name ->
      if name = "" then failwith "functor binding collection: empty binder name" ;
      binders := {id; name; expr; loc} :: !binders
  | Some _, None ->
      failwith "functor binding collection: named binder has no nonempty name"
  | None, Some _ ->
      failwith "functor binding collection: named binder has no identity"

let register_parameter parameters (parameter : functor_parameter) =
  match parameter with
  | Unit | Named (None, _, _) -> ()
  | Named (Some id, _, _) -> parameters := id :: !parameters

let same a b = Ident.same a b

let ensure_unique binders parameters =
  let rec no_duplicate role = function
    | [] -> ()
    | id :: rest ->
        if List.exists (same id) rest then
          failwith ("functor binding collection: duplicate " ^ role ^ " identity") ;
        no_duplicate role rest
  in
  let binder_ids = List.map (fun b -> b.id) binders in
  no_duplicate "binder" binder_ids ;
  no_duplicate "parameter" parameters ;
  if List.exists (fun id -> List.exists (same id) parameters) binder_ids then
    failwith "functor binding collection: binder/parameter identity collision"

let preindex structure =
  let binders = ref [] and parameters = ref [] in
  let iterator =
    { Tast_iterator.default_iterator with
      module_binding =
        (fun self mb ->
          register_named_binder binders mb.mb_id mb.mb_name mb.mb_expr mb.mb_loc ;
          Tast_iterator.default_iterator.module_binding self mb);
      expr =
        (fun self expr ->
          (match expr.exp_desc with
          | Texp_letmodule (id, name, _, rhs, _) ->
              register_named_binder binders id name rhs rhs.mod_loc
          | _ -> ()) ;
          Tast_iterator.default_iterator.expr self expr);
      module_expr =
        (fun self m ->
          (match m.mod_desc with Tmod_functor (p, _) -> register_parameter parameters p | _ -> ()) ;
          Tast_iterator.default_iterator.module_expr self m);
      module_type =
        (fun self m ->
          (match m.mty_desc with Tmty_functor (p, _) -> register_parameter parameters p | _ -> ()) ;
          Tast_iterator.default_iterator.module_type self m) }
  in
  iterator.structure iterator structure ;
  ensure_unique !binders !parameters ;
  (!binders, !parameters)

let formal position (parameter : functor_parameter) =
  match parameter with
  | Unit -> {position; kind = Unit; binder_key = None; name = None}
  | Named (id, name, _) ->
      { position;
        kind = Named;
        binder_key = Option.map ident_key id;
        name = name.Location.txt }

let telescope expr =
  let rec loop position acc m =
    let m = peel m in
    match m.mod_desc with
    | Tmod_functor (parameter, body) ->
        loop (position + 1) (formal position parameter :: acc) body
    | _ -> List.rev acc
  in
  loop 1 [] expr

let declaration_of_binder binder =
  match (peel binder.expr).mod_desc with
  | Tmod_functor _ ->
      let location, _ = Arch_index_functors.location_json binder.loc in
      Some
        { declaration_key = ident_key binder.id;
          name = binder.name;
          location;
          formals = telescope binder.expr }
  | _ -> None

let find_ident id xs = List.find_opt (fun candidate -> same id candidate.id) xs
let is_parameter id xs = List.exists (same id) xs

let resolution binders parameters head =
  let rec resolve_ident visited id =
    if Ident.persistent id then Error "cross_unit_head"
    else if is_parameter id parameters then Error "parameter_supplied_head"
    else if List.exists (same id) visited then Error "alias_cycle"
    else
      match find_ident id binders with
      | None -> Error "local_declaration_missing"
      | Some binder ->
          (match (peel binder.expr).mod_desc with
          | Tmod_functor _ -> Ok (binder, 1)
          | Tmod_ident (Path.Pident target, _) -> resolve_ident (id :: visited) target
          | _ -> Error "unsupported_alias_rhs")
  and advance application_kind = function
    | Error reason -> Error reason
    | Ok (binder, position) ->
        let formals = telescope binder.expr in
        let supplied = List.nth formals (position - 1) in
        let kind_matches =
          match application_kind, supplied.kind with
          | Arch_index_functors.Apply, Named
          | Arch_index_functors.Apply_unit, Unit -> true
          | _ -> false
        in
        if not kind_matches then Error "formal_kind_mismatch"
        else
          let next = position + 1 in
          if List.nth_opt formals (next - 1) = None then
            Error "curried_result_not_functor"
          else Ok (binder, next)
  and resolve head =
    match (peel head).mod_desc with
    | Tmod_ident (Path.Pident id, _) -> resolve_ident [] id
    | Tmod_ident _ -> Error "unsupported_path"
    | Tmod_apply (inner, _, _) -> advance Arch_index_functors.Apply (resolve inner)
    | Tmod_apply_unit inner -> advance Arch_index_functors.Apply_unit (resolve inner)
    | _ -> Error "unsupported_head_shape"
  in
  resolve head

let rec path_root = function
  | Path.Pident id -> Some id
  | Path.Pdot (path, _) -> path_root path
  | Path.Papply _ | Path.Pextra_ty _ -> None

let rec path_contains_apply = function
  | Path.Pident _ -> false
  | Path.Pdot (path, _) | Path.Pextra_ty (path, _) -> path_contains_apply path
  | Path.Papply _ -> true

let actual_root = function
  | None -> None
  | Some argument ->
      (match (peel argument).mod_desc with
      | Tmod_ident (path, _) when not (path_contains_apply path) ->
          (match path_root path with
          | Some id when not (Ident.persistent id) -> Some (ident_key id)
          | _ -> None)
      | _ -> None)

let actual_identity = function
  | None -> None
  | Some argument ->
      (match (peel argument).mod_desc with
      | Tmod_ident (path, _) when not (path_contains_apply path) ->
          (match path_root path with
          | Some id when not (Ident.persistent id) -> Some (ident_key id, path)
          | _ -> None)
      | _ -> None)

let formal_identity expr position =
  let rec loop current m =
    match (peel m).mod_desc with
    | Tmod_functor (parameter, body) ->
        if current = position then
          (match parameter with Named (Some id, _, _) -> Some id | Unit | Named (None, _, _) -> None)
        else loop (current + 1) body
    | _ -> None
  in
  loop 1 expr

let unresolved ~ordinal ~reason ~head_application_ordinal ~actual_root_key =
  { ordinal;
    status = "unresolved";
    reason = Some reason;
    declaration_key = None;
    formal_position = None;
    head_application_ordinal;
    actual_root_key }

let collect_with_actuals structure =
  let binders, parameters = preindex structure in
  let declarations = List.filter_map declaration_of_binder binders in
  let results = ref [] in
  let matched_actuals = ref [] in
  let on_application ~ordinal ~application_kind ~head_application_ordinal ~head ~argument =
    let actual_root_key = actual_root argument in
    let result =
      match resolution binders parameters head with
      | Error reason -> unresolved ~ordinal ~reason ~head_application_ordinal ~actual_root_key
      | Ok (binder, position) ->
          let selected = List.nth (telescope binder.expr) (position - 1) in
          let kind_matches =
            match application_kind, selected.kind with
            | Arch_index_functors.Apply, Named
            | Arch_index_functors.Apply_unit, Unit -> true
            | _ -> false
          in
          if not kind_matches then
            unresolved ~ordinal ~reason:"formal_kind_mismatch" ~head_application_ordinal
              ~actual_root_key
          else begin
            (match formal_identity binder.expr position, selected.binder_key,
                   actual_identity argument with
            | Some formal_id, Some formal_key, Some (actual_root_key, actual_path) ->
                matched_actuals :=
                  { application_ordinal = ordinal;
                    declaration_key = ident_key binder.id;
                    formal_position = position;
                    formal_key;
                    formal_id;
                    actual_root_key;
                    actual_path }
                  :: !matched_actuals
            | _ -> ()) ;
            { ordinal;
              status = "matched";
              reason = None;
              declaration_key = Some (ident_key binder.id);
              formal_position = Some position;
              head_application_ordinal;
              actual_root_key }
          end
    in
    results := result :: !results
  in
  ignore (Arch_index_functors.collect ~on_application structure) ;
  { bindings =
      { declarations =
          List.sort (fun (a : declaration) (b : declaration) ->
            String.compare a.declaration_key b.declaration_key) declarations;
        results = List.sort (fun a b -> Int.compare a.ordinal b.ordinal) !results };
    matched_actuals =
      List.sort (fun a b -> Int.compare a.application_ordinal b.application_ordinal)
        !matched_actuals }

let collect structure = (collect_with_actuals structure).bindings

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> failwith ("functor bindings SQL: " ^ Sqlite3.Rc.to_string rc ^ ": " ^ Sqlite3.errmsg db)

let quote s = "'" ^ String.concat "''" (String.split_on_char (Char.chr 39) s) ^ "'"
let optional_text = function None -> "NULL" | Some s -> quote s
let optional_int = function None -> "NULL" | Some n -> string_of_int n
let json_option = function None -> `Null | Some s -> `String s

let formals_json formals =
  Yojson.Safe.to_string (`List (List.map (fun (f : formal) ->
    `Assoc ["position", `Int f.position;
            "kind", `String (match f.kind with Named -> "named" | Unit -> "unit");
            "binder_key", json_option f.binder_key; "name", json_option f.name]) formals))

let store_collected db ~producer_run_id ~artifact collection =
  exec db "SAVEPOINT functor_binding_input" ;
  try
    exec db (Printf.sprintf
      "INSERT INTO functor_binding_inputs(producer_run_id,artifact,outcome,expected_declarations,expected_bindings) VALUES(%d,%s,'collected',%d,%d)"
      producer_run_id (quote artifact) (List.length collection.declarations) (List.length collection.results)) ;
    List.iter (fun (d : declaration) ->
      exec db (Printf.sprintf
        "INSERT INTO functor_declarations(producer_run_id,artifact,declaration_key,name,location,formals) VALUES(%d,%s,%s,%s,%s,%s)"
        producer_run_id (quote artifact) (quote d.declaration_key) (quote d.name)
        (quote d.location) (quote (formals_json d.formals)))) collection.declarations ;
    List.iter (fun (r : result) ->
      exec db (Printf.sprintf
        "INSERT INTO functor_bindings(producer_run_id,artifact,ordinal,status,reason,declaration_key,formal_position,head_application_ordinal,actual_root_key) VALUES(%d,%s,%d,%s,%s,%s,%s,%s,%s)"
        producer_run_id (quote artifact) r.ordinal (quote r.status) (optional_text r.reason)
        (optional_text r.declaration_key) (optional_int r.formal_position)
        (optional_int r.head_application_ordinal) (optional_text r.actual_root_key))) collection.results ;
    exec db "RELEASE functor_binding_input"
  with exn ->
    (* Any error, including rollback uncertainty, escapes to the caller's
       independent eligibility latch. Never unwind the catalogue savepoint. *)
    let rolled_back = Sqlite3.exec db "ROLLBACK TO functor_binding_input" in
    let released = Sqlite3.exec db "RELEASE functor_binding_input" in
    if rolled_back <> Sqlite3.Rc.OK || released <> Sqlite3.Rc.OK then
      failwith ("functor bindings rollback uncertain after " ^ Printexc.to_string exn) ;
    raise exn

let store_failed db ~producer_run_id ~artifact =
  exec db (Printf.sprintf
    "INSERT INTO functor_binding_inputs(producer_run_id,artifact,outcome,expected_declarations,expected_bindings) VALUES(%d,%s,'collection_failed',0,0)"
    producer_run_id (quote artifact))

exception Invalid_contract

let invalid () = raise Invalid_contract

let rows db sql =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize stmt)) (fun () ->
    let result = ref [] in
    let rec loop () =
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW ->
          result := List.init (Sqlite3.data_count stmt) (Sqlite3.column stmt) :: !result;
          loop ()
      | Sqlite3.Rc.DONE -> List.rev !result
      | rc ->
          failwith
            ("functor bindings validation SQL: " ^ Sqlite3.Rc.to_string rc ^ ": "
             ^ Sqlite3.errmsg db)
    in
    loop ())

let db_int = function
  | Sqlite3.Data.INT n ->
      let upper = Int64.of_int max_int and lower = Int64.of_int min_int in
      if Int64.compare n upper > 0 || Int64.compare n lower < 0 then invalid ();
      Int64.to_int n
  | _ -> invalid ()

let db_text = function Sqlite3.Data.TEXT s -> s | _ -> invalid ()
let db_optional_text = function
  | Sqlite3.Data.NULL -> None
  | Sqlite3.Data.TEXT s when s <> "" -> Some s
  | _ -> invalid ()
let db_optional_int = function
  | Sqlite3.Data.NULL -> None
  | value -> let n = db_int value in if n > 0 then Some n else invalid ()

let exact_fields fields keys =
  List.sort String.compare (List.map fst fields) = List.sort String.compare keys

let json text =
  try Yojson.Safe.from_string text with Yojson.Json_error _ -> invalid ()

let rec descriptor = function
  | `Assoc (["kind", `String ("structure" | "unpack" | "unit")]) as value -> value
  | `Assoc fields as value
    when exact_fields fields ["kind"; "compiler"; "source"; "contains_apply"] ->
      (match List.assoc_opt "kind" fields, List.assoc_opt "compiler" fields,
             List.assoc_opt "source" fields, List.assoc_opt "contains_apply" fields with
       | Some (`String "path"), Some (`String _), Some (`String _), Some (`Bool _) -> value
       | _ -> invalid ())
  | `Assoc fields as value when exact_fields fields ["kind"; "parameter"; "name"] ->
      (match List.assoc_opt "kind" fields, List.assoc_opt "parameter" fields,
             List.assoc_opt "name" fields with
       | Some (`String "functor"), Some (`String "unit"), Some `Null -> value
       | Some (`String "functor"), Some (`String "named"),
         (Some `Null | Some (`String _)) -> value
       | _ -> invalid ())
  | `Assoc fields as value when exact_fields fields ["kind"; "ordinal"] ->
      (match List.assoc_opt "kind" fields, List.assoc_opt "ordinal" fields with
       | Some (`String "application"), Some (`Int n) when n > 0 -> value
       | _ -> invalid ())
  | `Assoc fields as value when exact_fields fields ["kind"; "expression"] ->
      (match List.assoc_opt "kind" fields, List.assoc_opt "expression" fields with
       | Some (`String "constraint"), Some inner -> ignore (descriptor inner); value
       | _ -> invalid ())
  | _ -> invalid ()

let rec stripped_kind = function
  | `Assoc fields when List.assoc_opt "kind" fields = Some (`String "constraint") ->
      stripped_kind (List.assoc "expression" fields)
  | `Assoc fields ->
      (match List.assoc_opt "kind" fields with Some (`String kind) -> kind | _ -> invalid ())
  | _ -> invalid ()

let direct_kind = function
  | `Assoc fields ->
      (match List.assoc_opt "kind" fields with Some (`String kind) -> kind | _ -> invalid ())
  | _ -> invalid ()

let stripped_application = function
  | value ->
      let rec loop = function
        | `Assoc fields when List.assoc_opt "kind" fields = Some (`String "constraint") ->
            loop (List.assoc "expression" fields)
        | `Assoc fields when List.assoc_opt "kind" fields = Some (`String "application") ->
            (match List.assoc_opt "ordinal" fields with Some (`Int n) -> Some n | _ -> invalid ())
        | _ -> None
      in
      loop value

let descriptor_refs value =
  match stripped_application value with None -> [] | Some n -> [n]

let rec root_eligible = function
  | `Assoc fields when List.assoc_opt "kind" fields = Some (`String "constraint") ->
      (match List.assoc_opt "expression" fields with
       | Some inner -> root_eligible inner
       | None -> false)
  | `Assoc fields when List.assoc_opt "kind" fields = Some (`String "path") ->
      List.assoc_opt "contains_apply" fields = Some (`Bool false)
  | _ -> false

let valid_location value =
  match value with
  | `Assoc fields
    when exact_fields fields
      ["file"; "start_line"; "start_col"; "end_line"; "end_col"; "ghost"] ->
      (match List.assoc_opt "ghost" fields with Some (`Bool _) -> () | _ -> invalid ());
      let keys = ["file"; "start_line"; "start_col"; "end_line"; "end_col"] in
      let all_null = List.for_all (fun key -> List.assoc_opt key fields = Some `Null) keys in
      let coordinates =
        match List.assoc_opt "file" fields, List.assoc_opt "start_line" fields,
              List.assoc_opt "start_col" fields, List.assoc_opt "end_line" fields,
              List.assoc_opt "end_col" fields with
        | Some (`String file), Some (`Int sl), Some (`Int sc), Some (`Int el), Some (`Int ec) ->
            file <> "" && sl >= 1 && sc >= 0 && el >= 1 && ec >= 0
            && (sl < el || sl = el && sc <= ec)
        | _ -> false
      in
      if not (all_null || coordinates) then invalid ();
      all_null
  | _ -> invalid ()

type stored_formal = { stored_kind : string }

let stored_formals text =
  match json text with
  | `List values when values <> [] ->
      List.mapi (fun index -> function
        | `Assoc fields
          when exact_fields fields ["position"; "kind"; "binder_key"; "name"] ->
            let position =
              match List.assoc_opt "position" fields with Some (`Int n) -> n | _ -> invalid ()
            in
            let kind =
              match List.assoc_opt "kind" fields with Some (`String s) -> s | _ -> invalid ()
            in
            let optional key =
              match List.assoc_opt key fields with
              | Some `Null -> None
              | Some (`String s) when s <> "" -> Some s
              | _ -> invalid ()
            in
            let binder_key = optional "binder_key" and name = optional "name" in
            if position <> index + 1 then invalid ();
            (match kind with
             | "unit" when binder_key = None && name = None -> ()
             | "named" -> ()
             | _ -> invalid ());
            {stored_kind = kind}
        | _ -> invalid ()) values
  | _ -> invalid ()

let valid_reason = function
  | "cross_unit_head" | "parameter_supplied_head" | "alias_cycle"
  | "local_declaration_missing" | "unsupported_alias_rhs" | "unsupported_path"
  | "unsupported_head_shape" | "curried_result_not_functor" | "formal_kind_mismatch" -> true
  | _ -> false

let scalar_count db sql =
  match rows db ("SELECT count(*) FROM (" ^ sql ^ ")") with
  | [[value]] -> db_int value
  | _ -> invalid ()

let marker_is db key value =
  rows db
    (Printf.sprintf
       "SELECT typeof(value),value FROM comment_db_meta WHERE key=%s" (quote key))
  = [[Sqlite3.Data.TEXT "text"; Sqlite3.Data.TEXT value]]

let validate_shape db =
  (* Mirror the reader's capability guard before inspecting persisted rows.
     These names are static SQL identifiers, never input-derived paths. *)
  let required =
    [ "producer_runs", ["id"];
      "modules", ["id"; "path"];
      "comment_db_meta", ["key"; "value"];
      "functor_catalogue_runs", ["producer_run_id"; "selected_inputs"];
      "functor_catalogue_inputs",
        ["producer_run_id"; "artifact"; "source"; "compiler_unit";
         "module_id"; "outcome"; "expected_applications"];
      "functor_applications",
        ["producer_run_id"; "artifact"; "ordinal"; "application_kind";
         "location"; "head"; "argument"; "diagnostics"];
      "functor_binding_inputs",
        ["producer_run_id"; "artifact"; "outcome";
         "expected_declarations"; "expected_bindings"];
      "functor_declarations",
        ["producer_run_id"; "artifact"; "declaration_key";
         "name"; "location"; "formals"];
      "functor_bindings",
        ["producer_run_id"; "artifact"; "ordinal"; "status"; "reason";
         "declaration_key"; "formal_position"; "head_application_ordinal";
         "actual_root_key"] ]
  in
  let columns table =
    List.map (function
      | _ :: Sqlite3.Data.TEXT name :: _ -> name
      | _ -> invalid ()) (rows db ("PRAGMA table_info(" ^ quote table ^ ")"))
  in
  if List.mem "caller_name" (columns "calls") then invalid ();
  List.iter (fun (table, expected) ->
    let actual = columns table in
    if List.exists (fun column -> not (List.mem column actual)) expected then
      invalid ()) required

let validate_contract db ~selected_inputs =
  validate_shape db;
  if selected_inputs <= 0 || not (marker_is db "functor_catalogue_contract" "v1") then
    invalid ();
  let run =
    match rows db "SELECT producer_run_id,selected_inputs FROM functor_catalogue_runs" with
    | [[run; selected]] ->
        let run = db_int run in
        if db_int selected <> selected_inputs then invalid ();
        run
    | _ -> invalid ()
  in
  if scalar_count db (Printf.sprintf "SELECT 1 FROM producer_runs WHERE id=%d" run) <> 1 then
    invalid ();
  let inputs = Hashtbl.create selected_inputs in
  List.iter (function
    | [stored_run; artifact; source; compiler_unit; module_id; outcome; expected] ->
        let stored_run = db_int stored_run and artifact = db_text artifact
        and source = db_text source and compiler_unit = db_text compiler_unit
        and module_id = db_int module_id and outcome = db_text outcome
        and expected = db_int expected in
        if stored_run <> run || artifact = "" || source = "" || compiler_unit = ""
           || outcome <> "collected" || expected < 0 || Hashtbl.mem inputs artifact then invalid ();
        if scalar_count db
             (Printf.sprintf "SELECT 1 FROM modules WHERE id=%d AND path=%s" module_id (quote source))
           <> 1 then invalid ();
        Hashtbl.add inputs artifact expected
    | _ -> invalid ())
    (rows db "SELECT producer_run_id,artifact,source,compiler_unit,module_id,outcome,expected_applications FROM functor_catalogue_inputs");
  if Hashtbl.length inputs <> selected_inputs then invalid ();
  let applications = Hashtbl.create 32 in
  List.iter (function
    | [stored_run; artifact; ordinal; kind; location; head; argument; diagnostics] ->
        let stored_run = db_int stored_run and artifact = db_text artifact
        and ordinal = db_int ordinal and kind = db_text kind
        and location = json (db_text location) and head = descriptor (json (db_text head))
        and argument = descriptor (json (db_text argument))
        and diagnostics = json (db_text diagnostics) in
        if stored_run <> run || ordinal <= 0 || not (Hashtbl.mem inputs artifact)
           || Hashtbl.mem applications (artifact, ordinal)
           || (kind <> "apply" && kind <> "apply_unit") then invalid ();
        let bad_location = valid_location location in
        let expected_diagnostics =
          ((if stripped_kind head <> "path" && stripped_kind head <> "application"
            then ["opaque_functor_head"] else [])
           @ (if stripped_kind argument = "structure" then ["anonymous_argument"] else [])
           @ (if stripped_kind head = "unpack" || stripped_kind argument = "unpack"
              then ["unpacked_expression"] else [])
           @ (if bad_location then ["unusable_location"] else []))
          |> List.sort_uniq String.compare
        in
        let actual_diagnostics =
          match diagnostics with
          | `List values -> List.map (function `String s -> s | _ -> invalid ()) values
          | _ -> invalid ()
        in
        if actual_diagnostics <> expected_diagnostics
           || stripped_kind head = "unit"
           || (kind = "apply_unit") <> (direct_kind argument = "unit")
           || (kind = "apply" && stripped_kind argument = "unit") then invalid ();
        Hashtbl.add applications (artifact, ordinal) (kind, head, argument)
    | _ -> invalid ())
    (rows db "SELECT producer_run_id,artifact,ordinal,application_kind,location,head,argument,diagnostics FROM functor_applications");
  Hashtbl.iter (fun artifact expected ->
    let ordinals =
      Hashtbl.fold (fun (candidate, ordinal) _ acc ->
        if candidate = artifact then ordinal :: acc else acc) applications []
      |> List.sort Int.compare
    in
    if List.length ordinals <> expected
       || ordinals <> List.init expected (fun index -> index + 1) then invalid ();
    List.iter (fun ordinal ->
      let _, head, argument = Hashtbl.find applications (artifact, ordinal) in
      List.iter (fun reference ->
        if reference <= ordinal || not (Hashtbl.mem applications (artifact, reference))
        then invalid ()) (descriptor_refs head @ descriptor_refs argument)) ordinals) inputs;
  let binding_inputs = Hashtbl.create selected_inputs in
  List.iter (function
    | [stored_run; artifact; outcome; declarations; bindings] ->
        let stored_run = db_int stored_run and artifact = db_text artifact
        and outcome = db_text outcome and declarations = db_int declarations
        and bindings = db_int bindings in
        if stored_run <> run || not (Hashtbl.mem inputs artifact) || outcome <> "collected"
           || declarations < 0 || bindings < 0 || Hashtbl.mem binding_inputs artifact
           || bindings <> Hashtbl.find inputs artifact then invalid ();
        Hashtbl.add binding_inputs artifact (declarations, bindings)
    | _ -> invalid ())
    (rows db "SELECT producer_run_id,artifact,outcome,expected_declarations,expected_bindings FROM functor_binding_inputs");
  if Hashtbl.length binding_inputs <> selected_inputs then invalid ();
  let declarations = Hashtbl.create 32 in
  List.iter (function
    | [stored_run; artifact; key; name; location; formals] ->
        let stored_run = db_int stored_run and artifact = db_text artifact
        and key = db_text key and name = db_text name and location = db_text location
        and formals = db_text formals in
        if stored_run <> run || key = "" || name = "" || not (Hashtbl.mem binding_inputs artifact)
           || Hashtbl.mem declarations (artifact, key) then invalid ();
        ignore (valid_location (json location));
        Hashtbl.add declarations (artifact, key) (stored_formals formals)
    | _ -> invalid ())
    (rows db "SELECT producer_run_id,artifact,declaration_key,name,location,formals FROM functor_declarations");
  Hashtbl.iter (fun artifact (expected, _) ->
    let actual = Hashtbl.fold (fun (candidate, _) _ n -> n + if candidate = artifact then 1 else 0) declarations 0 in
    if actual <> expected then invalid ()) binding_inputs;
  let seen_results = Hashtbl.create 32 and matches = Hashtbl.create 32 in
  List.iter (function
    | [stored_run; artifact; ordinal; status; reason; declaration_key; formal_position;
       head_application_ordinal; actual_root_key] ->
        let stored_run = db_int stored_run and artifact = db_text artifact
        and ordinal = db_int ordinal and status = db_text status
        and reason = db_optional_text reason and declaration_key = db_optional_text declaration_key
        and formal_position = db_optional_int formal_position
        and head_application_ordinal = db_optional_int head_application_ordinal
        and actual_root_key = db_optional_text actual_root_key in
        if stored_run <> run || ordinal <= 0 || not (Hashtbl.mem binding_inputs artifact)
           || Hashtbl.mem seen_results (artifact, ordinal) then invalid ();
        Hashtbl.add seen_results (artifact, ordinal) ();
        let kind, catalogue_head, argument =
          match Hashtbl.find_opt applications (artifact, ordinal) with
          | Some value -> value | None -> invalid ()
        in
        if head_application_ordinal <> stripped_application catalogue_head then invalid ();
        (match actual_root_key with
         | Some _ when not (root_eligible argument) -> invalid ()
         | _ -> ());
        (match status, reason, declaration_key, formal_position with
         | "matched", None, Some key, Some position ->
             let formals =
               match Hashtbl.find_opt declarations (artifact, key) with
               | Some value -> value | None -> invalid ()
             in
             let formal = match List.nth_opt formals (position - 1) with Some f -> f | None -> invalid () in
             if (kind = "apply" && formal.stored_kind <> "named")
                || (kind = "apply_unit" && formal.stored_kind <> "unit")
                || (head_application_ordinal = None && position <> 1) then invalid ();
             Hashtbl.add matches (artifact, ordinal) (key, position)
         | "unresolved", Some reason, None, None when valid_reason reason -> ()
         | _ -> invalid ())
    | _ -> invalid ())
    (rows db "SELECT producer_run_id,artifact,ordinal,status,reason,declaration_key,formal_position,head_application_ordinal,actual_root_key FROM functor_bindings");
  if Hashtbl.length seen_results <> Hashtbl.length applications then invalid ();
  Hashtbl.iter (fun artifact (_, expected) ->
    let actual = Hashtbl.fold (fun (candidate, _) _ n -> n + if candidate = artifact then 1 else 0) seen_results 0 in
    if actual <> expected then invalid ()) binding_inputs;
  Hashtbl.iter (fun (artifact, ordinal) (key, position) ->
    match stripped_application (let _, head, _ = Hashtbl.find applications (artifact, ordinal) in head) with
    | None -> ()
    | Some parent ->
        (match Hashtbl.find_opt matches (artifact, parent) with
         | Some (parent_key, parent_position)
           when parent_key = key && parent_position = position - 1 -> ()
         | _ -> invalid ())) matches

let finalize_contract db ~selected_inputs =
  (* Clear success durably before beginning validation.  An operational failure
     during the snapshot must not roll this deletion back and revive stale proof. *)
  exec db "DELETE FROM comment_db_meta WHERE key='functor_binding_contract'";
  exec db "BEGIN";
  try
    let complete =
      try validate_contract db ~selected_inputs; true
      with Invalid_contract -> false
    in
    if complete then
      exec db
        "INSERT INTO comment_db_meta(key,value) VALUES('functor_binding_contract','v1')";
    exec db "COMMIT";
    complete
  with exn ->
    let rollback = Sqlite3.exec db "ROLLBACK" in
    if rollback <> Sqlite3.Rc.OK then
      failwith ("functor bindings finalization rollback uncertain after "
                ^ Printexc.to_string exn);
    raise exn

type target_witness = {
  application_ordinal : int;
  declaration_key : string;
  formal_position : int;
  formal_key : string;
  actual_root_key : string;
  actual_path : string list;
  member_path : string list;
  caller_name : string;
  call_location : string;
  occurrence_ordinal : int;
  target_function_id : int;
  candidate_call_id : int;
}

let string_list_json values =
  Yojson.Safe.to_string (`List (List.map (fun value -> `String value) values))

let store_target_collected db ~producer_run_id ~artifact ~expected_witnesses witnesses =
  exec db "SAVEPOINT functor_target_input" ;
  try
    exec db (Printf.sprintf
      "INSERT INTO functor_target_inputs(producer_run_id,artifact,outcome,expected_witnesses) VALUES(%d,%s,'collected',%d)"
      producer_run_id (quote artifact) expected_witnesses) ;
    List.iter (fun (w : target_witness) ->
      exec db (Printf.sprintf
        "INSERT INTO functor_target_witnesses(producer_run_id,artifact,application_ordinal,declaration_key,formal_position,formal_key,actual_root_key,actual_path,member_path,caller_name,call_location,occurrence_ordinal,target_function_id,candidate_call_id) VALUES(%d,%s,%d,%s,%d,%s,%s,%s,%s,%s,%s,%d,%d,%d)"
        producer_run_id (quote artifact) w.application_ordinal
        (quote w.declaration_key) w.formal_position (quote w.formal_key)
        (quote w.actual_root_key) (quote (string_list_json w.actual_path))
        (quote (string_list_json w.member_path)) (quote w.caller_name)
        (quote w.call_location) w.occurrence_ordinal w.target_function_id
        w.candidate_call_id)) witnesses ;
    exec db "RELEASE functor_target_input"
  with exn ->
    let rolled_back = Sqlite3.exec db "ROLLBACK TO functor_target_input" in
    let released = Sqlite3.exec db "RELEASE functor_target_input" in
    if rolled_back <> Sqlite3.Rc.OK || released <> Sqlite3.Rc.OK then
      failwith ("functor targets rollback uncertain after " ^ Printexc.to_string exn) ;
    raise exn

let store_target_failed db ~producer_run_id ~artifact =
  exec db (Printf.sprintf
    "INSERT INTO functor_target_inputs(producer_run_id,artifact,outcome,expected_witnesses) VALUES(%d,%s,'collection_failed',0)"
    producer_run_id (quote artifact))

let validate_target_contract db ~selected_inputs =
  if scalar_count db
       "SELECT 1 FROM comment_db_meta WHERE key='functor_binding_contract' AND value='v1'"
     <> 1 then invalid () ;
  if scalar_count db "SELECT 1 FROM functor_target_inputs" <> selected_inputs then invalid () ;
  if scalar_count db
       "SELECT 1 FROM functor_target_inputs WHERE outcome<>'collected'"
     <> 0 then invalid () ;
  let expected =
    match rows db "SELECT coalesce(sum(expected_witnesses),0) FROM functor_target_inputs" with
    | [[value]] -> db_int value
    | _ -> invalid ()
  in
  if scalar_count db "SELECT 1 FROM functor_target_witnesses" <> expected then invalid () ;
  if scalar_count db
       "SELECT 1 FROM functor_target_inputs i \
        LEFT JOIN (SELECT producer_run_id,artifact,count(*) AS actual \
                   FROM functor_target_witnesses GROUP BY producer_run_id,artifact) w \
          USING(producer_run_id,artifact) \
        WHERE i.expected_witnesses IS NOT coalesce(w.actual,0)"
     <> 0 then invalid () ;
  if scalar_count db
       "SELECT 1 FROM functor_target_witnesses w \
        LEFT JOIN functor_target_inputs i USING(producer_run_id,artifact) \
        LEFT JOIN functor_catalogue_inputs ci USING(producer_run_id,artifact) \
        LEFT JOIN functor_bindings b ON b.producer_run_id=w.producer_run_id \
          AND b.artifact=w.artifact AND b.ordinal=w.application_ordinal \
        LEFT JOIN functor_declarations d ON d.producer_run_id=w.producer_run_id \
          AND d.artifact=w.artifact AND d.declaration_key=w.declaration_key \
        LEFT JOIN calls c ON c.id=w.candidate_call_id \
        LEFT JOIN functions f ON f.id=w.target_function_id \
        LEFT JOIN modules target_module ON target_module.id=f.module_id \
        LEFT JOIN functions caller ON caller.id=c.caller_id \
        LEFT JOIN modules caller_module ON caller_module.id=caller.module_id \
        WHERE i.outcome IS NOT 'collected' OR ci.source IS NULL \
          OR b.status IS NOT 'matched' \
          OR b.declaration_key IS NOT w.declaration_key \
          OR b.formal_position IS NOT w.formal_position \
          OR b.actual_root_key IS NOT w.actual_root_key \
          OR d.declaration_key IS NULL \
          OR json_extract(d.formals,'$[' || (w.formal_position-1) || '].binder_key') \
             IS NOT w.formal_key \
          OR c.id IS NULL OR c.kind IS NOT 'MAY_ENUMERATED' \
          OR c.callee_id IS NOT w.target_function_id \
          OR c.producer_run_id IS NOT w.producer_run_id \
          OR caller.name IS NOT w.caller_name \
          OR caller_module.path IS NOT ci.source \
          OR c.call_site IS NOT \
             (ci.source || ':' || json_extract(w.call_location,'$.start_line')) \
          OR f.id IS NULL OR f.producer_run_id IS NOT w.producer_run_id \
          OR target_module.path IS NOT ci.source \
          OR json_valid(w.actual_path)<>1 OR json_type(w.actual_path)<>'array' \
          OR json_array_length(w.actual_path)=0 \
          OR json_valid(w.member_path)<>1 OR json_type(w.member_path)<>'array' \
          OR json_array_length(w.member_path)=0 \
          OR json_valid(w.call_location)<>1 \
          OR json_type(w.call_location)<>'object'"
     <> 0 then invalid ()

let finalize_target_contract db ~selected_inputs =
  exec db "DELETE FROM comment_db_meta WHERE key='functor_target_contract'" ;
  exec db "BEGIN" ;
  try
    let complete =
      try validate_target_contract db ~selected_inputs ; true
      with Invalid_contract -> false
    in
    if complete then
      exec db
        "INSERT INTO comment_db_meta(key,value) VALUES('functor_target_contract','v1')" ;
    exec db "COMMIT" ;
    complete
  with exn ->
    let rollback = Sqlite3.exec db "ROLLBACK" in
    if rollback <> Sqlite3.Rc.OK then
      failwith ("functor targets finalization rollback uncertain after "
                ^ Printexc.to_string exn) ;
    raise exn
