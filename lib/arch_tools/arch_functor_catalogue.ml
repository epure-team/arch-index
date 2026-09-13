let limitations =
  "not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections"

let required =
  ["producer_runs",["id"]; "modules",["id";"path"]; "comment_db_meta",["key";"value"];
   "functor_catalogue_runs",["producer_run_id";"selected_inputs"];
   "functor_catalogue_inputs",["producer_run_id";"artifact";"source";"compiler_unit";"module_id";"outcome";"expected_applications"];
   "functor_applications",["producer_run_id";"artifact";"ordinal";"application_kind";"location";"head";"argument";"diagnostics"]]

let inconsistent fmt = Printf.ksprintf (Arch_db.refuse "INCONSISTENT_CATALOGUE: %s") fmt
let json label s =
  try Yojson.Safe.from_string s
  with Yojson.Json_error _ -> inconsistent "malformed %s JSON" label
let exact fs ks = List.sort compare (List.map fst fs) = List.sort compare ks

let rec descriptor = function
  | `Assoc (["kind", `String "structure"] | ["kind", `String "unpack"]
           | ["kind", `String "unit"]) as j -> j
  | `Assoc fs as j when exact fs ["kind"; "compiler"; "source"; "contains_apply"] ->
      (match List.assoc_opt "kind" fs, List.assoc_opt "compiler" fs,
             List.assoc_opt "source" fs, List.assoc_opt "contains_apply" fs with
      | Some (`String "path"), Some (`String _), Some (`String _), Some (`Bool _) -> j
      | _ -> inconsistent "invalid path descriptor")
  | `Assoc fs as j when exact fs ["kind"; "parameter"; "name"] ->
      (match List.assoc_opt "kind" fs, List.assoc_opt "parameter" fs,
             List.assoc_opt "name" fs with
      | Some (`String "functor"), Some (`String "unit"), Some `Null -> j
      | Some (`String "functor"), Some (`String "named"),
        (Some `Null | Some (`String _)) -> j
      | _ -> inconsistent "invalid functor descriptor")
  | `Assoc fs as j when exact fs ["kind"; "ordinal"] ->
      (match List.assoc_opt "kind" fs, List.assoc_opt "ordinal" fs with
      | Some (`String "application"), Some (`Int n) when n > 0 -> j
      | _ -> inconsistent "invalid application descriptor")
  | `Assoc fs as j when exact fs ["kind"; "expression"] ->
      (match List.assoc_opt "kind" fs, List.assoc_opt "expression" fs with
      | Some (`String "constraint"), Some d -> ignore (descriptor d); j
      | _ -> inconsistent "invalid constraint descriptor")
  | _ -> inconsistent "descriptor violates closed v1 grammar"

let rec stripped_kind = function
  | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "constraint") ->
      stripped_kind (List.assoc "expression" fs)
  | `Assoc fs -> (match List.assoc_opt "kind" fs with Some (`String s) -> s | _ -> "")
  | _ -> ""

let direct_kind = function
  | `Assoc fs -> (match List.assoc_opt "kind" fs with Some (`String s) -> s | _ -> "")
  | _ -> ""

