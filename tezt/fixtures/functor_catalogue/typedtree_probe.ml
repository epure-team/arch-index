(* Test-only native CMT premise probe for the functor catalogue.  It never calls
   the collector: its only oracle is a fresh compiler-libs traversal of the CMT
   it reads/writes.  Synthetic output is explicitly labelled synthetic. *)

open Typedtree

type mode = Census | Papply | Ghost_valid | Invalid_location | Same_position | Unsupported_annotation | Missing_source

let fail fmt = Printf.ksprintf (fun message -> raise (Failure message)) fmt

let mode_of_string = function
  | "census" -> Census
  | "papply" -> Papply
  | "ghost-valid" -> Ghost_valid
  | "invalid-location" -> Invalid_location
  | "same-position" -> Same_position
  | "unsupported-annotation" -> Unsupported_annotation
  | "missing-source" -> Missing_source
  | value -> fail "unknown mode %S" value

let require_fresh_output path =
  if Sys.file_exists path then fail "output must be a fresh path: %s" path

let read_implementation path =
  match Cmt_format.read path with
  | cmi, Some ({Cmt_format.cmt_annots = Cmt_format.Implementation structure; _} as info) ->
      (cmi, info, structure)
  | _ -> fail "input is not an implementation CMT: %s" path

let save ?source_override output info cmi annotations =
  let source_file = Option.value ~default:(
    match info.Cmt_format.cmt_sourcefile with
    | Some source when source <> "" -> source
    | _ -> fail "CMT has no resolvable source mapping") source_override in
  let unit = Unit_info.make ~source_file Unit_info.Impl (Filename.remove_extension output) in
  if Unit_info.modname unit <> info.Cmt_format.cmt_modname then
    fail "output must retain CMT module basename %S (got %S)"
      info.Cmt_format.cmt_modname (Unit_info.modname unit) ;
  let target = Unit_info.cmt unit in
  let prior_input_name = !Location.input_name in
  Fun.protect ~finally:(fun () -> Location.input_name := prior_input_name) @@ fun () ->
  (* save_cmt derives cmt_sourcefile from compiler-global input_name.  Preserve
     the seed metadata so an indexed synthetic artifact remains source-resolvable. *)
  Location.input_name := source_file ;
  Clflags.binary_annotations := true ;
  Cmt_format.save_cmt target annotations
    info.Cmt_format.cmt_initial_env cmi info.Cmt_format.cmt_impl_shape ;
  if not (Sys.file_exists output) then fail "CMT writer did not create %s" output

let valid_position ~file ~line ~column =
  { Lexing.pos_fname = file; pos_lnum = line; pos_bol = 0; pos_cnum = column }

let invalid_location (loc : Location.t) : Location.t =
  { Location.loc_start = { Lexing.pos_fname = ""; pos_lnum = 0; pos_bol = 0; pos_cnum = 0 };
    loc_end = { Lexing.pos_fname = "other-file.ml"; pos_lnum = 0; pos_bol = 0; pos_cnum = 0 };
    loc_ghost = loc.loc_ghost }

let shared_location =
  { Location.loc_start = valid_position ~file:"shared-position.ml" ~line:7 ~column:10;
    loc_end = valid_position ~file:"shared-position.ml" ~line:7 ~column:20;
    loc_ghost = false }

let path_has_apply path =
  let rec loop = function
    | Path.Pident _ -> false
    | Path.Pdot (parent, _) | Path.Pextra_ty (parent, _) -> loop parent
    | Path.Papply _ -> true
  in
  loop path

type census = {
  applies : int;
  apply_units : int;
  papply_paths : int;
  contexts : (string * int) list;
  locations : (bool * bool * string) list;
}

let observe_location (loc : Location.t) =
  let s = loc.loc_start and e = loc.loc_end in
  let sc = s.pos_cnum - s.pos_bol and ec = e.pos_cnum - e.pos_bol in
  let valid = s.pos_fname <> "" && s.pos_fname = e.pos_fname && s.pos_lnum >= 1
    && e.pos_lnum >= 1 && sc >= 0 && ec >= 0
    && (s.pos_lnum < e.pos_lnum || (s.pos_lnum = e.pos_lnum && sc <= ec)) in
  (valid, loc.loc_ghost,
   Printf.sprintf "%s:%d:%d-%s:%d:%d" s.pos_fname s.pos_lnum sc e.pos_fname e.pos_lnum ec)

