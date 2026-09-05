(** arch-rules — architecture fitness functions over a SOUND call graph.

    ArchUnit, deptrac, import-linter and go-arch-lint all check DECLARED IMPORTS: whether module
    A mentions module B, not whether a call in A can reach B. A layering violation routed through
    a callback is invisible to all of them.

    This checks the second question, and — the part no other tool does — distinguishes "I proved
    it cannot" from "I could not tell":

    - [VIOLATION] a MUST path exists. Definite.
    - [POSSIBLE] reachable over MUST ∪ MAY_ENUMERATED. A dynamic dispatch could land there.
    - [UNKNOWN] the source cone reaches a ⊤ edge, so the analysis lost track. NOT a pass.
    - [PASS] proved unreachable in a closed universe. A real proof.

    For the two rule forms that ask a REACHABILITY question — [forbid reach] and [forbid effect] —
    an index that is not ⊤-marked can never yield PASS: it degrades to [UNKNOWN_NO_CONTRACT],
    because "no path found" in a graph that silently drops dynamic edges is not a proof of
    anything.

    [forbid dep] and [forbid exported] are NOT reachability questions. They read a declared fact
    (a module's own [open]/[include]/alias list; a function's [exported] flag) straight out of the
    index, so their PASS is exact on any backend and does not consult the ⊤ contract at all. That
    is why they are marked [exact] in the result. The price is that their PASS is only as complete
    as the FACTS the producer wrote: it says "no such declaration was recorded", which is a proof
    about the index, not about a call graph. A selector that matches nothing therefore has to be
    caught explicitly — see [NO_SOURCE] below — or an [exact] PASS would be indistinguishable from
    a rule aimed at a module that does not exist.

    Orthogonally to all of the above, any rule form can report:

    - [NO_SOURCE] / [NO_TARGET] the rule quantifies over nothing. VACUOUS: it cannot fail, so a
      green result establishes nothing. Governed by [--on-vacuous], which fails by default.
    - [NOT_COMPUTED] the index carries no data of the kind the rule needs, so it was never
      evaluated at all. Governed by [--on-not-computed]. *)

open Arch_tools
module SS = Arch_graph.SS

