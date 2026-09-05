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

Usage: arch-rules <db> [rules-file] [--format text|md|json|sarif]
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
    forbid dep from module:lib/core/** to module:Web.**
  rule "protocol entry points gain no new fatal origin"
    forbid origin from file:src/proto_alpha/**/main.ml form:assert,division allow-file:crash-allow.txt|}

let die msg =
  prerr_endline msg ;
  exit 2

let has_prefix p s = String.length s >= String.length p && String.sub s 0 (String.length p) = p

let strip_prefix p s = String.sub s (String.length p) (String.length s - String.length p)

(* An allow-list entry. [ident] is the four declared fields joined by "|":
   [fn | file:line | form | exn]. [count] is the number of origins that identity
   is permitted to carry.

   The count is not decoration. MEASURED (re-derived 2026-09-05) on a table that
   carries no UNIQUE constraint over these columns, so the probe could have come
   back empty and did not. All three rows come from indexes built by origin/main
   0982a42 -- proto_alpha and the whole tree from tezos/_build/default with
   --errors-profile=tezos, octez-manager from its own _build/default. The build
   state belongs beside the corpus name for the same reason it does for
   resolution rates: how many origins EXIST depends on which units were compiled,
   so a collision count is a joint property of the code and the build's coverage,
   never of the code alone.

                            all rows            rows with a real position
     proto_alpha     30526 / 26901 colliding    3344 / 281 (8.4%), worst 9
     octez-manager   18758 / 15569 (83%)        3100 / 218 (7.0%), worst 7
     whole src      265217 / 169525 (64%)      86198 / 4196 (4.9%), worst 9

   READ THE SECOND COLUMN. Every line = 0 origin is a PHANTOM: the walker records
   a None origin for each OMITTED OPTIONAL ARGUMENT -- the None Typecore
   synthesises during type-checking, not one anyone wrote. Attributed at 100%,
   zero residue, on two corpora (roadmap 3.14). Within a function they all
   collapse to one identity, so 2158 functions yield exactly 2158 identities
   (verified). The 139-row worst group is one value's phantoms:
   receipt_repr.ml's balance_and_update_encoding is a VALUE, not a function, so
   it cannot return None at all.

   The decision stands on the narrower number: on rows describing real code the
   identity still collides 5-8% of the time with a worst group of NINE, which is
   still a set exemption waiting to grow. But the 88% argued it from a producer
   artefact and would have gone false the day 3.14 lands.

   Adding the COLUMN does not rescue it (26901 -> 26786 on proto_alpha): 139
   origins can share a function, file, line, form and exception. So no positional
   identity is unique, and without a count an exemption is a SET exemption whose
   membership can grow after review — a 140th origin on an exempted line covered
   silently by the decision taken about the first 139.

   Filtered to what this gate polices the picture inverts: the 37 crash-surface
   sites from proto_alpha's main.ml are ALL x1. A format that is a key on the
   population you demo and not on the table it reads is exactly the shape that
   survives review. *)
type origin_allow = { al_path : string; al_entries : (string * int) list }

(* The identity, built in ONE place so the allow-list reader and the site
   collector cannot drift into two spellings of it. *)
let origin_ident ~fn ~file ~line ~form ~exn =
  Printf.sprintf "%s | %s:%d | %s | %s" fn file line form
    (if exn = "" then "-" else exn)

(* Reading happens at PARSE time, not at evaluation time: a malformed allow-list
   must abort the run exactly as a malformed rules file does. A gate that starts
   evaluating and then discovers it cannot read its own exemptions has already
   printed half a verdict. *)
