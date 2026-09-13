open Asttypes
open Typedtree

type annotation =
  | Implementation
  | Interface
  | Packed
  | Partial_implementation
  | Partial_interface

type location = Valid | Invalid | Ghost | Cross_file | Backwards | Max_column

type application_shape =
  | Ordinary
  | Later_saturation
  | Overapplied
  | Overapplied_all
  | Labelled_operand
  | Missing_second_slot

type operand_type = Original | Non_native | Unresolved

let fail fmt = Printf.ksprintf (fun message -> raise (Failure message)) fmt

let annotation_of_string = function
  | "implementation" -> Implementation
  | "interface" -> Interface
  | "packed" -> Packed
  | "partial-implementation" -> Partial_implementation
  | "partial-interface" -> Partial_interface
  | value -> fail "unknown annotation %S" value

let location_of_string = function
  | "valid" -> Valid
  | "invalid" -> Invalid
  | "ghost" -> Ghost
  | "cross-file" -> Cross_file
  | "backwards" -> Backwards
  | "max-column" -> Max_column
  | value -> fail "unknown location %S" value

let application_shape_of_string = function
  | "ordinary" -> Ordinary
  | "later-saturation" -> Later_saturation
  | "overapplied" -> Overapplied
  | "overapplied-all" -> Overapplied_all
  | "labelled-operand" -> Labelled_operand
  | "missing-second-slot" -> Missing_second_slot
  | value -> fail "unknown application shape %S" value

let operand_type_of_string = function
  | "original" -> Original
  | "non-native" -> Non_native
  | "unresolved" -> Unresolved
  | value -> fail "unknown operand type %S" value

let primitive = function
  | "%divint" | "%modint" | "%int32_div" | "%int32_mod"
  | "%int64_div" | "%int64_mod" | "%nativeint_div" | "%nativeint_mod" -> true
  | _ -> false

let target_head expression =
  match expression.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) -> primitive prim_name
  | _ -> false

let zero_guard_head expression =
  match expression.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) ->
      List.mem prim_name ["%equal"; "%notequal"; "%eq"; "%noteq"]
  | _ -> false

let replacement_type = function
  | Original -> invalid_arg "original operand type has no replacement"
  | Non_native -> Predef.type_int64
  | Unresolved -> Btype.newgenty (Types.Tvar None)

let position ~file ~line ~bol ~offset =
  {Lexing.pos_fname = file; pos_lnum = line; pos_bol = bol; pos_cnum = offset}

let mutate_location mode (loc : Location.t) =
  match mode with
  | Valid -> loc
  | Invalid ->
      {loc with loc_start = position ~file:"" ~line:0 ~bol:(-1) ~offset:0;
                loc_end = position ~file:"" ~line:0 ~bol:(-1) ~offset:0}
  | Ghost -> {loc with loc_ghost = true}
  | Cross_file ->
      {loc with loc_start = position ~file:"fixture-probe-a.ml" ~line:1 ~bol:0 ~offset:4;
                loc_end = position ~file:"fixture-probe-b.ml" ~line:1 ~bol:0 ~offset:8}
  | Backwards ->
      {loc with loc_start = position ~file:"fixture-probe.ml" ~line:1 ~bol:0 ~offset:20;
                loc_end = position ~file:"fixture-probe.ml" ~line:1 ~bol:0 ~offset:10}
  | Max_column ->
      {loc with loc_start = position ~file:"fixture-probe.ml" ~line:1 ~bol:0 ~offset:max_int;
                loc_end = position ~file:"fixture-probe.ml" ~line:1 ~bol:0 ~offset:max_int}

let utf8_identifier bytes =
  if bytes < 0 then fail "identifier bytes must be nonnegative" ;
  let buffer = Buffer.create bytes in
  for _ = 1 to bytes / 2 do Buffer.add_string buffer "é" done ;
  if bytes mod 2 = 1 then Buffer.add_char buffer 'a' ;
  Longident.Lident (Buffer.contents buffer)

