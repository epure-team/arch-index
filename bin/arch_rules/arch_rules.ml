open Arch_tools
open Arch_rule_eval

let usage =
  {|arch-rules — architecture fitness functions over a sound call graph.

Usage: arch-rules <db> [rules-file] [--format text|md|json|sarif]
                  [--on-unknown warn|fail] [--on-possible fail|warn] [--on-vacuous fail|warn]
                  [--on-not-computed fail|warn]

Rule syntax (line-oriented, # comments, one statement per rule):
  rule "ui must not reach persistence"
    forbid reach from file:src/ui/** to file:lib/db/**
  rule "no entry point reaches the vulnerable symbol"
    forbid reach from exported:** to fn:Vuln.parse
  rule "only the api layer is exported"
    forbid exported outside file:lib/api/**
  rule "validate must not mutate global state"
    forbid effect from file:src/validate/** kind:GlobalVar
  rule "core must not declare a dep on the web framework"
    forbid dep from module:lib/core/** to module:Web.**
  rule "protocol entry points gain no new fatal origin"
    forbid origin from file:src/proto_alpha/**/main.ml form:assert,division allow-file:crash-allow.txt|}

let die msg = raise (Error msg)

let symbol = function
  | "VIOLATION" -> "FAIL"
  | "POSSIBLE" -> "FAIL?"
  | "UNKNOWN" | "UNKNOWN_NO_CONTRACT" -> "UNKNOWN"
  | "PASS" -> "pass"
  | "NOT_COMPUTED" -> "n/a"
  | "NO_SOURCE" | "NO_TARGET" -> "VACUOUS"
  | v -> v

(* ------------------------------------------------------------------ *)
(* --format sarif (roadmap 2.1)                                        *)
(* ------------------------------------------------------------------ *)

(* Roadmap 1.2 (ADR 002): [driver.name]/[driver.version]. The MAIN schema's provenance lives in
   [producer_runs] (one row per producer invocation); the FLAT schema's (arch-load, runner.ml)
   lives in [comment_db_meta] instead — see that table's own comment for why the two writers
   disagree. Tried in that order so a MAIN-schema DB that also happens to carry a stray
   [comment_db_meta] producer key (it should not, but nothing enforces that) still prefers its
   own authoritative table. Falls back to a fixed, honest default rather than an empty string:
   SARIF's [driver.name] is not optional, and "arch-index" is true of every index this repo's own
   pipeline writes even when neither provenance mechanism was populated (a pre-1.2 index). *)
let producer_info (t : Arch_db.t) =
  let of_producer_runs () =
    if t.Arch_db.schema = Arch_db.Main && Arch_db.has_table t "producer_runs" then
      match
        Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t2' ~to_cells:Arch_db.Rows.c2
          "SELECT producer, producer_version FROM producer_runs ORDER BY id DESC LIMIT 1" ()
      with
      | [ [ p; v ] ] -> (
          match Arch_db.string_of_cell p with
          | "" -> None
          | producer -> Some (producer, match Arch_db.string_of_cell v with "" -> None | s -> Some s))
      | _ -> None
    else None
  in
  match of_producer_runs () with
  | Some pv -> pv
  | None -> (
      match Arch_db.meta t "producer" with
      | Some p -> (p, Arch_db.meta t "producer_version")
      | None -> ("arch-index", None))

(* Reads the ADR-002 soundness class the same two places {!producer_info} reads provenance from
   (MAIN's [producer_runs], FLAT's [comment_db_meta]) — but WITHOUT that function's fallthrough:
   [producer_info] tries [producer_runs] first and falls through to [comment_db_meta] when it
   yields no row; this function does not — on MAIN with a [producer_runs] table present, a query
   that finds no row (or an empty [soundness_class] cell) returns [None] directly, never checking
   [comment_db_meta]. Latent today: no in-repo MAIN producer writes [soundness_class] to
   [comment_db_meta], so the gap has never been observed to lose a real value — but if one ever
   does, this reads as "no soundness class" rather than falling back the way [producer_info]
   would. Every [arch-load] DB (FLAT) carries this key unconditionally (see
   [bin/arch_load/arch_load.ml]'s own comment), and the docs advertise
   [properties.soundness_class] for FR-022 filtering; a hardcoded [None] here would silently
   defeat that filter on every real index. [None] otherwise only for a pre-1.2 MAIN index with
   neither source populated. *)
let soundness_class_info (t : Arch_db.t) =
  if t.Arch_db.schema = Arch_db.Main && Arch_db.has_table t "producer_runs" then
    match
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1 ~to_cells:Arch_db.Rows.c1
        "SELECT soundness_class FROM producer_runs ORDER BY id DESC LIMIT 1" ()
    with
    | [ [ s ] ] -> ( match Arch_db.string_of_cell s with "" -> None | s -> Some s)
    | _ -> None
  else Arch_db.meta t "soundness_class"

(* Roadmap 1.3's coverage matrix, read straight off [analysis_coverage] — absent on any DB
   predating that roadmap item, in which case this is [[]] and the run simply carries no
   coverage/notifications, never a fabricated "covered" claim. *)
let coverage_rows (t : Arch_db.t) : Arch_sarif.coverage_row list =
  if not (Arch_db.has_table t "analysis_coverage") then []
  else
    Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t4' ~to_cells:Arch_db.Rows.c4
      "SELECT language, analysis, status, detail FROM analysis_coverage" ()
    |> List.filter_map (fun row ->
           match row with
           | [ lang; analysis; status; detail ] ->
               let opt c = match Arch_db.string_of_cell c with "" -> None | s -> Some s in
               Some
                 { Arch_sarif.language = opt lang; analysis = Arch_db.string_of_cell analysis;
                   status = Arch_db.string_of_cell status; detail = opt detail }
           | _ -> None)


let cli_main args =
  let opt name default =
    let rec go = function
      | a :: v :: _ when a = name -> v
      | _ :: tl -> go tl
      | [] -> default
    in
    go args
  in
  let positional = ref [] in
  let rec strip = function
    | a :: _ :: tl when String.length a > 2 && String.sub a 0 2 = "--" -> strip tl
    | a :: tl ->
        positional := a :: !positional ;
        strip tl
    | [] -> ()
  in
  strip args ;
  let positional = List.rev !positional in
  let db_path, rules_path =
    match positional with
    | [ d ] -> (d, "arch-rules.txt")
    | d :: r :: _ -> (d, r)
    | [] ->
        prerr_endline usage ;
        exit 2
  in
  let fmt = opt "--format" "text" in
  (* A typo'd `--format` used to fall through to the text/md renderer silently — exactly the
     `--on-possible fial`-style footgun the policy flags below are guarded against, but worse: a
     CI pipeline piping this straight into a SARIF or JSON consumer would get a human-readable
     report instead, which the consumer either chokes on or (worse) silently ignores. Refuse
     loudly instead of guessing. *)
  (if fmt <> "text" && fmt <> "md" && fmt <> "json" && fmt <> "sarif" then
     die (Printf.sprintf "arch-rules: --format takes 'text', 'md', 'json' or 'sarif', got %S" fmt)) ;
  (* A misspelled policy used to be read as "not fail" and silently disabled the gate:
     `--on-possible fial` turned a failing rule green. A policy flag that can be typo'd into
     permissiveness is worse than no flag. *)
  let policy name default =
    let v = opt name default in
    if v <> "fail" && v <> "warn" then
      die (Printf.sprintf "arch-rules: %s takes 'fail' or 'warn', got %S" name v) ;
    v
  in
  let on_unknown = policy "--on-unknown" "warn" in
  let on_possible = policy "--on-possible" "fail" in
  let on_vacuous = policy "--on-vacuous" "fail" in
  (* NOT_COMPUTED defaults to FAIL, unlike UNKNOWN. They are not the same thing: UNKNOWN is an
     analysis result (the cone escapes, so nothing is proved), while NOT_COMPUTED means the rule
     was never evaluated — the index carries no effects or module_deps data at all. A rule that
     silently reads "n/a" forever is indistinguishable from a rule that passes, and it is the
     one case the author can always fix (populate the data, or delete the rule). *)
  let on_not_computed = policy "--on-not-computed" "fail" in
  let t =
    try Arch_db.open_ro db_path
    with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-rules: " ^ m)
  in
  let contract_ok, results = evaluate_file t rules_path in
  let g = Arch_graph.load t in
  (* UNKNOWN is fail-OPEN by default: a rule that blocks every PR whose cone happens to touch a
     callback teaches people to delete the rule, which leaves them worse off than a warning. *)
  (* EXHAUSTIVE over [Arch_report.verdict], not a disjunction of string equalities.
     Until 2026-09-06 this was a chain of [v = "..."] tests, so a verdict absent
     from the chain evaluated to [false] and passed the gate in silence, and the
     census assertion below that dies on an uncounted verdict covers only the
     DISPLAY path. Coverage happened to be complete -- measured before the change,
     seven named of an eight-member vocabulary, the omitted one being [PASS] --
     but nothing kept it so. A ninth constructor is now a compile error here.

     An unparseable verdict string dies loudly rather than defaulting to "does
     not fail": ambiguity is absence of proof, and the safe default for a GATE is
     to refuse, not to pass. *)
  let failing v =
    match verdict_of_string v with
    | None ->
        die
          (Printf.sprintf
             "verdict %S is outside the published vocabulary [%s]. Refusing rather than treating \
              it as passing: an unrecognised verdict must not silently satisfy the gate."
             v
             (String.concat "; " verdict_vocabulary))
    | Some Pass -> false
    | Some Violation -> true
    | Some Possible -> on_possible = "fail"
    | Some (Unknown | Unknown_no_contract) -> on_unknown = "fail"
    | Some (No_source | No_target) -> on_vacuous = "fail"
    | Some Not_computed -> on_not_computed = "fail"
  in
  let failed_names = List.filter_map (fun r -> if failing r.verdict then Some r.rule else None) results in
  let count_verdicts vs = List.length (List.filter (fun r -> List.mem r.verdict vs) results) in
  (* The VERDICT census. These seven counts PARTITION the rules — every rule has exactly one
     verdict, and `census` below is asserted to sum to the rule count — which is what makes the
     summary line readable as a whole. `failing` is a different kind of number entirely: it is a
     policy-driven aggregate that OVERLAPS six of the seven, so the two are reported on separate
     lines and never added together. See the summary block near the end of this file.

     UNKNOWN and UNKNOWN_NO_CONTRACT are counted apart, not merged. They have different causes and
     different fixes: the first means the source cone escaped through a ⊤ edge (a real analysis
     result — the fix is a better producer, or roadmap 3.7); the second means the index was never
     ⊤-marked at all, so NOTHING was ruled out for any rule (the fix is to rebuild with a
     contract-stamping backend). A single line reading "N UNKNOWN (the cone escapes through a ⊤
     edge)" is simply false for the second. *)
  let proved = count_verdicts [ "PASS" ] in
  let violations = count_verdicts [ "VIOLATION" ] in
  let possible = count_verdicts [ "POSSIBLE" ] in
  let unknown_escaping = count_verdicts [ "UNKNOWN" ] in
  let unknown_no_contract = count_verdicts [ "UNKNOWN_NO_CONTRACT" ] in
  (* Retained as the UNION for the JSON field of the same name, whose meaning predates this split
     and which consumers already read. Never used in the text census, where it would double-count
     against `unknown_no_contract`. *)
  let unknown = unknown_escaping + unknown_no_contract in
  (* NO_SOURCE and NO_TARGET stay merged, unlike the two UNKNOWNs: they are the SAME failure with
     the same fix — a selector that matches nothing — and the per-rule note already names which of
     the two selectors it was. *)
  let vacuous = count_verdicts [ "NO_SOURCE"; "NO_TARGET" ] in
  let not_computed = count_verdicts [ "NOT_COMPUTED" ] in
  (* arch-rules never refuses at the process level (unlike arch-impact's exit 3) — an
     un-⊤-marked or data-less index degrades individual rules to UNKNOWN_NO_CONTRACT /
     NOT_COMPUTED verdicts instead, which the fail-open/fail-closed policy flags above already
     govern. So `verdict` here only ever takes "pass" or "fail", mirroring the exit code
     computed below (line ~464), never "refused". *)
  let verdict = if failed_names <> [] then "fail" else "pass" in
  (* The VERDICT census, as name/count pairs for the text and `md` summary lines. Defined — and
     checked — ABOVE the format split on purpose: the partition claim is a property of the
     verdicts, not of the renderer, and the JSON object below prints the same seven numbers. Left
     inside the text branch it left `--format json` unguarded, where an unknown verdict would be
     under-counted silently AND `failing` would treat it as not-failing: fail-open in the one
     channel a gate actually reads. *)
  let census =
    [ ("proved", proved); ("violation", violations); ("possible", possible);
      ("unknown", unknown_escaping); ("unknown-no-contract", unknown_no_contract);
      ("vacuous", vacuous); ("not-computed", not_computed) ]
  in
  (* The partition claim, checked rather than asserted in prose: if a verdict string ever escapes
     `census`, this refuses to print a summary that silently loses it. *)
  let counted = List.fold_left (fun a (_, n) -> a + n) 0 census in
  if counted <> List.length results then
    die
      (Printf.sprintf
         "arch-rules: internal error — the summary census covers %d of %d rules. A verdict the \
          summary does not know about would be silently dropped from the line; refusing to print \
          it."
         counted (List.length results)) ;
  (if fmt = "json" then
     print_endline
       (Yojson.Safe.pretty_to_string
          (`Assoc
            [ ("computed", `Bool true);
              ("contract_ok", `Bool contract_ok);
              ("verdict", `String verdict);
              (* `failing` is the GATE: policy-driven, and it overlaps every census field below
                 except `proved`. The seven census fields — proved, violations, possible,
                 unknown_escaping, unknown_no_contract, vacuous, not_computed — partition the
                 rules and sum to the length of `results`. Do not add `failing` to them.

                 `unknown` is kept as the UNION unknown_escaping + unknown_no_contract, because
                 that is what it has always meant and gates read it. It is the one field here that
                 is redundant with two others; the split ones are the honest pair. *)
              ("failing", `Int (List.length failed_names));
              ("proved", `Int proved);
              ("violations", `Int violations);
              ("possible", `Int possible);
              ("unknown", `Int unknown);
              ("unknown_escaping", `Int unknown_escaping);
              ("unknown_no_contract", `Int unknown_no_contract);
              ("vacuous", `Int vacuous);
              ("not_computed", `Int not_computed);
              ( "results",
                `List
                  (List.mapi
                     (fun ordinal r ->
                       `Assoc
                         ([ ("ordinal", `Int (ordinal + 1));
                           ("rule", `String r.rule); ("kind", `String r.kind);
                           ("verdict", `String r.verdict);
                           ("detail", `List (List.map (fun d -> `String d) r.detail));
                           ("detail_total", `Int r.detail_total);
                           ("witness", `List (List.map (fun w -> `String w) r.witness));
                           ("top_reasons", `List (List.map (fun tr -> `String tr) r.top_reasons));
                           ("origin_contexts", `List r.origin_contexts);
                           ("context_total", `Int r.context_total);
                           ("context_omitted", `Int r.context_omitted);
                           ("note", (match r.note with Some n -> `String n | None -> `Null)) ]
                         @ (match (r.sizes, r.kind) with
                           (* `exported` and `dep` size their SOURCE population only; neither has
                              a target population a number could describe. *)
                           | Some (sn, _), ("exported" | "dep") -> [ ("source_size", `Int sn) ]
                           | Some (sn, tn), _ ->
                               [ ("source_size", `Int sn); ("target_size", `Int tn) ]
                           | None, _ -> [])
                         @ (if r.exact then [ ("exact", `Bool true) ] else [])))
                     results) );
              ("failed", `List (List.map (fun n -> `String n) failed_names)) ]))
   else if fmt = "sarif" then (
     (* One `run`, category "arch-index/rules": every result this invocation produced is a
        `forbid ...` rule verdict, a single (producer, analysis) pair in roadmap 2.1's sense.
        `arch-report` (2.2), which reuses Arch_sarif, is what emits several runs with distinct
        categories in one log — this binary only ever has the one. *)
     let producer, producer_version = producer_info t in
     let soundness_class = soundness_class_info t in
     let level_of = function
       | "VIOLATION" -> Arch_sarif.Error
       | "POSSIBLE" -> Arch_sarif.Warning
       (* UNKNOWN, UNKNOWN_NO_CONTRACT, NOT_COMPUTED, NO_SOURCE, NO_TARGET: none of these is a
          proof of anything, but none is silence either — FR-024's discipline applied to a
          single rule's own verdict, not just to a whole language's coverage. `note` carries
          which of the five it is. *)
       | _ -> Arch_sarif.Note
     in
     let message_of r =
       let base = Printf.sprintf "%s [%s]: %s" r.rule r.kind r.verdict in
       let with_note = match r.note with Some n -> base ^ " — " ^ n | None -> base in
       (* `dep` and `effect` verdicts carry their evidence as prose rows in `detail`, and
          `finding_of` (below) deliberately keeps that prose OUT of `locations` — it is not a
          display label, and stuffing it in there fabricates a bogus SARIF location (H1, round-3
          review). `message.text` is therefore the ONLY channel left for that evidence, so it must
          appear even when a NOTE is also present — `dep`'s non-vacuous branch always attaches a
          fixed advisory note ("declared-dependency check: ..."), and without this the note would
          silently replace the evidence instead of accompanying it. `reach`/`exported` need no
          such override: their `detail` is already the SARIF `locations` list, and their notes
          are the rarer case (an overlap or a vacuity explanation) where the note text alone is
          already the whole story. *)
       match r.kind with
       | ("dep" | "effect") when r.detail <> [] -> with_note ^ " — " ^ String.concat ", " r.detail
       | _ -> ( match r.note with Some _ -> with_note | None -> if r.detail = [] then with_note else with_note ^ " — " ^ String.concat ", " r.detail)
     in
     let finding_of r : Arch_sarif.finding =
       { rule_id = r.rule; level = level_of r.verdict; message = message_of r;
         verdict = Some r.verdict;
         (* The ADR-002 class of the INDEX this verdict was computed against (heuristic /
            sound_with_top / asserted), not a per-finding ingestion fact — `arch-rules` never
            ingests a heuristic fact itself (that is roadmap 2.3's job, where a future SARIF-in
            adapter constructs findings with a class of its own choosing). Every finding from
            THIS binary shares the one index's class, read once above. *)
         soundness_class;
         (* UNKNOWN and UNKNOWN_NO_CONTRACT are NOT the same soundness gap and must not collapse
            onto one value (arch_rules.ml's own `census` above draws exactly this line): UNKNOWN
            means this cone's own witness escaped through a real ⊤ edge; UNKNOWN_NO_CONTRACT
            means the whole index was never ⊤-marked, so nothing was proved for ANY rule. A SARIF
            consumer reading `properties.soundness` needs the same distinction the JSON channel
            already gives it. *)
         soundness =
           (match r.verdict with
           | "UNKNOWN" -> Some "unknown_top"
           | "UNKNOWN_NO_CONTRACT" -> Some "no_contract"
           | _ -> None);
         top_reasons = r.top_reasons;
         (* `locations` MUST be display labels from `Arch_graph.label` (see
            `Arch_sarif.finding.locations`'s doc comment) — `split_label` parses them on that
            contract, and a mismatch fabricates a bogus `physicalLocation`. Only `reach` and
            `exported` build `detail` that way (`List.map lbl ...` above); `dep`'s detail rows are
            "A --kind--> B  (line N)" prose and `effect`'s are "name KIND VALUE" prose — neither
            is a label, and `dep`'s in particular contains the exact "  (" separator followed by a
            LINE NUMBER, which `split_label` would parse as a file name. Those two kinds carry
            their evidence in `message` only (`message_of` above already appends `detail` there
            when `note` is `None`); `locations` stays empty for them rather than fabricating a
            `uri` that names no real file. *)
         locations = (match r.kind with "reach" | "exported" -> r.detail | _ -> []);
         detail_total = r.detail_total; code_flow = r.witness }
     in
     let findings =
       (* "one result per rule verdict that is not PASS" (roadmap 2.1) — a PASS is a proof, not a
          finding, and putting proofs in the same list as violations is what CodeQL-style tools
          do that this repo's own design explicitly rejects. *)
       List.filter_map (fun r -> if r.verdict = "PASS" then None else Some (finding_of r)) results
     in
     let top_frontier = Arch_graph.SM.fold (fun _ n acc -> acc + n) g.tops 0 in
     let coverage = coverage_rows t in
     let notifications =
       List.filter_map
         (fun (c : Arch_sarif.coverage_row) ->
           if c.status = "not_analysed" then
             Some
               { Arch_sarif.language = c.language; analysis = c.analysis;
                 message =
                   Printf.sprintf "%s: not analysed%s" c.analysis
                     (match c.language with Some l -> " for language " ^ l | None -> "") }
           else None)
         coverage
     in
     let run : Arch_sarif.run =
       { producer; producer_version; category = "arch-index/rules"; findings; coverage;
         top_frontier = Some top_frontier; notifications;
         (* Mirrors the `--format json` channel's own top-level `contract_ok`/`computed`/`proved`
            fields (see above) — without these, an all-PASS run and a run that evaluated nothing
            both produce a document with an empty `results` list and no way to tell them apart. *)
         contract_ok = Some contract_ok; computed = Some true; proved = Some proved }
     in
     print_endline (Arch_sarif.to_string [ run ]))
   else
     let md = fmt = "md" in
     print_endline (if md then "# Architecture rules" else "== Architecture rules") ;
     List.iter
       (fun r ->
         let tag = symbol r.verdict in
         print_endline
           (if md then Printf.sprintf "- **%s** — %s" tag r.rule
            else Printf.sprintf "[%s] %s" (Printf.sprintf "%*s%*s" ((7 + String.length tag) / 2) tag
                                             (7 - ((7 + String.length tag) / 2)) "") r.rule) ;
         List.iter (fun d -> print_endline (if md then "    - " ^ d else "           " ^ d)) r.detail ;
         (if r.witness <> [] then
            print_endline
              (if md then "    - witness: " ^ String.concat " → " r.witness
               else "           witness: " ^ String.concat " -> " r.witness)) ;
         match r.note with
         | Some n -> print_endline (if md then "    > " ^ n else "           note: " ^ n)
         | None -> ())
       results ;
     (* TWO lines, because there are two different questions and one number cannot answer both.

        Line 1 is the VERDICT: what the analysis found. Its seven counts partition the rules — every
        rule has exactly one verdict — so the line can be read as a whole and the parts add up to
        the total. It is unconditional: a state that only appears when non-zero is a state a reader
        cannot distinguish from a state the tool does not have, and "0 proved" is the single most
        important thing this summary can say.

        Line 2 is the GATE: what the POLICY did with those verdicts. `failing` is not a verdict —
        it is an aggregate over VIOLATION, POSSIBLE, NO_SOURCE, NO_TARGET, NOT_COMPUTED and
        conditionally the two UNKNOWNs, so it OVERLAPS six of the seven census counts. Printing it
        inside line 1 made "4 rule(s), 1 proved, 3 failing, 1 UNKNOWN" sum to 5 over 4 rules. It
        also has to state the policy actually in force: the previous text said "fail-open by
        default" to an operator who had just passed --on-unknown fail, which is a newly-written
        sentence that is false for the run it annotates — the exact defect class this summary
        exists to fix.

        specs/qualified-unit-resolution.md §10.5: "a verdict with N states must be reported with N
        numbers ... Report 1 proved / 3 UNKNOWN / 0 violations". That asks for `violations`, the
        verdict — not `failing`, the gate. Both are here, on the line each belongs to. *)
     let nf = List.length failed_names in
     (* In `md` the two lines are bullets: consecutive plain lines would be reflowed into one
        paragraph, which would put the census and the gate back on a single line — the exact
        conflation this split exists to undo. *)
     let bullet = if md then "- " else "" and sub = if md then "  - " else "  " in
     print_endline "" ;
     print_endline
       (Printf.sprintf "%s%d rule(s): %s" bullet (List.length results)
          (String.concat ", " (List.map (fun (n, c) -> Printf.sprintf "%d %s" c n) census))) ;
     (* Every state the flags govern, with the value actually in force — no defaults quoted, and
        no claim about fail-open that the current invocation contradicts. VIOLATION is listed as
        `always` because no flag can open it. *)
     print_endline
       (Printf.sprintf
          "%sgate: %d failing — violation=always possible=%s unknown=%s vacuous=%s \
           not-computed=%s"
          bullet nf on_possible on_unknown on_vacuous on_not_computed) ;
     (* The causes, once each, only for states actually present. They are per-STATE and must not be
        shared: for UNKNOWN_NO_CONTRACT no cone escaped anywhere — the index was never ⊤-marked, so
        no rule on it could have been proved regardless. *)
     List.iter
       (fun (n, msg) -> if n > 0 then print_endline (sub ^ msg))
       [ ( unknown_escaping,
           "unknown: the source cone reaches a ⊤ edge — no path was found and none can be ruled \
            out either. Not proved." );
         ( unknown_no_contract,
           "unknown-no-contract: this index is not ⊤-marked, so 'no path' is not a proof for ANY \
            rule on it — a dropped dynamic edge is indistinguishable from an absent one. Rebuild \
            with a contract-stamping backend." );
         (vacuous, "vacuous: a selector matched nothing — the rule cannot fail, so it proves nothing.");
         ( not_computed,
           "not-computed: the index carries no data for that rule form — it was never checked." ) ]) ;
  exit (if List.exists (fun r -> failing r.verdict) results then 1 else 0)

(* The [open_ro] handler inside [main] covers exactly one call. A
   {!Arch_tools.Arch_db.Refused} raised by a LATER query — the schema-drift backstop in
   [Arch_db.ok] fires at any of them — escaped this binary altogether and was reported by
   OCaml's uncaught-exception path: [Fatal error: exception
   Arch_tools.Arch_db.Refused("this index predates column exposed …")], exit 2.

   Exit 2 is kept ON PURPOSE, and this is the one place it would be tempting to change.
   docs/fitness-functions.md states that arch-rules has no process-level sound-refusal
   path (no exit 3), and this tool already aborts at 2 for its own refusal-shaped
   conditions — the [Origin] evaluator's two vocabulary checks ([channel:] naming a
   channel this index does not contain, [form:] naming a form its schema does not
   declare) both reach [die], which exits 2. Giving ONE refusal cause exit 3 while its
   siblings keep 2 would make this tool's exit vocabulary incoherent and break that
   documented contract. Only the rendering changes here. *)


let () =
  try cli_main (List.tl (Array.to_list Sys.argv))
  with Error m ->
    prerr_endline m ;
    exit 2
  | Arch_db.Refused m | Arch_db.Broken m ->
    prerr_endline ("arch-rules: " ^ m) ;
    exit 2
