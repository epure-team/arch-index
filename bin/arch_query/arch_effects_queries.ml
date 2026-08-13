(** The effects / capability / dead-code half of arch-query.

    Split out only for readability — these are the subcommands that need the optional effects
    and capability tables, and every one of them REFUSES when its table is missing rather than
    answering "nothing found". "Not computed" and "nothing to report" are different facts. *)

open Arch_tools

let die code msg =
  prerr_endline msg ;
  exit code

let lower = String.lowercase_ascii

(* [mp] equals [fp], or is a whole-'/'-segment suffix of it, by SUBSTR ARITHMETIC.
   Never LIKE: a path is data, and in a LIKE pattern `_` matches any character —
   including '/' — so `foo_bar.ml` matched an effect recorded in `foo/bar.ml`. *)
let suffix_match fp mp =
  Printf.sprintf
    "(%s = %s OR (length(%s) > length(%s) AND substr(%s, -length(%s)) = %s AND substr(%s, \
     -length(%s)-1, 1) = '/'))"
    fp mp fp mp fp mp mp fp mp

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
  (* On the MAIN schema every closure below HOPS through [calls.callee_id],
     never through [calls.callee_name]. A caller records its callee as dune
     spells it (`Arch_index__.Lsp_client.start`) while that function's own
     [functions.name] is `start`, so a name join fails at every module boundary;
     and a name is unique only WITHIN its module, so a name-keyed closure also
     conflates homonyms — the first fix moved only the join and left the
     recursion set keyed by name, which made the closure cross boundaries and
     then conflate on arrival. Both the join and the set are ids now.

     What CANNOT be id-keyed are the endpoints touching [function_effects]: that
     table has no function id, only (function_name, file_path). Seeds and
     projections therefore resolve a fe row to function ids by name, narrowed to
     the candidates whose module path is a '/'-segment suffix of fe.file_path
     (the CMT extractor emits build-dir paths like `default/.lib.objs/byte/m1.ml`
     against a module path of `m1.ml`), preferring the LONGEST matching path —
     `src/api.ml` beats `api.ml`, so a basename collision does not hand the row
     to the shallower homonym. The comparison is substr arithmetic, NOT LIKE: a
     path is data, and in a LIKE pattern `_` matches `/`, so `foo_bar.ml`
     matched an effect recorded in `foo/bar.ml`. When NO candidate path-matches,
     ALL same-named candidates are kept. The FALLBACK is what never narrows to
     zero; the positive arm can still pick a single wrong candidate in the
     residual below, so the guarantee is scoped to the arm that provides it.

     RESIDUAL, stated rather than claimed away: if the extractor and the indexer
     disagree about the source-relative root (an effect recorded as
     `build/api.ml` against modules `src/api.ml` and `api.ml`), the shallow
     homonym can still suffix-match alone and take the row. The cure is to
     resolve effects to function ids at LOAD time; until then this narrowing is
     best-effort and the fallback keeps it from ever dropping to zero. *)

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
        q ~h:[ "function_name"; "file_path"; "how"; "soundness" ] ~shape:Arch_db.Rows.t4' ~cells:Arch_db.Rows.c4 ~pty:str1
          ("WITH RECURSIVE dm(fn, fp, snd) AS (SELECT DISTINCT function_name, file_path, \
            soundness FROM function_effects WHERE value_kind=?), seed(id) AS (SELECT f.id FROM \
            dm JOIN functions f ON f.name = dm.fn LEFT JOIN modules m ON f.module_id = m.id \
            WHERE dm.fp IS NULL OR dm.fp = '' OR m.path IS NULL OR ("
           ^ suffix_match "dm.fp" "m.path"
           ^ " AND NOT EXISTS (SELECT 1 FROM functions f2 JOIN modules m2 ON f2.module_id = \
              m2.id WHERE f2.name = dm.fn AND "
           ^ suffix_match "dm.fp" "m2.path"
           ^ " AND length(m2.path) > length(m.path))) OR NOT EXISTS (SELECT 1 FROM functions \
              f2 JOIN modules m2 ON f2.module_id = m2.id WHERE f2.name = dm.fn AND "
           ^ suffix_match "dm.fp" "m2.path"
           ^ ")), transitive(id) AS (SELECT id FROM seed UNION SELECT c.caller_id FROM calls c \
              JOIN transitive t ON c.callee_id = t.id WHERE c.kind IS NULL OR c.kind IN \
              ('MUST','MAY_ENUMERATED')) SELECT DISTINCT f.name AS function_name, \
              COALESCE(dm2.fp, m.path) AS file_path, CASE WHEN sd.id IS NOT NULL THEN 'direct' \
              ELSE 'transitive' END AS how, COALESCE(dm2.snd, 'candidate') AS soundness FROM \
              transitive t JOIN functions f ON f.id = t.id LEFT JOIN modules m ON f.module_id = \
              m.id LEFT JOIN seed sd ON sd.id = t.id LEFT JOIN dm dm2 ON sd.id IS NOT NULL AND \
              dm2.fn = f.name UNION ALL SELECT dm.fn, dm.fp, 'direct', dm.snd FROM dm WHERE NOT \
              EXISTS (SELECT 1 FROM functions f WHERE f.name = dm.fn) ORDER BY 3 DESC, 1")
          a
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
          ("WITH RECURSIVE reach(id) AS (SELECT id FROM functions WHERE name = ? UNION SELECT \
            c.callee_id FROM calls c JOIN reach r ON c.caller_id = r.id WHERE c.callee_id IS \
            NOT NULL AND (c.kind IS NULL OR c.kind IN ('MUST','MAY_ENUMERATED'))) SELECT \
            DISTINCT fe.value_kind, fe.function_name AS mutating_fn, fe.file_path, fe.target, \
            fe.soundness FROM function_effects fe WHERE fe.is_direct=1 AND EXISTS (SELECT 1 \
            FROM functions f LEFT JOIN modules m ON f.module_id = m.id WHERE f.name = \
            fe.function_name AND f.id IN (SELECT id FROM reach) AND (fe.file_path IS NULL OR \
            fe.file_path = '' OR m.path IS NULL OR ("
           ^ suffix_match "fe.file_path" "m.path"
           ^ " AND NOT EXISTS (SELECT 1 FROM functions f2 JOIN modules m2 ON f2.module_id = \
              m2.id WHERE f2.name = fe.function_name AND "
           ^ suffix_match "fe.file_path" "m2.path"
           ^ " AND length(m2.path) > length(m.path))) OR NOT EXISTS (SELECT 1 FROM functions \
              f2 JOIN modules m2 ON f2.module_id = m2.id WHERE f2.name = fe.function_name AND "
           ^ suffix_match "fe.file_path" "m2.path"
           ^ "))) ORDER BY fe.value_kind, fe.function_name")
          a
  | "pure-fns" ->
      if not (Arch_db.has_table t "function_effects") then
        die 3 "arch-query: pure-fns requires the effects tables." ;
      (* SOUND definition: a function is pure iff its forward closure reaches NO direct effect
         AND no MAY_TOP edge. Computed as the backward closure over MUST∪MAY_ENUMERATED seeded
         by (a) direct-effect functions and (b) functions holding a ⊤ edge — which could call
         anything, so purity cannot be certified for them.

         The effect seed is DELIBERATELY name-keyed with no path narrowing, unlike the other
         closures: over-seeding marks a same-named pure function impure — and, through the
         backward closure, its ENTIRE caller cone with it — which withholds purity claims
         rather than forging one. For "pure" — a claim consumers act on — that is the only
         safe direction to be wrong in. *)
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
          "WITH RECURSIVE impure(id) AS (SELECT f.id FROM functions f JOIN function_effects fe \
           ON fe.function_name = f.name AND fe.is_direct = 1 UNION SELECT DISTINCT c.caller_id \
           FROM calls c WHERE c.kind='MAY_TOP' UNION SELECT c.caller_id FROM calls c JOIN impure \
           i ON c.callee_id = i.id WHERE c.kind IS NULL OR c.kind IN ('MUST','MAY_ENUMERATED')) \
           SELECT f.name, m.path AS file_path FROM functions f LEFT JOIN modules m ON \
           f.module_id = m.id WHERE f.id NOT IN (SELECT id FROM impure) AND f.name NOT LIKE \
           '%*TOP*%' ORDER BY m.path, f.name"
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
        | "--roots", "" ->
            (* The flag with no value must not silently mean `exported` — that
               is the same trap family as the unparsed flag: a spelling the user
               believes names roots, quietly answering a different question. *)
            die 2
              "arch-query: dead-code: --roots given without a value. Pass \
               --roots exported or --roots <fn1,fn2,...>."
        | "--roots", v -> v
        | _, _ when String.length a >= 8 && String.sub a 0 8 = "--roots=" ->
            let v = String.sub a 8 (String.length a - 8) in
            if v = "" then
              die 2
                "arch-query: dead-code: --roots= given without a value. Pass \
                 --roots exported or --roots <fn1,fn2,...>."
            else v
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
      (* On the MAIN schema the closure walks IDs, not names.

         Walking names broke the chain at every module boundary. A caller writes
         the callee as dune spells it — `Arch_index__.Lsp_client.start` — while
         the callee's own `functions.name` is `start`, so `reach` accumulated a
         name that matched no row and everything reachable only through that
         edge was reported dead. On the self-index CI builds (lib/arch_index
         alone), 83 of 813 resolved edges are of that shape; indexing the whole
         repository's build tree gives 1257 of 4254 — state the scope with the
         number, or the number reads as false to whoever measures the other one. `calls.callee_id` already holds the
         correct resolution; the query simply was not using it.

         The FLAT schema keeps names, because there the name IS the key: it has
         no ids to walk. *)
      let edge_join =
        if flat then "FROM calls c JOIN reach r ON c.caller_name=r.n"
        else "FROM calls c JOIN reach r ON c.caller_id=r.n"
      in
      let reach_step =
        if flat then "c.callee_name" else "c.callee_id"
      in
      (* An unresolved callee has no id, so it cannot extend the closure — and
         that IS lossy, not merely tidy. "Unresolved" does not mean "outside the
         index". Two shapes exist, and they are handled by DIFFERENT branches of
         [verdict_expr] below:
         - a module alias (`module A = Foo` then `A.target x`): the CMT producer
           demotes these to MAY_TOP (observed, not assumed), so the ⊤ kind
           branch already degrades them;
         - a qualified head the resolver cannot place — `Stdlib.+`, or a
           cross-library name — recorded with kind MUST/MAY_ENUMERATED. The kind
           branch NEVER fires on these, and the callee may perfectly well be an
           indexed function. The unresolved branch exists for exactly this
           shape, and its cost is stated: any cone that calls the stdlib
           degrades from `sound` to the lower-bound message, and `sound` stays
           reachable only for cones whose every edge resolves (the corpus pins
           both directions). *)
      let reach_guard = if flat then "" else " WHERE c.callee_id IS NOT NULL" in
      let key = if flat then "f.name" else "f.id" in
      (* A reachable MAY_TOP edge means "could call anything", so nothing below it can be called
         dead: the closure is an under-approximation from there on. The candidates are still the
         list worth reading, but the verdict must not claim soundness. An index with no calls.kind
         carries no MAY_TOP information at all, so there is nothing to degrade on. *)
      let top_from =
        if flat then "FROM calls c2 WHERE c2.caller_name IN (SELECT n FROM reach)"
        else "FROM calls c2 WHERE c2.caller_id IN (SELECT n FROM reach)"
      in
      let verdict_expr =
        if Arch_db.has_col t "calls" "kind" then
          if flat then
            Printf.sprintf
              "CASE WHEN EXISTS(SELECT 1 %s AND (c2.kind IS NULL OR c2.kind NOT IN \
               ('MUST','MAY_ENUMERATED'))) THEN 'candidate (MAY_TOP reachable: could-call-anything, \
               cannot rule out a caller)' ELSE '%s' END"
              top_from soundness
          else
            Printf.sprintf
              "CASE WHEN EXISTS(SELECT 1 %s AND (c2.kind IS NULL OR c2.kind NOT IN \
               ('MUST','MAY_ENUMERATED'))) THEN 'candidate (MAY_TOP reachable: could-call-anything, \
               cannot rule out a caller)' WHEN EXISTS(SELECT 1 %s AND c2.callee_id IS NULL) THEN \
               'candidate (unresolved callees in the cone — the reach set is a lower bound)' \
               ELSE '%s' END"
              top_from top_from soundness
        else Printf.sprintf "'%s'" soundness
      in
      let sql roots_clause =
        Printf.sprintf
          "WITH RECURSIVE roots(n) AS (%s), reach(n) AS (SELECT n FROM roots UNION SELECT \
           %s %s%s) SELECT f.name AS function_name, %s AS file_path, %s AS \
           verdict_soundness FROM functions f %s WHERE %s NOT IN (SELECT n FROM reach) AND \
           f.name NOT LIKE '%%*TOP*%%' AND %s NOT IN (SELECT n FROM roots) ORDER BY %s, f.name"
          roots_clause reach_step edge_join reach_guard fp_expr verdict_expr join_clause key key
          fp_expr
      in
      let h = [ "function_name"; "file_path"; "verdict_soundness" ] in
      if roots_arg = "exported" then begin
        (* An EMPTY root set makes every function unreachable, so the report
           lists the whole index as deletable — with exit 0, and stamped with
           the strongest soundness the index supports, since an empty reach
           cone touches no degrading edge. That is the same maximally-wrong
           report the unmatched-root guard below refuses, reachable through
           the DEFAULT invocation on any index with nothing exported (a
           library with no .mli, a Go package with only lowercase names).
           The guard belongs on the root SET, not on the name list. *)
        (if
           Arch_db.rows t ~params_ty:unit_ty ~shape:Arch_db.Rows.t1
             ~to_cells:Arch_db.Rows.c1
             (Printf.sprintf "SELECT name FROM functions WHERE %s=1 LIMIT 1" vis)
             ()
           = []
         then
           die 2
             (Printf.sprintf
                "arch-query: dead-code: no function has %s=1, so the root set \
                 is empty and EVERY function would be reported dead. Refusing. \
                 Pass --roots <fn1,fn2,...> to name the entry points."
                vis)) ;
        (* No placeholder in this branch, so the parameter type must be unit — declaring one
           anyway made Caqti bind a parameter the statement did not have. *)
        q ~h ~shape:Arch_db.Rows.t3' ~cells:Arch_db.Rows.c3 ~pty:unit_ty
          (sql
             (Printf.sprintf "SELECT %s FROM functions WHERE %s=1"
                (if flat then "name" else "id")
                vis))
          ()
      end
      else
        (* Variable-length root lists are the one place a typed API has nothing to offer: Caqti
           parameters are a fixed tuple, so `IN (?,?,?)` cannot be expressed. The bash version
           spliced the names into the SQL with sed. Passing ONE json array and expanding it with
           json_each keeps the arity fixed at 1 and the names as data. *)
        let names =
          String.split_on_char ',' roots_arg |> List.map String.trim
          |> List.filter (fun n -> n <> "")
        in
        if names = [] then
          die 2
            "arch-query: dead-code: the --roots list is empty. An empty root set \
             would report every function as dead." ;
        (* A root that matches no function is BROKEN INPUT, not a root set of
           zero. Silently, an unmatched root makes the reachable set empty and
           every function in the index is reported dead — the maximally wrong
           answer for a report whose whole purpose is "this code can be
           deleted", and indistinguishable from a correct answer to anyone who
           trusts it. A typo in a root name has to fail, not delete a codebase.

           On the FLAT schema the universe is NOT [functions] alone: a caller
           need not have a functions row there (arch_query.ml's `known` learned
           this same lesson), so the check spans callers too — but NOT callees.
           The rule is indexed-vs-external, not leaf-ness: an INDEXED leaf
           (`--roots island`) is a legitimate if odd question and stays
           accepted. A callee-only name is a function this index knows nothing
           about — `*TOP*`, `fmt.Println` — and treating it as "known" rooted
           the closure at a node with no outgoing edges: every function dead,
           exit 0, stamped sound, the whole-index-dead report this guard
           exists to refuse. A review proved both spellings did exactly that
           while the callee arm was present. *)
        let known_sql =
          if flat then
            "SELECT name FROM (SELECT name FROM functions UNION SELECT caller_name FROM calls) \
             WHERE name = ? LIMIT 1"
          else "SELECT name FROM functions WHERE name = ? LIMIT 1"
        in
        let unknown =
          List.filter
            (fun n ->
              Arch_db.rows t ~params_ty:str1 ~shape:Arch_db.Rows.t1
                ~to_cells:Arch_db.Rows.c1 known_sql n
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
          (sql
             (if flat then
                (* Same universe as the known-check: a legitimate flat root with
                   no functions row must still seed the closure, or the guard
                   would pass it and the query would then report everything
                   dead anyway. Callees excluded for the same reason as there. *)
                "SELECT name FROM (SELECT name FROM functions UNION SELECT caller_name FROM \
                 calls) WHERE name IN (SELECT value FROM json_each(?))"
              else "SELECT id FROM functions WHERE name IN (SELECT value FROM json_each(?))"))
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
