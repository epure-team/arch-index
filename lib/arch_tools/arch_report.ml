(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-report]'s single source of truth (roadmap 2.2, specs/reporting-and-integration.md
    FR-020).

    {1 Why this module exists at all}

    The spec asks for three artifacts — SARIF, HTML, JSON — and CHECK-5 asks that every finding in
    one appear in the other two {i with identical provenance}. The cheap way to satisfy a check
    like that is to build three renderings and then write three assertions comparing them. That
    test cannot fail for the right reason: three independently-built collections can be wrong in
    the same way, and the assertion compares two implementations of one mistake.

    So CHECK-5 is a {b construction} constraint here, not a verification one. {!collect} runs the
    queries once and returns a [report]; {!to_json}, {!to_sarif} and {!to_html} are total functions
    of that one value and share no query. Agreement between the three is then a property of the
    types rather than a property the test establishes — and the test still runs, because a
    guarantee nothing checks is a guarantee that expires quietly.

    This is the multi-channel shape of a defect this repository has shipped twice: [arch-rules]'
    JSON channel honest while its TEXT channel was not, then SARIF flattening five distinct
    verdicts into one [note] where JSON kept them apart. Both looked like formatting bugs and were
    single-source bugs.

    {1 The header}

    FR-021 requires the same header on all three artifacts. It carries {b every} verdict the tools
    emit, not a four-way bucketing — the spec's original four collapsed [UNKNOWN] (a cone escaping
    through a ⊤ edge) with [UNKNOWN_NO_CONTRACT] (an index that never marked ⊤ at all), and
    [NOT_COMPUTED] (an analysis that never ran) with [NO_SOURCE] (one that ran over nothing).
    Distinguishing those pairs is most of what this toolchain is for. *)

