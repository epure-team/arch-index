(** arch-query — canned call-graph queries over an arch-index comment_db.

    {1 EDGE-KIND CONTRACT}

    When the index is built by a ⊤-marking backend it carries [calls.kind] ∈
    {MUST, MAY_ENUMERATED, MAY_TOP} and a [callgraph_contract] meta flag:

    - [MUST] a uniquely-resolved static call → trust a POSITIVE (reachability)
    - [MAY_ENUMERATED] a dynamic call bounded to a candidate set → over-approx
    - [MAY_TOP] an unresolvable/dynamic/reflective/FFI call → "could call anything"; never dropped

    [reaches] is an UNDER-approximation (MUST edges only): a positive path is must-reach ground
    truth. [unreachable] is the DUAL: sound ONLY when the graph is ⊤-marked, so it REFUSES on a
    legacy DB, where "no path" may merely hide a silently-dropped dynamic edge.

    {1 Port note}

    This replaces a bash script that interpolated arguments into SQL after stripping single
    quotes ([A="${A//\'/}"]). That is not escaping, it is mutilation — a function name
    containing a quote silently became a different name, and the query answered a question
    nobody asked. The SQL below is carried over verbatim, with [?] parameters bound as values. *)

open Arch_tools

let usage =
  {|arch-query — canned call-graph queries over an arch-index comment_db (SQLite).
Usage: arch-query <db> <subcommand> [args]

Subcommands:
  callers-of   <name>          who calls NAME (1 hop)
  callees-of   <name>          what NAME calls (1 hop)
  reachable-from <name>        transitive closure of callees from NAME
  reaches      <from> <to>     MUST-only: does a definite call path exist?
  unreachable  <from> <to>     SOUND dual (requires ⊤-marking): REACHABLE | UNREACHABLE | UNKNOWN
  escapes      <from>          the MAY_TOP (⊤) edges reachable from FROM
  may-fail     <fn> --channel <name|all> [--assume-externals-pure] [--builtin-summaries]
                               per error-channel generalisation of raises (specs/error-channels.md):
                               BOUNDED | UNBOUNDED (⊤) | NOT_A_CARRIER(channel); --channel all
                               prints one block per channel error_contract lists
  fails-with   <E> [--channel <name>] [--assume-externals-pure] [--builtin-summaries]
                               bounded nodes whose set contains E (channel default: exception);
                               ⊤ nodes listed separately as "may include"
  error-stats  --channel <name|all> [--assume-externals-pure] [--builtin-summaries]
                               per-channel generalisation of exn-stats
  raises       <fn> [--assume-externals-pure]
                               exceptions that may ESCAPE fn, transitively, minus what
                               handlers around each call site catch; BOUNDED | UNBOUNDED (⊤)
  raisers-of   <Exn> [--assume-externals-pure]
                               functions whose may-raise set contains Exn (⊤ nodes listed apart)
  exn-stats    [--assume-externals-pure]
                               bounded/unbounded share of every node, ⊤ reasons, origin counts
  fan-in       [N]             top-N most-called functions
  exported                     all exported functions
  useless-branches [limit]     decisions with an actionable verdict — dead logic
  dead-blocks [limit]          call sites in CFG-unreachable blocks
  mutation-density [limit]     functions ranked by mutation sites (advisory — never a gate)
  unresolved                   callees with no matching function row
  find         <substr>        functions whose name matches substr
  stats                        row counts (+ contract status)
  mutators-of  <value-kind>    functions that mutate <value-kind> (direct + transitive)
  effects-of   <fn>            all mutations reachable from <fn>
  pure-fns                     functions with no effects, transitively
  dead-code    [--roots exported|<fn1,fn2,...>]
  capabilities-of <component>  Phase-2 capability attributes
  compose      <action>        forward 'sequence'/'removes_guard' edges
  removes-guard <guard>        gated actions and their unlockers
  actor-paths  <value-kind>    paths across >=2 distinct actor roles
  prune        <A> <B>         P13 pruning signal
  missing-docs                 exported functions with no doc-comment (fact)
  missing-mli                  modules with no .mli (fact)
  type-search  <type>          functions whose signature mentions <type> (fact)
  large-files      [N]         modules sorted by line count, top-N (MEASURE — no gate)
  large-functions  [N]         functions sorted by line count, top-N (MEASURE — no gate)
  god-modules      [N]         modules sorted by aggregate fan-in, top-N (MEASURE — no gate)
  low-coverage     [N]         least-covered functions, latest snapshot per function, top-N
  gardening        [open|log]  open gardening tasks, or the append-only log (default: open)
  unsafe-params    [unfixed|fixed|all]  string-typed params tracked for a proper type (default: unfixed)

A "MEASURE" command reports an exact number and sorts by it. It never fails the build and never
takes a --fail-on-... threshold: "is this too big" is a human judgement, not something these
commands decide. Record that judgement in the curation ledger instead of scripting a gate on the
number.

low-coverage/gardening/unsafe-params read the curation ledgers (coverage, gardening_tasks,
gardening_log, unsafe_params) — see docs/curation-workflow.md for how they get written.

ARCH_QUERY_FORMAT=box|list|json|csv|line|markdown selects the output mode (default box).
Machine consumers should set `list` or `json`: -box wraps a one-line verdict in ~400
box-drawing characters.|}

let die code msg =
  prerr_endline msg ;
  exit code

let mode () =
  match Sys.getenv_opt "ARCH_QUERY_FORMAT" with
  | None -> Arch_fmt.Box
  | Some s -> (
      match Arch_fmt.mode_of_string s with
      | Some m -> m
      | None ->
          die 2
            (Printf.sprintf
               "arch-query: unknown ARCH_QUERY_FORMAT='%s' \
                (box|list|json|csv|line|markdown)"
               s))

(* ------------------------------------------------------------------ *)

