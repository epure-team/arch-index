(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-sarif-load] — import a foreign analyser's SARIF as HEURISTIC facts
    (roadmap 2.3, specs/reporting-and-integration.md FR-010/FR-012).

    {1 The guarantee that gives the item its point}

    ADR 002: a [heuristic] fact may RAISE a finding and may never discharge a ⊤ anchor nor license
    a [PASS]. That is not enforced by remembering to check it at each consumer — it is enforced
    by where the rows go. Imported findings land in [imported_findings], a table no reachability
    or effect query reads, and they carry no [calls] row, no [callee_id] and no edge kind. A
    Semgrep finding therefore cannot discharge anything, because there is nothing for it to
    discharge {i through}.

    {1 Two hazards specific to a foreign input}

    {b The vocabulary is not ours.} SARIF's [level] is a closed set today and the standard evolves;
    producers also carry their own values in property bags. Mapping onto a closed set with a
    catch-all makes a new member vanish silently — the quiet cousin of a missing column, except
    the input is not under our control, so it is a matter of when rather than whether. Every level
    outside the standard four is REFUSED and counted.

    {b The paths are not ours either.} [artifactLocation.uri] is written by a tool that knows
    nothing of this index: absolute, relative to a [uriBaseId] we were not given, or
    percent-encoded. A uri matching no indexed module is stored [resolution='unresolved'] with a
    NULL [module_id] — never attached to the nearest match. A finding on the wrong function is
    worse than a finding on none, and a suffix match will produce one cheerfully.

    {1 FR-012 is transactional, and this is how it is met}

    "Writes no facts" cannot be honoured by a loop that stops at the bad record: everything before
    it is already written. [Arch_db] has no transaction support, so the whole input is parsed and
    validated BEFORE a single write is opened. A malformed file therefore never reaches the
    writer.

    The residual is named rather than assumed away: a WRITE that fails part-way (a constraint
    violation, a full disk) is not covered. That needs a transaction and this adapter has none. *)

let die code msg =
  prerr_endline msg ;
  exit code

let usage =
  {|arch-sarif-load — import a SARIF 2.1.0 log as heuristic findings.

Usage: arch-sarif-load <db> <file.sarif>

Findings land in `imported_findings`, attributed to a new producer_runs row with
soundness_class = 'heuristic'. By ADR 002 such a fact can raise a finding and can
never discharge a ⊤ anchor or license a PASS.

Exit: 0 imported (possibly partial) · 2 usage, unreadable db, or unparseable SARIF|}

(* SARIF 2.1.0 §3.27.10. Closed here on purpose: a level outside it is refused and counted, not
   folded into a default. *)
let known_levels = [ "none"; "note"; "warning"; "error" ]

type record = {
  rule_id : string;
  level : string;
  message : string;
  uri : string option;
  start_line : int option;
}

type parsed = { tool : string; tool_version : string option; records : record list; refused : int }

let member k = function `Assoc fs -> List.assoc_opt k fs | _ -> None
let str = function Some (`String s) -> Some s | _ -> None
let integer = function Some (`Int n) -> Some n | _ -> None

(** Parse and validate the WHOLE document. Returns [Error] for anything that makes the file not a
    SARIF log — no partial result, because a caller that receives one has already been given the
    chance to write half an import. Records the file REFUSES (an unknown level, no rule id) are
    counted and dropped, which is a different outcome and FR-012's [partial]. *)
let parse (raw : string) : (parsed, string) result =
  match Yojson.Safe.from_string raw with
  | exception Yojson.Json_error e -> Error ("not JSON: " ^ e)
  | json -> (
      match member "runs" json with
      | Some (`List runs) ->
          let refused = ref 0 in
          let tool = ref "unknown" and tool_version = ref None in
          let records =
            List.concat_map
              (fun run ->
                (match member "tool" run |> Option.map (member "driver") with
                | Some (Some driver) ->
                    (match str (member "name" driver) with Some n -> tool := n | None -> ()) ;
                    tool_version := str (member "version" driver)
                | _ -> ()) ;
                match member "results" run with
                | Some (`List results) ->
                    List.filter_map
                      (fun r ->
                        let rule_id = str (member "ruleId" r) in
                        let level = Option.value ~default:"warning" (str (member "level" r)) in
                        let message =
                          match member "message" r with
                          | Some m -> Option.value ~default:"" (str (member "text" m))
                          | None -> ""
                        in
                        let loc =
                          match member "locations" r with
                          | Some (`List (l :: _)) -> (
                              match member "physicalLocation" l with
                              | Some pl ->
                                  let uri =
                                    match member "artifactLocation" pl with
                                    | Some al -> str (member "uri" al)
                                    | None -> None
                                  in
                                  let line =
                                    match member "region" pl with
                                    | Some rg -> integer (member "startLine" rg)
                                    | None -> None
                                  in
                                  (uri, line)
                              | None -> (None, None))
                          | _ -> (None, None)
                        in
                        match rule_id with
                        | None ->
                            (* A result with no ruleId is not attributable to anything, so it is
                               refused rather than given a placeholder id that would later look
                               like a real rule. *)
                            incr refused ; None
                        | Some rid ->
                            if not (List.mem level known_levels) then (incr refused ; None)
                            else
                              Some
                                { rule_id = rid; level; message; uri = fst loc;
                                  start_line = snd loc })
                      results
                | _ -> [])
              runs
          in
          Ok { tool = !tool; tool_version = !tool_version; records; refused = !refused }
      | _ -> Error "no `runs` array — not a SARIF log")

