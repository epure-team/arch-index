(** arch-impact — change-impact briefing for a diff, over a sound call graph.

    {1 Approximation direction}

    BOTH closures are UNDER-approximations. Dropping ⊤ edges is what makes them computable, and a
    ⊤ edge could land anywhere — so "N functions reach the change" is a LOWER bound in both
    directions, never a bound. Anyone who reads it as a bound will under-review the change.

    Backwards, the additional callers a ⊤ edge could hide ARE enumerable: every function holding
    a ⊤ edge, plus everything that reaches one. That set is reported as MAY-REACH, separately
    from the definite set. Forwards it is not enumerable (⊤ means "anything"), so only the
    frontier itself is reported.

    On an index WITHOUT the edge-kind contract the lower bounds survive — dropping edges only
    lowers a lower bound — but the CLOSED-CONE claim does not: "no ⊤ in the forward cone,
    therefore the radius is a genuine bound" is exactly the inference a silently-dropped dynamic
    edge invalidates. That one claim is withheld. *)

open Arch_tools
module SS = Arch_graph.SS
module SM = Arch_graph.SM

let usage =
  {|arch-impact — change-impact briefing for a diff, over a sound call graph.

Usage: arch-impact <db> [--diff <git-range>] [--files a,b,...] [--repo DIR]
                   [--format text|md|json] [--max-list N] [--fail-on-new-findings]|}

let die msg = prerr_endline msg ; exit 2

(* A test root, guessed from names and paths.

   The patterns are ANCHORED, not substrings. A loose `contains "test"` matches
   "bufio.(Writer).WriteString" — "wri(test)ring" — and a Go stdlib index is full of such names,
   so the guess silently reported dozens of stdlib functions as tests. Matching:
     "test" at the start of the path or right after a '/'
     "spec" likewise, when followed by '/' or '_'
     "_test." or "_test_" anywhere (x_test.go, a_test_b)
     a function NAME starting with "test" *)
let is_test name path =
  let low = String.lowercase_ascii in
  let p = low (Option.value ~default:"" path) in
  let at i pat =
    i + String.length pat <= String.length p && String.sub p i (String.length pat) = pat
  in
  let boundary i = i = 0 || p.[i - 1] = '/' in
  let rec scan i =
    i < String.length p
    && ((boundary i && at i "test")
       || (boundary i && at i "spec"
          && i + 4 < String.length p
          && (p.[i + 4] = '/' || p.[i + 4] = '_'))
       || at i "_test." || at i "_test_"
       || scan (i + 1))
  in
  (p <> "" && scan 0)
  || (String.length name >= 4 && String.sub (low name) 0 4 = "test")

let take n l = if n <= 0 then l else List.filteri (fun i _ -> i < n) l

(* [pre] is the prefix the CALLER will not add, because the entries already carry it. The
   touched-functions list formats its own bullets, so the overflow marker must carry one too;
   every other list is printed with a uniform indent applied afterwards. *)
let cap ?(pre = "") n l =
  let total = List.length l in
  if n > 0 && total > n then take n l @ [ Printf.sprintf "%s… and %d more" pre (total - n) ] else l

(* ------------------------------------------------------------------ *)

type touched = { name : string; file : string; exported : bool; how : string }

