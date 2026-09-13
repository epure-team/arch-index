open Typedtree
module B = Arch_index__Arch_index_bindings
module C = Arch_index__Arch_index_functors
type rhs = Structure | Alias | Application | Functor | Unpack
type binder = { id : Ident.t; rhs : rhs }
let fail fmt = Printf.ksprintf (fun s -> prerr_endline s; exit 2) fmt
let option f = function None -> `Null | Some x -> f x
let rec peel m = match m.mod_desc with Tmod_constraint (x, _, _, _) -> peel x | _ -> m
let rhs m = match (peel m).mod_desc with
  | Tmod_structure _ -> Structure
  | Tmod_ident _ -> Alias
  | Tmod_apply _ | Tmod_apply_unit _ -> Application
  | Tmod_functor _ -> Functor
  | Tmod_unpack _ -> Unpack
  | Tmod_constraint _ -> assert false
let preindex structure =
  let binders = ref [] and parameters = ref [] in
  let parameter = function Named (Some id, _, _) -> parameters := id :: !parameters | _ -> () in
  let base = Tast_iterator.default_iterator in
  let iterator = {base with
    module_binding = (fun self mb ->
      Option.iter (fun id -> binders := {id; rhs = rhs mb.mb_expr} :: !binders) mb.mb_id;
      base.module_binding self mb);
    expr = (fun self e ->
      (match e.exp_desc with
      | Texp_letmodule (Some id, _, _, m, _) -> binders := {id; rhs = rhs m} :: !binders
      | _ -> ());
      base.expr self e);
    module_expr = (fun self m ->
      (match m.mod_desc with Tmod_functor (p, _) -> parameter p | _ -> ());
      base.module_expr self m);
    module_type = (fun self m ->
      (match m.mty_desc with Tmty_functor (p, _) -> parameter p | _ -> ());
      base.module_type self m)} in
  iterator.structure iterator structure;
  (!binders, !parameters)
let rec path_json = function
  | Path.Pident id -> `Assoc ["kind", `String "pident"; "name", `String (Ident.name id);
      "key", `String (Ident.unique_name id); "persistent", `Bool (Ident.persistent id)]
  | Path.Pdot (p, n) -> `Assoc ["kind", `String "pdot"; "parent", path_json p; "member", `String n]
  | Path.Papply (f, a) -> `Assoc ["kind", `String "papply"; "functor", path_json f; "argument", path_json a]
  | Path.Pextra_ty (p, x) ->
      let x = match x with
        | Path.Pcstr_ty n -> `Assoc ["kind", `String "pcstr_ty"; "name", `String n]
        | Path.Pext_ty -> `Assoc ["kind", `String "pext_ty"] in
      `Assoc ["kind", `String "pextra_ty"; "parent", path_json p; "extra", x]
let rec exotic = function
  | Path.Pident _ -> false | Path.Pdot (p, _) -> exotic p
  | Path.Papply _ | Path.Pextra_ty _ -> true
let rec root = function
  | Path.Pident id -> id | Path.Pdot (p, _) | Path.Pextra_ty (p, _) -> root p
  | Path.Papply (p, _) -> root p
let rhs_name = function
  | Structure -> "bound_rhs_structure" | Alias -> "bound_rhs_alias"
  | Application -> "bound_rhs_application" | Functor -> "bound_rhs_functor"
  | Unpack -> "bound_rhs_unpack"
let root_info binders parameters path =
  if exotic path then (`Null, `Null, `String "applied_or_extra_path") else
  let id = root path in
  let category = if Ident.persistent id then "persistent_unit"
    else if List.exists (Ident.same id) parameters then "named_functor_parameter"
    else match List.find_opt (fun b -> Ident.same b.id id) binders with
      | Some b -> rhs_name b.rhs | None -> "unknown_nonpersistent" in
  (`String (Ident.unique_name id), `String (Ident.name id), `String category)
