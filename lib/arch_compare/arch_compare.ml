(* arch_compare — metrics regression gate engine.
   Ported from octez-manager tools/arch_compare.ml (same author) with spec deltas
   (specs/arch-metrics-gate.md): arch-index metric direction table, strict flat-JSON
   parsing (FR-009), duplicate accept entries invalid (FR-014), 1e-9 unchanged
   tolerance (FR-011). *)

module Metric_map = struct
  include Map.Make (String)

  let of_list entries =
    List.fold_left (fun acc (key, value) -> add key value acc) empty entries
end

type metric_change = {metric : string; baseline : float; current : float}

type comparison_result = {
  regressions : metric_change list;
  improvements : metric_change list;
  unchanged : (string * float) list;
  missing : (string * float) list;
}

type acceptance_entry = {metric : string; bound : float; reason : string; line : int}

type acceptance_error = {metric : string; line : int; message : string}

type acceptance_file = {
  accepted : acceptance_entry list;
  invalid_entries : acceptance_error list;
}

type gate_result = {
  comparison : comparison_result;
  blocking_regressions : metric_change list;
  accepted_regressions : (metric_change * acceptance_entry) list;
  invalid_acceptances : acceptance_error list;
}

(* Direction table (spec Clarifications). Informational metrics
   (modules, total_functions, exported_functions, call_edges) are untracked:
   they never regress, block, or accept. *)
let worse_when_higher =
  ["large_files"; "large_functions"; "may_top_edges"; "undocumented_exposed"]

let worse_when_lower = ["doc_coverage_pct"]

let is_worse_when_higher key = List.mem key worse_when_higher

let is_worse_when_lower key = List.mem key worse_when_lower

let is_tracked_metric key = is_worse_when_higher key || is_worse_when_lower key

let acceptance_operator metric = if is_worse_when_lower metric then ">=" else "<="

(* FR-011: values closer than this are "unchanged". *)
let unchanged_tolerance = 1e-9

let float_of_json_number = function
  | `Float value -> Some value
  | `Int value -> Some (float_of_int value)
  | `Intlit value -> float_of_string_opt value
  | _ -> None

(* FR-009: inputs must be flat {string: number} JSON — anything else is an error,
   never silently coerced to an empty metric set. *)
let parse_metrics_json_string s =
  match Yojson.Safe.from_string s with
  | exception Yojson.Json_error msg -> Error (Printf.sprintf "invalid JSON: %s" msg)
  | `Assoc fields ->
      List.fold_left
        (fun acc (key, json) ->
          match acc with
          | Error _ as e -> e
          | Ok metrics -> (
              match float_of_json_number json with
              | Some value -> Ok (Metric_map.add key value metrics)
              | None ->
                  Error
                    (Printf.sprintf "field %S is not a number — expected a flat \
                                     {string: number} object" key)))
        (Ok Metric_map.empty) fields
  | _ -> Error "not a flat JSON object of metrics"

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let n = in_channel_length ic in
      really_input_string ic n)

let parse_metrics_json path =
  match read_file path with
  | exception Sys_error msg -> Error msg
  | contents -> (
      match parse_metrics_json_string contents with
      | Ok _ as ok -> ok
      | Error msg -> Error (Printf.sprintf "%s: %s" path msg))

(* ── .metrics-accept parsing ─────────────────────────────────────────────── *)

let string_starts_with ~prefix s =
  let prefix_len = String.length prefix in
  String.length s >= prefix_len && String.equal (String.sub s 0 prefix_len) prefix

let split_comment line =
  match String.index_opt line '#' with
  | None -> (line, None)
  | Some index ->
      let before = String.sub line 0 index in
      let after =
        String.sub line (index + 1) (String.length line - index - 1) |> String.trim
      in
      (before, if String.equal after "" then None else Some after)

let is_whitespace = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let first_token_and_rest line =
  let trimmed = String.trim line in
  let len = String.length trimmed in
  if Int.equal len 0 then None
  else
    let rec token_end index =
      if index >= len || is_whitespace trimmed.[index] then index
      else token_end (index + 1)
    in
    let rec rest_start index =
      if index >= len || not (is_whitespace trimmed.[index]) then index
      else rest_start (index + 1)
    in
    let token_end = token_end 0 in
    let rest_start = rest_start token_end in
    let first = String.sub trimmed 0 token_end in
    let rest =
      if rest_start >= len then None
      else Some (String.sub trimmed rest_start (len - rest_start))
    in
    Some (first, rest)

