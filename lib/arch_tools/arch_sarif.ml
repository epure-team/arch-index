(** SARIF 2.1.0 writer — roadmap 2.1.

    Shared by [arch-rules --format sarif] and, later, [arch-report]'s [report.sarif]
    (roadmap 2.2), which is why this lives in [lib/arch_tools] rather than in a binary: 2.2
    reuses this module rather than reimplementing SARIF emission from scratch.

    {1 Design decisions this module encodes}

    - {b One [run] per (producer, analysis) pair, never one per producer alone.} GitHub stopped
      merging SARIF runs that share [tool.driver.name] + [runs[].properties.category] in a single
      upload as of July 2025 — a second upload with the same pair now OVERWRITES the first rather
      than merging. [category] (mirrored into [automationDetails.id]) is therefore a REQUIRED,
      caller-supplied field, not an afterthought: a caller emitting two analyses from one
      producer (e.g. [arch-index/callgraph] and [arch-index/effects]) must give them distinct
      categories or the second clobbers the first on GitHub's side. See {!run}.

    - {b The ⊤ frontier is not a result list.} It is 286k+ edges on a corpus like Octez, and
      GitHub caps a run at 25 000 results (displays 5 000). Frontier totals go in
      [run.properties.top_frontier]; per-rule witnesses (roadmap 1.5) go in [codeFlows] on the
      individual result they belong to.

    - {b A [heuristic] fact says so in its own properties bag.} [soundness_class] on a finding
      carries the ADR-002 vocabulary verbatim so a SARIF consumer can filter without re-deriving
      it (spec FR-022).

    - {b [NOT_ANALYSED] is a notification, never silence} (spec FR-024). A language with no
      adapter becomes a [toolExecutionNotifications] entry on the run, not an absent section. *)

type level = Error | Warning | Note

let level_to_string = function Error -> "error" | Warning -> "warning" | Note -> "note"