let read_origin_allow path lineno =
  let ic =
    try open_in path
    with Sys_error e ->
      die
        (Printf.sprintf
           "arch-rules: line %d: cannot read allow-file %S: %s. The path is resolved relative to \
            the working directory, not to the rules file."
           lineno path e)
  in
  let entries = ref [] and n = ref 0 in
  (try
     while true do
       let raw = input_line ic in
       incr n ;
       let line = String.trim raw in
       (* FULL-LINE comments only, deliberately. Trailing-comment stripping is
          what truncates a rules-file path at its first '#', and that failure is
          BY DELETION — the line still parses, just shorter. An allow-list is
          read by humans in review, so it gets comments; it does not get the
          failure mode. *)
       if line <> "" && line.[0] <> '#' then
         (* Split from the RIGHT, keeping the last four fields and letting the
            FUNCTION NAME absorb everything before them.

            A left split on '|' requiring exactly five fields makes any site
            whose function name contains '|' permanently un-exemptable — and
            OCaml operator names legitimately contain one: [|+|] already exists
            in this repository's own scenario_dsl.ml, and [|/|], [|>] and their
            relatives are ordinary. Worse than un-exemptable: a malformed
            allow-file ABORTS, so one such line copied verbatim from the tool's
            own output took down EVERY OTHER RULE in the file with it.

            The last four fields cannot contain '|' by construction — a
            file:line, a form drawn from a closed vocabulary, an exception path,
            and a count. So the remainder is the name, whatever it contains. *)
         match
           let parts = String.split_on_char '|' line in
           let n = List.length parts in
           if n < 5 then List.map String.trim parts
           else
             let rec split i acc = function
               | rest when i = n - 4 -> String.concat "|" (List.rev acc) :: rest
               | x :: tl -> split (i + 1) (x :: acc) tl
               | [] -> List.rev acc
             in
             split 0 [] parts |> List.map String.trim
         with
         | [ fn; loc; form; exn; count ] ->
             let c =
               let d =
                 (* Both spellings accepted: the multiplication sign is correct
                    and awkward to type, and a gate whose file is painful to
                    edit is a gate people route around. *)
                 if has_prefix "\xc3\x97" count then strip_prefix "\xc3\x97" count
                 else if has_prefix "x" count then strip_prefix "x" count
                 else count
               in
               match int_of_string_opt (String.trim d) with
               | Some c when c > 0 -> c
               | _ ->
                   die
                     (Printf.sprintf
                        "arch-rules: %s line %d: last field must be a positive count (\xc3\x97N or xN), \
                         got %S"
                        path !n count)
             in
             let ident =
               Printf.sprintf "%s | %s | %s | %s" fn loc form (if exn = "" then "-" else exn)
             in
             (* A duplicate identity was previously accepted in silence and the
                FIRST occurrence won, so the ORDER OF LINES decided the verdict:
                the same file with two lines swapped exited 1 or 0, with no
                diagnostic either way and `stale` reporting 0 in both. In an
                append-only workflow — the one this design imposes, since there
                is no --regenerate — a corrected allowance appended at the end of
                the file was silently ignored in favour of the stale one above
                it. Refused, naming both counts, because the author's intent is
                genuinely ambiguous and guessing it is what produced the bug. *)
             (match List.assoc_opt ident !entries with
             | Some prev ->
                 die
                   (Printf.sprintf
                      "arch-rules: %s line %d: duplicate allow-list entry for %s (already \
                       allowed \xc3\x97%d, this line says \xc3\x97%d). Merge them into one line \
                       with the intended count — line order must not decide which wins."
                      path !n ident prev c)
             | None -> ()) ;
             entries := (ident, c) :: !entries
         | _ ->
             die
               (Printf.sprintf
                  "arch-rules: %s line %d: expected five |-separated fields \
                   (fn | file:line | form | exn | \xc3\x97N), got %d in %S"
                  path !n
                  (List.length (String.split_on_char '|' line))
                  line)
     done
   with End_of_file -> ()) ;
  close_in ic ;
  { al_path = path; al_entries = List.rev !entries }

type body =
  | Reach of Arch_sel.t * Arch_sel.t
  | Dep of Arch_sel.t * Arch_sel.t
  | Exported of Arch_sel.t
  | Effect of Arch_sel.t * string
  (* 3.12: the crash-surface regression gate. [Arch_sel.t] is the ROOT, the string
     list is the set of origin forms to police, and the last string is the path of
     the ALLOW-LIST file — not a baseline. See briefs/rules-origin-verb-design.md
     for why an allow-list rather than a regenerable baseline: a site list can grow
     for three different reasons (a real regression, widened coverage, a proof that
     strengthened MAY→MUST) and only a human can tell them apart, so the gate must
     force the human rather than automate an excuse. *)
  | Origin of Arch_sel.t * string list * string * origin_allow

type rule = { name : string; body : body }

(* The rule FORM, reported alongside the verdict so a consumer can tell a semantic `reach`
   result from a syntactic `dep` one without re-parsing the rules file. *)
let kind_of = function
  | Reach _ -> "reach"
  | Dep _ -> "dep"
  | Exported _ -> "exported"
  | Effect _ -> "effect"
  | Origin _ -> "origin"

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

(* `forbid origin` names its kinds explicitly, because the alternative is what the #73 review
   found in `Dep`: a verb that does not declare them inherits a silent reinterpretation by
   omission. An origin belongs to a FUNCTION in a FILE — `module:` is not a root a cone starts
   from here, and `ext:` names a leaf with no body, hence no origin to hold. *)
let origin_sel_allow = Arch_sel.[ File; Fn ]

(* The `form` vocabulary is exn_origins.form's CHECK constraint, verbatim. Kept as data rather
   than accepted as free text: a typo like `form:asserts` would otherwise select nothing and the
   rule would report a PASS it never earned — the same vacuous green this tool exists to refuse. *)
let origin_forms =
  [ "raise"; "reraise"; "unknown"; "failwith"; "invalid_arg"; "assert"; "partial_match";
    "compare"; "division"; "index"; "inferred_bind" ]

