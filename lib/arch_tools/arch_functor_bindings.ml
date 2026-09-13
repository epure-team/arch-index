(* Same-CMT functor-formal provenance reader.  This deliberately consumes the
   catalogue reader's semantic validation rather than maintaining a second,
   subtly different definition of an application occurrence. *)

let limitations =
  "not_runtime_instances;not_closed_world;no_call_target_resolution;no_actual_substitution;no_source_freshness_check;artifact_scoped_compiler_identity"

let required =
  [ "functor_binding_inputs", ["producer_run_id"; "artifact"; "outcome";
                               "expected_declarations"; "expected_bindings"];
    "functor_declarations", ["producer_run_id"; "artifact"; "declaration_key";
                               "name"; "location"; "formals"];
    "functor_bindings", ["producer_run_id"; "artifact"; "ordinal"; "status";
                           "reason"; "declaration_key"; "formal_position";
                           "head_application_ordinal"; "actual_root_key"] ]

let old_required =
  ["producer_runs", ["id"]; "modules", ["id"; "path"];
   "comment_db_meta", ["key"; "value"];
   "functor_catalogue_runs", ["producer_run_id"; "selected_inputs"];
   "functor_catalogue_inputs", ["producer_run_id"; "artifact"; "source";
     "compiler_unit"; "module_id"; "outcome"; "expected_applications"];
   "functor_applications", ["producer_run_id"; "artifact"; "ordinal";
     "application_kind"; "location"; "head"; "argument"; "diagnostics"]]

let inconsistent fmt = Printf.ksprintf (Arch_db.refuse "INCONSISTENT_BINDINGS: %s") fmt
let quote = Arch_db.quote_lit

let cells t shape conv sql =
  Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape ~to_cells:conv sql ()

let count t sql =
  match cells t Arch_db.Rows.t1 Arch_db.Rows.c1
          ("SELECT CAST(count(*) AS TEXT) FROM (" ^ sql ^ ")") with
  | [[Arch_db.Text n]] ->
      (match int_of_string_opt n with Some n -> n | None -> inconsistent "invalid count")
  | _ -> inconsistent "invalid count"

let snapshot t f =
  let module Db = (val t.Arch_db.conn : Arch_db.C.CONNECTION) in
  Arch_db.ok (Db.start ());
  try
    let value = f () in
    Arch_db.ok (Db.commit ());
    value
  with exn ->
      (match Db.rollback () with
       | Ok () -> ()
       | Error error -> Arch_db.broken "%s" (Caqti_error.show error));
      raise exn

let exact fs ks = List.sort compare (List.map fst fs) = List.sort compare ks

type formal = { position : int; kind : string; key : string option; name : string option }

let formals text =
  let json = try Yojson.Safe.from_string text with Yojson.Json_error _ -> inconsistent "malformed formals JSON" in
  match json with
  | `List xs when xs <> [] ->
      List.mapi (fun i -> function
        | `Assoc fs when exact fs ["position"; "kind"; "binder_key"; "name"] ->
            let position = match List.assoc_opt "position" fs with Some (`Int n) -> n | _ -> inconsistent "invalid formal position" in
            let kind = match List.assoc_opt "kind" fs with Some (`String s) -> s | _ -> inconsistent "invalid formal kind" in
            let opt field = match List.assoc_opt field fs with
              | Some `Null -> None | Some (`String s) when s <> "" -> Some s
              | _ -> inconsistent "invalid formal %s" field
            in
            let key = opt "binder_key" and name = opt "name" in
            if position <> i + 1 then inconsistent "formal positions are not contiguous";
            (match kind with
             | "unit" when key = None && name = None -> ()
             | "named" -> ()
             | _ -> inconsistent "invalid formal nullable shape");
            {position; kind; key; name}
        | _ -> inconsistent "formal violates closed grammar") xs
  | _ -> inconsistent "formals must be a nonempty array"

