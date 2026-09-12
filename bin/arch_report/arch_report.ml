(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-report] — one query pass, three artifacts (roadmap 2.2,
    specs/reporting-and-integration.md FR-020).

    This file is argument parsing, file writing and the exit policy. Every decision about WHAT the
    report says lives in {!Arch_tools.Arch_report}, and deliberately so: the three renderings must
    be functions of one value, so there is nowhere here for a fourth source of truth to appear. *)

open Arch_tools

let usage =
  {|arch-report — one report, three renderings, from a single query pass.

Usage: arch-report <db> --out <dir> [--rules <rules-file>]

Writes into <dir>:
  report.json   the machine contract
  report.sarif  SARIF 2.1.0, one run per analysis (distinct categories)
  report.html   a single self-contained file, no external assets

The database is the fourth artifact and is NOT regenerated or copied.

Exit: 0 report written · 2 bad usage or unreadable db · 3 the db refused the read|}

let die code msg =
  prerr_endline msg ;
  exit code

let write_file path contents =
  let oc =
    try open_out path
    with Sys_error e -> die 2 (Printf.sprintf "arch-report: cannot write %s: %s" path e)
  in
  try
    output_string oc contents ;
    close_out oc
  with Sys_error e ->
    close_out_noerr oc ;
    die 2 (Printf.sprintf "arch-report: cannot write %s: %s" path e)

let () =
  try
    let db_path, dir, rules_path =
      match Array.to_list Sys.argv with
      | [_; db_path; "--out"; dir] -> (db_path, dir, None)
      | [_; db_path; "--out"; dir; "--rules"; rules] -> (db_path, dir, Some rules)
      | _ -> die 2 usage
    in
      if not (Sys.file_exists dir && Sys.is_directory dir) then
        die 2 (Printf.sprintf "arch-report: --out %s is not a directory" dir) ;
      let t =
        try Arch_db.open_ro db_path
        with
        (* Refused and Broken are DIFFERENT states and get different codes: a database that
           refuses a read (a column this binary's schema knows and that one lacks) is an
           actionable version mismatch, while Broken is a corrupt or absent file. Collapsing them
           would tell an operator to check the wrong thing. *)
        | Arch_db.Refused m -> die 3 ("arch-report: " ^ m)
        | Arch_db.Broken m -> die 2 ("arch-report: " ^ m)
      in
      let rule_evaluation =
        match rules_path with
        | None -> None
        | Some path ->
            let contract_ok, results = Arch_rule_eval.evaluate_file t path in
            Some (path, contract_ok, results)
      in
      let r =
        try Arch_report.collect ?rule_evaluation ~db_path t
        with Arch_db.Refused m -> die 3 ("arch-report: " ^ m)
      in
      let json = Yojson.Safe.pretty_to_string (Arch_report.to_json r) ^ "\n" in
      let sarif = Yojson.Safe.pretty_to_string (Arch_report.to_sarif r) ^ "\n" in
      let html = Arch_report.to_html r in
      write_file (Filename.concat dir "report.json")
        json ;
      write_file (Filename.concat dir "report.sarif")
        sarif ;
      write_file (Filename.concat dir "report.html") html ;
      let historical = List.length (Arch_report.findings r) in
      let rule_alerts =
        List.length
          (List.filter
             (fun (_, result) -> result.Arch_rule_eval.verdict <> "PASS")
             r.Arch_report.rule_results)
      in
      Printf.printf
        "arch-report: %d historical finding(s) across %d section(s), %d rule alert(s) -> %s\n"
        historical (List.length r.Arch_report.sections) rule_alerts dir
  with
  | Arch_db.Refused m -> die 3 ("arch-report: " ^ m)
  | Arch_db.Broken m -> die 2 ("arch-report: " ^ m)
  | Invalid_argument m -> die 2 ("arch-report: " ^ m)
  | Arch_rule_eval.Error m -> die 2 ("arch-report: " ^ m)