(** One SARIF [result]. [rule_id] is the [arch-rules] rule name (or, from a future SARIF-in
    producer, its own rule id) — {b not** the rule's human title; SARIF's [ruleId] is a stable
    key, and the message carries the prose.

    [locations] are display labels as produced by {!Arch_graph.label} — ["name  (file)"] when a
    file is known, bare ["name"] otherwise. This module does the best it can with what
    [arch-rules] actually has today (no line numbers on a rule verdict, only a function/file
    pair), so a location here becomes a SARIF [logicalLocations] entry always, and a
    [physicalLocation] additionally whenever a file could be parsed out of the label. A future
    producer with real line numbers extends {!location_of_label}'s caller, not this shape.

    [code_flow] is the witness path (source-to-target order) from roadmap 1.5, rendered as a
    SARIF [codeFlow] with one thread flow location per step. *)
type finding = {
  rule_id : string;
  level : level;
  message : string;
  soundness_class : string option;  (** ADR-002 vocabulary, e.g. ["heuristic"] *)
  soundness_unknown_top : bool;
      (** Set for a verdict that stopped at an unresolvable (⊤) edge: stamps
          [properties.soundness = "unknown_top"] (spec FR-022 / roadmap 1.4). *)
  top_reasons : string list;
      (** The ⊤-anchor taxonomy vocabulary (roadmap 1.4) for the escaping edge(s) this
          finding's cone hit, when known. [[]] when the verdict carries no specific reason
          (e.g. [UNKNOWN_NO_CONTRACT], where the whole index was never ⊤-marked, not one edge). *)
  locations : string list;  (** Primary location(s), as display labels (see above). *)
  code_flow : string list;  (** Witness path, source-to-target order, as display labels. *)
}

(** One row of the [analysis_coverage] matrix (roadmap 1.3), destined for
    [run.properties.coverage]. [language = None] is a cross-language analysis. *)
type coverage_row = { language : string option; analysis : string; status : string; detail : string option }

(** A [status = not_analysed] coverage row becomes one of these, which becomes a
    [toolExecutionNotifications] entry — the FR-024 guarantee that "no adapter for this
    language" renders as an explicit, labelled absence, never as silence. *)
type notification = { language : string option; analysis : string; message : string }

(** One SARIF [run]. [category] MUST be distinct across every (producer, analysis) pair a
    caller emits into the same log — see the module-level note above. *)
type run = {
  producer : string;  (** [tool.driver.name] *)
  producer_version : string option;  (** [tool.driver.version] *)
  category : string;  (** [runs[].properties.category] and [automationDetails.id] *)
  findings : finding list;
  coverage : coverage_row list;
  top_frontier : int option;
  notifications : notification list;
}

let schema_uri =
  "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json"

let sarif_version = "2.1.0"

let opt_field name = function None -> [] | Some v -> [ (name, v) ]

(** A display label from {!Arch_graph.label} is either ["name"] or ["name  (file)"]. Split it so
    a finding can carry both a [logicalLocations] entry (always meaningful — it names the
    function) and a [physicalLocation] (only when a file was recorded). Never fails: an
    unparseable label degrades to a logical-only location rather than being dropped. *)
let split_label label =
  match String.rindex_opt label '(' with
  | Some i when i > 0 && String.length label > 0 && label.[String.length label - 1] = ')' ->
      let name = String.trim (String.sub label 0 i) in
      let file = String.sub label (i + 1) (String.length label - i - 2) in
      if file = "" then (label, None) else (name, Some file)
  | _ -> (label, None)

let location_of_label label =
  let name, file = split_label label in
  `Assoc
    ([ ("logicalLocations", `List [ `Assoc [ ("fullyQualifiedName", `String name) ] ]) ]
    @
    match file with
    | None -> []
    | Some f ->
        [ ("physicalLocation",
           `Assoc [ ("artifactLocation", `Assoc [ ("uri", `String f) ]) ]) ])

(** A [codeFlow] with exactly one thread flow, one location per witness step — the shape a SARIF
    viewer (GitHub included) renders as a clickable path. [[]] when there is no witness, which
    omits [codeFlows] entirely rather than emitting an empty, meaningless array. *)
let code_flows_of_witness = function
  | [] -> []
  | steps ->
      [ ( "codeFlows",
          `List
            [ `Assoc
                [ ( "threadFlows",
                    `List
                      [ `Assoc
                          [ ( "locations",
                              `List
                                (List.map (fun step -> `Assoc [ ("location", location_of_label step) ]) steps) )
                          ]
                      ] )
                ]
            ] )
      ]

let properties_of_finding (f : finding) =
  let base =
    (match f.soundness_class with Some s -> [ ("soundness_class", `String s) ] | None -> [])
    @ (if f.soundness_unknown_top then [ ("soundness", `String "unknown_top") ] else [])
    @
    match f.top_reasons with
    | [] -> []
    | rs -> [ ("top_reason", `List (List.map (fun r -> `String r) rs)) ]
  in
  match base with [] -> [] | fields -> [ ("properties", `Assoc fields) ]

let result_of_finding (f : finding) =
  `Assoc
    ([ ("ruleId", `String f.rule_id); ("level", `String (level_to_string f.level));
       ("message", `Assoc [ ("text", `String f.message) ]) ]
    @ (match f.locations with
      | [] -> []
      | ls -> [ ("locations", `List (List.map location_of_label ls)) ])
    @ code_flows_of_witness f.code_flow
    @ properties_of_finding f)

let coverage_json (rows : coverage_row list) =
  `List
    (List.map
       (fun (r : coverage_row) ->
         `Assoc
           ([ ("analysis", `String r.analysis); ("status", `String r.status) ]
           @ opt_field "language" (Option.map (fun l -> `String l) r.language)
           @ opt_field "detail" (Option.map (fun d -> `String d) r.detail)))
       rows)

let notification_json (n : notification) =
  `Assoc
    ([ ("message", `Assoc [ ("text", `String n.message) ]);
       (* SARIF's own vocabulary for "this could not be analysed at all" — never a level that
          reads as a finding. *)
       ("descriptor", `Assoc [ ("id", `String (Printf.sprintf "not_analysed/%s" n.analysis)) ]) ]
    @ opt_field "properties"
        (Some
           (`Assoc
             ([ ("analysis", `String n.analysis) ]
             @ opt_field "language" (Option.map (fun l -> `String l) n.language)))))

(** The distinct [ruleId]s a run's findings mention, in first-seen order — SARIF's
    [tool.driver.rules] catalogue. Not required by the schema, but it is what lets a consumer
    (GitHub included) show a rule's full name/description instead of a bare id. *)
let rule_catalogue (findings : finding list) =
  let seen = Hashtbl.create 16 in
  List.filter_map
    (fun f ->
      if Hashtbl.mem seen f.rule_id then None
      else (
        Hashtbl.add seen f.rule_id () ;
        Some (`Assoc [ ("id", `String f.rule_id) ])))
    findings

let run_json (r : run) : Yojson.Safe.t =
  let properties =
    [ ("category", `String r.category) ]
    @ (match r.top_frontier with Some n -> [ ("top_frontier", `Int n) ] | None -> [])
    @ (match r.coverage with [] -> [] | rows -> [ ("coverage", coverage_json rows) ])
  in
  `Assoc
    ([ ( "tool",
         `Assoc
           [ ( "driver",
               `Assoc
                 ([ ("name", `String r.producer);
                    ("rules", `List (rule_catalogue r.findings)) ]
                 @ opt_field "version" (Option.map (fun v -> `String v) r.producer_version)) )
           ] );
       (* [automationDetails.id] is the OTHER half of GitHub's (tool, category) merge key —
          stamped alongside [runs[].properties.category] rather than instead of it, since
          different consumers read one or the other. *)
       ("automationDetails", `Assoc [ ("id", `String r.category) ]);
       ("results", `List (List.map result_of_finding r.findings));
       ("properties", `Assoc properties) ]
    @
    match r.notifications with
    | [] -> []
    | ns ->
        [ ( "invocations",
            `List
              [ `Assoc
                  [ ("executionSuccessful", `Bool true);
                    ("toolExecutionNotifications", `List (List.map notification_json ns))
                  ]
              ] )
        ])

(** [log runs] wraps one or more {!run}s into a complete SARIF 2.1.0 document — the top-level
    object [$schema]/[version]/[runs] every consumer (GitHub included) expects. *)
let log (runs : run list) : Yojson.Safe.t =
  `Assoc
    [ ("$schema", `String schema_uri); ("version", `String sarif_version);
      ("runs", `List (List.map run_json runs)) ]

let to_string runs = Yojson.Safe.pretty_to_string (log runs)