let parse_bound metric = function
  | None -> Error "missing reviewed bound"
  | Some rest -> (
      match first_token_and_rest rest with
      | None -> Error "missing reviewed bound"
      | Some (op, value_and_reason) -> (
          let expected_op = acceptance_operator metric in
          if not (String.equal op expected_op) then
            Error (Printf.sprintf "expected %s bound" expected_op)
          else
            match value_and_reason with
            | None -> Error "missing reviewed bound"
            | Some value_and_reason -> (
                match first_token_and_rest value_and_reason with
                | None -> Error "missing reviewed bound"
                | Some (value, reason) -> (
                    match float_of_string_opt value with
                    | Some bound -> Ok (bound, reason)
                    | None -> Error "invalid reviewed bound"))))

let parse_accept_file_string s =
  let lines = String.split_on_char '\n' s in
  let accepted = ref [] in
  let invalid_entries = ref [] in
  let pending_comments = ref [] in
  let seen_metrics = ref [] in
  let clear_comments () = pending_comments := [] in
  List.iteri
    (fun index raw_line ->
      let line_no = index + 1 in
      let trimmed = String.trim raw_line in
      if String.equal trimmed "" then clear_comments ()
      else if string_starts_with ~prefix:"#" trimmed then (
        let comment =
          String.sub trimmed 1 (String.length trimmed - 1) |> String.trim
        in
        if not (String.equal comment "") then
          pending_comments := !pending_comments @ [comment])
      else (
        (let before_comment, inline_reason = split_comment trimmed in
         match first_token_and_rest before_comment with
         | None -> ()
         | Some (metric, trailing_reason) ->
             let bound, bound_error, trailing_reason =
               match parse_bound metric trailing_reason with
               | Ok (bound, reason) -> (Some bound, None, reason)
               | Error message -> (None, Some message, trailing_reason)
             in
             let reason =
               match inline_reason with
               | Some reason -> Some reason
               | None -> (
                   match trailing_reason with
                   | Some reason -> Some reason
                   | None -> (
                       match !pending_comments with
                       | [] -> None
                       | comments -> Some (String.concat " " comments)))
             in
             let invalid message =
               invalid_entries :=
                 {metric; line = line_no; message} :: !invalid_entries
             in
             if not (is_tracked_metric metric) then
               invalid "not a tracked architecture metric"
             else if List.mem metric !seen_metrics then
               (* FR-014: one reviewed entry per metric — a silent last-wins would
                  hide review errors. *)
               invalid "duplicate entry for this metric"
             else (
               seen_metrics := metric :: !seen_metrics;
               match (bound, bound_error, reason) with
               | Some bound, None, Some reason ->
                   accepted := {metric; bound; reason; line = line_no} :: !accepted
               | None, Some message, _ -> invalid message
               | Some _, None, None -> invalid "missing reviewable reason"
               | _ -> invalid "invalid reviewed bound"));
        clear_comments ()))
    lines;
  {accepted = List.rev !accepted; invalid_entries = List.rev !invalid_entries}

(* FR-016: absent file = empty policy, not an error. *)
let load_accept_file path =
  if Sys.file_exists path then read_file path |> parse_accept_file_string
  else {accepted = []; invalid_entries = []}

(* ── comparison ──────────────────────────────────────────────────────────── *)

let compare_change (a : metric_change) (b : metric_change) =
  String.compare a.metric b.metric

let compare_metrics ~baseline ~current =
  let regressions = ref [] in
  let improvements = ref [] in
  let unchanged = ref [] in
  Metric_map.iter
    (fun key cur_val ->
      if is_tracked_metric key then
        match Metric_map.find_opt key baseline with
        | None -> ()
        | Some base_val ->
            if Float.abs (cur_val -. base_val) < unchanged_tolerance then
              unchanged := (key, cur_val) :: !unchanged
            else
              let change = {metric = key; baseline = base_val; current = cur_val} in
              if
                (is_worse_when_higher key && cur_val > base_val)
                || (is_worse_when_lower key && cur_val < base_val)
              then regressions := change :: !regressions
              else improvements := change :: !improvements)
    current;
  let missing =
    Metric_map.fold
      (fun key base_val acc ->
        if is_tracked_metric key && not (Metric_map.mem key current) then
          (key, base_val) :: acc
        else acc)
      baseline []
  in
  {
    regressions = List.sort compare_change !regressions;
    improvements = List.sort compare_change !improvements;
    unchanged =
      List.sort (fun (left, _) (right, _) -> String.compare left right) !unchanged;
    missing =
      List.sort (fun (left, _) (right, _) -> String.compare left right) missing;
  }

let find_acceptance metric (accepted : acceptance_entry list) =
  List.find_opt
    (fun (entry : acceptance_entry) -> String.equal entry.metric metric)
    accepted

(* EC-4: bound is inclusive. *)
let acceptance_covers (change : metric_change) (entry : acceptance_entry) =
  if is_worse_when_lower change.metric then change.current >= entry.bound
  else change.current <= entry.bound

