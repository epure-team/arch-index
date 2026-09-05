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
       arch-mutants run    <db> --plan <plan.json> --engine <cmd> --test-cmd <cmd>
                                 [--tests <selector>] [--profile <name>]
                                 [--catalogue <file>] [--report <file>]
                                 [--from generic|mutaml] [--seed S] [--engine-version V]
                                 [--repo DIR] [--format text|json] [--max-list N]

`run` invokes the ENGINE once. The engine loops over its own mutants and calls
scripts/mutaml-wrapper.sh once per mutant; the wrapper reads MUTAML_MUTANT, resolves it
through the plan, and runs only the tests that reach the mutated function. The per-mutant
executed set is always a SUPERSET of that reaching set, never a subset.

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

(** The ⊤ edges the TEST CONE can reach — the one measurement every soundness claim in this
    tool rests on.

    Extracted from [plan] so [run] uses the SAME binding rather than a second copy: the
    [proof = escapes = [] && sound] conjunction below and [run]'s [selection_provenance]
    must never be able to disagree about the same index, and two copies of one fold is
    exactly how they would come to.

    Only a ⊤ edge held by something a TEST can reach matters. A ⊤ edge in code no test
    touches cannot make an untested function secretly tested; counting those reported
    thousands of functions as ambiguous on the strength of dispatch nothing was executing. *)
let cone_escapes (g : Arch_graph.t) test_keys =
  let reachable = SS.union test_keys (Arch_graph.closure test_keys g.fwd) in
  (* SM.fold walks keys ascending and `::` reverses, so the list must be flipped back: the
     reported order is part of the output, and on the main schema keys are row ids. *)
  ( reachable,
    List.rev (SM.fold (fun k _ acc -> if SS.mem k reachable then k :: acc else acc) g.tops [])
  )

let plan (t : Arch_db.t) (g : Arch_graph.t) test_keys heuristic fmt maxlist =
  let reachable, escapes = cone_escapes g test_keys in
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
(* run — drive ONE campaign through an engine, and persist it          *)
(* ------------------------------------------------------------------ *)

(** {2 The execution model, stated once so it cannot be read two ways}

    {v
    driver  →  engine (invoked ONCE)  →  wrapper (invoked ONCE PER MUTANT)  →  tests
    v}

    The driver invokes the engine {b once}. The engine loops over its own mutants
    internally — that is how mutaml and cargo-mutants both work, and the driver cannot
    change it. What runs once per mutant is a {b wrapper} (scripts/mutaml-wrapper.sh) that
    the driver hands to the engine as the engine's test command. mutaml's runner builds,
    per mutant, [MUTAML_MUTANT=<mut_id> timeout <n> <test_cmd>]
    (src/runner/runner.ml:123-130 at github.com/jmid/mutaml 783831d), so the active
    mutant's identity reaches the wrapper through the environment.

    Anything asserting "the engine was invoked twice for two mutants" asserts the wrong
    thing. The per-mutant unit of observation is the {b wrapper}'s invocation, recorded in
    the trace file.

    The per-mutant executed set is always a {b superset} of the reaching set the plan
    declares, never a subset: under-selection can turn a mutant an excluded test would
    have killed into a survivor, which is a false accusation against a real test. *)

module MDb = Arch_mutant_db

(** The profile's addressing granularity. [case] is one test case; [group] is the coarser
    unit a runner can actually name (alcotest addresses tests by group regex plus a
    numeric index, not by exact case name — so its profile declares [group], and that
    declared coarseness IS the answer rather than a shim hiding it); [suite] is everything. *)
type granularity = Case | Group | Suite

let granularity_to_string = function Case -> "case" | Group -> "group" | Suite -> "suite"

(** The built-in profile registry {b for slice 1 only}.

    Slice 5 replaces this with a loader for [<name>-tests.toml] carrying its own
    discovery — deliberately NOT a generalisation of
    [Arch_index.discover_profile], which hardcodes both the [-errors.toml] suffix and its
    environment variable and has a live precedence test.

    An unknown name is refused rather than defaulted, for the same reason a profile
    missing [granularity] will be: defaulting silently decides the soundness question the
    field exists to answer. *)
let known_profiles =
  [ ("case", Case); ("group", Group); ("suite", Suite); ("alcotest", Group);
    ("cargo-mutants", Suite) ]

