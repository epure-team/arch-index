(** OCaml Tier-1 effects extractor — CMT typedtree walk. *)

open Extractor_intf

let producer_id    = "arch-effects-ocaml-cmt"
let soundness_tier = Sound

(* ── mutation pattern tables ─────────────────────────────────────────────── *)

(** Hashtbl-mutating function names (stdlib, short-name matching). *)
let hashtbl_mutators =
  ["Hashtbl.add"; "Hashtbl.replace"; "Hashtbl.remove";
   "Hashtbl.clear"; "Hashtbl.reset"; "Hashtbl.filter_map_inplace"]

(** Array-element mutating names (a.(i) <- v desugars to Array.unsafe_set
    or stdlib prim; we also catch the explicit call form). *)
let array_mutators =
  ["Array.set"; "Array.unsafe_set"; "Bigarray.Array1.set";
   "Bigarray.Array2.set"; "Bigarray.Array3.set"]

(** Bytes/Buffer mutating names. *)
let bytes_mutators =
  ["Bytes.set"; "Bytes.blit"; "Bytes.fill"; "Bytes.unsafe_set";
   "Buffer.add_string"; "Buffer.add_bytes"; "Buffer.add_char";
   "Buffer.add_channel"; "Buffer.add_buffer"; "Buffer.add_utf_8_uchar";
   "Buffer.add_subbytes"; "Buffer.add_substring"; "Buffer.reset"; "Buffer.clear"]

(** I/O side-effect names (non-exhaustive; covers the common stdlib surface). *)
let io_names =
  ["print_string"; "print_int"; "print_float"; "print_char"; "print_endline";
   "print_newline"; "Printf.printf"; "Printf.eprintf"; "Printf.fprintf";
   "Printf.bprintf"; "output_string"; "output_bytes"; "output_char";
   "output_value"; "flush"; "Format.printf"; "Format.eprintf";
   "Format.fprintf"; "Format.kasprintf"; "Fmt.pr"; "Fmt.epr"]

(** Environment-variable mutators. *)
let env_names = ["Sys.putenv"; "Unix.putenv"]

(** File-system mutators (non-exhaustive). *)
let fs_names =
  ["open_out"; "open_out_bin"; "open_out_gen";
   "Unix.openfile"; "Unix.creat"; "Unix.unlink"; "Unix.rename";
   "Unix.chmod"; "Unix.chown"; "Unix.mkdir"; "Unix.rmdir"; "Unix.symlink";
   "Unix.truncate"; "Unix.ftruncate"]

(** Network mutators. *)
let net_names =
  ["Unix.connect"; "Unix.bind"; "Unix.listen"; "Unix.accept";
   "Unix.send"; "Unix.recv"; "Unix.sendto"; "Unix.recvfrom";
   "Unix.sendmsg"; "Unix.recvmsg"; "Unix.shutdown";
   "Unix.socket"; "Unix.socketpair"]

(* ── name classification ─────────────────────────────────────────────────── *)

let member_of lst name = List.mem name lst

(** Classify a callee fully-qualified name to an optional [value_kind].
    Returns [None] if the call is not a recognized mutation. *)
let classify_callee name =
  if member_of hashtbl_mutators  name then Some HashTbl
  else if member_of array_mutators    name then Some ArrayElem
  else if member_of bytes_mutators    name then Some BytesBuf
  else if member_of io_names          name then Some IoSideEffect
  else if member_of env_names         name then Some EnvVar
  else if member_of fs_names          name then Some FileSystem
  else if member_of net_names         name then Some Network
  else None

(* ── path helpers ────────────────────────────────────────────────────────── *)

let path_to_string p =
  let rec aux = function
    | Path.Pident id          -> Ident.name id
    | Path.Pdot (inner, lbl)  -> aux inner ^ "." ^ lbl
    | Path.Papply (f, _)      -> aux f
    | Path.Pextra_ty (p, _)   -> aux p
  in
  aux p

(* ── file scanning ───────────────────────────────────────────────────────── *)

let find_cmt_files build_dir =
  let files = ref [] in
  let rec walk dir =
    let entries = try Sys.readdir dir with Sys_error _ -> [||] in
    Array.iter (fun entry ->
      let path = Filename.concat dir entry in
      let is_dir = try Sys.is_directory path with Sys_error _ -> false in
      if is_dir then walk path
      else if Filename.check_suffix path ".cmt"
           && not (String.starts_with ~prefix:"dune__" (Filename.basename path))
      then files := path :: !files
    ) entries
  in
  walk build_dir;
  List.sort String.compare !files

