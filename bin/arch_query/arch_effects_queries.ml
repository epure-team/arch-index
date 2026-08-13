(** The effects / capability / dead-code half of arch-query.

    Split out only for readability — these are the subcommands that need the optional effects
    and capability tables, and every one of them REFUSES when its table is missing rather than
    answering "nothing found". "Not computed" and "nothing to report" are different facts. *)

open Arch_tools

let die code msg =
  prerr_endline msg ;
  exit code

let lower = String.lowercase_ascii

let dispatch (t : Arch_db.t) fmt ~cmd ~a ~b ~flat ~usage =
  let q ~h ~shape ~cells ~pty sql params =
    Arch_fmt.print fmt h (Arch_db.rows t ~params_ty:pty ~shape ~to_cells:cells sql params)
  in
  let unit_ty = Arch_db.Ty.unit in
      let str1 = Arch_db.Ty.string in
  let str2 = Arch_db.Ty.(t2 string string) in
  let str4 = Arch_db.Ty.(t2 (t2 string string) (t2 string string)) in
  ignore str4 ;
  let need_table name what =
    if not (Arch_db.has_table t name) then
      die 3 (Printf.sprintf "arch-query: %s requires the %s table. Run the migration first." what name)
  in
  match cmd with
  | "mutators-of" ->
      if not (Arch_db.has_table t "function_effects") then
        die 3
          "arch-query: mutators-of requires the effects tables. Run: sqlite3 <db> < \
           effects-schema-migration.sql && arch-effects-load <db>" ;
      if flat then
        q ~h:[ "function_name"; "file_path"; "how"; "soundness" ] ~shape:Arch_db.Rows.t4' ~cells:Arch_db.Rows.c4 ~pty:str2
          "WITH RECURSIVE direct_mutators(fn) AS (SELECT DISTINCT function_name FROM \
           function_effects WHERE value_kind=?), transitive(fn) AS (SELECT fn FROM \
           direct_mutators UNION SELECT c.caller_name FROM calls c JOIN transitive t ON \
           c.callee_name = t.fn WHERE c.kind IN ('MUST','MAY_ENUMERATED')) SELECT DISTINCT t.fn AS \
           function_name, COALESCE(fe.file_path, f.file_path) AS file_path, CASE WHEN dm.fn IS NOT \
           NULL THEN 'direct' ELSE 'transitive' END AS how, COALESCE(fe.soundness, 'candidate') AS \
           soundness FROM transitive t LEFT JOIN direct_mutators dm ON dm.fn = t.fn LEFT JOIN \
           function_effects fe ON fe.function_name = t.fn AND fe.value_kind=? LEFT JOIN functions f \
           ON f.name = t.fn ORDER BY how DESC, t.fn"
          (a, a)
      else
        q ~h:[ "function_name"; "file_path"; "how"; "soundness" ] ~shape:Arch_db.Rows.t4' ~cells:Arch_db.Rows.c4 ~pty:str2
          "WITH RECURSIVE direct_mutators(fn) AS (SELECT DISTINCT function_name FROM \
           function_effects WHERE value_kind=?), transitive(fn) AS (SELECT fn FROM \
           direct_mutators UNION SELECT cf.name FROM calls c JOIN functions cf ON c.caller_id = \
           cf.id JOIN transitive t ON c.callee_name = t.fn WHERE c.kind IS NULL OR c.kind IN \
           ('MUST','MAY_ENUMERATED')) SELECT DISTINCT t.fn AS function_name, \
           COALESCE(fe.file_path, m.path) AS file_path, CASE WHEN dm.fn IS NOT NULL THEN 'direct' \
           ELSE 'transitive' END AS how, COALESCE(fe.soundness, 'candidate') AS soundness FROM \
           transitive t LEFT JOIN direct_mutators dm ON dm.fn = t.fn LEFT JOIN function_effects fe \
           ON fe.function_name = t.fn AND fe.value_kind=? LEFT JOIN functions f ON f.name = t.fn \
           LEFT JOIN modules m ON f.module_id = m.id ORDER BY how DESC, t.fn"
          (a, a)
  | "effects-of" ->
      if not (Arch_db.has_table t "function_effects") then
        die 3 "arch-query: effects-of requires the effects tables." ;
      if flat then
        q ~h:[ "value_kind"; "mutating_fn"; "file_path"; "target"; "soundness" ] ~shape:Arch_db.Rows.t5' ~cells:Arch_db.Rows.c5 ~pty:str1
          "WITH RECURSIVE reach(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c JOIN reach \
           r ON c.caller_name=r.n WHERE c.kind IN ('MUST','MAY_ENUMERATED')) SELECT DISTINCT \
           fe.value_kind, fe.function_name AS mutating_fn, fe.file_path, fe.target, fe.soundness \
           FROM function_effects fe WHERE fe.function_name IN (SELECT n FROM reach) AND \
           fe.is_direct=1 ORDER BY fe.value_kind, fe.function_name"
          a
      else
        q ~h:[ "value_kind"; "mutating_fn"; "file_path"; "target"; "soundness" ] ~shape:Arch_db.Rows.t5' ~cells:Arch_db.Rows.c5 ~pty:str1
          "WITH RECURSIVE reach(n) AS (SELECT ? UNION SELECT c.callee_name FROM calls c JOIN \
           functions cf ON c.caller_id = cf.id JOIN reach r ON cf.name = r.n WHERE c.kind IS NULL \
           OR c.kind IN ('MUST','MAY_ENUMERATED')) SELECT DISTINCT fe.value_kind, fe.function_name \
           AS mutating_fn, fe.file_path, fe.target, fe.soundness FROM function_effects fe WHERE \
           fe.function_name IN (SELECT n FROM reach) AND fe.is_direct=1 ORDER BY fe.value_kind, \
           fe.function_name"
          a
  | "pure-fns" ->
      if not (Arch_db.has_table t "function_effects") then
        die 3 "arch-query: pure-fns requires the effects tables." ;
      (* SOUND definition: a function is pure iff its forward closure reaches NO direct effect
         AND no MAY_TOP edge. Computed as the backward closure over MUST∪MAY_ENUMERATED seeded
         by (a) direct-effect functions and (b) functions holding a ⊤ edge — which could call
         anything, so purity cannot be certified for them. *)
      if flat then
        q ~h:[ "name"; "file_path" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:unit_ty
          "WITH RECURSIVE impure(fn) AS (SELECT DISTINCT function_name FROM function_effects WHERE \
           is_direct=1 UNION SELECT DISTINCT caller_name FROM calls WHERE kind='MAY_TOP' UNION \
           SELECT c.caller_name FROM calls c JOIN impure i ON c.callee_name = i.fn WHERE c.kind IN \
           ('MUST','MAY_ENUMERATED')) SELECT f.name, f.file_path FROM functions f WHERE f.name NOT \
           IN (SELECT fn FROM impure) AND f.name NOT LIKE '%*TOP*%' ORDER BY f.file_path, f.name"
          ()
      else
        q ~h:[ "name"; "file_path" ] ~shape:Arch_db.Rows.t2' ~cells:Arch_db.Rows.c2 ~pty:unit_ty
          "WITH RECURSIVE impure(fn) AS (SELECT DISTINCT function_name FROM function_effects WHERE \
           is_direct=1 UNION SELECT DISTINCT cf.name FROM calls c JOIN functions cf ON c.caller_id \
           = cf.id WHERE c.kind='MAY_TOP' UNION SELECT cf.name FROM calls c JOIN functions cf ON \
           c.caller_id = cf.id JOIN impure i ON c.callee_name = i.fn WHERE c.kind IS NULL OR c.kind \
           IN ('MUST','MAY_ENUMERATED')) SELECT f.name, m.path AS file_path FROM functions f LEFT \
           JOIN modules m ON f.module_id = m.id WHERE f.name NOT IN (SELECT fn FROM impure) AND \
           f.name NOT LIKE '%*TOP*%' ORDER BY m.path, f.name"
          ()
  | "dead-code" ->
      (* The flag this subcommand's own usage documents — `dead-code [--roots
         exported|<fn1,fn2,...>]` — was never parsed. `--roots entry` put the
         literal string "--roots" in the roots list, which matches no function,
         so the root set came out EMPTY and every function in the index was
         reported dead. A "delete this code" report that names everything,
         produced by following the documented interface. Both spellings are
         accepted now, and the bare positional form still works. *)
      let roots_arg =
        match (a, b) with
        | "--roots", "" -> ""
        | "--roots", v -> v
        | _, _
          when String.length a > 8 && String.sub a 0 8 = "--roots=" ->
            String.sub a 8 (String.length a - 8)
        | _ -> a
      in
      let roots_arg = if roots_arg = "" then "exported" else roots_arg in
      let soundness = match t.Arch_db.contract with Some _ -> "sound" | None -> "candidate" in
      let vis =
        if Arch_db.has_col t "functions" "exported" then "exported"
        else if Arch_db.has_col t "functions" "exposed" then "exposed"
        else "exported"
      in
      let has_modules = Arch_db.has_table t "modules" in
      let fp_expr = if has_modules then "m.path" else "f.file_path" in
      let join_clause = if has_modules then "LEFT JOIN modules m ON f.module_id = m.id" else "" in
      let edge_join =
        if flat then "FROM calls c JOIN reach r ON c.caller_name=r.n"
        else "FROM calls c JOIN functions cf ON c.caller_id=cf.id JOIN reach r ON cf.name=r.n"
      in
      (* A reachable MAY_TOP edge means "could call anything", so nothing below it can be called
         dead: the closure is an under-approximation from there on. The candidates are still the
         list worth reading, but the verdict must not claim soundness. An index with no calls.kind
         carries no MAY_TOP information at all, so there is nothing to degrade on. *)
      let top_from =
        if flat then "FROM calls c2 WHERE c2.caller_name IN (SELECT n FROM reach)"
        else
          "FROM calls c2 JOIN functions cf2 ON c2.caller_id = cf2.id WHERE cf2.name IN (SELECT n \
           FROM reach)"
      in
      let verdict_expr =
        if Arch_db.has_col t "calls" "kind" then
          Printf.sprintf
            "CASE WHEN EXISTS(SELECT 1 %s AND (c2.kind IS NULL OR c2.kind NOT IN \
             ('MUST','MAY_ENUMERATED'))) THEN 'candidate (MAY_TOP reachable: could-call-anything, \
             cannot rule out a caller)' ELSE '%s' END"
            top_from soundness
        else Printf.sprintf "'%s'" soundness
      in
      let sql roots_clause =
        Printf.sprintf
          "WITH RECURSIVE roots(n) AS (%s), reach(n) AS (SELECT n FROM roots UNION SELECT \
           c.callee_name %s) SELECT f.name AS function_name, %s AS file_path, %s AS \
           verdict_soundness FROM functions f %s WHERE f.name NOT IN (SELECT n FROM reach) AND \
           f.name NOT LIKE '%%*TOP*%%' AND f.name NOT IN (SELECT n FROM roots) ORDER BY %s, f.name"
          roots_clause edge_join fp_expr verdict_expr join_clause fp_expr
      in
      let h = [ "function_name"; "file_path"; "verdict_soundness" ] in
      if roots_arg = "exported" then
        (* No placeholder in this branch, so the parameter type must be unit — declaring one
           anyway made Caqti bind a parameter the statement did not have. *)
        q ~h ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3 ~pty:unit_ty
          (sql (Printf.sprintf "SELECT name FROM functions WHERE %s=1" vis))
          ()
      else
        (* Variable-length root lists are the one place a typed API has nothing to offer: Caqti
           parameters are a fixed tuple, so `IN (?,?,?)` cannot be expressed. The bash version
           spliced the names into the SQL with sed. Passing ONE json array and expanding it with
           json_each keeps the arity fixed at 1 and the names as data. *)
        let names = String.split_on_char ',' roots_arg |> List.map String.trim in
        (* A root that matches no function is BROKEN INPUT, not a root set of
           zero. Silently, an unmatched root makes the reachable set empty and
           every function in the index is reported dead — the maximally wrong
           answer for a report whose whole purpose is "this code can be
           deleted", and indistinguishable from a correct answer to anyone who
           trusts it. A typo in a root name has to fail, not delete a codebase. *)
        let unknown =
          List.filter
            (fun n ->
              Arch_db.rows t ~params_ty:str1 ~shape:Arch_db.Rows.t1
                ~to_cells:Arch_db.Rows.c1
                "SELECT name FROM functions WHERE name = ? LIMIT 1" n
              = [])
            names
        in
        if unknown <> [] then
          die 2
            (Printf.sprintf
               "arch-query: dead-code: no function named %s in this index. Refusing: an \
                unmatched root makes EVERY function unreachable, so the report would list the \
                whole index as dead."
               (String.concat ", " (List.map (Printf.sprintf "%S") unknown))) ;
        q ~h ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3 ~pty:str1
          (sql "SELECT name FROM functions WHERE name IN (SELECT value FROM json_each(?))")
          (Yojson.Safe.to_string (`List (List.map (fun n -> `String n) names)))
  | "capabilities-of" ->
      need_table "function_effects" "capabilities-of" ;
      if not (Arch_db.has_col t "function_effects" "reachability_class") then
        die 3
          "arch-query: capabilities-of requires Phase-2 columns. Run: sqlite3 <db> < \
           capabilities-schema-migration.sql" ;
      let pat = "%" ^ lower a ^ "%" in
      q ~h:[ "function_name"; "rclass"; "actor_role"; "temporal_class"; "gating"; "value_touched"; "precondition"; "soundness" ] ~shape:Arch_db.Rows.t8' ~cells:Arch_db.Rows.c8 ~pty:str2
        "SELECT DISTINCT fe.function_name, COALESCE(fe.reachability_class,'?') AS rclass, \
         COALESCE(fe.actor_role,'?') AS actor_role, COALESCE(fe.temporal_class,'?') AS \
         temporal_class, COALESCE(fe.gating,'?') AS gating, COALESCE(fe.value_touched,'[]') AS \
         value_touched, COALESCE(fe.precondition,'?') AS precondition, fe.soundness FROM \
         function_effects fe WHERE lower(COALESCE(fe.file_path,'')) LIKE ? OR \
         lower(fe.function_name) LIKE ? ORDER BY fe.file_path, fe.function_name"
        (pat, pat)
  | "compose" ->
      need_table "attack_edges" "compose" ;
      q ~h:[ "to_action"; "edge_type"; "evidence"; "to_rclass"; "to_actor_role" ] ~shape:Arch_db.Rows.t5' ~cells:Arch_db.Rows.c5 ~pty:str1
        "SELECT ae.to_action, ae.edge_type, ae.evidence, COALESCE(fe.reachability_class,'?') AS \
         to_rclass, COALESCE(fe.actor_role,'?') AS to_actor_role FROM attack_edges ae LEFT JOIN \
         (SELECT function_name, reachability_class, actor_role FROM function_effects GROUP BY \
         function_name) fe ON ae.to_action = fe.function_name WHERE ae.from_action = ? AND \
         ae.edge_type IN ('sequence','removes_guard') ORDER BY ae.edge_type, ae.to_action"
        a
  | "removes-guard" ->
      need_table "attack_edges" "removes-guard" ;
      if not (Arch_db.has_col t "function_effects" "gating") then
        die 3 "arch-query: removes-guard requires Phase-2 tables. Run the migration first." ;
      q ~h:[ "gated_action"; "gating"; "unlocker"; "evidence" ] ~shape:Arch_db.Rows.t4' ~cells:Arch_db.Rows.c4 ~pty:str1
        "SELECT fe.function_name AS gated_action, fe.gating, ae.from_action AS unlocker, \
         ae.evidence FROM function_effects fe LEFT JOIN attack_edges ae ON ae.to_action = \
         fe.function_name AND ae.edge_type = 'removes_guard' WHERE lower(COALESCE(fe.gating,'')) \
         LIKE ? ORDER BY fe.function_name, ae.from_action"
        ("%" ^ lower a ^ "%")
  | "actor-paths" ->
      if not (Arch_db.has_col t "function_effects" "actor_role") then
        die 3
          "arch-query: actor-paths requires Phase-2 columns. Run: sqlite3 <db> < \
           capabilities-schema-migration.sql" ;
      let json_pat = "%\"kind\":\"" ^ a ^ "\"%" in
      q ~h:[ "action_a"; "actor_a"; "action_b"; "actor_b"; "value_touched_a"; "value_touched_b" ] ~shape:Arch_db.Rows.t6' ~cells:Arch_db.Rows.c6 ~pty:str4
        "SELECT DISTINCT a.function_name AS action_a, a.actor_role AS actor_a, b.function_name AS \
         action_b, b.actor_role AS actor_b, a.value_touched AS value_touched_a, b.value_touched AS \
         value_touched_b FROM function_effects a JOIN function_effects b ON a.actor_role IS NOT \
         NULL AND b.actor_role IS NOT NULL AND a.actor_role != b.actor_role AND a.function_name != \
         b.function_name WHERE (a.value_kind = ? OR lower(COALESCE(a.value_touched,'')) LIKE ?) AND \
         (b.value_kind = ? OR lower(COALESCE(b.value_touched,'')) LIKE ?) ORDER BY a.function_name, \
         b.function_name"
        ((a, lower json_pat), (a, lower json_pat))
  | "prune" ->
      need_table "attack_edges" "prune" ;
      let pa = "%" ^ lower a ^ "%" and pb = "%" ^ lower b ^ "%" in
      let where =
        "FROM attack_edges ae JOIN function_effects fa ON ae.from_action = fa.function_name JOIN \
         function_effects fb ON ae.to_action = fb.function_name WHERE ae.edge_type = \
         'shares_resource' AND (lower(COALESCE(fa.file_path,'')) LIKE ? OR lower(fa.function_name) \
         LIKE ?) AND (lower(COALESCE(fb.file_path,'')) LIKE ? OR lower(fb.function_name) LIKE ?)"
      in
      let ps = ((pa, pa), (pb, pb)) in
      let n = Arch_db.count4 t ("SELECT count(*) " ^ where) ps in
      if n = 0 then
        Printf.printf "PRUNE: no shared resource found between '%s' and '%s' — safe to prune (P13 passes)\n" a b
      else (
        Printf.printf "DO NOT PRUNE: %d shared_resource edge(s) between '%s' and '%s' — P13 signal\n" n a b ;
        q ~h:[ "from_action"; "to_action"; "evidence" ] ~shape:Arch_db.Rows.t3'
          ~cells:Arch_db.Rows.c3 ~pty:str4
          ("SELECT ae.from_action, ae.to_action, ae.evidence " ^ where) ps)
  | _ ->
      prerr_endline ("arch-query: unknown subcommand: " ^ cmd) ;
      prerr_endline usage ;
      exit 2
