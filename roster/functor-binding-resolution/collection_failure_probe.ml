(* Writes one premise-checked synthetic Implementation CMT whose Alias binder
   reuses F's Ident. This is deliberately not claimed source-valid. *)

open Typedtree

exception Setup_error of string
exception Assertion_failure of string

let setup fmt = Printf.ksprintf (fun s -> raise (Setup_error s)) fmt
let require condition fmt =
  if condition then Printf.ksprintf ignore fmt
  else Printf.ksprintf (fun s -> raise (Assertion_failure s)) fmt

let read path =
  match Cmt_format.read path with
  | cmi, Some ({Cmt_format.cmt_annots=Implementation structure; _} as info) ->
      (cmi, info, structure)
  | _ -> setup "input is not an implementation CMT: %s" path

let binding structure name =
  match List.find_opt (fun item -> match item.str_desc with
    | Tstr_module binding -> binding.mb_name.Location.txt = Some name
    | _ -> false) structure.str_items with
  | Some {str_desc=Tstr_module binding; _} -> binding
  | _ -> setup "seed module %s is absent" name

let save output info cmi structure =
  let source_file = match info.Cmt_format.cmt_sourcefile with
    | Some source when source <> "" -> source
    | _ -> setup "seed CMT has no source mapping" in
  let unit = Unit_info.make ~source_file Unit_info.Impl (Filename.remove_extension output) in
  require (Unit_info.modname unit = info.Cmt_format.cmt_modname)
    "output basename changes compiler unit (%s <> %s)"
    (Unit_info.modname unit) info.Cmt_format.cmt_modname ;
  let prior = !Location.input_name in
  Fun.protect ~finally:(fun () -> Location.input_name := prior) @@ fun () ->
  Location.input_name := source_file ;
  Clflags.binary_annotations := true ;
  Cmt_format.save_cmt (Unit_info.cmt unit) (Implementation structure)
    info.Cmt_format.cmt_initial_env cmi info.Cmt_format.cmt_impl_shape

let run input output =
  require (not (Sys.file_exists output)) "output must be fresh: %s" output ;
  let cmi, info, structure = read input in
  let f = binding structure "F" and alias = binding structure "Alias" in
  let f_id = Option.get f.mb_id and alias_id = Option.get alias.mb_id in
  require (not (Ident.same f_id alias_id))
    "native seed F and Alias identities are already equal" ;
  let changed =
    {structure with str_items=List.map (fun item -> match item.str_desc with
      | Tstr_module candidate when candidate == alias ->
          {item with str_desc=Tstr_module {candidate with mb_id=Some f_id}}
      | _ -> item) structure.str_items}
  in
  let changed_alias = binding changed "Alias" in
  require (Option.fold ~none:false ~some:(Ident.same f_id) changed_alias.mb_id)
    "synthetic duplicate binder premise was not created" ;
  save output info cmi changed ;
  let _, _, reread = read output in
  require
    (Option.fold ~none:false ~some:(Ident.same (Option.get (binding reread "F").mb_id))
       (binding reread "Alias").mb_id)
    "serialized CMT did not retain duplicate Ident.same binders" ;
  `Assoc
    ["ok", `Bool true;
     "synthetic", `Bool true;
     "source_valid", `Bool false;
     "premise", `String "duplicate-binder-ident-same";
     "serialized", `Bool true]

let () =
  try
    let input, output = match Array.to_list Sys.argv with
      | [_; input; output] -> (input, output)
      | _ -> setup "usage: collection_failure_probe INPUT.cmt OUTPUT.cmt"
    in
    Yojson.Safe.to_channel stdout (run input output) ; output_char stdout '\n'
  with
  | Assertion_failure message ->
      prerr_endline ("collection_failure_probe assertion: " ^ message); exit 1
  | Setup_error message | Sys_error message ->
      prerr_endline ("collection_failure_probe setup: " ^ message); exit 2
  | exn ->
      prerr_endline ("collection_failure_probe unexpected: " ^ Printexc.to_string exn); exit 2
