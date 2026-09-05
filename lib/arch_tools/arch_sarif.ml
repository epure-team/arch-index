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

(** One SARIF [result]. [rule_id] is the [arch-rules] rule name — TODAY this {e is} the rule's
    human title, because the [.rules] DSL has no stable-id syntax of its own to give [ruleId]
    instead. That is a real limitation, not a design choice: renaming a rule's prose therefore
    closes its GitHub alerts and opens new ones, exactly as if the rule had been deleted and a
    different one added. A stable id independent of the prose is tracked separately (see the
    round-2/round-3 review history on roadmap 2.1); until it exists, callers should expect
    renaming a rule to churn its alert history. A future SARIF-in producer may supply its own
    stable id here instead.

    [locations] are display labels as produced by {!Arch_graph.label} — ["name  (file)"] when a
    file is known, bare ["name"] otherwise. This module does the best it can with what
    [arch-rules] actually has today (no line numbers on a rule verdict, only a function/file
    pair), so a location here becomes a SARIF [logicalLocations] entry always, and a
    [physicalLocation] additionally whenever a file could be parsed out of the label. A future
    producer with real line numbers extends {!location_of_label}'s caller, not this shape.
    {b The caller, not this module, is responsible for only ever passing genuine display labels
    here} — see [locations]'s own field comment below for what happens if it does not.

    [code_flow] is the witness path (source-to-target order) from roadmap 1.5, rendered as a
    SARIF [codeFlow] with one thread flow location per step. *)
type finding = {
  rule_id : string;
  level : level;
  message : string;
  verdict : string option;
      (** The producer's own verdict string verbatim (e.g. ["UNKNOWN_NO_CONTRACT"],
          ["NOT_COMPUTED"]), mirrored into [properties.verdict]. [level] alone collapses several
          distinct verdicts onto the same SARIF severity (every one of [UNKNOWN],
          [UNKNOWN_NO_CONTRACT], [NOT_COMPUTED], [NO_SOURCE], [NO_TARGET] is [note]) — this field
          is what lets a machine consumer tell them apart without re-parsing [message.text].
          [None] for a producer that has no verdict vocabulary of its own (e.g. a future SARIF-in
          heuristic finding). *)
  soundness_class : string option;  (** ADR-002 vocabulary, e.g. ["heuristic"] *)
  soundness : string option;
      (** The ADR-002 / FR-022 soundness-gap vocabulary verbatim, e.g. [Some "unknown_top"] for a
          verdict that stopped at an unresolvable (⊤) edge, or [Some "no_contract"] for a verdict
          reached because the whole index was never ⊤-marked at all (a DIFFERENT cause: nothing
          was ruled out for any rule, not just this one's cone). [None] when the verdict is not a
          soundness gap (e.g. [VIOLATION], [POSSIBLE], [PASS]). Stamped into
          [properties.soundness] verbatim — never collapsed to a single "unknown_top" value the
          way a bare boolean would. *)
  top_reasons : string list;
      (** The ⊤-anchor taxonomy vocabulary (roadmap 1.4) for the escaping edge(s) this
          finding's cone hit, when known. [[]] when the verdict carries no specific reason
          (e.g. [UNKNOWN_NO_CONTRACT], where the whole index was never ⊤-marked, not one edge). *)
  locations : string list;  (** Primary location(s), as display labels (see above). *)
  detail_total : int;
      (** The UNTRUNCATED count `locations` (and, for a kind whose evidence stays in [message]
          only, `message` itself) was capped from — [arch-rules]' own [detail_total]
          (docs/fitness-functions.md's "a consumer never has to guess whether '20 shown' means
          '20 total' or '20 of 200'" fitness function). Stamped into [properties.detail_total]
          unconditionally, even when it equals [List.length locations] and the field is
          redundant: a consumer should never have to special-case "is this the truncated case"
          by counting `locations` itself and comparing. *)
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
  contract_ok : bool option;
      (** Mirrors [arch-rules]' own [contract_ok] (whether the index carries a ⊤-marking
          contract) into [run.properties]. [None] for a caller with no such concept. *)
  computed : bool option;
      (** Mirrors [arch-rules]' own [computed] (whether the analysis ran at all, as opposed to
          refusing outright) into [run.properties]. Without this, an all-PASS run and a run that
          evaluated nothing both produce a document with an empty [results] and no way to tell
          them apart. *)
  proved : int option;
      (** Count of verdicts the producer proved (PASS), mirrored into [run.properties]. *)
}

let schema_uri =
  "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json"

let sarif_version = "2.1.0"

let opt_field name = function None -> [] | Some v -> [ (name, v) ]

(** The exact separator {!Arch_graph.label} inserts between name and file — two spaces, then
    an open paren. Not just ["("] : a file name can itself contain a parenthesis (e.g.
    ["wri#te (x).ts"]), and splitting on the RIGHTMOST bare ['('] then picks a paren inside the
    file name instead of the real separator, fabricating both halves. The name a producer indexes
    is never expected to contain this exact two-space-then-paren sequence, so the LEFTMOST
    occurrence of the full separator is the real one. *)
let label_sep = "  ("