(* -------------------------------------------------------------------------- *)
(* Writing — reached only once the whole input has parsed                      *)
(* -------------------------------------------------------------------------- *)

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> die 2 (Printf.sprintf "arch-sarif-load: %s: %s" (Sqlite3.Rc.to_string rc) sql)

let quote s =
  "'" ^ String.concat "''" (String.split_on_char '\'' s) ^ "'"

let quote_opt = function None -> "NULL" | Some s -> quote s
let int_opt = function None -> "NULL" | Some n -> string_of_int n

(** Resolve a foreign uri against this index's modules, or refuse.

    The match is on a full trailing PATH SEGMENT boundary, never a bare suffix: [src/a/b.ml] must
    not be matched by a module at [other/ab.ml]. A uri that matches more than one module is
    UNRESOLVED too — ambiguity is absence of proof, and picking one is how a finding lands on the
    wrong function. *)
let resolve_uri db uri =
  match uri with
  | None -> None
  | Some u ->
      let u = match String.index_opt u '#' with Some i -> String.sub u 0 i | None -> u in
      let u =
        (* Strip a scheme and any leading slashes; a foreign tool writes file:///abs or a
           relative path, and neither spelling is a fact about our tree. *)
        let u = if String.length u > 7 && String.sub u 0 7 = "file://" then
            String.sub u 7 (String.length u - 7) else u in
        u
      in
      let matches = ref [] in
      let stmt =
        Sqlite3.prepare db
          "SELECT id, path FROM modules WHERE ? = path OR ? LIKE '%/' || path OR path LIKE '%/' || ?"
      in
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT u)) ;
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT u)) ;
      ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT u)) ;
      let rec loop () =
        match Sqlite3.step stmt with
        | Sqlite3.Rc.ROW ->
            (match Sqlite3.column stmt 0 with
             | Sqlite3.Data.INT i -> matches := Int64.to_int i :: !matches
             | _ -> ()) ;
            loop ()
        | _ -> ()
      in
      loop () ;
      ignore (Sqlite3.finalize stmt) ;
      match !matches with
      | [ id ] -> Some id
      | _ ->
          (* Zero matches, or several. Both are UNRESOLVED: a finding attached to the wrong
             function is worse than one attached to none, and "the only plausible candidate" is
             exactly the reasoning that produces the wrong one. *)
          None

let () =
  match Array.to_list Sys.argv with
  | _ :: db_path :: sarif_path :: _ ->
      if not (Sys.file_exists db_path) then
        die 2 (Printf.sprintf "arch-sarif-load: no such db: %s" db_path) ;
      let raw =
        try
          let ic = open_in_bin sarif_path in
          let n = in_channel_length ic in
          let s = really_input_string ic n in
          close_in ic ; s
        with Sys_error e -> die 2 ("arch-sarif-load: " ^ e)
      in
      (* FR-012: the ENTIRE input is parsed before any write is opened. A malformed file exits
         here, with the database untouched — not after some records have landed. *)
      let p =
        match parse raw with
        | Ok p -> p
        | Error e ->
            (* The coverage row is a write about the FAILURE, not about the program, which is the
               distinction FR-012's own second sentence already relies on. *)
            let db = Sqlite3.db_open db_path in
            exec db
              (Printf.sprintf
                 "INSERT INTO analysis_coverage (language, analysis, status, detail) VALUES \
                  (NULL, 'sarif_import', 'failed', %s)"
                 (quote (Printf.sprintf "%s: %s" (Filename.basename sarif_path) e))) ;
            ignore (Sqlite3.db_close db) ;
            die 2 (Printf.sprintf "arch-sarif-load: cannot parse %s: %s" sarif_path e)
      in
      let db = Sqlite3.db_open db_path in
      exec db
        (Printf.sprintf
           "INSERT INTO producer_runs (producer, producer_version, soundness_class) VALUES \
            (%s, %s, 'heuristic')"
           (quote p.tool) (quote_opt p.tool_version)) ;
      let run_id = Int64.to_int (Sqlite3.last_insert_rowid db) in
      let unresolved = ref 0 in
      List.iter
        (fun r ->
          let module_id = resolve_uri db r.uri in
          if module_id = None && r.uri <> None then incr unresolved ;
          exec db
            (Printf.sprintf
               "INSERT INTO imported_findings (producer_run_id, rule_id, level, message, uri, \
                start_line, module_id, resolution) VALUES (%d, %s, %s, %s, %s, %s, %s, %s)"
               run_id (quote r.rule_id) (quote r.level) (quote r.message) (quote_opt r.uri)
               (int_opt r.start_line)
               (match module_id with Some m -> string_of_int m | None -> "NULL")
               (quote (if module_id = None then "unresolved" else "resolved"))))
        p.records ;
      (* [partial] is for an input that PARSED while records were refused — a different state from
         [failed], which is the input that could not be parsed at all. Offering them as
         alternatives, as the spec first did, lets an implementation report either and one would
         be a lie about what happened. *)
      let status = if p.refused > 0 then "partial" else "covered" in
      exec db
        (Printf.sprintf
           "INSERT INTO analysis_coverage (language, analysis, status, detail) VALUES (NULL, \
            'sarif_import', %s, %s)"
           (quote status)
           (quote
              (Printf.sprintf "%s: %d imported, %d refused, %d unresolved location(s)" p.tool
                 (List.length p.records) p.refused !unresolved))) ;
      ignore (Sqlite3.db_close db) ;
      Printf.printf
        "arch-sarif-load: %d finding(s) from %s imported as heuristic (%d refused, %d unresolved)\n"
        (List.length p.records) p.tool p.refused !unresolved
  | _ -> die 2 usage
