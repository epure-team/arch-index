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
    argument, an unknown gardening mode, an unknown unsafe-params filter). *)

open Arch_tezt

let seed =
  {|
INSERT INTO modules(path, lines) VALUES ('lib/a.ml', 500), ('lib/b.ml', 5);
|}

let db () = Fixture.main ~name:"query-limits" ~seed ()

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

      (* health.ml's "measures are never gates" test already asserts that a
         stray `--fail-on-...`-shaped argument to these MEASURE commands is
         silently ignored — deliberately, so nobody can wire one into a real
         threshold. This fix must not close that hole while closing the typo
         one: an option-shaped argument keeps falling back to the default,
         it is not the same mistake as "abc" or "-1". *)
      let outcome = query_raw db ["large-files"; "--fail-on-size"] in
      Batch.exit_code b
        ~msg:"a stray flag-shaped argument stays ignored — it is not a numeric typo" ~expected:0
        outcome ;

      (* Every call site that threads a user-supplied limit through
         [limit_of] must be covered, not just the first one — a fix scoped to
         one command while others still default-on-garbage would be a
         regression hiding behind a green test. Restricted to commands with no
         other precondition on this fixture (large-functions/fan-in need only
         the main schema's modules table; the rest of the eight limited
         commands die with exit 3 first on a fixture with no decision/coverage
         producer data, which would mask the exit-2 assertion this test is
         actually about). *)
      List.iter
        (fun cmd ->
          let outcome = query_raw db [cmd; "abc"] in
          Batch.exit_code b
            ~msg:(Printf.sprintf "'%s abc' must exit 2 like every other limited command" cmd)
            ~expected:2 outcome)
        ["fan-in"; "large-functions"]) ;
  Lwt.return_unit