(** First index of [needle] in [haystack], or [None]. No [Str]/substring search in [Stdlib]. *)
let find_substring haystack needle =
  let hn = String.length haystack and nn = String.length needle in
  let rec go i = if i + nn > hn then None else if String.sub haystack i nn = needle then Some i else go (i + 1) in
  go 0

(** A display label from {!Arch_graph.label} is either ["name"] or ["name  (file)"]. Split it so
    a finding can carry both a [logicalLocations] entry (always meaningful — it names the
    function) and a [physicalLocation] (only when a file was recorded). Never fails: an
    unparseable label degrades to a logical-only location rather than being dropped — and
    "unparseable" means "does not end in [')']", not "picked the wrong paren", which is why this
    searches for the exact separator rather than any ['(']. *)
let split_label label =
  match find_substring label label_sep with
  | Some i when String.length label > 0 && label.[String.length label - 1] = ')' ->
      let name = String.sub label 0 i in
      let file_start = i + String.length label_sep in
      let file = String.sub label file_start (String.length label - file_start - 1) in
      if file = "" then (label, None) else (name, Some file)
  | _ -> (label, None)

(** Percent-encode the characters a raw file path can legally contain that are otherwise
    significant in a URI — most importantly ['#'], a fragment delimiter GitHub's SARIF viewer
    will otherwise split the path on, mapping the finding to no file at all. *)
let uri_encode s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '~' | '/' | ':' ->
          Buffer.add_char buf c
      | c -> Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c)))
    s ;
  Buffer.contents buf

(** Split a trailing [":<digits>"] off a file part, so a label written ["name  (file:12)"]
    yields a [region.startLine]. Returns the file unchanged when there is no such suffix — the
    labels [arch-rules] produces carry no line and must keep behaving exactly as before.

    A line is only recognised when EVERY character after the last colon is a digit: a Windows
    drive or a path that merely contains a colon is left alone rather than silently truncated. *)
let split_line file =
  match String.rindex_opt file ':' with
  | None -> (file, None)
  | Some i ->
      let tail = String.sub file (i + 1) (String.length file - i - 1) in
      let all_digits =
        tail <> "" && String.for_all (function '0' .. '9' -> true | _ -> false) tail
      in
      if all_digits then (String.sub file 0 i, int_of_string_opt tail) else (file, None)

let location_of_label label =
  let name, file = split_label label in
  `Assoc
    ([ ("logicalLocations", `List [ `Assoc [ ("fullyQualifiedName", `String name) ] ]) ]
    @
    match file with
    | None -> []
    | Some f ->
        let path, line = split_line f in
        [ ( "physicalLocation",
            `Assoc
              (("artifactLocation", `Assoc [ ("uri", `String (uri_encode path)) ])
              :: (match line with
                 | Some l -> [ ("region", `Assoc [ ("startLine", `Int l) ]) ]
                 | None -> [])) ) ])

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
    (match f.verdict with Some v -> [ ("verdict", `String v) ] | None -> [])
    @ (match f.soundness_class with Some s -> [ ("soundness_class", `String s) ] | None -> [])
    @ (match f.soundness with Some s -> [ ("soundness", `String s) ] | None -> [])
    @ (match f.top_reasons with
      | [] -> []
      | rs -> [ ("top_reason", `List (List.map (fun r -> `String r) rs)) ])
    (* Unconditional, unlike the fields above: `0` is a meaningful value here (no evidence rows
       at all), not an absence to omit the way `None` is for the optional fields — a consumer
       that saw the key missing would have no way to distinguish "0 total" from "this producer
       never set it". See the field's own doc comment on `detail_total` above the [finding] type. *)
    @ [ ("detail_total", `Int f.detail_total) ]
  in
  [ ("properties", `Assoc base) ]

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
    @ (match r.contract_ok with Some b -> [ ("contract_ok", `Bool b) ] | None -> [])
    @ (match r.computed with Some b -> [ ("computed", `Bool b) ] | None -> [])
    @ (match r.proved with Some n -> [ ("proved", `Int n) ] | None -> [])
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

(** Every (producer, category) pair a caller emits must be distinct — see the module-level note:
    GitHub OVERWRITES a run sharing tool+category with a later one rather than merging, so two
    runs colliding on this pair in one log is a defect worth refusing NOW, before 2.2
    (`arch-report`, the caller that actually emits several runs per log) exists to trip over it
    for the first time in production. *)
let check_distinct_categories (runs : run list) =
  let seen = Hashtbl.create 8 in
  List.iter
    (fun (r : run) ->
      let key = (r.producer, r.category) in
      if Hashtbl.mem seen key then
        invalid_arg
          (Printf.sprintf
             "Arch_sarif.log: two runs share (producer, category) = (%S, %S) — GitHub overwrites \
              a run sharing tool+category with a later one rather than merging; give them \
              distinct categories"
             r.producer r.category)
      else Hashtbl.add seen key ())
    runs

(** [log runs] wraps one or more {!run}s into a complete SARIF 2.1.0 document — the top-level
    object [$schema]/[version]/[runs] every consumer (GitHub included) expects. *)
let log (runs : run list) : Yojson.Safe.t =
  check_distinct_categories runs ;
  `Assoc
    [ ("$schema", `String schema_uri); ("version", `String sarif_version);
      ("runs", `List (List.map run_json runs)) ]

let to_string runs = Yojson.Safe.pretty_to_string (log runs)