let location text =
  let json = try Yojson.Safe.from_string text with Yojson.Json_error _ -> inconsistent "malformed declaration location JSON" in
  match json with
  | `Assoc fs when exact fs ["file"; "start_line"; "start_col"; "end_line"; "end_col"; "ghost"] ->
      (match List.assoc_opt "ghost" fs with
       | Some (`Bool _) -> ()
       | _ -> inconsistent "invalid declaration location");
      let null = List.for_all (fun key -> List.assoc_opt key fs = Some `Null)
          ["file"; "start_line"; "start_col"; "end_line"; "end_col"] in
      let valid = match List.assoc_opt "file" fs, List.assoc_opt "start_line" fs,
                        List.assoc_opt "start_col" fs, List.assoc_opt "end_line" fs,
                        List.assoc_opt "end_col" fs with
        | Some (`String file), Some (`Int sl), Some (`Int sc), Some (`Int el), Some (`Int ec) ->
            file <> "" && sl >= 1 && sc >= 0 && el >= 1 && ec >= 0
            && (sl < el || sl = el && sc <= ec)
        | _ -> false
      in
      if not (null || valid) then inconsistent "invalid declaration location"
  | _ -> inconsistent "declaration location violates closed grammar"

let root_eligible argument =
  let json = try Yojson.Safe.from_string argument with Yojson.Json_error _ -> inconsistent "malformed argument JSON" in
  let rec strip = function
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "constraint") ->
        (match List.assoc_opt "expression" fs with Some expression -> strip expression | None -> false)
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "path") ->
        List.assoc_opt "contains_apply" fs = Some (`Bool false)
    | _ -> false
  in strip json

let stripped_head_application head =
  let json =
    try Yojson.Safe.from_string head
    with Yojson.Json_error _ -> inconsistent "malformed catalogue head JSON"
  in
  let rec strip = function
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "constraint") ->
        (match List.assoc_opt "expression" fs with
         | Some expression -> strip expression
         | None -> inconsistent "invalid catalogue head constraint")
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "application") ->
        (match List.assoc_opt "ordinal" fs with
         | Some (`Int n) when n > 0 -> Some n
         | _ -> inconsistent "invalid catalogue head application")
    | _ -> None
  in
  strip json

let is_reason = function
  | "cross_unit_head" | "parameter_supplied_head" | "alias_cycle"
  | "local_declaration_missing" | "unsupported_alias_rhs" | "unsupported_path"
  | "unsupported_head_shape" | "curried_result_not_functor" | "formal_kind_mismatch" -> true
  | _ -> false

let require_shape t =
  if t.Arch_db.schema = Arch_db.Flat
     || Arch_db.has_col t "calls" "caller_name"
     || List.exists (fun (table, columns) -> not (Arch_db.has_table t table)
          || List.exists (fun c -> not (Arch_db.has_col t table c)) columns)
          (old_required @ required)
  then Arch_db.refuse "UNSUPPORTED_SCHEMA: functor binding v1 tables/columns are absent"

let marker t key expected refusal =
  let rows = cells t Arch_db.Rows.t2' Arch_db.Rows.c2
      (Printf.sprintf "SELECT typeof(value),CASE WHEN typeof(value)='text' THEN value ELSE NULL END FROM comment_db_meta WHERE key='%s'" key) in
  if rows <> [[Arch_db.Text "text"; Arch_db.Text expected]] then Arch_db.refuse refusal

