(* Tests for Arch_compare (specs/arch-metrics-gate.md FR-006..FR-017, EC-2..6). *)

open Arch_compare

let metrics l = Metric_map.of_list l

let names (changes : metric_change list) =
  List.map (fun (c : metric_change) -> c.metric) changes

let eval ?(accept = "") ~baseline ~current () =
  let acceptance = parse_accept_file_string accept in
  evaluate ~acceptance ~baseline:(metrics baseline) ~current:(metrics current)

(* ── compare_metrics ─────────────────────────────────────────────────────── *)

let test_regression_higher () =
  let r =
    compare_metrics
      ~baseline:(metrics [("large_functions", 10.)])
      ~current:(metrics [("large_functions", 12.)])
  in
  Alcotest.(check (list string)) "regressed" ["large_functions"] (names r.regressions)

let test_regression_lower () =
  let r =
    compare_metrics
      ~baseline:(metrics [("doc_coverage_pct", 80.)])
      ~current:(metrics [("doc_coverage_pct", 75.)])
  in
  Alcotest.(check (list string)) "regressed" ["doc_coverage_pct"] (names r.regressions)

let test_improvement () =
  let r =
    compare_metrics
      ~baseline:(metrics [("doc_coverage_pct", 80.)])
      ~current:(metrics [("doc_coverage_pct", 85.)])
  in
  Alcotest.(check (list string)) "improved" ["doc_coverage_pct"] (names r.improvements);
  Alcotest.(check (list string)) "no regressions" [] (names r.regressions)

let test_untracked_ignored () =
  (* FR-008 / EC-2: informational metrics never classify. *)
  let r =
    compare_metrics
      ~baseline:(metrics [("total_functions", 100.); ("modules", 10.)])
      ~current:(metrics [("total_functions", 250.)])
  in
  Alcotest.(check (list string)) "no regressions" [] (names r.regressions);
  Alcotest.(check int) "no missing" 0 (List.length r.missing)

let test_missing_tracked () =
  let r =
    compare_metrics
      ~baseline:(metrics [("large_files", 3.)])
      ~current:(metrics [])
  in
  Alcotest.(check (list string)) "missing" ["large_files"] (List.map fst r.missing)

let test_unchanged_tolerance () =
  (* FR-011 / EC-6 *)
  let r =
    compare_metrics
      ~baseline:(metrics [("large_files", 3.)])
      ~current:(metrics [("large_files", 3. +. 1e-12)])
  in
  Alcotest.(check (list string)) "unchanged" ["large_files"] (List.map fst r.unchanged);
  Alcotest.(check (list string)) "no regressions" [] (names r.regressions)

(* ── strict JSON parsing (FR-009) ────────────────────────────────────────── *)

let test_json_ok () =
  match parse_metrics_json_string {|{"large_files": 3, "doc_coverage_pct": 87.5}|} with
  | Ok m -> Alcotest.(check (float 0.001)) "float" 87.5 (Metric_map.find "doc_coverage_pct" m)
  | Error e -> Alcotest.fail e