(** A verdict count. Every member is present on every report, zero included: a consumer must never
    have to decide whether a missing key means "none" or "this producer does not use that
    verdict". *)
let verdict_vocabulary =
  [ "PASS"; "VIOLATION"; "POSSIBLE"; "UNKNOWN"; "UNKNOWN_NO_CONTRACT"; "NO_SOURCE"; "NO_TARGET";
    "NOT_COMPUTED" ]

type producer = {
  p_name : string;
  p_version : string option;
  p_soundness_class : string;
      (** ADR-002: ['sound_with_top'] | ['heuristic'] | ['asserted']. Lives on [producer_runs], so
          a finding inherits it from the run that produced it rather than carrying its own copy —
          which is what makes FR-022 implementable with no new column. *)
  p_invocation_digest : string option;
}

type coverage = {
  c_language : string option;
  c_analysis : string;
  c_status : string;  (** ['covered'] | ['not_analysed'] | ['failed'] | ['partial'] *)
  c_detail : string option;
}

(** One finding, in the only representation any renderer sees.

    [f_id] is a stable identity {b derived from the content}, not a row id: CHECK-5 compares
    findings across three documents, and a row id is meaningless in SARIF and invisible in HTML.
    Deriving it from (kind, location, subject) means the same finding carries the same handle in
    all three, which is what "identical provenance" has to mean to be checkable. *)
type finding = {
  f_id : string;
  f_kind : string;  (** the analysis that produced it, e.g. ["dead_code"] *)
  f_message : string;
  f_location : string option;  (** ["file:line"], the repo's existing call-site spelling *)
  f_subject : string option;  (** the function or callee the finding is about *)
  f_producer : string option;
  f_soundness_class : string option;
      (** [None] when the table this finding came from records no [producer_run_id].

          That is not a gap to paper over with the first run in the table. A review demonstrated
          what [match producers with p :: _] does: it labels EVERY finding with whichever run
          sorted first, so a dead-code finding reported [producer=semgrep,
          soundness_class=heuristic] as soon as an importer existed — and the same line labels an
          imported heuristic finding [sound_with_top] when the indexer sorts first, which is the
          ordinary order.

          It also defeated the guarantee the ingest slice enforces structurally. That slice decides
          WHERE rows go; this decided provenance by WHICH ROW SORTED FIRST. The two did not
          compose, and neither was wrong alone. A finding with no recorded run is rendered
          unattributed, which is a fact; the alternative was a label that looked like one. *)
  f_verdict : string option;
}

type section = {
  s_analysis : string;
  s_status : string;
  s_findings : finding list;
      (** Empty is a legitimate, rendered state. FR-024: a section with no findings appears
          LABELLED AND EMPTY, never absent — a missing section and a clean one are the same
          picture to a reader, and this whole toolchain exists to keep "nothing found" apart from
          "nothing looked". *)
}

type t = {
  db_path : string;
  schema_version : string option;
  producers : producer list;
  coverage : coverage list;
  top_frontier : int option;
      (** A COUNT, never a result list: 286 356 edges on Octez against GitHub's 25 000-result
          cap. Per-rule witnesses belong in [codeFlows], not here. *)
  verdicts : (string * int) list;  (** every member of {!verdict_vocabulary}, zero included *)
  sections : section list;
}

let findings (r : t) = List.concat_map (fun s -> s.s_findings) r.sections

(* -------------------------------------------------------------------------- *)
(* collect — the ONE query pass                                               *)
(* -------------------------------------------------------------------------- *)

let q1 t sql =
  Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1 ~to_cells:Arch_db.Rows.c1 sql ()
  |> List.filter_map (function [ c ] -> Some (Arch_db.string_of_cell c) | _ -> None)

let q t ~shape ~to_cells sql =
  Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape ~to_cells sql ()
  |> List.map (List.map Arch_db.string_of_cell)

let opt = function "" -> None | s -> Some s

(* Every analysis this tool knows how to look for. An analysis absent from the index still gets a
   section, because FR-024's whole point is that a reader must be able to tell "we looked and found
   none" from "we never looked" — and an absent section says neither. *)
let known_analyses = [ ("dead_code", "dead_code_sites"); ("imported", "imported_findings") ]

let collect ~db_path (t : Arch_db.t) : t =
  let schema_version =
    if Arch_db.has_table t "comment_db_meta" then
      match q1 t "SELECT value FROM comment_db_meta WHERE key='schema_version'" with
      | [ v ] -> Some v
      | _ -> None
    else None
  in
  let producers =
    if not (Arch_db.has_table t "producer_runs") then []
    else
      q t ~shape:Arch_db.Rows.t4' ~to_cells:Arch_db.Rows.c4
        "SELECT producer, COALESCE(producer_version,''), COALESCE(soundness_class,'heuristic'), \
         COALESCE(invocation_digest,'') FROM producer_runs ORDER BY id"
      |> List.filter_map (function
           | [ n; v; sc; d ] ->
               Some { p_name = n; p_version = opt v; p_soundness_class = sc;
                      p_invocation_digest = opt d }
           | _ -> None)
  in
  let coverage =
    if not (Arch_db.has_table t "analysis_coverage") then []
    else
      q t ~shape:Arch_db.Rows.t4' ~to_cells:Arch_db.Rows.c4
        "SELECT COALESCE(language,''), analysis, status, COALESCE(detail,'') \
         FROM analysis_coverage ORDER BY analysis, language"
      |> List.filter_map (function
           | [ l; a; s; d ] ->
               Some { c_language = opt l; c_analysis = a; c_status = s; c_detail = opt d }
           | _ -> None)
  in
  let top_frontier =
    if Arch_db.has_table t "calls" && Arch_db.has_col t "calls" "kind" then
      match q1 t "SELECT CAST(count(*) AS TEXT) FROM calls WHERE kind='MAY_TOP'" with
      | [ n ] -> int_of_string_opt n
      | _ -> None
    else None
  in
  (* Verdict counts are ZERO here and that is honest, not a stub: no verdict-producing analysis
     writes its results into the database today — [arch-rules] evaluates in memory and prints. The
     header carries the full vocabulary at zero rather than omitting the section, so a reader sees
     "no verdicts recorded" instead of a report that looks like it has no rules to report on. *)
  let verdicts = List.map (fun v -> (v, 0)) verdict_vocabulary in
  let dead_code =
    if not (Arch_db.has_table t "dead_code_sites") then []
    else
      q t ~shape:Arch_db.Rows.t3' ~to_cells:Arch_db.Rows.c3
        "SELECT COALESCE(d.call_site,''), COALESCE(d.callee_name,''), COALESCE(f.name,'?') \
         FROM dead_code_sites d LEFT JOIN functions f ON d.function_id = f.id \
         ORDER BY d.call_site, d.callee_name"
      |> List.filter_map (function
           | [ site; callee; fn ] ->
               Some
                 { f_id = Printf.sprintf "dead_code|%s|%s" site callee;
                   f_kind = "dead_code";
                   f_message =
                     Printf.sprintf "call to %s in %s sits in a CFG-unreachable block" callee fn;
                   f_location = opt site;
                   f_subject = opt callee;
                   (* dead_code_sites carries no producer_run_id, so this finding's run is not
                      recorded and is therefore not known. *)
                   f_producer = None;
                   f_soundness_class = None;
                   f_verdict = None }
           | _ -> None)
  in
  let status_of analysis table =
    (* FOUR states, and an earlier version of this function had three because it wrote "covered"
       for the last one — claiming an analysis ran when nothing in the database says so.

         - an [analysis_coverage] row exists  -> believe it, whatever it says;
         - no row and the table is ABSENT     -> not_analysed: this index predates the analysis;
         - no row, table present, HAS rows    -> covered: it demonstrably produced something;
         - no row, table present, EMPTY       -> UNKNOWN. It may have run and found nothing, or
                                                 never run at all, and this database cannot tell
                                                 them apart.

       That last one is the whole subject of FR-003, and writing "covered" there is the failure it
       forbids: zero rows rendering as a clean result. [unknown] is not in
       [analysis_coverage.status]'s own vocabulary (covered | not_analysed | failed | partial)
       because it is not a statement about the ANALYSIS — it is a statement about what this
       report can determine, and inventing a coverage row would be asserting a fact nobody
       recorded. *)
    if not (Arch_db.has_table t table) then "not_analysed"
    else
      (* Across ALL languages, worst status wins. An earlier version took the FIRST row whose
         analysis matched and ignored [c_language] entirely, so an index with (ocaml, dead_code)
         = covered and (rust, dead_code) = failed reported `covered` — a partially-failed analysis
         rendered as clean, which is the one outcome this report exists to prevent.

         The order is deliberate and is not alphabetical: `failed` beats `partial` beats
         `not_analysed` beats `covered`, because a reader must be told the worst thing that
         happened, not the most common. *)
      let rank = function
        | "failed" -> 3
        | "partial" -> 2
        | "not_analysed" -> 1
        | _ -> 0
      in
      match
        List.filter (fun c -> c.c_analysis = analysis) coverage
        |> List.sort (fun a b -> compare (rank b.c_status) (rank a.c_status))
      with
      | c :: _ -> c.c_status
      | [] -> (
          match q1 t (Printf.sprintf "SELECT CAST(count(*) AS TEXT) FROM %s" table) with
          | [ "0" ] -> "unknown"
          | [ _ ] -> "covered"
          | _ -> "unknown")
  in
  (* Findings imported from a FOREIGN analyser (roadmap 2.3). Rendered here because the
     alternative was measured and is worse than absence: with imports present, the header listed
     `semgrep` and `gosec` as heuristic producers and every section showed no findings, so a
     reader saw two third-party tools having run and a clean report. An analysis that appears in
     the provenance and nowhere in the results is not a missing feature, it is a false clean --
     which is the exact reading FR-024 exists to prevent, arrived at through the INTERACTION of
     two slices neither of which is wrong alone.

     The soundness class comes from the finding's own producer run, not from the first one:
     several importers can coexist and a heuristic finding attributed to the sound producer would
     be the ADR-002 mislabel this table's design exists to make impossible. *)
  let imported =
    if not (Arch_db.has_table t "imported_findings") then []
    else
      q t ~shape:Arch_db.Rows.t6' ~to_cells:Arch_db.Rows.c6
        "SELECT f.rule_id, COALESCE(f.uri,''), COALESCE(CAST(f.start_line AS TEXT),''), \
         f.message, COALESCE(r.producer,'?'), COALESCE(r.soundness_class,'heuristic') \
         FROM imported_findings f LEFT JOIN producer_runs r ON f.producer_run_id = r.id \
         ORDER BY f.id"
      |> List.filter_map (function
           | [ rid; uri; line; msg; producer; sc ] ->
               let loc =
                 match (opt uri, opt line) with
                 | Some u, Some l -> Some (u ^ ":" ^ l)
                 | Some u, None -> Some u
                 | None, _ -> None
               in
               Some
                 { f_id =
                     Printf.sprintf "imported|%s|%s|%s" producer rid
                       (Option.value ~default:"-" loc);
                   f_kind = "imported";
                   f_message = msg;
                   f_location = loc;
                   f_subject = Some rid;
                   (* Imported findings DO record their run, so these are facts. *)
                   f_producer = Some producer;
                   f_soundness_class = Some sc;
                   f_verdict = None }
           | _ -> None)
  in
  let sections =
    List.map
      (fun (analysis, table) ->
        { s_analysis = analysis;
          s_status = status_of analysis table;
          s_findings =
            (match analysis with
            | "dead_code" -> dead_code
            | "imported" -> imported
            | _ -> []) })
      known_analyses
  in
  { db_path; schema_version; producers; coverage; top_frontier; verdicts; sections }

(* -------------------------------------------------------------------------- *)
(* The three renderings. Each is a TOTAL function of one [t] and issues no      *)
(* query of its own — that is what makes CHECK-5 a property of the types        *)
(* rather than something three assertions try to establish after the fact.      *)
(* -------------------------------------------------------------------------- *)

let header_json (r : t) =
  [ ("db_path", `String r.db_path);
    ( "schema_version",
      match r.schema_version with Some v -> `String v | None -> `Null );
    ( "producers",
      `List
        (List.map
           (fun p ->
             `Assoc
               [ ("producer", `String p.p_name);
                 ("producer_version", match p.p_version with Some v -> `String v | None -> `Null);
                 ("soundness_class", `String p.p_soundness_class);
                 ( "invocation_digest",
                   match p.p_invocation_digest with Some d -> `String d | None -> `Null ) ])
           r.producers) );
    ( "analysis_coverage",
      `List
        (List.map
           (fun c ->
             `Assoc
               [ ("language", match c.c_language with Some l -> `String l | None -> `Null);
                 ("analysis", `String c.c_analysis); ("status", `String c.c_status);
                 ("detail", match c.c_detail with Some d -> `String d | None -> `Null) ])
           r.coverage) );
    ("top_frontier", match r.top_frontier with Some n -> `Int n | None -> `Null);
    ("verdicts", `Assoc (List.map (fun (k, n) -> (k, `Int n)) r.verdicts)) ]

let finding_json (f : finding) =
  `Assoc
    [ ("id", `String f.f_id); ("kind", `String f.f_kind); ("message", `String f.f_message);
      ("location", match f.f_location with Some l -> `String l | None -> `Null);
      ("subject", match f.f_subject with Some s -> `String s | None -> `Null);
      ("producer", match f.f_producer with Some p -> `String p | None -> `Null);
      ( "soundness_class",
        match f.f_soundness_class with Some c -> `String c | None -> `Null );
      ("verdict", match f.f_verdict with Some v -> `String v | None -> `Null) ]

let to_json (r : t) : Yojson.Safe.t =
  `Assoc
    (header_json r
    @ [ ( "sections",
          `List
            (List.map
               (fun s ->
                 `Assoc
                   [ ("analysis", `String s.s_analysis); ("status", `String s.s_status);
                     ("finding_count", `Int (List.length s.s_findings));
                     ("findings", `List (List.map finding_json s.s_findings)) ])
               r.sections) ) ])

let to_sarif (r : t) : Yojson.Safe.t =
  let sarif_finding (f : finding) : Arch_sarif.finding =
    { rule_id = f.f_kind; level = Arch_sarif.Warning; message = f.f_message;
      verdict = f.f_verdict; soundness_class = f.f_soundness_class; soundness = None;
      top_reasons = [];
      (* [Arch_sarif] parses a label as ["name  (file)"] — the shape [Arch_graph.label] produces.
         An earlier version passed a bare ["file:line"], which has no such separator, so every
         finding degraded to a logical-only location and report.sarif carried ZERO
         physicalLocation: GitHub could not map a single one to a file. Emitting the shape the
         library documents is the fix; the line survives because [split_line] now reads a numeric
         suffix off the file part. *)
      locations =
        (match (f.f_subject, f.f_location) with
        | Some subj, Some loc -> [ Printf.sprintf "%s  (%s)" subj loc ]
        | None, Some loc -> [ Printf.sprintf "%s  (%s)" f.f_kind loc ]
        | Some subj, None -> [ subj ]
        | None, None -> []);
      detail_total = 1; code_flow = [] }
  in
  (* One run per SECTION, so each carries its own category. GitHub OVERWRITES a run sharing
     tool+category with a later one rather than merging them (behaviour change, July 2025), so a
     single category across analyses would silently keep only the last. [Arch_sarif.log] refuses
     duplicates outright, which is why this is safe to state rather than hope. *)
  Arch_sarif.log
    (List.map
       (fun s ->
         { Arch_sarif.producer = "arch-report";
           producer_version = None;
           category = "arch-report/" ^ s.s_analysis;
           findings = List.map sarif_finding s.s_findings;
           coverage =
             List.map
               (fun c ->
                 { Arch_sarif.language = c.c_language; analysis = c.c_analysis;
                   status = c.c_status; detail = c.c_detail })
               r.coverage;
           top_frontier = r.top_frontier;
           notifications =
             (* FR-024 in the SARIF channel: a section that ran over nothing says so as a
                notification rather than as an empty results array, which is indistinguishable
                from a clean run. *)
             (if s.s_status = "covered" then []
              else
                [ { Arch_sarif.language = None; analysis = s.s_analysis;
                    message =
                      Printf.sprintf "analysis %s: %s — this is NOT a clean result" s.s_analysis
                        s.s_status } ]);
           contract_ok = None; computed = Some (s.s_status = "covered");
           proved = None })
       r.sections)

let esc s =
  String.to_seq s
  |> Seq.fold_left
       (fun acc c ->
         acc
         ^
         match c with
         | '&' -> "&amp;"
         | '<' -> "&lt;"
         | '>' -> "&gt;"
         | '"' -> "&quot;"
         | c -> String.make 1 c)
       ""

let to_html (r : t) : string =
  let b = Buffer.create 4096 in
  let p fmt = Printf.ksprintf (Buffer.add_string b) fmt in
  (* Self-contained by FR-020: no external asset, so the file works as a CI artifact opened from
     disk with no network. *)
  p "<!doctype html><html><head><meta charset=\"utf-8\"><title>arch-report</title><style>\n\
     body{font:14px/1.5 system-ui,sans-serif;margin:2rem;max-width:60rem}\n\
     table{border-collapse:collapse;margin:.5rem 0}td,th{border:1px solid #ccc;padding:.25rem \
     .5rem;text-align:left}\n\
     .empty{color:#666;font-style:italic}.notrun{background:#fff3cd}\n\
     code{background:#f4f4f4;padding:0 .2rem}</style></head><body>\n";
  p "<h1>arch-report</h1><p><code>%s</code>" (esc r.db_path) ;
  (match r.schema_version with Some v -> p " &middot; schema %s" (esc v) | None -> ()) ;
  p "</p>\n<h2>Producers</h2>\n" ;
  if r.producers = [] then p "<p class=\"empty\">no producer_runs rows — provenance unknown</p>\n"
  else (
    p "<table><tr><th>producer</th><th>version</th><th>soundness</th></tr>\n" ;
    List.iter
      (fun pr ->
        p "<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n" (esc pr.p_name)
          (esc (Option.value ~default:"—" pr.p_version))
          (esc pr.p_soundness_class))
      r.producers ;
    p "</table>\n") ;
  p "<h2>Verdicts</h2>\n<table><tr>" ;
  List.iter (fun (k, _) -> p "<th>%s</th>" (esc k)) r.verdicts ;
  p "</tr><tr>" ;
  List.iter (fun (_, n) -> p "<td>%d</td>" n) r.verdicts ;
  p "</tr></table>\n" ;
  (* The coverage matrix, which the HTML channel did not render at all — so the one artifact a
     human opens was missing the per-(language, analysis) statuses the other two carry. FR-021
     asks for the SAME header on all three; a channel that silently drops part of it is the
     multi-channel defect this module's construction was meant to make impossible, surviving in
     the one place the shared type does not reach: the rendering itself. *)
  p "<h2>Coverage</h2>\n" ;
  if r.coverage = [] then
    p "<p class=\"empty\">no <code>analysis_coverage</code> rows — coverage is unrecorded, which \
       is not the same as complete</p>\n"
  else (
    p "<table><tr><th>language</th><th>analysis</th><th>status</th><th>detail</th></tr>\n" ;
    List.iter
      (fun c ->
        p "<tr%s><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"
          (if c.c_status = "covered" then "" else " class=\"notrun\"")
          (esc (Option.value ~default:"(all)" c.c_language))
          (esc c.c_analysis) (esc c.c_status)
          (esc (Option.value ~default:"—" c.c_detail)))
      r.coverage ;
    p "</table>\n") ;
  p "<h2>⊤ frontier</h2><p>%s</p>\n"
    (match r.top_frontier with
    | Some n -> Printf.sprintf "%d MAY_TOP edge(s)" n
    | None -> "<span class=\"empty\">not measured — no <code>calls.kind</code> in this index</span>") ;
  (* FR-024: every known analysis gets a section, labelled, whether or not it has findings. *)
  List.iter
    (fun s ->
      p "<h2 id=\"%s\"%s>%s <small>(%s)</small></h2>\n" (esc s.s_analysis)
        (if s.s_status = "covered" then "" else " class=\"notrun\"")
        (esc s.s_analysis) (esc s.s_status) ;
      if s.s_status <> "covered" then
        p "<p class=\"notrun\">status <code>%s</code> — this is NOT a clean result. An empty \
           list here means the analysis did not run, not that it found nothing.</p>\n"
          (esc s.s_status) ;
      if s.s_findings = [] then p "<p class=\"empty\">no findings</p>\n"
      else (
        p
          "<table><tr><th>id</th><th>location</th><th>message</th><th>producer</th>\
           <th>soundness</th></tr>\n" ;
        List.iter
          (fun f ->
            p "<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n"
              (esc f.f_id)
              (esc (Option.value ~default:"—" f.f_location))
              (esc f.f_message)
              (esc (Option.value ~default:"—" f.f_producer))
              (* An unrecorded class renders as an explicit "unattributed", never as a blank a
                 reader would take for "nothing special". *)
              (esc (Option.value ~default:"unattributed" f.f_soundness_class)))
          s.s_findings ;
        p "</table>\n"))
    r.sections ;
  p "</body></html>\n" ;
  Buffer.contents b