let census structure =
  let applies = ref 0 and apply_units = ref 0 and papply_paths = ref 0 and locations = ref [] in
  let context = ref ["structure"] and contexts = Hashtbl.create 16 in
  let bump label =
    let prior = Option.value ~default:0 (Hashtbl.find_opt contexts label) in
    Hashtbl.replace contexts label (prior + 1)
  in
  let with_context label f =
    let prior = !context in context := label :: prior ; Fun.protect ~finally:(fun () -> context := prior) f
  in
  let base = Tast_iterator.default_iterator in
  let module_expr self module_expr =
    (match module_expr.mod_desc with
    | Tmod_apply _ -> incr applies ; locations := observe_location module_expr.mod_loc :: !locations ; List.iter bump !context
    | Tmod_apply_unit _ -> incr apply_units ; locations := observe_location module_expr.mod_loc :: !locations ; List.iter bump !context
    | Tmod_ident (path, _) when path_has_apply path -> incr papply_paths
    | _ -> ()) ;
    (match module_expr.mod_desc with
    | Tmod_unpack _ -> with_context "unpack" (fun () -> base.module_expr self module_expr)
    | Tmod_functor _ -> with_context "functorbody" (fun () -> base.module_expr self module_expr)
    | _ -> base.module_expr self module_expr)
  in
  let expression self expression =
    match expression.exp_desc with
    | Texp_letmodule _ -> with_context "localmodule" (fun () -> base.expr self expression)
    | _ -> base.expr self expression
  in
  let structure_item self item =
    match item.str_desc with
    | Tstr_class _ -> with_context "class" (fun () -> base.structure_item self item)
    | _ -> base.structure_item self item
  in
  let module_type self module_type =
    match module_type.mty_desc with
    | Tmty_typeof _ -> with_context "module-type-of" (fun () -> base.module_type self module_type)
    | _ -> base.module_type self module_type
  in
  let iterator = { base with module_expr; expr = expression; structure_item; module_type } in
  iterator.structure iterator structure ;
  { applies = !applies; apply_units = !apply_units; papply_paths = !papply_paths;
    contexts = Hashtbl.to_seq contexts |> List.of_seq |> List.sort compare;
    locations = List.rev !locations }

