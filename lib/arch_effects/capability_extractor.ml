(** Capability extractor — Phase 2 implementation. *)

open Capability_types

(* ── path-based reachability class derivation ───────────────────────────── *)

(** Split a path into lowercase components separated by '/', '_', '-', '.'. *)
let path_components path =
  let lower = String.lowercase_ascii path in
  (* split on path separators and common word boundaries *)
  let buf = Buffer.create (String.length lower) in
  let flush acc =
    let s = Buffer.contents buf in
    Buffer.clear buf;
    if s = "" then acc else s :: acc
  in
  let rec go i acc =
    if i >= String.length lower then List.rev (flush acc)
    else
      let c = lower.[i] in
      if c = '/' || c = '_' || c = '-' || c = '.' then go (i+1) (flush acc)
      else (Buffer.add_char buf c; go (i+1) acc)
  in
  go 0 []

let component_matches components words =
  List.exists (fun w -> List.mem w components) words

let derive_reachability_class file_path =
  let comps = path_components file_path in
  if component_matches comps ["validate"; "validation"; "validator"] then
    Some Validate
  else if component_matches comps ["apply"; "application"] then
    Some Apply
  else if component_matches comps ["rpc"; "rpcs"] then
    Some Rpc
  else if component_matches comps ["internal"; "manager"] then
    (* manager_operation.ml → InternalOp; avoid false-pos on "manager_key" *)
    if component_matches comps ["operation"; "op"] then Some InternalOp
    else None
  else if component_matches comps ["init"; "genesis"; "initialization"] then
    Some Init
  else if component_matches comps ["mempool"; "p2p"; "node"; "shell"] then
    Some NodeLocal
  else if component_matches comps ["operation"; "op"; "ops"] then
    Some ExternalOp
  else
    None

(* ── call-site gating pattern detection ─────────────────────────────────── *)

(** Normalize a callee name to lowercase for pattern matching. *)
let norm s = String.lowercase_ascii s

let has_prefix prefix s = String.length s >= String.length prefix &&
  String.sub s 0 (String.length prefix) = prefix

let contains sub s =
  let ls = String.length s and lsub = String.length sub in
  if lsub > ls then false
  else
    let rec go i =
      if i > ls - lsub then false
      else if String.sub s i lsub = sub then true
      else go (i+1)
    in
    go 0

(** Extract the feature name from check_<feature>_enabled or similar.
    Returns "X" for "check_X_enabled", or the full callee name on failure. *)
let extract_flag_name callee =
  let lc = norm callee in
  (* check_<feature>_enabled *)
  if has_prefix "check_" lc && contains "_enabled" lc then begin
    let after_check = String.sub lc 6 (String.length lc - 6) in
    (* remove trailing _enabled *)
    let idx = try
      let len = String.length after_check in
      let sub = "_enabled" in
      let lsub = String.length sub in
      let rec go i =
        if i > len - lsub then -1
        else if String.sub after_check i lsub = sub then i
        else go (i+1)
      in go 0
    with _ -> -1 in
    if idx > 0 then String.sub after_check 0 idx
    else after_check
  end
  (* assert_feature_enabled *)
  else if has_prefix "assert_feature_" lc then
    String.sub lc 15 (String.length lc - 15)
  else
    callee

let derive_gating_from_calls callees =
  let lc_callees = List.map (fun c -> (c, norm c)) callees in
  (* Priority 1: gas/fee gates *)
  let gas_gate = List.exists (fun (_, lc) ->
    contains "gas.check" lc || contains "check_gas" lc ||
    contains "fees.check" lc || contains "assert_gas" lc ||
    contains "check_fees" lc
  ) lc_callees in
  if gas_gate then Some "cost(gas)"
  else
  (* Priority 2: signature auth *)
  let sig_gate = List.exists (fun (_, lc) ->
    contains "signature.check" lc || contains "bls.check" lc ||
    contains "check_signature" lc || contains "verify_signature" lc
  ) lc_callees in
  if sig_gate then Some "auth(signature)"
  else
  (* Priority 3: manager / source auth *)
  let mgr_gate = List.exists (fun (_, lc) ->
    contains "assert_manager" lc || contains "check_manager" lc ||
    contains "check_source" lc || contains "check_account_is_manager" lc
  ) lc_callees in
  if mgr_gate then Some "auth(manager_key)"
  else
  (* Priority 4: feature flag *)
  let flag_gate = List.find_opt (fun (orig, lc) ->
    ignore orig;
    contains "check_" lc && contains "_enabled" lc ||
    contains "assert_feature_" lc ||
    contains "_feature_enabled" lc
  ) lc_callees in
  match flag_gate with
  | Some (orig, _) ->
    let feature = extract_flag_name orig in
    Some (Printf.sprintf "flag(%s)" feature)
  | None -> None

