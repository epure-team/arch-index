(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The health-check subcommands: missing-docs, missing-mli, type-search (exact
    facts) and large-files, large-functions, god-modules (measures).

    One rule runs through all of it. The measures are MEASURES, never verdicts:
    they sort and report a number, they do not accept a threshold, and they say
    so in their own output — so nobody wires them into a gate and then tunes the
    gate instead of the code. The facts are exact, which means a free-text
    argument must be escaped before it reaches LIKE: an unescaped [_] is a SQL
    wildcard, and a search for a literal [a_b] that silently also matches [aXb]
    is a fact that is not a fact. *)

open Arch_tezt

let fixture_sql =
  {|
INSERT INTO modules(path, lines, has_mli) VALUES
  ('lib/big.ml', 600, 1),
  ('lib/small.ml', 10, 0),
  ('lib/mid.ml', 100, 1);

INSERT INTO functions(module_id, name, signature, line_start, line_end, exposed, intent) VALUES
  ((SELECT id FROM modules WHERE path='lib/big.ml'),   'big_fn',    'int -> string',          1, 205, 1, NULL),
  ((SELECT id FROM modules WHERE path='lib/small.ml'), 'small_fn',  'unit -> unit',           1, 5,   1, 'documented'),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'mid_fn',    'Foo.instance -> bool',   1, 20,  0, NULL),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'another_fn','string -> Foo.instance', 1, 3,   1, NULL),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'fn_us',     'a_b -> c',               1, 1,   0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/mid.ml'),   'fn_x',      'aXb -> c',               1, 1,   0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/big.ml'),   'caller_a',  NULL,                     210, 212, 0, 'x'),
  ((SELECT id FROM modules WHERE path='lib/small.ml'), 'caller_b',  NULL,                     6,   7,   0, 'x');

INSERT INTO calls(caller_id, callee_id, callee_name, call_site, kind) VALUES
  ((SELECT id FROM functions WHERE name='caller_a'), (SELECT id FROM functions WHERE name='big_fn'), 'big_fn', 'x:1', 'MUST'),
  ((SELECT id FROM functions WHERE name='caller_b'), (SELECT id FROM functions WHERE name='big_fn'), 'big_fn', 'x:2', 'MUST'),
  ((SELECT id FROM functions WHERE name='caller_a'), (SELECT id FROM functions WHERE name='mid_fn'), 'mid_fn', 'x:3', 'MUST');
|}

let main_index () = Fixture.main ~name:"health" ~seed:fixture_sql ()

