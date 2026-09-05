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
                                 [--diff <git-range>]
                                 [--repo DIR] [--format text|json] [--max-list N]
       arch-mutants verdict <db> [--campaign N] [--format text|json] [--max-list N]

`verdict` publishes what `run` persisted. The verdict is DERIVED, never stored:
KILLED or TIMEOUT publish KILLED whatever the provenance (a kill is a proof);
ERROR publishes ERROR; SURVIVED publishes SURVIVED only under `proved_superset`,
UNKNOWN under `top_bounded` and UNKNOWN_NO_CONTRACT under `no_contract`; and a
catalogued mutant with NO run row in a campaign whose completion is NULL is
PENDING, by that absence.

That last derivation needs a universe of catalogued sites, and no table records
which sites a campaign catalogued. So `verdict` REFUSES (exit 3) when it is asked
for an OPEN campaign in a database holding MORE THAN ONE campaign: there the only
derivable universe is the whole database's site table, which would report another
campaign's sites as this one's PENDING. One campaign, or a completed campaign, is
answered normally.

`run` invokes the ENGINE once. The engine loops over its own mutants and calls
scripts/mutaml-wrapper.sh once per mutant; the wrapper reads MUTAML_MUTANT, resolves it
through the plan, and runs only the tests that reach the mutated function. The per-mutant
executed set is always a SUPERSET of that reaching set, never a subset.

`run --diff <range>` scopes the campaign to what the range put at risk: mutants
inside functions the range TOUCHED, mutants of everything reached by a test the
range MODIFIED or ADDED (helpers included, so a shared helper selects every case
that traverses it), and mutants a prior campaign attributed to a DELETED test
ALONE. A mutant whose attribution was never known is reported UN-RECHECKABLE,
never silently skipped. Selection is by FUNCTION, so a comment-only change inside
a function still selects it — over-selection is sound, under-selection is not.
Without --diff the selection is the WHOLE INDEX, said so in the report; there is
no implicit default range. The diff -> function mapping comes from
`arch-impact --format json`, and its exit 3 means REFUSED, not failed.

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