(* And [channel:] is closed for exactly the same reason, which had to be pointed
   out to me: I refused an unknown [form:] on the ground that it "would select
   nothing, and the rule would report a PASS while policing an empty population"
   -- and then added [channel:] three lines away with no such check.

   Measured before fixing: `channel:banana` and `channel:result` produced
   BYTE-IDENTICAL verdicts, both `[UNKNOWN] 0 origin(s)`, both exit 0. A
   misspelled channel was indistinguishable from a genuinely clean one, and on a
   cone with no ⊤ escape it is an outright PASS.

   Unlike [form:], the vocabulary is not a schema CHECK: `exn_origins.channel` is
   free text whose members come from the errors profile the INDEX was built with.
   So the check cannot be a hardcoded list -- it is the set of channels this
   database actually contains, which is also the only set that can answer. A
   channel absent from the index is refused with the ones that are present. *)


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
               (* THE '#' TRAP, refused for EVERY verb rather than for one.

                  Comment stripping above is [String.index_opt raw '#'] — the
                  FIRST '#', wherever it sits — so any token containing one is
                  silently shortened and the line still parses, just against
                  something else. It fails BY DELETION.

                  An earlier revision guarded only `forbid origin`, on the
                  grounds that a file path was the motivating case. That is the
                  partial fix that is worse than none: the class gets named, one
                  member gets closed, and the remaining four become LESS likely
                  to be looked at. Verified on a sibling: `forbid reach ... to
                  fn:plain#variant2` truncates to `fn:plain` and reports a
                  VIOLATION against a population the author never wrote — a
                  false finding, not merely a missed one.

                  A '#' preceded by whitespace is an ordinary trailing comment
                  and stays legal; only a GLUED one indicates a truncated
                  token. *)
               (match String.index_opt raw '#' with
               | Some i when i > 0 && raw.[i - 1] <> ' ' && raw.[i - 1] <> '\t' ->
                   die
                     (Printf.sprintf
                        "arch-rules: line %d: this line contains a '#' with no space before \
                         it, and comment stripping removes everything from the FIRST '#' \
                         onwards — so the rule would be parsed with a TRUNCATED token. A '#' \
                         cannot appear inside a selector pattern or a path. Rename the target, \
                         or put a space before the '#' if it was meant as a comment."
                        !lineno)
               | _ -> ()) ;
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
                 | ("forbid" :: "origin" :: "from" :: a :: rest) as _all
                   when (match rest with
                        | [ f; al ] -> has_prefix "form:" f && has_prefix "allow-file:" al
                        | [ f; ch; al ] ->
                            has_prefix "form:" f && has_prefix "channel:" ch
                            && has_prefix "allow-file:" al
                        | _ -> false) ->
                     let f, channel, al =
                       match rest with
                       | [ f; al ] -> (f, "exception", al)
                       | [ f; ch; al ] -> (f, strip_prefix "channel:" ch, al)
                       | _ -> assert false
                     in
                     let forms =
                       String.split_on_char ',' (strip_prefix "form:" f)
                       |> List.filter (fun x -> x <> "")
                     in
                     (* An unknown form selects nothing, so it would make the rule PASS while
                        policing an empty population. Refused at PARSE time, where the author is
                        looking, rather than surfacing later as a green. *)
                     List.iter
                       (fun x ->
                         if not (List.mem x origin_forms) then
                           die
                             (Printf.sprintf
                                "arch-rules: line %d: unknown origin form %S. Known forms: %s"
                                !lineno x (String.concat ", " origin_forms)))
                       forms ;
                     if forms = [] then
                       die
                         (Printf.sprintf
                            "arch-rules: line %d: form: lists no form — the rule would police \
                             nothing and report a PASS it never earned"
                            !lineno) ;
                     Origin
                       ( sel ~allow:origin_sel_allow a !lineno,
                         forms,
                         channel,
                         read_origin_allow (strip_prefix "allow-file:" al) !lineno )
                 | _ ->
                     die
                       (Printf.sprintf
                          "arch-rules: line %d: unrecognised rule body %S. Supported:\n\
                          \    forbid reach from <sel> to <sel>\n\
                          \    forbid dep from <sel> to <sel>\n\
                          \    forbid exported outside <sel>\n\
                          \    forbid effect from <sel> kind:<VALUE_KIND>\n\
                          \    forbid origin from <sel> form:<f1,f2,...> allow-file:<path>\n\
                           \n\
                           If the body above looks right, check for a SPACE in a path: the \
                           parser splits the line on spaces, so a path containing one arrives \
                           as an extra token and lands here. Paths with spaces are not \
                           supported."
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
  (* Roadmap 1.4's ⊤-anchor taxonomy, for an UNKNOWN reach verdict: the distinct [top_reason]
     values recorded on the MAY_TOP edge(s) the escaping cone actually hit. [[]] for every other
     verdict, and for UNKNOWN_NO_CONTRACT (no specific edge is at fault there — the whole index
     was never ⊤-marked). Feeds `--format sarif`'s [properties.top_reason] (spec FR-022). *)
  top_reasons : string list;
}

(** Order matters: a definite path is VIOLATION even when the source ALSO reaches a ⊤ edge.
    UNKNOWN is what you say when you found nothing and cannot rule it out — never a way to
    downgrade something you did find. *)
(* `sound` here is Arch_db.contract_ok's verdict, not the raw flag: a flag set on an index whose
   `kind` column is missing or partly NULL is worse than no flag, because SQL's 3-valued logic
   makes such an edge invisible to both the closure and the ⊤ check. The caller passes the result
   of the full check. *)
(* The channels this index actually contains. Not a hardcoded list: unlike
   [exn_origins.form], the channel column has no schema CHECK -- its members come
   from the errors profile the index was BUILT with, so the database is the only
   thing that can answer, and it is also the only answer that matters to a rule
   evaluated against it. *)
(* [exn_origins.channel] arrived in schema 1.8. An index written by an earlier
   producer has the table and NOT the column, and reading it there is a SQL error
   rather than an empty result -- the rule would die instead of reporting what it
   could not compute. Gated on the COLUMN, not on the schema version, exactly as
   arch-query gates [edge_form]: a version is what a database CLAIMS, a column is
   what it has.

   On such an index every origin is an exception origin by construction: the
   column was introduced by a re-tag slice whose producer emitted only
   [channel = 'exception']. So the honest answer for [exception] is "all rows",
   and for any other channel it is a refusal -- that channel cannot exist here. *)
let has_channel_column t = Arch_db.has_col t "exn_origins" "channel"

let channels_in_index t =
  if not (has_channel_column t) then [ "exception" ]
  else
    Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1 ~to_cells:Arch_db.Rows.c1
      "SELECT DISTINCT channel FROM exn_origins ORDER BY 1" ()
    |> List.filter_map (function [ c ] -> Some (Arch_db.string_of_cell c) | _ -> None)

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

(* Roadmap 1.4's ⊤-anchor taxonomy, looked up for a specific set of ESCAPING node keys — the
   [hit] list [reach_verdict] already returns for UNKNOWN. Distinct [top_reason] values only,
   over the [MAY_TOP] edges those nodes themselves hold, so this is honest about scope: it names
   the reason(s) for the ⊤ edge the cone actually stopped at, not every ⊤ reason anywhere in the
   index.

   The two schemas key nodes differently (see Arch_graph's module doc): [Main] keys as
   ['#'..id], resolved straight back to [calls.caller_id]; [Flat] keys as the function's own
   name, resolved through [calls.caller_name]. Either lookup that finds nothing (a malformed or
   foreign DB, or a key this function cannot parse) degrades to [[]] rather than raising — this
   is best-effort provenance for a SARIF property bag, never a correctness-critical path.

   [calls.top_reason] itself is roadmap 1.4 (landed after this feature's own MAY_TOP support),
   so every index built before it — and the FLAT schema's own LSP-backend writer, which never
   emits [MAY_TOP] today but is one change away — has [kind] and [MAY_TOP] edges with no
   [top_reason] column at all. Querying a column that does not exist is a `no such column` SQL
   error, not "finds nothing": gated explicitly via {!Arch_db.has_col}, checked once, ahead of
   the schema match below, so both branches share the guard. *)
let top_reasons_for (t : Arch_db.t) (g : Arch_graph.t) keys =
  if keys = [] || not (Arch_db.has_col t "calls" "top_reason") then []
  else
    let distinct_reasons sql json =
      Arch_db.rows t ~params_ty:Arch_db.Ty.string ~shape:Arch_db.Rows.t1 ~to_cells:Arch_db.Rows.c1 sql json
      |> List.filter_map (function
           | [ c ] -> ( match Arch_db.string_of_cell c with "" -> None | s -> Some s)
           | _ -> None)
    in
    match t.Arch_db.schema with
    | Arch_db.Flat ->
        let names =
          List.filter_map
            (fun k -> Option.map (fun (n : Arch_graph.node) -> n.name) (Arch_graph.SM.find_opt k g.nodes))
            keys
        in
        if names = [] then []
        else
          distinct_reasons
            "SELECT DISTINCT top_reason FROM calls WHERE caller_name IN (SELECT value FROM \
             json_each(?)) AND kind = 'MAY_TOP' AND top_reason IS NOT NULL"
            (Yojson.Safe.to_string (`List (List.map (fun n -> `String n) names)))
    | Arch_db.Main ->
        let ids =
          List.filter_map
            (fun k ->
              if String.length k > 1 && k.[0] = '#' then int_of_string_opt (String.sub k 1 (String.length k - 1))
              else None)
            keys
        in
        if ids = [] then []
        else
          distinct_reasons
            "SELECT DISTINCT top_reason FROM calls WHERE caller_id IN (SELECT value FROM \
             json_each(?)) AND kind = 'MAY_TOP' AND top_reason IS NOT NULL"
            (Yojson.Safe.to_string (`List (List.map (fun i -> `Int i) ids)))

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
        detail_total = 0; sizes = None; witness = []; top_reasons = [];
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
      let top_reasons = if v = "UNKNOWN" then top_reasons_for t g hit else [] in
      { rule = r.name; kind = kind_of r.body; exact = false; verdict = v; detail = List.map lbl (take 20 hit);
        detail_total = List.length hit; note; sizes = Some (SS.cardinal src, SS.cardinal dst); witness;
        top_reasons }
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
      { rule = r.name; kind = kind_of r.body; exact = true; witness = []; top_reasons = [];
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
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
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
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
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
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "VIOLATION"; sizes = None; witness = []; top_reasons = [];
            detail =
              take 20
                (List.map (fun row -> String.concat " " (List.map Arch_db.string_of_cell row)) hits);
            detail_total = List.length hits; note = None }
        else if not (SS.is_empty escaping) then
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "UNKNOWN"; detail = [];
            detail_total = 0; sizes = None; witness = []; top_reasons = [];
            note =
              Some
                (Printf.sprintf
                   "no %s effect found, but the cone escapes through %d ⊤ edge(s) — the effect \
                    could be behind one"
                   kind (SS.cardinal escaping)) }
        else
          { rule = r.name; kind = kind_of r.body; exact = false;
            verdict = (if sound then "PASS" else "UNKNOWN_NO_CONTRACT");
            detail = []; detail_total = 0; note = None; sizes = None; witness = []; top_reasons = [] }
  | Origin (s, forms, channel, allow) ->
      (* Selected once and reused, for the reason [Effect] gives: the vacuity guard and the cone
         must read the SAME set, or the guard passes on one selection and the cone is built from
         another. *)
      let origin_src = lazy (Arch_sel.select g s) in
      if (not (Arch_db.has_table t "exn_origins")) || t.schema = Arch_db.Flat then
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
          note =
            Some
              "this index carries no exn_origins — 'no fatal origin found' would be a lie, not a \
               result. Origins are produced by the OCaml .cmt backend; the flat schema has no \
               such table." }
      else if not (Arch_db.nonempty t "exn_origins") then
        (* Distinct from the branch above ON PURPOSE. A table that exists and is EMPTY is what a
           producer killed before the exception pass looks like, and it would otherwise report
           the same PASS as a codebase with genuinely no origins. See the completion-marker
           class: the two must not print the same thing. *)
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
          note =
            Some
              "exn_origins exists but holds no rows — the exception pass produced nothing, so \
               this rule was never evaluated against anything." }
      else if not (List.mem channel (channels_in_index t)) then
        (* Refused, not reported as clean. An unknown channel selects nothing, so
           every downstream verdict would be a PASS earned by policing an empty
           population -- the vacuity this whole verb exists to refuse, and the
           one its own [form:] check already refuses. *)
        die
          (Printf.sprintf
             "arch-rules: rule %S names channel %S, which this index does not contain. \
              Channels present: %s. A channel that selects nothing would make this rule \
              report a PASS it never earned."
             r.name channel
             (String.concat ", " (channels_in_index t)))
      else if SS.is_empty (Lazy.force origin_src) then
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NO_SOURCE"; detail = [];
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
          note =
            Some
              (Printf.sprintf
                 "selector %s matched nothing — the rule is VACUOUS. An empty cone contains no \
                  origins by construction, which is not a result about your code."
                 (Arch_sel.to_string s)) }
      else
        let src = Lazy.force origin_src in
        let cone = SS.union src (Arch_graph.closure src g.fwd) in
        (* Keyed on the function ID, never on its NAME. Two modules legitimately define
           [handle_error]; matching by name would police origins in files the root never
           reaches and report them as this root's regressions. [Arch_graph]'s key is
           ['#' || f.id], so the id is recovered by dropping the marker. *)
        let ids =
          SS.fold
            (fun k acc ->
              if String.length k > 1 && k.[0] = '#' then
                match int_of_string_opt (String.sub k 1 (String.length k - 1)) with
                | Some i -> `Int i :: acc
                | None -> acc
              else acc)
            cone []
        in
        let ids_json = Yojson.Safe.to_string (`List ids) in
        let forms_json = Yojson.Safe.to_string (`List (List.map (fun f -> `String f) forms)) in
        let hits =
          (* The channel predicate is omitted entirely on a pre-1.8 index rather
             than being written against a column that is not there. The
             refusal above has already established that only `exception` is
             askable on such an index, and on it every row IS an exception row,
             so dropping the predicate is not a widening. *)
          let chan_and = if has_channel_column t then "AND o.channel = ? " else "" in
          let sql =
            Printf.sprintf
              "SELECT f.name, COALESCE(m.path,'?'), o.form, COALESCE(o.exn_path,''), \
               CAST(o.line AS TEXT) \
               FROM exn_origins o JOIN functions f ON o.function_id = f.id \
               LEFT JOIN modules m ON f.module_id = m.id \
               WHERE o.escapes = 1 %s\
               AND o.form IN (SELECT value FROM json_each(?)) \
               AND o.function_id IN (SELECT value FROM json_each(?))"
              chan_and
          in
          if has_channel_column t then
            Arch_db.rows t
              ~params_ty:Arch_db.Ty.(t2 string (t2 string string))
              ~shape:Arch_db.Rows.t5' ~to_cells:Arch_db.Rows.c5 sql
              (channel, (forms_json, ids_json))
          else
            Arch_db.rows t
              ~params_ty:Arch_db.Ty.(t2 string string)
              ~shape:Arch_db.Rows.t5' ~to_cells:Arch_db.Rows.c5 sql (forms_json, ids_json)
        in
        (* Group into site identities and COUNT. The count is the whole reason this is not a
           plain set difference — see [origin_allow]: a ninth array access on an
           already-exempted line must fail loud, not inherit the decision taken about the
           first eight. *)
        let tbl = Hashtbl.create 64 in
        List.iter
          (fun row ->
            match List.map Arch_db.string_of_cell row with
            | [ fn; file; form; exn; line ] ->
                let id =
                  origin_ident ~fn ~file
                    ~line:(Option.value ~default:0 (int_of_string_opt line))
                    ~form ~exn
                in
                Hashtbl.replace tbl id (1 + Option.value ~default:0 (Hashtbl.find_opt tbl id))
            | _ -> ())
          hits ;
        let sites = Hashtbl.fold (fun k n acc -> (k, n) :: acc) tbl [] |> List.sort compare in
        let offenders =
          List.filter_map
            (fun (id, n) ->
              (* The marker goes FIRST, and that is a safety property rather than a layout
                 taste. This line is the artefact a reviewer copies into the allow-file, so a
                 sloppy paste must not produce a VALID entry that says something else. With the
                 marker trailing, a paste corrupts the COUNT — the one field that decides how
                 much a line exempts. With it leading, a paste corrupts the function name, which
                 simply fails to match and stays an offender. Both fail; only one fails safe. *)
              match List.assoc_opt id allow.al_entries with
              | None -> Some (Printf.sprintf "[new]          %s | \xc3\x97%d" id n)
              | Some k ->
                  if n > k then
                    Some (Printf.sprintf "[was \xc3\x97%d]       %s | \xc3\x97%d" k id n)
                  else None)
            sites
        in
        (* A stale entry does not FAIL — it exempts nothing, so it cannot hide a regression. But
           it is reported, because the usual cause is that the coverage it was written for went
           away, and that is worth a look before someone concludes the gate is fine. *)
        let stale =
          List.filter (fun (id, _) -> not (Hashtbl.mem tbl id)) allow.al_entries |> List.length
        in
        let escaping = SS.filter (fun k -> Arch_graph.SM.mem k g.tops) cone in
        (* THE COVERAGE DELTA, reported on every verdict and not only on failure. The design
           note names this as the condition for the gate surviving contact with people: a new
           site can appear because the code regressed, because coverage WIDENED, or because a
           proof strengthened — and a failure message that shows only the new sites reads as
           the first cause, whichever it was. Someone then disables the rule. *)
        let coverage =
          Printf.sprintf "coverage: %d node(s) in cone, %d origin(s) of form %s on channel \
                          '%s', %d site(s); allow-file %s has %d entr%s (%d matching nothing)"
            (SS.cardinal cone) (List.length hits) (String.concat "," forms) channel
            (List.length sites) allow.al_path
            (List.length allow.al_entries)
            (if List.length allow.al_entries = 1 then "y" else "ies")
            stale
        in
        if offenders <> [] then
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "VIOLATION";
            sizes = None; witness = []; top_reasons = [];
            (* 200, not the 20 every other verdict uses, and the difference is not an
               inconsistency to tidy away. Elsewhere `detail` is a SAMPLE of offenders: you read
               a few, you fix the code. Here the list IS the artefact the workflow consumes — a
               reviewer transcribes it into the allow-file — and there is deliberately no
               `--regenerate` flag to produce it another way. Capping at 20 on a root with 32
               sites would make the intended workflow impossible while looking like it worked.
               `detail_total` still reports the truth if 200 is ever exceeded. *)
            detail = take 200 offenders;
            detail_total = List.length offenders;
            note =
              Some
                (coverage
               ^ ". A site listed here is not necessarily a REGRESSION: it is a site the \
                  allow-file does not cover. Compare the coverage figure above with the one \
                  from the run that produced the allow-file before concluding the code got \
                  worse.") }
        else if not (SS.is_empty escaping) then
          { rule = r.name; kind = kind_of r.body; exact = false; verdict = "UNKNOWN"; detail = [];
            detail_total = 0; sizes = None; witness = []; top_reasons = [];
            note =
              Some
                (* LEADS with what the run DID establish. On a real index the
                   cone almost always escapes, so this is the verb's NORMAL
                   verdict rather than a degraded one — and a note that opens on
                   what is unproved reads as a tool failure to someone who has
                   just run a gate that worked. It proves "no NEW site among
                   those it can see"; it never proves "no fatal origin exists",
                   and both halves belong in the sentence. *)
                (Printf.sprintf
                   "%s. GATE HELD: every site in view is covered by the allow-file, so no new \
                    fatal origin appeared among the ones this run could see. It is NOT a proof \
                    that none exists: the cone still escapes through %d \xe2\x8a\xa4 edge(s) and an \
                    origin could sit behind one. This verdict is the expected outcome on a \
                    real index, not a failure of the check \xe2\x80\x94 a VIOLATION fails the gate \
                    regardless of \xe2\x8a\xa4, which is what makes the rule useful while \
                    completeness is out of reach"
                   coverage (SS.cardinal escaping)) }
        else
          { rule = r.name; kind = kind_of r.body; exact = false;
            verdict = (if sound then "PASS" else "UNKNOWN_NO_CONTRACT");
            detail = []; detail_total = 0; sizes = None; witness = []; top_reasons = [];
            (* Says the same thing the UNKNOWN branch says, minus the caveat it
               has earned the right to drop: here the cone is closed, so "no new
               fatal origin among those in view" IS "no new fatal origin". Both
               verdicts state the guarantee rather than leaving a reader to infer
               it from the absence of findings. *)
            note =
              Some
                (coverage
               ^ ". GATE HELD: every site is covered by the allow-file and the cone does not \
                  escape through any \xe2\x8a\xa4 edge, so no fatal origin of these forms is reachable \
                  from this root and unaccounted for") }
  | Dep (s, d) ->
      if (not (Arch_db.has_table t "module_deps")) || t.schema = Arch_db.Flat then
        { rule = r.name; kind = kind_of r.body; exact = false; verdict = "NOT_COMPUTED"; detail = [];
          detail_total = 0; sizes = None; witness = []; top_reasons = [];
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
        { rule = r.name; kind = kind_of r.body; exact = true; witness = []; top_reasons = [];
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

(* ------------------------------------------------------------------ *)
(* --format sarif (roadmap 2.1)                                        *)
(* ------------------------------------------------------------------ *)

(* Roadmap 1.2 (ADR 002): [driver.name]/[driver.version]. The MAIN schema's provenance lives in
   [producer_runs] (one row per producer invocation); the FLAT schema's (arch-load, runner.ml)
   lives in [comment_db_meta] instead — see that table's own comment for why the two writers
   disagree. Tried in that order so a MAIN-schema DB that also happens to carry a stray
   [comment_db_meta] producer key (it should not, but nothing enforces that) still prefers its
   own authoritative table. Falls back to a fixed, honest default rather than an empty string:
   SARIF's [driver.name] is not optional, and "arch-index" is true of every index this repo's own
   pipeline writes even when neither provenance mechanism was populated (a pre-1.2 index). *)
let producer_info (t : Arch_db.t) =
  let of_producer_runs () =
    if t.Arch_db.schema = Arch_db.Main && Arch_db.has_table t "producer_runs" then
      match
        Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t2' ~to_cells:Arch_db.Rows.c2
          "SELECT producer, producer_version FROM producer_runs ORDER BY id DESC LIMIT 1" ()
      with
      | [ [ p; v ] ] -> (
          match Arch_db.string_of_cell p with
          | "" -> None
          | producer -> Some (producer, match Arch_db.string_of_cell v with "" -> None | s -> Some s))
      | _ -> None
    else None
  in
  match of_producer_runs () with
  | Some pv -> pv
  | None -> (
      match Arch_db.meta t "producer" with
      | Some p -> (p, Arch_db.meta t "producer_version")
      | None -> ("arch-index", None))

(* Reads the ADR-002 soundness class the same two places {!producer_info} reads provenance from
   (MAIN's [producer_runs], FLAT's [comment_db_meta]) — but WITHOUT that function's fallthrough:
   [producer_info] tries [producer_runs] first and falls through to [comment_db_meta] when it
   yields no row; this function does not — on MAIN with a [producer_runs] table present, a query
   that finds no row (or an empty [soundness_class] cell) returns [None] directly, never checking
   [comment_db_meta]. Latent today: no in-repo MAIN producer writes [soundness_class] to
   [comment_db_meta], so the gap has never been observed to lose a real value — but if one ever
   does, this reads as "no soundness class" rather than falling back the way [producer_info]
   would. Every [arch-load] DB (FLAT) carries this key unconditionally (see
   [bin/arch_load/arch_load.ml]'s own comment), and the docs advertise
   [properties.soundness_class] for FR-022 filtering; a hardcoded [None] here would silently
   defeat that filter on every real index. [None] otherwise only for a pre-1.2 MAIN index with
   neither source populated. *)
let soundness_class_info (t : Arch_db.t) =
  if t.Arch_db.schema = Arch_db.Main && Arch_db.has_table t "producer_runs" then
    match
      Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t1 ~to_cells:Arch_db.Rows.c1
        "SELECT soundness_class FROM producer_runs ORDER BY id DESC LIMIT 1" ()
    with
    | [ [ s ] ] -> ( match Arch_db.string_of_cell s with "" -> None | s -> Some s)
    | _ -> None
  else Arch_db.meta t "soundness_class"

(* Roadmap 1.3's coverage matrix, read straight off [analysis_coverage] — absent on any DB
   predating that roadmap item, in which case this is [[]] and the run simply carries no
   coverage/notifications, never a fabricated "covered" claim. *)
let coverage_rows (t : Arch_db.t) : Arch_sarif.coverage_row list =
  if not (Arch_db.has_table t "analysis_coverage") then []
  else
    Arch_db.rows t ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t4' ~to_cells:Arch_db.Rows.c4
      "SELECT language, analysis, status, detail FROM analysis_coverage" ()
    |> List.filter_map (fun row ->
           match row with
           | [ lang; analysis; status; detail ] ->
               let opt c = match Arch_db.string_of_cell c with "" -> None | s -> Some s in
               Some
                 { Arch_sarif.language = opt lang; analysis = Arch_db.string_of_cell analysis;
                   status = Arch_db.string_of_cell status; detail = opt detail }
           | _ -> None)

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
  (* A typo'd `--format` used to fall through to the text/md renderer silently — exactly the
     `--on-possible fial`-style footgun the policy flags below are guarded against, but worse: a
     CI pipeline piping this straight into a SARIF or JSON consumer would get a human-readable
     report instead, which the consumer either chokes on or (worse) silently ignores. Refuse
     loudly instead of guessing. *)
  (if fmt <> "text" && fmt <> "md" && fmt <> "json" && fmt <> "sarif" then
     die (Printf.sprintf "arch-rules: --format takes 'text', 'md', 'json' or 'sarif', got %S" fmt)) ;
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
                           ("top_reasons", `List (List.map (fun tr -> `String tr) r.top_reasons));
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
   else if fmt = "sarif" then (
     (* One `run`, category "arch-index/rules": every result this invocation produced is a
        `forbid ...` rule verdict, a single (producer, analysis) pair in roadmap 2.1's sense.
        `arch-report` (2.2), which reuses Arch_sarif, is what emits several runs with distinct
        categories in one log — this binary only ever has the one. *)
     let producer, producer_version = producer_info t in
     let soundness_class = soundness_class_info t in
     let level_of = function
       | "VIOLATION" -> Arch_sarif.Error
       | "POSSIBLE" -> Arch_sarif.Warning
       (* UNKNOWN, UNKNOWN_NO_CONTRACT, NOT_COMPUTED, NO_SOURCE, NO_TARGET: none of these is a
          proof of anything, but none is silence either — FR-024's discipline applied to a
          single rule's own verdict, not just to a whole language's coverage. `note` carries
          which of the five it is. *)
       | _ -> Arch_sarif.Note
     in
     let message_of r =
       let base = Printf.sprintf "%s [%s]: %s" r.rule r.kind r.verdict in
       let with_note = match r.note with Some n -> base ^ " — " ^ n | None -> base in
       (* `dep` and `effect` verdicts carry their evidence as prose rows in `detail`, and
          `finding_of` (below) deliberately keeps that prose OUT of `locations` — it is not a
          display label, and stuffing it in there fabricates a bogus SARIF location (H1, round-3
          review). `message.text` is therefore the ONLY channel left for that evidence, so it must
          appear even when a NOTE is also present — `dep`'s non-vacuous branch always attaches a
          fixed advisory note ("declared-dependency check: ..."), and without this the note would
          silently replace the evidence instead of accompanying it. `reach`/`exported` need no
          such override: their `detail` is already the SARIF `locations` list, and their notes
          are the rarer case (an overlap or a vacuity explanation) where the note text alone is
          already the whole story. *)
       match r.kind with
       | ("dep" | "effect") when r.detail <> [] -> with_note ^ " — " ^ String.concat ", " r.detail
       | _ -> ( match r.note with Some _ -> with_note | None -> if r.detail = [] then with_note else with_note ^ " — " ^ String.concat ", " r.detail)
     in
     let finding_of r : Arch_sarif.finding =
       { rule_id = r.rule; level = level_of r.verdict; message = message_of r;
         verdict = Some r.verdict;
         (* The ADR-002 class of the INDEX this verdict was computed against (heuristic /
            sound_with_top / asserted), not a per-finding ingestion fact — `arch-rules` never
            ingests a heuristic fact itself (that is roadmap 2.3's job, where a future SARIF-in
            adapter constructs findings with a class of its own choosing). Every finding from
            THIS binary shares the one index's class, read once above. *)
         soundness_class;
         (* UNKNOWN and UNKNOWN_NO_CONTRACT are NOT the same soundness gap and must not collapse
            onto one value (arch_rules.ml's own `census` above draws exactly this line): UNKNOWN
            means this cone's own witness escaped through a real ⊤ edge; UNKNOWN_NO_CONTRACT
            means the whole index was never ⊤-marked, so nothing was proved for ANY rule. A SARIF
            consumer reading `properties.soundness` needs the same distinction the JSON channel
            already gives it. *)
         soundness =
           (match r.verdict with
           | "UNKNOWN" -> Some "unknown_top"
           | "UNKNOWN_NO_CONTRACT" -> Some "no_contract"
           | _ -> None);
         top_reasons = r.top_reasons;
         (* `locations` MUST be display labels from `Arch_graph.label` (see
            `Arch_sarif.finding.locations`'s doc comment) — `split_label` parses them on that
            contract, and a mismatch fabricates a bogus `physicalLocation`. Only `reach` and
            `exported` build `detail` that way (`List.map lbl ...` above); `dep`'s detail rows are
            "A --kind--> B  (line N)" prose and `effect`'s are "name KIND VALUE" prose — neither
            is a label, and `dep`'s in particular contains the exact "  (" separator followed by a
            LINE NUMBER, which `split_label` would parse as a file name. Those two kinds carry
            their evidence in `message` only (`message_of` above already appends `detail` there
            when `note` is `None`); `locations` stays empty for them rather than fabricating a
            `uri` that names no real file. *)
         locations = (match r.kind with "reach" | "exported" -> r.detail | _ -> []);
         detail_total = r.detail_total; code_flow = r.witness }
     in
     let findings =
       (* "one result per rule verdict that is not PASS" (roadmap 2.1) — a PASS is a proof, not a
          finding, and putting proofs in the same list as violations is what CodeQL-style tools
          do that this repo's own design explicitly rejects. *)
       List.filter_map (fun r -> if r.verdict = "PASS" then None else Some (finding_of r)) results
     in
     let top_frontier = Arch_graph.SM.fold (fun _ n acc -> acc + n) g.tops 0 in
     let coverage = coverage_rows t in
     let notifications =
       List.filter_map
         (fun (c : Arch_sarif.coverage_row) ->
           if c.status = "not_analysed" then
             Some
               { Arch_sarif.language = c.language; analysis = c.analysis;
                 message =
                   Printf.sprintf "%s: not analysed%s" c.analysis
                     (match c.language with Some l -> " for language " ^ l | None -> "") }
           else None)
         coverage
     in
     let run : Arch_sarif.run =
       { producer; producer_version; category = "arch-index/rules"; findings; coverage;
         top_frontier = Some top_frontier; notifications;
         (* Mirrors the `--format json` channel's own top-level `contract_ok`/`computed`/`proved`
            fields (see above) — without these, an all-PASS run and a run that evaluated nothing
            both produce a document with an empty `results` list and no way to tell them apart. *)
         contract_ok = Some contract_ok; computed = Some true; proved = Some proved }
     in
     print_endline (Arch_sarif.to_string [ run ]))
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