let mutate_structure ~location ~identifier_bytes ~first_location_file_bytes
    ~application_shape ~operand_type ~operand_slot ~guard_operand_type
    ~guard_operand_slot ~target_site
    ~duplicate_coordinates structure =
  let target_sites = ref 0 in
  let identifier_changed = ref false in
  let first_location_file_changed = ref false in
  let application_changed = ref false in
  let operand_type_changed = ref false in
  let guard_operand_type_changed = ref false in
  let base = Tast_mapper.default in
  let expr self expression =
    let expression = base.expr self expression in
    let expression =
      match guard_operand_type, expression.exp_desc with
      | Original, _ -> expression
      | kind, Texp_apply (head, arguments) when zero_guard_head head ->
          guard_operand_type_changed := true ;
          let arguments = List.mapi (fun index (label, argument) ->
            if Option.fold ~none:true ~some:(fun slot -> index = slot - 1)
                 guard_operand_slot
            then
              (label, Option.map (fun operand ->
                 {operand with exp_type = replacement_type kind}) argument)
            else (label, argument)) arguments in
          {expression with exp_desc = Texp_apply (head, arguments)}
      | _ -> expression
    in
    match expression.exp_desc with
    | Texp_apply (head, arguments) when target_head head ->
        incr target_sites ;
        let selected = Option.fold ~none:true
            ~some:(fun requested -> requested = !target_sites) target_site in
        let loc =
          if duplicate_coordinates then
            let start = position ~file:"duplicate-coordinate.ml" ~line:7 ~bol:100 ~offset:108 in
            let finish = position ~file:"duplicate-coordinate.ml" ~line:7 ~bol:100 ~offset:116 in
            {Location.loc_start = start; loc_end = finish; loc_ghost = false}
          else mutate_location location expression.exp_loc
        in
        let loc =
          match first_location_file_bytes with
          | None -> loc
          | Some _ when !first_location_file_changed -> loc
          | Some bytes ->
              first_location_file_changed := true ;
              let file = String.make bytes 'f' in
              {loc with
               loc_start = {loc.loc_start with pos_fname = file};
               loc_end = {loc.loc_end with pos_fname = file}}
        in
        let arguments =
          if Option.is_none identifier_bytes || !identifier_changed then arguments
          else
            List.mapi
              (fun index (label, argument) ->
                if index <> 1 then (label, argument)
                else
                  match argument with
                  | Some ({exp_desc = Texp_ident (path, lid, description); _} as operand) ->
                      identifier_changed := true ;
                      let lid = {lid with txt = utf8_identifier (Option.get identifier_bytes)} in
                      (label, Some {operand with exp_desc = Texp_ident (path, lid, description)})
                  | Some _ | None -> (label, argument))
              arguments
        in
        let arguments =
          if operand_type = Original || !operand_type_changed || not selected then arguments
          else
            List.mapi
              (fun index (label, argument) ->
                if index <> operand_slot - 1 then (label, argument)
                else
                  match argument with
                  | None -> (label, None)
                  | Some operand ->
                      operand_type_changed := true ;
                      let exp_type = replacement_type operand_type in
                      (label, Some {operand with exp_type}))
              arguments
        in
        let application = {expression with exp_desc = Texp_apply (head, arguments); exp_loc = loc} in
        if (not selected)
           || (!application_changed && application_shape <> Overapplied_all) then application
        else (
          application_changed := application_shape <> Ordinary ;
          match application_shape with
          | Ordinary -> application
          | Later_saturation ->
              let extra = match arguments with (_, Some value) :: _ -> Some value | _ -> None in
              {application with exp_desc = Texp_apply (application, [(Nolabel, extra)])}
          | Overapplied | Overapplied_all ->
              let extra = match arguments with (_, Some value) :: _ -> Some value | _ -> None in
              {application with exp_desc = Texp_apply (head, arguments @ [(Nolabel, extra)])}
          | Labelled_operand ->
              let arguments = List.mapi (fun index (_, value) ->
                if index = 1 then (Labelled "divisor", value) else (Nolabel, value)) arguments in
              {application with exp_desc = Texp_apply (head, arguments)}
          | Missing_second_slot ->
              let original = match List.nth_opt arguments 1 with Some (_, value) -> value | None -> None in
              let arguments = List.mapi (fun index (label, value) ->
                if index = 1 then (label, None) else (label, value)) arguments in
              {application with exp_desc = Texp_apply (head, arguments @ [(Nolabel, original)])})
    | _ -> expression
  in
  let mapper = {base with expr} in
  let structure = mapper.structure mapper structure in
  (structure, !target_sites, !identifier_changed, !first_location_file_changed,
   !application_changed, !operand_type_changed, !guard_operand_type_changed)

let require_fresh_output path =
  if Sys.file_exists path then fail "output must be a fresh owned path: %s" path

