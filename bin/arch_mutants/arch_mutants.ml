(** arch-mutants — mutation testing TARGETED by the call graph.

    arch-index deliberately contains no mutation engine: the category is mature and per-language
    (Mutaml, cargo-mutants, go-mutesting, mutmut, Stryker, PIT) and each drives its own AST and
    test runner. What is missing everywhere is TARGETING, which is why mutation testing has a
    reputation for being unusably slow.

    {b There is no mutation score.} A score is exactly as gameable as a coverage percentage.
    This reports surviving mutants together with the tests that should have killed them, and
    [--fail-on-survivors] is a defect list being non-empty, not a threshold to tune. *)

open Arch_tools
module SS = Arch_graph.SS
module SM = Arch_graph.SM

let usage =
  {|arch-mutants — mutation testing targeted by the call graph.

Usage: arch-mutants plan   <db> [--tests <selector>] [--format text|json|lines] [--max-list N]
       arch-mutants report <db> <mutant-report> [--from generic|mutaml] [--tests <selector>]
                                 [--repo DIR] [--format text|json]
                                 [--fail-on-survivors] [--fail-on-errored]

Generic mutant format (NDJSON, one object per line):
  {"file":"lib/x.ml","line":42,"status":"SURVIVED"|"KILLED"|"TIMEOUT"|"ERROR",
   "id":"7","mutation":"a && b -> a || b"}|}

let die msg = prerr_endline msg ; exit 2
let take n l = if n <= 0 then l else List.filteri (fun i _ -> i < n) l

let test_re name path =
  let low = String.lowercase_ascii in
  let p = low (Option.value ~default:"" path) in
  let at i pat = i + String.length pat <= String.length p && String.sub p i (String.length pat) = pat in
  let boundary i = i = 0 || p.[i - 1] = '/' in
  let rec scan i =
    i < String.length p
    && ((boundary i && at i "test")
       || (boundary i && at i "spec" && i + 4 < String.length p && (p.[i + 4] = '/' || p.[i + 4] = '_'))
       || at i "_test." || at i "_test_" || scan (i + 1))
  in
  (p <> "" && scan 0) || (String.length name >= 4 && String.sub (low name) 0 4 = "test")

(* ------------------------------------------------------------------ *)