let analyse (t : Arch_db.t) (g : Arch_graph.t) changed repo =
  let nodes = Arch_graph.nodes g in
  let resolver =
    Arch_path.make ~repo
      (List.filter_map (fun (n : Arch_graph.node) -> n.file) nodes)
  in
  let by_file = Hashtbl.create 64 in
  List.iter
    (fun (n : Arch_graph.node) ->
      match n.file with
      | Some f -> Hashtbl.replace by_file f (n :: Option.value ~default:[] (Hashtbl.find_opt by_file f))
      | None -> ())
    nodes ;
  let touched = Hashtbl.create 64 in
  let unmatched = ref [] and file_granular = ref [] in
  Arch_diff.SM.iter
    (fun diff_path lines ->
      let dbs = Arch_path.resolve resolver diff_path in
      if Arch_path.SS.is_empty dbs then unmatched := diff_path :: !unmatched
      else
        Arch_path.SS.iter
          (fun db_path ->
            let entries = Option.value ~default:[] (Hashtbl.find_opt by_file db_path) in
            let spanned =
              List.filter (fun (n : Arch_graph.node) -> n.line_start <> None && n.line_end <> None)
                entries
            in
            (* Three distinct reasons to fall back to whole-file granularity, kept distinct
               because they call for different actions from the reader. *)
            (* `--files` asks for the WHOLE file, so it takes the file branch even though its
               line set is not empty — every line is in it. *)
            if spanned = [] || lines = Arch_diff.Whole || Arch_diff.is_empty lines then (
              let how =
                if lines = Arch_diff.Whole then "file (--files: whole file requested)"
                else if spanned = [] then "file (no line spans in index)"
                else "file (deletion-only diff)"
              in
              if spanned = [] && entries <> [] then file_granular := diff_path :: !file_granular ;
              List.iter
                (fun (n : Arch_graph.node) ->
                  if not (Hashtbl.mem touched n.key) then
                    Hashtbl.replace touched n.key
                      { name = n.name; file = diff_path; exported = n.exported; how })
                entries)
            else
              List.iter
                (fun (n : Arch_graph.node) ->
                  match (n.line_start, n.line_end) with
                  | Some a, Some b ->
                      let hit = ref false in
                      for i = a to b do
                        if Arch_diff.mem lines i then hit := true
                      done ;
                      if !hit then
                        Hashtbl.replace touched n.key
                          { name = n.name; file = diff_path; exported = n.exported; how = "line" }
                  | _ -> ())
                spanned)
          dbs)
    changed ;
  ignore t ;
  (touched, List.sort_uniq compare !unmatched, List.sort_uniq compare !file_granular)

