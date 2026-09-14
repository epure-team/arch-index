(* Read-only compiler-native census. No arch-index implementation linked.
   Documentary counts only: not an admission oracle or an implementation test. *)
open Typedtree

let rec shape e =
  match e.exp_desc with
  | Texp_open (o, body) ->
      let m = match o.open_expr.mod_desc with
        | Tmod_ident (p, _) -> "path:" ^ Path.name p
        | _ -> "computed-module"
      in "open(" ^ m ^ ")/" ^ shape body
  | Texp_function (ps, body) ->
      "function:" ^ string_of_int (List.length ps +
        match body with Tfunction_cases _ -> 1 | _ -> 0)
  | Texp_let _ -> "let"
  | Texp_ident _ -> "ident"
  | _ -> "other"

let rec wrapped_function e = match e.exp_desc with
  | Texp_open (_, body) -> wrapped_function body
  | Texp_function _ -> true
  | _ -> false

let inspect file =
  let _, cmt = Cmt_format.read file in
  match cmt with
  | Some {cmt_annots = Implementation structure; _} ->
      let bindings = ref [] in
      let calls = Hashtbl.create 32 in
      let it = {Tast_iterator.default_iterator with
        value_binding = (fun self vb ->
          (match vb.vb_pat.pat_desc, vb.vb_expr.exp_desc with
          | Tpat_var (id, _, uid), Texp_open _ when wrapped_function vb.vb_expr ->
              bindings := (id, uid, vb) :: !bindings
          | _ -> ());
          Tast_iterator.default_iterator.value_binding self vb);
        expr = (fun self e ->
          (match e.exp_desc with
          | Texp_apply ({exp_desc = Texp_ident (Path.Pident id, _, _); _}, _) ->
              let key = Ident.unique_name id in
              let n = Option.value (Hashtbl.find_opt calls key) ~default:0 in
              Hashtbl.replace calls key (n + 1)
          | _ -> ());
          Tast_iterator.default_iterator.expr self e)
      } in
      it.structure it structure;
      List.iter (fun (id, uid, vb) ->
        Printf.printf "%s\t%d\t%s\t%s\t%s\t%d\t%s\n"
          vb.vb_loc.loc_start.pos_fname vb.vb_loc.loc_start.pos_lnum
          (Ident.name id) (Ident.unique_name id)
          (Format.asprintf "%a" Shape.Uid.print uid)
          (Option.value (Hashtbl.find_opt calls (Ident.unique_name id)) ~default:0)
          (shape vb.vb_expr)) (List.rev !bindings)
  | _ -> failwith ("not implementation: " ^ file)

let () = Array.iteri (fun i file -> if i > 0 then inspect file) Sys.argv
