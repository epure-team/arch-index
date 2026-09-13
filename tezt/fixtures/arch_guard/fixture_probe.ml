open Typedtree

type annotation =
  | Implementation
  | Interface
  | Packed
  | Partial_implementation
  | Partial_interface

type location = Valid | Invalid | Ghost | Cross_file | Backwards | Max_column

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

let primitive = function
  | "%divint" | "%modint" | "%int32_div" | "%int32_mod"
  | "%int64_div" | "%int64_mod" | "%nativeint_div" | "%nativeint_mod" -> true
  | _ -> false

let target_head expression =
  match expression.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) -> primitive prim_name
  | _ -> false

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

let long_identifier =
  Longident.Ldot (Longident.Lident (String.make 200 'a'), String.make 100 'b')

let mutate_structure ~location ~long_identifier_requested ~first_location_file_bytes structure =
  let target_sites = ref 0 in
  let long_identifier_changed = ref false in
  let first_location_file_changed = ref false in
  let base = Tast_mapper.default in
  let expr self expression =
    let expression = base.expr self expression in
    match expression.exp_desc with
    | Texp_apply (head, arguments) when target_head head ->
        incr target_sites ;
        let loc = mutate_location location expression.exp_loc in
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
          if not long_identifier_requested || !long_identifier_changed then arguments
          else
            List.mapi
              (fun index (label, argument) ->
                if index <> 1 then (label, argument)
                else
                  match argument with
                  | Some ({exp_desc = Texp_ident (path, lid, description); _} as operand) ->
                      long_identifier_changed := true ;
                      let lid = {lid with txt = long_identifier} in
                      (label, Some {operand with exp_desc = Texp_ident (path, lid, description)})
                  | Some _ | None -> (label, argument))
              arguments
        in
        {expression with exp_desc = Texp_apply (head, arguments); exp_loc = loc}
    | _ -> expression
  in
  let mapper = {base with expr} in
  let structure = mapper.structure mapper structure in
  (structure, !target_sites, !long_identifier_changed, !first_location_file_changed)

let require_fresh_output path =
  if Sys.file_exists path then fail "output must be a fresh owned path: %s" path

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

let rewrite ~input ~output ~annotation ~location ~long_identifier_requested ~first_location_file_bytes =
  require_fresh_output output ;
  let cmi, info, structure = read_implementation input in
  let structure, target_sites, long_identifier_changed, first_location_file_changed =
    mutate_structure ~location ~long_identifier_requested ~first_location_file_bytes structure
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
  if target_sites = 0 && (location <> Valid || long_identifier_requested) then
    fail "input has no target primitive application to mutate: %s" input ;
  if long_identifier_requested && not long_identifier_changed then
    fail "input has no target primitive whose original slot 2 is an identifier: %s" input ;
  save output info cmi annotations ;
  `Assoc
    [json_bool "ok" true; json_string "input" input; json_string "output" output;
     json_string "annotation"
       (match annotation with Implementation -> "implementation" | Interface -> "interface" | Packed -> "packed"
        | Partial_implementation -> "partial-implementation" | Partial_interface -> "partial-interface");
     json_string "location"
       (match location with Valid -> "valid" | Invalid -> "invalid" | Ghost -> "ghost" | Cross_file -> "cross-file"
        | Backwards -> "backwards" | Max_column -> "max-column");
     json_bool "long_identifier" long_identifier_changed;
     ("first_location_file_bytes", match first_location_file_bytes with None -> `Null | Some bytes -> `Int bytes);
     json_bool "first_location_file_changed" first_location_file_changed;
     ("target_sites", `Int target_sites)]

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
    "usage: fixture_probe rewrite --input INPUT.cmt --output OUTPUT.cmt --annotation implementation|interface|packed|partial-implementation|partial-interface [--location valid|invalid|ghost|cross-file|backwards|max-column] [--long-identifier] [--first-location-file-bytes N] | inspect --input INPUT.cmt | generate --output OUTPUT.ml --kind sites|nest|nodes --count N" ;
  exit 2

let required = function Some value -> value | None -> usage ()

let rec parse_rewrite input output annotation location long_identifier_requested first_location_file_bytes = function
  | [] ->
      let input = required input in
      let output = required output in
      let annotation = required annotation in
      rewrite ~input ~output ~annotation:(annotation_of_string annotation)
        ~location:(location_of_string (match location with Some value -> value | None -> "valid"))
        ~long_identifier_requested ~first_location_file_bytes
  | "--input" :: value :: rest -> parse_rewrite (Some value) output annotation location long_identifier_requested first_location_file_bytes rest
  | "--output" :: value :: rest -> parse_rewrite input (Some value) annotation location long_identifier_requested first_location_file_bytes rest
  | "--annotation" :: value :: rest -> parse_rewrite input output (Some value) location long_identifier_requested first_location_file_bytes rest
  | "--location" :: value :: rest -> parse_rewrite input output annotation (Some value) long_identifier_requested first_location_file_bytes rest
  | "--long-identifier" :: rest -> parse_rewrite input output annotation location true first_location_file_bytes rest
  | "--first-location-file-bytes" :: value :: rest ->
      let bytes = try int_of_string value with Failure _ -> fail "invalid first-location-file-bytes %S" value in
      if bytes < 0 then fail "first-location-file-bytes must be nonnegative" ;
      parse_rewrite input output annotation location long_identifier_requested (Some bytes) rest
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
      | _ :: "rewrite" :: arguments -> parse_rewrite None None None None false None arguments
      | _ :: "inspect" :: arguments -> parse_inspect None arguments
      | _ :: "generate" :: arguments -> parse_generate None None None arguments
      | _ -> usage ()
    in
    print_endline (Yojson.Safe.to_string result)
  with
  | Failure message -> prerr_endline ("fixture_probe: " ^ message) ; exit 2
  | Sys_error message -> prerr_endline ("fixture_probe: " ^ message) ; exit 2
  | Cmt_format.Error _ -> prerr_endline "fixture_probe: CMT read/write error" ; exit 2
