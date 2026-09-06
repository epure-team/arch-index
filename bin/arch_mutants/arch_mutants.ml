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

(* Aliased here rather than beside its first use: `selection_provenance` and
   `executed_is_superset` below are the shared rules two commands call, and both need it. *)
module MDb = Arch_mutant_db

let usage =
  {|arch-mutants — mutation testing targeted by the call graph.

Usage: arch-mutants plan   <db> [--tests <selector>] [--format text|json|lines] [--max-list N]
       arch-mutants report <db> <mutant-report> [--from generic|mutaml] [--tests <selector>]
                                 [--repo DIR] [--format text|json]
                                 [--fail-on-survivors] [--fail-on-errored]
       arch-mutants run    <db> --plan <plan.json> --engine <cmd> --test-cmd <cmd>
                                 --catalogue <file>
                                 [--tests <selector>] [--profile <name>] [--report <file>]
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

(** A REFUSAL, distinct from [die]'s error.

    THE EXIT-CODE CONTRACT, stated by KIND and not by the one FR that first needed it. The
    docstring here used to read "exit 1 is FR-030's code", which was narrower than the code
    it described the day it was written and grew more so: the file already exited 1 for a
    join it could not disambiguate, which is not FR-030 at all. A contract stated once and
    contradicted elsewhere in the same file is not a contract a caller can rely on.

      0  the campaign ran and its record is consistent with what it published;
      1  a REFUSAL: the request was well-formed and understood, and the tool declined to act
         because acting would have produced a plausible-looking answer that was wrong. Every
         site that exits 1 says which refusal it is, in words, on stderr:
           * FR-030, the tree boundary — a wrapper or an arch-impact resolved from an
             ENCLOSING checkout, so every mutant would survive against an unmutated binary;
           * a catalogue offering one site key to two mutants (two verdicts, one row);
           * a report entry that matches two catalogued sites indistinguishably;
           * a campaign whose persisted rows do not account for its attempts.
      2  a malformed request or an unusable environment: nothing was attempted;
      3  a CALLEE refused to answer us (FR-032) — neither a failure nor an empty result.

    The three are kept apart so a caller can tell them apart without parsing prose. *)
let refuse msg = prerr_endline msg ; exit 1
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

(** THE selection-provenance rule, in ONE place.

    It was a three-arm decision written out twice, byte-identical, at the head of [report]
    and again at the head of [run_campaign] — while [report]'s own docstring claimed the
    provenance came from the shared bindings "never from a second copy of the rule". A
    widened signature bought a shared INGREDIENT ([cone_escapes]); it did not buy a shared
    RULE, and a duplicated call site is the exact class this campaign exists to detect.

    [cone_escapes] is taken as a parameter rather than recomputed here so the ⊤-edge
    measurement stays the single binding [plan] and [run] already share. *)
let selection_provenance ~sound ~escapes =
  if not sound then MDb.No_contract
  else if escapes <> [] then MDb.Top_bounded
  else MDb.Proved_superset

(** Test-set INCLUSION, not cardinality.

    FR-003 forbids invoking the engine with a SUBSET of the intended set "under any
    circumstances", and the only relation computed anywhere was
    [List.length executed > List.length intended] — which is satisfied by an executed set of
    equal or greater size with a member SUBSTITUTED, the precise violation FR-003 names.
    [superset] answers the question FR-003 asks; [missing] names the members that make the
    answer no, because a boolean cannot be acted on. *)
let missing_from_executed ~intended ~executed =
  let have = List.fold_left (fun a t -> SS.add t a) SS.empty executed in
  List.sort_uniq compare (List.filter (fun t -> not (SS.mem t have)) intended)

let executed_is_superset ~intended ~executed =
  missing_from_executed ~intended ~executed = []

(** WIDENED: a proper superset. This is what the report's `executed_superset` key has always
    meant — the profile's granularity made the executed set bigger than the reaching set —
    and it is a different question from FR-003's, which is whether the executed set CONTAINS
    the intended one at all. Both are computed from inclusion now; the old
    [List.length executed > List.length intended] answered neither, since an equal-sized set
    with a member substituted satisfies it while violating FR-003. *)
let executed_is_widened ~intended ~executed =
  executed_is_superset ~intended ~executed
  && List.length (List.sort_uniq compare executed) > List.length (List.sort_uniq compare intended)

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

(* ------------------------------------------------------------------ *)
(* THE WRAPPER'S REFUSAL — FR-031.                                     *)
(*                                                                    *)
(* `scripts/mutaml-wrapper.sh` exits 99, and only 99, when it cannot   *)
(* do its job: MUTAML_MUTANT unset, a mutant the driver never          *)
(* catalogued, an unset or unreadable selection file. It needs a code  *)
(* of its own because mutaml persists the RAW exit code rather than    *)
(* the label it prints — src/runner/runner.ml:109-110 saves            *)
(* `{ status = ret; mutant }` over a `status : int`                    *)
(* (src/common/mutaml_common.ml:74) — and [load_mutaml] below reads 0  *)
(* as SURVIVED, 124 as TIMEOUT and EVERY OTHER CODE as KILLED. The     *)
(* wrapper used to exit 2, so a refusal arrived as a clean KILL and a  *)
(* wholly broken selection produced a campaign of kills: the worst     *)
(* possible reading, because a kill is the one outcome this design     *)
(* treats as self-certifying proof.                                    *)
(*                                                                    *)
(* 99 collides with nothing already spoken for: 0 (passed), 124 (GNU   *)
(* timeout, which mutaml wraps every test in), 126 (not executable),   *)
(* 127 (command not found, fatal to mutaml) and 128+n (signals). The   *)
(* mapping below is EXACT — a single value, no range and no catch-all  *)
(* — so a runner that happens to exit 98 or 100 is still a kill and    *)
(* not a silent not-attempted.                                         *)
(* ------------------------------------------------------------------ *)

let refusal_exit_code = 99

(** The status string a refusal is carried as, from the report adapters through to the
    run loop. It is deliberately NOT one of the four engine statuses: a refusal is not an
    outcome the engine produced, it is the absence of an attempt. *)
let refused_status = "REFUSED"

(** Every string a report adapter can hand the run loop, classified TOTALLY (FR-031).

    Three arms and no catch-all, because each has a different consequence and folding any
    two together loses a fact the campaign is built on: a refusal was never attempted, an
    engine status is an outcome, and an unrecognised string must ABORT rather than be
    guessed — guessing inverts a verdict, and a survivor read as killed is a defect
    silently deleted. *)
type engine_class =
  | Wrapper_refused  (** the wrapper exited [refusal_exit_code]: nothing ran *)
  | Engine_status of MDb.status  (** one of the four values the schema's CHECK allows *)
  | Unrecognised_status of string  (** neither: abort at the call site *)

let classify_engine_status s =
  let up = String.uppercase_ascii (String.trim s) in
  if up = refused_status then Wrapper_refused
  else
    match MDb.status_of_string up with
    | Some st -> Engine_status st
    | None -> Unrecognised_status s

let is_wrapper_refusal s = match classify_engine_status s with
  | Wrapper_refused -> true
  | Engine_status _ | Unrecognised_status _ -> false

(* ------------------------------------------------------------------ *)
(* IDENTITY DOCTRINE (resolved, round 4).                              *)
(*                                                                    *)
(* Two documents in this branch each held a coherent and mutually      *)
(* exclusive theory of what identifies a mutant, and nothing said      *)
(* which governed. mutants-schema-migration.sql: a mutant is           *)
(* identified by where the mutation is and what it replaces, "never by *)
(* an engine-assigned id (engine ids are not trusted for identity)".   *)
(* This file: the join's FIRST key was the engine's own id. A reader   *)
(* could satisfy either and be following the project, which is why the *)
(* same defect survived three rounds of review — each round fixed the  *)
(* symptom the driver's own theory made visible.                       *)
(*                                                                    *)
(* THE MIGRATION PREVAILS. Not by seniority: an engine id is a         *)
(* COORDINATE, not an identity. It is handed out by one run of one     *)
(* engine over one catalogue and nothing in the mutant determines it — *)
(* re-run the engine, reorder the catalogue, or change the adapter and *)
(* the same mutant gets a different number. A verdict keyed on a       *)
(* position is misattributed the moment the position moves, silently   *)
(* and with no error, which is exactly what was measured here. And     *)
(* when two coherent documents contradict, the one asserting a         *)
(* PROPERTY outranks the one asserting a MECHANISM: the migration's    *)
(* claim is checkable and stays true, while this file's described how  *)
(* the code happened to join on the day it was written.                *)
(*                                                                    *)
(* So: the SITE KEY is the sole discriminant of identity. The engine   *)
(* id is DEMOTED, not deleted — it is recorded beside the run as "what *)
(* the engine called this thing", RUN-scoped, useful for reading an    *)
(* engine's output back, and never consulted by any join.              *)
(* checks/identity-doctrine-is-resolved.sh holds both halves.          *)
(* ------------------------------------------------------------------ *)

(** What an engine calls a mutant — and how much that name is worth.

    A sum type rather than a [string], because the defect that survived three reviews was a
    SYNTHESISED ordinal — the report file's own physical line counter — living in the same
    [id : string] field as a real engine-assigned name. Nothing in the type stopped it, and
    from inside a fixture whose catalogue ids are named ([m1], [m2]) the confusion is
    invisible: it only bites when the catalogue happens to be numbered 1, 2, at which point
    the ordinals collide with the ids and the join silently becomes list order. Two
    constructors make the compiler refuse the conflation that a comment could only
    discourage.

    [Report_ordinal] is deliberately an [int] and not a [string]: there is no way to hand it
    to something expecting a name without saying so. *)
type engine_name =
  | Engine_declared of string
      (** the report (or the catalogue) actually wrote this id. RUN-scoped: it names this
          mutant in THIS engine invocation's output and nowhere else. *)
  | Report_ordinal of int
      (** NOT a name. The position of the record in the report file, kept only so a
          diagnostic can point at the offending line. Never joined on, never stored. *)

(** For a diagnostic an operator reads, and for nothing else — the name says which, because
    a renderer called [to_string] is one a later author reaches for when comparing two of
    these, and that comparison is the join arm this round deleted. It says WHAT IT IS, too:
    a bare "3" in a diagnostic reads as an engine id and sends the reader looking for one in
    the engine's output. *)
let engine_name_for_display = function
  | Engine_declared s -> s
  | Report_ordinal n -> Printf.sprintf "<report record %d: the engine declared no id>" n

let declared_name = function Engine_declared s -> Some s | Report_ordinal _ -> None

(** One entry of the ENGINE's own report.

    [m_cols], [m_repl] and [m_occurrence] are carried because they ARE the site identity the
    [mutants] table's UNIQUE key is built from. They were previously dropped at the door and
    the join was then left with nothing but a basename and a line — which is how two mutants
    on one line came to have their verdicts stored against each other. They are OPTIONS
    because a report is a third party's file: absent means "this engine did not say", never
    "they are equal". *)
type mutant = {
  file : string;
  line : int;
  status : string;
  m_name : engine_name;
  mutation : string option;
  m_cols : (int * int) option;
  m_repl : string option;
  m_occurrence : int option;
}

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
                 (* The SAME refusal [load_mutaml] makes, for the same reason: the status is
                    the input to a closed four-value vocabulary, and a misspelled or
                    newly-added one read as anything at all is a defect removed from the
                    defect list with no crash and no log (FR-031). It is checked HERE, where
                    the string enters, so every downstream consumer can match totally. *)
                 (match classify_engine_status s with
                 | Wrapper_refused | Engine_status _ -> ()
                 | Unrecognised_status bad ->
                     die
                       (Printf.sprintf
                          "arch-mutants: %s:%d: mutant record has unrecognised status %S; the \
                           vocabulary is KILLED | SURVIVED | TIMEOUT | ERROR (and %s for a \
                           wrapper refusal). Refusing to guess — a mis-read status inverts the \
                           verdict, and a survivor counted as anything else is a defect \
                           silently deleted."
                          path !n bad refused_status)) ;
                 let num k = match List.assoc_opt k a with Some (`Int i) -> Some i | _ -> None in
                 acc := { file = f; line = l; status = s;
                          (* THE SPLIT. What used to be
                             [Option.value ~default:(string_of_int !n) (str "id")] wrote the
                             report's physical LINE COUNTER into the same field a real engine
                             name lives in, and the join then compared that field against the
                             catalogue's ids. A catalogue numbered 1, 2 therefore matched the
                             ordinals 1, 2 and the join became list order wearing an id's
                             clothes; the identical report against a catalogue named m1, m2
                             missed that arm and was correct. The ordinal is now a different
                             CONSTRUCTOR, so it cannot reach anything that wants a name. *)
                          m_name =
                            (match str "id" with
                            | Some id -> Engine_declared id
                            | None -> Report_ordinal !n);
                          mutation = str "mutation";
                          m_cols =
                            (match (num "col_start", num "col_end") with
                            | Some cs, Some ce -> Some (cs, ce)
                            | _ -> None);
                          m_repl = str "replacement";
                          (* Which occurrence of the anchor this is, as the MUTATION
                             SPECIFICATION states it — never a position in this file. See
                             [site]'s [s_occurrence]. *)
                          m_occurrence = num "occurrence" } :: !acc
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
                (* FR-031: exactly the wrapper's reserved code, tested by equality against
                   the one constant, never by a range. Placed BEFORE the catch-all int arm
                   because that arm is what used to swallow it into KILLED. *)
                | Some (`Int c) when c = refusal_exit_code -> refused_status
                | Some (`Int _) -> "KILLED"
                | Some (`String s) -> (
                    match String.lowercase_ascii s with
                    | "passed" -> "SURVIVED"
                    | "timeout" -> "TIMEOUT"
                    | "failed" -> "KILLED"
                    | "refused" -> refused_status
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
              let stop = match List.assoc_opt "loc_end" loc with Some (`Assoc s) -> s | _ -> [] in
              (* The SAME arithmetic [load_mutaml_catalogue] uses for the catalogue side, so
                 the two halves of the site key are computed once and cannot disagree. *)
              let col p = match (List.assoc_opt "pos_cnum" p, List.assoc_opt "pos_bol" p) with
                | Some (`Int c), Some (`Int b) -> Some (c - b)
                | _ -> None
              in
              let repl = match List.assoc_opt "repl" m with Some (`String r) -> Some r | _ -> None in
              match
                (List.assoc_opt "pos_fname" start, List.assoc_opt "pos_lnum" start)
              with
              | Some (`String f), Some (`Int l) when f <> "" ->
                  { file = f; line = l; status;
                    (* Same split as [load_generic]: mutaml's own "<file>:<n>" is a real
                       declared name; the entry's position in the array is not one, and
                       saying so is the whole of the fix. *)
                    m_name =
                      (match List.assoc_opt "number" m with
                      | Some (`Int n) ->
                          Engine_declared (Filename.remove_extension f ^ ":" ^ string_of_int n)
                      | _ -> Report_ordinal (i + 1));
                    mutation = repl;
                    m_cols = (match (col start, col stop) with Some a, Some b -> Some (a, b) | _ -> None);
                    m_repl = repl;
                    (* mutaml addresses every mutant by a column span, so it has no anchor
                       occurrence to state. NOT 0 and not 1: absent means "this engine did
                       not say", which is a different fact from "the first one". *)
                    m_occurrence = None }
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

(** [report] answers about an ENGINE'S OWN report file, with no campaign row behind it. It
    still owes the reader the same thing [run] and [verdict] owe: FR-013, never a status
    without its selection provenance, in either format.

    A backward test-closure is only a LOWER BOUND — MAY_TOP edges are never traversed — so a
    SURVIVED read off a report is a real test gap ONLY under [proved_superset]. Under
    [top_bounded] or [no_contract] the tests that would have killed it may never have run,
    and calling it a survivor accuses a test that was never given the chance. The provenance
    is therefore computed by the SAME function [run] calls, {!selection_provenance}, over the
    same two bindings ([cone_escapes] and [Arch_db.contract_ok]). That sentence was FALSE
    when it was first written: the three-arm rule was spelled out here and again in
    [run_campaign], byte for byte, and a shared ingredient is not a shared rule. *)
let report (t : Arch_db.t) (g : Arch_graph.t) mutants test_keys repo fmt maxlist =
  let _, escapes = cone_escapes g test_keys in
  let sound = Arch_db.contract_ok t "mutants" in
  let provenance = selection_provenance ~sound ~escapes in
  (* Every survivor in this report shares one selection, so they share one verdict — but it
     is DERIVED through [published_verdict] rather than spelled out here, so `report` cannot
     drift from `verdict`'s rule. *)
  let survivor_outcome = { MDb.o_status = MDb.Survived; o_provenance = provenance } in
  let survivor_verdict = MDb.published_verdict survivor_outcome in
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
  (* A wrapper refusal is not an engine error and above all not a kill: nothing was tested,
     so the mutant is counted apart and never lands in either bucket. *)
  let refused = ref 0 in
  List.iter
    (fun m ->
      (* FR-031: TOTAL over the closed vocabulary, no catch-all. The old chain ended in
         `else if st <> "SURVIVED" then incr errored`, so a misspelled or newly-added status
         was counted as an engine error — a defect removed from the defect list with no
         crash and no log. [load_generic] and [load_mutaml] both refuse an unrecognised
         status before it reaches here; the arm below is what makes that refusal
         structural rather than a convention. *)
      match classify_engine_status m.status with
      | Unrecognised_status bad ->
          die
            (Printf.sprintf
               "arch-mutants: mutant %s (%s:%d) carries status %S, which is neither one of \
                KILLED | SURVIVED | TIMEOUT | ERROR nor %s. Refusing to guess: counting it \
                as anything at all deletes a defect from the list."
               (engine_name_for_display m.m_name) m.file m.line bad refused_status)
      | Wrapper_refused -> incr refused
      | Engine_status (MDb.Killed | MDb.Timeout) -> incr killed
      | Engine_status MDb.Errored -> incr errored
      | Engine_status MDb.Survived ->
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
                       [ ("file", `String m.file); ("line", `Int m.line);
                         ("id", `String (engine_name_for_display m.m_name));
                         (* RUN-scope, stated in the payload rather than left for the reader
                            to assume: this names the mutant in ONE engine invocation's
                            output. It is not a key and nothing may join on it. *)
                         ("id_scope", `String "engine_run");
                         ("mutation", match m.mutation with Some x -> `String x | None -> `Null);
                         ("function", `String fn);
                         (* FR-013: the status this record carries is SURVIVED, so its
                            selection provenance and the verdict derived from the pair
                            travel WITH it. A reader copies one survivor object out of this
                            list; a provenance living only at the top of the document would
                            not travel with it. *)
                         ("selection_provenance",
                          `String (MDb.provenance_to_string provenance));
                         ("verdict", `String (MDb.verdict_to_string survivor_verdict));
                         ("verdict_basis", `String (MDb.verdict_basis survivor_outcome));
                         ("reaching_tests", `List (List.map (fun s -> `String s) reaching)) ])
                   survivors));
             ("selection_provenance", `String (MDb.provenance_to_string provenance));
             ("selection_caveat", `String (MDb.provenance_caveat provenance));
             ("survivors_publish_as", `String (MDb.verdict_to_string survivor_verdict));
             ("killed", `Int !killed); ("errored", `Int !errored);
             (* Never folded into `killed` or `errored`: the wrapper declined to run this
                mutant's tests at all, so no verdict of any kind was reached. *)
             ("refused_by_wrapper", `Int !refused);
             (* The WHOLE record, not just its location: a survivor that could not be mapped is
                still a defect, and dropping its id and mutation makes it unactionable. *)
             ("unmapped",
              `List
                (List.map
                   (fun m ->
                     `Assoc
                       [ ("file", `String m.file); ("line", `Int m.line);
                         ("status", `String m.status);
                         ("id", `String (engine_name_for_display m.m_name));
                         ("id_scope", `String "engine_run");
                         ("mutation", match m.mutation with Some x -> `String x | None -> `Null);
                         (* FR-013 here TOO. This record is the one a reader copies out for a
                            survivor nobody could map, and it used to carry a naked
                            `status: SURVIVED` while the document above it said survivors
                            publish as UNKNOWN — two answers to one question in one object,
                            with the naked one attached to the record. Unmapped is a fact
                            about the INDEX, never about the verdict. *)
                         ("selection_provenance",
                          `String (MDb.provenance_to_string provenance));
                         ("verdict", `String (MDb.verdict_to_string survivor_verdict));
                         ("verdict_basis", `String (MDb.verdict_basis survivor_outcome));
                         ("function", `Null);
                         ("unmapped_reason",
                          `String
                            "the index maps this file and line into no function span, so no \
                             reaching test set can be computed for it. The verdict is \
                             unaffected: it is derived from the status and the selection \
                             provenance, neither of which depends on the mapping") ])
                   unmapped));
             ("total", `Int (List.length mutants)) ]))
  else (
    print_endline "== Surviving mutants" ;
    (* FR-013 in the text format too. Printed BEFORE the counts, because the counts are what
       a reader acts on and a caveat arriving after them arrives too late. *)
    Printf.printf "  • selection provenance: %s — %s\n"
      (MDb.provenance_to_string provenance)
      (MDb.provenance_caveat provenance) ;
    (* survivors + unmapped, which is the total `--fail-on-survivors` already gates on. The
       headline used to print [List.length survivors] alone, so a report holding one
       surviving mutant read "1 mutant(s) in the report: 0 survived, 0 killed" while the
       bullet below it reported the survivor and the gate would have failed on it. The
       unmapped share is named INLINE rather than left to a later line, because the summary
       is what a reader acts on. *)
    Printf.printf "  • %d mutant(s) in the report: %d survived%s, %d killed%s\n"
      (List.length mutants)
      (List.length survivors + List.length unmapped)
      (if unmapped <> [] then
         Printf.sprintf " (%d of them unmapped to any indexed function)" (List.length unmapped)
       else "")
      !killed
      (if !errored > 0 then Printf.sprintf ", %d errored (counted neither way)" !errored else "") ;
    if !refused > 0 then
      Printf.printf
        "  • %d mutant(s) REFUSED by the wrapper (exit %d): their tests were never run, so \
         these are neither killed nor survived nor errored\n"
        !refused refusal_exit_code ;
    if unmapped <> [] then (
      Printf.printf
        "  • %d survivor(s) could not be mapped to an indexed function — reported here rather \
         than dropped, because a dropped survivor is a defect that silently disappears:\n"
        (List.length unmapped) ;
      (* The VERDICT, exactly as a mapped survivor gets it. Printing only the location left
         the one shape in this rendering that carries no verdict at all. *)
      List.iter
        (fun m ->
          Printf.printf "      %s %s:%d%s\n"
            (MDb.verdict_to_string survivor_verdict)
            m.file m.line
            (match m.mutation with Some x -> Printf.sprintf "  (%s)" x | None -> "") ;
          Printf.printf "        engine status %s under %s — %s\n"
            (String.uppercase_ascii m.status)
            (MDb.provenance_to_string provenance)
            (MDb.verdict_basis survivor_outcome))
        (take maxlist unmapped)) ;
    print_endline "" ;
    if survivors = [] then
      print_endline
        "  no attributable survivor. That is a real result only if the plan actually targeted \
         this code — check `arch-mutants plan` before celebrating." ;
    List.iter
      (fun (m, fn, reaching) ->
        (* The VERDICT, not the engine status: under a ⊤-bounded or contract-less selection
           the engine's SURVIVED publishes as UNKNOWN, and printing the raw status here
           would be the naked status FR-013 forbids. *)
        Printf.printf "  • %s %s:%d%s\n"
          (MDb.verdict_to_string survivor_verdict)
          m.file m.line
          (match m.mutation with Some x -> Printf.sprintf "  (%s)" x | None -> "") ;
        Printf.printf "      in %s\n" fn ;
        Printf.printf "      engine status SURVIVED under %s — %s\n"
          (MDb.provenance_to_string provenance)
          (MDb.verdict_basis survivor_outcome) ;
        if reaching <> [] then
          Printf.printf "      %d test(s) reach it and none killed it: %s%s\n" (List.length reaching)
            (String.concat ", " (take 5 reaching))
            (if List.length reaching > 5 then Printf.sprintf " +%d" (List.length reaching - 5) else "")
        else print_endline "      NO test reaches it — this is not a weak test, it is untested code")
      (take maxlist survivors) ;
    if maxlist > 0 && List.length survivors > maxlist then
      Printf.printf "  … and %d more (--max-list 0 for all)\n" (List.length survivors - maxlist)) ;
  (survivors, unmapped, !errored, survivor_outcome)

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

(** THE ENGINE'S HANDLE ON A MUTANT — a run-scoped coordinate, and NOT an identity.

    R4-A closed the original conflation in the type: [site_key] is a distinct record with no
    identifier field, so an identity cannot carry an engine id by construction, and
    [engine_name] splits [Engine_declared] from [Report_ordinal]. Those are compiler
    guarantees. What was left open is smaller: this handle was a bare [string], so a future
    author could compare two of them and rebuild the deleted join arm under a name no grep
    anticipates.

    THIS MODULE DOES NOT CLOSE THAT HOLE, AND IT IS NOT MEANT TO READ AS IF IT DOES. Both
    legitimate uses of the handle — telling the wrapper which mutant to activate, and naming
    an entry in a diagnostic — require a string. So the type has renderers, and the moment it
    has one, [to_display_string a = to_display_string b] reconstitutes exactly the comparison
    an unexposed equality was supposed to forbid. Abstraction MOVES the escape hatch; it does
    not remove it.

    What it does buy is that the wrong thing has to be WRITTEN OUT. There is no [to_string]:
    each renderer is named for the CHANNEL it feeds, so a comparison of two handles cannot be
    spelled without naming a channel in it, and [to_display_string a = to_display_string b]
    reads as wrong at the call site rather than as ordinary. That is legibility, not
    prevention. The enforcement lives elsewhere and is named where it lives:
    checks/join-independent-of-id-shape.js diverges on any residual id-sensitivity whatever
    it is called, and checks/one-engine-id-two-sites-is-refused.js refuses a catalogue in
    which one handle addresses two sites. *)
module Engine_run_id : sig
  type t

  val of_catalogue : string -> t
  (** the id the ENGINE'S CATALOGUE gave this mutant. The only origin there is: a generic
      catalogue record without an [id] is refused at load, and mutaml's is derived exactly
      as mutaml derives it. *)

  val of_wrapper_trace : string -> t
  (** the handle a trace line reports back, which is the same string the driver put in the
      selection file. Separate from [of_catalogue] so the round trip is visible: these two
      constructors are the ONLY two ends of the wrapper protocol. *)

  val for_wrapper_argv : t -> string
  (** the selection file's first field, and hence [MUTAML_MUTANT]. This is a protocol
      channel: the bytes matter and no other use may borrow it. *)

  val to_display_string : t -> string
  (** for a diagnostic an operator reads, and for the [engine_mutant_id] column that records
      what the engine called this thing. Never for a decision. *)
end = struct
  type t = string

  let of_catalogue s = s
  let of_wrapper_trace s = s
  let for_wrapper_argv s = s
  let to_display_string s = s
end

(** One mutant as the ENGINE's own catalogue describes it: a SITE, plus the id the engine
    will export in [MUTAML_MUTANT].

    [s_engine_id] is RUN-SCOPED and is used for exactly two things: telling the wrapper which
    mutant to activate, and reading the wrapper's trace line back. It is never an identity and
    no join consults it — see the IDENTITY DOCTRINE above. Its type says so and its renderers
    are named for their channel; neither makes a comparison impossible, only conspicuous. *)
type site = {
  s_engine_id : Engine_run_id.t;
  s_file : string;
  s_line : int;
  s_col_start : int;
  s_col_end : int;
  s_repl : string;
  s_occurrence : int option;
      (** WHICH OCCURRENCE OF THE ANCHOR this mutant is, when the engine addresses mutants by
          an anchor rather than by a column span — [scripts/mutate-check.sh] already prints
          [(anchor x<n>)], so two mutants can share a file, a line, an anchor and a
          replacement and differ in nothing else.

          It comes from the MUTATION SPECIFICATION — the catalogue record — and from nowhere
          else. Taking it from a position in the report file would be the defect this round
          removes, reintroduced under a new name: a report position is a coordinate of one
          run, and the site key must not depend on one.

          [None] means the specification stated no occurrence, which is a different fact from
          "the first". Two catalogue entries that are both [None] on an otherwise identical
          site key are INDISTINGUISHABLE, and the driver refuses them rather than choosing. *)
}

(** The SITE KEY: the sole discriminant of a mutant's identity, and the OCaml counterpart of
    [UNIQUE(file_path, line, col_start, col_end, replacement, source_hash)] in
    mutants-schema-migration.sql — the occurrence ordinal reaches that key through
    [source_hash], which is why [source_hash] carries it.

    REFUSE ON COLLISION, NEVER CHOOSE. If two mutants resolve to one site key the honest
    output is a refusal. The tempting implementation is to take one — [LIMIT 1], or the head
    of a list — and a later reader WILL write it, which is why the rule is stated here beside
    the key and not only in a commit message. Taking one turns an honest "I cannot attribute
    this" into a false attribution, which is precisely the failure this whole round removes:
    nothing distinguishes the candidates, so any choice is list order recorded as a fact. *)
type site_key = {
  k_file : string;
  k_line : int;
  k_col_start : int;
  k_col_end : int;
  k_repl : string;
  k_occurrence : int option;
}

(* Full-path equality with a leading "./" normalised away and NOTHING else. A basename
   comparison is what an earlier round removed: [lib/a/main.ml] and [lib/b/main.ml] are two
   different mutants and no amount of convenience makes them one. *)
let strip_dot p =
  if String.length p > 2 && String.sub p 0 2 = "./" then String.sub p 2 (String.length p - 2)
  else p

let same_path a b = strip_dot a = strip_dot b

let site_key s =
  { k_file = strip_dot s.s_file; k_line = s.s_line; k_col_start = s.s_col_start;
    k_col_end = s.s_col_end; k_repl = s.s_repl; k_occurrence = s.s_occurrence }

(** For a diagnostic. Named for that, not for its type: an identity comparison belongs on
    the [site_key] record itself, where the fields are, and never on two rendered strings. *)
let site_key_for_display k =
  Printf.sprintf "%s:%d cols %d-%d replacement %S%s" k.k_file k.k_line k.k_col_start k.k_col_end
    k.k_repl
    (match k.k_occurrence with
    | Some n -> Printf.sprintf " occurrence %d" n
    | None -> " (no occurrence stated)")

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
                    { s_engine_id =
                        Engine_run_id.of_catalogue
                          (Filename.remove_extension fname ^ ":" ^ string_of_int n);
                      s_file = fname;
                      s_line = ints start "pos_lnum";
                      s_col_start = ints start "pos_cnum" - ints start "pos_bol";
                      s_col_end = ints stop "pos_cnum" - ints stop "pos_bol";
                      s_repl = repl;
                      (* mutaml addresses every mutant by an exact column span, so its
                         specification states no anchor occurrence. [None] rather than 1:
                         "not stated" and "the first" are different facts, and only the
                         former may be refused as ambiguous. *)
                      s_occurrence = None })
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
                     { s_engine_id = Engine_run_id.of_catalogue id; s_file = f; s_line = l;
                       s_col_start = num "col_start" 0; s_col_end = num "col_end" 0;
                       s_repl = Option.value ~default:"" (str "replacement");
                       (* From the mutation SPECIFICATION — this record — and never from a
                          position in any report. Absent is a real answer. *)
                       s_occurrence =
                         (match List.assoc_opt "occurrence" a with
                         | Some (`Int i) -> Some i
                         | _ -> None) }
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

(** The two DERIVATION TAGS [source_hash] can stamp. They are part of the stored value, so a
    consumer reads the derivation out of the column with plain SQL and needs no access to
    this file. *)
let hash_from_source_line = "line"

let hash_from_site_descriptor = "site"

(** [<derivation>:<32-hex MD5>] — the repository's existing digest idiom (see
    [Arch_index_compare]'s body hash), with the derivation written INTO the value.

    Why the tag exists. This column is half of [UNIQUE(file_path, line, col_start, col_end,
    replacement, source_hash)], and it held two INCOMPARABLE derivations in one TEXT field
    with nothing recording which had been used — the same design error as an engine ordinal
    sharing a field with an engine name, in the very column the identity key is built from:

      * [line] — the digest of the actual source line. This is what makes the key survive an
        edit ABOVE the mutant (the line moves, the hash follows) and refuse to conflate two
        different texts that landed on one span.
      * [site] — the digest of a synthetic site descriptor, used when the source cannot be
        read. Still stable and still discriminating between two replacements at one span,
        but it will never notice a rewrite of the line.

    The degradation used to be named only in this docstring, which is to say only to a reader
    of the OCaml and never to a consumer holding the database. It is now in the value.

    THE OCCURRENCE ORDINAL IS HASHED IN, in both arms, and that is load-bearing rather than
    tidy: the site key distinguishes two mutants on one anchor by their occurrence, but the
    DATABASE's uniqueness runs through this column, so a hash that ignored the ordinal would
    re-collapse in storage exactly the pair the key had just told apart.
    checks/source-hash-declares-its-derivation.js pins all of it. *)
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
  let occ = match s.s_occurrence with Some n -> string_of_int n | None -> "" in
  match line with
  | Some l ->
      Printf.sprintf "%s:%s" hash_from_source_line
        (Digest.to_hex (Digest.string (Printf.sprintf "%s\x00occurrence=%s" l occ)))
  | None ->
      Printf.sprintf "%s:%s" hash_from_site_descriptor
        (Digest.to_hex
           (Digest.string
              (Printf.sprintf "site\x00%s\x00%d\x00%d\x00%d\x00%s\x00occurrence=%s" s.s_file
                 s.s_line s.s_col_start s.s_col_end s.s_repl occ)))

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

(* ------------------------------------------------------------------ *)
(* FR-030 / AC-24 — THE TREE BOUNDARY (issue #77).                     *)
(*                                                                    *)
(* [locate_wrapper] and [locate_impact] both find their artefact by    *)
(* walking ancestor directories from the working directory. A checkout *)
(* placed INSIDE another checkout therefore resolves the PARENT's      *)
(* wrapper and the PARENT's arch-impact, silently, with entirely       *)
(* plausible output. For a mutation campaign that is the worst         *)
(* available failure: the parent's binary is unmutated, so every       *)
(* mutant survives and the report becomes a page of false test gaps    *)
(* that reads exactly like a real finding.                             *)
(*                                                                    *)
(* The boundary is the checkout the command was invoked from. It is    *)
(* `git rev-parse --show-toplevel`, NARROWED to a nearer               *)
(* `dune-project` only when that repository does not TRACK it — a      *)
(* tracked one is the same checkout, and narrowing there refuses the   *)
(* repository's own artefact — and falling back to the working         *)
(* directory itself where neither answers, which is the narrower and   *)
(* therefore safer answer. An artefact resolved outside the boundary   *)
(* is REFUSED and the outside path is NAMED, because an exit code on   *)
(* its own cannot tell a fired guard from an unrelated failure. The    *)
(* DIAGNOSIS is chosen by which of the three answered, never asserted. *)
(*                                                                    *)
(* An environment override naming a path that EXISTS is exempt, and    *)
(* deliberately so: there the operator named the path, and refusing it *)
(* would break every harness that points the driver at a built binary  *)
(* outside its own tree on purpose.                                    *)
(* ------------------------------------------------------------------ *)

let real_path p = try Unix.realpath p with Unix.Unix_error _ -> p

(** HOW the boundary was established, carried alongside it because the refusal's DIAGNOSIS
    depends on it and printing the wrong one is its own defect: a fallback boundary that
    asserts "this checkout is nested inside another one" sends the reader hunting for a
    tree that does not exist. *)
type tree_anchor =
  | Anchor_git  (** `git rev-parse --show-toplevel` answered *)
  | Anchor_marker  (** a `dune-project` above the working directory: the checkout's own root *)
  | Anchor_cwd  (** neither: the boundary is the invocation directory, and nothing is claimed *)
  | Anchor_undetermined of int
      (** git answered the toplevel but could NOT answer whether the nested marker is
          tracked — it exited with the carried code, which is neither 0 (tracked) nor 1 (not
          tracked). The boundary is the narrower one, as under [Anchor_marker], but the
          reason is different and saying [Anchor_marker]'s reason here is FALSE: it asserts
          the repository does not track the marker, which is precisely what nobody knows. *)

(** The MACHINE-READABLE name of the arm that decided the boundary, printed alongside the
    refusal so that a reader — human or check — can tell which of the four branches ran
    WITHOUT parsing the English diagnosis.

    THIS EXISTS BECAUSE MATCHING PROSE IS A GATE THAT ROTS. Every check that wanted to know
    which arm fired had to key on phrases lifted out of the diagnoses, and an enumerated set
    of phrases is defeated by the next phrase: a repair that knew two of them shipped a check
    blind to the third, and the coverage hole it opened was on the very defect it was
    repairing. A tag the CODE emits removes the question instead of moving it — reword every
    diagnosis and the tag is unchanged.

    THE MATCH IS EXHAUSTIVE AND CARRIES NO WILDCARD ON PURPOSE. A fifth anchor cannot be
    added without the compiler demanding a tag for it, so the set of arms and the set of tags
    cannot drift apart in silence. checks/tree-boundary-anchor-is-structural.js pins that
    same correspondence from the outside, against this source and against the binary. *)
let anchor_tag = function
  | Anchor_git -> "git"
  | Anchor_marker -> "marker"
  | Anchor_cwd -> "cwd"
  | Anchor_undetermined _ -> "marker-undetermined"

(** The nearest ancestor of [d] holding a tree-local marker of a checkout root.

    `dune-project` is the marker. It is what says "this directory is the root of the
    project the campaign belongs to" in exactly the case git cannot answer — an unpacked
    tarball, a vendored subtree, an out-of-tree copy — and every OCaml source tree this
    driver can be pointed at carries one. *)
let marker_root d =
  let rec up d =
    if Sys.file_exists (Filename.concat d "dune-project") then Some d
    else
      let parent = Filename.dirname d in
      if parent = d then None else up parent
  in
  up d

(** What git said when asked whether the repository rooted at [repo] tracks [path].

    THREE ANSWERS, NOT TWO, and the third is the whole point of this type existing. The
    previous shape of this code was [Sys.command ... = 0], a boolean, and every non-zero exit
    collapsed into "not tracked" — conflating a NEGATIVE ANSWER with A FAILURE TO ANSWER.

    That is not hypothetical and it is not rare. `git ls-files --error-unmatch` reads the
    INDEX; `git rev-parse --show-toplevel` does not. So an index that cannot be read —
    permissions, truncation, a half-written file, a corrupted checkout — leaves the toplevel
    answering 0 while ls-files exits 128. MEASURED (git 2.55.0): with the index chmod 000, and
    again with fourteen bytes of garbage written over it, ls-files exits 128 and
    `rev-parse --show-toplevel` exits 0 in both. The branch below IS therefore reached, a
    TRACKED marker was declared untracked, the boundary shrank, and the repository refused its
    own artefact while asserting it belonged to a different tree — a wrong verdict carrying a
    wrong reason. That was finding :1133 returning through the error path of its own fix.

    The exit vocabulary is git's own and is narrow on purpose: 0 means every named path is in
    the index, 1 means one is not, and `--error-unmatch` is what makes that 1 an ANSWER rather
    than an empty listing. Everything else — 128 for a fatal error, 127 for no git on PATH —
    is git declining to answer, and is carried out of here as such.

    The message text is deliberately NOT consulted. git localises its diagnostics (the same
    fatal read `fichier d'index plus petit qu'attendu` on the machine this was measured on),
    so anything keyed on English wording is a matcher that stops matching under LANG. The exit
    code is the part of the interface that does not move. *)
type tracked_answer =
  | Tracked
  | Untracked
  | Undetermined of int  (** git's exit code, which is neither 0 nor 1 *)

let tracked_by ~repo path =
  match
    Sys.command
      (Printf.sprintf "git -C %s ls-files --error-unmatch -- %s >/dev/null 2>&1"
         (Filename.quote repo) (Filename.quote path))
  with
  | 0 -> Tracked
  | 1 -> Untracked
  | code -> Undetermined code

(** The boundary, resolved ONCE. Computed lazily so a campaign that never walks an ancestor
    never pays for a subprocess, and so the value cannot drift between the two call sites
    that consult it.

    It is the NEARER of the git toplevel and the checkout's own marker root, not the git
    toplevel alone. Anchoring on git alone made `git init` — rather than the layout —
    decide whether FR-030's guard fires at all: a checkout that is not itself a repository
    but sits inside one resolves its toplevel to the OUTER repo, the boundary spans both
    trees, and the outer tree's wrapper is handed to the engine. That is issue #77
    unrefused, and `git init` in the inner tree flipped it. *)
let working_tree_root =
  lazy
    (let cwd = real_path (Sys.getcwd ()) in
     let out = Filename.temp_file "arch-mutants-toplevel" ".txt" in
     let code =
       Sys.command
         (Printf.sprintf "git rev-parse --show-toplevel > %s 2>/dev/null" (Filename.quote out))
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
     let git = if code = 0 && value <> "" then Some (real_path value) else None in
     let marker = Option.map real_path (marker_root cwd) in
     (* Both, when present, are ancestors of the working directory, so "nearer" is simply
        the longer path. The DEEPER boundary is the safer one ONLY where the two describe
        DIFFERENT checkouts. Where a git repository TRACKS the marker, they describe the
        same one, and narrowing there refuses the repository's own artefact while asserting
        it "belongs to a different tree" — a false verdict carrying a false reason. This
        repository carries a tracked poc/decision-lint/dune-project, so it refused itself. *)
     match (git, marker) with
     | Some g, Some m ->
         if String.length m <= String.length g then (g, Anchor_git)
         else (
           (* Three answers, three boundaries, and the third one is NOT a rounding of either
              neighbour. Tracked: same checkout, keep the repository. Untracked: a different
              checkout, narrow — that is issue #77 and nothing here trades it away. Could not
              tell: narrow, because widening on an answer nobody has would hand the OUTER
              tree's artefact to the engine on a broken index, but carry the REASON so the
              refusal says the index could not be read instead of asserting a nesting that
              nobody established. *)
           match tracked_by ~repo:g (Filename.concat m "dune-project") with
           | Tracked -> (g, Anchor_git)
           | Untracked -> (m, Anchor_marker)
           | Undetermined code -> (m, Anchor_undetermined code))
     | Some g, None -> (g, Anchor_git)
     | None, Some m -> (m, Anchor_marker)
     | None, None -> (cwd, Anchor_cwd))

let tree_root () = fst (Lazy.force working_tree_root)
let tree_anchor () = snd (Lazy.force working_tree_root)

let inside_tree path =
  let root = tree_root () in
  let p = real_path path in
  let prefix = if String.length root > 0 && root.[String.length root - 1] = '/' then root else root ^ "/" in
  p = root
  || (String.length p >= String.length prefix
     && String.sub p 0 (String.length prefix) = prefix)

(** [what] names the artefact in the refusal, so the message says which of the two walks
    fired. The path is reported EXACTLY as the walk built it, not as [Unix.realpath]
    rewrote it, because that is the path the operator can go and look at. *)
let guard_inside_tree ~what path =
  if inside_tree path then path
  else
    let root = tree_root () in
    (* The diagnosis is chosen by HOW the boundary was found, never asserted. Under
       [Anchor_cwd] there is no enclosing repository and no marker, so there is no nesting
       to report and claiming one is simply false. *)
    let diagnosis =
      match tree_anchor () with
      | Anchor_git ->
          "The boundary is the enclosing git repository (`git rev-parse --show-toplevel`).            The artefact was reached by walking ancestor directories, so this checkout is            nested inside another one and the campaign was about to run the OUTER tree's            artefact."
      | Anchor_marker ->
          "The boundary is this checkout's own root, found as the nearest `dune-project`            above the working directory — with no git repository at all, or nearer than one            that does NOT track it, which is what makes it a checkout of its own. The            artefact was reached by walking PAST that root, so it belongs to a different            tree."
      | Anchor_cwd ->
          "No boundary could be established: `git rev-parse --show-toplevel` did not            answer and there is no `dune-project` above the working directory. The boundary            therefore FELL BACK to the invocation directory itself, which is the narrower            and safer answer. This is NOT a claim that this checkout is nested inside            another one — nothing here can tell whether it is."
      | Anchor_undetermined code ->
          Printf.sprintf
            "The boundary is this checkout's own `dune-project` root, and it was narrowed to            it because git COULD NOT SAY whether the enclosing repository tracks that            marker: `git ls-files --error-unmatch` exited %d, which is neither 0 (tracked)            nor 1 (not tracked). The usual cause is an index that cannot be read — check            `.git/index` for permissions and for truncation. This is NOT a claim that the            marker is untracked and NOT a claim that this artefact was reached by walking out of the            checkout it belongs to; either might be true and nothing here established which. The narrower            boundary was taken because the wider one cannot be justified on an answer that            was never given."
            code
    in
    refuse
      (Printf.sprintf
         "arch-mutants: %s resolved to %s, which is OUTSIDE the boundary %s.\n\
          arch-mutants: boundary-anchor=%s\n\
          %s That is issue #77's mechanism: the outer tree's binary is unmutated, every \
          mutant survives, and the report becomes a page of false test gaps that reads \
          exactly like a real finding. Refusing rather than producing it.\n\
          What would make this work: build the artefact inside %s, or name the one you mean \
          explicitly with ARCH_MUTANTS_WRAPPER / ARCH_IMPACT — an override that names an \
          existing path is honoured, because there you chose it."
         what path root (anchor_tag (tree_anchor ())) diagnosis root)

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
      (* FR-030: the walk may leave the tree, and a wrapper from the enclosing checkout is
         not a fallback, it is a different campaign. *)
      Option.map
        (guard_inside_tree ~what:"the per-mutant wrapper scripts/mutaml-wrapper.sh")
        (up (Sys.getcwd ()))

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
      (* FR-030 again. Only the ANCESTOR WALK is guarded: a PATH hit is an installed
         binary the operator put there on purpose, which is the same kind of explicit
         choice as an environment override, whereas an ancestor hit is one nobody made. *)
      match up (Sys.getcwd ()) with
      | Some p -> Some (guard_inside_tree ~what:"arch-impact" p)
      | None -> resolve_binary "arch-impact")

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
        (* An EMPTY `touched` array is NOT refused here, and the distinction is the whole
           point. Rules 1 and 2 selecting nothing is legitimate — a documentation-only range
           touches no indexed function — and rule 3, the deleted-test recheck, can still
           select mutants on its own. What must never happen is the campaign proceeding once
           ALL THREE rules have selected nothing, and that is refused where the union is
           known, in [run_campaign] after the narrowing, naming an empty touched set as the
           cause when it was one. Refusing here instead would have broken the deleted-test
           rule, which is the case this driver's own tezt suite exercises. *)
        | Some (`List l) ->
            (* Entries the reader cannot understand are COUNTED, never dropped. They used to
               go through `List.filter_map` with no count at all, so an arch-impact that
               renamed `name` shrank the touched set silently — and a set silently shrunk
               from twelve to three is indistinguishable from a correct set of three. *)
            let parsed =
              List.filter_map
                (function
                  | `Assoc f -> (
                      let str k =
                        match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None
                      in
                      match str "name" with
                      | Some n -> Some { i_name = n; i_how = Option.value ~default:"?" (str "how") }
                      | None -> None)
                  | _ -> None)
                l
            in
            let dropped = List.length l - List.length parsed in
            if dropped > 0 then
              die
                (Printf.sprintf
                   "arch-mutants: %s --format json returned %d `touched` entr(ies) and %d of \
                    them carry no string `name` field, so they could not be read. Refusing \
                    rather than scoping the campaign on the %d that could: a touched set \
                    silently shrunk is indistinguishable from a correct small one, and every \
                    mutant outside it would publish as 'not at risk' rather than 'not looked \
                    at'. No campaign row was written.\n\
                    What this usually means: arch-impact's `touched` entry shape changed and \
                    the field is no longer called `name`."
                   impact (List.length l) dropped (List.length parsed)) ;
            Impact_ok parsed
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
    OUTCOME, and how many `mutant_kills` rows that campaign holds for it.

    The outcome is an {!MDb.outcome} and never a boolean. A [pk_killed : bool] read off
    [engine_status] ALONE is the exact shape FR-011 exists to forbid: a SURVIVED recorded
    under a ⊤-bounded selection publishes as UNKNOWN everywhere else in this tool, and
    collapsing it to "not killed" here made it a PROVEN non-kill — which is what decided
    that it needed no re-check when a test was deleted. Status and provenance are read
    from the same row, in the projection below, and every consumer branches on
    {!MDb.published_verdict}.

    "Alone" is [pk_kills = 1] together with [pk_sole_test]. Attribution "never known" is
    [pk_kills = 0] on a mutant whose verdict is not a proved SURVIVED — the executed set
    was larger than one and no engine named the killer, or the selection cannot be shown
    to have run the reaching tests at all, so nothing can say whether the deleted test was
    the only one catching it. *)
type prior_mutant = {
  pk_file : string;
  pk_line : int;
  (* The other half of the site key the `mutants` UNIQUE constraint is built from. It was
     projected away, so the deleted-test recheck matched on (basename, line) and inherited
     the outcome join's conflation: two mutants on one line could not be told apart, and
     slice 4 reads the very table that conflation corrupts. *)
  pk_col_start : int;
  pk_col_end : int;
  pk_repl : string;
  pk_outcome : MDb.outcome;
  pk_kills : int;
  pk_sole_test : string option;
}

module Prior_shape = struct
  open Arch_db

  let s = Rows.s
  let i = Rows.i

  (* file_path, line, engine_status, selection_provenance, one kill row's test_name,
     kill count, then col_start, col_end and replacement. The provenance travels in the
     SAME projection as the status: this is the only place either is read, so there is no
     second site at which they could be paired with a value from a different row (FR-013,
     FR-033). The three site columns travel in it for the same reason. *)
  let row = Ty.(t3 (t3 s i s) (t3 s s i) (t3 i i s))

  let cells ((file, line, status), (prov, test, kills), (cs, ce, repl)) =
    [ text_cell file; int_cell line; text_cell status; text_cell prov; text_cell test;
      int_cell kills; int_cell cs; int_cell ce; text_cell repl ]
end

(** What a prior outcome lets us conclude about ATTRIBUTION, which is the only question
    the deleted-test rule asks of it. Total over the published verdict, so a sixth verdict
    cannot be dropped here silently. *)
type prior_attribution =
  | Pa_no_test_kills_it
      (** verdict SURVIVED: every reaching test ran and none killed it, so no deleted test
          can have been the one catching it. Safe from the deletion, provably. *)
  | Pa_known of string  (** killed, and exactly one kill row names the killer *)
  | Pa_never_known
      (** nothing can be said: a kill with no attribution, or a verdict of UNKNOWN /
          UNKNOWN_NO_CONTRACT / ERROR, where the reaching tests may never have run at
          all. Reported as UN-RECHECKABLE rather than silently skipped. *)

let prior_attribution p =
  match MDb.published_verdict p.pk_outcome with
  | MDb.V_survived -> Pa_no_test_kills_it
  | MDb.V_killed -> (
      match p.pk_sole_test with Some tn when p.pk_kills = 1 -> Pa_known tn | _ -> Pa_never_known)
  (* UNKNOWN, UNKNOWN_NO_CONTRACT and ERROR all mean the same thing HERE: no run of any
     test was proved, so the deletion cannot be shown to be harmless. V_pending cannot
     reach this — [published_verdict] never returns it and a prior_mutant is built from a
     run row that exists — and is named rather than caught so a future change is a
     compile error. *)
  | MDb.V_unknown | MDb.V_unknown_no_contract | MDb.V_error | MDb.V_pending -> Pa_never_known

let prior_mutants (t : Arch_db.t) =
  if not (Arch_db.has_table t "mutant_runs" && Arch_db.has_table t "mutant_kills") then None
  else
    Some
      (List.filter_map
         (fun row ->
           match row with
           | [ file_c; line_c; status_c; prov_c; test_c; kills_c; cs_c; ce_c; repl_c ] ->
               let text = function
                 | Arch_db.Text s -> Some s
                 | Arch_db.Nul | Arch_db.Int _ | Arch_db.Real _ -> None
               in
               let int_of = function
                 | Arch_db.Int i -> Some i
                 | Arch_db.Nul | Arch_db.Text _ | Arch_db.Real _ -> None
               in
               let kills = Option.value ~default:0 (int_of kills_c) in
               let status =
                 match Option.map MDb.status_of_string (text status_c) with
                 | Some (Some st) -> st
                 | Some None | None ->
                     die
                       (Printf.sprintf
                          "arch-mutants: a prior mutant_runs row holds engine_status %S, which \
                           is not one of KILLED|SURVIVED|TIMEOUT|ERROR. Refusing to guess: a \
                           status added to the CHECK and dropped here would silently shrink the \
                           re-check set."
                          (Option.value ~default:"NULL" (text status_c)))
               in
               (* Read here and nowhere else, from the same row as the status above, and
                  refused on the same terms: defaulting it to proved_superset is precisely
                  what would turn an UNKNOWN into a proven non-kill. *)
               let provenance =
                 match Option.map MDb.provenance_of_string (text prov_c) with
                 | Some (Some pr) -> pr
                 | Some None | None ->
                     die
                       (Printf.sprintf
                          "arch-mutants: a prior mutant_runs row holds selection_provenance \
                           %S, which is not one of proved_superset|top_bounded|no_contract. \
                           Refusing to guess: defaulting it would publish a bounded SURVIVED \
                           as a proved non-kill and drop the mutant from the re-check set."
                          (Option.value ~default:"NULL" (text prov_c)))
               in
               Some
                 { pk_file = Option.value ~default:"" (text file_c);
                   pk_line = Option.value ~default:0 (int_of line_c);
                   pk_col_start = Option.value ~default:0 (int_of cs_c);
                   pk_col_end = Option.value ~default:0 (int_of ce_c);
                   pk_repl = Option.value ~default:"" (text repl_c);
                   pk_outcome = { MDb.o_status = status; o_provenance = provenance };
                   pk_kills = kills;
                   pk_sole_test = (if kills = 1 then text test_c else None) }
           | _ -> None)
         (Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Prior_shape.row
            ~to_cells:Prior_shape.cells
            "SELECT m.file_path, m.line, r.engine_status, r.selection_provenance, (SELECT \
             k.test_name FROM \
             mutant_kills k WHERE k.mutant_id = m.id AND k.campaign_id = l.cid ORDER BY \
             k.test_name LIMIT 1), (SELECT count(*) FROM mutant_kills k WHERE k.mutant_id = \
             m.id AND k.campaign_id = l.cid), m.col_start, m.col_end, m.replacement FROM \
             mutants m JOIN (SELECT mutant_id AS mid, \
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
  ds_recheck : prior_mutant list;  (** carried whole: the recheck match is the SITE KEY *)
  ds_unrecheckable : (string * int) list;
  ds_file_granular : int;
}

(** The deleted-test recheck's site match. It used to be
    [line = s_line && (file = s_file || basename file = basename s_file)] over a pair
    projected down to (file, line), so it carried the outcome join's conflation: two mutants
    on one line were one site, and two files sharing a basename were one file. The prior row
    carries the full key — the same columns the `mutants` UNIQUE constraint is built from —
    so the match is that key. This will be load-bearing for slice 4, which reads the
    `mutant_kills` table the conflation corrupts. *)
let same_site (p : prior_mutant) (s : site) =
  p.pk_line = s.s_line && p.pk_file = s.s_file && p.pk_col_start = s.s_col_start
  && p.pk_col_end = s.s_col_end && p.pk_repl = s.s_repl

let in_scope ds (sel : selection) =
  (match sel.sel_fn with Some fn -> SS.mem fn ds.ds_by_function | None -> false)
  || List.exists (fun p -> same_site p sel.sel_site) ds.ds_recheck

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
          (* One traversal, one match, so the two halves cannot disagree about a row: a
             mutant is re-checked, provably safe, or un-recheckable, and never two of
             those. *)
          ( List.filter_map
              (fun p ->
                match prior_attribution p with
                | Pa_known tn when SS.mem tn deleted_set -> Some p
                | Pa_known _ | Pa_no_test_kills_it | Pa_never_known -> None)
              rows,
            List.filter_map
              (fun p ->
                match prior_attribution p with
                | Pa_never_known -> Some (p.pk_file, p.pk_line)
                | Pa_known _ | Pa_no_test_kills_it -> None)
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
  let provenance = selection_provenance ~sound ~escapes in
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
          sel_superset = executed_is_widened ~intended ~executed;
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
        (* A narrowing that leaves NOTHING is refused here, before a single row exists.
           [load_catalogue]'s empty-catalogue refusal fires BEFORE this narrowing and
           cannot see the case; without this, a `--diff` that selected nothing produced a
           COMPLETED campaign with zero runs, which `verdict` then published as all-zero
           counts. That is the one conflation this whole design refuses: an empty read is
           not a clean read. *)
        if keep = [] then
          refuse
            (Printf.sprintf
               "arch-mutants: --diff %s narrowed the catalogue from %d mutant(s) to ZERO. A \
                campaign over an EMPTY SET would select nothing and read as 'nothing to \
                test' — it would report no survivors for the same reason a campaign that \
                found none does — so it is REFUSED rather than run: no campaign row was \
                written.\n\
                %s\n\
                Selection is by FUNCTION, so a mutant is in scope only when the index maps \
                its site into a selected one; %d of the excluded mutant(s) map to no \
                indexed function at all. The deleted-test rule re-selected %d mutant(s).\n\
                What would make this non-empty: a range that touches a function the index \
                carries and the catalogue has a mutant inside."
               ds.ds_range (List.length selections)
               (if ds.ds_touched = [] then
                  Printf.sprintf
                    "%s answered with an EMPTY `touched` array, so rules 1 and 2 selected \
                     nothing at all. That is legitimate on its own — a documentation-only \
                     range touches no indexed function — but here the deleted-test rule \
                     added nothing either, so the union is empty."
                    ds.ds_impact_path
                else
                  Printf.sprintf "The scope came from %s, which named %d touched function(s): %s."
                    ds.ds_impact_path (List.length ds.ds_touched)
                    (String.concat ", " (take 5 ds.ds_touched)))
               (List.length (List.filter (fun s -> s.sel_fn = None) drop))
               (List.length ds.ds_recheck)) ;
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
  (* A test name is not operator input: it is a function name harvested from the ANALYSED
     REPOSITORY'S OWN SOURCE, and it is about to be written into a TSV the wrapper splits
     on tabs and commas and then splices into a command line. So it is checked HERE, where
     it is named, rather than left to detonate in the wrapper — the wrapper quotes it now,
     but a name carrying a comma or a tab would still silently split into two tests, and a
     campaign over an untrusted checkout should be refused at the point the bad name enters
     the pipeline.

     An ALLOWLIST, not a blocklist: a blocklist over shell metacharacters has to be right
     about every shell, and being wrong once is arbitrary command execution. The set below
     covers the test names of every language this index handles — `Test_x.case 1`,
     `tests::foo::bar`, `pkg/foo.TestBar`, `t_alpha` — and nothing that is a separator in
     the TSV or an operator in `sh`. *)
  let name_is_safe n =
    n <> ""
    && String.for_all
         (fun c ->
           (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
           (* The apostrophe is an ordinary OCaml identifier character — `aux'`, `loop'`,
              `test_foo'` — and one such name anywhere in the reaching set used to abort the
              WHOLE campaign at exit 2 with no campaign row. It is also the one excluded
              character the wrapper demonstrably handles: every name is POSIX-quoted before
              substitution, with an embedded quote closed and reopened the '\'' way. Comma,
              tab and newline stay refused — they are the TSV's own separators, which is what
              the refusal message argues for. *)
           || String.contains "_-.:/+@= '" c)
         n
  in
  (* FR-003 — the engine is NEVER invoked with a SUBSET of the intended set, under any
     circumstances. It had no acceptance criterion, no check and no code: the only relation
     computed anywhere was a cardinality comparison, which an executed set of equal size with
     a member SUBSTITUTED satisfies while violating the requirement outright. It is checked
     HERE, before the selection file is written and before any row exists, because a campaign
     that ran the wrong tests reports survivors that are accusations against tests nobody
     gave the chance. *)
  List.iter
    (fun sel ->
      match missing_from_executed ~intended:sel.sel_intended ~executed:sel.sel_executed with
      | [] -> ()
      | missing ->
          die
            (Printf.sprintf
               "arch-mutants: FR-003 — the executed test set for mutant %s at %s:%d is NOT a \
                superset of the intended set: %d of %d intended test(s) would not run (%s). \
                A campaign is allowed to run MORE tests than the plan requires and never \
                fewer; a missing test turns a mutant it would have killed into a survivor, \
                which is a false accusation against a real test. No campaign row was \
                written.\n\
                Where this comes from: the plan's reaching set and the profile's addressable \
                set were computed from different test selections. Run `plan` and `run` with \
                the same --tests."
               (Engine_run_id.to_display_string sel.sel_site.s_engine_id) sel.sel_site.s_file
               sel.sel_site.s_line
               (List.length missing) (List.length sel.sel_intended)
               (String.concat ", " (take 5 missing))))
    selections ;
  List.iter
    (fun sel ->
      List.iter
        (fun n ->
          if not (name_is_safe n) then
            die
              (Printf.sprintf
                 "arch-mutants: the test name %S, reaching mutant %s at %s:%d, carries a \
                  character outside the allowed set (letters, digits, space, apostrophe and \
                  _-.:/+@=). \
                  It would be written into the selection the wrapper reads and then spliced \
                  into a command line, so a name like this is a code-execution vector from \
                  the analysed repository's own source, and a comma or tab in it would \
                  silently split one test into two. No campaign row was written. Fix the \
                  name in the index, or exclude the test with --tests."
                 n
                 (Engine_run_id.to_display_string sel.sel_site.s_engine_id)
                 sel.sel_site.s_file sel.sel_site.s_line))
        (sel.sel_intended @ sel.sel_executed))
    selections ;
  write_file selection_file
    (String.concat ""
       (List.map
          (fun sel ->
            (* The PROTOCOL channel, and the only place the handle is written as itself:
               the engine exports this field as MUTAML_MUTANT to activate one mutant. *)
            Printf.sprintf "%s\t%d\t%s\t%s\n"
              (Engine_run_id.for_wrapper_argv sel.sel_site.s_engine_id)
              (if sel.sel_superset then 1 else 0)
              (String.concat "," sel.sel_intended)
              (String.concat "," sel.sel_executed))
          selections)) ;
  write_file trace_file "" ;
  (* The index run this selection was derived from, where the schema records one. Read
     through the READ-ONLY handle, before the writer opens: on the flat schema there is no
     `producer_runs` table and NULL is the honest answer, not a missing one. *)
  let producer_run_id =
    if not (Arch_db.has_table t "producer_runs") then None
    else
      match
        Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1
          ~to_cells:Arch_db.Rows.c1
          "SELECT CAST(MAX(id) AS TEXT) FROM producer_runs" ()
      with
      | [ Arch_db.Text v ] :: _ -> int_of_string_opt v
      | _ -> None
  in
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
  (* 5a. THE CATALOGUE MUST BE AN INJECTION FROM ids TO SITE KEYS — checked BEFORE the
     campaign row exists, so a refusal here leaves the database exactly as it was found.

     Once the site key is the sole discriminant of identity, a catalogue offering two
     DIFFERENT mutants under one site key is a catalogue this driver cannot honour: it has two
     verdicts and one row to put them in. What used to happen was measured, not argued — the
     two entries collapsed into ONE `mutants` row (INSERT OR IGNORE, then read the id back),
     both report entries resolved to the same `mutant_id`, the second `insert_run` violated
     UNIQUE(campaign_id, mutant_id), and its exception was caught and printed to stderr and
     nothing else. The counters had already been incremented, so the campaign published
     `survived: 1` while the database held one row, stamped `completed_at`, and DELETED a
     survivor in silence — a lost survivor indistinguishable from no survivor, the one
     conflation this design exists to refuse.

     REFUSE, DO NOT RESOLVE. There is no correct choice available: nothing in the two entries
     distinguishes them, so picking one (a `LIMIT 1`, a list head) turns an honest "I cannot
     attribute this" into a false attribution — the same failure in a new costume. What makes
     two such entries legitimately distinct is an anchor OCCURRENCE ordinal stated by the
     mutation specification; that is what the operator is told to add. *)
  let collisions =
    let tbl = Hashtbl.create 64 in
    List.iter (fun sel -> Hashtbl.add tbl (site_key sel.sel_site) sel) selections ;
    Hashtbl.fold
      (fun k _ acc ->
        if List.mem_assoc k acc then acc
        else
          match Hashtbl.find_all tbl k with
          | _ :: _ :: _ as group -> (k, group) :: acc
          | _ -> acc)
      tbl []
  in
  (match collisions with
  | [] -> ()
  | _ ->
      Printf.eprintf
        "arch-mutants: the catalogue gives %d site key(s) to more than one mutant. A site key \
         is the WHOLE of a mutant's identity here (mutants-schema-migration.sql: identity is \
         where the mutation is and what it replaces, never an engine-assigned id), so two \
         entries sharing one have two verdicts and a single row to store them in:\n"
        (List.length collisions) ;
      List.iter
        (fun (k, group) ->
          Printf.eprintf "    %s\n" (site_key_for_display k) ;
          List.iter
            (fun sel ->
              Printf.eprintf "      claimed by engine id %S (RUN-scoped)\n"
                (Engine_run_id.to_display_string sel.sel_site.s_engine_id))
            group)
        collisions ;
      Printf.eprintf
        "  Refusing, rather than choosing one. Nothing in these entries tells them apart, so \
         any choice would be list order recorded as a fact — and the previous behaviour was \
         worse than a wrong choice: the rows collapsed, the second verdict was rejected by \
         UNIQUE(campaign_id, mutant_id), the exception was printed and swallowed, and the \
         campaign completed with a SURVIVOR deleted. No campaign row was written.\n\
         What would make this catalogue acceptable: an `occurrence` ordinal on each entry, \
         from the mutation specification (the anchor occurrence `scripts/mutate-check.sh` \
         already counts) — never a position in a report file, which is a coordinate of one \
         run and not a property of the mutant.\n" ;
      ignore (finish 1 : 'a)) ;
  (* 5b. AND THE OTHER DIRECTION, which 5a's own comment claims and 5a's code does not check:
     no engine id may address more than one SELECTED site. Checked here, before the campaign
     row exists, for the same reason as 5a — a refusal must leave the database as it was
     found.

     WHY THIS IS A REFUSAL AND NOT A REPAIR. The engine id is the wrapper's ONLY handle on a
     mutant: `run` writes one selection line per site whose first field is that id, and the
     engine activates a mutant by exporting exactly that string as MUTAML_MUTANT. Two selected
     sites under one id are therefore unaddressable in the literal sense — nothing the driver
     can send activates one and not the other — and the trace line that comes back names the
     id, so even the observed test set cannot be attributed to one of them. There is no
     correct choice to make, which is 5a's doctrine reached along the other axis.

     WHAT WAS MEASURED BEFORE THIS EXISTED, on a two-entry catalogue whose sites differ in
     their column span and whose ids are both "1": two `mutants` rows were written, the map
     from a selection to its row was keyed on the id so the second entry OVERWROTE the first,
     the SURVIVED verdict of the col-3 site was stored against the col-11 mutant — a false
     attribution, the exact failure this round removes — and the KILLED verdict was rejected
     by UNIQUE(campaign_id, mutant_id) and lost. The campaign did NOT read as complete: the
     reconciliation guard saw 1 row against 2 attempts and withheld completed_at, which is a
     real mitigation and is why this was a wrong row rather than a silent success. But a
     false row plus a raw SQLite constraint message is not a diagnosis an operator can act
     on, and the wrong row was still written.

     checks/one-engine-id-two-sites-is-refused.js holds this, with a control arm in which the
     identical catalogue carries distinct ids and must still run. *)
  let id_collisions =
    let tbl = Hashtbl.create 64 in
    List.iter
      (fun sel -> Hashtbl.add tbl (Engine_run_id.for_wrapper_argv sel.sel_site.s_engine_id) sel)
      selections ;
    Hashtbl.fold
      (fun handle _ acc ->
        if List.mem_assoc handle acc then acc
        else
          match Hashtbl.find_all tbl handle with
          | (_ :: _ :: _) as group
            when List.length
                   (List.sort_uniq compare (List.map (fun sel -> site_key sel.sel_site) group))
                 > 1 ->
              (handle, group) :: acc
          | _ -> acc)
      tbl []
  in
  (match id_collisions with
  | [] -> ()
  | _ ->
      Printf.eprintf
        "arch-mutants: %d engine id(s) in this catalogue address more than one SELECTED site. \
         The engine id is the wrapper's only handle on a mutant — it is the selection file's \
         first field and the value the engine exports as MUTAML_MUTANT — so these sites cannot \
         be activated, traced or attributed separately:\n"
        (List.length id_collisions) ;
      List.iter
        (fun (handle, group) ->
          Printf.eprintf "    engine id %S (RUN-scoped) is claimed by %d sites:\n" handle
            (List.length group) ;
          List.iter
            (fun sel -> Printf.eprintf "      %s\n" (site_key_for_display (site_key sel.sel_site)))
            group)
        id_collisions ;
      Printf.eprintf
        "  Refusing, rather than choosing one. Measured on the previous behaviour: the map \
         from a selection to its database row was keyed on this id, so one entry overwrote \
         the other, ONE verdict was stored against the WRONG mutant and the other was \
         rejected by UNIQUE(campaign_id, mutant_id) and lost. No campaign row was written.\n\
         What would make this catalogue acceptable: a distinct id per entry. An id is a \
         RUN-scoped coordinate and not an identity, so the driver will not invent one — a \
         synthesised handle is a handle the engine does not answer to.\n" ;
      ignore (finish 1 : 'a)) ;
  let campaign_id =
    try
      MDb.insert_campaign db ~engine ~engine_version ~seed ~engine_path
        ~test_runner_path:runner_path ~profile:profile_name
        ~granularity:(granularity_to_string granularity) ~producer_run_id
    with MDb.Write_failed m ->
      prerr_endline ("arch-mutants: " ^ m) ;
      finish 2
  in
  (* Keyed on the SITE KEY, never on the engine id. This map stands between a mutant and the
     row its verdict is written to, which makes it an identity-bearing operation, and an
     identity-bearing operation keyed on a run-scoped coordinate is the deleted join arm
     wearing a hashtable. 5b now refuses the catalogue that made the difference observable;
     the key is on the identity anyway, so weakening 5b later cannot quietly reintroduce a
     verdict stored against the wrong row. *)
  let mutant_ids = Hashtbl.create 32 in
  List.iter
    (fun sel ->
      let s = sel.sel_site in
      match
        MDb.insert_mutant db ~file_path:s.s_file ~line:s.s_line ~col_start:s.s_col_start
          ~col_end:s.s_col_end ~replacement:s.s_repl ~source_hash:sel.sel_hash
          ~function_name:sel.sel_fn
      with
      | id -> Hashtbl.replace mutant_ids (site_key s) id
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
          Hashtbl.replace executed_by_id (Engine_run_id.of_wrapper_trace id) tests
      | _ -> ())
    (read_lines trace_file) ;
  (* 8. The engine's own report file is where each mutant's OUTCOME comes from — not
     stdout, not an exit code. It is read through the very adapters `report` already has. *)
  let outcomes =
    if Sys.file_exists report_path then
      if from = "mutaml" then load_mutaml report_path else load_generic report_path
    else []
  in
  (* 8a. THE JOIN — the engine's outcomes onto the catalogued sites. ONE key: the SITE.

     History, because it is the argument. The join was first [Filename.basename file = basename
     && line = line], consuming duplicates in list order and never refusing: two mutants on one
     line had their KILLED/SURVIVED verdicts stored against EACH OTHER, and a `mutant_kills`
     row — the one record in this schema that claims to name a killer — was written against a
     different FILE whenever two paths shared a basename. Round 3 added the site key but put
     the ENGINE'S OWN ID in front of it, and that arm carried the defect forward in a form no
     fixture could see: a generic report carries no id, so the adapter synthesised one from
     the record's position in the file, and against a catalogue whose ids happened to be
     numbered 1, 2 the "id" arm matched report line N to catalogue entry N. List order, wearing
     an id's clothes. The IDENTICAL report against a catalogue named m1, m2 fell through to the
     site key and was correct — which is why every named fixture passed.

     There is now no id arm. Per the IDENTITY DOCTRINE at the top of this file, an engine id is
     a COORDINATE of one engine run and the migration's property claim governs: identity is
     where the mutation is and what it replaces. What the report actually carries decides, and
     a field the report omits is not treated as equal — it is simply not discriminating.

     Where two catalogued sites survive that, the driver REFUSES. Taking the head of the list
     is a coin flip recorded as a fact, in a table whose whole purpose is to say which test
     proved what. *)
  let pending_sites = ref selections in
  let unmatched = ref 0 in
  let attempted = ref [] in
  let by_site (m : mutant) sel =
    sel.sel_site.s_line = m.line
    && same_path sel.sel_site.s_file m.file
    && (match m.m_cols with
       | Some (cs, ce) -> sel.sel_site.s_col_start = cs && sel.sel_site.s_col_end = ce
       | None -> true)
    && (match m.m_repl with Some r -> sel.sel_site.s_repl = r | None -> true)
    && (match m.m_occurrence with Some o -> sel.sel_site.s_occurrence = Some o | None -> true)
  in
  let refuse_ambiguous (m : mutant) candidates =
    Printf.eprintf
      "arch-mutants: the report entry for %s:%d (engine id %s, status %s) matches %d \
       catalogued mutant sites that are INDISTINGUISHABLE from what the report carries:\n"
      m.file m.line (engine_name_for_display m.m_name) (String.uppercase_ascii m.status)
      (List.length candidates) ;
    List.iter
      (fun sel ->
        Printf.eprintf "      %s (engine id %S, RUN-scoped)\n"
          (site_key_for_display (site_key sel.sel_site))
          (Engine_run_id.to_display_string sel.sel_site.s_engine_id))
      candidates ;
    Printf.eprintf
      "  The report carries no column span, replacement or anchor occurrence that tells these \
       sites apart, and an engine id is not consulted: it is a coordinate of one engine run, \
       not an identity, so joining on it is how a verdict came to be stored against the wrong \
       mutant in the first place. Taking the first candidate would pair this outcome with a \
       mutant chosen by LIST ORDER. Refusing instead. No run row was written for this entry \
       and the campaign is NOT complete.\n\
       What would make this joinable: a report that echoes the catalogue's column span, its \
       replacement text, or the anchor occurrence its mutation specification states.\n" ;
    ignore (finish 1 : 'a)
  in
  List.iter
    (fun (m : mutant) ->
      let consume sel =
        pending_sites := List.filter (fun s -> s != sel) !pending_sites ;
        attempted := (sel, m) :: !attempted
      in
      match List.filter (by_site m) !pending_sites with
      | [ sel ] -> consume sel
      | [] -> incr unmatched
      | _ :: _ :: _ as amb -> refuse_ambiguous m amb)
    outcomes ;
  let matched = List.rev !attempted in
  (* 8b. THREE populations, separated before anything is persisted. Each was previously
     folded into "attempted", and each fold destroyed a different fact.

     REFUSED (FR-031). The wrapper exited [refusal_exit_code]; its tests never ran. This is
     not an outcome, so it is not an attempt: no run row, no kill row, no status. It counts
     towards PENDING, which is exactly the schema's own encoding for "no verdict" — the
     ABSENCE of a `mutant_runs` row inside a campaign whose completed_at is NULL — and so
     needs no fifth engine_status value and no widening of a vocabulary the rest of the
     codebase depends on being closed.

     UNOBSERVED. The wrapper wrote no trace line for this mutant, so NOTHING is known about
     which tests ran. The old code substituted the PLANNED set here and recorded it as what
     executed; when that planned set happened to be a singleton it then wrote a
     `mutant_kills` row with attribution `singleton_executed_set`, naming a test nobody ever
     saw run — a fabricated attribution from the one table that exists to keep attribution
     honest. There is no defensible number to store for `executed_tests`, so again the
     honest record is the absence of the row.

     ATTEMPTED. A trace line exists, so the executed set is carried alongside the outcome as
     a plain [string list]. The lookup is gone from the three places downstream that used to
     redo it with a default, which is why it can no longer silently succeed. *)
  (* A refusal is 99 AND NO TRACE LINE. The wrapper writes its trace line last and every
     refusal path exits before reaching it, so the absence is the discriminator — and it is
     the second half of reserving 99 end to end. `scripts/mutaml-wrapper.sh` already remaps a
     test command's own 99 to 1, but a THIRD-PARTY wrapper cannot be made to, and the driver
     must not read a runner's legitimate 99 as "never attempted": that turns a real test
     failure into a mutant that can never be killed and a campaign that can never complete.

     It applies to the MUTAML path only, and that restriction is not caution: there REFUSED
     is INFERRED from a raw exit code, which is what makes 99 ambiguous. In a generic report
     the status string is written explicitly by whoever produced the file, and a driver that
     overrode an explicit REFUSED with a guess drawn from a trace line would be doing the
     very thing this whole finding is about. *)
  let refused_runs, engine_reported =
    List.partition
      (fun (sel, (m : mutant)) ->
        is_wrapper_refusal m.status
        && not (from = "mutaml" && Hashtbl.mem executed_by_id sel.sel_site.s_engine_id))
      matched
  in
  let reclassified_99 = ref 0 in
  let engine_reported =
    List.map
      (fun (sel, (m : mutant)) ->
        if is_wrapper_refusal m.status then (
          incr reclassified_99 ;
          Printf.eprintf
            "arch-mutants: %s:%d (engine id %s) carries the wrapper's refusal code, but the \
             wrapper WROTE A TRACE LINE for it — so its tests did run and this is the test \
             command's own exit status, not a refusal. Recording it as KILLED, which is what \
             a non-zero test run under a mutation means. Only a refusal leaves no trace \
             line.\n"
            sel.sel_site.s_file sel.sel_site.s_line
            (Engine_run_id.to_display_string sel.sel_site.s_engine_id) ;
          (sel, { m with status = MDb.status_to_string MDb.Killed }))
        else (sel, m))
      engine_reported
  in
  let unobserved_runs, attempted =
    List.partition_map
      (fun (sel, m) ->
        match Hashtbl.find_opt executed_by_id sel.sel_site.s_engine_id with
        | None -> Either.Left (sel, m)
        | Some executed -> Either.Right (sel, m, executed))
      engine_reported
  in
  (* A refusal whose report entry matched NO catalogued site used to reach [n_refused] by
     no path at all: refusals are partitioned out of [matched], and [matched] is what the
     partition runs over. Two real refusals were invisible that way. The count is therefore
     taken over the report entries the adapter produced — every refusal the wrapper made —
     while [refused_runs] stays the list of the ones that could be NAMED with a site. *)
  let unmatched_refused =
    List.length (List.filter (fun (m : mutant) -> is_wrapper_refusal m.status) outcomes)
    - List.length refused_runs - !reclassified_99
  in
  let n_refused = List.length refused_runs + unmatched_refused
  and n_unobserved = List.length unobserved_runs in
  (* 9. Persist one run row per ATTEMPTED mutant. A mutant with no row is PENDING by that
     absence — never SURVIVED. *)
  let killed = ref 0 and survived = ref 0 and timed_out = ref 0 and errored = ref 0 in
  let kills_written = ref 0 in
  List.iter
    (fun (sel, (m : mutant), executed) ->
      match classify_engine_status m.status with
      | Wrapper_refused ->
          (* Unreachable: refusals were partitioned out above. Spelled out rather than
             folded into a catch-all so that adding a fourth population cannot land here
             silently (FR-031). *)
          Printf.eprintf
            "arch-mutants: internal error — a refused mutant reached the persistence loop \
             for %s:%d\n"
            m.file m.line ;
          ignore (finish 2 : 'a)
      | Unrecognised_status _ ->
          Printf.eprintf
            "arch-mutants: %s reports status %S for %s:%d, which is not one of \
             KILLED|SURVIVED|TIMEOUT|ERROR. Refusing to guess — a mis-read status inverts \
             the verdict.\n"
            report_path m.status m.file m.line ;
          ignore (finish 2 : 'a)
      | Engine_status status ->
          (match status with
          | MDb.Killed -> incr killed
          | MDb.Survived -> incr survived
          | MDb.Timeout -> incr timed_out
          | MDb.Errored -> incr errored) ;
          Option.iter
            (fun mutant_id ->
              (try
                 MDb.insert_run db ~campaign_id ~mutant_id
                   (* RUN-SCOPED, recorded and MARKED as such: what the engine called this
                      thing in THIS invocation. The report's own declared name is preferred
                      over the catalogue's because it is the one that appears in the engine
                      output a reader will be holding; a synthesised report ordinal is not a
                      name and the type says so, so it falls back rather than being stored.
                      Nothing joins on this — see the IDENTITY DOCTRINE at the top. *)
                   ~engine_mutant_id:
                     (Some
                        (Option.value
                           ~default:(Engine_run_id.to_display_string sel.sel_site.s_engine_id)
                           (declared_name m.m_name)))
                   ~status ~provenance
                   ~intended:(List.length sel.sel_intended)
                   ~executed:(List.length executed)
                   ~superset:(executed_is_widened ~intended:sel.sel_intended ~executed)
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
            (Hashtbl.find_opt mutant_ids (site_key sel.sel_site)))
    attempted ;
  let catalogued = List.length selections in
  let n_attempted = List.length attempted in
  (* Refused and unobserved mutants are NOT attempted, so they are inside `pending` by
     arithmetic. The two extra conjuncts are not redundancy for its own sake: they state the
     rule the reviewer asked for directly, so a later change to how `pending` is computed
     cannot quietly stamp a campaign complete while a mutant was never tested or its
     executed set was never seen. *)
  let pending = catalogued - n_attempted in
  (* [!unmatched] belongs in this conjunction and was published only in the JSON. A run
     whose report entries matched NO catalogued site at all — a total join failure, measured
     at 2 of 2 — was stamped complete on the strength of `pending = 0`, which is trivially
     true when the outcomes never reached the sites. *)
  (* THE RECONCILIATION. Every conjunct above is arithmetic over this process's own
     counters, and those counters are incremented BEFORE the write. So the campaign could —
     and did — publish `survived: 1` for a row the database had rejected, with the exception
     caught by `prerr_endline` and `completed_at` stamped regardless. A survivor lost that way
     is indistinguishable from a survivor that never existed, which is the single conflation
     this whole design refuses.
     The fix is to ask the DATABASE, not the counters: the rows that exist must equal the
     mutants attempted. Anything less leaves `completed_at` NULL, which is precisely the
     schema's encoding for "partial" — and it is reported with BOTH numbers, because
     "0 of 1 persisted" is what an operator acts on and "a write failed" is not. *)
  let runs_persisted =
    try MDb.count_runs db ~campaign_id
    with MDb.Write_failed m ->
      prerr_endline ("arch-mutants: " ^ m) ;
      (* Unknown, and unknown must not read as agreement: -1 can equal no attempt count. *)
      -1
  in
  let reconciled = runs_persisted = n_attempted in
  if not reconciled then
    Printf.eprintf
      "arch-mutants: RECONCILIATION FAILED — %d run row(s) persisted against %d mutant(s) \
       attempted. The counters this campaign published were incremented before the writes, so \
       a verdict has been reported that reached no table. completed_at is NOT being stamped: \
       a campaign whose rows do not account for its attempts must read as PARTIAL, because a \
       survivor lost to a failed write is otherwise indistinguishable from a survivor that \
       was never there.\n"
      runs_persisted n_attempted ;
  let complete =
    (not refused) && engine_code = 0 && pending = 0 && n_refused = 0 && n_unobserved = 0
    && !unmatched = 0 && reconciled
  in
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
            ("rechecked_for_deleted_tests",
             `List
               (List.map
                  (fun (p : prior_mutant) ->
                    (* The full key, published: a reader who has to reconcile this list with
                       the `mutants` table needs the columns the table is keyed on, not a
                       file and a line that name two rows. *)
                    `Assoc
                      [ ("file", `String p.pk_file); ("line", `Int p.pk_line);
                        ("col_start", `Int p.pk_col_start); ("col_end", `Int p.pk_col_end);
                        ("replacement", `String p.pk_repl) ])
                  ds.ds_recheck));
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
             (* Read back from the database, not counted in memory. Published so a consumer
                can make the same comparison the completeness gate makes. *)
             ("run_rows_persisted", `Int runs_persisted);
             ("attempts_reconciled_with_rows", `Bool reconciled);
             ("mutants_pending", `Int pending);
             (* FR-031: the wrapper declined to run these mutants' tests, so they have no
                outcome of any kind. Never folded into killed/survived/errored. *)
             ("mutants_refused_by_wrapper", `Int n_refused);
             (* The wrapper wrote no trace line, so what ran is UNKNOWN. Reported as its own
                number rather than papered over with the planned set. *)
             ("mutants_unobserved_executed_set", `Int n_unobserved);
             ( "refused_by_wrapper",
               `List
                 (List.map
                    (fun (sel, _) ->
                      `Assoc
                        [ ( "engine_mutant_id",
                            `String (Engine_run_id.to_display_string sel.sel_site.s_engine_id) );
                          ("file", `String sel.sel_site.s_file);
                          ("line", `Int sel.sel_site.s_line) ])
                    refused_runs) );
             ( "unobserved_executed_set",
               `List
                 (List.map
                    (fun (sel, (m : mutant)) ->
                      `Assoc
                        [ ( "engine_mutant_id",
                            `String (Engine_run_id.to_display_string sel.sel_site.s_engine_id) );
                          ("file", `String sel.sel_site.s_file);
                          ("line", `Int sel.sel_site.s_line);
                          ("engine_status", `String (String.uppercase_ascii m.status));
                          (* FR-013: the key travels with engine_status here too. The
                             provenance describes the SELECTION, which was computed for this
                             mutant whether or not it was ever observed to run, so omitting
                             it would publish a status naked — the one thing FR-013 forbids. *)
                          ("selection_provenance", `String (MDb.provenance_to_string provenance));
                          (* Explicitly null, never the planned set: the planned set is what
                             SHOULD have run, and printing it here as `executed_tests` was
                             the defect. *)
                          ("executed_tests", `Null);
                          ("intended_tests",
                           `List (List.map (fun t -> `String t) sel.sel_intended));
                          ("note",
                           `String
                             "the wrapper wrote no trace line for this mutant, so no test is \
                              known to have run. No run row and no attribution were recorded, \
                              and the campaign is not complete") ])
                    unobserved_runs) );
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
                    (fun (sel, (m : mutant), executed) ->
                      `Assoc
                        [ ( "engine_mutant_id",
                            `String (Engine_run_id.to_display_string sel.sel_site.s_engine_id) );
                          ("file", `String sel.sel_site.s_file); ("line", `Int sel.sel_site.s_line);
                          ("function", match sel.sel_fn with Some f -> `String f | None -> `Null);
                          ("engine_status", `String (String.uppercase_ascii m.status));
                          (* FR-013: this key travels with engine_status, always. *)
                          ("selection_provenance", `String (MDb.provenance_to_string provenance));
                          ("intended_tests", `List (List.map (fun s -> `String s) sel.sel_intended));
                          ("executed_tests", `List (List.map (fun s -> `String s) executed));
                          ("executed_superset",
                           `Bool (executed_is_widened ~intended:sel.sel_intended ~executed));
                          (* Named, not just denied: FR-003 forbids invoking the engine
                             with a SUBSET, and a bare `false` cannot be acted on. *)
                          ("intended_tests_not_executed",
                           `List
                             (List.map (fun t -> `String t)
                                (missing_from_executed ~intended:sel.sel_intended ~executed))) ])
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
    if n_refused = 0 then
      print_endline
        "  • 0 mutant(s) REFUSED by the wrapper. What would have made this non-zero: the \
         wrapper exiting 99 — an unset MUTAML_MUTANT, a mutant it was never given, or a \
         selection file it could not read"
    else (
      Printf.printf
        "  • %d mutant(s) REFUSED by the wrapper (exit %d): their tests were NEVER RUN. \
         Not killed, not survived, not errored — no run row and no attribution was written \
         for any of them, and the campaign is NOT complete:\n"
        n_refused refusal_exit_code ;
      List.iter
        (fun (sel, _) -> Printf.printf "      %s:%d\n" sel.sel_site.s_file sel.sel_site.s_line)
        (take maxlist refused_runs)) ;
    if n_unobserved = 0 then
      print_endline
        "  • 0 mutant(s) with an UNOBSERVED executed set. What would have made this \
         non-zero: a mutant the engine reported an outcome for while the wrapper wrote no \
         trace line, so nothing could say which tests ran"
    else (
      Printf.printf
        "  • %d mutant(s) with an UNOBSERVED executed set: the engine reported an outcome \
         but the wrapper wrote NO trace line, so no test is known to have run. The planned \
         set is NOT substituted — that substitution is what once produced a per-test \
         attribution naming a test nobody saw run. No run row, no attribution, campaign \
         NOT complete:\n"
        n_unobserved ;
      List.iter
        (fun (sel, (m : mutant)) ->
          (* FR-013 again: a status is never rendered without its selection provenance. *)
          Printf.printf "      %-8s [%s] %s:%d (planned %d test(s), executed UNKNOWN)\n"
            (String.uppercase_ascii m.status)
            (MDb.provenance_to_string provenance)
            sel.sel_site.s_file sel.sel_site.s_line
            (List.length sel.sel_intended))
        (take maxlist unobserved_runs)) ;
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
      (fun (sel, (m : mutant), executed) ->
        Printf.printf "  • %-8s [%s]  %s:%d  in %s\n" (String.uppercase_ascii m.status)
          (MDb.provenance_to_string provenance) sel.sel_site.s_file sel.sel_site.s_line
          (match sel.sel_fn with Some f -> f | None -> "(unmapped — persisted, not dropped)") ;
        Printf.printf "      intended %d, executed %d%s\n" (List.length sel.sel_intended)
          (List.length executed)
          (match missing_from_executed ~intended:sel.sel_intended ~executed with
          | [] -> if executed_is_widened ~intended:sel.sel_intended ~executed then " (SUPERSET)" else ""
          | missing ->
              Printf.sprintf " — NOT A SUPERSET: %d intended test(s) did not run (%s)"
                (List.length missing) (String.concat ", " (take 5 missing))))
      (take maxlist attempted) ;
    if maxlist > 0 && n_attempted > maxlist then
      Printf.printf "  … and %d more (--max-list 0 for all)\n" (n_attempted - maxlist)) ;
  (* 3 = the engine REFUSED (FR-032, the callee declined to answer); 1 = the campaign ran but
     its rows do not account for its attempts, which must not be reported as success — a
     zero exit on an unreconciled campaign is exactly how a lost survivor stayed invisible. *)
  finish (if refused then 3 else if not reconciled then 1 else 0)

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
                         ("findings_total", `Int (List.length findings));
                         (* A campaign with no finding of any kind attempted NOTHING. Said
                            as its own key rather than left for a reader to infer from six
                            zeroes, because six zeroes is also what a campaign in which
                            nothing survived looks like, and those are not the same fact. *)
                         ("attempted_nothing", `Bool (findings = [])) ])
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
        if findings = [] then
          print_endline
            "  • this campaign ATTEMPTED NOTHING: it holds no run row and no catalogued \
             site, so every count above is zero by ABSENCE. That is not \"nothing \
             survived\" and must never be read as it. What would have made it non-zero: a \
             selection that was not narrowed away — a `--diff` range touching an indexed \
             function the catalogue has a mutant inside" ;
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
      let survivors, unmapped, errored, survivor_outcome =
        report t g mutants test_keys (opt "--repo" ".") fmt maxlist
      in
      let n_survivors = List.length survivors + List.length unmapped in
      (* The gate fails on a DEFECT LIST, and a mutant only lands on that list when its
         derived verdict is genuinely V_survived. Under `top_bounded` or `no_contract` the
         same engine status publishes as UNKNOWN — the tests that would have killed it may
         never have run — and failing a build on that is a false accusation against a test
         nobody gave the chance. The verdict is matched TOTALLY: a gate that silently
         declined to fire would be worse than one that over-fires, so each arm says which
         it is. *)
      if List.mem "--fail-on-survivors" args && n_survivors > 0 then (
        match MDb.published_verdict survivor_outcome with
        | MDb.V_survived ->
            Printf.eprintf "arch-mutants: FAIL — %d surviving mutant(s)\n" n_survivors ;
            exit 1
        | MDb.V_unknown | MDb.V_unknown_no_contract ->
            Printf.eprintf
              "arch-mutants: --fail-on-survivors did NOT fail, and here is why: the %d \
               mutant(s) the engine reported SURVIVED publish as %s under \
               selection_provenance %s — %s. Fix the selection (close the test cone, or \
               give the index a soundness contract) before treating this list as a defect \
               list.\n"
              n_survivors
              (MDb.verdict_to_string (MDb.published_verdict survivor_outcome))
              (MDb.provenance_to_string survivor_outcome.MDb.o_provenance)
              (MDb.provenance_caveat survivor_outcome.MDb.o_provenance)
        (* [report] derives this verdict from a SURVIVED status, so no other arm can be
           reached. They are spelled out rather than caught, because a catch-all here is
           what would let a later fifth verdict pass the gate unnoticed. *)
        | MDb.V_killed | MDb.V_error | MDb.V_pending ->
            die
              "arch-mutants: internal — a survivor list produced a verdict that is not a \
               survivor verdict") ;
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