let evaluate ~acceptance ~baseline ~current =
  let comparison = compare_metrics ~baseline ~current in
  let blocking_regressions = ref [] in
  let accepted_regressions = ref [] in
  List.iter
    (fun (change : metric_change) ->
      match find_acceptance change.metric acceptance.accepted with
      | Some entry when acceptance_covers change entry ->
          accepted_regressions := (change, entry) :: !accepted_regressions
      | Some _ | None -> blocking_regressions := change :: !blocking_regressions)
    comparison.regressions;
  {
    comparison;
    blocking_regressions = List.rev !blocking_regressions;
    accepted_regressions = List.rev !accepted_regressions;
    invalid_acceptances = acceptance.invalid_entries;
  }

(* ── report rendering ────────────────────────────────────────────────────── *)

let format_float value =
  let rounded = Float.round value in
  if Float.abs (value -. rounded) < 0.0001 then Printf.sprintf "%.0f" value
  else Printf.sprintf "%.1f" value

let format_delta value =
  let rendered = format_float value in
  if value > 0.0 then "+" ^ rendered else rendered

let tracked_baseline_values comparison =
  let changed =
    List.map
      (fun (change : metric_change) -> (change.metric, change.baseline))
      (comparison.regressions @ comparison.improvements)
  in
  List.sort
    (fun (left, _) (right, _) -> String.compare left right)
    (changed @ comparison.missing @ comparison.unchanged)

let render_report ~baseline_path ~current_path result =
  let buffer = Buffer.create 512 in
  let add = Buffer.add_string buffer in
  add (Printf.sprintf "Baseline: %s\n" baseline_path);
  add (Printf.sprintf "Current: %s\n\n" current_path);
  add "Tracked baseline metrics:\n";
  List.iter
    (fun (metric, value) ->
      add (Printf.sprintf "  %s: %s\n" metric (format_float value)))
    (tracked_baseline_values result.comparison);
  add "\n";
  let change_line (change : metric_change) =
    Printf.sprintf "  %s: %s -> %s (%s)\n" change.metric
      (format_float change.baseline)
      (format_float change.current)
      (format_delta (change.current -. change.baseline))
  in
  if result.blocking_regressions <> [] then (
    add "REGRESSIONS (CI will fail):\n";
    List.iter (fun change -> add (change_line change)) result.blocking_regressions;
    add "\n");
  if result.comparison.missing <> [] then (
    add "Missing tracked metrics (CI will fail):\n";
    List.iter
      (fun (metric, value) ->
        add (Printf.sprintf "  %s: %s -> missing\n" metric (format_float value)))
      result.comparison.missing;
    add "\n");
  if result.comparison.improvements <> [] then (
    add "Improvements:\n";
    List.iter (fun change -> add (change_line change)) result.comparison.improvements;
    add "\n");
  if result.accepted_regressions <> [] then (
    add "Accepted regressions (via .metrics-accept):\n";
    List.iter
      (fun (change, (entry : acceptance_entry)) ->
        add (change_line change);
        add
          (Printf.sprintf "    Bound: %s %s\n"
             (acceptance_operator entry.metric)
             (format_float entry.bound));
        add (Printf.sprintf "    Reason: %s\n" entry.reason))
      result.accepted_regressions;
    add "\n");
  if result.invalid_acceptances <> [] then (
    add "Invalid .metrics-accept entries:\n";
    List.iter
      (fun (error : acceptance_error) ->
        add
          (Printf.sprintf "  %s (line %d): %s\n" error.metric error.line
             error.message))
      result.invalid_acceptances;
    add "\n");
  if result.blocking_regressions <> [] then
    add
      (Printf.sprintf "FAILED: %d metric(s) regressed.\n"
         (List.length result.blocking_regressions))
  else if result.comparison.missing <> [] then
    add
      (Printf.sprintf "FAILED: %d tracked metric(s) missing.\n"
         (List.length result.comparison.missing))
  else if result.invalid_acceptances <> [] then
    add
      (Printf.sprintf "FAILED: %d invalid .metrics-accept entr%s.\n"
         (List.length result.invalid_acceptances)
         (if Int.equal (List.length result.invalid_acceptances) 1 then "y"
          else "ies"))
  else
    add
      (Printf.sprintf
         "OK: No blocking regressions (%d improvements, %d unchanged, %d accepted).\n"
         (List.length result.comparison.improvements)
         (List.length result.comparison.unchanged)
         (List.length result.accepted_regressions));
  Buffer.contents buffer

let has_failures result =
  result.blocking_regressions <> []
  || result.comparison.missing <> []
  || result.invalid_acceptances <> []
