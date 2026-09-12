let take n xs =
  let rec go n acc = function
    | _ when n = 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: rest -> go (n - 1) (x :: acc) rest
  in go n [] xs

module String_set = Set.Make (String)

let selected_ids ids =
  ids
  |> List.map (fun id ->
         match int_of_string_opt id with
         | Some n when n >= 0 -> string_of_int n
         | _ -> raise (Arch_db.Refused (Printf.sprintf "invalid selected origin row id %S" id)))
  |> String.concat ","

let json_for_sites t ~displayed_row_ids ~offender_row_ids =
  if offender_row_ids = [] || not (Arch_db.has_table t "exn_origins") then
    ([], 0, 0)
  else
    let selected = selected_ids offender_row_ids in
    let offenders = String_set.of_list offender_row_ids in
    let displayed = String_set.of_list displayed_row_ids in
    let rows =
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t6'
        ~to_cells:Arch_db.Rows.c6
        ("SELECT CAST(o.id AS TEXT), f.name, COALESCE(m.path,'?'), CAST(o.line AS TEXT), \
         CAST(o.col AS TEXT), o.form FROM exn_origins o JOIN functions f ON f.id=o.function_id \
         LEFT JOIN modules m ON m.id=f.module_id WHERE o.escapes=1 AND o.id IN (" ^ selected ^
         ") ORDER BY f.name,m.path,o.line,o.col,o.id") ()
    in
    let identities = Hashtbl.create 32 in
    (if Arch_db.has_col t "exn_origins" "channel" then
       Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t3'
         ~to_cells:Arch_db.Rows.c3
         ("SELECT CAST(id AS TEXT), COALESCE(exn_path,''), channel FROM exn_origins WHERE id IN (" ^
          selected ^ ") ORDER BY id") ()
       |> List.iter (fun row -> match List.map Arch_db.string_of_cell row with
            | [id; exn; channel] -> Hashtbl.replace identities id (exn, channel) | _ -> ())
     else
       Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t2'
         ~to_cells:Arch_db.Rows.c2
         ("SELECT CAST(id AS TEXT), COALESCE(exn_path,'') FROM exn_origins WHERE id IN (" ^
          selected ^ ") ORDER BY id") ()
       |> List.iter (fun row -> match List.map Arch_db.string_of_cell row with
            | [id; exn] -> Hashtbl.replace identities id (exn, "exception") | _ -> ())) ;
    let metadata = Hashtbl.create 32 in
    let reasons = Hashtbl.create 32 in
    let metadata_types = Hashtbl.create 32 in
    let reason_types = Hashtbl.create 32 in
    if Arch_db.has_col t "exn_origins" "operand_category" then
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t6'
        ~to_cells:Arch_db.Rows.c6
        ("SELECT CAST(id AS TEXT), typeof(operand_primitive), typeof(operand_slot), \
          typeof(operand_category), typeof(operand_repr), typeof(operand_integer_kind) \
          FROM exn_origins WHERE id IN (" ^ selected ^ ") ORDER BY id") ()
      |> List.iter (fun row ->
             match List.map Arch_db.string_of_cell row with
             | [id; primitive; slot; category; repr; kind] ->
                 Hashtbl.replace metadata_types id [primitive; slot; category; repr; kind]
             | _ -> ()) ;
    if Arch_db.has_col t "exn_origins" "operand_category" then
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t6'
        ~to_cells:Arch_db.Rows.c6
        ("SELECT CAST(id AS TEXT), COALESCE(operand_primitive,''), COALESCE(CAST(operand_slot AS TEXT),''), \
         COALESCE(operand_category,''), COALESCE(operand_repr,''), COALESCE(operand_integer_kind,'') \
         FROM exn_origins WHERE id IN (" ^ selected ^ ") ORDER BY id") ()
      |> List.iter (fun row ->
             match List.map Arch_db.string_of_cell row with
             | [id; primitive; slot; category; repr; kind] ->
                 if category <> "" && not (List.mem category ["integer_literal"; "identifier"; "other"; "missing"])
                 then raise (Arch_db.Refused (Printf.sprintf "invalid exn_origins.operand_category %S" category)) ;
                 let slot = if slot = "" then None else
                   match int_of_string_opt slot with Some n -> Some n | None ->
                     raise (Arch_db.Refused (Printf.sprintf "invalid exn_origins.operand_slot %S" slot))
                 in
                 if slot <> None && slot <> Some 2 then
                   raise (Arch_db.Refused (Printf.sprintf "invalid exn_origins.operand_slot %S" (Option.value ~default:"" (Option.map string_of_int slot)))) ;
                 Hashtbl.replace metadata id (primitive, slot, category, repr, kind)
             | _ -> ()) ;
    if Arch_db.has_col t "exn_origins" "operand_unavailable_reason" then
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t2'
        ~to_cells:Arch_db.Rows.c2
        ("SELECT CAST(id AS TEXT), typeof(operand_unavailable_reason) FROM exn_origins \
          WHERE id IN (" ^ selected ^ ") ORDER BY id") ()
      |> List.iter (fun row -> match List.map Arch_db.string_of_cell row with
           | [id; typ] -> Hashtbl.replace reason_types id typ | _ -> ()) ;
    if Arch_db.has_col t "exn_origins" "operand_unavailable_reason" then
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t2'
        ~to_cells:Arch_db.Rows.c2
        ("SELECT CAST(id AS TEXT), COALESCE(operand_unavailable_reason,'') FROM exn_origins \
          WHERE id IN (" ^ selected ^ ") ORDER BY id") ()
      |> List.iter (fun row -> match List.map Arch_db.string_of_cell row with
           | [id; reason] -> Hashtbl.replace reasons id reason | _ -> ()) ;
    let all_contexts =
      List.filter_map
        (fun row -> match List.map Arch_db.string_of_cell row with
          | [id; fn; file; line; col; form] ->
              let exn, channel = Option.value ~default:("", "exception") (Hashtbl.find_opt identities id) in
              let site = Printf.sprintf "%s | %s:%s | %s | %s" fn file line form exn in
              if not (String_set.mem id offenders) then None
              else
                let primitive, slot, category, repr, kind =
                  Option.value ~default:("", None, "", "", "") (Hashtbl.find_opt metadata id)
                in
                let types =
                  Option.value ~default:["null"; "null"; "null"; "null"; "null"]
                    (Hashtbl.find_opt metadata_types id)
                in
                let primitive_type, slot_type, category_type, repr_type, kind_type =
                  match types with
                  | [a; b; c; d; e] -> (a, b, c, d, e)
                  | _ -> ("null", "null", "null", "null", "null")
                in
                let reason_type = Option.value ~default:"null" (Hashtbl.find_opt reason_types id) in
                let require_type field expected actual =
                  if actual <> "null" && actual <> expected then
                    raise (Arch_db.Refused
                      (Printf.sprintf "invalid SQL type for exn_origins.%s: %s" field actual))
                in
                require_type "operand_primitive" "text" primitive_type ;
                require_type "operand_slot" "integer" slot_type ;
                require_type "operand_category" "text" category_type ;
                require_type "operand_repr" "text" repr_type ;
                require_type "operand_integer_kind" "text" kind_type ;
                require_type "operand_unavailable_reason" "text" reason_type ;
                let any_metadata =
                  List.exists (( <> ) "null")
                    [primitive_type; slot_type; category_type; repr_type; kind_type; reason_type]
                in
                if any_metadata && (category = "" || primitive = "" || slot = None || kind = "") then
                  raise (Arch_db.Refused (Printf.sprintf "incomplete operand metadata on exn_origins row %s" id)) ;
                if primitive <> "" && not (List.mem primitive
                    ["%divint"; "%modint"; "%int32_div"; "%int32_mod"; "%int64_div";
                     "%int64_mod"; "%nativeint_div"; "%nativeint_mod"])
                then raise (Arch_db.Refused (Printf.sprintf "invalid exn_origins.operand_primitive %S" primitive)) ;
                if kind <> "" && not (List.mem kind ["int"; "int32"; "int64"; "nativeint"])
                then raise (Arch_db.Refused (Printf.sprintf "invalid exn_origins.operand_integer_kind %S" kind)) ;
                let expected_kind =
                  match primitive with
                  | "%int32_div" | "%int32_mod" -> Some "int32"
                  | "%int64_div" | "%int64_mod" -> Some "int64"
                  | "%nativeint_div" | "%nativeint_mod" -> Some "nativeint"
                  | "%divint" | "%modint" -> Some "int"
                  | _ -> None
                in
                (match expected_kind with
                | Some expected when kind <> expected ->
                    raise (Arch_db.Refused
                      (Printf.sprintf "operand primitive %S is inconsistent with integer kind %S"
                         primitive kind))
                | _ -> ()) ;
                if List.mem category ["other"; "missing"] && repr <> "" then
                  raise (Arch_db.Refused (Printf.sprintf "operand category %S cannot carry a representation" category)) ;
                let unavailable_reason =
                  match Hashtbl.find_opt reasons id with Some s when s <> "" -> Some s | _ -> None
                in
                if List.mem category ["integer_literal"; "identifier"] && repr = ""
                   && unavailable_reason = None then
                  raise (Arch_db.Refused
                    (Printf.sprintf "operand category %S has neither representation nor unavailability reason"
                       category)) ;
                if String.length repr > 256 then
                  raise (Arch_db.Refused "exn_origins.operand_repr exceeds 256 bytes") ;
                let line_number = Option.value ~default:0 (int_of_string_opt line) in
                let column_number = Option.value ~default:0 (int_of_string_opt col) in
                let row_id = Option.value ~default:0 (int_of_string_opt id) in
                Some ((site, line_number, column_number, row_id), `Assoc
                  [("site", `String site); ("channel", `String channel);
                   ("row_id", `Int row_id);
                   ("line", `Int line_number);
                   ("column", `Int column_number);
                   ("availability", `String (if category = "" then "unavailable" else "available"));
                   ("primitive", if primitive = "" then `Null else `String primitive);
                   ("slot", match slot with None -> `Null | Some n -> `Int n);
                   ("category", if category = "" then `Null else `String category);
                   ("representation", if repr = "" then `Null else `String repr);
                   ("integer_kind", if kind = "" then `Null else `String kind);
                   ("unavailable_reason",
                    match unavailable_reason with Some s -> `String s | None -> `Null)])
          | _ -> None)
        rows
    in
    let all_contexts =
      List.sort (fun (left, _) (right, _) -> compare left right) all_contexts
    in
    let total = List.length all_contexts in
    let emitted =
      List.filter_map (fun ((_site, _line, _column, _row_id), json) ->
          match json with
          | `Assoc fields -> (
              match List.assoc_opt "row_id" fields with
              | Some (`Int id) when String_set.mem (string_of_int id) displayed -> Some json
              | _ -> None)
          | _ -> None) all_contexts
      |> take 200
    in
    (emitted, total, total - List.length emitted)