let test_json_invalid () =
  (match parse_metrics_json_string "{not json" with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "accepted invalid JSON");
  (match parse_metrics_json_string {|[1,2]|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "accepted non-object JSON");
  match parse_metrics_json_string {|{"a": "str"}|} with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "accepted non-numeric field"

(* ── .metrics-accept parsing (FR-012..FR-014, FR-017) ────────────────────── *)

let test_accept_inline_reason () =
  let f = parse_accept_file_string "large_functions <= 12  # refactor pending #42\n" in
  Alcotest.(check int) "accepted" 1 (List.length f.accepted);
  Alcotest.(check int) "invalid" 0 (List.length f.invalid_entries);
  let e = List.hd f.accepted in
  Alcotest.(check string) "reason" "refactor pending #42" e.reason;
  Alcotest.(check (float 0.001)) "bound" 12. e.bound

let test_accept_trailing_reason () =
  let f = parse_accept_file_string "large_functions <= 12 refactor pending\n" in
  Alcotest.(check int) "accepted" 1 (List.length f.accepted);
  Alcotest.(check string) "reason" "refactor pending" (List.hd f.accepted).reason

let test_accept_preceding_comment () =
  let f =
    parse_accept_file_string "# refactor of parser pending\nlarge_functions <= 12\n"
  in
  Alcotest.(check int) "accepted" 1 (List.length f.accepted);
  Alcotest.(check string) "reason" "refactor of parser pending"
    (List.hd f.accepted).reason

let test_blank_line_clears_comment () =
  (* FR-013: blank line clears the pending comment block ⇒ no reason ⇒ invalid. *)
  let f = parse_accept_file_string "# stale comment\n\nlarge_functions <= 12\n" in
  Alcotest.(check int) "accepted" 0 (List.length f.accepted);
  Alcotest.(check string) "message" "missing reviewable reason"
    (List.hd f.invalid_entries).message

let test_accept_missing_reason () =
  let f = parse_accept_file_string "large_functions <= 12\n" in
  Alcotest.(check int) "invalid" 1 (List.length f.invalid_entries);
  Alcotest.(check string) "message" "missing reviewable reason"
    (List.hd f.invalid_entries).message

let test_accept_wrong_operator () =
  let f = parse_accept_file_string "doc_coverage_pct <= 70 # justified\n" in
  Alcotest.(check int) "invalid" 1 (List.length f.invalid_entries);
  Alcotest.(check string) "message" "expected >= bound"
    (List.hd f.invalid_entries).message

let test_accept_untracked () =
  let f = parse_accept_file_string "total_functions <= 999 # nope\n" in
  Alcotest.(check int) "invalid" 1 (List.length f.invalid_entries);
  Alcotest.(check string) "message" "not a tracked architecture metric"
    (List.hd f.invalid_entries).message

let test_accept_bad_bound () =
  let f = parse_accept_file_string "large_functions <= many # reason\n" in
  Alcotest.(check int) "invalid" 1 (List.length f.invalid_entries);
  Alcotest.(check string) "message" "invalid reviewed bound"
    (List.hd f.invalid_entries).message

let test_accept_duplicate () =
  (* FR-014: duplicate entries are invalid, never last-wins. *)
  let f =
    parse_accept_file_string
      "large_functions <= 12 # first\nlarge_functions <= 15 # second\n"
  in
  Alcotest.(check int) "accepted" 1 (List.length f.accepted);
  Alcotest.(check int) "invalid" 1 (List.length f.invalid_entries);
  let e = List.hd f.invalid_entries in
  Alcotest.(check string) "message" "duplicate entry for this metric" e.message;
  Alcotest.(check int) "line" 2 e.line

let test_template_bare_append_rejected () =
  (* Codex review finding: a bare entry appended right after a comment block
     would inherit the block as its reason. The committed .metrics-accept
     template must end with a blank line so an appended bare entry is invalid. *)
  let template =
    "# .metrics-accept — reviewed waivers.\n# Default policy: EMPTY.\n\n"
  in
  let f = parse_accept_file_string (template ^ "large_functions <= 12\n") in
  Alcotest.(check int) "accepted" 0 (List.length f.accepted);
  Alcotest.(check string) "message" "missing reviewable reason"
    (List.hd f.invalid_entries).message

let test_accept_line_numbers () =
  let f = parse_accept_file_string "# c\n\nlarge_functions <= 12\n" in
  Alcotest.(check int) "line" 3 (List.hd f.invalid_entries).line

(* ── evaluate / has_failures (FR-007, FR-015, EC-4, EC-5) ────────────────── *)

let test_blocking_without_waiver () =
  let r = eval ~baseline:[("large_functions", 10.)] ~current:[("large_functions", 12.)] () in
  Alcotest.(check bool) "fails" true (has_failures r);
  Alcotest.(check (list string)) "blocking" ["large_functions"]
    (names r.blocking_regressions)

let test_accepted_within_bound () =
  let r =
    eval
      ~accept:"large_functions <= 12 # waived\n"
      ~baseline:[("large_functions", 10.)]
      ~current:[("large_functions", 12.)] ()
  in
  (* EC-4: bound inclusive. *)
  Alcotest.(check bool) "passes" false (has_failures r);
  Alcotest.(check int) "accepted" 1 (List.length r.accepted_regressions)

let test_blocking_beyond_bound () =
  let r =
    eval
      ~accept:"large_functions <= 12 # waived\n"
      ~baseline:[("large_functions", 10.)]
      ~current:[("large_functions", 13.)] ()
  in
  Alcotest.(check bool) "fails" true (has_failures r);
  Alcotest.(check (list string)) "blocking" ["large_functions"]
    (names r.blocking_regressions)

let test_unused_waiver_harmless () =
  (* EC-5 *)
  let r =
    eval
      ~accept:"large_files <= 5 # unused\n"
      ~baseline:[("large_functions", 10.)]
      ~current:[("large_functions", 10.)] ()
  in
  Alcotest.(check bool) "passes" false (has_failures r)

let test_invalid_entry_fails_gate () =
  (* FR-017: invalid entries fail even with zero regressions. *)
  let r =
    eval
      ~accept:"large_files <= 5\n"
      ~baseline:[("large_functions", 10.)]
      ~current:[("large_functions", 10.)] ()
  in
  Alcotest.(check bool) "fails" true (has_failures r)

let test_missing_fails_gate () =
  let r = eval ~baseline:[("large_files", 3.)] ~current:[] () in
  Alcotest.(check bool) "fails" true (has_failures r)

let test_report_renders () =
  let r =
    eval
      ~accept:"large_functions <= 12 # waived for #42\n"
      ~baseline:[("large_functions", 10.); ("doc_coverage_pct", 80.)]
      ~current:[("large_functions", 12.); ("doc_coverage_pct", 85.)] ()
  in
  let report = render_report ~baseline_path:"b.json" ~current_path:"c.json" r in
  let contains needle =
    let nlen = String.length needle and rlen = String.length report in
    let rec scan i =
      i + nlen <= rlen && (String.sub report i nlen = needle || scan (i + 1))
    in
    scan 0
  in
  Alcotest.(check bool) "reason shown" true (contains "waived for #42");
  Alcotest.(check bool) "improvement shown" true (contains "Improvements");
  Alcotest.(check bool) "OK verdict" true (contains "OK: No blocking regressions")

let () =
  Alcotest.run "arch_compare"
    [
      ( "compare",
        [
          Alcotest.test_case "regression higher" `Quick test_regression_higher;
          Alcotest.test_case "regression lower" `Quick test_regression_lower;
          Alcotest.test_case "improvement" `Quick test_improvement;
          Alcotest.test_case "untracked ignored" `Quick test_untracked_ignored;
          Alcotest.test_case "missing tracked" `Quick test_missing_tracked;
          Alcotest.test_case "unchanged tolerance" `Quick test_unchanged_tolerance;
        ] );
      ( "json",
        [
          Alcotest.test_case "valid flat object" `Quick test_json_ok;
          Alcotest.test_case "invalid inputs rejected" `Quick test_json_invalid;
        ] );
      ( "accept-file",
        [
          Alcotest.test_case "inline reason" `Quick test_accept_inline_reason;
          Alcotest.test_case "trailing reason" `Quick test_accept_trailing_reason;
          Alcotest.test_case "preceding comment" `Quick test_accept_preceding_comment;
          Alcotest.test_case "blank clears comment" `Quick test_blank_line_clears_comment;
          Alcotest.test_case "missing reason" `Quick test_accept_missing_reason;
          Alcotest.test_case "wrong operator" `Quick test_accept_wrong_operator;
          Alcotest.test_case "untracked metric" `Quick test_accept_untracked;
          Alcotest.test_case "bad bound" `Quick test_accept_bad_bound;
          Alcotest.test_case "duplicate entry" `Quick test_accept_duplicate;
          Alcotest.test_case "template bare append rejected" `Quick
            test_template_bare_append_rejected;
          Alcotest.test_case "line numbers" `Quick test_accept_line_numbers;
        ] );
      ( "evaluate",
        [
          Alcotest.test_case "blocking without waiver" `Quick test_blocking_without_waiver;
          Alcotest.test_case "accepted within bound" `Quick test_accepted_within_bound;
          Alcotest.test_case "blocking beyond bound" `Quick test_blocking_beyond_bound;
          Alcotest.test_case "unused waiver harmless" `Quick test_unused_waiver_harmless;
          Alcotest.test_case "invalid entry fails gate" `Quick test_invalid_entry_fails_gate;
          Alcotest.test_case "missing fails gate" `Quick test_missing_fails_gate;
          Alcotest.test_case "report renders" `Quick test_report_renders;
        ] );
    ]
