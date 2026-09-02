(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** arch-query: a limit argument that is not a non-negative integer must be
    refused, not silently defaulted (#33).

    [limit_of] used to fall back to its default on ANY unparsable argument,
    including a typo — [arch-query db.sqlite large-files abc] printed the top
    25 as if that answered the question. It also passed negatives straight
    through: SQLite reads [LIMIT -1] as unlimited, so [large-functions -1]
    dumped every row while the caller believed they had asked for exactly one.
    Both are now refused with exit 2, matching the exit-2-means-caller-error
    convention already used elsewhere in this tool (type-search with no
    argument, an unknown gardening mode, an unknown unsafe-params filter).

    Round 1 review found the first fix too coarse: exempting any
    `--`-prefixed argument from refusal (to preserve health.ml's "measures
    are never gates" doctrine) had been applied to every command sharing
    [limit_of]'s shape, not just the three MEASURE commands the doctrine is
    actually about — so [low-coverage --fail-on-coverage 80] silently
    defaulted instead of refusing, the exact false-green hole #33 exists to
    close, just spelled with two dashes. [limit_of] (strict — used by
    fan-in/dead-blocks/useless-branches/mutation-density/low-coverage) and
    [measure_limit_of] (large-files/large-functions/god-modules only) are now
    two distinct functions, and both directions are asserted below: a
    MEASURE command still silently ignores a `--`-shaped argument, everything
    else refuses it exactly like a typo. *)

open Arch_tezt

let seed =
  {|
INSERT INTO modules(path, lines) VALUES ('lib/a.ml', 500), ('lib/b.ml', 5);
|}

let db () = Fixture.main ~name:"query-limits" ~seed ()

(* Commands reachable to their own `limit_of`/`measure_limit_of` call on a
   fixture with only `modules` populated: `has_table` on a main-schema index
   is true for every table architecture-schema.sql declares, empty or not, so
   god-modules/low-coverage/dead-blocks reach it here despite having no
   producer data — only useless-branches and mutation-density additionally
   gate on a non-zero ROW COUNT, which IS zero on this fixture, and so die 3
   before ever reaching the limit argument. Excluding those two is not an
   oversight: asserting exit 2 past a command that already died 3 for an
   unrelated reason would prove nothing about the limit parse. *)
let measure_commands = ["large-files"; "large-functions"; "god-modules"]

let strict_commands = ["fan-in"; "low-coverage"; "dead-blocks"]

let register () =
  Test.register ~__FILE__ ~title:"arch-query: a bad limit argument is refused, not defaulted"
    ~tags:["arch_query"; "limits"]
  @@ fun () ->
  let db = db () in
  Batch.run (fun b ->
      (* A non-numeric limit must be refused outright, not silently answered
         with the default top-N as though the argument had been honoured. *)
      let outcome = query_raw db ["large-files"; "abc"] in
      Batch.exit_code b ~msg:"a non-numeric limit must exit 2, not fall back to the default"
        ~expected:2 outcome ;
      let _, out = outcome in
      Batch.contains b ~msg:"the refusal must name the bad argument" ~haystack:out "abc" ;

      (* A negative limit is worse than a typo: SQLite reads `LIMIT -1` as
         unlimited, so this argument means the OPPOSITE of what the caller
         asked for unless it is refused. *)
      let outcome = query_raw db ["large-files"; "-1"] in
      Batch.exit_code b ~msg:"a negative limit must exit 2, never reach SQLite as LIMIT -1"
        ~expected:2 outcome ;

      (* The empty-string sentinel ("no argument given") must still fall back
         to the default — this is not a regression on the no-argument path. *)
      let outcome = query_raw db ["large-files"] in
      Batch.exit_code b ~msg:"no limit argument at all must still use the default, not refuse"
        ~expected:0 outcome ;

      (* A valid non-negative integer, including zero, must still work. *)
      let outcome = query_raw db ["large-files"; "0"] in
      Batch.exit_code b ~msg:"an explicit zero limit is valid and must not be refused" ~expected:0
        outcome ;

      (* [int_of_string_opt] accepts OCaml integer-literal syntax, so a
         non-decimal shape must still be refused, not silently reinterpreted
         as a different number than the one written. *)
      List.iter
        (fun garbage ->
          Batch.exit_code b
            ~msg:(Printf.sprintf "'%s' is not a plain decimal limit and must be refused" garbage)
            ~expected:2
            (query_raw db ["large-files"; garbage]))
        ["0x10"; "1_0"; "+5"] ;

      (* health.ml's "measures are never gates" test already asserts that a
         stray `--fail-on-...`-shaped argument to the three MEASURE commands
         is silently ignored — deliberately, so nobody can wire one into a
         real threshold. That exemption belongs to those three commands only. *)
      List.iter
        (fun cmd ->
          Batch.exit_code b
            ~msg:
              (Printf.sprintf
                 "'%s --fail-on-x' is a MEASURE command — a stray flag-shaped argument stays \
                  ignored, not a numeric typo"
                 cmd)
            ~expected:0
            (query_raw db [cmd; "--fail-on-x"]))
        measure_commands ;

      (* Every OTHER command sharing [limit_of]'s shape is NOT that doctrine's
         subject: a flag-shaped argument there must be refused exactly like
         "abc", or the doctrine has a hole precisely where a caller would
         reach for it first (round-1 review HIGH finding). *)
      List.iter
        (fun cmd ->
          Batch.exit_code b
            ~msg:
              (Printf.sprintf
                 "'%s --fail-on-x' is NOT a measure command — a flag-shaped argument must be \
                  refused like any other non-integer"
                 cmd)
            ~expected:2
            (query_raw db [cmd; "--fail-on-x"]))
        strict_commands ;

      (* Every call site that threads a user-supplied limit through
         [limit_of]/[measure_limit_of] must be covered on the numeric-typo
         axis too, not just the first one — a fix scoped to one command while
         others still default-on-garbage would be a regression hiding behind
         a green test. *)
      List.iter
        (fun cmd ->
          Batch.exit_code b
            ~msg:(Printf.sprintf "'%s abc' must exit 2 like every other limited command" cmd)
            ~expected:2
            (query_raw db [cmd; "abc"]))
        (measure_commands @ strict_commands)) ;
  Lwt.return_unit
