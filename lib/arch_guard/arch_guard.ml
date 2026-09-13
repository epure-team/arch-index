open Typedtree

module Guard_domain = Guard_domain

exception Error of string
let fail fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

type input = {path : string; sha256 : string; module_name : string; source : string option; bytes : int}
type raw_site = {id : int; primitive : string; kind : string; operand_category : string; operand_representation : string option; loc : Location.t; expression : Typedtree.expression; status : string; reasons : string list}

let primitive_kind = function
  | "%divint" | "%modint" as p -> Some (p, "int")
  | "%int32_div" | "%int32_mod" as p -> Some (p, "int32")
  | "%int64_div" | "%int64_mod" as p -> Some (p, "int64")
  | "%nativeint_div" | "%nativeint_mod" as p -> Some (p, "nativeint")
  | _ -> None

let primitive_of_expression expression =
  match expression.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) -> primitive_kind prim_name
  | _ -> None

let operand_metadata = function
  | None -> ("missing", None)
  | Some {exp_desc = Texp_constant (Const_int n); _} -> ("integer_literal", Some (string_of_int n))
  | Some {exp_desc = Texp_constant (Const_int32 n); _} -> ("integer_literal", Some (Int32.to_string n))
  | Some {exp_desc = Texp_constant (Const_int64 n); _} -> ("integer_literal", Some (Int64.to_string n))
  | Some {exp_desc = Texp_constant (Const_nativeint n); _} -> ("integer_literal", Some (Nativeint.to_string n))
  | Some {exp_desc = Texp_ident (_, lid, _); _} ->
      let spelling = Format.asprintf "%a" Pprintast.longident lid.txt in
      if String.length spelling <= 256 then ("identifier", Some spelling) else ("identifier", None)
  | Some _ -> ("other", None)

let inventory ~nodes ~site_count structure =
  let sites = ref [] in
  let ordinal = ref 0 in
  let depth = ref 0 in
  let base = Tast_iterator.default_iterator in
  let expr self expression =
    incr nodes ;
    incr depth ;
    if !nodes > 100_000 then fail "expression node count exceeds 100000" ;
    if !depth > 512 then fail "expression recursion depth exceeds 512" ;
    (match expression.exp_desc with
    | Texp_apply (head, args) -> (
        match primitive_of_expression head with
        | None -> ()
        | Some (primitive, kind) ->
            incr ordinal ;
            incr site_count ;
            if !site_count > 10_000 then fail "site count exceeds 10000" ;
            let operand = match List.nth_opt args 1 with Some (_, value) -> value | None -> None in
            let operand_category, operand_representation = operand_metadata operand in
            sites := {id = !ordinal; primitive; kind; operand_category; operand_representation; loc = expression.exp_loc; expression; status = ""; reasons = []} :: !sites)
    | _ -> ()) ;
    base.expr self expression ;
    decr depth
  in
  let iterator = {base with expr} in
  iterator.structure iterator structure ;
  List.rev !sites

let digest path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) @@ fun () ->
  Digestif.SHA256.(to_hex (digest_string (really_input_string channel (in_channel_length channel))))

let canonicalize paths =
  if paths = [] then fail "at least one --cmt FILE is required" ;
  let paths =
    List.map (fun path ->
        let stat = try Unix.lstat path with Unix.Unix_error (e, _, _) -> fail "%s: %s" path (Unix.error_message e) in
        if stat.st_kind = Unix.S_LNK then fail "%s: symlink inputs are not accepted" path ;
        if stat.st_kind <> Unix.S_REG then fail "%s: input is not a regular file" path ;
        if stat.st_size > 32 * 1024 * 1024 then fail "%s: input exceeds 32 MiB" path ;
        Unix.realpath path)
      paths |> List.sort_uniq String.compare
  in
  if List.length paths > 128 then fail "input count exceeds 128" ;
  let limit = 268_435_456L in
  ignore (List.fold_left (fun total p ->
      let size = Int64.of_int (Unix.stat p).st_size in
      if Int64.compare size (Int64.sub limit total) > 0 then fail "aggregate input size exceeds 256 MiB" ;
      Int64.add total size) 0L paths) ;
  paths