let plan (t : Arch_db.t) (g : Arch_graph.t) test_keys heuristic fmt maxlist =
  let reachable = SS.union test_keys (Arch_graph.closure test_keys g.fwd) in
  (* Only a ⊤ edge held by something a TEST can reach matters. A ⊤ edge in code no test touches
     cannot make an untested function secretly tested; counting those reported thousands of
     functions as ambiguous on the strength of dispatch nothing was executing. *)
  (* SM.fold walks keys ascending and `::` reverses, so the list must be flipped back: the
     reported order is part of the output, and on the main schema keys are row ids. *)
  let escapes =
    List.rev (SM.fold (fun k _ acc -> if SS.mem k reachable then k :: acc else acc) g.tops [])
  in
  let meta = g.nodes in
  let all = SM.fold (fun k _ acc -> SS.add k acc) meta SS.empty in
  let unreached = SS.diff (SS.diff all reachable) test_keys in
  let skip_lines = Hashtbl.create 16 in
  if Arch_db.nonempty t "decisions" then
    List.iter
      (fun r ->
        match r with
        | [ Arch_db.Text p; Arch_db.Int l ] ->
            Hashtbl.replace skip_lines (p, l) ()
        | _ -> ())
      (Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.s_i
         ~to_cells:(fun (a, b) -> [ Arch_db.text_cell a; Arch_db.int_cell b ])
         "SELECT file_path, line FROM decisions WHERE verdict NOT IN ('OK','HIGH_ARITY')" ()) ;
  let targets = ref [] and no_location = ref [] in
  SS.iter
    (fun key ->
      if not (SS.mem key test_keys) then
        match SM.find_opt key meta with
        | None -> ()
        | Some (n : Arch_graph.node) -> (
            match n.file with
            | None ->
                (* Reachable, but the index has no file — typically a stdlib or dependency
                   function appearing only as a callee. Counted rather than skipped: every
                   indexed function must land in exactly one bucket, or the plan quietly loses
                   thousands of them and still looks complete. *)
                no_location := n.name :: !no_location
            | Some path ->
                let reaching =
                  SS.inter (Arch_graph.closure (SS.singleton key) g.bwd) test_keys
                  |> SS.elements
                  |> List.filter_map (fun k -> match SM.find_opt k meta with Some (m : Arch_graph.node) -> Some m.name | None -> None)
                  |> List.sort compare
                in
                let skipped =
                  match (n.line_start, n.line_end) with
                  | Some a, Some b ->
                      let acc = ref [] in
                      for i = a to b do
                        if Hashtbl.mem skip_lines (path, i) then acc := i :: !acc
                      done ;
                      List.sort compare !acc
                  | _ -> []
                in
                targets := (n, path, reaching, skipped) :: !targets))
    reachable ;
  let targets = List.sort (fun ((a : Arch_graph.node), _, _, _) (b, _, _, _) -> compare a.key b.key) !targets in
  let no_location = List.sort compare !no_location in
  let roots =
    SS.elements test_keys
    |> List.filter_map (fun k -> match SM.find_opt k meta with Some (n : Arch_graph.node) -> Some n.name | None -> None)
    |> List.sort compare
  in
  let unreached_names =
    SS.elements unreached
    |> List.filter_map (fun k -> match SM.find_opt k meta with Some (n : Arch_graph.node) -> Some n.name | None -> None)
    |> List.sort compare
  in
  let indexed = SM.cardinal meta in
  let unaccounted =
    indexed - (List.length targets + List.length no_location + List.length roots + SS.cardinal unreached)
  in
  (* Arch_db.contract_ok, not t.contract <> None && t.kinded — see arch_coverage.ml's identical
     comment; round-2 review, F6. *)
  let sound = Arch_db.contract_ok t "mutants" in
  let proof = escapes = [] && sound in
  let without_span =
    List.length (List.filter (fun ((n : Arch_graph.node), _, _, _) -> n.line_start = None) targets)
  in
  match fmt with
  | "lines" ->
      if without_span > 0 then
        Printf.eprintf "arch-mutants: %d target(s) omitted from the allowlist for lack of a line span\n"
          without_span ;
      List.iter
        (fun ((n : Arch_graph.node), path, _, _) ->
          match (n.line_start, n.line_end) with
          | Some a, Some b -> Printf.printf "%s:%d-%d\n" path a b
          | _ -> ())
        targets
  | "json" ->
      print_endline
        (Yojson.Safe.pretty_to_string
           (`Assoc
             [ ("db", `String t.path);
               ("test_roots", `List (List.map (fun s -> `String s) roots));
               ("test_roots_from_heuristic", `Bool heuristic);
               ("targets",
                `List
                  (List.map
                     (fun ((n : Arch_graph.node), path, reaching, skipped) ->
                       `Assoc
                         [ ("function", `String n.name); ("file", `String path);
                           ("line_start", match n.line_start with Some x -> `Int x | None -> `Null);
                           ("line_end", match n.line_end with Some x -> `Int x | None -> `Null);
                           ("reaching_tests", `List (List.map (fun s -> `String s) reaching));
                           ("already_vacuous_lines", `List (List.map (fun i -> `Int i) skipped)) ])
                     targets));
               ("targets_without_span", `Int without_span);
               ("no_source_location", `List (List.map (fun s -> `String s) no_location));
               ("unreached", `List (List.map (fun s -> `String s) unreached_names));
               ("test_cone_escapes",
                `List
                  (List.filter_map
                     (fun k -> match SM.find_opt k meta with Some (n : Arch_graph.node) -> Some (`String n.name) | None -> None)
                     escapes));
               ("unreached_is_proof", `Bool proof);
               ("indexed_functions", `Int indexed);
               ("sound_targeting", `Bool sound);
               ("decision_analysis_available", `Bool (Arch_db.nonempty t "decisions"));
               ("unaccounted", `Int unaccounted) ]))
  | _ ->
      print_endline "== Mutation plan" ;
      if roots = [] then
        print_endline
          "  • NO TEST ROOTS FOUND. Every target below would be unattributable, so the plan is \
           meaningless. Pass --tests file:<glob> pointing at your test sources, and check the \
           test binary was indexed at all."
      else if heuristic then
        Printf.printf
          "  • %d test root(s), found by NAME/PATH HEURISTIC. Every number below depends on this \
           set being right — pass --tests to make it a decision instead of a guess.\n"
          (List.length roots)
      else Printf.printf "  • %d test root(s), from --tests\n" (List.length roots) ;
      if not sound then
        print_endline
          "  • this index is not ⊤-marked, so 'unreached' below is NOT proof that no test reaches \
           the code — a dropped dynamic edge looks identical to an absent one. Treat it as a \
           candidate list." ;
      Printf.printf "  • %d function(s) worth mutating (test-reachable)\n" (List.length targets) ;
      let vac = List.fold_left (fun a (_, _, _, s) -> a + List.length s) 0 targets in
      if vac > 0 then
        Printf.printf
          "  • %d line(s) inside those targets already carry a dead-logic finding — no mutant \
           needed, the cheap tier settled them\n"
          vac ;
      if without_span > 0 then
        Printf.printf
          "  • %d target(s) have no line span, so they cannot be handed to an engine as a range. \
           Rebuild with a span-emitting producer.\n"
          without_span ;
      if proof then
        Printf.printf
          "  • %d function(s) NO test reaches — proved, in a closed cone. These need a DEAD-CODE \
           report, not a mutant: a surviving mutant there tells you nothing you did not already \
           know\n"
          (List.length unreached_names)
      else (
        Printf.printf "  • %d function(s) no test is KNOWN to reach — a candidate list, not a proof\n"
          (List.length unreached_names) ;
        if escapes <> [] then (
          Printf.printf
            "  • the test cone escapes through %d function(s) holding a ⊤ edge, so the suite may \
             in fact execute code listed as unreached above. Targeting is a heuristic here, not a \
             restriction you can trust:\n"
            (List.length escapes) ;
          List.iter
            (fun k ->
              match SM.find_opt k meta with
              | Some (n : Arch_graph.node) -> Printf.printf "      %s\n" n.name
              | None -> ())
            (take 5 escapes))) ;
      if no_location <> [] then
        Printf.printf
          "  • %d reachable function(s) have no file in the index (stdlib / dependency callees) — \
           nothing to mutate, listed only so the counts add up\n"
          (List.length no_location) ;
      Printf.printf "  • %d indexed function(s) accounted for%s\n" indexed
        (if unaccounted <> 0 then
           Printf.sprintf ", %d UNACCOUNTED — this is a bug in arch-mutants, please report it"
             unaccounted
         else "") ;
      print_endline "" ;
      print_endline "-- targets (function → tests that must rerun)" ;
      List.iter
        (fun ((n : Arch_graph.node), path, reaching, _) ->
          let span =
            match (n.line_start, n.line_end) with Some a, Some b -> Printf.sprintf ":%d-%d" a b | _ -> ""
          in
          let tests = if reaching = [] then "(none — unattributable)" else String.concat ", " (take 5 reaching) in
          let more = if List.length reaching > 5 then Printf.sprintf " +%d" (List.length reaching - 5) else "" in
          Printf.printf "  • %s  [%s%s]  ← %s%s\n" n.name path span tests more)
        (take maxlist targets) ;
      if maxlist > 0 && List.length targets > maxlist then
        Printf.printf "  … and %d more (--max-list 0 for all)\n" (List.length targets - maxlist)

(* ------------------------------------------------------------------ *)

type mutant = { file : string; line : int; status : string; id : string; mutation : string option }

let load_generic path =
  let ic = try open_in path with Sys_error e -> die ("arch-mutants: " ^ e) in
  let acc = ref [] and n = ref 0 in
  (try
     while true do
       let raw = String.trim (input_line ic) in
       incr n ;
       if raw <> "" then
         match Yojson.Safe.from_string raw with
         | `Assoc a ->
             let str k = match List.assoc_opt k a with Some (`String s) -> Some s | _ -> None in
             let file = str "file" and line = (match List.assoc_opt "line" a with Some (`Int i) -> Some i | _ -> None) in
             let status = str "status" in
             (match (file, line, status) with
             | Some f, Some l, Some s ->
                 acc := { file = f; line = l; status = s;
                          id = Option.value ~default:(string_of_int !n) (str "id");
                          mutation = str "mutation" } :: !acc
             | _ -> die (Printf.sprintf "arch-mutants: %s:%d: mutant record missing file/line/status" path !n))
         | _ -> die (Printf.sprintf "arch-mutants: %s:%d: record is not a JSON object" path !n)
     done
   with End_of_file -> () | Yojson.Json_error e -> die (Printf.sprintf "arch-mutants: %s:%d: invalid JSON: %s" path !n e)) ;
  close_in ic ;
  List.rev !acc