let descriptor_refs d =
  let rec go acc = function
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "application") ->
        (match List.assoc_opt "ordinal" fs with Some (`Int n) -> n :: acc | _ -> acc)
    | `Assoc fs when List.assoc_opt "kind" fs = Some (`String "constraint") ->
        go acc (List.assoc "expression" fs)
    | _ -> acc
  in
  go [] d

let location = function
  | `Assoc fs when exact fs ["file";"start_line";"start_col";"end_line";"end_col";"ghost"] ->
      let ghost =
        match List.assoc_opt "ghost" fs with Some (`Bool _) -> true | _ -> false
      in
      let null =
        List.for_all (fun k -> List.assoc_opt k fs = Some `Null)
          ["file"; "start_line"; "start_col"; "end_line"; "end_col"]
      in
      let valid =
        match List.assoc_opt "file" fs, List.assoc_opt "start_line" fs,
              List.assoc_opt "start_col" fs, List.assoc_opt "end_line" fs,
              List.assoc_opt "end_col" fs with
        | Some (`String f), Some (`Int sl), Some (`Int sc), Some (`Int el), Some (`Int ec) ->
            f <> "" && sl >= 1 && el >= 1 && sc >= 0 && ec >= 0
            && (sl < el || sl = el && sc <= ec)
        | _ -> false
      in
      if ghost && (null || valid) then null else inconsistent "invalid location"
  | _ -> inconsistent "location violates closed v1 grammar"

let cells t shape conv sql =
  Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape ~to_cells:conv sql ()

let int field value_type value =
  if value_type <> "integer" then inconsistent "%s is not an integer" field;
  try int_of_string value
  with Failure _ -> inconsistent "%s is outside OCaml integer range" field

let count t sql =
  let query = "SELECT CAST(count(*) AS TEXT) FROM (" ^ sql ^ ")" in
  match cells t Arch_db.Rows.t1 Arch_db.Rows.c1 query with
  | [[Arch_db.Text value]] -> int "count" "integer" value
  | _ -> inconsistent "invalid count"
let quote = Arch_db.quote_lit
let snapshot t f =
  let module Db = (val t.Arch_db.conn : Arch_db.C.CONNECTION) in
  Arch_db.ok (Db.start ());
  match f () with
  | value ->
      Arch_db.ok (Db.commit ());
      value
  | exception exn ->
      (match Db.rollback () with
      | Ok () -> ()
      | Error error -> Arch_db.broken "%s" (Caqti_error.show error));
      raise exn

type input = {
  run : int;
  artifact : string;
  source : string;
  unit_name : string;
  expected : int;
}

let read t ~limit = snapshot t @@ fun () ->
  if Arch_db.has_col t "calls" "caller_name" || List.exists(fun(tbl,cs)->not(Arch_db.has_table t tbl)||List.exists(fun c->not(Arch_db.has_col t tbl c))cs)required
  then Arch_db.refuse "UNSUPPORTED_SCHEMA: functor catalogue v1 tables/columns are absent";
  let marker =
    cells t Arch_db.Rows.t2' Arch_db.Rows.c2
      "SELECT typeof(value),CASE WHEN typeof(value)='text' THEN value ELSE NULL END FROM comment_db_meta WHERE key='functor_catalogue_contract'"
  in
  if marker <> [[Arch_db.Text "text"; Arch_db.Text "v1"]] then begin
    let outcomes =
      ["unreadable"; "unsupported_annotation"; "missing_source";
       "dropped_module"; "collection_failed"]
    in
    let summary =
      outcomes
      |> List.map (fun outcome ->
        let query = Printf.sprintf
          "SELECT 1 FROM functor_catalogue_inputs WHERE outcome='%s'" outcome
        in
        Printf.sprintf "%s=%d" outcome (count t query))
      |> String.concat ","
    in
    Arch_db.refuse
      "NOT_COLLECTED: functor catalogue contract v1 is absent (failed outcomes: %s)"
      summary
  end;
  let hs=cells t Arch_db.Rows.t4' Arch_db.Rows.c4 "SELECT typeof(producer_run_id),CAST(producer_run_id AS TEXT),typeof(selected_inputs),CAST(selected_inputs AS TEXT) FROM functor_catalogue_runs ORDER BY producer_run_id" in
  let run, selected =
    match hs with
    | [[Arch_db.Text rt; Arch_db.Text rv; Arch_db.Text st; Arch_db.Text sv]] ->
        int "producer_run_id" rt rv, int "selected_inputs" st sv
    | _ -> inconsistent "expected exactly one run header"
  in
  if selected <= 0 then inconsistent "selected_inputs is not positive";
  if count t (Printf.sprintf "SELECT 1 FROM producer_runs WHERE id=%d" run) <> 1 then
    inconsistent "header is not linked to a producer";
  if count t "SELECT 1 FROM functor_catalogue_inputs i WHERE NOT EXISTS(SELECT 1 FROM functor_catalogue_runs r WHERE r.producer_run_id=i.producer_run_id)"<>0 || count t "SELECT 1 FROM functor_applications a WHERE NOT EXISTS(SELECT 1 FROM functor_catalogue_inputs i WHERE i.producer_run_id=a.producer_run_id AND i.artifact=a.artifact)"<>0 then inconsistent "orphan catalogue rows exist";
  if count t
       "SELECT 1 FROM functor_catalogue_inputs WHERE typeof(artifact)<>'text' OR typeof(source)<>'text' OR typeof(compiler_unit)<>'text' OR typeof(outcome)<>'text'"
     <> 0
  then inconsistent "input text value has an invalid SQLite storage class";
  if count t
       "SELECT 1 FROM functor_applications WHERE typeof(artifact)<>'text' OR typeof(application_kind)<>'text' OR typeof(location)<>'text' OR typeof(head)<>'text' OR typeof(argument)<>'text' OR typeof(diagnostics)<>'text'"
     <> 0
  then inconsistent "application text value has an invalid SQLite storage class";
  let shape10 = Arch_db.Ty.(
    t2 (t5 (option string) (option string) (option string) (option string) (option string))
       (t5 (option string) (option string) (option string) (option string) (option string)))
  in
  let conv10 ((a, b, c, d, e), (f, g, h, i, j)) =
    List.map Arch_db.text_cell [a; b; c; d; e; f; g; h; i; j]
  in
  let irs=cells t shape10 conv10 "SELECT typeof(producer_run_id),CAST(producer_run_id AS TEXT),artifact,source,compiler_unit,outcome,typeof(module_id),CAST(module_id AS TEXT),typeof(expected_applications),CAST(expected_applications AS TEXT) FROM functor_catalogue_inputs ORDER BY artifact" in
  if List.length irs<>selected then inconsistent "selected/input counts disagree";
  let seen=Hashtbl.create selected in
  let inputs = List.map (function
    | [Arch_db.Text rt; Arch_db.Text rv; Arch_db.Text artifact; Arch_db.Text source;
       Arch_db.Text unit_name; Arch_db.Text outcome; Arch_db.Text mt; Arch_db.Text mv;
       Arch_db.Text et; Arch_db.Text ev] ->
        let r = int "input producer_run_id" rt rv
        and mid = int "module_id" mt mv
        and expected = int "expected_applications" et ev in
        if r <> run || artifact = "" || source = "" || unit_name = ""
           || outcome <> "collected" || expected < 0 then
          inconsistent "invalid collected input";
        if Hashtbl.mem seen artifact then inconsistent "duplicate artifact"
        else Hashtbl.add seen artifact ();
        if count t (Printf.sprintf "SELECT 1 FROM modules WHERE id=%d AND path='%s'"
                      mid (quote source)) <> 1 then
          inconsistent "invalid module/source linkage";
        {run = r; artifact; source; unit_name; expected}
    | _ -> inconsistent "invalid input row") irs
  in
  let ars=cells t shape10 conv10 "SELECT typeof(producer_run_id),CAST(producer_run_id AS TEXT),artifact,typeof(ordinal),CAST(ordinal AS TEXT),application_kind,location,head,argument,diagnostics FROM functor_applications ORDER BY artifact,ordinal" in
  let public, decoded = List.split (List.map (function
    | [Arch_db.Text rt; Arch_db.Text rv; Arch_db.Text artifact; Arch_db.Text ot;
       Arch_db.Text ov; Arch_db.Text kind; Arch_db.Text ls; Arch_db.Text hs;
       Arch_db.Text as_; Arch_db.Text ds] ->
        let r = int "application producer_run_id" rt rv
        and ordinal = int "ordinal" ot ov in
        let inp =
          match List.find_opt (fun i -> i.run = r && i.artifact = artifact) inputs with
          | Some i -> i
          | None -> inconsistent "application has no same-run input"
        in
        if ordinal <= 0 || (kind <> "apply" && kind <> "apply_unit") then
          inconsistent "invalid application row";
        let loc = json "location" ls and head = descriptor (json "head" hs)
        and arg = descriptor (json "argument" as_) and diags = json "diagnostics" ds in
        let bad = location loc in
        let expected =
          ((if stripped_kind head <> "path" && stripped_kind head <> "application"
            then ["opaque_functor_head"] else [])
          @ (if stripped_kind arg = "structure" then ["anonymous_argument"] else [])
          @ (if stripped_kind head = "unpack" || stripped_kind arg = "unpack"
             then ["unpacked_expression"] else [])
          @ (if bad then ["unusable_location"] else []))
          |> List.sort_uniq compare
        in
        let actual = match diags with
          | `List xs -> List.map (function
              | `String s -> s
              | _ -> inconsistent "non-string diagnostic") xs
          | _ -> inconsistent "diagnostics is not an array"
        in
        if actual <> expected then inconsistent "diagnostics do not match operands/location";
        if stripped_kind head = "unit"
           || (kind = "apply_unit") <> (direct_kind arg = "unit")
           || (kind = "apply" && stripped_kind arg = "unit") then
          inconsistent "unit descriptor/kind mismatch";
        ([Arch_db.Text artifact; Arch_db.Text inp.source; Arch_db.Text inp.unit_name;
          Arch_db.Int ordinal; Arch_db.Text kind; Arch_db.Text ls; Arch_db.Text hs;
          Arch_db.Text as_; Arch_db.Text ds],
         (artifact, ordinal, descriptor_refs head @ descriptor_refs arg))
    | _ -> inconsistent "invalid application row") ars)
  in
  List.iter (fun i ->
    if List.fold_left (fun n (a, _, _) -> n + if a = i.artifact then 1 else 0)
         0 decoded <> i.expected then
      inconsistent "per-input expected count disagrees") inputs;
  List.iter (fun i ->
    let es = List.filter (fun (a, _, _) -> a = i.artifact) decoded in
    let os = List.map (fun (_, o, _) -> o) es |> List.sort compare in
    if os <> List.init (List.length os) (fun n -> n + 1) then
      inconsistent "ordinals are not contiguous";
    List.iter (fun (_, o, rs) ->
      List.iter (fun r ->
        if r <= o || not (List.mem r os) then
          inconsistent "invalid forward same-input reference") rs) es) inputs;
  let total = List.length public and returned = min limit (List.length public) in
  [[Arch_db.Text "v1"; Arch_db.Int selected; Arch_db.Int selected; Arch_db.Int total;
    Arch_db.Int returned; Arch_db.Int (if returned < total then 1 else 0);
    Arch_db.Text "selected_cmt_syntax_only"; Arch_db.Text limitations]],
  List.filteri (fun i _ -> i < returned) public
