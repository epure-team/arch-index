(* Independent compiler-native endpoint witness. No arch-index modules linked. *)
open Typedtree
let q s =
  let b = Buffer.create 32 in
  Buffer.add_char b '"'; String.iter (function
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t" | c when Char.code c < 32 ->
      Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) s; Buffer.add_char b '"'; Buffer.contents b
let obj xs = "{" ^ String.concat "," (List.map (fun (k,v) -> q k ^ ":" ^ v) xs) ^ "}"
let arr xs = "[" ^ String.concat "," xs ^ "]"
let uid u = q (Format.asprintf "%a" Shape.Uid.print u)
let resolution = function
  | Shape_reduce.Resolved u -> obj ["kind",q "Resolved";"uid",uid u]
  | Shape_reduce.Resolved_alias (u,_) -> obj ["kind",q "Resolved_alias";"uid",uid u]
  | Shape_reduce.Unresolved _ -> obj ["kind",q "Unresolved"]
  | Shape_reduce.Approximated u -> obj ["kind",q "Approximated";"uid",(match u with None -> "null" | Some u -> uid u)]
  | Shape_reduce.Internal_error_missing_uid -> obj ["kind",q "Internal_error_missing_uid"]
let loc l = obj ["file",q l.Location.loc_start.pos_fname;
  "start",string_of_int l.loc_start.pos_lnum; "end",string_of_int l.loc_end.pos_lnum;
  "start_offset",string_of_int l.loc_start.pos_cnum; "end_offset",string_of_int l.loc_end.pos_cnum;
  "column",string_of_int (l.loc_start.pos_cnum-l.loc_start.pos_bol);
  "ghost",string_of_bool l.loc_ghost]
let arity e = match e.exp_desc with Texp_function (ps,b) ->
  List.length ps + (match b with Tfunction_cases _ -> 1 | _ -> 0) | _ -> 0
let () =
  for ai = 1 to Array.length Sys.argv - 1 do
    let file = Sys.argv.(ai) in
    let c = Cmt_format.read_cmt file in
    let binds = ref [] and ids = ref [] and apps = ref [] and functions = ref [] and callback_uses = ref [] in
    let d = Tast_iterator.default_iterator in
    let iter = {d with value_binding = (fun self v ->
      (match v.vb_pat.pat_desc with Tpat_var (_,name,u) ->
        binds := (u,name.txt,v.vb_loc,v.vb_expr.exp_loc,arity v.vb_expr) :: !binds
      | _ -> ()); d.value_binding self v);
      expr = (fun self e ->
        (match e.exp_desc with
        | Texp_function _ -> functions := e.exp_loc :: !functions
        | Texp_ident (p,n,v) -> ids := (p,n,v,e) :: !ids
        | Texp_apply (head,args) ->
          List.iteri (fun i (_,arg) -> match arg with Some a ->
            (match a.exp_desc with Texp_ident _ -> callback_uses := (a,e.exp_loc,i) :: !callback_uses | _ -> ()) | None -> ()) args;
          (match head.exp_desc with
          | Texp_ident (p,n,v) -> apps := (p,n,v,e.exp_loc,head.exp_loc,
            List.length (List.filter (fun (_,v) -> Option.is_some v) args),List.length args) :: !apps
          | _ -> ())
        | _ -> ()); d.expr self e)
    } in
    (match c.cmt_annots with Implementation s -> iter.structure iter s | _ -> ());
    let binding (u,n,l,e,a) = obj ["uid",uid u;"name",q n;"binding_loc",loc l;"body_loc",loc e;"arity",string_of_int a] in
    let by_uid = Shape.Uid.Tbl.create 128 and by_loc = Hashtbl.create 128 in
    List.iter (fun ((u,_,_,_,_) as b) -> Shape.Uid.Tbl.replace by_uid u
      (b :: Option.value ~default:[] (Shape.Uid.Tbl.find_opt by_uid u))) !binds;
    (* PPX-generated identifiers may share a source location. Retain the actual
       located longident as part of the key, not location alone. *)
    List.iter (fun ((k,_) as r) -> Hashtbl.replace by_loc k
      (r :: Option.value ~default:[] (Hashtbl.find_opt by_loc k))) c.cmt_ident_occurrences;
    let matches u = arr (List.map binding (Option.value ~default:[] (Shape.Uid.Tbl.find_opt by_uid u))) in
    let evidence n v =
      let resolutions = Option.value ~default:[] (Hashtbl.find_opt by_loc n) in
      ["val_uid",uid v.Types.val_uid;"val_uid_bindings",matches v.val_uid;
       "occurrences",arr (List.map (fun (_,r) -> obj ["result",resolution r;
         "resolved_bindings",(match r with Shape_reduce.Resolved u -> matches u | _ -> "[]")]) resolutions)] in
    let identifiers = List.map (fun (p,n,v,e) -> obj (["path",q (Path.name p);"loc",loc e.exp_loc;"name_loc",loc n.Location.loc;
      "callback_contexts",arr (List.filter_map (fun (a,l,i) -> if a == e then Some (obj ["application_loc",loc l;"argument_slot",string_of_int i]) else None) !callback_uses)] @ evidence n v)) !ids in
    let applications = List.map (fun (p,n,v,l,h,a,slots) -> obj (["path",q (Path.name p);"loc",loc l;"head_loc",loc h;
      "supplied",string_of_int a;"slots",string_of_int slots] @ evidence n v)) !apps in
    print_endline (obj ["cmt",q file;"source",(match c.cmt_sourcefile with None -> "null" | Some s -> q s);
      "builddir",q c.cmt_builddir;"source_digest",(match c.cmt_source_digest with None -> "null" | Some s -> q (Digest.to_hex s));
      "bindings",arr (List.map binding !binds);"identifiers",arr identifiers;"applications",arr applications;
      "functions",arr (List.map loc !functions);
      "uid_to_decl_count",string_of_int (Shape.Uid.Tbl.length c.cmt_uid_to_decl);
      "occurrence_count",string_of_int (List.length c.cmt_ident_occurrences)])
  done
