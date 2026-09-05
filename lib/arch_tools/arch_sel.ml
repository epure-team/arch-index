(** Selectors: [file:<glob>], [fn:<glob>], [module:<glob>], [ext:<glob>],
    [exported:<glob>].

    Shared so that [file:test/**] means the same thing in [arch-rules], [arch-mutants] and
    [arch-coverage]. *)

(** [Exported] is [Fn] restricted to the API surface — the same population, filtered on the
    node's [exported] flag.

    {b Why it is spelled [exported:] and not [entry:].} This repository already names the concept
    three times: [Arch_graph.node.exported], [arch-query --roots exported], and the
    [forbid exported outside] rule form. A fourth spelling for the same set is the defect that
    rendered a failed SARIF import as [covered] on PR #80 — two names for one thing, agreeing
    everywhere except where it mattered. The verb [forbid exported outside] and the selector kind
    [exported:] live in different namespaces (rule verbs vs selector kinds) and cannot be
    confused by the parser.

    The flag itself is already normalised across the two schemas by {!Arch_graph}: the MAIN
    schema's column is [functions.exposed] and the FLAT schema's is [functions.exported], and
    both are read into [node.exported]. Selecting through the node rather than through SQL is
    what keeps that single normalisation point single. *)
type kind = File | Fn | Module | Ext | Exported
type t = kind * string

let kind_name = function
  | File -> "file" | Fn -> "fn" | Module -> "module" | Ext -> "ext" | Exported -> "exported"

let all_kinds = [ File; Fn; Module; Ext; Exported ]
let kinds_doc allow = String.concat ", " (List.map (fun k -> kind_name k ^ ":<glob>") allow)

(* The allow-list every call site used before `ext:` existed, and the one every call site that
   has not been taught about `ext:` still wants. Named once so that adding a fifth kind is one
   edit here rather than an audit of every `~allow` at every call site — `arch-coverage` and
   `arch-mutants` used to spell [File; Fn; Module] out by hand, which is exactly the duplication
   this guards against. *)
let structural = [ File; Fn; Module ]

(** The kinds valid as the SOURCE of a cone — [structural] plus [exported:].

    {b This list has TWO consumers}: [forbid reach]'s source position ([arch_rules.ml]) and
    [arch-coverage --roots] ([arch_coverage.ml]). Both genuinely range over a call cone, which
    is what makes one shared list the honest modelling rather than a convenience — but it means
    a kind added here lands in BOTH at once, and a reviewer looking at one need not look at the
    other. Smaller blast radius than [structural], identical mechanism. Name both when you
    widen it.

    Deliberately a separate name rather than an addition to [structural], which
    [arch-mutants --tests] still passes. The reason is SEMANTIC, not structural, and an earlier
    revision of this comment got that wrong: [--tests] does build a cone —
    [arch_mutants.ml:47] takes [Arch_graph.closure test_keys g.fwd] — so "its population is not
    a cone" was false. What is true is that its roots are meant to be the TEST SUITE, and
    "reachable from the API surface" is a different set: admitting the kind there would silently
    change what the mutation plan measures, rather than make it unanswerable. Widening
    [structural] in place would have handed it that by omission — the "silent reinterpretation
    by omission" the #73 review found in [Dep]. A kind is granted, never inherited.

    (An earlier revision of this comment said [structural] is "the list [arch-coverage] and
    [arch-mutants] pass, and neither ranges over a call cone". Both halves stopped being true
    when [arch-coverage --roots] was granted [Exported] — and the second half is the very
    argument that made the grant defensible, so the comment had come to contradict the change
    three lines below it.) *)
let cone_source = [ File; Fn; Module; Exported ]

(** [allow] is MANDATORY, and that is the point.

    [ext:] is meaningful in exactly one position — the TARGET of a [forbid reach]. An external
    leaf has no body, hence no outgoing edge and no file, so everywhere else it selects keys that
    cannot serve that position, and the two failure modes are not the same failure:

    {b [Exported]'s arm deliberately enumerates and explains nothing, and that is not
    laziness.} [Ext]'s clauses are earned by a STRUCTURAL property of its keys — no body, no
    outgoing edge, no file — which is what entitles it to say "keys that cannot serve this
    position". Exported nodes are ordinary nodes with bodies, edges and files, so there is no
    such property to carry, and three attempts to write one produced three claims that measure
    FALSE: that the refusing position does not range over a cone ([arch-coverage --roots] prints
    "API cone"); that an empty match there reads as a proof (a [reach] target matching nothing
    reports [1 vacuous], exit 1); that it would "select keys this position cannot serve"
    ([forbid dep] selects no keys at all — its evaluator never calls {!select}, it globs the
    pattern against [module_deps] rows — and admitting the kind there returns [1 proved],
    exit 0). Any "because" here must discriminate [forbid effect], which IS a cone start and is
    refused anyway. A list of the granted positions has nothing in it to be wrong about.

    - as a [reach] SOURCE, or (in principle) an [effect] cone, the selector still matches
      something real — the leaf itself — so no vacuity check fires. The cone then starts at a
      node with no outgoing edges, so it can never reach anything, and the rule reports a PASS it
      never earned: a false green, silently.
    - as a [dep] operand or an [exported] allow-list, the emptiness is caught the ordinary way —
      NO_SOURCE / VACUOUS — because those positions do not read [ext_keys] at all once the kind is
      rejected upstream of them.

    Either way a caller should not get it by omission, so the argument is mandatory rather than
    conventional: the compiler makes every call site name the kinds it can honestly serve, and a
    rejection is loud and specific rather than a silent wrong answer of either kind. *)
let parse ~allow tok =
  match String.index_opt tok ':' with
  | None -> Error (Printf.sprintf "bad selector %S — expected one of: %s" tok (kinds_doc allow))
  | Some i -> (
      let k = String.sub tok 0 i and pat = String.sub tok (i + 1) (String.length tok - i - 1) in
      match List.find_opt (fun c -> kind_name c = k) all_kinds with
      | None ->
          Error
            (Printf.sprintf "bad selector kind %S — expected one of: %s" k
               (String.concat ", " (List.map kind_name allow)))
      | Some c when not (List.mem c allow) ->
          (* Named separately from an unknown kind: `ext` IS a selector kind, it is just not
             answerable here, and "expected file, fn or module" would send the author looking for
             a typo that is not there. *)
          Error
            (Printf.sprintf "selector kind %S is not valid in this position — only %s. %s" k
               (String.concat ", " (List.map kind_name allow))
               (match c with
                | Ext -> "`ext:` matches external leaves, which have no body, no outgoing edge and no file, so it is answerable only as the target of `forbid reach`. Here it would select keys that cannot serve this position."
                | Exported -> "`exported:` is granted at exactly two positions: the SOURCE of `forbid reach`, and `arch-coverage --roots`. It is not granted here. Widening a position is a deliberate change with its own test."
                | File | Fn | Module -> "This position reads a different population."))
      | Some c -> Ok (c, pat))

let to_string (k, p) = kind_name k ^ ":" ^ p

(** Shell-style glob where [*] stops at ['/'] and [**] crosses it.

    [**/] compiles to [(?:.*/)?] — zero or more {b whole} directory components — so
    [**/parser.ml] matches [lib/parser.ml] and bare [parser.ml] but {b never} [lib/my_parser.ml].
    Getting this wrong is not cosmetic: a rule aimed at one file silently covering a
    differently-named sibling turns an architecture gate into a source of false verdicts in
    both directions. (An earlier version compiled [**/] to [.*/?] and did exactly that.)

    Implemented as a direct matcher rather than via Str, so the library needs no regexp
    dependency and the semantics are visible in one place.

    {b The [*]/[**] distinction is meaningful only where the value can contain ['/'].} For
    [ext:], it cannot: external OCaml names are dot-separated ([Stdlib.List.iter]), never
    slash-separated, so [*]'s "stop at ['/']" rule never triggers and [*] matches exactly as much
    as [**] does. [ext:Stdlib.*] and [ext:Stdlib.**] are therefore the same selector — both match
    the whole [Stdlib] subtree, which over-matches loudly in a [forbid] rule rather than silently
    passing something it should have caught, so this is a documentation gap, not a correctness
    one. See [select] below for where this matters. *)
