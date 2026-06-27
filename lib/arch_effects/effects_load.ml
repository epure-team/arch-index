(** NDJSON effects record reader + DB writer. *)

open Extractor_intf

type load_result = {
  n_effects : int;
  n_skipped : int;
}

(* ── NDJSON parsing ──────────────────────────────────────────────────────── *)

let parse_effect_line line_num line =
  let j =
    match Yojson.Safe.from_string line with
    | exception Yojson.Json_error msg ->
      failwith (Printf.sprintf "invalid JSON (line %d): %s" line_num msg)
    | v -> v
  in
  let obj = match j with
    | `Assoc o -> o
    | _ -> failwith (Printf.sprintf "expected JSON object (line %d)" line_num)
  in
  let get_str k = match List.assoc_opt k obj with
    | Some (`String s) -> Some s | _ -> None in
  (* Accept records with "type":"effect" OR any record that has "value_kind" *)
  let typ = get_str "type" in
  let has_vk = List.mem_assoc "value_kind" obj in
  if typ <> Some "effect" && not has_vk then None
  else
    let fn_name = match get_str "function_name" with
      | Some n -> n
      | None -> failwith (Printf.sprintf "effect record missing function_name (line %d)" line_num)
    in
    let value_kind = match get_str "value_kind" with
      | Some vk -> (match value_kind_of_string vk with
        | Some k -> k
        | None   -> UnknownMut)
      | None -> failwith (Printf.sprintf "effect record missing value_kind (line %d)" line_num)
    in
    let soundness = match get_str "soundness" with
      | Some "sound"     -> Sound
      | Some "manual"    -> Manual
      | _                -> Candidate
    in
    Some {
      er_function_name = fn_name;
      er_file_path     = get_str "file_path";
      er_value_kind    = value_kind;
      er_target        = get_str "target";
      er_soundness     = soundness;
      er_producer      = (match get_str "producer" with Some p -> p | None -> "unknown");
    }

(* ── main entry ─────────────────────────────────────────────────────────── *)

let load ~db_path ic =
  let records = ref [] in
  let n_skipped = ref 0 in
  let line_num = ref 0 in
  (try
    while true do
      let raw = input_line ic in
      incr line_num;
      let line = String.trim raw in
      if line <> "" then
        match parse_effect_line !line_num line with
        | exception Failure _ -> incr n_skipped
        | None -> ()
        | Some r -> records := r :: !records
    done
  with End_of_file -> ());
  let recs = List.rev !records in
  match Effects_db.write_effects ~db_path recs with
  | Ok (n_inserted, n_db_skipped) ->
    Ok { n_effects = n_inserted; n_skipped = !n_skipped + n_db_skipped }
  | Error msg -> Error msg