let register () =
  Test.register ~__FILE__ ~title:"health: facts are exact, measures are not gates"
    ~tags:["health"; "query"]
  @@ fun () ->
  let db = main_index () in
  Batch.run (fun b ->
      (* ---- missing-docs: exported and no intent ---- *)
      let out = query db ["missing-docs"] in
      Batch.contains b ~msg:"missing-docs must list big_fn (exported, no intent)" ~haystack:out
        "lib/big.ml|big_fn|1" ;
      Batch.contains b ~msg:"missing-docs must list another_fn (exported, no intent)"
        ~haystack:out "lib/mid.ml|another_fn|1" ;
      Batch.not_contains b ~msg:"missing-docs must not list small_fn (it has an intent)"
        ~haystack:out "small_fn" ;
      Batch.not_contains b ~msg:"missing-docs must not list mid_fn (not exported)" ~haystack:out
        "mid_fn" ;

      (* ---- missing-mli ---- *)
      let out = query db ["missing-mli"] in
      Batch.contains b ~msg:"missing-mli must list lib/small.ml (has_mli=0)" ~haystack:out
        "lib/small.ml" ;
      Batch.not_contains b ~msg:"missing-mli must not list lib/big.ml (has_mli=1)" ~haystack:out
        "lib/big.ml" ;
      Batch.not_contains b ~msg:"missing-mli must not list lib/mid.ml (has_mli=1)" ~haystack:out
        "lib/mid.ml" ;

      (* ---- type-search: substring over signature ---- *)
      let out = query db ["type-search"; "Foo.instance"] in
      Batch.contains b ~msg:"type-search Foo.instance must list mid_fn (parameter)" ~haystack:out
        "mid_fn" ;
      Batch.contains b ~msg:"type-search Foo.instance must list another_fn (return type)"
        ~haystack:out "another_fn" ;
      Batch.eq_int b ~msg:"type-search Foo.instance must return exactly 2 rows"
        (List.length (lines out)) 2 ;

      (* The LIKE-escaping proof: '_' is a single-character wildcard in SQL, so
         an unescaped search for 'a_b' also matches 'aXb'. *)
      let out = query db ["type-search"; "a_b"] in
      Batch.contains b ~msg:"type-search a_b must list fn_us (the literal a_b)" ~haystack:out
        "fn_us" ;
      Batch.not_contains b
        ~msg:"type-search a_b must not match fn_x (aXb): '_' must be escaped, not a wildcard"
        ~haystack:out "fn_x" ;

      (* ---- large-files ---- *)
      let out = query db ["large-files"; "2"] in
      let data = List.filter (has_prefix ~prefix:"lib/") (lines out) in
      Batch.eq_int b ~msg:"large-files 2 must return exactly 2 data rows" (List.length data) 2 ;
      (match data with
      | first :: _ ->
          Batch.contains b ~msg:"large-files must sort DESC by lines (big.ml first)"
            ~haystack:first "lib/big.ml"
      | [] -> Batch.note b "large-files returned no data rows at all") ;
      Batch.contains b
        ~msg:"large-files must state in its own output that it is a measure, not a gate"
        ~haystack:(String.lowercase_ascii (query db ["large-files"]))
        "measure only" ;

      (* ---- large-functions ---- *)
      let out = query db ["large-functions"; "3"] in
      Batch.contains b ~msg:"large-functions must list big_fn (largest span)" ~haystack:out
        "big_fn" ;
      (match List.filter (fun l -> String.contains l '|') (lines out) with
      | first :: _ ->
          Batch.contains b ~msg:"large-functions must sort DESC by line_count (big_fn first)"
            ~haystack:first "big_fn"
      | [] -> Batch.note b "large-functions returned no data rows at all") ;
      Batch.contains b
        ~msg:"large-functions must state in its own output that it is a measure, not a gate"
        ~haystack:(String.lowercase_ascii (query db ["large-functions"]))
        "measure only" ;

      (* ---- god-modules: per-module sum of function fan-in ---- *)
      let out = query db ["god-modules"] in
      Batch.contains b
        ~msg:"god-modules: lib/big.ml must show fan_in=2 (big_fn called by caller_a and caller_b)"
        ~haystack:out "lib/big.ml|2" ;
      Batch.contains b ~msg:"god-modules: lib/mid.ml must show fan_in=1 (mid_fn called by caller_a)"
        ~haystack:out "lib/mid.ml|1" ;
      Batch.not_contains b ~msg:"god-modules must not list lib/small.ml (no incoming calls)"
        ~haystack:out "lib/small.ml" ;
      Batch.contains b
        ~msg:"god-modules must state in its own output that it is a measure, not a gate"
        ~haystack:(String.lowercase_ascii (query db ["god-modules"]))
        "measure only" ;

      (* ---- no gate, anywhere ----
         A stray threshold-looking argument is IGNORED, which is the point: it
         must not be parsed into something that can fail a build. *)
      List.iter
        (fun cmd ->
          Batch.exit_code b
            ~msg:
              (Printf.sprintf "%s must not turn a stray flag-looking argument into a build failure"
                 cmd)
            ~expected:0 (query_raw db [cmd; "--fail-on-size"; "100"]))
        ["large-files"; "large-functions"; "god-modules"] ;
      let _, usage = run_command (arch_query ()) [] in
      Batch.contains b ~msg:"usage text must document the MEASURE/no-gate contract"
        ~haystack:(String.uppercase_ascii usage) "MEASURE") ;
  Lwt.return_unit

(* These commands read main-schema columns and tables (modules.has_mli,
   functions.intent) that a flat index simply does not have. Feature-detection
   must produce a REFUSAL, not a crash and not an empty answer: an empty answer
   to "which functions are undocumented" reads as "none are". *)
let register_refusal () =
  Test.register ~__FILE__ ~title:"health: refuses a flat index rather than answering emptily"
    ~tags:["health"; "query"; "contract"]
  @@ fun () ->
  let flat = Fixture.minimal_flat ~name:"health_flat" in
  Batch.run (fun b ->
      List.iter
        (fun args ->
          Batch.exit_code b
            ~msg:
              (Printf.sprintf "'%s' on a flat index must REFUSE, not crash or answer emptily"
                 (String.concat " " args))
            ~expected:3 (query_raw flat args))
        [
          ["missing-docs"];
          ["missing-mli"];
          ["type-search"; "foo"];
          ["large-files"];
          ["large-functions"];
          ["god-modules"];
        ]) ;
  Lwt.return_unit