(* ── record construction ─────────────────────────────────────────────────── *)

let make_static_record ~function_name ~file_path ~callees =
  let cap_reachability = match file_path with
    | Some fp -> derive_reachability_class fp
    | None    -> None
  in
  let cap_gating = derive_gating_from_calls callees in
  { cap_function_name  = function_name;
    cap_file_path      = file_path;
    cap_reachability   = cap_reachability;
    cap_actor_role     = None;
    cap_temporal_class = None;
    cap_gating         = cap_gating;
    cap_value_touched  = [];
    cap_precondition   = None;
    cap_source         = "static"; }

let merge_option base override =
  match override with Some _ -> override | None -> base

let merge_list base override =
  match override with [] -> base | _ -> override

let merge_records ~base ~override =
  { cap_function_name  = base.cap_function_name;
    cap_file_path      = merge_option base.cap_file_path override.cap_file_path;
    cap_reachability   = merge_option base.cap_reachability override.cap_reachability;
    cap_actor_role     = merge_option base.cap_actor_role override.cap_actor_role;
    cap_temporal_class = merge_option base.cap_temporal_class override.cap_temporal_class;
    cap_gating         = merge_option base.cap_gating override.cap_gating;
    cap_value_touched  = merge_list base.cap_value_touched override.cap_value_touched;
    cap_precondition   = merge_option base.cap_precondition override.cap_precondition;
    cap_source         = override.cap_source; }

(* ── sidecar YAML loader ─────────────────────────────────────────────────── *)

type sidecar_result = {
  sc_capabilities : capability_record list;
  sc_edges        : attack_edge list;
  sc_errors       : string list;
}

(** Very minimal YAML/JSON reader for the sidecar format.
    We support two styles: native YAML (line-by-line) and JSON (via Yojson).
    The sidecar files we generate are simple flat structures, so we parse them
    with a lightweight hand-rolled approach rather than pulling in a full YAML
    library (none is in scope here).

    Supported format:
      capabilities:
        - fn: "..."
          actor_role: ["a", "b"]   OR  actor_role: "a,b"
          temporal_class: [...]    OR  temporal_class: "..."
          precondition: "..."
          gating: "..."
      attack_edges:
        - from: "..."
          to: "..."
          edge_type: "..."
          evidence: "..."
*)

(** Strip surrounding quotes and whitespace from a YAML scalar value. *)
let strip_quotes s =
  let s = String.trim s in
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n-1] = '"' then String.sub s 1 (n-2)
  else if n >= 2 && s.[0] = '\'' && s.[n-1] = '\'' then String.sub s 1 (n-2)
  else s

(** Parse a YAML inline list ["a","b",...] or "a,b,..." into a string list. *)
let parse_list_or_scalar s =
  let s = String.trim s in
  if String.length s >= 2 && s.[0] = '[' then begin
    (* inline list: ["a", "b", ...] *)
    let inner = String.sub s 1 (String.length s - 2) in
    String.split_on_char ',' inner
    |> List.map strip_quotes
    |> List.filter (fun x -> x <> "")
  end else begin
    (* comma-separated scalar: "a,b,c" or a,b,c *)
    let v = strip_quotes s in
    String.split_on_char ',' v
    |> List.map String.trim
    |> List.filter (fun x -> x <> "")
  end

(** Parse the YAML sidecar file line by line using a simple state machine.
    This is intentionally minimal: it handles the known shape of the file only. *)