let read_artifact path =
  let before, (bytes, info) =
    try
      Guard_input.read_checked ~digest
        ~read:(fun path ->
          let bytes = (Unix.stat path).st_size in
          let info =
            match Cmt_format.read path with
            | _, Some info -> info
            | _ -> fail "%s: not a CMT artifact" path
          in
          (bytes, info)) path
    with
    | Guard_input.Changed -> fail "%s: input changed while being read" path
    | Error _ as e -> raise e
    | Cmi_format.Error _ -> fail "%s: incompatible compiler artifact" path
    | exn -> fail "%s: malformed/read failure: %s" path (Printexc.to_string exn)
  in
  let structure = match info.cmt_annots with
    | Implementation structure -> structure
    | Interface _ -> fail "%s: interface annotation is unsupported" path
    | Packed _ -> fail "%s: packed annotation is unsupported" path
    | Partial_implementation _ | Partial_interface _ -> fail "%s: partial annotation is unsupported" path
  in
  let source = Option.bind info.cmt_sourcefile (fun s -> if s = "" then None else Some s) in
  ({path; sha256 = before; module_name = info.cmt_modname; source; bytes}, structure)

let pos_json pos =
  if pos.Lexing.pos_lnum >= 1 && pos.pos_bol >= 0 && pos.pos_cnum >= pos.pos_bol then
    let delta = pos.pos_cnum - pos.pos_bol in
    let column = if delta = max_int then `Intlit (Int64.(to_string (add (of_int delta) 1L))) else `Int (delta + 1) in
    `Assoc [("line", `Int pos.pos_lnum); ("column", column); ("offset", `Int pos.pos_cnum)]
  else `Assoc [("line", `Null); ("column", `Null); ("offset", `Null)]

let location_json loc =
  let valid_end = loc.Location.loc_start.pos_fname = loc.loc_end.pos_fname && loc.loc_end.pos_cnum >= loc.loc_start.pos_cnum in
  `Assoc [("file", if loc.loc_start.pos_fname = "" then `Null else `String loc.loc_start.pos_fname);
          ("start", pos_json loc.loc_start); ("end", if valid_end then pos_json loc.loc_end else pos_json Lexing.dummy_pos);
          ("ghost", `Bool loc.loc_ghost)]

let valid_pos pos = pos.Lexing.pos_lnum >= 1 && pos.pos_bol >= 0 && pos.pos_cnum >= pos.pos_bol

let metadata_reasons site =
  let loc = site.loc in
  let invalid_location =
    loc.Location.loc_start.pos_fname = "" || not (valid_pos loc.loc_start)
    || loc.loc_start.pos_fname <> loc.loc_end.pos_fname
    || loc.loc_end.pos_cnum < loc.loc_start.pos_cnum || not (valid_pos loc.loc_end)
  in
  (if site.operand_category = "identifier" && Option.is_none site.operand_representation then ["operand_spelling_omitted"] else [])
  @ (if invalid_location then ["location_unavailable"] else [])
  @ (if loc.loc_ghost then ["ghost_location"] else [])

let input_json i = `Assoc [("path", `String i.path); ("sha256", `String i.sha256); ("module", `String i.module_name);
                            ("source", Option.fold ~none:`Null ~some:(fun s -> `String s) i.source); ("bytes", `Int i.bytes)]

let site_json artifact site =
  let reasons = List.sort_uniq String.compare (site.reasons @ metadata_reasons site) in
  `Assoc [("artifact", `String artifact.path); ("id", `Int site.id); ("primitive", `String site.primitive);
          ("integer_kind", `String site.kind);
          ("operand", `Assoc [("slot", `Int 2); ("category", `String site.operand_category);
                               ("representation", Option.fold ~none:`Null ~some:(fun s -> `String s) site.operand_representation)]);
          ("location", location_json site.loc); ("status", `String site.status);
          ("reasons", `List (List.map (fun reason -> `String reason) reasons))]

let analysis_json = `Assoc [("mode", `String "experimental-report-only"); ("fragment", `String "ocaml-int-acyclic-v1");
  ("domain", `String "constant-zero-v1");
  ("assumptions", `List [`String "trusted same-compiler and same-target CMT"; `String "artifact-only scope"; `String "no source freshness certificate"]);
  ("limitations", `List [`String "no whole-program completeness"; `String "no guaranteed execution or confirmed failure";
    `String "no machine-checked proof"; `String "unsupported fragment is explicit"; `String "no interprocedural or heap reasoning"])]

let run paths =
  let artifacts = canonicalize paths |> List.map read_artifact in
  let identities = Hashtbl.create 16 in
  List.iter (fun (i, _) -> let key = (i.module_name, i.source) in
    if Hashtbl.mem identities key then fail "duplicate module/source identity" else Hashtbl.add identities key ()) artifacts ;
  let inputs = List.map fst artifacts in
  let nodes = ref 0 and site_count = ref 0 in
  (* Complete inventory/preflight for every artifact precedes interpretation. *)
  let prepared = List.map (fun (i, structure) -> (i, structure, inventory ~nodes ~site_count structure)) artifacts in
  let sites = List.concat_map (fun (i, structure, raw) ->
      let semantic = Guard_interpreter.analyze structure in
      let reconcile site =
        match List.filter (fun (expression, _, _) -> expression == site.expression) semantic with
        | [(_, status, reasons)] -> {site with status; reasons}
        | [] -> fail "%s: interpreter omitted inventoried site %d" i.path site.id
        | _ -> fail "%s: interpreter duplicated inventoried site %d" i.path site.id
      in
      if List.length raw <> List.length semantic then fail "%s: inventory/interpreter site census mismatch" i.path ;
      List.map (fun site -> (i, reconcile site)) raw) prepared in
  let optional_offset pos = if valid_pos pos then Some pos.Lexing.pos_cnum else None in
  let emitted_end site =
    if site.loc.loc_start.pos_fname = site.loc.loc_end.pos_fname
       && site.loc.loc_end.pos_cnum >= site.loc.loc_start.pos_cnum
    then optional_offset site.loc.loc_end else None
  in
  let sites = List.sort (fun (ia, a) (ib, b) ->
      compare (ia.path, optional_offset a.loc.loc_start, emitted_end a, a.primitive, a.id)
        (ib.path, optional_offset b.loc.loc_start, emitted_end b, b.primitive, b.id)) sites in
  let count status = List.fold_left (fun n (_, s) -> if s.status = status then n + 1 else n) 0 sites in
  let nonzero, zero, may_zero, unreachable, unsupported = count "NONZERO", count "ZERO", count "MAY_ZERO", count "UNREACHABLE", count "UNSUPPORTED" in
  let numeric_covered = nonzero + zero + may_zero + unreachable in
  `Assoc [("schema_version", `Int 1);
    ("tool", `Assoc [("name", `String "arch-guard"); ("version", `String "0.1.0"); ("compiler_version", `String Sys.ocaml_version); ("int_bits", `Int Sys.int_size)]);
    ("analysis", analysis_json); ("outcome", `String (if sites = [] then "empty_inventory" else "classified"));
    ("inputs", `List (List.map input_json inputs)); ("sites", `List (List.map (fun (i,s) -> site_json i s) sites));
    ("census", `Assoc [("artifacts", `Int (List.length inputs)); ("total_sites", `Int (List.length sites));
      ("numeric_covered", `Int numeric_covered); ("nonzero", `Int nonzero); ("zero", `Int zero); ("may_zero", `Int may_zero);
      ("unreachable", `Int unreachable); ("unsupported", `Int unsupported); ("precision_gain_sites", `Int (nonzero + unreachable))])]

let enforce_output_bound rendered =
  if String.length rendered > 16 * 1024 * 1024 then fail "serialized report exceeds 16 MiB" ;
  rendered

let render_json paths =
  let json = Yojson.Safe.to_string (run paths) |> enforce_output_bound in
  json

let render_text paths =
  let result = run paths in
  let json = Yojson.Safe.to_string result |> enforce_output_bound in
  let open Yojson.Safe.Util in
  let inputs = result |> member "inputs" |> to_list in
  let sites = result |> member "sites" |> to_list in
  let census = result |> member "census" in
  let buffer = Buffer.create 1024 in
  Printf.bprintf buffer "arch-guard experimental report\ninputs: %d (supplied accepted artifacts only)\nint_bits: %d\n"
    (List.length inputs) Sys.int_size ;
  if sites = [] then Buffer.add_string buffer "No matching immediate primitive occurrences in supplied artifacts.\n" ;
  List.iter (fun site ->
      let location = site |> member "location" in
      let coordinate value = match value with `Null -> "?" | `Int n -> string_of_int n | `Intlit n -> n | _ -> fail "invalid rendered coordinate" in
      let source = match location |> member "file" with `String s -> s | _ -> "?" in
      Printf.bprintf buffer "%s %s artifact=%s id=%d location=%s:%s:%s reasons=%s\n"
        (site |> member "status" |> to_string) (site |> member "primitive" |> to_string)
        (site |> member "artifact" |> to_string) (site |> member "id" |> to_int)
        source (coordinate (location |> member "start" |> member "line"))
        (coordinate (location |> member "start" |> member "column"))
        (site |> member "reasons" |> to_list |> List.map to_string |> String.concat ",")) sites ;
  List.iter (fun name -> Printf.bprintf buffer "%s: %d\n" name (census |> member name |> to_int))
    ["artifacts"; "total_sites"; "numeric_covered"; "nonzero"; "zero"; "may_zero"; "unreachable"; "unsupported"; "precision_gain_sites"] ;
  Buffer.add_string buffer "Report-only conditional facts: no whole-program, guaranteed-execution, confirmed-failure, or machine-checked-proof claim.\n" ;
  ignore json ;
  Buffer.contents buffer |> enforce_output_bound