let findings (t : Arch_db.t) changed repo =
  let decisions =
    if not (Arch_db.nonempty t "decisions") then []
    else
      let rows =
        Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.ub_shape
          ~to_cells:Arch_db.Rows.ub_cells
          "SELECT file_path, line, form, verdict, COALESCE(snippet,''), '' FROM decisions WHERE \
           verdict NOT IN ('OK','HIGH_ARITY')"
          ()
      in
      let paths = List.filter_map (fun r -> match r with Arch_db.Text p :: _ -> Some p | _ -> None) rows in
      let resolver = Arch_path.make ~repo paths in
      let want = Hashtbl.create 16 in
      Arch_diff.SM.iter
        (fun dp lines ->
          Arch_path.SS.iter
            (fun db ->
              (* UNION, not replace: two diff paths can resolve to one indexed file (suffix
                 matching is ambiguous by construction), and overwriting dropped the earlier
                 path's lines — findings on them then vanished from the gate. *)
              let merged =
                match Hashtbl.find_opt want db with
                | Some prev -> Arch_diff.union prev lines
                | None -> lines
              in
              Hashtbl.replace want db merged)
            (Arch_path.resolve resolver dp))
        changed ;
      List.filter_map
        (fun r ->
          match r with
          | [ Arch_db.Text path; Arch_db.Int line; form; verdict; snippet; _ ] -> (
              match Hashtbl.find_opt want path with
              | Some lines when Arch_diff.mem lines line ->
                  Some (path, line, Arch_db.string_of_cell form, Arch_db.string_of_cell verdict,
                        Arch_db.string_of_cell snippet)
              | _ -> None)
          | _ -> None)
        rows
  in
  decisions

(* ------------------------------------------------------------------ *)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function a :: v :: _ when a = name -> v | _ :: tl -> go tl | [] -> default in
    go args
  in
  let has_flag f = List.mem f args in
  let positional =
    List.filteri
      (fun i a ->
        String.length a < 2
        || String.sub a 0 2 <> "--"
           && (i = 0 || not (List.mem (List.nth args (i - 1)) [ "--diff"; "--files"; "--repo"; "--format"; "--max-list" ])))
      args
  in
  let db_path = match positional with d :: _ -> d | [] -> (prerr_endline usage ; exit 2) in
  let repo = opt "--repo" "." in
  let fmt = opt "--format" "text" in
  let maxlist = match int_of_string_opt (opt "--max-list" "20") with Some n -> n | None -> 20 in
  let t =
    try Arch_db.open_ro db_path
    with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-impact: " ^ m)
  in
  let files = opt "--files" "" in
  let changed =
    if files <> "" then Arch_diff.of_files (String.split_on_char ',' files)
    else
      match Arch_diff.changed_lines ~repo ~range:(opt "--diff" "HEAD~1..HEAD") with
      | Ok c -> c
      | Error e -> die ("arch-impact: " ^ e)
  in
  if Arch_diff.SM.is_empty changed then
    prerr_endline "arch-impact: the diff is empty — nothing to brief" ;
  let g = Arch_graph.load t in
  let with_span =
    List.length
      (List.filter (fun (n : Arch_graph.node) -> n.line_start <> None) (Arch_graph.nodes g))
  in
  if with_span = 0 && files = "" && Arch_graph.nodes g <> [] then
    prerr_endline
      "arch-impact: WARNING — no function in this index has a line span, so every diff can only \
       be mapped at FILE granularity. Rebuild with a producer that emits line_start/line_end." ;
  let touched, unmatched, file_granular = analyse t g changed repo in
  let seeds = Hashtbl.fold (fun k _ acc -> SS.add k acc) touched SS.empty in
  let upstream = if SS.is_empty seeds then SS.empty else Arch_graph.closure seeds g.bwd in
  let downstream = if SS.is_empty seeds then SS.empty else Arch_graph.closure seeds g.fwd in
  (* The ⊤-hidden upstream. A function holding a MAY_TOP edge "may call anything", which includes
     the changed code — so it, and everything that reaches it, MAY reach the change even though
     no resolved path says so. Enumerating this is the difference between an honest lower bound
     and a number that quietly pretends to be complete. *)
  let top_holders = SM.fold (fun k _ acc -> if SS.mem k seeds then acc else SS.add k acc) g.tops SS.empty in
  let may_upstream =
    if SS.is_empty seeds then SS.empty
    else SS.diff (SS.diff (SS.union top_holders (Arch_graph.closure top_holders g.bwd)) upstream) seeds
  in
  let exported k = match SM.find_opt k g.nodes with Some (n : Arch_graph.node) -> n.exported | None -> false in
  let is_test_key k =
    match SM.find_opt k g.nodes with Some (n : Arch_graph.node) -> is_test n.name n.file | None -> false
  in
  let lbl k = Arch_graph.label g k in
  let affected = SS.filter exported (SS.union upstream seeds) |> SS.elements |> List.map lbl |> List.sort compare in
  let may_affected = SS.filter exported may_upstream |> SS.elements |> List.map lbl |> List.sort compare in
  let tests = SS.filter is_test_key (SS.union upstream seeds) |> SS.elements |> List.map lbl |> List.sort compare in
  let may_tests = SS.filter is_test_key may_upstream |> SS.elements |> List.map lbl |> List.sort compare in
  let frontier =
    SS.fold (fun k acc -> match SM.find_opt k g.tops with Some n -> (lbl k, n) :: acc | None -> acc)
      (SS.union downstream seeds) []
    |> List.sort (fun (a, x) (b, y) -> if x = y then compare a b else compare y x)
  in
  (* Not [t.contract <> None && t.kinded]: that weaker check is satisfied by a malformed index
     (flag set, but a real edge has kind=NULL) that Arch_db.contract_ok correctly refuses — a
     NULL kind is invisible to SQL's 3-valued logic and would silently under-count the closure.
     Sharing this with arch-rules's `contract_ok` means the two tools can never disagree about
     the same index. *)
  let sound = Arch_db.contract_ok t "impact" in
  let decs = findings t changed repo in
  let touched_list =
    Hashtbl.fold (fun _ v acc -> v :: acc) touched []
    |> List.sort (fun a b -> compare a.name b.name)
  in
  (* Mirrors the --fail-on-new-findings decision made below (line ~443) so the JSON `verdict`
     and the exit code always agree — a consumer with only one of the two can still conclude. *)
  let decision_analysis_available = Arch_db.nonempty t "decisions" in
  let new_findings = List.length decs in
  let verdict =
    if not (has_flag "--fail-on-new-findings") then `Pass
    else if not decision_analysis_available then `Refused
    else if new_findings > 0 then `Fail
    else `Pass
  in
  let verdict_str = function `Pass -> "pass" | `Fail -> "fail" | `Refused -> "refused" in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("computed", `Bool true);
             ("contract_ok", `Bool sound);
             ("verdict", `String (verdict_str verdict));
             ("new_findings", `Int new_findings);
             ("db", `String db_path); ("sound_reachability", `Bool sound);
             ("touched",
              `List
                (List.map
                   (fun x ->
                     `Assoc
                       [ ("name", `String x.name); ("file", `String x.file);
                         ("exported", `Bool x.exported); ("how", `String x.how) ])
                   touched_list));
             ("files_unmatched", `List (List.map (fun f -> `String f) unmatched));
             ("files_file_granular", `List (List.map (fun f -> `String f) file_granular));
             ("affected_exported", `List (List.map (fun s -> `String s) affected));
             ("may_affected_exported", `List (List.map (fun s -> `String s) may_affected));
             ("exported_upstream_count", `Int (SS.cardinal (SS.filter exported upstream)));
             ("upstream_count", `Int (SS.cardinal upstream));
             ("may_upstream_count", `Int (SS.cardinal may_upstream));
             ("downstream_count", `Int (SS.cardinal downstream));
             ("top_frontier",
              `List (List.map (fun (n, c) -> `Assoc [ ("function", `String n); ("escapes", `Int c) ]) frontier));
             ("tests_reaching", `List (List.map (fun s -> `String s) tests));
             ("may_tests_reaching", `List (List.map (fun s -> `String s) may_tests));
             ("decision_analysis_available", `Bool decision_analysis_available);
             ("findings",
              `Assoc
                [ ("computed", `Bool decision_analysis_available);
                  ("reason",
                   if decision_analysis_available then `Null
                   else `String "no decision analysis in this index — absence of data, not absence of findings");
                  ("decisions",
                   `List
                     (List.map
                        (fun (p, l, f, v, s) ->
                          `Assoc
                            [ ("file", `String p); ("line", `Int l); ("form", `String f);
                              ("verdict", `String v); ("snippet", `String s) ])
                        decs));
                  (* Reserved for a future finding kind; always empty today — no producer emits
                     dead-site data yet. Documented in docs/change-impact.md so a consumer does
                     not read the empty list as "computed, zero found". *)
                  ("dead_sites", `List []) ]) ]))
  else (
    let md = fmt = "md" in
    let h1 = if md then "# " else "== " and h2 = if md then "## " else "-- " in
    let b = if md then "- " else "  • " in
    print_endline (h1 ^ "Change impact") ;
    print_endline (b ^ "index: " ^ (if md then "`" ^ db_path ^ "`" else db_path)) ;
    if not sound then
      print_endline
        (b
        ^ "**this index is NOT ⊤-marked** (no edge-kind contract). The DEFINITE sets below \
           remain valid lower bounds — a dropped edge only shrinks them — but the ⊤ frontier \
           cannot be trusted to be complete, so no closed-cone claim is made and the MAY-reach \
           set may be understated.") ;
    print_endline "" ;
    print_endline (Printf.sprintf "%sTouched functions (%d)" h2 (List.length touched_list)) ;
    if touched_list = [] then
      print_endline
        (b
        ^ "none — the diff touches no indexed function (config, docs, generated code, or a file \
           outside the index)") ;
    List.iter print_endline
      (cap ~pre:b maxlist
         (List.map
            (fun x ->
              Printf.sprintf "%s%s%s — %s%s" b x.name
                (if x.exported then " [exported]" else "")
                x.file
                (if x.how = "line" then "" else "  (matched by " ^ x.how ^ ")"))
            touched_list)) ;
    if file_granular <> [] then (
      print_endline
        (Printf.sprintf
           "%s%d file(s) have no line spans in the index, so EVERY function in them is treated as \
            touched. Rebuild with a producer that emits line_start/line_end to narrow this:"
           b (List.length file_granular)) ;
      List.iter (fun f -> print_endline ("    " ^ f)) (cap maxlist file_granular)) ;
    if unmatched <> [] then (
      print_endline
        (Printf.sprintf "%s%d changed file(s) are NOT in the index — impact for them is UNKNOWN, not zero:"
           b (List.length unmatched)) ;
      List.iter (fun f -> print_endline ("    " ^ f)) (cap maxlist unmatched)) ;
    print_endline "" ;
    print_endline (h2 ^ "Who is affected (reverse reachability)") ;
    print_endline
      (Printf.sprintf
         "%s%d function(s) DEFINITELY reach the change (%d exported), over MUST ∪ MAY_ENUMERATED. \
          This is a LOWER bound — ⊤ edges are dropped to make it computable."
         b (SS.cardinal upstream) (SS.cardinal (SS.filter exported upstream))) ;
    print_endline
      (Printf.sprintf
         "%s%d exported function(s) affected (definite upstream, plus exported functions changed \
          directly):"
         b (List.length affected)) ;
    List.iter (fun n -> print_endline (if md then "  - " ^ n else "    " ^ n)) (cap maxlist affected) ;
    if SS.cardinal may_upstream > 0 then (
      print_endline
        (Printf.sprintf
           "%splus %d function(s) that MAY reach it through an unresolvable (⊤) edge, of which %d \
            are exported:"
           b (SS.cardinal may_upstream) (List.length may_affected)) ;
      List.iter (fun n -> print_endline (if md then "  - " ^ n else "    " ^ n)) (cap maxlist may_affected)) ;
    print_endline "" ;
    print_endline (h2 ^ "Blast radius (forward reachability)") ;
    print_endline
      (Printf.sprintf "%sthe changed code definitely reaches %d function(s) (also a lower bound)" b
         (SS.cardinal downstream)) ;
    if frontier <> [] then (
      print_endline
        (Printf.sprintf
           "%s⊤ FRONTIER — %d function(s) in that cone hold an unresolvable edge, so the radius \
            above is a LOWER BOUND, not a bound:"
           b (List.length frontier)) ;
      List.iter
        (fun s -> print_endline ("    " ^ s))
        (cap maxlist (List.map (fun (n, c) -> Printf.sprintf "%s  (%d escaping edge(s))" n c) frontier)))
    else if sound then
      print_endline
        (b ^ "⊤ frontier: none — the forward cone is CLOSED, so the radius above really is a \
              bound, not just a lower bound")
    else
      print_endline
        (b
        ^ "⊤ frontier: none found — but this index is not ⊤-marked, so that is NOT evidence the \
           cone is closed: an unresolvable edge would have been dropped silently rather than \
           marked. Treat the radius as a lower bound.") ;
    print_endline "" ;
    print_endline (h2 ^ "Tests reaching the change") ;
    if tests <> [] then (
      print_endline (Printf.sprintf "%s%d test function(s) definitely reach it:" b (List.length tests)) ;
      List.iter (fun n -> print_endline ("    " ^ n)) (cap maxlist tests))
    else
      print_endline
        (b
        ^ "no test definitely reaches the change — either it is untested, or the tests are not in \
           this index (check what was indexed before concluding it is untested)") ;
    if may_tests <> [] then (
      print_endline (Printf.sprintf "%s%d more MAY reach it via a ⊤ edge:" b (List.length may_tests)) ;
      List.iter (fun n -> print_endline ("    " ^ n)) (cap maxlist may_tests)) ;
    print_endline "" ;
    print_endline (h2 ^ "Effects crossed") ;
    (if not (Arch_db.nonempty t "function_effects") then
       print_endline
         (b ^ "not available on this index (no effects tables) — this is 'not computed', not 'no \
               effects'")
     else
       let cone = SS.union downstream seeds in
       let names =
         SS.fold
           (fun k acc ->
             match SM.find_opt k g.nodes with Some (n : Arch_graph.node) -> n.name :: acc | None -> acc)
           cone []
       in
       let json = Yojson.Safe.to_string (`List (List.map (fun n -> `String n) names)) in
       let hits =
         Arch_db.rows t ~params_ty:Arch_db.Ty.string ~shape:Arch_db.Rows.t2'
           ~to_cells:Arch_db.Rows.c2
           "SELECT DISTINCT effect_kind, value_kind FROM function_effects WHERE function_name IN \
            (SELECT value FROM json_each(?))"
           json
       in
       if hits = [] then print_endline (b ^ "none in the forward cone")
       else
         List.iter print_endline
           (cap maxlist
              (List.map
                 (fun r -> b ^ String.concat " / " (List.map Arch_db.string_of_cell r))
                 hits))) ;
    print_endline "" ;
    print_endline (h2 ^ "Findings introduced by this diff") ;
    if not (Arch_db.nonempty t "decisions") then
      print_endline (b ^ "decision analysis not present in this index — not computed")
    else if decs = [] then print_endline (b ^ "none")
    else
      List.iter print_endline
        (cap maxlist
           (List.map (fun (p, l, f, v, s) -> Printf.sprintf "%s%s at %s:%d (%s) %s" b v p l f s) decs))) ;
  if has_flag "--fail-on-new-findings" then
    if not (Arch_db.nonempty t "decisions") then (
      (* A gate whose input was never computed must not report "clean". The text already said
         "not computed"; the EXIT CODE is the only thing CI reads, and it was saying "no
         findings". *)
      prerr_endline
        "arch-impact: REFUSED — --fail-on-new-findings was requested but this index carries no \
         decision analysis, so 'no findings' would be an absence of data, not a result. Run \
         decision-lint --db against the index first." ;
      exit 3)
    else if decs <> [] then (
      Printf.eprintf "arch-impact: FAIL — %d finding(s) on lines this diff touches\n"
        (List.length decs) ;
      exit 1)