(** Adapt mutaml-report.json — a bare array of [test_result = {status; mutant}].

    [status] is the one field whose encoding is NOT stable across mutaml versions: the type
    declares [int] (an exit code) while the runner maps exit codes to strings first. Both are
    accepted; anything else ABORTS rather than being guessed, because guessing wrong inverts
    every verdict — a survived mutant read as killed is a defect silently deleted. *)
let load_mutaml path =
  let json = try Yojson.Safe.from_file path with _ -> die ("arch-mutants: cannot read mutaml report " ^ path) in
  match json with
  | `List entries ->
      List.mapi
        (fun i e ->
          match e with
          | `Assoc a -> (
              let status =
                match List.assoc_opt "status" a with
                | Some (`Int 0) -> "SURVIVED"
                | Some (`Int 124) -> "TIMEOUT"
                | Some (`Int _) -> "KILLED"
                | Some (`String s) -> (
                    match String.lowercase_ascii s with
                    | "passed" -> "SURVIVED"
                    | "timeout" -> "TIMEOUT"
                    | "failed" -> "KILLED"
                    | _ ->
                        die
                          (Printf.sprintf
                             "arch-mutants: %s: entry %d has unrecognised status %S; mutaml emits \
                              'passed' | 'failed' | 'timeout'. Refusing to guess — a mis-read \
                              status inverts the verdict."
                             path (i + 1) s))
                | _ ->
                    die
                      (Printf.sprintf "arch-mutants: %s: entry %d has no usable status" path (i + 1))
              in
              let m = match List.assoc_opt "mutant" a with Some (`Assoc m) -> m | _ -> [] in
              let loc = match List.assoc_opt "loc" m with Some (`Assoc l) -> l | _ -> [] in
              let start = match List.assoc_opt "loc_start" loc with Some (`Assoc s) -> s | _ -> [] in
              match
                (List.assoc_opt "pos_fname" start, List.assoc_opt "pos_lnum" start)
              with
              | Some (`String f), Some (`Int l) when f <> "" ->
                  { file = f; line = l; status;
                    id = (match List.assoc_opt "number" m with Some (`Int n) -> string_of_int n | _ -> string_of_int (i + 1));
                    mutation = (match List.assoc_opt "repl" m with Some (`String r) -> Some r | _ -> None) }
              | _ ->
                  die
                    (Printf.sprintf
                       "arch-mutants: %s: entry %d has no usable loc_start (pos_fname/pos_lnum)" path
                       (i + 1)))
          | _ ->
              die
                (Printf.sprintf
                   "arch-mutants: %s: entry %d is not a mutaml test_result (expected keys 'status' \
                    and 'mutant')"
                   path (i + 1)))
        entries
  | _ -> die (Printf.sprintf "arch-mutants: %s: expected a JSON array of mutaml test_result objects" path)

let report (g : Arch_graph.t) mutants test_keys repo fmt maxlist =
  let nodes = Arch_graph.nodes g in
  let resolver = Arch_path.make ~repo (List.filter_map (fun (n : Arch_graph.node) -> n.file) nodes) in
  let by_file = Hashtbl.create 64 in
  List.iter
    (fun (n : Arch_graph.node) ->
      match (n.file, n.line_start, n.line_end) with
      | Some f, Some _, Some _ -> Hashtbl.replace by_file f (n :: Option.value ~default:[] (Hashtbl.find_opt by_file f))
      | _ -> ())
    nodes ;
  (* Prepending reversed each bucket, and the innermost-span tie-break keeps the FIRST node of
     equal width — so a reversed bucket silently picks a different function for every tie. *)
  Hashtbl.iter (fun k v -> Hashtbl.replace by_file k (List.rev v)) (Hashtbl.copy by_file) ;
  let survivors = ref [] and killed = ref 0 and errored = ref 0 and unmapped = ref [] in
  List.iter
    (fun m ->
      let st = String.uppercase_ascii m.status in
      if st = "KILLED" || st = "TIMEOUT" then incr killed
      else if st <> "SURVIVED" then incr errored
      else
        let best = ref None in
        Arch_path.SS.iter
          (fun db ->
            List.iter
              (fun (n : Arch_graph.node) ->
                match (n.line_start, n.line_end) with
                | Some a, Some b when a <= m.line && m.line <= b -> (
                    (* innermost enclosing span wins — blaming an enclosing function makes the
                       developer hunt through it *)
                    match !best with
                    | Some ((p : Arch_graph.node), pa, pb) when pb - pa <= b - a -> ignore p
                    | _ -> best := Some (n, a, b))
                | _ -> ())
              (Option.value ~default:[] (Hashtbl.find_opt by_file db)))
          (Arch_path.resolve resolver m.file) ;
        match !best with
        | None -> unmapped := m :: !unmapped
        | Some ((n : Arch_graph.node), _, _) ->
            let reaching =
              SS.inter (Arch_graph.closure (SS.singleton n.key) g.bwd) test_keys
              |> SS.elements
              |> List.filter_map (fun k -> match SM.find_opt k g.nodes with Some (x : Arch_graph.node) -> Some x.name | None -> None)
              |> List.sort compare
            in
            survivors := (m, n.name, reaching) :: !survivors)
    mutants ;
  let survivors = List.rev !survivors and unmapped = List.rev !unmapped in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("survivors",
              `List
                (List.map
                   (fun (m, fn, reaching) ->
                     `Assoc
                       [ ("file", `String m.file); ("line", `Int m.line); ("id", `String m.id);
                         ("mutation", match m.mutation with Some x -> `String x | None -> `Null);
                         ("function", `String fn);
                         ("reaching_tests", `List (List.map (fun s -> `String s) reaching)) ])
                   survivors));
             ("killed", `Int !killed); ("errored", `Int !errored);
             (* The WHOLE record, not just its location: a survivor that could not be mapped is
                still a defect, and dropping its id and mutation makes it unactionable. *)
             ("unmapped",
              `List
                (List.map
                   (fun m ->
                     `Assoc
                       [ ("file", `String m.file); ("line", `Int m.line);
                         ("status", `String m.status); ("id", `String m.id);
                         ("mutation", match m.mutation with Some x -> `String x | None -> `Null) ])
                   unmapped));
             ("total", `Int (List.length mutants)) ]))
  else (
    print_endline "== Surviving mutants" ;
    Printf.printf "  • %d mutant(s) in the report: %d survived, %d killed%s\n" (List.length mutants)
      (List.length survivors) !killed
      (if !errored > 0 then Printf.sprintf ", %d errored (counted neither way)" !errored else "") ;
    if unmapped <> [] then (
      Printf.printf
        "  • %d survivor(s) could not be mapped to an indexed function — reported here rather \
         than dropped, because a dropped survivor is a defect that silently disappears:\n"
        (List.length unmapped) ;
      List.iter (fun m -> Printf.printf "      %s:%d\n" m.file m.line) (take maxlist unmapped)) ;
    print_endline "" ;
    if survivors = [] then
      print_endline
        "  no attributable survivor. That is a real result only if the plan actually targeted \
         this code — check `arch-mutants plan` before celebrating." ;
    List.iter
      (fun (m, fn, reaching) ->
        Printf.printf "  • SURVIVED %s:%d%s\n" m.file m.line
          (match m.mutation with Some x -> Printf.sprintf "  (%s)" x | None -> "") ;
        Printf.printf "      in %s\n" fn ;
        if reaching <> [] then
          Printf.printf "      %d test(s) reach it and none killed it: %s%s\n" (List.length reaching)
            (String.concat ", " (take 5 reaching))
            (if List.length reaching > 5 then Printf.sprintf " +%d" (List.length reaching - 5) else "")
        else print_endline "      NO test reaches it — this is not a weak test, it is untested code")
      (take maxlist survivors) ;
    if maxlist > 0 && List.length survivors > maxlist then
      Printf.printf "  … and %d more (--max-list 0 for all)\n" (List.length survivors - maxlist)) ;
  (survivors, unmapped, !errored)

(* ------------------------------------------------------------------ *)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function a :: v :: _ when a = name -> v | _ :: tl -> go tl | [] -> default in
    go args
  in
  let flags = [ "--tests"; "--format"; "--max-list"; "--from"; "--repo" ] in
  let positional =
    let rec go acc = function
      | a :: v :: tl when List.mem a flags -> ignore v ; go acc tl
      | a :: tl when String.length a > 1 && String.sub a 0 2 = "--" -> go acc tl
      | a :: tl -> go (a :: acc) tl
      | [] -> List.rev acc
    in
    go [] args
  in
  let cmd, db_path, extra =
    match positional with
    | c :: d :: rest -> (c, d, rest)
    | _ -> (prerr_endline usage ; exit 2)
  in
  let fmt = opt "--format" "text" in
  let maxlist = match int_of_string_opt (opt "--max-list" "20") with Some n -> n | None -> 20 in
  let t =
    try Arch_db.open_ro db_path
    with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-mutants: " ^ m)
  in
  let g = Arch_graph.load t in
  let tests_sel = opt "--tests" "" in
  let test_keys, heuristic =
    if tests_sel <> "" then
      match Arch_sel.parse ~allow:Arch_sel.structural tests_sel with
      | Error e -> die ("arch-mutants: " ^ e)
      | Ok s ->
          let k = Arch_sel.select g s in
          if SS.is_empty k then
            die
              (Printf.sprintf
                 "arch-mutants: --tests %s matched no function — refusing to plan against an empty \
                  test-root set, which would report every function as unreached"
                 tests_sel) ;
          (k, false)
    else
      ( List.fold_left
          (fun acc (n : Arch_graph.node) -> if test_re n.name n.file then SS.add n.key acc else acc)
          SS.empty (Arch_graph.nodes g),
        true )
  in
  match cmd with
  | "plan" -> plan t g test_keys heuristic fmt maxlist
  | "report" ->
      let mfile = match extra with m :: _ -> m | [] -> die "arch-mutants: report needs a mutant report path" in
      let mutants = if opt "--from" "generic" = "mutaml" then load_mutaml mfile else load_generic mfile in
      if fmt = "lines" then die "arch-mutants: --format lines is only meaningful for `plan`" ;
      let survivors, unmapped, errored =
        report g mutants test_keys (opt "--repo" ".") fmt maxlist
      in
      if List.mem "--fail-on-survivors" args && (survivors <> [] || unmapped <> []) then (
        Printf.eprintf "arch-mutants: FAIL — %d surviving mutant(s)\n"
          (List.length survivors + List.length unmapped) ;
        exit 1) ;
      (* An ERRORED mutant is one the engine could not build or run. It is neither killed nor
         survived, so it could never fail --fail-on-survivors — and a green gate on a report
         where most mutants errored says nothing about the tests. It stays out of the default
         gate because a mutation engine erroring on some mutants is routine, but it can no
         longer pass unremarked, and --fail-on-errored is there when the run is expected to be
         clean. *)
      if errored > 0 then
        Printf.eprintf
          "arch-mutants: NOTE — %d mutant(s) errored (neither killed nor survived). They cannot \
           fail this gate, so a pass here covers %d of %d mutants.\n"
          errored
          (List.length mutants - errored)
          (List.length mutants) ;
      if List.mem "--fail-on-errored" args && errored > 0 then (
        Printf.eprintf
          "arch-mutants: FAIL — --fail-on-errored was requested and %d mutant(s) errored\n" errored ;
        exit 1)
  | _ ->
      prerr_endline usage ;
      exit 2