let read_unwrapped t ~limit =
  require_shape t;
  marker t "functor_catalogue_contract" "v1" "NOT_COLLECTED_BINDINGS: functor catalogue contract v1 is absent";
  marker t "functor_binding_contract" "v1" "NOT_COLLECTED_BINDINGS: functor binding contract v1 is absent";
  (* The catalogue reader supplies the complete old-table semantic validation
     in this caller-owned snapshot. *)
  let _, applications =
    try Arch_functor_catalogue.read_unwrapped t ~limit:max_int with
    | Arch_db.Refused message ->
        inconsistent "catalogue validation failed: %s" message
  in
  if count t "SELECT 1 FROM functor_binding_inputs WHERE typeof(producer_run_id)<>'integer' OR typeof(artifact)<>'text' OR typeof(outcome)<>'text' OR typeof(expected_declarations)<>'integer' OR typeof(expected_bindings)<>'integer'" <> 0
  then inconsistent "binding input has an invalid SQLite storage class";
  if count t "SELECT 1 FROM functor_declarations WHERE typeof(producer_run_id)<>'integer' OR typeof(artifact)<>'text' OR typeof(declaration_key)<>'text' OR typeof(name)<>'text' OR typeof(location)<>'text' OR typeof(formals)<>'text'" <> 0
  then inconsistent "declaration has an invalid SQLite storage class";
  if count t "SELECT 1 FROM functor_bindings WHERE typeof(producer_run_id)<>'integer' OR typeof(artifact)<>'text' OR typeof(ordinal)<>'integer' OR typeof(status)<>'text' OR (reason IS NOT NULL AND typeof(reason)<>'text') OR (declaration_key IS NOT NULL AND typeof(declaration_key)<>'text') OR (formal_position IS NOT NULL AND typeof(formal_position)<>'integer') OR (head_application_ordinal IS NOT NULL AND typeof(head_application_ordinal)<>'integer') OR (actual_root_key IS NOT NULL AND typeof(actual_root_key)<>'text')" <> 0
  then inconsistent "binding has an invalid SQLite storage class";
  let in_shape = Arch_db.Ty.(t2 (t3 (option string) (option string) (option string)) (t2 (option string) (option string))) in
  let in_cells ((a,b,c),(d,e)) = List.map Arch_db.text_cell [a;b;c;d;e] in
  let inputs = cells t in_shape in_cells "SELECT CAST(producer_run_id AS TEXT),artifact,outcome,CAST(expected_declarations AS TEXT),CAST(expected_bindings AS TEXT) FROM functor_binding_inputs ORDER BY artifact" in
  let app_count = List.length applications in
  if List.length inputs = 0 then inconsistent "binding inputs are absent";
  let input_map = Hashtbl.create (List.length inputs) in
  List.iter (function
    | [Arch_db.Text run; Arch_db.Text artifact; Arch_db.Text outcome; Arch_db.Text ds; Arch_db.Text bs] ->
        let run = match int_of_string_opt run with Some n -> n | None -> inconsistent "invalid binding run" in
        let declarations = match int_of_string_opt ds with Some n when n >= 0 -> n | _ -> inconsistent "invalid expected declarations" in
        let bindings = match int_of_string_opt bs with Some n when n >= 0 -> n | _ -> inconsistent "invalid expected bindings" in
        if outcome <> "collected" then inconsistent "binding input is not collected";
        if Hashtbl.mem input_map artifact then inconsistent "duplicate binding input";
        if count t (Printf.sprintf "SELECT 1 FROM functor_catalogue_inputs WHERE producer_run_id=%d AND artifact='%s' AND outcome='collected'" run (quote artifact)) <> 1 then
          inconsistent "binding input has no same-run collected catalogue input";
        Hashtbl.add input_map artifact (run, declarations, bindings)
    | _ -> inconsistent "invalid binding input row") inputs;
  if count t "SELECT 1 FROM functor_catalogue_inputs" <> List.length inputs then
    inconsistent "catalogue/binding input coverage disagrees";
  (* All catalogue applications are already valid and carry the artifact/ordinal
     in their first and fourth display cells. *)
  let expected = Hashtbl.create app_count in
  List.iter (function
    | Arch_db.Text artifact :: _ :: _ :: Arch_db.Int ordinal :: Arch_db.Text kind :: _ :: Arch_db.Text head :: Arch_db.Text argument :: _ ->
        if Hashtbl.mem expected (artifact, ordinal) then
          inconsistent "duplicate catalogue occurrence";
        Hashtbl.add expected (artifact, ordinal)
          (kind, argument, stripped_head_application head)
    | _ -> inconsistent "catalogue projection changed") applications;
  Hashtbl.iter (fun artifact (_, _, n) ->
    let actual = Hashtbl.fold (fun (a, _) _ total -> if a = artifact then total + 1 else total) expected 0 in
    if n <> actual then inconsistent "binding expected count disagrees") input_map;
  let dec_shape = Arch_db.Ty.(t2 (t3 (option string) (option string) (option string)) (t3 (option string) (option string) (option string))) in
  let dec_cells ((a,b,c),(d,e,f)) = List.map Arch_db.text_cell [a;b;c;d;e;f] in
  let declarations = cells t dec_shape dec_cells "SELECT CAST(producer_run_id AS TEXT),artifact,declaration_key,name,location,formals FROM functor_declarations ORDER BY artifact,declaration_key" in
  let decls = Hashtbl.create (List.length declarations) in
  List.iter (function
    | [Arch_db.Text run; Arch_db.Text artifact; Arch_db.Text key; Arch_db.Text name; Arch_db.Text location_text; Arch_db.Text fs] ->
        if key = "" || name = "" || Hashtbl.mem decls (artifact,key) then inconsistent "invalid duplicate declaration";
        location location_text;
        let run = match int_of_string_opt run with Some n -> n | None -> inconsistent "invalid declaration run" in
        (match Hashtbl.find_opt input_map artifact with Some (r,_,_) when r = run -> () | _ -> inconsistent "orphan declaration");
        Hashtbl.add decls (artifact,key) (name, formals fs)
    | _ -> inconsistent "invalid declaration row") declarations;
  Hashtbl.iter (fun artifact (_, expected_declarations, _) ->
    let n = Hashtbl.fold (fun (a, _) _ n -> if a = artifact then n + 1 else n) decls 0 in
    if n <> expected_declarations then inconsistent "expected declaration count disagrees") input_map;
  let bind_shape = Arch_db.Ty.(t2 (t3 (option string) (option string) (option string)) (t2 (t3 (option string) (option string) (option string)) (t3 (option string) (option string) (option string)))) in
  let bind_cells ((a,b,c),((d,e,f),(g,h,i))) = List.map Arch_db.text_cell [a;b;c;d;e;f;g;h;i] in
  let bindings = cells t bind_shape bind_cells "SELECT CAST(producer_run_id AS TEXT),artifact,CAST(ordinal AS TEXT),status,reason,declaration_key,CASE WHEN formal_position IS NULL THEN NULL ELSE CAST(formal_position AS TEXT) END,CASE WHEN head_application_ordinal IS NULL THEN NULL ELSE CAST(head_application_ordinal AS TEXT) END,actual_root_key FROM functor_bindings ORDER BY artifact,ordinal" in
  let seen_bindings = Hashtbl.create (List.length bindings) in
  let match_meta = Hashtbl.create (List.length bindings) in
  let rows = List.map (function
    | [Arch_db.Text run; Arch_db.Text artifact; Arch_db.Text ordinal; Arch_db.Text status; reason; key; position; head_ordinal; root] ->
        let run = match int_of_string_opt run with Some n -> n | None -> inconsistent "invalid binding run" in
        let ordinal = match int_of_string_opt ordinal with Some n when n > 0 -> n | _ -> inconsistent "invalid binding ordinal" in
        (match Hashtbl.find_opt input_map artifact with Some (r,_,_) when r = run -> () | _ -> inconsistent "orphan binding");
        if Hashtbl.mem seen_bindings (artifact, ordinal) then
          inconsistent "duplicate binding occurrence";
        Hashtbl.add seen_bindings (artifact, ordinal) ();
        let kind, argument, expected_head = match Hashtbl.find_opt expected (artifact,ordinal) with Some x -> x | None -> inconsistent "binding has no catalogue occurrence" in
        let pos = match position with Arch_db.Nul -> None | Arch_db.Text s -> (match int_of_string_opt s with Some n when n > 0 -> Some n | _ -> inconsistent "invalid formal position") | _ -> inconsistent "invalid formal position" in
        let head = match head_ordinal with Arch_db.Nul -> None | Arch_db.Text s -> (match int_of_string_opt s with Some n when n > 0 -> Some n | _ -> inconsistent "invalid head ordinal") | _ -> inconsistent "invalid head ordinal" in
        if head <> expected_head then
          inconsistent "head application reference disagrees with catalogue head";
        let root = match root with Arch_db.Nul -> None | Arch_db.Text s when s <> "" -> Some s | _ -> inconsistent "invalid actual root key" in
        (match root with Some _ when not (root_eligible argument) -> inconsistent "actual root is not eligible for its operand" | _ -> ());
        let decl, formal = match status, reason, key, pos with
          | "matched", Arch_db.Nul, Arch_db.Text key, Some pos ->
              (match Hashtbl.find_opt decls (artifact,key) with
               | Some (name, fs) ->
                   let f = match List.nth_opt fs (pos - 1) with Some f -> f | None -> inconsistent "matched formal does not exist" in
                   if (kind = "apply" && f.kind <> "named") || (kind = "apply_unit" && f.kind <> "unit") then inconsistent "formal kind mismatch";
                   (Some (key,name), Some f)
               | None -> inconsistent "matched declaration does not exist")
          | "unresolved", Arch_db.Text r, Arch_db.Nul, None when is_reason r -> (None, None)
          | _ -> inconsistent "invalid binding status shape"
        in
        (match head with Some h when h <= ordinal || not (Hashtbl.mem expected (artifact,h)) -> inconsistent "invalid head application reference" | _ -> ());
        (match decl, formal with
         | Some (key, _), Some formal ->
             if head = None && formal.position <> 1 then
               inconsistent "direct matched binding does not start at formal position one";
             Hashtbl.add match_meta (artifact, ordinal) (key, formal.position, head)
         | _ -> ());
        let source, unit_name = match List.find_opt (function Arch_db.Text a :: Arch_db.Text _ :: Arch_db.Text _ :: _ when a=artifact -> true | _ -> false) applications with
          | Some (Arch_db.Text _ :: Arch_db.Text s :: Arch_db.Text u :: _) -> s,u | _ -> inconsistent "missing catalogue provenance" in
        [Arch_db.Text artifact; Arch_db.Text source; Arch_db.Text unit_name; Arch_db.Int ordinal; Arch_db.Text status;
         reason; (match decl with None -> Arch_db.Nul | Some (k,_) -> Arch_db.Text k);
         (match decl with None -> Arch_db.Nul | Some (_,n) -> Arch_db.Text n);
         (match formal with None -> Arch_db.Nul | Some f -> Arch_db.Int f.position);
         (match formal with None -> Arch_db.Nul | Some f -> Arch_db.Text f.kind);
         (match formal with None -> Arch_db.Nul | Some f -> Arch_db.text_cell f.key);
         (match formal with None -> Arch_db.Nul | Some f -> Arch_db.text_cell f.name);
         Arch_db.int_cell head; Arch_db.text_cell root; Arch_db.Text argument]
    | _ -> inconsistent "invalid binding row") bindings in
  if List.length rows <> app_count then inconsistent "binding/result coverage disagrees";
  Hashtbl.iter (fun (artifact, _) (key, position, head) ->
    match head with
    | None -> ()
    | Some ordinal ->
        (match Hashtbl.find_opt match_meta (artifact, ordinal) with
         | Some (parent_key, parent_position, _) when parent_key = key && parent_position = position - 1 -> ()
         | _ -> inconsistent "matched parent does not link its preceding formal")) match_meta;
  let matched = List.fold_left (fun n row -> match List.nth row 4 with Arch_db.Text "matched" -> n+1 | _ -> n) 0 rows in
  let total = List.length rows and returned = min limit (List.length rows) in
  [[Arch_db.Text "v1"; Arch_db.Int (List.length inputs); Arch_db.Int (List.length inputs);
    Arch_db.Int total; Arch_db.Int matched; Arch_db.Int (total - matched); Arch_db.Int returned;
    Arch_db.Int (if returned < total then 1 else 0); Arch_db.Text "selected_cmt_local_binding_provenance";
    Arch_db.Text limitations]], List.filteri (fun i _ -> i < returned) rows

let read t ~limit = snapshot t @@ fun () -> read_unwrapped t ~limit