(** One mutant as the ENGINE's own catalogue describes it: a site plus the id the engine
    will export in [MUTAML_MUTANT]. The engine id is carried for traceability only — it is
    never part of a mutant's identity, exactly as an engine-assigned test id is not. *)
type site = {
  s_id : string;
  s_file : string;
  s_line : int;
  s_col_start : int;
  s_col_end : int;
  s_repl : string;
}

(** One target as [arch-mutants plan --format json] emitted it. [run] consumes the plan
    rather than recomputing the site→function mapping: the mapping is computed once,
    before execution, and reused for the verdict. *)
type target = { t_fn : string; t_file : string; t_a : int; t_b : int; t_tests : string list }

let json_string = function `String s -> Some s | _ -> None

let load_plan path =
  let json =
    try Yojson.Safe.from_file path
    with _ -> die (Printf.sprintf "arch-mutants: cannot read the plan %s" path)
  in
  let targets =
    match json with
    | `Assoc a -> (
        match List.assoc_opt "targets" a with
        | Some (`List l) -> l
        | _ ->
            die
              (Printf.sprintf
                 "arch-mutants: %s has no `targets` array — is it the output of \
                  `arch-mutants plan --format json`?"
                 path))
    | _ -> die (Printf.sprintf "arch-mutants: %s is not a plan object" path)
  in
  List.filter_map
    (function
      | `Assoc f -> (
          let str k = match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None in
          let num k = match List.assoc_opt k f with Some (`Int i) -> Some i | _ -> None in
          let tests =
            match List.assoc_opt "reaching_tests" f with
            | Some (`List l) -> List.filter_map json_string l
            | _ -> []
          in
          match (str "function", str "file", num "line_start", num "line_end") with
          | Some fn, Some file, Some a, Some b ->
              Some { t_fn = fn; t_file = file; t_a = a; t_b = b; t_tests = tests }
          (* A target with no span cannot be joined to a line, and `plan` already reports
             those separately. Dropping it here would be a silent loss, so it is counted
             by the caller through the catalogued-but-unmapped path instead. *)
          | _ -> None)
      | _ -> None)
    targets

(** mutaml's [.muts] catalogue: a JSON array of [{number; repl; loc}].

    The engine id is not stored in the file — it is DERIVED, exactly as mutaml derives it:
    [make_mut_id file_name number] is [Filename.remove_extension file_name ^ ":" ^ n]
    (src/common/mutaml_common.ml:30), and both the ppx (which passes the source file name)
    and the runner (which passes the [.muts] file name) reach the same string because the
    [.muts] name is the source name with its extension replaced. *)
let load_mutaml_catalogue path =
  let entries =
    match
      try Yojson.Safe.from_file path with _ -> `Null
    with
    | `List l -> Some l
    | _ -> None
  in
  match entries with
  | Some entries ->
      List.filter_map
        (function
          | `Assoc m ->
              let number = match List.assoc_opt "number" m with Some (`Int n) -> Some n | _ -> None in
              let repl =
                match List.assoc_opt "repl" m with Some (`String r) -> r | _ -> ""
              in
              let loc = match List.assoc_opt "loc" m with Some (`Assoc l) -> l | _ -> [] in
              let pos which =
                match List.assoc_opt which loc with Some (`Assoc p) -> p | _ -> []
              in
              let ints p k = match List.assoc_opt k p with Some (`Int i) -> i | _ -> 0 in
              let start = pos "loc_start" and stop = pos "loc_end" in
              let fname =
                match List.assoc_opt "pos_fname" start with Some (`String f) -> f | _ -> ""
              in
              if fname = "" then None
              else
                Option.map
                  (fun n ->
                    { s_id = Filename.remove_extension fname ^ ":" ^ string_of_int n;
                      s_file = fname;
                      s_line = ints start "pos_lnum";
                      s_col_start = ints start "pos_cnum" - ints start "pos_bol";
                      s_col_end = ints stop "pos_cnum" - ints stop "pos_bol";
                      s_repl = repl })
                  number
          | _ -> None)
        entries
  | None -> []

(** The catalogue the driver must have BEFORE the engine runs: without it the wrapper
    cannot resolve [MUTAML_MUTANT] to anything, and the [mutants] site rows have nothing
    to be built from.

    Two shapes are read. A mutaml [.muts] file (a JSON array), or mutaml's own
    [mutaml-mut-files.txt] — a newline-separated list of [.muts] paths, which is what a
    whole-project instrumentation run actually produces. Anything else is the generic
    NDJSON contract. *)
let load_catalogue ~from path =
  if from = "mutaml" then (
    let direct = load_mutaml_catalogue path in
    if direct <> [] then direct
    else
      (* Not a .muts array: read it as mutaml-mut-files.txt, resolving each listed file
         relative to the list's own directory and to mutaml's _build/default prefix. *)
      let dir = Filename.dirname path in
      let lines =
        let ic =
          try open_in path
          with Sys_error e -> die ("arch-mutants: cannot read the catalogue: " ^ e)
        in
        let acc = ref [] in
        (try
           while true do
             let l = String.trim (input_line ic) in
             if l <> "" then acc := l :: !acc
           done
         with End_of_file -> ()) ;
        close_in ic ;
        List.rev !acc
      in
      let resolved =
        List.concat_map
          (fun l ->
            let candidates =
              [ l; Filename.concat dir l;
                Filename.concat (Filename.concat "_build" "default") l ]
            in
            match List.find_opt Sys.file_exists candidates with
            | Some p -> load_mutaml_catalogue p
            | None -> [])
          lines
      in
      if resolved = [] then
        die
          (Printf.sprintf
             "arch-mutants: %s yielded no mutants. Expected either a mutaml `.muts` JSON \
              array or a `mutaml-mut-files.txt` listing one path per line. A campaign over \
              an empty catalogue would report nothing and read as 'no survivors'."
             path)
      else resolved)
  else
    let ic =
      try open_in path with Sys_error e -> die ("arch-mutants: cannot read the catalogue: " ^ e)
    in
    let acc = ref [] and n = ref 0 in
    (try
       while true do
         let raw = String.trim (input_line ic) in
         incr n ;
         if raw <> "" then
           match Yojson.Safe.from_string raw with
           | `Assoc a ->
               let str k = match List.assoc_opt k a with Some (`String s) -> Some s | _ -> None in
               let num k d = match List.assoc_opt k a with Some (`Int i) -> i | _ -> d in
               (match (str "id", str "file", List.assoc_opt "line" a) with
               | Some id, Some f, Some (`Int l) ->
                   acc :=
                     { s_id = id; s_file = f; s_line = l;
                       s_col_start = num "col_start" 0; s_col_end = num "col_end" 0;
                       s_repl = Option.value ~default:"" (str "replacement") }
                     :: !acc
               | _ ->
                   die
                     (Printf.sprintf
                        "arch-mutants: %s:%d: a catalogue record needs id/file/line" path !n))
           | _ -> die (Printf.sprintf "arch-mutants: %s:%d: record is not a JSON object" path !n)
       done
     with
    | End_of_file -> ()
    | Yojson.Json_error e -> die (Printf.sprintf "arch-mutants: %s:%d: invalid JSON: %s" path !n e)) ;
    close_in ic ;
    List.rev !acc

(** [Digest.to_hex (Digest.string ...)] — the repository's existing idiom (see
    [Arch_index_compare]'s body hash).

    Hashing the mutated SOURCE LINE is what makes the site key survive an edit above the
    mutant and refuse to conflate two different texts that landed on the same span. When
    the source cannot be read the hash degrades to the site descriptor itself: still
    stable, still discriminating between two replacements at one span, but it no longer
    notices a rewrite of the line. That degradation is named here rather than hidden,
    because a hash that silently stops discriminating is a key that silently stops being
    one. *)
let source_hash ~repo s =
  let path = if Filename.is_relative s.s_file then Filename.concat repo s.s_file else s.s_file in
  let line =
    match open_in path with
    | exception Sys_error _ -> None
    | ic ->
        let rec go i =
          match input_line ic with
          | l -> if i = s.s_line then Some l else go (i + 1)
          | exception End_of_file -> None
        in
        let r = go 1 in
        close_in_noerr ic ;
        r
  in
  match line with
  | Some l -> Digest.to_hex (Digest.string l)
  | None ->
      Digest.to_hex
        (Digest.string
           (Printf.sprintf "site\x00%s\x00%d\x00%d\x00%d\x00%s" s.s_file s.s_line s.s_col_start
              s.s_col_end s.s_repl))

(** Resolve a PATH-or-path command to an absolute binary, or [None].

    [None] is what produces the exit-2 refusal: an unresolvable engine writes NO campaign
    row, because a campaign with no runs and no rows reads exactly like a campaign in
    which nothing survived. *)
let resolve_binary cmd =
  let word = match String.split_on_char ' ' (String.trim cmd) with w :: _ -> w | [] -> "" in
  if word = "" then None
  else if String.contains word '/' then
    if Sys.file_exists word then Some word else None
  else
    let out = Filename.temp_file "arch-mutants-which" ".txt" in
    let code =
      Sys.command (Printf.sprintf "command -v %s > %s 2>/dev/null" (Filename.quote word) (Filename.quote out))
    in
    let value =
      match open_in out with
      | exception Sys_error _ -> ""
      | ic ->
          let v = try String.trim (input_line ic) with End_of_file -> "" in
          close_in_noerr ic ;
          v
    in
    (try Sys.remove out with Sys_error _ -> ()) ;
    if code = 0 && value <> "" then Some value else None

(** The wrapper the engine will call once per mutant. [ARCH_MUTANTS_WRAPPER] overrides;
    otherwise it is found by walking up from the working directory, the same resolution
    the test harness uses. An override that names a path which does not exist is refused
    rather than falling back: a silent fallback is how a campaign comes to run something
    other than what the operator named. *)
let locate_wrapper () =
  match Sys.getenv_opt "ARCH_MUTANTS_WRAPPER" with
  | Some p when Sys.file_exists p -> Some p
  | Some p -> die (Printf.sprintf "arch-mutants: ARCH_MUTANTS_WRAPPER=%s does not exist" p)
  | None ->
      let rec up d =
        let c = Filename.concat d "scripts/mutaml-wrapper.sh" in
        if Sys.file_exists c then Some c
        else
          let parent = Filename.dirname d in
          if parent = d then None else up parent
      in
      up (Sys.getcwd ())

let mkdir_p d =
  let rec go d =
    if not (Sys.file_exists d) then (
      go (Filename.dirname d) ;
      try Unix.mkdir d 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
  in
  go d

let write_file path contents =
  mkdir_p (Filename.dirname path) ;
  let oc = open_out path in
  Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc contents)

let read_lines path =
  match open_in path with
  | exception Sys_error _ -> []
  | ic ->
      let acc = ref [] in
      (try
         while true do
           acc := input_line ic :: !acc
         done
       with End_of_file -> ()) ;
      close_in_noerr ic ;
      List.rev !acc

let split_on s c = String.split_on_char c s

(** One catalogued mutant, resolved: which function it sits in, which tests the plan says
    reach that function ({b intended}), and which tests the profile can actually address
    ({b executed}). The second is always a superset of the first. *)
type selection = {
  sel_site : site;
  sel_fn : string option;
  sel_intended : string list;
  sel_executed : string list;
  sel_superset : bool;
  sel_hash : string;
}

let run_campaign (t : Arch_db.t) (g : Arch_graph.t) test_keys ~db_path ~plan_path ~engine
    ~engine_version ~seed ~profile_name ~granularity ~from ~catalogue_path ~report_path
    ~test_cmd ~repo ~fmt ~maxlist =
  (* 1. Resolve what will actually run, BEFORE writing anything. *)
  let wrapper =
    match locate_wrapper () with
    | Some w -> w
    | None ->
        prerr_endline
          "arch-mutants: cannot find scripts/mutaml-wrapper.sh from here. It is the \
           per-mutant test command the engine calls; without it the campaign would run \
           the whole suite for every mutant and record a selection it never made. Set \
           ARCH_MUTANTS_WRAPPER." ;
        exit 2
  in
  let engine_path =
    match resolve_binary engine with
    | Some p -> p
    | None ->
        Printf.eprintf
          "arch-mutants: engine %S could not be resolved (profile %s). No campaign row was \
           written: an empty campaign must never read as \"no survivors\".\n"
          engine
          (match profile_name with Some p -> p | None -> "none") ;
        exit 2
  in
  let runner_path =
    match resolve_binary test_cmd with
    | Some p -> p
    | None ->
        Printf.eprintf
          "arch-mutants: the test command %S could not be resolved (profile %s). No \
           campaign row was written.\n"
          test_cmd
          (match profile_name with Some p -> p | None -> "none") ;
        exit 2
  in
  (* 2. Selection provenance — ONE binding, shared with `plan`, never recomputed. *)
  let _, escapes = cone_escapes g test_keys in
  let sound = Arch_db.contract_ok t "mutants" in
  let provenance =
    if not sound then MDb.No_contract
    else if escapes <> [] then MDb.Top_bounded
    else MDb.Proved_superset
  in
  (* 3. The plan, the catalogue, and the mapping between them. *)
  let targets = load_plan plan_path in
  let sites = load_catalogue ~from catalogue_path in
  let resolver = Arch_path.make ~repo (List.map (fun tg -> tg.t_file) targets) in
  let by_file = Hashtbl.create 32 in
  List.iter
    (fun tg ->
      Hashtbl.replace by_file tg.t_file (tg :: Option.value ~default:[] (Hashtbl.find_opt by_file tg.t_file)))
    targets ;
  (* Test name → the file it lives in, so a `group` profile can widen a selection to the
     coarser unit its runner can actually name. *)
  let test_file = Hashtbl.create 32 in
  let all_tests =
    SS.fold
      (fun k acc ->
        match SM.find_opt k g.nodes with
        | Some (n : Arch_graph.node) ->
            Hashtbl.replace test_file n.name (Option.value ~default:"" n.file) ;
            n.name :: acc
        | None -> acc)
      test_keys []
    |> List.sort_uniq compare
  in
  let tests_in_file = Hashtbl.create 32 in
  List.iter
    (fun name ->
      let f = Option.value ~default:"" (Hashtbl.find_opt test_file name) in
      Hashtbl.replace tests_in_file f (name :: Option.value ~default:[] (Hashtbl.find_opt tests_in_file f)))
    all_tests ;
  let expand intended =
    match granularity with
    | Case -> intended
    | Group ->
        List.concat_map
          (fun name ->
            let f = Option.value ~default:"" (Hashtbl.find_opt test_file name) in
            Option.value ~default:[ name ] (Hashtbl.find_opt tests_in_file f))
          intended
        |> List.sort_uniq compare
    | Suite -> all_tests
  in
  let selections =
    List.map
      (fun s ->
        let best = ref None in
        Arch_path.SS.iter
          (fun known ->
            List.iter
              (fun tg ->
                if tg.t_a <= s.s_line && s.s_line <= tg.t_b then
                  (* innermost enclosing span wins — blaming an enclosing function sends
                     the developer hunting through it *)
                  match !best with
                  | Some prev when prev.t_b - prev.t_a <= tg.t_b - tg.t_a -> ()
                  | _ -> best := Some tg)
              (Option.value ~default:[] (Hashtbl.find_opt by_file known)))
          (Arch_path.resolve resolver s.s_file) ;
        let intended = match !best with Some tg -> tg.t_tests | None -> [] in
        let executed = expand intended in
        { sel_site = s;
          sel_fn = (match !best with Some tg -> Some tg.t_fn | None -> None);
          sel_intended = intended;
          sel_executed = executed;
          sel_superset = List.length executed > List.length intended;
          sel_hash = source_hash ~repo s })
      sites
  in
  (* 4. The work directory: the selection the wrapper reads, and the trace it writes. *)
  let work =
    match Sys.getenv_opt "ARCH_MUTANTS_WORKDIR" with
    | Some d -> d
    | None ->
        Filename.concat (Filename.get_temp_dir_name ())
          (Printf.sprintf "arch-mutants-%d" (Unix.getpid ()))
  in
  mkdir_p work ;
  let selection_file = Filename.concat work "selection.tsv" in
  let trace_file = Filename.concat work "wrapper-trace.tsv" in
  write_file selection_file
    (String.concat ""
       (List.map
          (fun sel ->
            Printf.sprintf "%s\t%d\t%s\t%s\n" sel.sel_site.s_id
              (if sel.sel_superset then 1 else 0)
              (String.concat "," sel.sel_intended)
              (String.concat "," sel.sel_executed))
          selections)) ;
  write_file trace_file "" ;
  (* 5. Open the database and write the campaign row. Only now: everything that could
     refuse has refused. *)
  let db =
    try MDb.open_and_migrate db_path
    with MDb.Write_failed m -> die ("arch-mutants: " ^ m)
  in
  let finish code =
    MDb.close db ;
    exit code
  in
  let campaign_id =
    try
      MDb.insert_campaign db ~engine ~engine_version ~seed ~producer_run_id:None
        ~engine_path ~test_runner_path:runner_path ~profile:profile_name
        ~granularity:(granularity_to_string granularity)
    with MDb.Write_failed m ->
      prerr_endline ("arch-mutants: " ^ m) ;
      finish 2
  in
  let mutant_ids = Hashtbl.create 32 in
  List.iter
    (fun sel ->
      let s = sel.sel_site in
      match
        MDb.insert_mutant db ~file_path:s.s_file ~line:s.s_line ~col_start:s.s_col_start
          ~col_end:s.s_col_end ~replacement:s.s_repl ~source_hash:sel.sel_hash
          ~function_id:None ~function_name:sel.sel_fn
      with
      | id -> Hashtbl.replace mutant_ids s.s_id id
      | exception MDb.Write_failed m -> prerr_endline ("arch-mutants: " ^ m))
    selections ;
  (* 6. ONE engine invocation. The engine loops; the wrapper is what runs per mutant. *)
  let env =
    [ ("ARCH_MUTANTS_SELECTION", selection_file); ("ARCH_MUTANTS_TRACE", trace_file);
      ("ARCH_MUTANTS_TEST_CMD", test_cmd) ]
  in
  (* The engine's own chatter — and the test runner's, through the wrapper — is routed to
     stderr. arch-index's convention is that stdout is the machine-readable surface, and an
     engine that prints one line of progress would otherwise land in the middle of the JSON
     object this command emits, making it unparseable for exactly the consumers it exists
     for. Nothing is lost: the operator still sees every line. *)
  let cmd =
    Printf.sprintf "{ %s %s %s ; } >&2"
      (String.concat " "
         (List.map (fun (k, v) -> Printf.sprintf "%s=%s" k (Filename.quote v)) env))
      engine (Filename.quote wrapper)
  in
  let engine_code = Sys.command cmd in
  (* FR-032: 3 means REFUSED — the callee declined to answer. It is neither a failure nor
     an empty result, and folding it into either loses "did not really run" at exactly the
     process boundary the distinction has to cross. *)
  let refused = engine_code = 3 in
  (* 7. What the wrapper actually executed, per mutant. *)
  let executed_by_id = Hashtbl.create 32 in
  List.iter
    (fun line ->
      match split_on line '\t' with
      | id :: _ :: executed :: _ ->
          let tests = List.filter (fun s -> s <> "") (split_on executed ',') in
          Hashtbl.replace executed_by_id id tests
      | _ -> ())
    (read_lines trace_file) ;
  (* 8. The engine's own report file is where each mutant's OUTCOME comes from — not
     stdout, not an exit code. It is read through the very adapters `report` already has. *)
  let outcomes =
    if Sys.file_exists report_path then
      if from = "mutaml" then load_mutaml report_path else load_generic report_path
    else []
  in
  (* Report entries carry a location, not the engine's wrapper id, so they are matched to
     catalogued sites by (file, line), consuming duplicates in order. An entry that
     matches nothing catalogued is counted rather than dropped. *)
  let pending_sites = ref selections in
  let unmatched = ref 0 in
  let attempted = ref [] in
  List.iter
    (fun (m : mutant) ->
      let base p = Filename.basename p in
      let rec take acc = function
        | [] -> None
        | sel :: tl
          when sel.sel_site.s_line = m.line
               && base sel.sel_site.s_file = base m.file ->
            Some (sel, List.rev_append acc tl)
        | sel :: tl -> take (sel :: acc) tl
      in
      match take [] !pending_sites with
      | Some (sel, rest) ->
          pending_sites := rest ;
          attempted := (sel, m) :: !attempted
      | None -> incr unmatched)
    outcomes ;
  let attempted = List.rev !attempted in
  (* 9. Persist one run row per ATTEMPTED mutant. A mutant with no row is PENDING by that
     absence — never SURVIVED. *)
  let killed = ref 0 and survived = ref 0 and timed_out = ref 0 and errored = ref 0 in
  let kills_written = ref 0 in
  List.iter
    (fun (sel, (m : mutant)) ->
      match MDb.status_of_string m.status with
      | None ->
          Printf.eprintf
            "arch-mutants: %s reports status %S for %s:%d, which is not one of \
             KILLED|SURVIVED|TIMEOUT|ERROR. Refusing to guess — a mis-read status inverts \
             the verdict.\n"
            report_path m.status m.file m.line ;
          ignore (finish 2 : 'a)
      | Some status ->
          (match status with
          | MDb.Killed -> incr killed
          | MDb.Survived -> incr survived
          | MDb.Timeout -> incr timed_out
          | MDb.Errored -> incr errored) ;
          let executed =
            Option.value ~default:sel.sel_executed
              (Hashtbl.find_opt executed_by_id sel.sel_site.s_id)
          in
          Option.iter
            (fun mutant_id ->
              (try
                 MDb.insert_run db ~campaign_id ~mutant_id
                   ~engine_mutant_id:(Some sel.sel_site.s_id) ~status ~provenance
                   ~intended:(List.length sel.sel_intended)
                   ~executed:(List.length executed)
                   ~superset:(List.length executed > List.length sel.sel_intended)
               with MDb.Write_failed msg -> prerr_endline ("arch-mutants: " ^ msg)) ;
              (* FR-007: attribution ONLY when it is genuinely known. A singleton executed
                 set is the one case the driver can prove by itself; an engine that names
                 the killing test is the other, and no engine surveyed does. A kill under a
                 larger set says the suite catches it, NOT which test did. *)
              match (status, executed) with
              | (MDb.Killed | MDb.Timeout), [ only ] -> (
                  try
                    MDb.insert_kill db ~campaign_id ~mutant_id ~test_name:only
                      ~attribution:MDb.Singleton_executed_set ;
                    incr kills_written
                  with MDb.Write_failed msg -> prerr_endline ("arch-mutants: " ^ msg))
              | (MDb.Killed | MDb.Timeout), ([] | _ :: _ :: _) -> ()
              | (MDb.Survived | MDb.Errored), _ -> ())
            (Hashtbl.find_opt mutant_ids sel.sel_site.s_id))
    attempted ;
  let catalogued = List.length selections in
  let n_attempted = List.length attempted in
  let pending = catalogued - n_attempted in
  let complete = (not refused) && engine_code = 0 && pending = 0 in
  (* Parenthesised, and it matters: without them the trailing `;` binds INSIDE the `with`
     handler, so every line below would run only on a write failure and a successful
     campaign would print nothing at all — while still typechecking, because the handler's
     tail is [exit]. *)
  (if complete then
     try MDb.complete_campaign db ~campaign_id
     with MDb.Write_failed m -> prerr_endline ("arch-mutants: " ^ m)) ;
  let any_kill = !killed + !timed_out > 0 in
  (* 10. Say it. FR-013: never a status without its provenance, in either format.
     FR-027/FR-029: a campaign with no kills is SELF-UNCERTIFIED, and the three ways of
     having no kill are three different facts that must never be reported in the same
     words. It is a VARIANT rather than a formatted string so a consumer — a test
     included — can assert on the tag rather than grep for a word: a word survives a great
     many wrong implementations, because it can be present for reasons that have nothing
     to do with the branch that was supposed to produce it. A tag cannot. *)
  let certification =
    if any_kill then `Certified
    else if n_attempted = 0 then `Nothing_attempted
    else if !survived = 0 then `All_errored
    else `No_kill
  in
  let certification_tag =
    match certification with
    | `Certified -> "self_certifying"
    | `Nothing_attempted -> "uncertified_nothing_attempted"
    | `All_errored -> "uncertified_all_errored"
    | `No_kill -> "uncertified_no_kill"
  in
  let certification_text =
    match certification with
    | `Certified ->
        "self-certifying: at least one mutant was KILLED, which an unmutated or stale \
         binary could not have produced"
    | `Nothing_attempted ->
        "SELF-UNCERTIFIED: nothing was attempted at all, so this campaign says nothing \
         about any test. This is NOT 'everything survived'"
    | `All_errored ->
        "SELF-UNCERTIFIED: every attempted mutant ERRORED — the campaign did not \
         meaningfully run. This is NOT 'ran and everything survived', and the two must \
         never be reported in the same words"
    | `No_kill ->
        "SELF-UNCERTIFIED: mutants were attempted and none was killed. An entirely green \
         campaign cannot distinguish a weak test suite from the wrong binary having run — \
         an unmutated binary produces exactly this picture. One single mutant whose \
         executed test set actually fails under the mutation is what would have made this \
         non-zero"
  in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("campaign_id", `Int campaign_id); ("db", `String db_path);
             ("engine", `String engine); ("engine_path", `String engine_path);
             ("engine_version", match engine_version with Some v -> `String v | None -> `Null);
             ("test_runner_path", `String runner_path);
             ("profile", match profile_name with Some p -> `String p | None -> `Null);
             ("granularity", `String (granularity_to_string granularity));
             ("seed", match seed with Some s -> `String s | None -> `Null);
             ("seed_declared", `Bool (seed <> None));
             ("selection_provenance", `String (MDb.provenance_to_string provenance));
             ("selection_caveat", `String (MDb.provenance_caveat provenance));
             ("mutants_catalogued", `Int catalogued); ("mutants_attempted", `Int n_attempted);
             ("mutants_pending", `Int pending);
             ("report_entries_unmatched", `Int !unmatched);
             ("completed", `Bool complete); ("engine_exit", `Int engine_code);
             ("engine_refused", `Bool refused);
             ("attributions_recorded", `Int !kills_written);
             (* Per-status counts, so a consumer can assert on a NUMBER it worked out by
                hand rather than on a word appearing somewhere in a rendering. A word
                survives a great many wrong implementations; a count does not. *)
             ("killed", `Int !killed); ("survived", `Int !survived);
             ("timed_out", `Int !timed_out); ("errored", `Int !errored);
             ("any_kill", `Bool any_kill);
             ("self_uncertified", `Bool (certification <> `Certified));
             ("certification", `String certification_tag);
             ("certification_text", `String certification_text);
             ( "runs",
               `List
                 (List.map
                    (fun (sel, (m : mutant)) ->
                      let executed =
                        Option.value ~default:sel.sel_executed
                          (Hashtbl.find_opt executed_by_id sel.sel_site.s_id)
                      in
                      `Assoc
                        [ ("engine_mutant_id", `String sel.sel_site.s_id);
                          ("file", `String sel.sel_site.s_file); ("line", `Int sel.sel_site.s_line);
                          ("function", match sel.sel_fn with Some f -> `String f | None -> `Null);
                          ("engine_status", `String (String.uppercase_ascii m.status));
                          (* FR-013: this key travels with engine_status, always. *)
                          ("selection_provenance", `String (MDb.provenance_to_string provenance));
                          ("intended_tests", `List (List.map (fun s -> `String s) sel.sel_intended));
                          ("executed_tests", `List (List.map (fun s -> `String s) executed));
                          ("executed_superset",
                           `Bool (List.length executed > List.length sel.sel_intended)) ])
                    attempted) ) ]))
  else (
    Printf.printf "== Mutation campaign %d\n" campaign_id ;
    Printf.printf "  • engine %s → %s%s\n" engine engine_path
      (match engine_version with Some v -> " (" ^ v ^ ")" | None -> "") ;
    Printf.printf "  • test runner %s → %s\n" test_cmd runner_path ;
    Printf.printf "  • profile %s, granularity %s\n"
      (match profile_name with Some p -> p | None -> "(none — one test case per mutant)")
      (granularity_to_string granularity) ;
    (match seed with
    | Some s -> Printf.printf "  • seed %s\n" s
    | None ->
        print_endline
          "  • no seed: this engine declares no seed concept. Recorded as absent rather \
           than as an empty value") ;
    Printf.printf "  • selection provenance: %s — %s\n"
      (MDb.provenance_to_string provenance)
      (MDb.provenance_caveat provenance) ;
    Printf.printf
      "  • %d mutant site(s) catalogued, %d attempted, %d PENDING (no run row in a \
       campaign whose completion is %s)\n"
      catalogued n_attempted pending
      (if complete then "recorded" else "NULL") ;
    if !unmatched > 0 then
      Printf.printf
        "  • %d report entry/entries matched no catalogued mutant — counted, not dropped\n"
        !unmatched ;
    Printf.printf "  • outcomes: %d KILLED, %d SURVIVED, %d TIMEOUT, %d ERROR\n" !killed
      !survived !timed_out !errored ;
    if !kills_written = 0 then
      print_endline
        "  • 0 per-test attributions recorded. What would have made it non-zero: a kill \
         whose executed test set was a SINGLETON, or an engine that names the killing \
         test. Attribution is never inferred from a larger set"
    else Printf.printf "  • %d per-test attribution(s) recorded\n" !kills_written ;
    if refused then
      print_endline
        "  • the engine exited 3 — REFUSED, meaning it declined to answer. That is neither \
         a failure nor an empty result and is not folded into either" ;
    Printf.printf "  • %s\n" certification_text ;
    print_endline "" ;
    print_endline "-- runs (engine status ALWAYS with its selection provenance)" ;
    List.iter
      (fun (sel, (m : mutant)) ->
        let executed =
          Option.value ~default:sel.sel_executed
            (Hashtbl.find_opt executed_by_id sel.sel_site.s_id)
        in
        Printf.printf "  • %-8s [%s]  %s:%d  in %s\n" (String.uppercase_ascii m.status)
          (MDb.provenance_to_string provenance) sel.sel_site.s_file sel.sel_site.s_line
          (match sel.sel_fn with Some f -> f | None -> "(unmapped — persisted, not dropped)") ;
        Printf.printf "      intended %d, executed %d%s\n" (List.length sel.sel_intended)
          (List.length executed)
          (if List.length executed > List.length sel.sel_intended then " (SUPERSET)" else ""))
      (take maxlist attempted) ;
    if maxlist > 0 && n_attempted > maxlist then
      Printf.printf "  … and %d more (--max-list 0 for all)\n" (n_attempted - maxlist)) ;
  finish (if refused then 3 else 0)

(* ------------------------------------------------------------------ *)

let main () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function a :: v :: _ when a = name -> v | _ :: tl -> go tl | [] -> default in
    go args
  in
  let flags =
    [ "--tests"; "--format"; "--max-list"; "--from"; "--repo";
      (* `run`'s own value-taking flags. They MUST be listed here or their values fall
         through into [positional] and the subcommand's database argument becomes whichever
         one came first. *)
      "--plan"; "--engine"; "--engine-version"; "--seed"; "--profile"; "--catalogue";
      "--report"; "--test-cmd" ]
  in
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
  | "run" ->
      let require name =
        match opt name "" with
        | "" ->
            die
              (Printf.sprintf
                 "arch-mutants: run needs %s. It is not defaulted: a guessed %s would drive \
                  a campaign the operator never asked for."
                 name name)
        | v -> v
      in
      let plan_path = require "--plan" in
      let engine = require "--engine" in
      (* The command the WRAPPER runs, as opposed to the engine the DRIVER runs. Two
         different programs, so two different arguments; conflating them is what makes a
         campaign run the whole suite N times and call it selection. *)
      let test_cmd = require "--test-cmd" in
      let from = opt "--from" "generic" in
      if from <> "generic" && from <> "mutaml" then
        die (Printf.sprintf "arch-mutants: --from %s is neither `generic` nor `mutaml`" from) ;
      let profile_name = match opt "--profile" "" with "" -> None | p -> Some p in
      let granularity =
        match profile_name with
        (* No profile means one test case per mutant — the finest and therefore the
           SOUNDEST addressing. A coarser default would silently widen every executed set
           and make every campaign cost more than it says it does. *)
        | None -> Case
        | Some p -> (
            match List.assoc_opt p known_profiles with
            | Some gr -> gr
            | None ->
                die
                  (Printf.sprintf
                     "arch-mutants: unknown profile %S. Known: %s. A profile is never \
                      silently defaulted — its granularity decides whether a survivor is \
                      admissible at all."
                     p
                     (String.concat ", " (List.map fst known_profiles))))
      in
      let catalogue_path =
        match opt "--catalogue" "" with
        | "" ->
            die
              "arch-mutants: run needs --catalogue, the engine's own list of the mutants it \
               will attempt (mutaml: a `.muts` file or `mutaml-mut-files.txt`; otherwise \
               NDJSON id/file/line records). Without it the wrapper cannot resolve \
               MUTAML_MUTANT to a test set and would fall back to running everything."
        | c -> c
      in
      let report_path =
        match opt "--report" "" with
        | "" -> if from = "mutaml" then "mutaml-report.json" else "mutants.ndjson"
        | r -> r
      in
      if fmt = "lines" then die "arch-mutants: --format lines is only meaningful for `plan`" ;
      run_campaign t g test_keys ~db_path ~plan_path ~engine
        ~engine_version:(match opt "--engine-version" "" with "" -> None | v -> Some v)
        ~seed:(match opt "--seed" "" with "" -> None | s -> Some s)
        ~profile_name ~granularity ~from ~catalogue_path ~report_path ~test_cmd
        ~repo:(opt "--repo" ".") ~fmt ~maxlist
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

(* The [open_ro] handler inside [main] covers exactly one call. A
   {!Arch_tools.Arch_db.Refused} raised by a LATER query — the schema-drift backstop in
   [Arch_db.ok] fires at any of them — escaped this binary altogether and was reported by
   OCaml's uncaught-exception path: a [Fatal error: exception …] dump at exit 2. This
   tool has no exit-3 contract (see the per-binary note in lib/arch_tools/arch_db.ml), so
   the code stays 2 and only the rendering changes. *)
let () = try main () with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-mutants: " ^ m)
