(* Documentary compiler-only observation. No arch-index imports or DB reads. *)
open Typedtree

let extra = function
  | Texp_constraint _ -> "constraint"
  | Texp_coerce _ -> "coerce"
  | Texp_poly _ -> "poly"
  | Texp_newtype _ -> "newtype"

let rec shape e =
  match e.exp_desc with
  | Texp_function (params, body) ->
      Printf.sprintf "function(%d,%s)" (List.length params)
        (match body with Tfunction_cases _ -> "cases" | Tfunction_body _ -> "body")
  | Texp_open (opened, body) ->
      Printf.sprintf "open(%s)->%s"
        (match opened.open_expr.mod_desc with Tmod_ident _ -> "ident" | _ -> "computed")
        (shape body)
  | Texp_let _ -> "let"
  | Texp_apply _ -> "apply"
  | Texp_match _ -> "match"
  | Texp_ifthenelse _ -> "if"
  | _ -> "other"

let inspect file =
  let info = Cmt_format.read_cmt file in
  match info.cmt_annots with
  | Cmt_format.Implementation structure ->
      let base = Tast_iterator.default_iterator in
      let rec iter =
        { base with expr = (fun self e ->
              (match e.exp_desc with
              | Texp_let (Asttypes.Recursive, bindings, _) ->
                  List.iter (fun vb ->
                      match vb.vb_pat.pat_desc with
                      | Tpat_var (id, _, _) ->
                          let name = Ident.name id in
                          if List.mem name ["make_proof_argument"; "build_handler"; "aux"] then
                            Printf.printf "%s\t%d\t%s\t%d\t%s\t%s\n"
                              vb.vb_loc.loc_start.pos_fname vb.vb_loc.loc_start.pos_lnum
                              name (List.length bindings) (shape vb.vb_expr)
                              (String.concat "," (List.map (fun (x, _, _) -> extra x) vb.vb_expr.exp_extra))
                      | _ -> ()) bindings
              | _ -> ());
              base.expr self e) }
      in
      iter.structure iter structure
  | _ -> failwith "complete implementation CMT required"

let () = Array.iteri (fun i file -> if i > 0 then inspect file) Sys.argv
