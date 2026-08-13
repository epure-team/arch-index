(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The shared library's own string helpers, tested directly.

    They were hoisted out of five hand-rolled copies, which made them
    load-bearing for [Batch.contains] and [Batch.not_contains] across the whole
    suite — and left them with no test of their own. A mutation proved the gap:
    changing [index_of]'s bound from [i > h - n] to [i >= h - n], so that a
    needle sitting at the very END of the haystack is never found, left all 67
    tests green. Nothing in the suite happened to search for a string at the end
    of a capture, so a helper that could not find one looked correct.

    That is the exact failure mode the whole Tezt port exists to remove, arrived
    at from inside the port's own foundation, and it is worse here than in any
    single test: [Batch.not_contains] is an ABSENCE assertion, so a search that
    cannot find its needle passes. One weakened helper silently disarms every
    negative assertion in the suite at once.

    So the boundaries are pinned here rather than left to whichever caller
    happens to exercise them. *)

open Arch_tezt

let register () =
  Test.register ~__FILE__ ~title:"helpers: the shared string search holds at its boundaries"
    ~tags:["helpers"; "unit"]
  @@ fun () ->
  Batch.run (fun b ->
      let eq_pos ~msg actual expected =
        let show = function None -> "none" | Some i -> string_of_int i in
        if actual <> expected then
          Batch.note b "%s: got %s, expected %s" msg (show actual) (show expected)
      in
      (* Position, not just presence: a helper that returns the WRONG index
         still satisfies [contains], and [field_after] reads from it. *)
      eq_pos ~msg:"needle at the start" (index_of ~needle:"ab" "abcdef") (Some 0) ;
      eq_pos ~msg:"needle in the middle" (index_of ~needle:"cd" "abcdef") (Some 2) ;
      (* The case the surviving mutation broke. *)
      eq_pos ~msg:"needle at the very END of the haystack"
        (index_of ~needle:"ef" "abcdef") (Some 4) ;
      eq_pos ~msg:"needle IS the whole haystack" (index_of ~needle:"abc" "abc") (Some 0) ;
      eq_pos ~msg:"needle one char longer than the haystack"
        (index_of ~needle:"abcd" "abc") None ;
      eq_pos ~msg:"absent needle" (index_of ~needle:"zz" "abcdef") None ;
      eq_pos ~msg:"needle in an empty haystack" (index_of ~needle:"a" "") None ;
      (* First occurrence, not last: [field_after] reads the line following the
         first marker, and [verdict_token] picks the EARLIEST token to decide
         which verdict a tool printed. *)
      eq_pos ~msg:"the FIRST of several occurrences" (index_of ~needle:"aa" "xaayaa") (Some 1) ;
      (* Overlapping candidates: a scan that skips by the needle's length rather
         than by one would miss this. *)
      eq_pos ~msg:"overlapping candidates" (index_of ~needle:"aaa" "aaaa") (Some 0) ;
      eq_pos ~msg:"a partial prefix must not count as a match"
        (index_of ~needle:"abc" "ababab") None ;
      eq_pos ~msg:"the empty needle is at position 0" (index_of ~needle:"" "abc") (Some 0) ;

      Batch.check b ~msg:"contains agrees with index_of on a present needle"
        (contains ~needle:"ef" "abcdef") ;
      Batch.check b ~msg:"contains agrees with index_of on an absent needle"
        (not (contains ~needle:"zz" "abcdef")) ;

      (* field_after: the value after a marker, trimmed, to end of line. *)
      Batch.eq_string_opt b ~msg:"field_after reads to end of line"
        (field_after ~marker:"readiness: " "noise\nreadiness: reported complete\nmore\n")
        (Some "reported complete") ;
      Batch.eq_string_opt b ~msg:"field_after works with no trailing newline"
        (field_after ~marker:"readiness: " "noise\nreadiness: timed out")
        (Some "timed out") ;
      Batch.eq_string_opt b ~msg:"field_after takes the FIRST marker"
        (field_after ~marker:"k: " "k: one\nk: two\n")
        (Some "one") ;
      Batch.eq_string_opt b ~msg:"field_after on an absent marker is None"
        (field_after ~marker:"absent: " "k: one\n")
        None ;

      (* verdict_token exists so an assertion cannot confuse a may-reach answer
         with a proof of unreachability. Two test files did exactly that with
         `contains "REACHABLE"` while this function sat unshared in a third, so
         the distinction is pinned here rather than assumed. *)
      Batch.eq_string b ~msg:"UNREACHABLE is not read as REACHABLE"
        (verdict_token "UNREACHABLE: no resolved path a -> b — sound; G2 fails by construction.")
        "UNREACHABLE:" ;
      Batch.eq_string b ~msg:"REACHABLE (may-reach) is read as itself"
        (verdict_token "REACHABLE (may-reach): a -> b over MUST u MAY_ENUMERATED")
        "REACHABLE (may-reach)" ;
      Batch.eq_string b ~msg:"the EARLIEST token wins, not the alphabetically first"
        (verdict_token "PATH EXISTS (must-reach)\n… mentions UNKNOWN: later in the note")
        "PATH EXISTS" ;
      Batch.eq_string b ~msg:"output with no verdict is reported as such, not defaulted"
        (verdict_token "arch-query: no such function")
        "<no verdict token>" ;

      Batch.check b ~msg:"has_prefix on an exact-length match" (has_prefix ~prefix:"abc" "abc") ;
      Batch.check b ~msg:"has_prefix rejects a prefix longer than the string"
        (not (has_prefix ~prefix:"abcd" "abc")) ;

      (* [lines] backs every row COUNT in the suite, so a formatter's trailing
         blank line must not read as a row. *)
      Batch.eq_int b ~msg:"lines drops blank and whitespace-only lines"
        (List.length (lines "a\n\nb\n   \nc\n"))
        3 ;
      Batch.eq_int b ~msg:"lines on empty output counts zero rows"
        (List.length (lines "\n  \n"))
        0) ;
  Lwt.return_unit