let () =
  let argv = Array.to_list Sys.argv in
  match argv with
  | _ :: db_path :: cmd :: rest -> (
      let fmt = mode () in
      let t =
        try Arch_db.open_ro db_path
        with Arch_db.Refused m | Arch_db.Broken m -> die 2 ("arch-query: " ^ m)
      in
      let flat = t.Arch_db.schema = Arch_db.Flat in
      let a = match rest with x :: _ -> x | [] -> "" in
      let b = match rest with _ :: y :: _ -> y | _ -> "" in
      (* Every result shape is DECLARED: the Caqti row type and its projection into display
         cells, plus the column headers. Headers used to come from Sqlite3.column_name at
         runtime; hardcoding them is the cost of a typed API, and the differential gate against
         the tool being replaced is what proves they still match sqlite's own AS aliases. *)
      let q ~h ~shape ~cells ~pty sql params =
        Arch_fmt.print fmt h (Arch_db.rows t ~params_ty:pty ~shape ~to_cells:cells sql params)
      in
      (* A preamble line that says something about the ANSWER — the contract stamp, which rungs
         the decision analysis ran — printed as bare text in every format, so with
         ARCH_QUERY_FORMAT=json it landed in the middle of the JSON stream and a consumer either
         choked on it or learned to strip lines. In json mode it becomes a document of its own,
         which is already the shape of that stream (several of these commands emit more than one
         table). Text formats keep the exact line they had. *)
      let preamble ~h ~cells ~text =
        if fmt = Arch_fmt.Json then Arch_fmt.print fmt h [ List.map (fun s -> Arch_db.Text s) cells ]
        else print_endline text
      in
      let unit_ty = Arch_db.Ty.unit in
      let str1 = Arch_db.Ty.string in
      let str2 = Arch_db.Ty.(t2 string string) in
      ignore str2 ;
      let need_contract () = Arch_db.require_contract t cmd in
      (* [error_contract = "v1:exception,result,option,…"] — the channel
         list [--channel all] iterates (specs/error-channels.md "Query
         vocabulary"). *)
      let channels_of_contract t =
        match Arch_db.meta t "error_contract" with
        | None -> ["exception"]
        | Some s -> (
            match String.index_opt s ':' with
            | None -> ["exception"]
            | Some i -> String.split_on_char ',' (String.sub s (i + 1) (String.length s - i - 1)))
      in
      (* Is this name a node of the graph at all?

         On the FLAT schema a node need not have a `functions` row — an unresolved callee exists
         only as a `calls.callee_name` — so `functions` alone is not the universe. The guard below
         used to run on the main schema only, for exactly that reason, which left the flat schema
         answering "UNREACHABLE … sound" for a name that is not in the index: a typo returned a
         proof. *)
      let known name =
        if name = "" then false
        else if flat then
          Arch_db.count1 t "SELECT count(*) FROM functions WHERE name=?" name > 0
          || Arch_db.count2 t
               "SELECT count(*) FROM calls WHERE caller_name=? OR callee_name=?" (name, name)
             > 0
        else Arch_db.count1 t "SELECT count(*) FROM functions WHERE name=?" name > 0
      in
      let need_known role name =
        if not (known name) then
          die 3
            (Printf.sprintf
               "arch-query: REFUSED — %s '%s' resolves to no function in this index; '%s' cannot \
                give a sound verdict about a name it does not know."
               role name cmd)
      in
      (* A caller who typed a limit and got it wrong (not an integer, or negative — SQLite
         reads `LIMIT -1` as unlimited, so a negative limit means "dump every row" while the
         caller believes they asked for one) must not be met with a silent default: that
         reads as "here are the top N" when N was never honoured. Empty string is the
         "no argument given" sentinel used throughout this file, so it alone falls through
         to [default].

         Strict decimal digits only, not [int_of_string_opt] directly: that accepts OCaml
         integer-literal syntax, so "0x10", "1_0" and "+5" would silently be reinterpreted as
         16, 10 and 5 rather than refused — the exact residue of the hole this refusal exists
         to close. Matches the shape PR #5's bash guard already used
         ([[ "$v" =~ ^[0-9]+$ ]]). *)
      let is_decimal s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s in
      let strict_int_of s = if is_decimal s then int_of_string_opt s else None in
      let refuse_limit s =
        die 2 (Printf.sprintf "arch-query: expected a non-negative integer limit, got '%s'" s)
      in
      let limit_of s default =
        if s = "" then default
        else match strict_int_of s with Some n -> n | None -> refuse_limit s
      in
      (* Only the three MEASURE commands (large-files/large-functions/god-modules — the ones
         whose own output states "measure only, no gate/threshold") accept a stray
         `--`-shaped argument silently, per tezt/tests/health.ml's "measures are never gates"
         invariant: these commands parse no flags at all, so a `--fail-on-...` a caller reaches
         for must be ignored, never wired into a real threshold. Every OTHER command sharing
         [limit_of]'s shape (fan-in, dead-blocks, useless-branches, mutation-density,
         low-coverage) is NOT that doctrine's subject and must refuse a flag-shaped argument
         exactly like any other garbage — silently defaulting there is the same false-green
         hole #33 closes for a typo, just spelled with two dashes instead of letters. *)
      let measure_limit_of s default =
        if String.length s >= 2 && s.[0] = '-' && s.[1] = '-' then default else limit_of s default
      in
      let vis =
        if Arch_db.has_col t "functions" "exported" then "exported" else "exposed"
      in
      try
        (match cmd with
        (* PORT FIX. These four read `calls.caller_name`, which exists only on the FLAT
           schema, so on arch-index's own CMT-produced schema the bash version died with a
           raw sqlite error and exit 1 — including `callers-of`, which the README advertises
           as the variant-analysis entry point. Each now has a main-schema form. *)
        | "callers-of" ->
            if flat then
              q
                ~h:[ "caller_name"; "caller_file" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:str1
                "SELECT DISTINCT caller_name, caller_file FROM calls WHERE callee_name=? ORDER BY 1"
                a
            else
              (* On the main schema a callee is EITHER a resolved id or a qualified name
                 string, and both mean "calls a", so both must be matched or the answer is a
                 silent under-count. *)
              q ~h:[ "caller_name"; "caller_file" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:str2
                "SELECT DISTINCT cf.name AS caller_name, COALESCE(m.path,'') AS caller_file FROM \
                 calls c JOIN functions cf ON c.caller_id=cf.id LEFT JOIN modules m ON \
                 cf.module_id=m.id WHERE c.callee_name=? OR c.callee_id IN (SELECT id FROM \
                 functions WHERE name=?) ORDER BY 1"
                (a, a)
        | "callees-of" ->
            if flat then
              q
                ~h:[ "callee_name"; "callee_file" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:str1
                "SELECT DISTINCT callee_name, callee_file FROM calls WHERE caller_name=? ORDER BY 1"
                a
            else
              q ~h:[ "callee_name"; "callee_file" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:str1
                "SELECT DISTINCT c.callee_name, COALESCE(m.path,'') AS callee_file FROM calls c \
                 JOIN functions f ON c.caller_id=f.id LEFT JOIN functions ef ON c.callee_id=ef.id \
                 LEFT JOIN modules m ON ef.module_id=m.id WHERE f.name=? ORDER BY 1"
                a
        | "reachable-from" ->
            if flat then
              q ~h:[ "reachable" ] ~shape:Arch_db.Rows.t1 ~cells:Arch_db.Rows.c1 ~pty:str2
                "WITH RECURSIVE reach(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c JOIN \
                 reach r ON c.caller_name=r.n) SELECT n AS reachable FROM reach WHERE n<>? ORDER BY 1"
                (a, a)
            else
              q ~h:[ "reachable" ] ~shape:Arch_db.Rows.t1 ~cells:Arch_db.Rows.c1 ~pty:str2
                "WITH RECURSIVE reach(id) AS (SELECT id FROM functions WHERE name=? UNION SELECT \
                 c.callee_id FROM calls c JOIN reach r ON c.caller_id=r.id WHERE c.callee_id IS NOT \
                 NULL) SELECT DISTINCT f.name AS reachable FROM functions f JOIN reach r ON \
                 f.id=r.id WHERE f.name<>? ORDER BY 1"
                (a, a)
        (* SQL RETURNS FACTS, OCaml WRITES PROSE.
           These verdicts used to be assembled inside the query with `||`, which is why the
           bindings ran to NINE positional parameters per call — and nothing checks that a
           parameter list matches the `?` count, so a miscount binds NULL and silently changes
           the verdict. Asking SQL for the boolean and formatting in OCaml drops it to one
           parameter per name and states each sentence exactly once instead of four times. *)
        | "reaches" ->
            let sql =
              if flat then
                Printf.sprintf
                  "WITH RECURSIVE reach(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c \
                   JOIN reach r ON c.caller_name=r.n WHERE 1=1 %s) SELECT EXISTS(SELECT 1 FROM \
                   reach WHERE n=?)"
                  (if t.Arch_db.kinded then "AND c.kind='MUST'" else "")
              else
                Printf.sprintf
                  "WITH RECURSIVE reach(id) AS (SELECT id FROM functions WHERE name=? UNION SELECT \
                   c.callee_id FROM calls c JOIN reach r ON c.caller_id=r.id WHERE c.callee_id IS \
                   NOT NULL %s) SELECT EXISTS(SELECT 1 FROM functions f JOIN reach r ON f.id=r.id \
                   WHERE f.name=?)"
                  (if t.Arch_db.kinded then "AND c.kind='MUST'" else "")
            in
            let hit = Arch_db.count2 t sql (a, b) = 1 in
            Arch_fmt.print fmt [ "result" ]
              [ [ Arch_db.Text
                    (if hit then Printf.sprintf "PATH EXISTS (must-reach): %s -> %s" a b
                     else
                       Printf.sprintf
                         "no MUST path: %s -> %s  (NOT proof of unreachability — use `unreachable`)"
                         a b) ] ]
        | "unreachable" ->
            need_contract () ;
            (* An empty/unknown universe cannot yield a sound verdict — and that applies to the
               TARGET too: a typo'd target has no row, so the query finds no path and reports
               UNREACHABLE as a proof about a function that does not exist. *)
            need_known "source" a ;
            need_known "target" b ;
            let sql =
              if flat then
                "WITH RECURSIVE reach_res(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c \
                 JOIN reach_res r ON c.caller_name=r.n WHERE c.kind IN ('MUST','MAY_ENUMERATED')) \
                 SELECT EXISTS(SELECT 1 FROM reach_res WHERE n=?) AS hit, EXISTS(SELECT 1 FROM \
                 calls c WHERE c.caller_name IN (SELECT n FROM reach_res) AND (c.kind IS NULL OR \
                 c.kind NOT IN ('MUST','MAY_ENUMERATED'))) AS escapes"
              else
                "WITH RECURSIVE reach_res(id) AS (SELECT id FROM functions WHERE name=? UNION \
                 SELECT c.callee_id FROM calls c JOIN reach_res r ON c.caller_id=r.id WHERE \
                 c.callee_id IS NOT NULL AND c.kind IN ('MUST','MAY_ENUMERATED')) SELECT \
                 EXISTS(SELECT 1 FROM functions f JOIN reach_res r ON f.id=r.id WHERE f.name=?) AS \
                 hit, EXISTS(SELECT 1 FROM calls c WHERE c.caller_id IN (SELECT id FROM reach_res) \
                 AND (c.kind IS NULL OR c.kind NOT IN ('MUST','MAY_ENUMERATED'))) AS escapes"
            in
            let verdict =
              match
                Arch_db.rows t ~params_ty:str2 ~shape:Arch_db.Rows.i_i
                  ~to_cells:(fun (x, y) -> [ Arch_db.int_cell x; Arch_db.int_cell y ])
                  sql (a, b)
              with
              | [ [ Arch_db.Int 1; _ ] ] -> Printf.sprintf "REACHABLE (may-reach): %s -> %s" a b
              | [ [ _; Arch_db.Int 1 ] ] ->
                  Printf.sprintf
                    "UNKNOWN: no resolved path %s -> %s, but %s reaches a non-resolved (MAY_TOP / \
                     NULL / unknown-kind) edge — could-call-anything; cannot rule out a path. Do \
                     NOT kill G2."
                    a b a
              | _ ->
                  Printf.sprintf
                    "UNREACHABLE: no resolved path %s -> %s and no reachable MAY_TOP — sound; G2 \
                     fails by construction."
                    a b
            in
            Arch_fmt.print fmt [ "verdict" ] [ [ Arch_db.Text verdict ] ]
        | "escapes" ->
            need_contract () ;
            (* An unknown root yields an empty ⊤ frontier, which reads as "nothing escapes" — the
               most reassuring possible answer to a question that was never asked. *)
            need_known "source" a ;
            let hesc = [ "escaping_fn"; "call_site"; "kind" ] in
            if flat then
              q ~h:hesc ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3 ~pty:str1
                "WITH RECURSIVE reach_res(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c \
                 JOIN reach_res r ON c.caller_name=r.n WHERE c.kind IN ('MUST','MAY_ENUMERATED')) \
                 SELECT DISTINCT c.caller_name AS escaping_fn, c.call_site, COALESCE(c.kind,'NULL') \
                 AS kind FROM calls c WHERE c.caller_name IN (SELECT n FROM reach_res) AND (c.kind \
                 IS NULL OR c.kind NOT IN ('MUST','MAY_ENUMERATED')) ORDER BY 1"
                a
            else
              q ~h:hesc ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3 ~pty:str1
                "WITH RECURSIVE reach_res(id) AS (SELECT id FROM functions WHERE name=? UNION \
                 SELECT c.callee_id FROM calls c JOIN reach_res r ON c.caller_id=r.id WHERE \
                 c.callee_id IS NOT NULL AND c.kind IN ('MUST','MAY_ENUMERATED')) SELECT DISTINCT \
                 cf.name AS escaping_fn, c.call_site, COALESCE(c.kind,'NULL') AS kind FROM calls c \
                 JOIN functions cf ON c.caller_id=cf.id WHERE c.caller_id IN (SELECT id FROM \
                 reach_res) AND (c.kind IS NULL OR c.kind NOT IN ('MUST','MAY_ENUMERATED')) ORDER BY 1"
                a
        | "fan-in" ->
            (* specs/point-free-aliases.md FR-006: a point-free alias
               ([let f = M.g]) is not a CALLER of [M.g] — nobody invokes
               anything at that site; the binding transfers a body. Counting it
               as one inflates exactly the measure this query exists to report,
               and does so silently.

               Gated on the column, not on the schema: BOTH schemas carry
               [edge_form] now (the flat one because its OCaml cmt branch shares
               [collect_calls_from_expr] with the main indexer, so alias edges
               arrive there whether or not the column exists). The gate remains
               because a database built by an EARLIER binary has neither column
               nor rows, and an unconditional [WHERE edge_form IS NULL] would
               make this query ERROR against one rather than merely over-count.
               Same shape as the [functions.exported] gate below. *)
            let not_alias =
              if Arch_db.has_col t "calls" "edge_form" then "WHERE edge_form IS NULL " else ""
            in
            q ~h:[ "callee_name"; "callers" ] ~shape:Arch_db.Rows.s_i ~cells:Arch_db.Rows.csi ~pty:unit_ty
              (Printf.sprintf
                 (if flat then
                    "SELECT callee_name, count(DISTINCT caller_name) AS callers FROM calls %sGROUP \
                     BY callee_name ORDER BY callers DESC LIMIT %d"
                  else
                    "SELECT callee_name, count(DISTINCT caller_id) AS callers FROM calls %sGROUP BY \
                     callee_name ORDER BY callers DESC LIMIT %d")
                 not_alias
                 (limit_of a 25))
              ()
        | "exported" ->
            let hexp = [ "name"; "file_path" ] in
            if Arch_db.has_col t "functions" "exported" then
              q ~h:hexp ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:unit_ty
                "SELECT name, file_path FROM functions WHERE exported=1 ORDER BY file_path, name" ()
            else
              q ~h:hexp ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:unit_ty
                "SELECT f.name, m.path AS file_path FROM functions f LEFT JOIN modules m ON \
                 f.module_id=m.id WHERE f.exposed=1 ORDER BY m.path, f.name"
                ()
        | "unresolved" ->
            q ~h:[ "callee_name" ] ~shape:Arch_db.Rows.t1 ~cells:Arch_db.Rows.c1 ~pty:unit_ty
              "SELECT DISTINCT callee_name FROM calls WHERE callee_name NOT IN (SELECT name FROM \
               functions) ORDER BY 1"
              ()
        | "find" ->
            let pat = "%" ^ a ^ "%" in
            let hfind = [ "name"; "file_path"; "exported" ] in
            if Arch_db.has_col t "functions" "exported" then
              q ~h:hfind ~shape:Arch_db.Rows.s_s_i ~cells:Arch_db.Rows.cssi ~pty:str1
                "SELECT name, file_path, exported FROM functions WHERE name LIKE ? ORDER BY name" pat
            else
              q ~h:hfind ~shape:Arch_db.Rows.s_s_i ~cells:Arch_db.Rows.cssi ~pty:str1
                "SELECT f.name, m.path AS file_path, f.exposed AS exported FROM functions f LEFT \
                 JOIN modules m ON f.module_id=m.id WHERE f.name LIKE ? ORDER BY f.name"
                pat
        | "stats" ->
            let contract_s =
              match t.Arch_db.contract with
              | Some c -> c
              | None -> "<none — not ⊤-marked; 'unreachable' will refuse>"
            in
            preamble ~h:[ "contract" ] ~cells:[ contract_s ]
              ~text:("contract: " ^ contract_s) ;
            q ~h:[ "functions"; "exported"; "call_edges" ] ~shape:Arch_db.Rows.i_i_i ~cells:Arch_db.Rows.ciii ~pty:unit_ty
              (Printf.sprintf
                 "SELECT (SELECT count(*) FROM functions) AS functions, (SELECT count(*) FROM \
                  functions WHERE %s=1) AS exported, (SELECT count(*) FROM calls) AS call_edges"
                 vis)
              () ;
            if t.Arch_db.kinded then
              q ~h:[ "kind"; "edges" ] ~shape:Arch_db.Rows.s_i ~cells:Arch_db.Rows.csi ~pty:unit_ty
                "SELECT kind, count(*) AS edges FROM calls GROUP BY kind ORDER BY 2 DESC" () ;
            if Arch_db.has_table t "function_effects" then
              q ~h:[ "effect_rows"; "fns_with_effects"; "value_kinds_seen" ] ~shape:Arch_db.Rows.i_i_i ~pty:unit_ty
                ~cells:Arch_db.Rows.ciii
                "SELECT (SELECT count(*) FROM function_effects) AS effect_rows, (SELECT \
                 count(DISTINCT function_name) FROM function_effects) AS fns_with_effects, (SELECT \
                 count(DISTINCT value_kind) FROM function_effects) AS value_kinds_seen"
                () ;
            if Arch_db.has_table t "dead_code_sites" then
              q ~h:[ "dead_call_sites" ] ~shape:Arch_db.Rows.i ~cells:(fun x -> [ Arch_db.int_cell x ]) ~pty:unit_ty
                "SELECT count(*) AS dead_call_sites FROM dead_code_sites" () ;
            if Arch_db.has_col t "functions" "mutation_sites" then
              if Arch_db.count t "SELECT count(*) FROM functions WHERE mutation_sites IS NOT NULL" > 0
              then
                q ~h:[ "mutation_sites"; "deref_sites"; "fns_measured" ] ~shape:Arch_db.Rows.i_i_i ~pty:unit_ty
                  ~cells:Arch_db.Rows.ciii
                  "SELECT sum(mutation_sites) AS mutation_sites, sum(deref_sites) AS deref_sites, \
                   count(*) AS fns_measured FROM functions WHERE mutation_sites IS NOT NULL"
                  ()
              else
                preamble ~h:[ "mutability_metrics" ]
                  ~cells:[ "not computed by this backend" ]
                  ~text:"mutability metrics: not computed by this backend"
        | "useless-branches" ->
            if not (Arch_db.has_table t "decisions") then
              die 3 "arch-query: useless-branches requires a schema with a decisions table." ;
            if Arch_db.count t "SELECT count(*) FROM decisions" = 0 then
              die 3
                "arch-query: this index carries no decision analysis (no producer has run \
                 decision-lint --db against it)." ;
            (* Degradation must be VISIBLE: a clean result on a degraded run must not be
               mistakable for a clean result on a complete one. A blank is not an honest
               answer. *)
            let meta_or k = match Arch_db.meta t k with Some v when v <> "" -> v | _ -> "<not reported>" in
            let armed = meta_or "decision_armed_rungs"
            and frontend = meta_or "decision_frontend"
            and solver = meta_or "decision_solver"
            (* Files the producer could not read or could not walk. A partial run and a clean run
               both yield an empty finding list, so the difference has to be stated. *)
            and skipped = meta_or "decision_parse_failures"
            and failed = meta_or "decision_analysis_failures" in
            preamble
              ~h:[ "armed"; "frontend"; "solver"; "files_unparsed"; "files_unanalysed" ]
              ~cells:[ armed; frontend; solver; skipped; failed ]
              ~text:
                (Printf.sprintf
                   "armed: %s   frontend: %s   solver: %s   files unparsed: %s   files \
                    unanalysed: %s"
                   armed frontend solver skipped failed) ;
            q ~h:[ "file_path"; "line"; "function_name"; "verdict"; "decided_by"; "evidence" ] ~pty:unit_ty
              ~shape:Arch_db.Rows.ub_shape ~cells:Arch_db.Rows.ub_cells
              (Printf.sprintf
                 "SELECT file_path, line, function_name, verdict, decided_by, evidence FROM \
                  v_useless_branches LIMIT %d"
                 (limit_of a 50))
              ()
        | "dead-blocks" ->
            if not (Arch_db.has_table t "dead_code_sites") then
              die 3
                "arch-query: dead-blocks requires a schema with dead_code_sites (this backend did \
                 not compute block reachability)." ;
            q ~h:[ "module_path"; "function_name"; "call_site"; "callee_name" ] ~shape:Arch_db.Rows.t4' ~pty:unit_ty
              ~cells:Arch_db.Rows.c4
              (Printf.sprintf
                 "SELECT module_path, function_name, call_site, callee_name FROM v_dead_code LIMIT %d"
                 (limit_of a 50))
              ()
        | "mutation-density" ->
            if not (Arch_db.has_col t "functions" "mutation_sites") then
              die 3 "arch-query: mutation-density requires a schema with functions.mutation_sites." ;
            if Arch_db.count t "SELECT count(*) FROM functions WHERE mutation_sites IS NOT NULL" = 0
            then
              die 3
                "arch-query: this index carries no mutability metrics (backend did not compute them)." ;
            q
              ~h:[ "module_path"; "function_name"; "mutation_sites"; "deref_sites"; "line_count";
                   "mutations_per_kloc" ]
              ~shape:Arch_db.Rows.mut ~cells:Arch_db.Rows.cmut ~pty:unit_ty
              (Printf.sprintf
                 "SELECT module_path, function_name, mutation_sites, deref_sites, line_count, \
                  mutations_per_kloc FROM v_mutation_heavy LIMIT %d"
                 (limit_of a 25))
              ()
        (* ---- A1: facts — exact, deterministic lookups; no judgement involved. ---- *)
        | "missing-docs" ->
            if not (Arch_db.has_table t "v_undocumented") then
              die 3
                "arch-query: missing-docs requires the main schema's v_undocumented view (this \
                 index has no `intent`/`exposed` columns — not built from \
                 architecture-schema.sql)." ;
            (* Restate the ORDER BY explicitly rather than lean on v_undocumented's own — it
               happens to sort the same way today, but every sibling command here states its
               own order, and a future edit to the view's definition should not silently change
               this command's determinism guarantee. *)
            q ~h:[ "file_path"; "name"; "exposed" ] ~shape:Arch_db.Rows.s_s_i ~cells:Arch_db.Rows.cssi
              ~pty:unit_ty "SELECT path, name, exposed FROM v_undocumented ORDER BY path, name" ()
        | "missing-mli" ->
            if (not (Arch_db.has_table t "modules")) || not (Arch_db.has_col t "modules" "has_mli")
            then
              die 3
                "arch-query: missing-mli requires the main schema's modules.has_mli column (not \
                 built from architecture-schema.sql)." ;
            q ~h:[ "path"; "lines" ] ~shape:Arch_db.Rows.s_i ~cells:Arch_db.Rows.csi ~pty:unit_ty
              "SELECT path, lines FROM modules WHERE has_mli=0 ORDER BY path" ()
        | "type-search" ->
            if not (Arch_db.has_col t "functions" "signature") then
              die 3
                "arch-query: type-search requires the main schema's functions.signature column \
                 (not built from architecture-schema.sql)." ;
            if a = "" then die 2 "arch-query: type-search requires a <type> argument." ;
            q ~h:[ "path"; "name"; "signature" ] ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3
              ~pty:str1
              "SELECT m.path, f.name, f.signature FROM functions f JOIN modules m ON \
               f.module_id=m.id WHERE f.signature LIKE ? ESCAPE '\\' ORDER BY m.path, f.name"
              (Arch_db.like_contains a)
        (* ---- A2: measures — an exact number, sorted; NEVER a gate (no --fail-on-...). ---- *)
        | "large-files" ->
            if not (Arch_db.has_table t "modules") then
              die 3
                "arch-query: large-files requires the main schema's modules table (not built \
                 from architecture-schema.sql)." ;
            preamble ~h:[ "note" ] ~cells:[ "measure only — sorted by size, no gate/threshold" ]
              ~text:"measure only — sorted by size, no gate/threshold" ;
            q ~h:[ "path"; "lines" ] ~shape:Arch_db.Rows.s_i ~cells:Arch_db.Rows.csi ~pty:unit_ty
              (Printf.sprintf "SELECT path, lines FROM modules ORDER BY lines DESC LIMIT %d"
                 (measure_limit_of a 25))
              ()
        | "large-functions" ->
            (* NOT `has_col t "functions" "line_count"`: line_count is a STORED GENERATED
               column, and sqlite's `pragma_table_info` — what has_col queries — omits
               generated columns entirely (only `pragma_table_xinfo` reports them). That check
               would always refuse. `modules` existing is the same main-schema signal every
               sibling command here already gates on. *)
            if not (Arch_db.has_table t "modules") then
              die 3
                "arch-query: large-functions requires the main schema's functions.line_count \
                 column (not built from architecture-schema.sql)." ;
            preamble ~h:[ "note" ] ~cells:[ "measure only — sorted by size, no gate/threshold" ]
              ~text:"measure only — sorted by size, no gate/threshold" ;
            q ~h:[ "path"; "name"; "line_count" ] ~shape:Arch_db.Rows.s_s_i ~cells:Arch_db.Rows.cssi
              ~pty:unit_ty
              (Printf.sprintf
                 "SELECT m.path, f.name, f.line_count FROM functions f JOIN modules m ON \
                  f.module_id=m.id ORDER BY f.line_count DESC LIMIT %d"
                 (measure_limit_of a 25))
              ()
        | "god-modules" ->
            if not (Arch_db.has_table t "modules") then
              die 3
                "arch-query: god-modules requires the main schema's modules table (not built \
                 from architecture-schema.sql)." ;
            (* Reuses the SAME measure as `fan-in` (count DISTINCT caller_id per callee), summed
               up to the module a callee belongs to — a sort/threshold on that existing measure,
               not a new calculation. *)
            preamble ~h:[ "note" ]
              ~cells:[ "measure only — aggregate fan-in per module, no gate/threshold" ]
              ~text:"measure only — aggregate fan-in per module, no gate/threshold" ;
            (* Same exclusion as [fan-in], for the same reason and by the same
               gate — this query states it REUSES that measure, so the two must
               agree or the claim in the comment above becomes false. *)
            let not_alias =
              if Arch_db.has_col t "calls" "edge_form" then "AND edge_form IS NULL " else ""
            in
            q ~h:[ "path"; "fan_in" ] ~shape:Arch_db.Rows.s_i ~cells:Arch_db.Rows.csi ~pty:unit_ty
              (Printf.sprintf
                 "SELECT m.path, SUM(fi.callers) AS fan_in FROM (SELECT callee_id, \
                  count(DISTINCT caller_id) AS callers FROM calls WHERE callee_id IS NOT NULL \
                  %sGROUP BY callee_id) fi JOIN functions f ON f.id=fi.callee_id JOIN modules m ON \
                  m.id=f.module_id GROUP BY m.id ORDER BY fan_in DESC LIMIT %d"
                 not_alias
                 (measure_limit_of a 25))
              ()
        (* ---- B2: read the curation ledgers written by arch-coverage-load / arch-curate. ---- *)
        | "low-coverage" ->
            if not (Arch_db.has_table t "coverage") then
              die 3
                "arch-query: low-coverage requires the main schema's coverage table (populate it \
                 with arch-coverage-load)." ;
            (* Only the LATEST snapshot per function — history-safe: arch-coverage-load APPENDS
               one row per run, so without this the same function would show once per past
               snapshot instead of once, as of now. *)
            q ~h:[ "path"; "name"; "percentage"; "covered_lines"; "total_lines" ]
              ~shape:Arch_db.Rows.cov_shape ~cells:Arch_db.Rows.cov_cells ~pty:unit_ty
              (Printf.sprintf
                 "SELECT m.path, f.name, c.percentage, c.covered_lines, c.total_lines FROM \
                  coverage c JOIN functions f ON c.function_id=f.id JOIN modules m ON \
                  f.module_id=m.id WHERE c.recorded_at = (SELECT MAX(c2.recorded_at) FROM \
                  coverage c2 WHERE c2.function_id=c.function_id) ORDER BY c.percentage ASC, \
                  m.path ASC, f.name ASC LIMIT %d"
                 (limit_of a 25))
              ()
        | "gardening" -> (
            match (if a = "" then "open" else a) with
            | "open" ->
                if not (Arch_db.has_table t "gardening_tasks") then
                  die 3 "arch-query: gardening open requires the gardening_tasks table." ;
                q
                  ~h:[ "github_issue"; "category"; "title"; "module_path"; "function_name"; "status";
                       "created_at" ]
                  ~shape:Arch_db.Rows.task_shape ~cells:Arch_db.Rows.task_cells ~pty:unit_ty
                  (* Not `status='open'`: architecture-schema.sql documents status as
                     'open'|'in_progress'|'done'. A task moved to 'in_progress' is neither
                     'open' (filtered out here) nor yet in gardening_log (the 'log' branch
                     above) — under the old filter it disappeared from every view, which is
                     exactly the "re-litigated every sprint" failure docs/curation-workflow.md
                     exists to prevent. Anything not yet 'done' belongs in the open view.

                     COALESCE(t.status,'open'), not a bare `<>`: `status` has a DEFAULT but no
                     NOT NULL, so an explicitly-NULLed row would otherwise satisfy `<>'done'`
                     as false in SQL's three-valued logic and vanish from this view exactly
                     like the bug this query already fixes once — reading an unset status as
                     the schema's own documented default is the same fix applied consistently,
                     not a new judgement call. *)
                  "SELECT t.github_issue, t.category, COALESCE(t.title,''), COALESCE(m.path,''), \
                   COALESCE(f.name,''), t.status, t.created_at FROM gardening_tasks t LEFT JOIN \
                   modules m ON t.target_module_id=m.id LEFT JOIN functions f ON \
                   t.target_function_id=f.id WHERE COALESCE(t.status,'open')<>'done' ORDER BY \
                   t.created_at, t.id" ()
            | "log" ->
                if not (Arch_db.has_table t "gardening_log") then
                  die 3 "arch-query: gardening log requires the gardening_log table." ;
                q ~h:[ "date"; "contributor"; "category"; "description"; "pr_number"; "issue_number" ]
                  ~shape:Arch_db.Rows.log_shape ~cells:Arch_db.Rows.log_cells ~pty:unit_ty
                  "SELECT date, COALESCE(contributor,''), category, description, pr_number, \
                   issue_number FROM gardening_log ORDER BY date DESC, id DESC" ()
            | other ->
                die 2
                  (Printf.sprintf "arch-query: gardening: unknown mode '%s' (expected open|log)" other))
        | "unsafe-params" ->
            if not (Arch_db.has_table t "unsafe_params") then
              die 3 "arch-query: unsafe-params requires the unsafe_params table." ;
            let where =
              match (if a = "" then "unfixed" else a) with
              | "unfixed" -> "u.fixed = 0"
              | "fixed" -> "u.fixed = 1"
              | "all" -> "1=1"
              | other ->
                  die 2
                    (Printf.sprintf
                       "arch-query: unsafe-params: unknown filter '%s' (expected unfixed|fixed|all)"
                       other)
            in
            q ~h:[ "path"; "name"; "param_name"; "current_type"; "target_type"; "github_issue"; "fixed" ]
              ~shape:Arch_db.Rows.unsafe_shape ~cells:Arch_db.Rows.unsafe_cells ~pty:unit_ty
              (Printf.sprintf
                 "SELECT m.path, f.name, u.param_name, u.current_type, u.target_type, \
                  u.github_issue, u.fixed FROM unsafe_params u JOIN functions f ON \
                  u.function_id=f.id JOIN modules m ON f.module_id=m.id WHERE %s ORDER BY m.path, \
                  f.name, u.param_name"
                 where)
              ()
        | "may-fail" ->
            (* Per-channel generalisation of [raises] (specs/error-channels.md
               "Query vocabulary"). [--channel all] prints one block per
               channel [error_contract] lists — the [exception] block is
               produced by the exact same code path [raises] uses (same
               [Arch_exn.load ~channel:"exception"], same table header
               [exception; via; how], same hypothesis preamble), so it is
               byte-identical (US-3.2). *)
            let channel =
              let rec find = function
                | "--channel" :: c :: _ -> Some c
                | _ :: tl -> find tl
                | [] -> None
              in
              find rest
            in
            let positional =
              let rec drop = function
                | "--channel" :: _ :: tl -> drop tl
                | "--assume-externals-pure" :: tl -> drop tl
                | "--builtin-summaries" :: tl -> drop tl
                | x :: tl -> x :: drop tl
                | [] -> []
              in
              drop rest
            in
            let hyp = List.mem "--assume-externals-pure" rest in
            let use_builtin_summaries = List.mem "--builtin-summaries" rest in
            let a = match positional with x :: _ -> x | [] -> "" in
            let run_one channel =
              let g =
                try Arch_exn.load ~channel ~use_builtin_summaries t
                with Arch_db.Refused m -> die 3 ("arch-query: " ^ m)
              in
              let sol = Arch_exn.solve ~assume_externals_pure:hyp g in
              let cell s = Arch_db.Text s in
              if channel = "exception" && hyp then
                preamble ~h:[ "hypothesis" ] ~cells:[ "externals_pure" ]
                  ~text:"hypothesis: externals_pure — callees outside the index assumed not to raise" ;
              List.iter
                (fun key ->
                  let label = match Arch_exn.name_of g key with Some n -> n | None -> key in
                  if not (Arch_exn.is_carrier g key) then
                    Arch_fmt.print fmt [ "verdict" ]
                      [ [ cell (Printf.sprintf "%s: NOT_A_CARRIER(%s)" label channel) ] ]
                  else begin
                    let set =
                      match Arch_exn.SM.find_opt key sol with
                      | Some s -> s
                      | None -> Arch_exn.Known Arch_exn.SS.empty
                    in
                    Arch_fmt.print fmt [ channel; "via"; "how" ]
                      (Arch_exn.rows_for g ~assume_externals_pure:hyp sol key) ;
                    let v = Arch_exn.verdict ~assume_externals_pure:hyp set in
                    Arch_fmt.print fmt [ "verdict" ]
                      ([ [ cell (Printf.sprintf "%s: %s" label v) ] ]
                      @ List.map (fun r -> [ cell ("  reason: " ^ r) ]) (Arch_exn.reasons_of set))
                  end)
                (Arch_exn.keys_of_name g a)
            in
            (match channel with
            | None -> die 2 "arch-query: may-fail requires --channel <name>"
            | Some "all" ->
                need_known "function" a ;
                List.iter run_one (channels_of_contract t)
            | Some channel ->
                need_known "function" a ;
                run_one channel)
        | "fails-with" ->
            (* specs/error-channels.md "Query vocabulary": bounded nodes
               whose set contains the canonical [E] on [--channel] (default
               [exception], same generalisation direction as
               [may-fail]/[raisers-of]); ⊤ nodes are listed separately
               ("may include"), exactly [raisers-of]'s shape, per channel. *)
            let channel =
              let rec find = function
                | "--channel" :: c :: _ -> Some c
                | _ :: tl -> find tl
                | [] -> None
              in
              find rest
            in
            let channel = match channel with Some c -> c | None -> "exception" in
            let positional =
              let rec drop = function
                | "--channel" :: _ :: tl -> drop tl
                | "--assume-externals-pure" :: tl -> drop tl
                | "--builtin-summaries" :: tl -> drop tl
                | x :: tl -> x :: drop tl
                | [] -> []
              in
              drop rest
            in
            let hyp = List.mem "--assume-externals-pure" rest in
            let use_builtin_summaries = List.mem "--builtin-summaries" rest in
            let a = match positional with x :: _ -> x | [] -> "" in
            if a = "" then die 2 "arch-query: fails-with needs an error path (e.g. Not_found)" ;
            let g =
              try Arch_exn.load ~channel ~use_builtin_summaries t
              with Arch_db.Refused m -> die 3 ("arch-query: " ^ m)
            in
            let sol = Arch_exn.solve ~assume_externals_pure:hyp g in
            let target = Arch_exn.canon g a in
            let cell s = Arch_db.Text s in
            let bounded, top =
              List.fold_left
                (fun (bounded, top) key ->
                  match Arch_exn.SM.find_opt key sol with
                  | Some (Arch_exn.Known s) when Arch_exn.SS.mem target s -> (key :: bounded, top)
                  | Some (Arch_exn.Top _ as s) when Arch_exn.SS.mem target (Arch_exn.known_part s)
                    -> (bounded, key :: top)
                  | _ -> (bounded, top))
                ([], []) (Arch_exn.all_keys g)
            in
            let name k = match Arch_exn.name_of g k with Some n -> n | None -> k in
            let file k = match Arch_exn.file_of g k with Some f -> f | None -> "" in
            Arch_fmt.print fmt [ "function"; "file" ]
              (List.rev_map (fun k -> [ cell (name k); cell (file k) ]) bounded) ;
            Arch_fmt.print fmt [ "may_include"; "file" ]
              (List.rev_map (fun k -> [ cell (name k); cell (file k) ]) top)
        | "error-stats" ->
            (* specs/error-channels.md "Query vocabulary": per-channel
               generalisation of [exn-stats]; [--channel all] prints one
               block per channel [error_contract] lists. *)
            let channel =
              let rec find = function
                | "--channel" :: c :: _ -> Some c
                | _ :: tl -> find tl
                | [] -> None
              in
              find rest
            in
            let hyp = List.mem "--assume-externals-pure" rest in
            let use_builtin_summaries = List.mem "--builtin-summaries" rest in
            let cell s = Arch_db.Text s in
            let run_one channel =
              let g =
                try Arch_exn.load ~channel ~use_builtin_summaries t
                with Arch_db.Refused m -> die 3 ("arch-query: " ^ m)
              in
              let t0 = Unix.gettimeofday () in
              let sol = Arch_exn.solve ~assume_externals_pure:hyp g in
              let fixpoint_seconds = Unix.gettimeofday () -. t0 in
              if hyp then
                preamble ~h:[ "hypothesis" ] ~cells:[ "externals_pure" ]
                  ~text:"hypothesis: externals_pure — callees outside the index assumed not to raise" ;
              let n = ref 0 and nb = ref 0 and by_reason = Hashtbl.create 4 in
              Arch_exn.SM.iter
                (fun key s ->
                  if Arch_exn.is_carrier g key then begin
                    incr n ;
                    match s with
                    | Arch_exn.Known _ -> incr nb
                    | Arch_exn.Top _ ->
                        let r =
                          match Arch_exn.dominant_reason s with
                          | Some r -> Arch_exn.reason_kind_to_string r
                          | None -> "none"
                        in
                        Hashtbl.replace by_reason r (1 + try Hashtbl.find by_reason r with Not_found -> 0)
                  end)
                sol ;
              let pct x = if !n = 0 then "0.0%" else Printf.sprintf "%.1f%%" (100.0 *. float_of_int x /. float_of_int !n) in
              let nt = !n - !nb in
              let rows =
                [ [ cell "channel"; cell channel ];
                  [ cell "nodes"; cell (string_of_int !n) ];
                  [ cell "bounded"; cell (Printf.sprintf "%d (%s)" !nb (pct !nb)) ];
                  [ cell "unbounded"; cell (Printf.sprintf "%d (%s)" nt (pct nt)) ] ]
                @ List.map
                    (fun r -> [ cell ("unbounded." ^ r); cell (string_of_int (Hashtbl.find by_reason r)) ])
                    (List.sort compare (Hashtbl.fold (fun k _ acc -> k :: acc) by_reason []))
                @ [ [ cell "origins"; cell (string_of_int (Arch_exn.n_origins g)) ];
                    [ cell "escaping_origins"; cell (string_of_int (Arch_exn.n_escaping g)) ];
                    [ cell "scopes"; cell (string_of_int (Arch_exn.n_scopes g)) ];
                    [ cell "fixpoint_seconds"; cell (Printf.sprintf "%.3f" fixpoint_seconds) ] ]
              in
              Arch_fmt.print fmt [ "metric"; "value" ] rows
            in
            (match channel with
            | None -> die 2 "arch-query: error-stats requires --channel <name|all>"
            | Some "all" -> List.iter run_one (channels_of_contract t)
            | Some channel -> run_one channel)
        | "raises" | "raisers-of" | "exn-stats" ->
            (* Exception-identity may-raise sets (specs/exn-raise-sets.md).
               The hypothesis flag may sit anywhere after the subcommand; the
               first non-flag argument is the name. *)
            let hyp = List.mem "--assume-externals-pure" rest in
            let positional = List.filter (fun x -> x <> "--assume-externals-pure") rest in
            let a = match positional with x :: _ -> x | [] -> "" in
            need_contract () ;
            (* NOT_ANALYSED refusal comes from [load] itself, before any answer. *)
            let g = Arch_exn.load t in
            let t0 = Unix.gettimeofday () in
            let sol = Arch_exn.solve ~assume_externals_pure:hyp g in
            let fixpoint_seconds = Unix.gettimeofday () -. t0 in
            let hyp_line () =
              if hyp then
                preamble ~h:[ "hypothesis" ] ~cells:[ "externals_pure" ]
                  ~text:"hypothesis: externals_pure — callees outside the index assumed not to raise"
            in
            let cell s = Arch_db.Text s in
            (match cmd with
            | "raises" ->
                need_known "function" a ;
                hyp_line () ;
                List.iter
                  (fun key ->
                    let set = match Arch_exn.SM.find_opt key sol with Some s -> s | None -> Arch_exn.Known Arch_exn.SS.empty in
                    Arch_fmt.print fmt [ "exception"; "via"; "how" ]
                      (Arch_exn.rows_for g ~assume_externals_pure:hyp sol key) ;
                    let v = Arch_exn.verdict ~assume_externals_pure:hyp set in
                    let label = match Arch_exn.name_of g key with Some n -> n | None -> key in
                    Arch_fmt.print fmt [ "verdict" ]
                      ([ [ cell (Printf.sprintf "%s: %s" label v) ] ]
                      @ List.map (fun r -> [ cell ("  reason: " ^ r) ]) (Arch_exn.reasons_of set)))
                  (Arch_exn.keys_of_name g a)
            | "raisers-of" ->
                if a = "" then die 2 "arch-query: raisers-of needs an exception path (e.g. Not_found)" ;
                hyp_line () ;
                let target = Arch_exn.canon g a in
                let bounded, top =
                  List.fold_left
                    (fun (bounded, top) key ->
                      match Arch_exn.SM.find_opt key sol with
                      | Some (Arch_exn.Known s) when Arch_exn.SS.mem target s ->
                          let how =
                            if
                              List.exists
                                (fun r -> match r with [ Arch_db.Text p; _; Arch_db.Text h ] -> p = target && h = "direct" | _ -> false)
                                (Arch_exn.rows_for g ~assume_externals_pure:hyp sol key)
                            then "direct"
                            else "transitive"
                          in
                          ((key, how) :: bounded, top)
                      | Some (Arch_exn.Top _ as s) -> (bounded, (key, s) :: top)
                      | _ -> (bounded, top))
                    ([], []) (Arch_exn.all_keys g)
                in
                let name k = match Arch_exn.name_of g k with Some n -> n | None -> k in
                let file k = match Arch_exn.file_of g k with Some f -> f | None -> "" in
                Arch_fmt.print fmt [ "function"; "file"; "how" ]
                  (List.rev_map (fun (k, how) -> [ cell (name k); cell (file k); cell how ]) bounded) ;
                Arch_fmt.print fmt [ "top_function"; "file"; "reason" ]
                  (List.rev_map
                     (fun (k, s) ->
                       [ cell (name k); cell (file k);
                         cell (match Arch_exn.dominant_reason s with Some r -> Arch_exn.reason_kind_to_string r | None -> "") ])
                     top)
            | _ ->
                (* exn-stats *)
                hyp_line () ;
                let n = ref 0 and nb = ref 0 and by_reason = Hashtbl.create 4 in
                Arch_exn.SM.iter
                  (fun _ s ->
                    incr n ;
                    match s with
                    | Arch_exn.Known _ -> incr nb
                    | Arch_exn.Top _ ->
                        let r = match Arch_exn.dominant_reason s with Some r -> Arch_exn.reason_kind_to_string r | None -> "none" in
                        Hashtbl.replace by_reason r (1 + try Hashtbl.find by_reason r with Not_found -> 0))
                  sol ;
                let elapsed = fixpoint_seconds in
                let pct x = if !n = 0 then "0.0%" else Printf.sprintf "%.1f%%" (100.0 *. float_of_int x /. float_of_int !n) in
                let nt = !n - !nb in
                let rows =
                  [ [ cell "nodes"; cell (string_of_int !n) ];
                    [ cell "bounded"; cell (Printf.sprintf "%d (%s)" !nb (pct !nb)) ];
                    [ cell "unbounded"; cell (Printf.sprintf "%d (%s)" nt (pct nt)) ] ]
                  @ List.map
                      (fun r -> [ cell ("unbounded." ^ r); cell (string_of_int (Hashtbl.find by_reason r)) ])
                      (List.sort compare (Hashtbl.fold (fun k _ acc -> k :: acc) by_reason []))
                  @ [ [ cell "origins"; cell (string_of_int (Arch_exn.n_origins g)) ];
                      [ cell "escaping_origins"; cell (string_of_int (Arch_exn.n_escaping g)) ];
                      [ cell "scopes"; cell (string_of_int (Arch_exn.n_scopes g)) ];
                      [ cell "fixpoint_seconds"; cell (Printf.sprintf "%.3f" elapsed) ] ]
                in
                Arch_fmt.print fmt [ "metric"; "value" ] rows)
        | _ -> Arch_effects_queries.dispatch t fmt ~cmd ~a ~b ~flat ~usage) ;
        exit 0
      with
      (* Exit 3 is a VERDICT — "this index cannot answer that soundly". A database that could
         not be read is not a verdict, and callers that treat 3 as an answer must not receive one
         for a locked file or a SQL error. *)
      | Arch_db.Refused m -> die 3 ("arch-query: " ^ m)
      | Arch_db.Broken m -> die 2 ("arch-query: " ^ m)
      | Sqlite3.Error e -> die 2 ("arch-query: sqlite error: " ^ e))
  | _ ->
      prerr_endline usage ;
      exit 2