let glob_match pattern value =
  let plen = String.length pattern and vlen = String.length value in
  (* memo.(i).(j) = "already proved (i,j) cannot match", so a pattern with several `**` cannot
     blow up exponentially on a long path. *)
  let memo = Array.make_matrix (plen + 1) (vlen + 1) false in
  let rec go i j =
    if memo.(i).(j) then false
    else if i >= plen then j >= vlen
    else
      let ok =
        if i + 2 < plen && pattern.[i] = '*' && pattern.[i + 1] = '*' && pattern.[i + 2] = '/'
        then
          (* zero components, or skip one whole component and retry *)
          go (i + 3) j
          || (let rec skip j =
                if j >= vlen then false
                else if value.[j] = '/' then go (i + 3) (j + 1) || skip (j + 1)
                else skip (j + 1)
              in
              skip j)
        else if i + 1 < plen && pattern.[i] = '*' && pattern.[i + 1] = '*' then
          let rec any j = go (i + 2) j || (j < vlen && any (j + 1)) in
          any j
        else if pattern.[i] = '*' then
          let rec any j =
            go (i + 1) j || (j < vlen && value.[j] <> '/' && any (j + 1))
          in
          any j
        else if pattern.[i] = '?' then j < vlen && value.[j] <> '/' && go (i + 1) (j + 1)
        else j < vlen && pattern.[i] = value.[j] && go (i + 1) (j + 1)
      in
      if not ok then memo.(i).(j) <- true ;
      ok
  in
  go 0 0