let terminal m =
  let rec loop depth m = match (peel m).mod_desc with
    | Tmod_apply (h, _, _) | Tmod_apply_unit h -> loop (depth + 1) h
    | Tmod_ident (p, _) -> Some (depth, p) | _ -> None in
  loop 0 m
let analyse file =
  let _, cmt = Cmt_format.read file in
  let cmt = match cmt with
    | Some cmt -> cmt
    | None -> fail "not a CMT: %s" file in
  let structure = match cmt.cmt_annots with
    | Cmt_format.Implementation structure -> structure
    | _ -> fail "not an implementation CMT: %s" file in
  let binders, parameters = preindex structure in
  let callbacks = Hashtbl.create 32 in
  let on_application
      ~ordinal ~application_kind:_ ~head_application_ordinal:_ ~head ~argument:_ =
    if Hashtbl.mem callbacks ordinal then
      fail "duplicate callback ordinal %d" ordinal;
    Hashtbl.add callbacks ordinal (terminal head) in
  let catalogue = C.collect ~on_application structure in
  let collected = B.collect structure in
  let occurrences = Hashtbl.create 32 in
  List.iter
    (fun (occurrence : C.occurrence) ->
      if Hashtbl.mem occurrences occurrence.ordinal then
        fail "duplicate catalogue ordinal %d" occurrence.ordinal;
      Hashtbl.add occurrences occurrence.ordinal occurrence)
    catalogue;
  if Hashtbl.length callbacks <> List.length catalogue
     || List.length collected.results <> List.length catalogue
  then fail "ordinal cardinality mismatch";
  let result_ordinals = Hashtbl.create 32 in
  List.iter
    (fun (result : B.result) ->
      if Hashtbl.mem result_ordinals result.ordinal then
        fail "duplicate binding result ordinal %d" result.ordinal;
      Hashtbl.add result_ordinals result.ordinal ())
    collected.results;
  let classes = ref [] in
  let applications = List.map
    (fun (result : B.result) ->
      let occurrence = match Hashtbl.find_opt occurrences result.ordinal with
        | Some occurrence -> occurrence
        | None -> fail "missing catalogue ordinal %d" result.ordinal in
      let observed = match Hashtbl.find_opt callbacks result.ordinal with
        | Some observed -> observed
        | None -> fail "missing callback ordinal %d" result.ordinal in
      let common =
        [ "ordinal", `Int result.ordinal;
          "status", `String result.status;
          "reason", option (fun reason -> `String reason) result.reason ] in
      match result.reason, observed with
      | Some "unsupported_path", Some (depth, path) ->
          let identity_class =
            match List.find_opt (fun (_, prior) -> Path.same prior path) !classes with
            | Some (number, _) -> number
            | None ->
                let number = List.length !classes + 1 in
                classes := !classes @ [(number, path)];
                number in
          let root_key, root_name, root_category =
            root_info binders parameters path in
          `Assoc
            (common @
             [ "location", Yojson.Safe.from_string occurrence.location;
               "terminal_path",
                 `Assoc
                   [ "display", `String (Path.name path);
                     "tree", path_json path ];
               "applied_head_depth", `Int depth;
               "root_key", root_key;
               "root_name", root_name;
               "root_category", root_category;
               "path_identity_class", `Int identity_class ])
      | Some "unsupported_path", None ->
          fail "unsupported_path has no terminal path at %d" result.ordinal
      | _ -> `Assoc common)
    collected.results in
  let imports = List.map
    (fun (name, crc) ->
      `Assoc
        [ "name", `String name;
          "crc", option (fun digest -> `String (Digest.to_hex digest)) crc ])
    cmt.cmt_imports in
  `Assoc
    [ "cmt_modname", `String cmt.cmt_modname;
      "imports", `List imports;
      "interface_digest",
        option (fun digest -> `String (Digest.to_hex digest)) cmt.cmt_interface_digest;
      "applications", `List applications ]
let () = match Array.to_list Sys.argv with
  | [_; file] -> Yojson.Safe.to_channel stdout (analyse file); output_char stdout '\n'
  | _ -> fail "usage: probe CMT"