let load_sidecar path =
  if not (Sys.file_exists path) then
    { sc_capabilities = []; sc_edges = []; sc_errors = [Printf.sprintf "sidecar not found: %s" path] }
  else begin
    let ic = open_in path in
    let lines = ref [] in
    (try
      while true do
        lines := input_line ic :: !lines
      done
    with End_of_file -> ());
    close_in ic;
    let lines = List.rev !lines in

    let errors = ref [] in
    let caps   = ref [] in
    let edges  = ref [] in

    (* State: which top-level section we're in, and current item fields *)
    let section = ref `None in
    (* cap fields accumulator *)
    let c_fn   = ref None in
    let c_ar   = ref None in
    let c_tc   = ref None in
    let c_pre  = ref None in
    let c_gate = ref None in
    (* edge fields accumulator *)
    let e_from = ref None in
    let e_to   = ref None in
    let e_type = ref None in
    let e_ev   = ref None in

    let flush_cap () =
      match !c_fn with
      | None -> ()
      | Some fn ->
        let cap = {
          cap_function_name  = fn;
          cap_file_path      = None;
          cap_reachability   = None;
          cap_actor_role     = !c_ar;
          cap_temporal_class = !c_tc;
          cap_gating         = !c_gate;
          cap_value_touched  = [];
          cap_precondition   = !c_pre;
          cap_source         = "sidecar";
        } in
        caps := cap :: !caps;
        c_fn := None; c_ar := None; c_tc := None;
        c_pre := None; c_gate := None
    in

    let flush_edge () =
      match !e_from, !e_to, !e_type with
      | Some f, Some t, Some et ->
        (match edge_type_of_string et with
         | None ->
           errors := (Printf.sprintf "unknown edge_type '%s'" et) :: !errors
         | Some etype ->
           let edge = {
             ae_from     = f;
             ae_to       = t;
             ae_type     = etype;
             ae_evidence = !e_ev;
             ae_source   = "sidecar";
           } in
           edges := edge :: !edges);
        e_from := None; e_to := None; e_type := None; e_ev := None
      | _ ->
        if !e_from <> None || !e_to <> None || !e_type <> None then
          errors := "incomplete attack_edge entry (missing from/to/edge_type)" :: !errors;
        e_from := None; e_to := None; e_type := None; e_ev := None
    in

    let indent_of line =
      let n = String.length line in
      let rec go i = if i < n && line.[i] = ' ' then go (i+1) else i in
      go 0
    in

    List.iter (fun line ->
      let trimmed = String.trim line in
      if trimmed = "" || trimmed.[0] = '#' then ()
      else begin
        let ind = indent_of line in
        (* Detect section headers at indent 0 *)
        if ind = 0 then begin
          (match trimmed with
           | "capabilities:" ->
             flush_cap (); flush_edge ();
             section := `Caps
           | "attack_edges:" ->
             flush_cap (); flush_edge ();
             section := `Edges
           | _ -> ())
        end
        (* New item in list: "  - fn: ..." or "  - from: ..." *)
        else if ind = 2 && String.length trimmed > 2 && trimmed.[0] = '-' then begin
          (* flush previous item *)
          (match !section with
           | `Caps  -> flush_cap ()
           | `Edges -> flush_edge ()
           | `None  -> ());
          (* The "- key: value" on the same line *)
          let rest = String.trim (String.sub trimmed 1 (String.length trimmed - 1)) in
          let colon = try String.index rest ':' with Not_found -> -1 in
          if colon > 0 then begin
            let key = String.trim (String.sub rest 0 colon) in
            let value = String.trim (String.sub rest (colon+1) (String.length rest - colon - 1)) in
            (match !section with
             | `Caps ->
               (match key with
                | "fn"             -> c_fn   := Some (strip_quotes value)
                | "actor_role"     -> c_ar   := Some (String.concat "," (parse_list_or_scalar value))
                | "temporal_class" -> c_tc   := Some (String.concat "," (parse_list_or_scalar value))
                | "precondition"   -> c_pre  := Some (strip_quotes value)
                | "gating"         -> c_gate := Some (strip_quotes value)
                | _ -> ())
             | `Edges ->
               (match key with
                | "from"      -> e_from := Some (strip_quotes value)
                | "to"        -> e_to   := Some (strip_quotes value)
                | "edge_type" -> e_type := Some (strip_quotes value)
                | "evidence"  -> e_ev   := Some (strip_quotes value)
                | _ -> ())
             | `None -> ())
          end
        end
        (* Continuation field at indent 4 *)
        else if ind = 4 then begin
          let colon = try String.index trimmed ':' with Not_found -> -1 in
          if colon > 0 then begin
            let key = String.trim (String.sub trimmed 0 colon) in
            let value = String.trim (String.sub trimmed (colon+1) (String.length trimmed - colon - 1)) in
            (match !section with
             | `Caps ->
               (match key with
                | "fn"             -> c_fn   := Some (strip_quotes value)
                | "actor_role"     -> c_ar   := Some (String.concat "," (parse_list_or_scalar value))
                | "temporal_class" -> c_tc   := Some (String.concat "," (parse_list_or_scalar value))
                | "precondition"   -> c_pre  := Some (strip_quotes value)
                | "gating"         -> c_gate := Some (strip_quotes value)
                | _ -> ())
             | `Edges ->
               (match key with
                | "from"      -> e_from := Some (strip_quotes value)
                | "to"        -> e_to   := Some (strip_quotes value)
                | "edge_type" -> e_type := Some (strip_quotes value)
                | "evidence"  -> e_ev   := Some (strip_quotes value)
                | _ -> ())
             | `None -> ())
          end
        end
      end
    ) lines;
    flush_cap ();
    flush_edge ();
    { sc_capabilities = List.rev !caps;
      sc_edges        = List.rev !edges;
      sc_errors       = List.rev !errors; }
  end