let usage =
  {|arch-rules — architecture fitness functions over a sound call graph.

Usage: arch-rules <db> [rules-file] [--format text|md|json]
                  [--on-unknown warn|fail] [--on-possible fail|warn] [--on-vacuous fail|warn]
                  [--on-not-computed fail|warn]

Rule syntax (line-oriented, # comments, one statement per rule):
  rule "ui must not reach persistence"
    forbid reach from file:src/ui/** to file:lib/db/**
  rule "only the api layer is exported"
    forbid exported outside file:lib/api/**
  rule "validate must not mutate global state"
    forbid effect from file:src/validate/** kind:GlobalVar
  rule "core must not declare a dep on the web framework"
    forbid dep from module:lib/core/** to module:Web.**|}

let die msg =
  prerr_endline msg ;
  exit 2

type body =
  | Reach of Arch_sel.t * Arch_sel.t
  | Dep of Arch_sel.t * Arch_sel.t
  | Exported of Arch_sel.t
  | Effect of Arch_sel.t * string

type rule = { name : string; body : body }

(* The rule FORM, reported alongside the verdict so a consumer can tell a semantic `reach`
   result from a syntactic `dep` one without re-parsing the rules file. *)
let kind_of = function
  | Reach _ -> "reach"
  | Dep _ -> "dep"
  | Exported _ -> "exported"
  | Effect _ -> "effect"

(* ------------------------------------------------------------------ *)
(* parsing — a malformed rule file ABORTS                              *)
(* ------------------------------------------------------------------ *)

(* Every call site names the selector kinds it can honestly answer. [ext:] appears in exactly
   one: the target of `forbid reach`. See Arch_sel.parse for why that is enforced by the type
   rather than by convention. *)
let structural = Arch_sel.structural
let with_ext = Arch_sel.[ File; Fn; Module; Ext ]

(* `forbid dep` never consults the graph: both operands are globbed straight against strings read
   out of `module_deps` (see [Dep]'s evaluator below), so `file:`/`fn:` are just as unimplemented
   there as `ext:` is — `Dep` throws the selector KIND away entirely and keeps only the pattern.
   [Module] is the only kind whose reading of a `dep` operand matches what a rule author would
   expect from the syntax; the other three would be silently reinterpreted as module-path globs. *)
let dep_allow = Arch_sel.[ Module ]

let sel ~allow tok line =
  match Arch_sel.parse ~allow tok with
  | Ok s -> s
  | Error e -> die (Printf.sprintf "arch-rules: line %d: %s" line e)

(** A rule that silently fails to parse is a gate that silently stops gating, which is the worst
    possible failure mode for this tool. *)
let parse_rules path =
  let ic = try open_in path with Sys_error e -> die ("arch-rules: cannot read rules file: " ^ e) in
  let rules = ref [] and pending = ref None and lineno = ref 0 in
  let finish () =
    match !pending with
    | Some (n, None, ln) ->
        die (Printf.sprintf "arch-rules: line %d: rule %S has no body" ln n)
    | Some (n, Some b, _) -> rules := { name = n; body = b } :: !rules
    | None -> ()
  in
  (try
     while true do
       let raw = input_line ic in
       incr lineno ;
       let line =
         String.trim (match String.index_opt raw '#' with Some i -> String.sub raw 0 i | None -> raw)
       in
       if line <> "" then
         if String.length line > 5 && String.sub line 0 5 = "rule " then (
           finish () ;
           let q = String.index_opt line '"' in
           match q with
           | Some i -> (
               match String.index_from_opt line (i + 1) '"' with
               | Some j -> pending := Some (String.sub line (i + 1) (j - i - 1), None, !lineno)
               | None -> die (Printf.sprintf "arch-rules: line %d: unterminated rule name" !lineno))
           | None -> die (Printf.sprintf "arch-rules: line %d: rule needs a quoted name" !lineno))
         else
           match !pending with
           | None ->
               die
                 (Printf.sprintf "arch-rules: line %d: statement outside any rule — start with: rule \"name\""
                    !lineno)
           | Some (_, Some _, _) ->
               die
                 (Printf.sprintf "arch-rules: line %d: rule already has a body; one statement per rule"
                    !lineno)
           | Some (n, None, ln) ->
               let toks = String.split_on_char ' ' line |> List.filter (fun s -> s <> "") in
               let b =
                 match toks with
                 | [ "forbid"; "reach"; "from"; a; "to"; c ] ->
                     (* Source structural, target may be `ext:` — an external leaf is a legitimate
                        thing to forbid REACHING, and an illegitimate thing to start FROM. *)
                     Reach (sel ~allow:structural a !lineno, sel ~allow:with_ext c !lineno)
                 | [ "forbid"; "dep"; "from"; a; "to"; c ] ->
                     (* See [dep_allow]: `Module` only, on both sides. `ext:` on the TARGET side
                        is not meaningless — `module_deps.target_module IS NULL` genuinely marks
                        a dependency on an external module, there is just no code reading that
                        column into a selectable population yet. It is UNIMPLEMENTED, not absurd;
                        `file:`/`fn:` are refused for the unrelated reason above. *)
                     Dep (sel ~allow:dep_allow a !lineno, sel ~allow:dep_allow c !lineno)
                 | [ "forbid"; "exported"; "outside"; a ] -> Exported (sel ~allow:structural a !lineno)
                 | [ "forbid"; "effect"; "from"; a; k ]
                   when String.length k > 5 && String.sub k 0 5 = "kind:" ->
                     Effect (sel ~allow:structural a !lineno, String.sub k 5 (String.length k - 5))
                 | _ ->
                     die
                       (Printf.sprintf
                          "arch-rules: line %d: unrecognised rule body %S. Supported:\n\
                          \    forbid reach from <sel> to <sel>\n\
                          \    forbid dep from <sel> to <sel>\n\
                          \    forbid exported outside <sel>\n\
                          \    forbid effect from <sel> kind:<VALUE_KIND>"
                          !lineno line)
               in
               pending := Some (n, Some b, ln)
     done
   with End_of_file -> ()) ;
  close_in ic ;
  finish () ;
  let rs = List.rev !rules in
  if rs = [] then die (Printf.sprintf "arch-rules: %s defines no rules — refusing a vacuous PASS" path) ;
  rs

(* ------------------------------------------------------------------ *)
(* evaluation                                                          *)
(* ------------------------------------------------------------------ *)

type result = {
  rule : string;
  kind : string;
  verdict : string;
  detail : string list;
  (* The untruncated count `detail` was capped from (via `take 20`). Equal to `List.length detail`
     when nothing was cut — a consumer that only ever sees the capped list has no way to tell "20
     offenders, shown in full" from "20 shown out of 200" without this. *)
  detail_total : int;
  note : string option;
  (* Selector cardinalities, reported for `reach` rules. They are what makes a VACUOUS verdict
     checkable and what pins the glob boundary: a rule aimed at write.ts must match exactly one
     file, not also my_write.ts. *)
  sizes : (int * int) option;
  (* True for the rule forms that need NO reachability — `exported` and `dep` read a fact
     directly, so their verdict is exact on any backend, including one with no edge kinds. *)
  exact : bool;
  (* A concrete witness path (labels, source-to-target order) for VIOLATION/POSSIBLE, or
     source-to-⊤-frontier for UNKNOWN — the offender LIST already says a path exists somewhere;
     this is the path, checkable by a reviewer without re-deriving it by hand. Every other
     verdict form carries no reachability claim, so [[]] there. *)
  witness : string list;
}

(** Order matters: a definite path is VIOLATION even when the source ALSO reaches a ⊤ edge.
    UNKNOWN is what you say when you found nothing and cannot rule it out — never a way to
    downgrade something you did find. *)
(* `sound` here is Arch_db.contract_ok's verdict, not the raw flag: a flag set on an index whose
   `kind` column is missing or partly NULL is worse than no flag, because SQL's 3-valued logic
   makes such an edge invisible to both the closure and the ⊤ check. The caller passes the result
   of the full check. *)
let reach_verdict (g : Arch_graph.t) ~sound src dst =
  if SS.is_empty src then ("NO_SOURCE", [])
  else if SS.is_empty dst then ("NO_TARGET", [])
  else
    let must = SS.union (Arch_graph.closure src g.must_fwd) (SS.inter src dst) in
    let hit = SS.inter must dst in
    if not (SS.is_empty hit) then ("VIOLATION", SS.elements hit)
    else
      let anyc = Arch_graph.closure src g.fwd in
      let hit = SS.inter anyc dst in
      if not (SS.is_empty hit) then ("POSSIBLE", SS.elements hit)
      else
        let escaping =
          SS.filter (fun k -> Arch_graph.SM.mem k g.tops) (SS.union anyc src) |> SS.elements
        in
        if escaping <> [] then ("UNKNOWN", escaping)
        else if not sound then ("UNKNOWN_NO_CONTRACT", [])
        else ("PASS", [])

let take n l = List.filteri (fun i _ -> i < n) l

let eval (t : Arch_db.t) (g : Arch_graph.t) ~sound r =
  let lbl k = Arch_graph.label g k in
  match r.body with
  | Reach (_, d) when fst d = Arch_sel.Ext && t.Arch_db.schema = Arch_db.Flat ->
      (* This is a claim about `arch-load`, the one producer of this schema in this repo, not
         about what the flat schema can hold: `calls.callee_name` with no matching `functions`
         row is a perfectly representable external leaf, and a hand-built flat DB can carry one.
         `arch-load` never writes that shape — it synthesises a `functions` row for every callee
         it sees, so a stream declaring 2 functions and calling `Stdlib.+` writes 3 — so on every
         index this tool's own pipeline produces, [ext_keys] is empty by construction, not empty
         because nothing happened to match.

         So this is NOT_COMPUTED rather than a silent empty match: the guard refuses every
         `ext:` reach question on this schema, unconditionally, because `arch-load`'s OUTPUT is
         known in advance to never populate that population — a property of what this repo's one
         producer writes, not a property of what a flat DB could in principle hold. A hand-built
         flat DB can carry a genuine external leaf (a `calls` row with no matching `functions`
         row), and on such a DB `ext:` could sometimes be answered directly — but arch-rules
         cannot distinguish that DB from `arch-load`'s ordinary output, so it refuses both alike
         rather than silently returning an empty match on the common case. It fails the gate by
         default. *)
      { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
        detail_total = 0; sizes = None; witness = [];
        note =
          Some
            (Printf.sprintf
               "%s is refused on a flat (NDJSON) index: arch-load gives every callee it writes a \
                function row, so on this producer's actual output the population ext: needs is \
                never populated — not zero external leaves found, but none ever written by this \
                pipeline. arch-rules cannot tell an arch-load-produced flat DB apart from a \
                hand-built one that might hold a genuine external leaf, so it refuses this \
                selector on the flat schema unconditionally rather than risk a silent empty match."
               (Arch_sel.to_string d)) }
  | Reach (s, d) ->
      let src = Arch_sel.select g s and dst = Arch_sel.select g d in
      let v, hit = reach_verdict g ~sound src dst in
      let note =
        match v with
        | "NO_SOURCE" ->
            Some
              (Printf.sprintf
                 "selector %s matched nothing — the rule is VACUOUS. A rule that matches no code \
                  cannot fail, which makes a green result meaningless."
                 (Arch_sel.to_string s))
        | "NO_TARGET" ->
            Some (Printf.sprintf "selector %s matched nothing — VACUOUS for the same reason." (Arch_sel.to_string d))
        | "UNKNOWN" ->
            Some
              "the source cone reaches an unresolvable (⊤) edge, so no path was found but none \
               can be ruled out either"
        | "VIOLATION" when not (SS.is_empty (SS.inter src dst)) ->
            (* The two selectors OVERLAP. Every function matched by both is trivially "reachable
               from itself", so the rule fires with no call path involved — and the offender
               list looked identical to one produced by a real path. Whether that is the
               intended reading is the author's call, but they cannot make it without being
               told which case they are in. *)
            Some
              (Printf.sprintf
                 "%d function(s) are matched by BOTH selectors (%s and %s), so they violate this \
                  rule by being in the forbidden target at all — not by any call path. Narrow one \
                  selector if that was not the intent."
                 (SS.cardinal (SS.inter src dst))
                 (Arch_sel.to_string s) (Arch_sel.to_string d))
        | "UNKNOWN_NO_CONTRACT" ->
            Some
              "this index is not ⊤-marked, so 'no path' is not a proof — a dropped dynamic edge \
               is indistinguishable from an absent one. Rebuild with a contract-stamping backend \
               to get a real PASS."
        | _ -> None
      in
      (* The offender list already says a path exists somewhere; this is the path itself, so a
         reviewer can check the verdict without re-deriving it by hand. A VIOLATION `hit` can mix
         self-overlap members (src ∩ dst — membership, not a call path) with genuine must-reachable
         targets in the SAME result, when a rule has both an accidental overlap and a real multi-hop
         violation: only the overlap members themselves get no witness; the first hit that is NOT
         also an overlap member still gets a real BFS path. *)
      let witness =
        match v with
        | "VIOLATION" -> (
            match List.find_opt (fun k -> not (SS.mem k src && SS.mem k dst)) hit with
            | None -> []
            | Some target -> (
                match Arch_graph.shortest_path_from_set ~adj:g.must_fwd ~from:src ~to_:target with
                | Some path -> List.map lbl path
                | None -> []))
        | "POSSIBLE" -> (
            match hit with
            | target :: _ -> (
                match Arch_graph.shortest_path_from_set ~adj:g.fwd ~from:src ~to_:target with
                | Some path -> List.map lbl path
                | None -> [])
            | [] -> [])
        | "UNKNOWN" -> (
            (* `hit` here is `escaping` (reach_verdict), the SAME set `detail` is built from — the
               witness must end at `hit`'s own head, not at whichever ⊤-holder a plain nearest-search
               happens to find first, or the two fields could name different functions. *)
            match hit with
            | target :: _ -> (
                match Arch_graph.shortest_path_from_set ~adj:g.fwd ~from:src ~to_:target with
                | Some path -> List.map lbl path
                | None -> [])
            | [] -> [])
        | _ -> []
      in
      { rule = r.name; kind = kind_of r.body; exact = false; verdict = v; detail = List.map lbl (take 20 hit);
        detail_total = List.length hit; note; sizes = Some (SS.cardinal src, SS.cardinal dst); witness }
  | Exported s ->
      let allowed = Arch_sel.select g s in
      let offenders =
        List.filter (fun (n : Arch_graph.node) -> n.exported && not (SS.mem n.key allowed))
          (Arch_graph.nodes g)
        |> List.sort (fun (a : Arch_graph.node) b -> compare a.name b.name)
      in
      (* The population this rule quantifies over is the EXPORTED functions, not the selector.
         With none in the index there is nothing to check, and "no offender found" is a fact about
         an empty set, not a proof about the code — the same vacuity `reach` reports as NO_SOURCE.
         It used to print `pass`, and since the summary now calls a PASS *proved*, that vacuity was
         being promoted to the word "proved" in the one line humans read.

         Note the case split: if the selector matched nothing while exported functions DO exist,
         every one of them is an offender and the verdict is VIOLATION — loud, and never
         downgraded to VACUOUS. So `offenders = []` with an empty selector is exactly the
         "nothing is exported at all" case. *)
      let exported_total =
        List.length (List.filter (fun (n : Arch_graph.node) -> n.exported) (Arch_graph.nodes g))
      in
      { rule = r.name; kind = kind_of r.body; exact = true; witness = [];
        sizes = Some (SS.cardinal allowed, exported_total);
        verdict =
          (if exported_total = 0 then "NO_SOURCE"
           else if offenders = [] then "PASS"
           else "VIOLATION");
        detail = List.map (fun (n : Arch_graph.node) -> lbl n.key) (take 20 offenders);
        detail_total = List.length offenders;
        note =
          (if exported_total = 0 then
             Some
               "no function in this index is marked exported, so this rule quantifies over the \
                empty set — the rule is VACUOUS. Either the producer does not record export \
                status, or there is genuinely nothing to check; a green result means nothing \
                either way."
           else if SS.is_empty allowed then
             Some
               (Printf.sprintf
                  "selector %s matched nothing, so EVERY exported function is an offender — check \
                   the selector before believing the list."
                  (Arch_sel.to_string s))
           else None) }
  | Effect (s, kind) ->
      (* Selected once and reused: the vacuity guard and the cone below must be reading the SAME
         set, or the guard could pass on one selection and the cone be built from another. *)
      let effect_src = lazy (Arch_sel.select g s) in
      if not (Arch_db.nonempty t "function_effects") then
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
          detail_total = 0; sizes = None; witness = [];
          note =
            Some
              "this index has no effects data — 'no effect found' would be a lie. Effects are \
               produced by the OCaml .cmt backend (effects-schema-migration.sql + arch-effects-load)." }
      else if SS.is_empty (Lazy.force effect_src) then
        (* An empty source selector makes the cone empty, so no effect can ever be found and the
           rule reports a proof it never performed. Same vacuity as `reach`'s NO_SOURCE, and it
           reached the summary as "proved". *)
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NO_SOURCE"; detail = [];
          (* `sizes = None` like every other Effect branch: an effect rule's JSON row has never
             carried source_size/target_size, and making one verdict the exception would be a
             schema a consumer cannot rely on. The note carries the evidence instead. *)
          detail_total = 0; sizes = None; witness = [];
          note =
            Some
              (Printf.sprintf
                 "selector %s matched nothing — the rule is VACUOUS. An empty source cone contains \
                  no effects by construction, which is not a result about your code."
                 (Arch_sel.to_string s)) }
      else
        let src = Lazy.force effect_src in
        let cone = SS.union src (Arch_graph.closure src g.fwd) in
        let names =
          SS.fold
            (fun k acc ->
              match Arch_graph.SM.find_opt k g.nodes with
              | Some (n : Arch_graph.node) -> n.name :: acc
              | None -> acc)
            cone []
        in
        let json = Yojson.Safe.to_string (`List (List.map (fun n -> `String n) names)) in
        let hits =
          Arch_db.rows t
            ~params_ty:Arch_db.Ty.(t2 string string)
            ~shape:Arch_db.Rows.t3' ~to_cells:Arch_db.Rows.c3
            "SELECT DISTINCT function_name, effect_kind, value_kind FROM function_effects WHERE \
             function_name IN (SELECT value FROM json_each(?)) AND value_kind = ?"
            (json, kind)
        in
        let escaping = SS.filter (fun k -> Arch_graph.SM.mem k g.tops) cone in
        if hits <> [] then
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "VIOLATION"; sizes = None; witness = [];
            detail =
              take 20
                (List.map (fun row -> String.concat " " (List.map Arch_db.string_of_cell row)) hits);
            detail_total = List.length hits; note = None }
        else if not (SS.is_empty escaping) then
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "UNKNOWN"; detail = [];
            detail_total = 0; sizes = None; witness = [];
            note =
              Some
                (Printf.sprintf
                   "no %s effect found, but the cone escapes through %d ⊤ edge(s) — the effect \
                    could be behind one"
                   kind (SS.cardinal escaping)) }
        else
          { rule = r.name; kind = kind_of r.body; exact = false;
            verdict = (if sound then "PASS" else "UNKNOWN_NO_CONTRACT");
            detail = []; detail_total = 0; note = None; sizes = None; witness = [] }
  | Dep (s, d) ->
      if (not (Arch_db.has_table t "module_deps")) || t.schema = Arch_db.Flat then
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
          detail_total = 0; sizes = None; witness = [];
          note =
            Some
              "this index has no module_deps — declared-dependency rules are produced today only by \
               the OCaml .cmt backend. NOTE: this is the one rule form that is a syntactic \
               over-approximation (it checks what a module DECLARES, like every other tool in the \
               category); `forbid reach` is the semantic version and works on every backend." }
      else
        let rows =
          Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t4' ~to_cells:Arch_db.Rows.c4
            "SELECT ms.path, COALESCE(mt.path, md.target_path), md.dep_kind, \
             CAST(md.line_number AS TEXT) FROM module_deps md JOIN modules ms ON md.source_module \
             = ms.id LEFT JOIN modules mt ON md.target_module = mt.id"
            ()
        in
        let hits =
          List.filter_map
            (fun row ->
              match List.map Arch_db.string_of_cell row with
              | [ a; b; k; ln ]
                when Arch_sel.glob_match (snd s) a && Arch_sel.glob_match (snd d) b ->
                  Some (Printf.sprintf "%s --%s--> %s  (line %s)" a k b ln)
              | _ -> None)
            rows
        in
        (* The SOURCE side is checkable for vacuity and the target side is not, and the asymmetry
           is not an oversight.

           A `dep` rule quantifies over the modules matched by [s]. If the index knows no module of
           that name the rule can never fire — a typo'd path, or a directory that was renamed —
           and "no forbidden dep found" is a statement about the empty set. That is NO_SOURCE, and
           it is exactly what `reach` already reports.

           The target side gets NO analogous check, unlike `reach`'s NO_TARGET. `reach`'s target
           selector ranges over functions that EXIST in the index; a `dep` target ranges over
           module paths that are ALREADY DEPENDED ON (external targets appear only as
           module_deps.target_path — there is no independent universe of them to match against).
           So "nothing matches `Web.**`" is not evidence of a typo, it is the rule succeeding:
           `forbid dep ... to module:Web.**` is a preventive rule whose whole purpose is to hold
           while nothing depends on Web. Reporting that as VACUOUS would fail the gate — by
           default, since --on-vacuous is fail-closed — precisely when the codebase is clean. *)
        let module_paths =
          Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1
            ~to_cells:Arch_db.Rows.c1 "SELECT path FROM modules" ()
        in
        let source_size =
          List.length
            (List.filter
               (fun row ->
                 match List.map Arch_db.string_of_cell row with
                 | [ p ] -> Arch_sel.glob_match (snd s) p
                 | _ -> false)
               module_paths)
        in
        { rule = r.name; kind = kind_of r.body; exact = true; witness = [];
          verdict =
            (if source_size = 0 then "NO_SOURCE" else if hits = [] then "PASS" else "VIOLATION");
          detail = take 20 hits; detail_total = List.length hits;
          (* Source only, like `exported`: a `dep` rule has no target POPULATION to size (see
             above), so a second number here would be a field with no meaning. *)
          sizes = Some (source_size, 0);
          note =
            Some
              (if source_size = 0 then
                 Printf.sprintf
                   "selector %s matches no module in this index (of %d) — the rule is VACUOUS. It \
                    cannot fail, so a green result says nothing about your code; check the path \
                    before trusting it."
                   (Arch_sel.to_string s) (List.length module_paths)
               else
                 "declared-dependency check: it sees what the module DECLARES, not what it can \
                  reach. Pair it with `forbid reach` for the semantic question.") }

(* ------------------------------------------------------------------ *)

let symbol = function
  | "VIOLATION" -> "FAIL"
  | "POSSIBLE" -> "FAIL?"
  | "UNKNOWN" | "UNKNOWN_NO_CONTRACT" -> "UNKNOWN"
  | "PASS" -> "pass"
  | "NOT_COMPUTED" -> "n/a"
  | "NO_SOURCE" | "NO_TARGET" -> "VACUOUS"
  | v -> v

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function
      | a :: v :: _ when a = name -> v
      | _ :: tl -> go tl
      | [] -> default
    in
    go args
  in
  let positional = ref [] in
  let rec strip = function
    | a :: _ :: tl when String.length a > 2 && String.sub a 0 2 = "--" -> strip tl
    | a :: tl ->
        positional := a :: !positional ;
        strip tl
    | [] -> ()
  in
  strip args ;
  let positional = List.rev !positional in
  let db_path, rules_path =
    match positional with
    | [ d ] -> (d, "arch-rules.txt")
    | d :: r :: _ -> (d, r)
    | [] ->
        prerr_endline usage ;
        exit 2
  in
  let fmt = opt "--format" "text" in
  (* A misspelled policy used to be read as "not fail" and silently disabled the gate:
     `--on-possible fial` turned a failing rule green. A policy flag that can be typo'd into
     permissiveness is worse than no flag. *)
  let policy name default =
    let v = opt name default in
    if v <> "fail" && v <> "warn" then
      die (Printf.sprintf "arch-rules: %s takes 'fail' or 'warn', got %S" name v) ;
    v
  in
  let on_unknown = policy "--on-unknown" "warn" in
  let on_possible = policy "--on-possible" "fail" in
  let on_vacuous = policy "--on-vacuous" "fail" in
  (* NOT_COMPUTED defaults to FAIL, unlike UNKNOWN. They are not the same thing: UNKNOWN is an
     analysis result (the cone escapes, so nothing is proved), while NOT_COMPUTED means the rule
     was never evaluated — the index carries no effects or module_deps data at all. A rule that
     silently reads "n/a" forever is indistinguishable from a rule that passes, and it is the
     one case the author can always fix (populate the data, or delete the rule). *)
  let on_not_computed = policy "--on-not-computed" "fail" in
  let t =
    try Arch_db.open_ro db_path
    with Arch_db.Refused m | Arch_db.Broken m -> die ("arch-rules: " ^ m)
  in
  let rules = parse_rules rules_path in
  let g = Arch_graph.load t in
  let contract_ok = Arch_db.contract_ok t "rules" in
  let results = List.map (eval t g ~sound:contract_ok) rules in
  (* UNKNOWN is fail-OPEN by default: a rule that blocks every PR whose cone happens to touch a
     callback teaches people to delete the rule, which leaves them worse off than a warning. *)
  let failing v =
    v = "VIOLATION"
    || (on_possible = "fail" && v = "POSSIBLE")
    || (on_unknown = "fail" && (v = "UNKNOWN" || v = "UNKNOWN_NO_CONTRACT"))
    || (on_vacuous = "fail" && (v = "NO_SOURCE" || v = "NO_TARGET"))
    || (on_not_computed = "fail" && v = "NOT_COMPUTED")
  in
  let failed_names = List.filter_map (fun r -> if failing r.verdict then Some r.rule else None) results in
  let count_verdicts vs = List.length (List.filter (fun r -> List.mem r.verdict vs) results) in
  (* The VERDICT census. These seven counts PARTITION the rules — every rule has exactly one
     verdict, and `census` below is asserted to sum to the rule count — which is what makes the
     summary line readable as a whole. `failing` is a different kind of number entirely: it is a
     policy-driven aggregate that OVERLAPS six of the seven, so the two are reported on separate
     lines and never added together. See the summary block near the end of this file.

     UNKNOWN and UNKNOWN_NO_CONTRACT are counted apart, not merged. They have different causes and
     different fixes: the first means the source cone escaped through a ⊤ edge (a real analysis
     result — the fix is a better producer, or roadmap 3.7); the second means the index was never
     ⊤-marked at all, so NOTHING was ruled out for any rule (the fix is to rebuild with a
     contract-stamping backend). A single line reading "N UNKNOWN (the cone escapes through a ⊤
     edge)" is simply false for the second. *)
  let proved = count_verdicts [ "PASS" ] in
  let violations = count_verdicts [ "VIOLATION" ] in
  let possible = count_verdicts [ "POSSIBLE" ] in
  let unknown_escaping = count_verdicts [ "UNKNOWN" ] in
  let unknown_no_contract = count_verdicts [ "UNKNOWN_NO_CONTRACT" ] in
  (* Retained as the UNION for the JSON field of the same name, whose meaning predates this split
     and which consumers already read. Never used in the text census, where it would double-count
     against `unknown_no_contract`. *)
  let unknown = unknown_escaping + unknown_no_contract in
  (* NO_SOURCE and NO_TARGET stay merged, unlike the two UNKNOWNs: they are the SAME failure with
     the same fix — a selector that matches nothing — and the per-rule note already names which of
     the two selectors it was. *)
  let vacuous = count_verdicts [ "NO_SOURCE"; "NO_TARGET" ] in
  let not_computed = count_verdicts [ "NOT_COMPUTED" ] in
  (* arch-rules never refuses at the process level (unlike arch-impact's exit 3) — an
     un-⊤-marked or data-less index degrades individual rules to UNKNOWN_NO_CONTRACT /
     NOT_COMPUTED verdicts instead, which the fail-open/fail-closed policy flags above already
     govern. So `verdict` here only ever takes "pass" or "fail", mirroring the exit code
     computed below (line ~464), never "refused". *)
  let verdict = if failed_names <> [] then "fail" else "pass" in
  (* The VERDICT census, as name/count pairs for the text and `md` summary lines. Defined — and
     checked — ABOVE the format split on purpose: the partition claim is a property of the
     verdicts, not of the renderer, and the JSON object below prints the same seven numbers. Left
     inside the text branch it left `--format json` unguarded, where an unknown verdict would be
     under-counted silently AND `failing` would treat it as not-failing: fail-open in the one
     channel a gate actually reads. *)
  let census =
    [ ("proved", proved); ("violation", violations); ("possible", possible);
      ("unknown", unknown_escaping); ("unknown-no-contract", unknown_no_contract);
      ("vacuous", vacuous); ("not-computed", not_computed) ]
  in
  (* The partition claim, checked rather than asserted in prose: if a verdict string ever escapes
     `census`, this refuses to print a summary that silently loses it. *)
  let counted = List.fold_left (fun a (_, n) -> a + n) 0 census in
  if counted <> List.length results then
    die
      (Printf.sprintf
         "arch-rules: internal error — the summary census covers %d of %d rules. A verdict the \
          summary does not know about would be silently dropped from the line; refusing to print \
          it."
         counted (List.length results)) ;
  (if fmt = "json" then
     print_endline
       (Yojson.Safe.pretty_to_string
          (`Assoc
            [ ("computed", `Bool true);
              ("contract_ok", `Bool contract_ok);
              ("verdict", `String verdict);
              (* `failing` is the GATE: policy-driven, and it overlaps every census field below
                 except `proved`. The seven census fields — proved, violations, possible,
                 unknown_escaping, unknown_no_contract, vacuous, not_computed — partition the
                 rules and sum to the length of `results`. Do not add `failing` to them.

                 `unknown` is kept as the UNION unknown_escaping + unknown_no_contract, because
                 that is what it has always meant and gates read it. It is the one field here that
                 is redundant with two others; the split ones are the honest pair. *)
              ("failing", `Int (List.length failed_names));
              ("proved", `Int proved);
              ("violations", `Int violations);
              ("possible", `Int possible);
              ("unknown", `Int unknown);
              ("unknown_escaping", `Int unknown_escaping);
              ("unknown_no_contract", `Int unknown_no_contract);
              ("vacuous", `Int vacuous);
              ("not_computed", `Int not_computed);
              ( "results",
                `List
                  (List.map
                     (fun r ->
                       `Assoc
                         ([ ("rule", `String r.rule); ("kind", `String r.kind);
                           ("verdict", `String r.verdict);
                           ("detail", `List (List.map (fun d -> `String d) r.detail));
                           ("detail_total", `Int r.detail_total);
                           ("witness", `List (List.map (fun w -> `String w) r.witness));
                           ("note", (match r.note with Some n -> `String n | None -> `Null)) ]
                         @ (match (r.sizes, r.kind) with
                           (* `exported` and `dep` size their SOURCE population only; neither has
                              a target population a number could describe. *)
                           | Some (sn, _), ("exported" | "dep") -> [ ("source_size", `Int sn) ]
                           | Some (sn, tn), _ ->
                               [ ("source_size", `Int sn); ("target_size", `Int tn) ]
                           | None, _ -> [])
                         @ (if r.exact then [ ("exact", `Bool true) ] else [])))
                     results) );
              ("failed", `List (List.map (fun n -> `String n) failed_names)) ]))
   else
     let md = fmt = "md" in
     print_endline (if md then "# Architecture rules" else "== Architecture rules") ;
     List.iter
       (fun r ->
         let tag = symbol r.verdict in
         print_endline
           (if md then Printf.sprintf "- **%s** — %s" tag r.rule
            else Printf.sprintf "[%s] %s" (Printf.sprintf "%*s%*s" ((7 + String.length tag) / 2) tag
                                             (7 - ((7 + String.length tag) / 2)) "") r.rule) ;
         List.iter (fun d -> print_endline (if md then "    - " ^ d else "           " ^ d)) r.detail ;
         (if r.witness <> [] then
            print_endline
              (if md then "    - witness: " ^ String.concat " → " r.witness
               else "           witness: " ^ String.concat " -> " r.witness)) ;
         match r.note with
         | Some n -> print_endline (if md then "    > " ^ n else "           note: " ^ n)
         | None -> ())
       results ;
     (* TWO lines, because there are two different questions and one number cannot answer both.

        Line 1 is the VERDICT: what the analysis found. Its seven counts partition the rules — every
        rule has exactly one verdict — so the line can be read as a whole and the parts add up to
        the total. It is unconditional: a state that only appears when non-zero is a state a reader
        cannot distinguish from a state the tool does not have, and "0 proved" is the single most
        important thing this summary can say.

        Line 2 is the GATE: what the POLICY did with those verdicts. `failing` is not a verdict —
        it is an aggregate over VIOLATION, POSSIBLE, NO_SOURCE, NO_TARGET, NOT_COMPUTED and
        conditionally the two UNKNOWNs, so it OVERLAPS six of the seven census counts. Printing it
        inside line 1 made "4 rule(s), 1 proved, 3 failing, 1 UNKNOWN" sum to 5 over 4 rules. It
        also has to state the policy actually in force: the previous text said "fail-open by
        default" to an operator who had just passed --on-unknown fail, which is a newly-written
        sentence that is false for the run it annotates — the exact defect class this summary
        exists to fix.

        specs/qualified-unit-resolution.md §10.5: "a verdict with N states must be reported with N
        numbers ... Report 1 proved / 3 UNKNOWN / 0 violations". That asks for `violations`, the
        verdict — not `failing`, the gate. Both are here, on the line each belongs to. *)
     let nf = List.length failed_names in
     (* In `md` the two lines are bullets: consecutive plain lines would be reflowed into one
        paragraph, which would put the census and the gate back on a single line — the exact
        conflation this split exists to undo. *)
     let bullet = if md then "- " else "" and sub = if md then "  - " else "  " in
     print_endline "" ;
     print_endline
       (Printf.sprintf "%s%d rule(s): %s" bullet (List.length results)
          (String.concat ", " (List.map (fun (n, c) -> Printf.sprintf "%d %s" c n) census))) ;
     (* Every state the flags govern, with the value actually in force — no defaults quoted, and
        no claim about fail-open that the current invocation contradicts. VIOLATION is listed as
        `always` because no flag can open it. *)
     print_endline
       (Printf.sprintf
          "%sgate: %d failing — violation=always possible=%s unknown=%s vacuous=%s \
           not-computed=%s"
          bullet nf on_possible on_unknown on_vacuous on_not_computed) ;
     (* The causes, once each, only for states actually present. They are per-STATE and must not be
        shared: for UNKNOWN_NO_CONTRACT no cone escaped anywhere — the index was never ⊤-marked, so
        no rule on it could have been proved regardless. *)
     List.iter
       (fun (n, msg) -> if n > 0 then print_endline (sub ^ msg))
       [ ( unknown_escaping,
           "unknown: the source cone reaches a ⊤ edge — no path was found and none can be ruled \
            out either. Not proved." );
         ( unknown_no_contract,
           "unknown-no-contract: this index is not ⊤-marked, so 'no path' is not a proof for ANY \
            rule on it — a dropped dynamic edge is indistinguishable from an absent one. Rebuild \
            with a contract-stamping backend." );
         (vacuous, "vacuous: a selector matched nothing — the rule cannot fail, so it proves nothing.");
         ( not_computed,
           "not-computed: the index carries no data for that rule form — it was never checked." ) ]) ;
  exit (if List.exists (fun r -> failing r.verdict) results then 1 else 0)
