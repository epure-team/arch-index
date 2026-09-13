(* OCaml 5.3 compiler-libs measurement.  It reports Typedtree syntax and local
   binder identities; it does not resolve a module target or create graph data. *)
open Typedtree

type rhs = Structure | Alias | Application | Functor | Unpack | Other
type root = Persistent_unit | Functor_parameter | Bound of rhs | Unknown_nonpersistent

let rhs_name = function
  | Structure -> "structure" | Alias -> "alias" | Application -> "application"
  | Functor -> "functor" | Unpack -> "unpack" | Other -> "other"

let root_name = function
  | Persistent_unit -> "persistent_unit"
  | Functor_parameter -> "named_functor_parameter"
  | Bound r -> "bound_rhs_" ^ rhs_name r
  | Unknown_nonpersistent -> "unknown_nonpersistent"

let rec strip_constraints m =
  match m.mod_desc with Tmod_constraint (inner, _, _, _) -> strip_constraints inner | _ -> m

let rhs_of_expr m =
  match (strip_constraints m).mod_desc with
  | Tmod_structure _ -> Structure
  | Tmod_ident _ -> Alias
  | Tmod_apply _ | Tmod_apply_unit _ -> Application
  | Tmod_functor _ -> Functor
  | Tmod_unpack _ -> Unpack
  | Tmod_constraint _ -> assert false

(* The table is per decoded CMT.  The hash key makes lookup cheap; [Ident.same]
   is still the identity check, so same-spelled shadowed binders cannot match. *)
type bindings = (string, Ident.t * rhs) Hashtbl.t
type parameters = (string, Ident.t) Hashtbl.t

let remember_binding bindings id rhs =
  Hashtbl.replace bindings (Ident.unique_name id) (id, rhs)

let remember_parameter parameters id =
  Hashtbl.replace parameters (Ident.unique_name id) id

let find_binding table id =
  match Hashtbl.find_opt table (Ident.unique_name id) with
  | Some (stored, value) when Ident.same stored id -> Some value
  | _ -> None

let find_parameter table id =
  match Hashtbl.find_opt table (Ident.unique_name id) with
  | Some stored when Ident.same stored id -> Some ()
  | _ -> None

let path_root path =
  let rec loop = function
    | Path.Pident id -> id
    | Path.Pdot (p, _) | Path.Pextra_ty (p, _) -> loop p
    | Path.Papply (p, _) -> loop p
  in
  loop path

let root_of_path bindings parameters path =
  let id = path_root path in
  if Ident.persistent id then Persistent_unit
  else match find_parameter parameters id with
    | Some _ -> Functor_parameter
    | None -> match find_binding bindings id with
      | Some rhs -> Bound rhs
      | None -> Unknown_nonpersistent

let descriptor bindings parameters m =
  match (strip_constraints m).mod_desc with
  | Tmod_ident (path, _) -> "path:" ^ root_name (root_of_path bindings parameters path)
  | Tmod_apply _ | Tmod_apply_unit _ -> "application"
  | Tmod_structure _ -> "structure"
  | Tmod_functor _ -> "functor"
  | Tmod_unpack _ -> "unpack"
  | Tmod_constraint _ -> assert false

type counters = { heads : (string, int) Hashtbl.t; arguments : (string, int) Hashtbl.t;
                  mutable ordinary : int; mutable unit_ : int }

let add table key =
  Hashtbl.replace table key (1 + Option.value ~default:0 (Hashtbl.find_opt table key))

let fresh_counters () = { heads = Hashtbl.create 16; arguments = Hashtbl.create 16;
                          ordinary = 0; unit_ = 0 }

let merge into from =
  into.ordinary <- into.ordinary + from.ordinary;
  into.unit_ <- into.unit_ + from.unit_;
  Hashtbl.iter (fun k v -> Hashtbl.replace into.heads k (v + Option.value ~default:0 (Hashtbl.find_opt into.heads k))) from.heads;
  Hashtbl.iter (fun k v -> Hashtbl.replace into.arguments k (v + Option.value ~default:0 (Hashtbl.find_opt into.arguments k))) from.arguments