let observed_type ty =
  match Types.get_desc ty with
  | Tconstr (path, [], _) when Path.same path Predef.path_int -> "int"
  | Tconstr (path, [], _) when Path.same path Predef.path_int64 -> "int64"
  | Tvar _ | Tunivar _ -> "unresolved"
  | _ -> "other"

let observe_target_operand_types structure =
  let site = ref 0 in
  let observed = ref [] in
  let base = Tast_iterator.default_iterator in
  let expr self expression =
    (match expression.exp_desc with
    | Texp_apply (head, arguments) when target_head head ->
        incr site ;
        List.iteri
          (fun index argument ->
            let value =
              match snd argument with
              | None -> `Null
              | Some operand -> `String (observed_type operand.exp_type)
            in
            observed :=
              `Assoc
                [("site", `Int !site); ("slot", `Int (index + 1));
                 ("type", value)]
              :: !observed)
          arguments
    | _ -> ()) ;
    base.expr self expression
  in
  let iterator = {base with expr} in
  iterator.structure iterator structure ;
  List.rev !observed

let read_implementation path =
  match Cmt_format.read path with
  | cmi, Some info -> (
      match info.Cmt_format.cmt_annots with
      | Cmt_format.Implementation structure -> (cmi, info, structure)
      | _ -> fail "input must be an implementation CMT: %s" path)
  | _, None -> fail "input is not a CMT artifact: %s" path

let save output info cmi annotations =
  let target = Unit_info.Artifact.from_filename output in
  Clflags.binary_annotations := true ;
  Cmt_format.save_cmt target annotations info.Cmt_format.cmt_initial_env cmi info.Cmt_format.cmt_impl_shape ;
  if not (Sys.file_exists output) then
    fail "Cmt_format.save_cmt did not create requested output: %s" output

let json_bool name value = (name, `Bool value)
let json_string name value = (name, `String value)

let rewrite ~input ~output ~annotation ~location ~identifier_bytes ~first_location_file_bytes
    ~application_shape ~operand_type ~operand_slot ~guard_operand_type
    ~guard_operand_slot ~target_site
    ~duplicate_coordinates =
  require_fresh_output output ;
  let cmi, info, structure = read_implementation input in
  let structure, target_sites, identifier_changed, first_location_file_changed,
      application_changed, operand_type_changed, guard_operand_type_changed =
    mutate_structure ~location ~identifier_bytes ~first_location_file_bytes
      ~application_shape ~operand_type ~operand_slot ~guard_operand_type
      ~guard_operand_slot ~target_site
      ~duplicate_coordinates structure
  in
  let annotations =
    match annotation with
    | Implementation -> Cmt_format.Implementation structure
    | Interface ->
        Cmt_format.Interface
          {sig_items = []; sig_type = []; sig_final_env = info.Cmt_format.cmt_initial_env}
    | Packed -> Cmt_format.Packed ([], [])
    | Partial_implementation -> Cmt_format.Partial_implementation [||]
    | Partial_interface -> Cmt_format.Partial_interface [||]
  in
  if target_sites = 0 &&
     (location <> Valid || Option.is_some identifier_bytes || application_shape <> Ordinary
      || operand_type <> Original || guard_operand_type <> Original
      || duplicate_coordinates) then
    fail "input has no target primitive application to mutate: %s" input ;
  if Option.is_some identifier_bytes && not identifier_changed then
    fail "input has no target primitive whose original slot 2 is an identifier: %s" input ;
  if application_shape <> Ordinary && not application_changed then
    fail "requested application mutation did not select a target site: %s" input ;
  if operand_type <> Original && not operand_type_changed then
    fail "requested operand-type mutation did not find a present selected operand: %s" input ;
  if guard_operand_type <> Original && not guard_operand_type_changed then
    fail "requested guard operand-type mutation found no zero comparison: %s" input ;
  let observed_operand_types = observe_target_operand_types structure in
  save output info cmi annotations ;
  `Assoc
    [json_bool "ok" true; json_string "input" input; json_string "output" output;
     json_string "annotation"
       (match annotation with Implementation -> "implementation" | Interface -> "interface" | Packed -> "packed"
        | Partial_implementation -> "partial-implementation" | Partial_interface -> "partial-interface");
     json_string "location"
       (match location with Valid -> "valid" | Invalid -> "invalid" | Ghost -> "ghost" | Cross_file -> "cross-file"
        | Backwards -> "backwards" | Max_column -> "max-column");
     ("identifier_bytes", match identifier_bytes with None -> `Null | Some bytes -> `Int bytes);
     json_bool "identifier_changed" identifier_changed;
     ("first_location_file_bytes", match first_location_file_bytes with None -> `Null | Some bytes -> `Int bytes);
     json_bool "first_location_file_changed" first_location_file_changed;
     json_bool "application_changed" application_changed;
     json_bool "operand_type_changed" operand_type_changed;
     ("operand_slot", `Int operand_slot);
     json_bool "guard_operand_type_changed" guard_operand_type_changed;
     ("guard_operand_slot", match guard_operand_slot with None -> `Null | Some slot -> `Int slot);
     ("target_site", match target_site with None -> `Null | Some site -> `Int site);
     json_bool "duplicate_coordinates" duplicate_coordinates;
     ("target_sites", `Int target_sites);
     ("observed_operand_types", `List observed_operand_types)]

let inspect input =
  let _, _, structure = read_implementation input in
  let nodes = ref 0 in
  let depth = ref 0 in
  let max_depth = ref 0 in
  let target_sites = ref 0 in
  let base = Tast_iterator.default_iterator in
  let expr self expression =
    incr nodes ;
    incr depth ;
    max_depth := max !max_depth !depth ;
    (match expression.exp_desc with
    | Texp_apply (head, _) when target_head head -> incr target_sites
    | _ -> ()) ;
    base.expr self expression ;
    decr depth
  in
  let iterator = {base with expr} in
  iterator.structure iterator structure ;
  `Assoc
    [json_bool "ok" true; json_string "input" input;
     ("expression_nodes", `Int !nodes); ("max_expression_depth", `Int !max_depth);
     ("target_sites", `Int !target_sites);
     json_string "scope" "independent Typedtree traversal; no arch_guard inventory is imported"]

let generated_source kind count =
  if count < 0 then fail "count must be nonnegative" ;
  match kind with
  | "sites" ->
      let lines = Buffer.create (max 128 (count * 28)) in
      Buffer.add_string lines "let probe d =\n" ;
      for _ = 1 to count do Buffer.add_string lines "  ignore (10 / d);\n" done ;
      Buffer.add_string lines "  0\n" ;
      Buffer.contents lines
  | "nest" ->
      let lines = Buffer.create (max 128 (count * 28)) in
      Buffer.add_string lines "let probe d =\n" ;
      for _ = 1 to count do Buffer.add_string lines "  if true then (\n" done ;
      Buffer.add_string lines "  10 / d" ;
      for _ = 1 to count do Buffer.add_string lines ") else 0" done ;
      Buffer.add_char lines '\n' ;
      Buffer.contents lines
  | "nodes" ->
      let lines = Buffer.create (max 128 (count * 20)) in
      Buffer.add_string lines "let probe d =\n" ;
      for _ = 1 to count do Buffer.add_string lines "  ignore d;\n" done ;
      Buffer.add_string lines "  10 / d\n" ;
      Buffer.contents lines
  | value -> fail "unknown generator kind %S" value

let generate ~output ~kind ~count =
  require_fresh_output output ;
  let channel = open_out_bin output in
  Fun.protect ~finally:(fun () -> close_out_noerr channel) @@ fun () ->
  output_string channel (generated_source kind count) ;
  `Assoc
    [json_bool "ok" true; json_string "output" output; json_string "kind" kind;
     ("count", `Int count);
     json_string "scope" "generated-source request only; compile then invoke the actual CLI to measure a limit"]

let usage () =
  prerr_endline
    "usage: fixture_probe rewrite --input INPUT.cmt --output OUTPUT.cmt --annotation implementation|interface|packed|partial-implementation|partial-interface [--location valid|invalid|ghost|cross-file|backwards|max-column] [--identifier-bytes N] [--application-shape ordinary|later-saturation|overapplied|overapplied-all|labelled-operand|missing-second-slot] [--operand-type original|non-native|unresolved] [--operand-slot 1|2] [--guard-operand-type original|non-native|unresolved] [--guard-operand-slot 1|2] [--target-site N] [--duplicate-coordinates] [--first-location-file-bytes N] | inspect --input INPUT.cmt | generate --output OUTPUT.ml --kind sites|nest|nodes --count N" ;
  exit 2

let required = function Some value -> value | None -> usage ()

let rec parse_rewrite input output annotation location identifier_bytes first_location_file_bytes
    application_shape operand_type operand_slot guard_operand_type guard_operand_slot
    target_site duplicate_coordinates = function
  | [] ->
      let input = required input in
      let output = required output in
      let annotation = required annotation in
      rewrite ~input ~output ~annotation:(annotation_of_string annotation)
        ~location:(location_of_string (match location with Some value -> value | None -> "valid"))
        ~identifier_bytes ~first_location_file_bytes
        ~application_shape:(application_shape_of_string (Option.value ~default:"ordinary" application_shape))
        ~operand_type:(operand_type_of_string (Option.value ~default:"original" operand_type))
        ~operand_slot
        ~guard_operand_type:(operand_type_of_string (Option.value ~default:"original" guard_operand_type))
        ~guard_operand_slot ~target_site ~duplicate_coordinates
  | "--input" :: value :: rest -> parse_rewrite (Some value) output annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--output" :: value :: rest -> parse_rewrite input (Some value) annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--annotation" :: value :: rest -> parse_rewrite input output (Some value) location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--location" :: value :: rest -> parse_rewrite input output annotation (Some value) identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--long-identifier" :: rest -> parse_rewrite input output annotation location (Some 301) first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--identifier-bytes" :: value :: rest ->
      let bytes = try int_of_string value with Failure _ -> fail "invalid identifier bytes %S" value in
      parse_rewrite input output annotation location (Some bytes) first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--application-shape" :: value :: rest -> parse_rewrite input output annotation location identifier_bytes first_location_file_bytes (Some value) operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--operand-type" :: value :: rest -> parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape (Some value) operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--operand-slot" :: value :: rest ->
      let slot = try int_of_string value with Failure _ -> fail "invalid operand slot %S" value in
      if slot <> 1 && slot <> 2 then fail "operand slot must be 1 or 2" ;
      parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape operand_type slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | "--guard-operand-type" :: value :: rest -> parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot (Some value) guard_operand_slot target_site duplicate_coordinates rest
  | "--guard-operand-slot" :: value :: rest ->
      let slot = try int_of_string value with Failure _ -> fail "invalid guard operand slot %S" value in
      if slot <> 1 && slot <> 2 then fail "guard operand slot must be 1 or 2" ;
      parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type (Some slot) target_site duplicate_coordinates rest
  | "--target-site" :: value :: rest ->
      let site = try int_of_string value with Failure _ -> fail "invalid target site %S" value in
      if site < 1 then fail "target site must be positive" ;
      parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot (Some site) duplicate_coordinates rest
  | "--duplicate-coordinates" :: rest -> parse_rewrite input output annotation location identifier_bytes first_location_file_bytes application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site true rest
  | "--first-location-file-bytes" :: value :: rest ->
      let bytes = try int_of_string value with Failure _ -> fail "invalid first-location-file-bytes %S" value in
      if bytes < 0 then fail "first-location-file-bytes must be nonnegative" ;
      parse_rewrite input output annotation location identifier_bytes (Some bytes) application_shape operand_type operand_slot guard_operand_type guard_operand_slot target_site duplicate_coordinates rest
  | _ -> usage ()

let rec parse_inspect input = function
  | [] -> inspect (required input)
  | "--input" :: value :: rest -> parse_inspect (Some value) rest
  | _ -> usage ()

let rec parse_generate output kind count = function
  | [] ->
      let output = required output in
      let kind = required kind in
      let count = required count in
      generate ~output ~kind ~count
  | "--output" :: value :: rest -> parse_generate (Some value) kind count rest
  | "--kind" :: value :: rest -> parse_generate output (Some value) count rest
  | "--count" :: value :: rest ->
      let count = try int_of_string value with Failure _ -> fail "invalid count %S" value in
      parse_generate output kind (Some count) rest
  | _ -> usage ()

let () =
  try
    let result =
      match Array.to_list Sys.argv with
      | _ :: "rewrite" :: arguments -> parse_rewrite None None None None None None None None 2 None None None false arguments
      | _ :: "inspect" :: arguments -> parse_inspect None arguments
      | _ :: "generate" :: arguments -> parse_generate None None None arguments
      | _ -> usage ()
    in
    print_endline (Yojson.Safe.to_string result)
  with
  | Failure message -> prerr_endline ("fixture_probe: " ^ message) ; exit 2
  | Sys_error message -> prerr_endline ("fixture_probe: " ^ message) ; exit 2
  | Cmt_format.Error _ -> prerr_endline "fixture_probe: CMT read/write error" ; exit 2