(** Resolve a selector to graph keys. [module:] matches the path, like [file:], everywhere
    except [forbid dep] — which reads declared module paths from a table, not from the graph.

    [ext:] is the one kind that does NOT range over [Arch_graph.nodes]: external leaves are not
    nodes (see [Arch_graph.ext_keys]), so it ranges over the external keys and matches the glob
    against the callee name with any ["ext:"] prefix stripped — the name as written at the call
    site, which is what a report shows and what a rule author can be asked to type.

    It is also the one kind for which [*] and [**] are indistinguishable — see the note on
    {!glob_match} — because an external name never contains ['/']. [ext:Stdlib.*] matches the
    same set as [ext:Stdlib.**]: the whole subtree, not just [Stdlib]'s immediate members. This
    is deliberately not special-cased into a different separator for [ext:]: doing that would
    make the same character mean two different things depending on which kind precedes it, which
    is the more surprising failure mode of the two. *)
let select (g : Arch_graph.t) ((k, pat) : t) =
  match k with
  | Ext ->
      Arch_graph.SS.filter
        (fun key -> glob_match pat (Arch_graph.ext_name key))
        (Arch_graph.ext_keys g)
  | File | Fn | Module | Exported ->
      List.fold_left
        (fun acc (n : Arch_graph.node) ->
          let target =
            match k with
            | Fn -> Some n.name
            (* An unexported node is not "a node that fails the glob" — it is outside the
               population entirely, so it is filtered before the glob is consulted rather than
               by an unmatchable pattern. [exported:**] therefore means "every entry point",
               not "every node". *)
            | Exported -> if n.exported then Some n.name else None
            | File | Module -> n.file
            | Ext -> None
          in
          match target with
          | Some v when glob_match pat v -> Arch_graph.SS.add n.key acc
          | _ -> acc)
        Arch_graph.SS.empty (Arch_graph.nodes g)
