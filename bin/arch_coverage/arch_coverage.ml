(** arch-coverage — reachability-weighted coverage.

    Line coverage answers "was this executed", which the whole MC/DC study argued is the wrong
    question. Three questions replace it: of the functions reachable from the exported API which
    are never exercised; which covered functions are only ⊤-reachable (the line ran, but what
    called it is unknown); and — with [--mutants] — which are covered {i and} have surviving
    mutants, i.e. executed by tests that would not notice them changing.

    {b "No instrumentation data" is not "0% covered".} A function with no DA record in its span —
    inlined, type-only, ppx-generated, or in a file the run never touched — is reported as no
    data. Calling it 0% fabricates a gap and sends someone to test code that cannot be
    instrumented. *)

open Arch_tools
module SS = Arch_graph.SS
module SM = Arch_graph.SM

let usage =
  {|arch-coverage — reachability-weighted coverage from an LCOV tracefile.

Usage: arch-coverage <db> <lcov-file> [--repo DIR] [--roots exported|<selector>]
                     [--mutants <arch-mutants-report.json>] [--format text|md|json]
                     [--max-list N] [--write]|}

let die msg = prerr_endline msg ; exit 2
let take n l = if n <= 0 then l else List.filteri (fun i _ -> i < n) l

(* ------------------------------------------------------------------ *)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function a :: v :: _ when a = name -> v | _ :: tl -> go tl | [] -> default in
    go args
  in
  let flags = [ "--repo"; "--roots"; "--mutants"; "--format"; "--max-list" ] in
  let positional =
    let rec go acc = function
      | a :: v :: tl when List.mem a flags -> ignore v ; go acc tl
      | a :: tl when String.length a > 1 && String.sub a 0 2 = "--" -> go acc tl
      | a :: tl -> go (a :: acc) tl
      | [] -> List.rev acc
    in
    go [] args
  in
  let db_path, lcov_path =
    match positional with d :: l :: _ -> (d, l) | _ -> (prerr_endline usage ; exit 2)
  in
  let repo = opt "--repo" "." and fmt = opt "--format" "text" in
  let maxlist = match int_of_string_opt (opt "--max-list" "20") with Some n -> n | None -> 20 in
  let t =
    try Arch_db.open_ro db_path
    with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-coverage: " ^ m)
  in
  let g = Arch_graph.load t in

  (* roots *)
  let roots_arg = opt "--roots" "exported" in
  let roots, roots_label =
    if roots_arg = "exported" then (
      let k =
        List.fold_left
          (fun acc (n : Arch_graph.node) -> if n.exported then SS.add n.key acc else acc)
          SS.empty (Arch_graph.nodes g)
      in
      (* Same refusal as the selector path below, which it was missing: an index whose producer
         never marked exports yields an empty cone, and every list in the report is then empty
         for want of a starting point, not for want of gaps. That reads as "fully covered". *)
      if SS.is_empty k then
        die
          "arch-coverage: --roots exported, but no function in this index is marked exported — the \
           API cone would be empty and every finding below would be vacuously none. Pass an \
           explicit --roots selector, or use a producer that records exports.";
      (k, "exported"))
    else
      match Arch_sel.parse ~allow:Arch_sel.[ File; Fn; Module ] roots_arg with
      | Error e -> die ("arch-coverage: " ^ e)
      | Ok s ->
          let k = Arch_sel.select g s in
          if SS.is_empty k then
            die
              (Printf.sprintf
                 "arch-coverage: --roots %s matched no function — refusing to report coverage \
                  against an empty API cone"
                 roots_arg) ;
          (k, Arch_sel.to_string s)
  in

  (* mutants cross-check *)
  let survivors =
    match opt "--mutants" "" with
    | "" -> None
    | p -> (
        match (try Yojson.Safe.from_file p with _ -> `Null) with
        | `Assoc a -> (
            match List.assoc_opt "survivors" a with
            | Some (`List l) ->
                let h = Hashtbl.create 32 in
                List.iter
                  (fun e ->
                    match e with
                    | `Assoc s -> (
                        match List.assoc_opt "function" s with
                        | Some (`String fn) ->
                            Hashtbl.replace h fn (1 + Option.value ~default:0 (Hashtbl.find_opt h fn))
                        | _ -> ())
                    | _ -> ())
                  l ;
                Some h
            | _ ->
                die
                  (Printf.sprintf
                     "arch-coverage: %s is not an `arch-mutants report --format json` document (no \
                      'survivors' key)"
                     p))
        | _ ->
            die
              (Printf.sprintf
                 "arch-coverage: %s is not an `arch-mutants report --format json` document (no \
                  'survivors' key)"
                 p))
  in

  let lcov = match Arch_lcov.parse lcov_path with Ok l -> l | Error e -> die ("arch-coverage: " ^ e) in

  let nodes = Arch_graph.nodes g in
  let resolver = Arch_path.make ~repo (List.filter_map (fun (n : Arch_graph.node) -> n.file) nodes) in
  (* LCOV path → DB path, summing where several tracefile records land on one indexed file. *)
  let by_db : (string, (int, int) Hashtbl.t) Hashtbl.t = Hashtbl.create 64 in
  let unmatched_files = ref [] in
  Arch_lcov.SM.iter
    (fun lpath lines ->
      let m = Arch_path.resolve resolver lpath in
      if Arch_path.SS.is_empty m then unmatched_files := lpath :: !unmatched_files
      else
        Arch_path.SS.iter
          (fun db ->
            let tgt =
              match Hashtbl.find_opt by_db db with
              | Some x -> x
              | None ->
                  let x = Hashtbl.create 64 in
                  Hashtbl.replace by_db db x ;
                  x
            in
            Hashtbl.iter
              (fun l h -> Hashtbl.replace tgt l (h + Option.value ~default:0 (Hashtbl.find_opt tgt l)))
              lines)
          m)
    lcov ;

  (* per-function coverage, over INSTRUMENTED lines only *)
  let per_fn = Hashtbl.create 128 in
  List.iter
    (fun (n : Arch_graph.node) ->
      match (n.file, n.line_start, n.line_end) with
      | Some path, Some a, Some b -> (
          match Hashtbl.find_opt by_db path with
          | None -> ()
          | Some lines ->
              let instrumented = ref 0 and covered = ref 0 in
              for i = a to b do
                match Hashtbl.find_opt lines i with
                | Some h ->
                    incr instrumented ;
                    if h > 0 then incr covered
                | None -> ()
              done ;
              (* Zero instrumented lines is NOT zero coverage — it is "the coverage tool had
                 nothing to say here". Recording it as 0% would fabricate a gap. *)
              if !instrumented > 0 then Hashtbl.replace per_fn n.key (n, path, !instrumented, !covered))
      | _ -> ())
    nodes ;

  let api_cone =
    SS.filter (fun k -> SM.mem k g.nodes) (SS.union roots (Arch_graph.closure roots g.fwd))
  in
  let name k = match SM.find_opt k g.nodes with Some (n : Arch_graph.node) -> n.name | None -> k in
  let sorted_names s = SS.elements s |> List.map name |> List.sort compare in
  let with_data = SS.filter (fun k -> Hashtbl.mem per_fn k) api_cone in
  let never =
    sorted_names
      (SS.filter (fun k -> match Hashtbl.find_opt per_fn k with Some (_, _, _, c) -> c = 0 | None -> false)
         with_data)
  in
  let no_data = sorted_names (SS.filter (fun k -> not (Hashtbl.mem per_fn k)) api_cone) in
  (* Covered, but reachable only through a ⊤ edge: the tool saw it run, the graph cannot say how. *)
  let top_holders = SM.fold (fun k _ acc -> SS.add k acc) g.tops SS.empty in
  let top_only = SS.diff (SS.union top_holders (Arch_graph.closure top_holders g.fwd)) api_cone in
  let via_top =
    sorted_names
      (SS.filter
         (fun k -> match Hashtbl.find_opt per_fn k with Some (_, _, _, c) -> c > 0 | None -> false)
         top_only)
  in
  (* Covered, outside the API cone, and not explained by a ⊤ edge either. Without this bucket a
     covered function could appear in NO list at all and simply vanish from the report — and the
     silent case is the interesting one: tests exercise code that nothing exported can reach. *)
  let outside =
    sorted_names
      (SS.filter
         (fun k ->
           (not (SS.mem k api_cone))
           && (not (SS.mem k top_only))
           && match Hashtbl.find_opt per_fn k with Some (_, _, _, c) -> c > 0 | None -> false)
         (SM.fold (fun k _ acc -> SS.add k acc) g.nodes SS.empty))
  in
  let files_in_index =
    List.sort_uniq compare (List.filter_map (fun (n : Arch_graph.node) -> n.file) nodes)
  in
  let not_instrumented = List.filter (fun f -> not (Hashtbl.mem by_db f)) files_in_index in

  (* Covered AND mutants survive. The join is by NAME, the only key a mutants report carries, so
     names shared by several indexed functions are EXCLUDED and reported rather than
     mis-attributed: an unexplained absence is recoverable, a wrong attribution sends someone to
     rewrite the wrong test. *)
  let unkilled, ambiguous =
    match survivors with
    | None -> ([], [])
    | Some h ->
        (* Counted over EVERY indexed function, not just the instrumented ones. Counting within
           per_fn asks "is this name ambiguous among functions that happen to have coverage
           data", but the mutants report is keyed by name against the whole index: if two
           functions share a name and only one is instrumented, the count is 1, the guard stays
           silent, and the survivor is attributed to the instrumented one — which may well be the
           other. Mis-attribution is the failure this guard exists to prevent. *)
        let seen = Hashtbl.create 64 in
        List.iter
          (fun (n : Arch_graph.node) ->
            Hashtbl.replace seen n.name (1 + Option.value ~default:0 (Hashtbl.find_opt seen n.name)))
          nodes ;
        let hits = ref [] and amb = ref [] in
        Hashtbl.iter
          (fun _ ((n : Arch_graph.node), path, _, c) ->
            if c > 0 then
              match Hashtbl.find_opt h n.name with
              | Some cnt ->
                  if Option.value ~default:1 (Hashtbl.find_opt seen n.name) > 1 then amb := n.name :: !amb
                  else hits := (n.name, path, cnt) :: !hits
              | None -> ())
          per_fn ;
        ( List.sort (fun (a, _, x) (b, _, y) -> if x = y then compare a b else compare y x) !hits,
          List.sort_uniq compare !amb )
  in
  (* Arch_db.contract_ok, not t.contract <> None && t.kinded: the weaker check is satisfied by a
     malformed index (flag set, but a real edge has NULL kind) that arch-impact/arch-rules
     correctly refuse — see Arch_db.require_contract's doc comment. Sharing the helper means this
     tool can never disagree with them about the same index (round-2 review, F6). *)
  let sound = Arch_db.contract_ok t "coverage" in

  (if fmt = "json" then
     print_endline
       (Yojson.Safe.pretty_to_string
          (`Assoc
            [ ("db", `String db_path); ("roots", `String roots_label);
              ("api_cone_size", `Int (SS.cardinal api_cone));
              ("api_with_coverage_data", `Int (SS.cardinal with_data));
              ("api_never_exercised", `List (List.map (fun s -> `String s) never));
              ("api_no_coverage_data", `List (List.map (fun s -> `String s) no_data));
              ("covered_via_top_only", `List (List.map (fun s -> `String s) via_top));
              ("covered_outside_api_cone", `List (List.map (fun s -> `String s) outside));
              ("covered_but_mutants_survive",
               `List
                 (List.map
                    (fun (fn, path, cnt) ->
                      `Assoc [ ("function", `String fn); ("file", `String path); ("survivors", `Int cnt) ])
                    unkilled));
              ("mutants_ambiguous_names", `List (List.map (fun s -> `String s) ambiguous));
              ("mutants_available", `Bool (survivors <> None));
              ("files_in_tracefile_not_in_index",
               `List (List.map (fun s -> `String s) (List.sort compare !unmatched_files)));
              ("files_in_index_not_instrumented",
               `List (List.map (fun s -> `String s) not_instrumented));
              ("sound_reachability", `Bool sound) ]))
   else
     let md = fmt = "md" in
     let b = if md then "- " else "  • " and h2 = if md then "## " else "-- " in
     print_endline (if md then "# Reachability-weighted coverage" else "== Reachability-weighted coverage") ;
     if not sound then
       print_endline
         (b
         ^ "**this index is not ⊤-marked** — the API cone below is whatever edges the producer \
            kept, so 'reachable from the API' is not a bound.") ;
     Printf.printf "%sroots: %s  →  %d function(s) in the API cone\n" b roots_label (SS.cardinal api_cone) ;
     Printf.printf "%s%d of them have coverage data\n" b (SS.cardinal with_data) ;
     print_endline "" ;
     print_endline (h2 ^ "Reachable from the API, never exercised") ;
     if never <> [] then (
       Printf.printf "%s%d function(s) — callable, and never run:\n" b (List.length never) ;
       List.iter (fun n -> Printf.printf "      %s\n" n) (take maxlist never))
     else print_endline (b ^ "none — every API-reachable function with coverage data was executed") ;
     if no_data <> [] then
       Printf.printf
         "%s%d API-reachable function(s) have NO coverage data. That is 'not instrumented', NOT \
          'not covered' — recording them as 0%% would fabricate a gap.\n"
         b (List.length no_data) ;
     print_endline "" ;
     print_endline (h2 ^ "Covered, but only ⊤-reachable") ;
     if via_top <> [] then (
       Printf.printf
         "%s%d function(s) the coverage tool saw run, which the graph can only reach through an \
          unresolvable edge. The line executed; what called it is unknown, so 'exercised by the \
          API' is not supported by this data:\n"
         b (List.length via_top) ;
       List.iter (fun n -> Printf.printf "      %s\n" n) (take maxlist via_top))
     else print_endline (b ^ "none") ;
     print_endline "" ;
     print_endline (h2 ^ "Covered, but outside the API cone") ;
     if outside <> [] then (
       Printf.printf
         "%s%d function(s) the tests execute that nothing in the API cone can reach — not even \
          through a ⊤ edge. Either the roots are wrong, or the tests are exercising code the \
          product cannot:\n"
         b (List.length outside) ;
       List.iter (fun n -> Printf.printf "      %s\n" n) (take maxlist outside))
     else print_endline (b ^ "none — every covered function is accounted for above") ;
     print_endline "" ;
     print_endline (h2 ^ "Covered, but the tests check nothing") ;
     (match survivors with
     | None ->
         print_endline
           (b
           ^ "not computed — pass --mutants <report> to cross-check coverage against surviving \
              mutants. This is the pairing that replaces a percentage.")
     | Some _ ->
         if unkilled <> [] then (
           Printf.printf
             "%s%d function(s) are covered AND have surviving mutants — executed by tests that \
              would not notice it changing:\n"
             b (List.length unkilled) ;
           List.iter (fun (fn, _, c) -> Printf.printf "      %s  (%d surviving mutant(s))\n" fn c)
             (take maxlist unkilled))
         else print_endline (b ^ "none — every covered function had its mutants killed")) ;
     if ambiguous <> [] then
       Printf.printf
         "%s%d name(s) are shared by several indexed functions, so a mutant cannot be attributed \
          to one of them and they are EXCLUDED above rather than mis-blamed: %s\n"
         b (List.length ambiguous) (String.concat ", " (take 10 ambiguous)) ;
     if !unmatched_files <> [] || not_instrumented <> [] then (
       print_endline "" ;
       print_endline (h2 ^ "Coverage/index mismatch") ;
       if !unmatched_files <> [] then
         Printf.printf
           "%s%d file(s) in the tracefile are not in the index — their coverage is not counted \
            anywhere above\n"
           b (List.length !unmatched_files) ;
       if not_instrumented <> [] then
         Printf.printf
           "%s%d indexed file(s) appear in no tracefile record — again 'not instrumented', not \
            '0%% covered'\n"
           b (List.length not_instrumented))) ;

  (* --write: populate the coverage table (main schema) or coverage_by_name (flat, which has no
     function ids — inventing them would produce rows that join to nothing). *)
  if List.mem "--write" args then (
    let n = Arch_cov_write.write ~db_path ~flat:(t.schema = Arch_db.Flat) per_fn in
    Printf.eprintf "arch-coverage: wrote %d coverage row(s) to %s\n" n db_path)
