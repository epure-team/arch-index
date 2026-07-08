(* arch-compare — CLI over Arch_compare (specs/arch-metrics-gate.md).
   Exit codes: 0 gate passes; 1 gate failure (blocking regression, missing
   tracked metric, or invalid .metrics-accept entry); 2 usage / malformed input. *)

let usage = "usage: arch-compare [--accept FILE] <baseline.json> <current.json>"

let die_usage msg =
  prerr_endline ("arch-compare: " ^ msg);
  prerr_endline usage;
  exit 2

let () =
  let accept_path = ref ".metrics-accept" in
  let positional = ref [] in
  let rec parse = function
    | [] -> ()
    | "--accept" :: path :: rest ->
        accept_path := path;
        parse rest
    | "--accept" :: [] -> die_usage "--accept requires a FILE argument"
    | arg :: _ when String.length arg > 1 && arg.[0] = '-' ->
        die_usage (Printf.sprintf "unknown option %s" arg)
    | arg :: rest ->
        positional := arg :: !positional;
        parse rest
  in
  parse (List.tl (Array.to_list Sys.argv));
  let baseline_path, current_path =
    match List.rev !positional with
    | [b; c] -> (b, c)
    | _ -> die_usage "expected exactly two arguments: <baseline.json> <current.json>"
  in
  let load path =
    match Arch_compare.parse_metrics_json path with
    | Ok metrics -> metrics
    | Error msg ->
        prerr_endline ("arch-compare: " ^ msg);
        exit 2
  in
  let baseline = load baseline_path in
  let current = load current_path in
  let acceptance = Arch_compare.load_accept_file !accept_path in
  let result = Arch_compare.evaluate ~acceptance ~baseline ~current in
  print_string (Arch_compare.render_report ~baseline_path ~current_path result);
  if Arch_compare.has_failures result then exit 1