(* ------------------------------------------------------------------ *)
(* --diff — DIFF-SCOPED SELECTION (FR-016, FR-017, FR-018)             *)
(*                                                                    *)
(* The selected set is the UNION of three things, and each is a        *)
(* different kind of claim:                                            *)
(*                                                                    *)
(*   1. mutants whose site falls inside a function the range TOUCHED;  *)
(*   2. mutants of every function reached by a test the range MODIFIED *)
(*      or ADDED — test helpers included, so a change to a shared      *)
(*      helper selects every case that traverses it and then           *)
(*      everything those cases reach;                                  *)
(*   3. for a test the range DELETED, every mutant a prior campaign    *)
(*      attributed to that test ALONE.                                 *)
(*                                                                    *)
(* Selection is BY FUNCTION, never by file and never by line. A        *)
(* comment-only change inside a production function still selects that *)
(* function's mutants. That over-selection is deliberate and sound:    *)
(* the alternative is parsing intent, and a selection that is too      *)
(* small turns a mutant an excluded test would have killed into a      *)
(* survivor — a false accusation against a real test. The report says  *)
(* so rather than presenting the selection as precise.                 *)
(*                                                                    *)
(* Rule 3's honest half is the un-recheckable list. A mutant whose     *)
(* attribution was NEVER known cannot be shown to be safe from the     *)
(* deletion, so it is reported separately rather than silently         *)
(* skipped — a rule that answers half a question must say which half.  *)
(* ------------------------------------------------------------------ *)

(** Where `arch-impact` is. [ARCH_IMPACT] overrides — the same variable
    `scripts/check-binary-provenance.sh` probes and the same convention
    `tezt/lib/arch_tezt.ml`'s `locate` uses — otherwise it is found by walking up from the
    working directory, and only then on PATH. An override naming a path that does not exist
    is REFUSED rather than falling back: a silent fallback is how a campaign comes to scope
    itself with another checkout's answer, which is issue #77's mechanism one tool over. *)
let locate_impact () =
  match Sys.getenv_opt "ARCH_IMPACT" with
  | Some p when Sys.file_exists p -> Some p
  | Some p -> die (Printf.sprintf "arch-mutants: ARCH_IMPACT=%s does not exist" p)
  | None -> (
      let rec up d =
        let c = Filename.concat d "_build/default/bin/arch_impact/arch_impact.exe" in
        if Sys.file_exists c then Some c
        else
          let parent = Filename.dirname d in
          if parent = d then None else up parent
      in
      match up (Sys.getcwd ()) with Some p -> Some p | None -> resolve_binary "arch-impact")

(** One entry of `arch-impact --format json`'s [touched] array. [how] is carried because it
    says at what granularity the mapping was made — ["line"] is a span hit, anything else is
    a whole-file fallback the reader must be able to see. *)
type touched_fn = { i_name : string; i_how : string }

(** What the subprocess said, kept as three distinct outcomes.

    FR-032: exit 3 means REFUSED — the callee declined to answer. It is neither a failure
    nor an empty result, and an empty touched set would select nothing and read as
    "nothing to test", which is the single worst way to lose the distinction. *)
type impact_outcome =
  | Impact_ok of touched_fn list
  | Impact_refused
  | Impact_failed of int

(** Shelled out on purpose, rather than extracting `arch-impact`'s diff→function mapping
    into a library. The logic is binary-local (bin/arch_impact/arch_impact.ml's [analyse])
    and extracting it is shared-library surgery this campaign does not own. The JSON shape
    was confirmed by running the command, not read off a document. *)
let run_impact ~impact ~db_path ~repo ~range =
  let out = Filename.temp_file "arch-mutants-impact" ".json" in
  (* stdout to the file, stderr left alone: arch-impact's warnings (a file with no line
     spans, a changed file absent from the index) are exactly what an operator needs to see
     when a selection comes out surprising. *)
  let code =
    Sys.command
      (Printf.sprintf "%s %s --diff %s --repo %s --format json > %s"
         (Filename.quote impact) (Filename.quote db_path) (Filename.quote range)
         (Filename.quote repo) (Filename.quote out))
  in
  let cleanup () = try Sys.remove out with Sys_error _ -> () in
  if code = 3 then (cleanup () ; Impact_refused)
  else if code <> 0 then (cleanup () ; Impact_failed code)
  else
    let json = try Yojson.Safe.from_file out with _ -> `Null in
    cleanup () ;
    match json with
    | `Assoc a -> (
        match List.assoc_opt "touched" a with
        | Some (`List l) ->
            Impact_ok
              (List.filter_map
                 (function
                   | `Assoc f -> (
                       let str k =
                         match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None
                       in
                       match str "name" with
                       | Some n -> Some { i_name = n; i_how = Option.value ~default:"?" (str "how") }
                       | None -> None)
                   | _ -> None)
                 l)
        | _ ->
            die
              (Printf.sprintf
                 "arch-mutants: %s --format json produced no `touched` array. The diff→function \
                  mapping is read from that key; refusing to continue on an empty set, which \
                  would select nothing and read as 'nothing to test'."
                 impact))
    | _ ->
        die
          (Printf.sprintf
             "arch-mutants: %s --format json did not produce a JSON object. Refusing to scope a \
              campaign on output it cannot read."
             impact)

(** One mutant as a PRIOR campaign left it: the latest campaign that ran it, that run's
    engine status, and how many `mutant_kills` rows that campaign holds for it.

    "Alone" is [pk_kills = 1] together with [pk_sole_test]. Attribution "never known" is
    [pk_kills = 0] on a mutant that was killed — the executed set was larger than one and
    no engine named the killer, so nothing can say whether the deleted test was the only
    one catching it. *)
type prior_mutant = {
  pk_file : string;
  pk_line : int;
  pk_killed : bool;
  pk_kills : int;
  pk_sole_test : string option;
}

module Prior_shape = struct
  open Arch_db

  let s = Rows.s
  let i = Rows.i

  (* file_path, line, engine_status, one kill row's test_name, kill count *)
  let row = Ty.(t2 (t3 s i s) (t2 s i))

  let cells ((file, line, status), (test, kills)) =
    [ text_cell file; int_cell line; text_cell status; text_cell test; int_cell kills ]
end

let prior_mutants (t : Arch_db.t) =
  if not (Arch_db.has_table t "mutant_runs" && Arch_db.has_table t "mutant_kills") then None
  else
    Some
      (List.filter_map
         (fun row ->
           match row with
           | [ file_c; line_c; status_c; test_c; kills_c ] ->
               let text = function
                 | Arch_db.Text s -> Some s
                 | Arch_db.Nul | Arch_db.Int _ | Arch_db.Real _ -> None
               in
               let int_of = function
                 | Arch_db.Int i -> Some i
                 | Arch_db.Nul | Arch_db.Text _ | Arch_db.Real _ -> None
               in
               let kills = Option.value ~default:0 (int_of kills_c) in
               let killed =
                 match Option.map MDb.status_of_string (text status_c) with
                 | Some (Some MDb.Killed) | Some (Some MDb.Timeout) -> true
                 | Some (Some MDb.Survived) | Some (Some MDb.Errored) -> false
                 | Some None | None ->
                     die
                       (Printf.sprintf
                          "arch-mutants: a prior mutant_runs row holds engine_status %S, which \
                           is not one of KILLED|SURVIVED|TIMEOUT|ERROR. Refusing to guess: a \
                           status added to the CHECK and dropped here would silently shrink the \
                           re-check set."
                          (Option.value ~default:"NULL" (text status_c)))
               in
               Some
                 { pk_file = Option.value ~default:"" (text file_c);
                   pk_line = Option.value ~default:0 (int_of line_c);
                   pk_killed = killed;
                   pk_kills = kills;
                   pk_sole_test = (if kills = 1 then text test_c else None) }
           | _ -> None)
         (Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Prior_shape.row
            ~to_cells:Prior_shape.cells
            "SELECT m.file_path, m.line, r.engine_status, (SELECT k.test_name FROM \
             mutant_kills k WHERE k.mutant_id = m.id AND k.campaign_id = l.cid ORDER BY \
             k.test_name LIMIT 1), (SELECT count(*) FROM mutant_kills k WHERE k.mutant_id = \
             m.id AND k.campaign_id = l.cid) FROM mutants m JOIN (SELECT mutant_id AS mid, \
             MAX(campaign_id) AS cid FROM mutant_runs GROUP BY mutant_id) l ON l.mid = m.id \
             JOIN mutant_runs r ON r.mutant_id = m.id AND r.campaign_id = l.cid ORDER BY m.id"
            ()))

(** Every test name any prior campaign attributed a kill to. Only these can be found to
    have been DELETED, because `mutant_kills` is the only place a campaign records a test
    name at all. *)
let prior_kill_tests (t : Arch_db.t) =
  if not (Arch_db.has_table t "mutant_kills") then []
  else
    List.filter_map
      (fun row -> match row with [ Arch_db.Text s ] -> Some s | _ -> None)
      (Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1
         ~to_cells:Arch_db.Rows.c1 "SELECT DISTINCT test_name FROM mutant_kills ORDER BY 1" ())

type diff_scope = {
  ds_range : string;
  ds_impact_path : string;
  ds_touched : string list;
  ds_touched_tests : string list;
  ds_reached : string list;
  ds_by_function : SS.t;  (** the union of rules 1 and 2, as function NAMES *)
  ds_prior_known : bool;
  ds_deleted_tests : string list;
  ds_recheck : (string * int) list;
  ds_unrecheckable : (string * int) list;
  ds_file_granular : int;
}

let same_site (file, line) (s : site) =
  line = s.s_line
  && (file = s.s_file || Filename.basename file = Filename.basename s.s_file)

let in_scope ds (sel : selection) =
  (match sel.sel_fn with Some fn -> SS.mem fn ds.ds_by_function | None -> false)
  || List.exists (fun site -> same_site site sel.sel_site) ds.ds_recheck

(** Build the scope. Nothing here writes: this runs BEFORE the campaign row exists, so a
    refusal leaves no campaign behind to be misread as "no survivors". *)
let compute_diff_scope (t : Arch_db.t) (g : Arch_graph.t) test_keys ~db_path ~repo ~range =
  let impact =
    match locate_impact () with
    | Some p -> p
    | None ->
        prerr_endline
          "arch-mutants: --diff needs arch-impact, which could not be found. It supplies the \
           diff → touched-function mapping; without it the touched set would be empty and an \
           empty set selects nothing, which reads as \"nothing to test\". Set ARCH_IMPACT." ;
        exit 2
  in
  let touched =
    match run_impact ~impact ~db_path ~repo ~range with
    | Impact_ok l -> l
    | Impact_refused ->
        Printf.eprintf
          "arch-mutants: %s REFUSED (exit 3) for range %s — it declined to answer rather than \
           failing. The campaign is NOT scoped and NOT run: an empty touched-function set \
           would select nothing and read as \"nothing to test\". No campaign row was written.\n"
          impact range ;
        exit 3
    | Impact_failed code ->
        Printf.eprintf
          "arch-mutants: %s exited %d for range %s. That is a FAILURE, distinct from the \
           refusal exit 3 carries. No campaign row was written.\n"
          impact code range ;
        exit 2
  in
  let touched_names = List.sort_uniq compare (List.map (fun x -> x.i_name) touched) in
  let file_granular =
    List.length (List.filter (fun x -> x.i_how <> "line") touched)
  in
  let want = List.fold_left (fun a n -> SS.add n a) SS.empty touched_names in
  let touched_keys =
    SM.fold
      (fun k (n : Arch_graph.node) acc -> if SS.mem n.name want then SS.add k acc else acc)
      g.nodes SS.empty
  in
  (* Rule 2. A touched TEST-side function may be a helper rather than a case, so the cases
     that traverse it are found by going BACKWARD to the test roots first, and only then
     forward. Forward from the helper alone would miss everything its callers reach, which
     is most of what a shared helper's change puts at risk. *)
  let touched_tests = SS.inter touched_keys test_keys in
  let cases =
    if SS.is_empty touched_tests then SS.empty
    else SS.union touched_tests (SS.inter (Arch_graph.closure touched_tests g.bwd) test_keys)
  in
  let reached_keys =
    if SS.is_empty cases then SS.empty else Arch_graph.closure cases g.fwd
  in
  let names_of keys =
    SS.fold
      (fun k acc ->
        match SM.find_opt k g.nodes with
        | Some (n : Arch_graph.node) -> SS.add n.name acc
        | None -> acc)
      keys SS.empty
  in
  let reached = names_of reached_keys in
  (* Rule 3. A deleted test is a name a prior campaign recorded that the CURRENT index no
     longer carries — the spec's own definition, and the only one available: `mutant_kills`
     holds a test NAME and no file, so the range cannot be intersected with it. *)
  let indexed_names = names_of (SM.fold (fun k _ acc -> SS.add k acc) g.nodes SS.empty) in
  let prior = prior_mutants t in
  let deleted_tests =
    List.filter (fun name -> not (SS.mem name indexed_names)) (prior_kill_tests t)
  in
  let deleted_set = List.fold_left (fun a n -> SS.add n a) SS.empty deleted_tests in
  let recheck, unrecheckable =
    match prior with
    | None -> ([], [])
    | Some rows ->
        if deleted_tests = [] then ([], [])
        else
          ( List.filter_map
              (fun p ->
                match p.pk_sole_test with
                | Some tn when SS.mem tn deleted_set -> Some (p.pk_file, p.pk_line)
                | Some _ | None -> None)
              rows,
            List.filter_map
              (fun p -> if p.pk_killed && p.pk_kills = 0 then Some (p.pk_file, p.pk_line) else None)
              rows )
  in
  { ds_range = range;
    ds_impact_path = impact;
    ds_touched = touched_names;
    ds_touched_tests = SS.elements (names_of touched_tests);
    ds_reached = SS.elements reached;
    ds_by_function = SS.union want reached;
    ds_prior_known = prior <> None;
    ds_deleted_tests = deleted_tests;
    ds_recheck = recheck;
    ds_unrecheckable = unrecheckable;
    ds_file_granular = file_granular }

let run_campaign (t : Arch_db.t) (g : Arch_graph.t) test_keys ~db_path ~plan_path ~engine
    ~engine_version ~seed ~profile_name ~granularity ~from ~catalogue_path ~report_path
    ~test_cmd ~diff_range ~repo ~fmt ~maxlist =
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
  (* 3b. --diff: narrow the catalogue to what the range put at risk. Done BEFORE anything
     is written, so a refusal from arch-impact leaves no campaign row behind. An absent
     --diff means WHOLE-INDEX selection, stated in the report; there is no implicit
     default range, because a guessed range scopes a campaign the operator never asked
     for and the result is indistinguishable from a correct one. *)
  let scope =
    Option.map
      (fun range -> compute_diff_scope t g test_keys ~db_path ~repo ~range)
      diff_range
  in
  let catalogued_total = List.length selections in
  let selections, excluded, excluded_unmapped =
    match scope with
    | None -> (selections, [], 0)
    | Some ds ->
        let keep, drop = List.partition (in_scope ds) selections in
        (keep, drop, List.length (List.filter (fun s -> s.sel_fn = None) drop))
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
  let site_json (f, l) = `Assoc [ ("file", `String f); ("line", `Int l) ] in
  let strings l = `List (List.map (fun s -> `String s) l) in
  (* The scope, published in full. A selection nobody can inspect is a selection nobody can
     contradict, and this one deliberately over-selects: it is by FUNCTION, so a
     comment-only edit inside a production function still selects that function's mutants. *)
  let diff_scope_json =
    match scope with
    | None ->
        `Assoc
          [ ("range", `Null); ("whole_index", `Bool true);
            ("note",
             `String
               "no --diff was given, so every catalogued mutant is in scope. There is no \
                implicit default range: a guessed one would scope a campaign the operator \
                never asked for, and the result would be indistinguishable from a correct \
                one") ]
    | Some ds ->
        `Assoc
          [ ("range", `String ds.ds_range); ("whole_index", `Bool false);
            ("impact_path", `String ds.ds_impact_path);
            ("selection_granularity", `String "function");
            ("over_selects_by_design", `Bool true);
            ("touched_functions", strings ds.ds_touched);
            ("touched_functions_matched_at_file_granularity", `Int ds.ds_file_granular);
            ("touched_tests", strings ds.ds_touched_tests);
            ("functions_reached_by_touched_tests", strings ds.ds_reached);
            ("prior_attribution_available", `Bool ds.ds_prior_known);
            ("deleted_tests", strings ds.ds_deleted_tests);
            ("rechecked_for_deleted_tests", `List (List.map site_json ds.ds_recheck));
            (* The honest half of rule 3. A mutant nobody could attribute cannot be shown
               to be safe from the deletion, so it is named rather than skipped. *)
            ("unrecheckable", `List (List.map site_json ds.ds_unrecheckable)) ]
  in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("campaign_id", `Int campaign_id); ("db", `String db_path);
             ("diff_scope", diff_scope_json);
             ("mutants_catalogued_before_scoping", `Int catalogued_total);
             ("mutants_excluded_by_scope", `Int (List.length excluded));
             ("mutants_excluded_unmapped", `Int excluded_unmapped);
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
    (match scope with
    | None ->
        print_endline
          "  • no --diff: WHOLE-INDEX selection. Every catalogued mutant is in scope. There \
           is no implicit default range" ;
        Printf.printf "  • %d mutant site(s) catalogued, none excluded by a scope\n"
          catalogued_total
    | Some ds ->
        Printf.printf "  • --diff %s, scoped through %s\n" ds.ds_range ds.ds_impact_path ;
        print_endline
          "  • selection is by FUNCTION, not by file and not by line. A comment-only change \
           inside a production function still selects that function's mutants. That \
           OVER-selection is deliberate: a selection that is too small turns a mutant an \
           excluded test would have killed into a survivor, which is a false accusation \
           against a real test" ;
        Printf.printf "  • %d function(s) touched by the range%s: %s%s\n"
          (List.length ds.ds_touched)
          (if ds.ds_file_granular > 0 then
             Printf.sprintf " (%d matched at WHOLE-FILE granularity, so every function in \
                             those files counts as touched)"
               ds.ds_file_granular
           else "")
          (if ds.ds_touched = [] then
             "none — the range touches no indexed function (config, docs, or a file outside \
              the index). What would have made this non-zero: a changed line inside the span \
              of an indexed function"
           else String.concat ", " (take maxlist ds.ds_touched))
          (if maxlist > 0 && List.length ds.ds_touched > maxlist then
             Printf.sprintf " … +%d" (List.length ds.ds_touched - maxlist)
           else "") ;
        Printf.printf
          "  • %d touched function(s) are tests; through the cases that traverse them, %d \
           function(s) are reached and in scope\n"
          (List.length ds.ds_touched_tests) (List.length ds.ds_reached) ;
        if not ds.ds_prior_known then
          print_endline
            "  • no prior campaign tables in this database, so no test can be shown to have \
             been deleted and nothing can be re-checked for one. What would have made this \
             non-zero: one earlier `arch-mutants run` against this index"
        else if ds.ds_deleted_tests = [] then
          print_endline
            "  • 0 deleted test(s): every test a prior campaign attributed a kill to is still \
             in this index. What would have made this non-zero: a test name recorded in \
             `mutant_kills` that the current index no longer carries"
        else (
          Printf.printf "  • %d deleted test(s): %s\n" (List.length ds.ds_deleted_tests)
            (String.concat ", " (take maxlist ds.ds_deleted_tests)) ;
          Printf.printf
            "  • %d mutant(s) re-selected because a prior campaign attributed them to a \
             deleted test ALONE (exactly one kill row in that mutant's latest campaign)\n"
            (List.length ds.ds_recheck) ;
          if ds.ds_unrecheckable = [] then
            print_endline
              "  • 0 UN-RECHECKABLE mutant(s). What would have made this non-zero: a mutant \
               killed in its latest campaign with NO kill row — an executed set larger than \
               one, so nothing can say whether the deleted test was the only one catching it"
          else (
            Printf.printf
              "  • %d UN-RECHECKABLE mutant(s): killed in their latest campaign with no \
               attribution recorded, so nothing can say whether a deleted test was the only \
               one catching them. Reported, never silently skipped:\n"
              (List.length ds.ds_unrecheckable) ;
            List.iter
              (fun (f, l) -> Printf.printf "      %s:%d\n" f l)
              (take maxlist ds.ds_unrecheckable))) ;
        Printf.printf
          "  • %d of %d catalogued mutant(s) excluded by the scope, %d of them because the \
           index maps them to no function at all\n"
          (List.length excluded) catalogued_total excluded_unmapped) ;
    Printf.printf
      "  • %d mutant site(s) in scope, %d attempted, %d PENDING (no run row in a \
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
(* verdict — the PUBLISHED verdict over what `run` persisted           *)
(*                                                                    *)
(* Derived, never stored (FR-011). There is no `verdict` column and    *)
(* there must never be one: PENDING in particular is the ABSENCE of a  *)
(* `mutant_runs` row inside a campaign whose `completed_at` is NULL,   *)
(* and a stored PENDING would widen a vocabulary closed to four values *)
(* that this file's own bucketing depends on.                          *)
(* ------------------------------------------------------------------ *)

let cell_text = function Arch_db.Text s -> Some s | Arch_db.Nul | Arch_db.Int _ | Arch_db.Real _ -> None
let cell_int = function Arch_db.Int i -> Some i | Arch_db.Nul | Arch_db.Text _ | Arch_db.Real _ -> None

(** One reported mutant. [f_outcome] is [None] for a PENDING finding and for nothing else:
    where the schema carries no run row, there is no status and no provenance, and the
    honest answer is the absence of both — never the first pair that happens to be lying
    around in the campaign (FR-033). *)
type finding = {
  f_file : string;
  f_line : int;
  f_fn : string option;
  f_engine_id : string option;
  f_outcome : MDb.outcome option;
  f_verdict : MDb.verdict;
}

let all_verdicts =
  [ MDb.V_killed; MDb.V_survived; MDb.V_unknown; MDb.V_unknown_no_contract; MDb.V_error;
    MDb.V_pending ]

(** The three shapes the campaign tables are read through. Declared, not inferred: the
    pair (row type, projection) is what [Arch_db.rows] checks the SELECT against, so a
    column that changes type stops the query rather than decoding into something plausible. *)
module Shape = struct
  open Arch_db

  let s = Rows.s
  let i = Rows.i

  (* id, completed_at, engine, engine_path, granularity *)
  let campaign = Ty.(t2 (t3 i s s) (t2 s s))

  let campaign_cells ((id, completed, engine), (path, gran)) =
    [ int_cell id; text_cell completed; text_cell engine; text_cell path; text_cell gran ]

  (* engine_status, selection_provenance, file_path, line, function_name, engine_mutant_id *)
  let run = Ty.(t2 (t3 s s s) (t3 i s s))

  let run_cells ((status, prov, file), (line, fn, eid)) =
    [ text_cell status; text_cell prov; text_cell file; int_cell line; text_cell fn;
      text_cell eid ]

  (* file_path, line, function_name *)
  let site = Ty.(t3 s i s)
  let site_cells (file, line, fn) = [ text_cell file; int_cell line; text_cell fn ]
end

(** Read one campaign's run rows into findings.

    Every finding's [outcome] is built from the status and the provenance of {b the same
    row}, in one place, so there is no list of provenances for a later loop to index into.
    FR-033's failure mode needs such a list to exist; this shape does not create one. *)
let findings_of_runs (t : Arch_db.t) campaign_id =
  List.filter_map
    (fun row ->
      match row with
      | [ st_cell; prov_cell; file_cell; line_cell; fn_cell; eid_cell ] ->
          let raw_status = cell_text st_cell and raw_prov = cell_text prov_cell in
          let status =
            match Option.map MDb.status_of_string raw_status with
            | Some (Some s) -> s
            | Some None | None ->
                die
                  (Printf.sprintf
                     "arch-mutants: campaign %d holds engine_status %S, which is not one of \
                      KILLED|SURVIVED|TIMEOUT|ERROR. Refusing to guess: a status added to \
                      the CHECK and dropped here would shrink the answer with no error at \
                      all."
                     campaign_id
                     (Option.value ~default:"NULL" raw_status))
          in
          let provenance =
            match Option.map MDb.provenance_of_string raw_prov with
            | Some (Some p) -> p
            | Some None | None ->
                die
                  (Printf.sprintf
                     "arch-mutants: campaign %d holds selection_provenance %S, which is not \
                      one of proved_superset|top_bounded|no_contract. Refusing to guess: \
                      defaulting it to proved_superset would turn a survivor into an \
                      accusation against a test that may never have run."
                     campaign_id
                     (Option.value ~default:"NULL" raw_prov))
          in
          let outcome = { MDb.o_status = status; o_provenance = provenance } in
          Some
            { f_file = Option.value ~default:"(unknown file)" (cell_text file_cell);
              f_line = Option.value ~default:0 (cell_int line_cell);
              f_fn = cell_text fn_cell;
              f_engine_id = cell_text eid_cell;
              f_outcome = Some outcome;
              f_verdict = MDb.published_verdict outcome }
      | _ -> None)
    (Arch_db.rows t ~params_ty:Arch_db.Ty.int ~shape:Shape.run ~to_cells:Shape.run_cells
       "SELECT r.engine_status, r.selection_provenance, m.file_path, m.line, \
        m.function_name, r.engine_mutant_id FROM mutant_runs r JOIN mutants m ON m.id = \
        r.mutant_id WHERE r.campaign_id = ? ORDER BY r.id"
       campaign_id)

(** The PENDING findings: mutant sites with no run row in this campaign.

    Only ever consulted for a campaign whose [completed_at] is NULL. In a completed
    campaign the same absence means something else entirely — a site catalogued by some
    other campaign — and calling that PENDING would invent work that was never scheduled. *)
let findings_of_pending (t : Arch_db.t) campaign_id =
  List.filter_map
    (fun row ->
      match row with
      | [ file_cell; line_cell; fn_cell ] ->
          Some
            { f_file = Option.value ~default:"(unknown file)" (cell_text file_cell);
              f_line = Option.value ~default:0 (cell_int line_cell);
              f_fn = cell_text fn_cell;
              f_engine_id = None;
              (* No run row, so no status and no provenance. FR-033: the honest answer
                 where no link exists is the absence, never the first one available. *)
              f_outcome = None;
              f_verdict = MDb.V_pending }
      | _ -> None)
    (Arch_db.rows t ~params_ty:Arch_db.Ty.int ~shape:Shape.site ~to_cells:Shape.site_cells
       "SELECT m.file_path, m.line, m.function_name FROM mutants m WHERE NOT EXISTS \
        (SELECT 1 FROM mutant_runs r WHERE r.campaign_id = ? AND r.mutant_id = m.id) \
        ORDER BY m.id"
       campaign_id)

let finding_json f =
  `Assoc
    [ ("file", `String f.f_file); ("line", `Int f.f_line);
      ("function", match f.f_fn with Some x -> `String x | None -> `Null);
      ("engine_mutant_id", match f.f_engine_id with Some x -> `String x | None -> `Null);
      (* FR-013: engine_status NEVER travels without selection_provenance. Both are NULL
         together for a PENDING finding, which is the one case where there is no run row
         to take either from. *)
      ("engine_status",
       match f.f_outcome with
       | Some o -> `String (MDb.status_to_string o.MDb.o_status)
       | None -> `Null);
      ("selection_provenance",
       match f.f_outcome with
       | Some o -> `String (MDb.provenance_to_string o.MDb.o_provenance)
       | None -> `Null);
      ("published_verdict", `String (MDb.verdict_to_string f.f_verdict));
      ("verdict_basis",
       match f.f_outcome with
       | Some o -> `String (MDb.verdict_basis o)
       | None ->
           `String
             "no run row in a campaign whose completion is NULL: this mutant was never \
              attempted, which is not the same as having survived") ]

let count_of v findings = List.length (List.filter (fun f -> f.f_verdict = v) findings)

let verdict_cmd (t : Arch_db.t) ~only_campaign ~fmt ~maxlist =
  if not (Arch_db.has_table t "mutant_runs") then (
    Printf.eprintf
      "arch-mutants: %s carries no `mutant_runs` table, so no campaign has ever been \
       executed against it. REFUSED (exit 3) rather than reported as an empty verdict \
       list: 'nothing ran' and 'ran and found nothing' are different facts. Run \
       `arch-mutants run` first.\n"
      t.path ;
    exit 3) ;
  let campaigns =
    Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Shape.campaign
      ~to_cells:Shape.campaign_cells
      (Printf.sprintf
         "SELECT id, completed_at, engine, engine_path, granularity FROM mutant_campaigns \
          %s ORDER BY id"
         (match only_campaign with Some n -> Printf.sprintf "WHERE id = %d" n | None -> ""))
      ()
  in
  let campaigns =
    List.filter_map
      (fun row ->
        match row with
        | [ id_cell; completed_cell; engine_cell; path_cell; gran_cell ] ->
            Option.map
              (fun id ->
                ( id,
                  cell_text completed_cell,
                  Option.value ~default:"(unnamed)" (cell_text engine_cell),
                  Option.value ~default:"(unresolved)" (cell_text path_cell),
                  Option.value ~default:"(unrecorded)" (cell_text gran_cell) ))
              (cell_int id_cell)
        | _ -> None)
      campaigns
  in
  if campaigns = [] then (
    Printf.eprintf
      "arch-mutants: no campaign %sto report on. What would have made this non-zero: one \
       `arch-mutants run` that got as far as resolving its engine.\n"
      (match only_campaign with Some n -> Printf.sprintf "with id %d " n | None -> "") ;
    exit 3) ;
  (* FR-034 / AC-28. PENDING is the absence of a `mutant_runs` row over a universe of
     mutant sites — and NO TABLE records which sites a given campaign catalogued. The only
     universe this schema can derive is the global `mutants` table, which is the whole
     site set of the database rather than of the campaign.

     On a database holding one campaign those two sets coincide, so the derivation is
     exactly right. On a database holding two campaigns over DIFFERENT mutant sets it is
     not merely imprecise: an open campaign reports the OTHER campaign's sites as PENDING,
     which is a wrong answer rather than a missing one, and it looks identical to a correct
     one to every reader.

     So the surface refuses — exit 3, refused rather than failed — instead of answering a
     question it cannot answer correctly. The refusal is deliberately narrow, because a
     refusal that fires where the answer IS derivable is its own kind of wrong:

       * open campaign requested (completed_at IS NULL) — a completed campaign has no
         pending set to get wrong, so it is answered normally;
       * AND the database holds more than one campaign — with one campaign the global site
         table IS that campaign's catalogue, so it is answered normally.

     Closing this properly needs a `campaign_id` on a catalogue table, or a
     `mutant_campaign_sites` join. That is a schema change and therefore a version bump,
     which this slice does not own. Until then, refusing is the honest surface. *)
  let campaigns_in_db = Arch_db.count t "SELECT count(*) FROM mutant_campaigns" in
  let sites_in_db = Arch_db.count t "SELECT count(*) FROM mutants" in
  let open_requested =
    List.filter_map
      (fun (id, completed, _, _, _) -> if completed = None then Some id else None)
      campaigns
  in
  if campaigns_in_db > 1 && open_requested <> [] then (
    Printf.eprintf
      "arch-mutants: REFUSED (exit 3) — the verdict surface cannot scope the PENDING set \
       of an open campaign in this database.\n\
      \  asked_for=%s\n\
      \  campaigns_in_db=%d\n\
      \  open_campaigns_requested=%d (ids: %s)\n\
      \  mutant_sites_in_db=%d\n\
       PENDING is derived as \"a catalogued mutant site with no `mutant_runs` row in this \
       campaign\", but no table records which sites a campaign catalogued, so the only \
       derivable universe is the %d site(s) of the whole database. With %d campaigns over \
       possibly different mutant sets, that universe would report another campaign's sites \
       as this campaign's PENDING — a wrong answer, not a missing one. Refusing rather \
       than answering it.\n\
       What would make this answerable: a catalogue link in the schema (a `campaign_id` on \
       a catalogue table, or a `mutant_campaign_sites` join), which is a schema change and \
       a version bump. Meanwhile: `--campaign N` on a COMPLETED campaign is reported \
       normally, since a completed campaign has no pending set.\n"
      (match only_campaign with
      | Some n -> Printf.sprintf "campaign %d" n
      | None -> "every campaign (no --campaign given)")
      campaigns_in_db
      (List.length open_requested)
      (String.concat "," (List.map string_of_int open_requested))
      sites_in_db sites_in_db campaigns_in_db ;
    exit 3) ;
  let per_campaign =
    List.map
      (fun (id, completed, engine, engine_path, granularity) ->
        let runs = findings_of_runs t id in
        (* PENDING is the absence of a run row, and ONLY inside an open campaign. *)
        let pending = if completed = None then findings_of_pending t id else [] in
        (id, completed, engine, engine_path, granularity, runs @ pending))
      campaigns
  in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("db", `String t.path);
             ("campaigns",
              `List
                (List.map
                   (fun (id, completed, engine, engine_path, granularity, findings) ->
                     `Assoc
                       [ ("campaign_id", `Int id); ("engine", `String engine);
                         ("engine_path", `String engine_path);
                         ("granularity", `String granularity);
                         ("completed_at", match completed with Some c -> `String c | None -> `Null);
                         ("partial", `Bool (completed = None));
                         ("verdict_counts",
                          `Assoc
                            (List.map
                               (fun v -> (MDb.verdict_to_string v, `Int (count_of v findings)))
                               all_verdicts));
                         ("findings", `List (List.map finding_json (take maxlist findings)));
                         ("findings_total", `Int (List.length findings)) ])
                   per_campaign)) ]))
  else
    List.iter
      (fun (id, completed, engine, engine_path, granularity, findings) ->
        Printf.printf "== Published verdicts for campaign %d\n" id ;
        Printf.printf "  • engine %s → %s, granularity %s\n" engine engine_path granularity ;
        (match completed with
        | Some c -> Printf.printf "  • completed at %s\n" c
        | None ->
            print_endline
              "  • PARTIAL: completion is NULL, so every catalogued mutant with no run row \
               is PENDING — never SURVIVED") ;
        List.iter
          (fun v ->
            Printf.printf "  • %-19s %d\n" (MDb.verdict_to_string v) (count_of v findings))
          all_verdicts ;
        if count_of MDb.V_survived findings = 0 then
          print_endline
            "  • 0 published SURVIVED. What would have made it non-zero: a mutant the \
             engine reported SURVIVED whose selection provenance is proved_superset — a \
             bounded selection publishes UNKNOWN instead, on purpose" ;
        print_endline "" ;
        print_endline "-- findings (verdict, then the status and provenance it was derived from)" ;
        List.iter
          (fun f ->
            Printf.printf "  • %-19s [%s / %s]  %s:%d  in %s\n"
              (MDb.verdict_to_string f.f_verdict)
              (match f.f_outcome with
              | Some o -> MDb.status_to_string o.MDb.o_status
              | None -> "no run row")
              (match f.f_outcome with
              | Some o -> MDb.provenance_to_string o.MDb.o_provenance
              | None -> "no provenance — none exists")
              f.f_file f.f_line
              (match f.f_fn with Some x -> x | None -> "(unmapped — persisted, not dropped)") ;
            Printf.printf "      %s\n"
              (match f.f_outcome with
              | Some o -> MDb.verdict_basis o
              | None ->
                  "never attempted: no run row inside a campaign whose completion is NULL"))
          (take maxlist findings) ;
        if maxlist > 0 && List.length findings > maxlist then
          Printf.printf "  … and %d more (--max-list 0 for all)\n" (List.length findings - maxlist) ;
        print_endline "")
      per_campaign

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
      "--report"; "--test-cmd"; "--diff";
      (* `verdict`'s own value-taking flag, same reason. *)
      "--campaign" ]
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
        ~diff_range:(match opt "--diff" "" with "" -> None | r -> Some r)
        ~repo:(opt "--repo" ".") ~fmt ~maxlist
  | "verdict" ->
      if fmt = "lines" then die "arch-mutants: --format lines is only meaningful for `plan`" ;
      let only_campaign =
        match opt "--campaign" "" with
        | "" -> None
        | v -> (
            match int_of_string_opt v with
            | Some n -> Some n
            | None -> die (Printf.sprintf "arch-mutants: --campaign %S is not a campaign id" v))
      in
      verdict_cmd t ~only_campaign ~fmt ~maxlist
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