let census_json c =
  `Assoc
    [ ("apply", `Int c.applies); ("apply_unit", `Int c.apply_units);
      ("papply_paths", `Int c.papply_paths);
      ("contexts", `Assoc (List.map (fun (label, count) -> (label, `Int count)) c.contexts));
      ("locations", `List (List.map (fun (valid, ghost, span) ->
        `Assoc [("valid", `Bool valid); ("ghost", `Bool ghost); ("span", `String span)]) c.locations)) ]

let mutate mode structure =
  let changed = ref 0 and applications = ref 0 in
  let base = Tast_mapper.default in
  let module_expr self module_expr =
    let module_expr = base.module_expr self module_expr in
    match module_expr.mod_desc with
    | Tmod_apply (head, argument, coercion) ->
        incr applications ;
        let module_expr =
          match mode with
          | Papply when !changed = 0 ->
              let rec rewrite_operand operand =
                match operand.mod_desc with
                | Tmod_ident (path, lid) ->
                    changed := 1 ;
                    { operand with mod_desc = Tmod_ident (Path.Papply (path, path), lid) }
                | Tmod_constraint (inner, module_type, constraint_, coercion) ->
                    let inner = rewrite_operand inner in
                    { operand with mod_desc = Tmod_constraint (inner, module_type, constraint_, coercion) }
                | _ -> operand
              in
              { module_expr with mod_desc = Tmod_apply (head, rewrite_operand argument, coercion) }
          | Ghost_valid when !changed = 0 ->
              changed := 1 ; { module_expr with mod_loc = { module_expr.mod_loc with loc_ghost = true } }
          | Invalid_location when !changed = 0 ->
              changed := 1 ; { module_expr with mod_loc = invalid_location module_expr.mod_loc }
          | Same_position when !changed < 2 ->
              incr changed ; { module_expr with mod_loc = shared_location }
          | Census | Papply | Ghost_valid | Invalid_location | Same_position | Unsupported_annotation | Missing_source -> module_expr
        in
        module_expr
    | Tmod_apply_unit _ ->
        incr applications ;
        (match mode with
        | Ghost_valid when !changed = 0 -> changed := 1 ; { module_expr with mod_loc = { module_expr.mod_loc with loc_ghost = true } }
        | Invalid_location when !changed = 0 -> changed := 1 ; { module_expr with mod_loc = invalid_location module_expr.mod_loc }
        | Same_position when !changed < 2 -> incr changed ; { module_expr with mod_loc = shared_location }
        | _ -> module_expr)
    | _ -> module_expr
  in
  let mapper = { base with module_expr } in
  let structure = mapper.structure mapper structure in
  (structure, !applications, !changed)

let json ~mode ~input ~output ~before ~after ~changed =
  `Assoc
    [ ("ok", `Bool true); ("synthetic", `Bool (mode <> Census));
      ("premise", `String (match mode with Census -> "default-iterator-census" | Papply -> "papply" | Ghost_valid -> "ghost-valid" | Invalid_location -> "invalid-location" | Same_position -> "same-position" | Unsupported_annotation -> "unsupported-annotation" | Missing_source -> "missing-source"));
      ("input", `String input); ("output", match output with None -> `Null | Some path -> `String path);
      ("source_resolvable", `Bool (mode <> Missing_source));
      ("changed", `Int changed); ("before", census_json before);
      ("after", match after with None -> `Null | Some value -> census_json value) ]

let source_mapping info =
  match info.Cmt_format.cmt_sourcefile with
  | Some source when source <> "" -> source
  | _ -> fail "CMT has no resolvable source mapping"

let emit ~source value =
  match value with
  | `Assoc fields -> Yojson.Safe.to_channel stdout (`Assoc (("source_mapping", `String source) :: fields))
  | _ -> assert false

let run mode input output =
  let cmi, info, structure = read_implementation input in
  let input_source = source_mapping info in
  let before = census structure in
  match mode with
  | Census -> emit ~source:input_source (json ~mode ~input ~output:None ~before ~after:(Some before) ~changed:0)
  | Papply | Ghost_valid | Invalid_location | Same_position | Unsupported_annotation | Missing_source ->
      let output = match output with Some value -> value | None -> fail "--output is required for synthetic mode" in
      require_fresh_output output ;
      let structure, applications, changed = mutate mode structure in
      if applications = 0 && mode <> Unsupported_annotation then fail "requested premise was not created from input" ;
      if changed = 0 && mode <> Unsupported_annotation && mode <> Missing_source then fail "requested premise was not created from input" ;
      let annotations, source_override = match mode with
        | Unsupported_annotation ->
            (Cmt_format.Interface {sig_items=[]; sig_type=[]; sig_final_env=info.Cmt_format.cmt_initial_env}, None)
        | Missing_source -> (Cmt_format.Implementation structure, Some (Filename.concat (Filename.dirname output) "__functor_catalogue_missing_source__.ml"))
        | _ -> (Cmt_format.Implementation structure, None) in
      (match source_override with
      | Some source ->
          if Sys.file_exists source then fail "missing-source temporary path already exists" ;
          let channel = open_out_bin source in close_out channel ;
          Fun.protect ~finally:(fun () -> if Sys.file_exists source then Sys.remove source) @@ fun () ->
          save ~source_override:source output info cmi annotations
      | None -> save output info cmi annotations) ;
      let reread_cmi, reread_info_option = Cmt_format.read output in
      let reread_info = match reread_info_option with Some value -> value | None -> fail "written CMT cannot be reread" in
      let reread_source = source_mapping reread_info in
      let after = match mode with
        | Unsupported_annotation ->
            (match reread_info.Cmt_format.cmt_annots with Cmt_format.Interface _ -> before | _ -> fail "reread CMT did not retain Interface annotation")
        | _ -> let _, _, reread = read_implementation output in census reread in
      ignore reread_cmi ;
      (match mode with
      | Missing_source when Sys.file_exists reread_source -> fail "reread missing-source metadata is not unresolved"
      | Missing_source -> ()
      | Unsupported_annotation -> ()
      | _ when reread_source <> input_source -> fail "CMT write changed source mapping: %S -> %S" input_source reread_source
      | _ -> ()) ;
      (match mode with
      | Papply when after.papply_paths <= before.papply_paths -> fail "rewritten CMT does not contain Papply"
      | Ghost_valid when not (List.exists (fun (valid, ghost, _) -> valid && ghost) after.locations) -> fail "reread CMT has no valid ghost location"
      | Invalid_location when not (List.exists (fun (valid, _, _) -> not valid) after.locations) -> fail "reread CMT has no invalid location"
      | Same_position when not (List.exists (fun (_, _, span) -> List.length (List.filter (fun (_, _, other) -> other = span) after.locations) >= 2) after.locations) -> fail "reread CMT has no duplicated valid span"
      | _ -> ()) ;
      emit ~source:reread_source (json ~mode ~input ~output:(Some output) ~before ~after:(if mode = Unsupported_annotation then None else Some after) ~changed)

let usage () =
  prerr_endline "usage: typedtree_probe census|papply|ghost-valid|invalid-location|same-position|unsupported-annotation|missing-source --input SEED.cmt [--output FRESH.cmt]" ;
  exit 2

let () =
  try
    match Array.to_list Sys.argv with
    | [_; mode; "--input"; input] -> run (mode_of_string mode) input None
    | [_; mode; "--input"; input; "--output"; output]
    | [_; mode; "--output"; output; "--input"; input] -> run (mode_of_string mode) input (Some output)
    | _ -> usage ()
  with Failure message -> prerr_endline ("typedtree_probe setup: " ^ message) ; exit 2
     | exn -> prerr_endline ("typedtree_probe setup: " ^ Printexc.to_string exn) ; exit 2
