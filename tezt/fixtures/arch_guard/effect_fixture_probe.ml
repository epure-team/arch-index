open Typedtree

let fail fmt = Printf.ksprintf (fun message -> raise (Failure message)) fmt

let accepted = function
  | "%perform" | "%resume" | "%runstack" | "%reperform" -> true
  | _ -> false

let arity = function
  | "%perform" -> 1
  | "%resume" -> 4
  | "%runstack" | "%reperform" -> 3
  | name -> fail "unsupported effect primitive %s" name

let read_implementation path =
  match Cmt_format.read path with
  | cmi, Some ({Cmt_format.cmt_annots = Implementation structure; _} as info) ->
      (cmi, info, structure)
  | _, Some _ -> fail "input must be an implementation CMT: %s" path
  | _, None -> fail "input is not a CMT artifact: %s" path

let rewrite ~input ~output ~primitive_name =
  if not (accepted primitive_name) then
    fail "effect primitive must be %%perform, %%resume, %%runstack, or %%reperform" ;
  if Sys.file_exists output then fail "output must be a fresh owned path: %s" output ;
  let cmi, info, structure = read_implementation input in
  let changed = ref false in
  let base = Tast_mapper.default in
  let expr self expression =
    let expression = base.expr self expression in
    match expression.exp_desc with
    | Texp_apply
        (({exp_desc = Texp_ident (path, lid, description); _} as head), arguments)
      when not !changed -> (
        match description.Types.val_kind with
        | Val_prim {Primitive.prim_name = "%ignore"; _} ->
            changed := true ;
            let primitive =
              Primitive.simple ~name:primitive_name ~arity:(arity primitive_name)
                ~alloc:true
            in
            let description = {description with Types.val_kind = Val_prim primitive} in
            let head = {head with exp_desc = Texp_ident (path, lid, description)} in
            {expression with exp_desc = Texp_apply (head, arguments)}
        | _ -> expression)
    | _ -> expression
  in
  let mapper = {base with expr} in
  let structure = mapper.structure mapper structure in
  if not !changed then fail "no %%ignore application was available for mutation" ;
  let target = Unit_info.Artifact.from_filename output in
  Clflags.binary_annotations := true ;
  Cmt_format.save_cmt target (Implementation structure) info.Cmt_format.cmt_initial_env
    cmi info.Cmt_format.cmt_impl_shape ;
  if not (Sys.file_exists output) then fail "CMT writer did not create %s" output ;
  `Assoc
    [("ok", `Bool true); ("input", `String input); ("output", `String output);
     ("primitive", `String primitive_name); ("changed", `Bool !changed);
     ("scope", `String "test-only Typedtree effect-primitive application seam")]

let usage () =
  prerr_endline
    "usage: effect_fixture_probe --input INPUT.cmt --output OUTPUT.cmt --primitive %perform|%resume|%runstack|%reperform" ;
  exit 2

let rec parse input output primitive_name = function
  | [] ->
      rewrite ~input:(Option.get input) ~output:(Option.get output)
        ~primitive_name:(Option.get primitive_name)
  | "--input" :: value :: rest -> parse (Some value) output primitive_name rest
  | "--output" :: value :: rest -> parse input (Some value) primitive_name rest
  | "--primitive" :: value :: rest -> parse input output (Some value) rest
  | _ -> usage ()

let () =
  try
    if Array.length Sys.argv < 7 then usage () ;
    print_endline
      (Yojson.Safe.to_string
         (parse None None None (List.tl (Array.to_list Sys.argv))))
  with
  | Failure message | Sys_error message ->
      prerr_endline ("effect_fixture_probe: " ^ message) ;
      exit 2
  | Invalid_argument _ -> usage ()
  | Cmt_format.Error _ ->
      prerr_endline "effect_fixture_probe: CMT read/write error" ;
      exit 2