(* ── per-file extractor ──────────────────────────────────────────────────── *)

(** Collect effect records from a single .cmt file. *)
let extract_from_cmt ~source_root cmt_path =
  let results : effect_record list ref = ref [] in
  let add fn_name fp kind target =
    results := {
      er_function_name = fn_name;
      er_file_path     = fp;
      er_value_kind    = kind;
      er_target        = target;
      er_soundness     = Sound;
      er_producer      = producer_id;
    } :: !results
  in
  (match Cmt_format.read cmt_path with
  | _, None -> ()
  | _, Some info -> (
    match info.cmt_annots with
    | Implementation structure ->
      let modname = info.cmt_modname in
      (* Resolve source path relative to source_root *)
      let src_path =
        match info.cmt_sourcefile with
        | Some f ->
          let abs = if Filename.is_relative f then
              Filename.concat (Filename.dirname cmt_path) f
            else f
          in
          let prefix = source_root ^ "/" in
          if String.length abs > String.length prefix
             && String.sub abs 0 (String.length prefix) = prefix
          then String.sub abs (String.length prefix)
                 (String.length abs - String.length prefix)
          else abs
        | None -> cmt_path
      in
      let fp = Some src_path in

      (* Walk value bindings, tracking current function name *)
      let open Tast_iterator in

      (* Process a top-level value binding *)
      let process_vb (vb : Typedtree.value_binding) =
        let fn_name = match vb.vb_pat.pat_desc with
          | Tpat_var (id, _, _) -> modname ^ "." ^ Ident.name id
          | _ -> modname ^ ".<anon>"
        in
        (* Walk the expression for mutations *)
        let iter = {
          default_iterator with
          expr = (fun self expr ->
            (match expr.exp_desc with

            (* ref assign: e := v  ==>  Texp_apply((:=), [e; v]) *)
            | Texp_apply ({ exp_desc = Texp_ident (path, _, _); _ }, _args)
              when path_to_string path = ":=" ->
              add fn_name fp HeapRef None

            (* mutable record field set: r.f <- v
               Texp_setfield(expr, longident_loc, label_description, expr) *)
            | Texp_setfield (_, _, lbl, _) ->
              add fn_name fp FieldAccess (Some lbl.Types.lbl_name)

            (* function call — classify the callee (includes Array.set / Array.unsafe_set
               which is what a.(i) <- v desugars to) *)
            | Texp_apply ({ exp_desc = Texp_ident (path, _, _); _ }, _) ->
              let callee = path_to_string path in
              (match classify_callee callee with
               | Some kind -> add fn_name fp kind (Some callee)
               | None -> ())

            | _ -> ());
            default_iterator.expr self expr);
        } in
        iter.expr iter vb.vb_expr
      in

      (* Walk module-level structure items; detect global mutable refs *)
      let is_ref_init (expr : Typedtree.expression) =
        (* ref {…} at module level — ref / Hashtbl.create / Queue.create *)
        match expr.exp_desc with
        | Texp_apply ({ exp_desc = Texp_ident (path, _, _); _ }, _) ->
          let n = path_to_string path in
          n = "ref" || n = "Hashtbl.create" || n = "Hashtbl.create_with_key"
          || n = "Queue.create" || n = "Stack.create"
        | _ -> false
      in

      List.iter (fun (item : Typedtree.structure_item) ->
        match item.str_desc with
        | Tstr_value (_, vbs) ->
          List.iter (fun (vb : Typedtree.value_binding) ->
            (* Detect module-level mutable bindings *)
            (match vb.vb_pat.pat_desc with
             | Tpat_var (id, _, _) when is_ref_init vb.vb_expr ->
               let name = modname ^ "." ^ Ident.name id in
               add name fp GlobalVar (Some (Ident.name id))
             | _ -> ());
            process_vb vb
          ) vbs
        | _ -> ()
      ) structure.str_items
    | _ -> ()));
  List.rev !results

(* ── public entry point ──────────────────────────────────────────────────── *)

let extract_effects ~source_root ~build_dir =
  let dir = match build_dir with
    | Some d -> d
    | None   -> Filename.concat source_root "_build/default"
  in
  let cmts = find_cmt_files dir in
  List.concat_map (fun cmt_path ->
    try extract_from_cmt ~source_root cmt_path
    with exn ->
      Printf.eprintf
        "arch-effects-ocaml: warning: skipping %s: %s\n%!" cmt_path
        (Printexc.to_string exn);
      []
  ) cmts