let census_structure structure =
  let bindings = Hashtbl.create 64 and parameters = Hashtbl.create 32 in
  let counters = fresh_counters () in
  let base = Tast_iterator.default_iterator in
  let module_binding self (mb : module_binding) =
    (match mb.mb_id with Some id -> remember_binding bindings id (rhs_of_expr mb.mb_expr) | None -> ());
    base.module_binding self mb
  in
  let module_expr self m =
    (match m.mod_desc with
    | Tmod_apply (head, argument, _) ->
        counters.ordinary <- counters.ordinary + 1;
        add counters.heads (descriptor bindings parameters head);
        add counters.arguments (descriptor bindings parameters argument)
    | Tmod_apply_unit head ->
        counters.unit_ <- counters.unit_ + 1;
        add counters.heads (descriptor bindings parameters head);
        add counters.arguments "unit"
    | Tmod_functor (Named (Some id, _, _), _) -> remember_parameter parameters id
    | _ -> ());
    base.module_expr self m
  in
  let expr self e =
    (match e.exp_desc with
    | Texp_letmodule (Some id, _, _, module_expr, _) ->
        remember_binding bindings id (rhs_of_expr module_expr)
    | _ -> ());
    base.expr self e
  in
  let iterator = { base with module_binding; module_expr; expr } in
  iterator.structure iterator structure; counters

let read_cmt path =
  match Cmt_format.read path with
  | _, Some { Cmt_format.cmt_annots = Cmt_format.Implementation structure; _ } -> Some structure
  | _ -> None

let sorted_counts table = Hashtbl.to_seq table |> List.of_seq |> List.sort compare

let print_counts label table =
  List.iter (fun (kind, n) -> Printf.printf "%s\t%s\t%d\n" label kind n) (sorted_counts table)

let print_slice slice c =
  Printf.printf "slice\t%s\tordinary\t%d\n" slice c.ordinary;
  Printf.printf "slice\t%s\tunit\t%d\n" slice c.unit_;
  print_counts ("head/" ^ slice) c.heads; print_counts ("argument/" ^ slice) c.arguments

let sha256 path =
  let ic = Unix.open_process_in ("sha256sum " ^ Filename.quote path) in
  match input_line ic |> String.split_on_char ' ' with
  | digest :: _ -> ignore (Unix.close_process_in ic); digest
  | _ -> ignore (Unix.close_process_in ic); failwith ("sha256sum malformed for " ^ path)

let parse_manifest path =
  let ic = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      let rows = ref [] in
      (try while true do
         let line = input_line ic in
         if line <> "" && line.[0] <> '#' then match String.split_on_char '\t' line with
           | [slice; digest; cmt] -> rows := (slice, digest, cmt) :: !rows
           | _ -> failwith ("invalid manifest row: " ^ line)
       done with End_of_file -> ()); List.rev !rows)

let run_manifest manifest =
  let rows = parse_manifest manifest in
  List.iter (fun (_, expected, cmt) ->
      let actual = sha256 cmt in
      if actual <> expected then failwith (Printf.sprintf "SHA256 mismatch: %s" cmt)) rows;
  let by_slice = Hashtbl.create 8 and total = fresh_counters () in
  List.iter (fun (slice, _, cmt) -> match read_cmt cmt with
      | None -> failwith ("not an Implementation CMT: " ^ cmt)
      | Some structure ->
          let c = census_structure structure in
          let prior = Option.value ~default:(fresh_counters ()) (Hashtbl.find_opt by_slice slice) in
          merge prior c; Hashtbl.replace by_slice slice prior; merge total c) rows;
  let slice_occurrences =
    Hashtbl.fold (fun _ c n -> n + c.ordinary + c.unit_) by_slice 0 in
  if total.ordinary + total.unit_ <> slice_occurrences then
    failwith "counter denominator mismatch";
  Printf.printf "manifest\t%s\n" manifest;
  Printf.printf "manifest_sha256\t%s\n" (sha256 manifest);
  Printf.printf "inputs\t%d\n" (List.length rows);
  Hashtbl.to_seq by_slice |> List.of_seq |> List.sort compare |> List.iter (fun (slice, c) -> print_slice slice c);
  print_slice "TOTAL" total

let () =
  match Array.to_list Sys.argv with
  | [_; "--manifest"; manifest] -> run_manifest manifest
  | [_; "--cmt"; cmt] ->
      (match read_cmt cmt with None -> failwith ("not an Implementation CMT: " ^ cmt)
       | Some structure -> print_slice "fixture" (census_structure structure))
  | _ -> prerr_endline "usage: binder_census --manifest MANIFEST | --cmt CMT"; exit 2
