(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** See arch_errors_config.mli. *)

type mode = Add | Replace

type channel = {
  name : string;
  type_paths : string list;
  error_arg : int option;
  lift : string list;
  error_type : string option;
  unwrap : string list;
  origins : (string * int) list;
  binds : string list;
  handlers : (string * int) list;
  transforms : (string * mode * int) list;
  converters : (string * string * string * int * string option) list;
  sinks : string list;
}

type t = {
  channels : channel list;
  summaries : (string * (string * string list) list) list;
}

(* -------------------------------------------------------------------------- *)
(* Built-ins                                                                  *)
(* -------------------------------------------------------------------------- *)

let exception_channel =
  {
    name = "exception";
    type_paths = [];
    error_arg = None;
    lift = [];
    error_type = None;
    unwrap = [];
    origins = [];
    binds = [];
    handlers = [];
    transforms = [];
    converters = [];
    sinks = [];
  }

let result_channel =
  {
    name = "result";
    (* Both spellings the compiler can print for the same predefined type —
       see roster/error-channels/feasibility-probe.md Q2, generalised here:
       an unqualified alias occurrence and the [Stdlib.]-qualified one. *)
    type_paths = ["result"; "Stdlib.result"];
    error_arg = Some 2;
    lift = [];
    error_type = None;
    unwrap = [];
    origins = [("Stdlib.Error", 1)];
    binds =
      ["Stdlib.Result.bind"; "Stdlib.Result.Syntax.let*"; "Stdlib.Result.Syntax.and*"];
    handlers =
      [
        ("Stdlib.Result.value", 1);
        ("Stdlib.Result.fold", 1);
        ("Stdlib.Result.get_ok", 1);
      ];
    transforms = [("Stdlib.Result.map_error", Replace, 1)];
    converters = [];
    sinks = [];
  }

let option_channel =
  {
    name = "option";
    type_paths = ["option"; "Stdlib.option"];
    error_arg = None;
    lift = [];
    (* "" = identity — the error is the [None] constructor itself, not an
       argument of it. *)
    error_type = Some "";
    unwrap = [];
    origins = [("None", 0)];
    binds =
      ["Stdlib.Option.bind"; "Stdlib.Option.Syntax.let*"; "Stdlib.Option.Syntax.and*"];
    handlers =
      [("Stdlib.Option.value", 1); ("Stdlib.Option.get", 1); ("Stdlib.Option.fold", 1)];
    transforms = [];
    converters = [];
    sinks = [];
  }

let builtin = { channels = [exception_channel; result_channel; option_channel]; summaries = [] }

(* -------------------------------------------------------------------------- *)
(* Wildcard path matching — [*] in the UNIT component of a profile path      *)
(* -------------------------------------------------------------------------- *)

let has_wildcard s = String.contains s '*'

let path_matches (pattern : string) (actual : string) : bool =
  if not (has_wildcard pattern) then pattern = actual
  else
    let plen = String.length pattern and alen = String.length actual in
    let rec go pi si =
      if pi = plen then si = alen
      else
        match pattern.[pi] with
        | '*' -> go (pi + 1) si || (si < alen && go pi (si + 1))
        | c -> si < alen && actual.[si] = c && go (pi + 1) (si + 1)
    in
    go 0 0

(* -------------------------------------------------------------------------- *)
(* TOML parsing                                                               *)
(* -------------------------------------------------------------------------- *)

let known_channel_keys =
  [
    "type"; "underlying"; "error_arg"; "lift"; "error_type"; "aliases";
    "origins"; "binds"; "handlers"; "transforms"; "converters"; "sinks"; "unwrap";
  ]

let reject_unknown_keys ~what tbl allowed =
  List.iter
    (fun (k, _) ->
      if not (List.mem k allowed) then
        failwith (Printf.sprintf "arch-errors.toml: %s: unknown key '%s'" what k))
    tbl

let get_table_exn ~what v =
  try Otoml.get_table v
  with _ -> failwith (Printf.sprintf "arch-errors.toml: %s must be a table" what)

let get_string_req tbl ~what k =
  match List.assoc_opt k tbl with
  | Some (Otoml.TomlString s) -> s
  | Some _ -> failwith (Printf.sprintf "arch-errors.toml: %s: '%s' must be a string" what k)
  | None -> failwith (Printf.sprintf "arch-errors.toml: %s: missing required key '%s'" what k)

let get_string_opt tbl ~what k =
  match List.assoc_opt k tbl with
  | None -> None
  | Some (Otoml.TomlString s) -> Some s
  | Some _ -> failwith (Printf.sprintf "arch-errors.toml: %s: '%s' must be a string" what k)

let get_int_opt tbl ~what k =
  match List.assoc_opt k tbl with
  | None -> None
  | Some (Otoml.TomlInteger i) -> Some i
  | Some _ -> failwith (Printf.sprintf "arch-errors.toml: %s: '%s' must be an integer" what k)

let get_int_default tbl ~what k ~default =
  match get_int_opt tbl ~what k with Some i -> i | None -> default

let get_str_list tbl ~what k =
  match List.assoc_opt k tbl with
  | None -> []
  | Some (Otoml.TomlArray items) ->
      List.map
        (function
          | Otoml.TomlString s -> s
          | _ ->
              failwith
                (Printf.sprintf "arch-errors.toml: %s: '%s' must be an array of strings" what k))
        items
  | Some _ -> failwith (Printf.sprintf "arch-errors.toml: %s: '%s' must be an array" what k)

let get_entries tbl ~what k =
  match List.assoc_opt k tbl with
  | None -> []
  | Some (Otoml.TomlArray items) ->
      List.map (fun item -> get_table_exn ~what:(Printf.sprintf "%s.%s[]" what k) item) items
  | Some _ -> failwith (Printf.sprintf "arch-errors.toml: %s: '%s' must be an array" what k)

let decode_channel (name : string) (v : Otoml.t) : channel =
  let what = Printf.sprintf "channel %s" name in
  let tbl = get_table_exn ~what v in
  reject_unknown_keys ~what tbl known_channel_keys ;
  let type_ = get_string_req tbl ~what "type" in
  let underlying = get_str_list tbl ~what "underlying" in
  let aliases = get_str_list tbl ~what "aliases" in
  let origins =
    List.map
      (fun et ->
        let ewhat = Printf.sprintf "%s.origins[]" what in
        reject_unknown_keys ~what:ewhat et ["path"; "arg"] ;
        (get_string_req et ~what:ewhat "path", get_int_default et ~what:ewhat "arg" ~default:1))
      (get_entries tbl ~what "origins")
  in
  let handlers =
    List.map
      (fun et ->
        let ewhat = Printf.sprintf "%s.handlers[]" what in
        reject_unknown_keys ~what:ewhat et ["path"; "arg"] ;
        (get_string_req et ~what:ewhat "path", get_int_default et ~what:ewhat "arg" ~default:1))
      (get_entries tbl ~what "handlers")
  in
  let transforms =
    List.map
      (fun et ->
        let ewhat = Printf.sprintf "%s.transforms[]" what in
        reject_unknown_keys ~what:ewhat et ["path"; "mode"; "arg"] ;
        let path = get_string_req et ~what:ewhat "path" in
        let mode =
          match get_string_req et ~what:ewhat "mode" with
          | "add" -> Add
          | "replace" -> Replace
          | other ->
              failwith (Printf.sprintf "arch-errors.toml: %s: unknown mode '%s'" ewhat other)
        in
        (path, mode, get_int_default et ~what:ewhat "arg" ~default:1))
      (get_entries tbl ~what "transforms")
  in
  let converters =
    List.map
      (fun et ->
        let ewhat = Printf.sprintf "%s.converters[]" what in
        reject_unknown_keys ~what:ewhat et ["path"; "from"; "to"; "arg"; "error"] ;
        let path = get_string_req et ~what:ewhat "path" in
        let from_ = get_string_req et ~what:ewhat "from" in
        let to_ = get_string_req et ~what:ewhat "to" in
        let arg = get_int_default et ~what:ewhat "arg" ~default:1 in
        let error = get_string_opt et ~what:ewhat "error" in
        (path, from_, to_, arg, error))
      (get_entries tbl ~what "converters")
  in
  {
    name;
    type_paths = (type_ :: underlying) @ aliases;
    error_arg = get_int_opt tbl ~what "error_arg";
    lift = get_str_list tbl ~what "lift";
    error_type = get_string_opt tbl ~what "error_type";
    unwrap = get_str_list tbl ~what "unwrap";
    origins;
    binds = get_str_list tbl ~what "binds";
    handlers;
    transforms;
    converters;
    sinks = get_str_list tbl ~what "sinks";
  }

let of_toml (s : string) : (t, string) result =
  match Otoml.Parser.from_string_result s with
  | Error e -> Error e
  | Ok toml -> (
      try
        let top = get_table_exn ~what:"arch-errors.toml" toml in
        let channels = ref [] in
        let summaries = ref [] in
        List.iter
          (fun (key, value) ->
            match key with
            | "channel" ->
                let chans = get_table_exn ~what:"channel" value in
                List.iter
                  (fun (cname, cval) -> channels := decode_channel cname cval :: !channels)
                  chans
            | "summaries" ->
                let entries = get_table_exn ~what:"summaries" value in
                List.iter
                  (fun (callee, cv) ->
                    let per_chan = get_table_exn ~what:(Printf.sprintf "summaries.%s" callee) cv in
                    let lst =
                      List.map
                        (fun (chan_name, arr) ->
                          let paths =
                            match arr with
                            | Otoml.TomlArray items ->
                                List.map
                                  (function
                                    | Otoml.TomlString s -> s
                                    | _ ->
                                        failwith
                                          (Printf.sprintf
                                             "arch-errors.toml: summaries.%s.%s must be an \
                                              array of strings"
                                             callee
                                             chan_name))
                                  items
                            | _ ->
                                failwith
                                  (Printf.sprintf
                                     "arch-errors.toml: summaries.%s.%s must be an array"
                                     callee
                                     chan_name)
                          in
                          (chan_name, paths))
                        per_chan
                    in
                    summaries := (callee, lst) :: !summaries)
                  entries
            | k -> failwith (Printf.sprintf "arch-errors.toml: unknown top-level key '%s'" k))
          top ;
        Ok { channels = List.rev !channels; summaries = List.rev !summaries }
      with
      | Failure msg -> Error msg
      | Otoml.Type_error msg -> Error msg
      | Otoml.Key_error msg -> Error msg
      | Otoml.Duplicate_key msg -> Error msg)

(* -------------------------------------------------------------------------- *)
(* Merge — right wins per channel name / summary callee, builtin < profile <  *)
(* user, order preserved (base first, then override's new entries)           *)
(* -------------------------------------------------------------------------- *)

let merge_named ~name_of (base : 'a list) (override : 'a list) : 'a list =
  let tbl = Hashtbl.create 16 in
  List.iter (fun x -> Hashtbl.replace tbl (name_of x) x) base ;
  List.iter (fun x -> Hashtbl.replace tbl (name_of x) x) override ;
  let seen = Hashtbl.create 16 in
  let order = ref [] in
  List.iter
    (fun x ->
      let n = name_of x in
      if not (Hashtbl.mem seen n) then (
        Hashtbl.replace seen n () ;
        order := n :: !order))
    (base @ override) ;
  List.rev !order |> List.map (fun n -> Hashtbl.find tbl n)

let merge (base : t) (override : t) : t =
  {
    channels = merge_named ~name_of:(fun (c : channel) -> c.name) base.channels override.channels;
    summaries =
      merge_named ~name_of:(fun (s, _) -> s) base.summaries override.summaries;
  }

(* -------------------------------------------------------------------------- *)
(* Digest — canonical structural serialisation, MD5 hex                      *)
(* -------------------------------------------------------------------------- *)

let string_of_mode = function Add -> "add" | Replace -> "replace"

let join_sorted l = String.concat "," (List.sort compare l)

let canon_channel (c : channel) =
  let pa l = join_sorted (List.map (fun (p, a) -> Printf.sprintf "%s:%d" p a) l) in
  let tr l =
    join_sorted (List.map (fun (p, m, a) -> Printf.sprintf "%s:%s:%d" p (string_of_mode m) a) l)
  in
  let cv l =
    join_sorted
      (List.map
         (fun (p, f, to_, a, e) ->
           Printf.sprintf "%s:%s:%s:%d:%s" p f to_ a (Option.value ~default:"\x00" e))
         l)
  in
  Printf.sprintf
    "name=%s|type_paths=%s|error_arg=%s|lift=%s|error_type=%s|unwrap=%s|origins=%s|binds=%s|\
     handlers=%s|transforms=%s|converters=%s|sinks=%s"
    c.name
    (join_sorted c.type_paths)
    (match c.error_arg with Some i -> string_of_int i | None -> "")
    (join_sorted c.lift)
    (Option.value ~default:"\x00" c.error_type)
    (join_sorted c.unwrap)
    (pa c.origins)
    (join_sorted c.binds)
    (pa c.handlers)
    (tr c.transforms)
    (cv c.converters)
    (join_sorted c.sinks)

let canon_summary (callee, chans) =
  let chans_sorted = List.sort (fun (a, _) (b, _) -> compare a b) chans in
  Printf.sprintf
    "%s={%s}"
    callee
    (String.concat
       ";"
       (List.map (fun (cn, paths) -> Printf.sprintf "%s:%s" cn (join_sorted paths)) chans_sorted))

let digest (t : t) : string =
  let channels_sorted = List.sort (fun (a : channel) b -> compare a.name b.name) t.channels in
  let chan_str = String.concat "#" (List.map canon_channel channels_sorted) in
  let summaries_sorted = List.sort (fun (a, _) (b, _) -> compare a b) t.summaries in
  let sum_str = String.concat "#" (List.map canon_summary summaries_sorted) in
  Digest.to_hex (Digest.string (chan_str ^ "##" ^ sum_str))

(* -------------------------------------------------------------------------- *)
(* Validation — declared-set-with-found-flags                                *)
(* -------------------------------------------------------------------------- *)

type seen = {
  values : (string, bool ref) Hashtbl.t;
  types : (string, bool ref) Hashtbl.t;
  values_wild : string list;  (** subset of [values]' keys containing [*] *)
  types_wild : string list;  (** subset of [types]' keys containing [*] *)
}

(* FIX (review round 1, HIGH): [lift] and [unwrap] used to be listed here.
   They are TYPE paths, not value paths — [Arch_index_errch.strip_wrapper]
   compares them against a [Tconstr]'s [Path.name] (the shipped Tezos
   profile declares [lift = ["Lwt.t"; ...]] and
   [unwrap = ["...Error_monad.trace"]]), and the walker reports type
   occurrences through [note_type_path], which only ever flips flags in the
   [types] table. Seeded into [values], they could therefore never be
   found: EVERY config declaring a lift or an unwrap reported them as
   "matched nothing", and [--errors-strict] exited 1 unconditionally —
   including for [profiles/tezos-errors.toml], whose whole reason to exist
   is [--errors-profile tezos]. *)
let declared_value_paths (c : channel) =
  List.map fst c.origins
  @ List.map fst c.handlers
  @ c.binds
  @ List.map (fun (p, _, _) -> p) c.transforms
  @ List.map (fun (p, _, _, _, _) -> p) c.converters
  @ c.sinks

(* Every path this channel expects to meet as a TYPE. The carrier spellings
   ([type]/[underlying]/[aliases], all folded into [type_paths] at parse
   time) plus the two wrapper lists. Only [type_paths] participates in the
   "carrier matched nothing at all" FATAL rule below — a [lift] wrapper the
   corpus happens not to use is an ordinary per-path miss, not a dead
   channel. *)
let declared_type_paths (c : channel) = c.type_paths @ c.lift @ c.unwrap

let create (t : t) : seen =
  let values = Hashtbl.create 64 and types = Hashtbl.create 64 in
  List.iter
    (fun c ->
      List.iter
        (fun p -> if not (Hashtbl.mem values p) then Hashtbl.replace values p (ref false))
        (declared_value_paths c) ;
      List.iter
        (fun p -> if not (Hashtbl.mem types p) then Hashtbl.replace types p (ref false))
        (declared_type_paths c))
    t.channels ;
  let wild_keys tbl = Hashtbl.fold (fun k _ acc -> if has_wildcard k then k :: acc else acc) tbl [] in
  { values; types; values_wild = wild_keys values; types_wild = wild_keys types }

let note_value_path (s : seen) (p : string) =
  match Hashtbl.find_opt s.values p with
  | Some flag -> flag := true
  | None ->
      List.iter
        (fun pat -> if path_matches pat p then (Hashtbl.find s.values pat) := true)
        s.values_wild

let note_type_path (s : seen) (p : string) =
  match Hashtbl.find_opt s.types p with
  | Some flag -> flag := true
  | None ->
      List.iter
        (fun pat -> if path_matches pat p then (Hashtbl.find s.types pat) := true)
        s.types_wild

let unmatched (s : seen) : string list =
  let acc = ref [] in
  Hashtbl.iter (fun p flag -> if not !flag then acc := p :: !acc) s.values ;
  Hashtbl.iter (fun p flag -> if not !flag then acc := p :: !acc) s.types ;
  List.sort compare !acc

(* -------------------------------------------------------------------------- *)
(* Reachability — a channel shadowed by an earlier one (review round 1, HIGH) *)
(* -------------------------------------------------------------------------- *)

(* Carrier-channel selection is FIRST-MATCH-WINS over the merged channel list
   ([Arch_index_errch.carrier_channel_of_type] is a [List.find_opt]), so a
   channel whose carrier types are all already claimed by an earlier channel
   can never own a carrier. It is not inert-and-harmless: it is still
   published in [comment_db_meta.error_contract], so every query on it
   answers [NOT_A_CARRIER(c)] — a claim ABOUT THE CODE — where the truth is
   "this channel was never applicable". That is exactly the "looked and found
   nothing" / "never looked" confusion the whole feature exists to prevent,
   so a shadowed declaration is refused at load time instead of shipped.

   [claims ~earlier ~later p]: would [earlier] swallow every carrier that
   [later] claims through its type path [p]? Deliberately conservative — it
   says yes only when [earlier] both spells a pattern covering [p] AND
   applies no narrower argument test than [later] does. Two channels over
   the same carrier type distinguished by [error_type] (e.g. two [result]
   channels with different error types) stay reachable and are not refused. *)
let claims ~(earlier : channel) ~(later : channel) (p : string) =
  let covers = List.exists (fun p' -> path_matches p' p) earlier.type_paths in
  let no_narrower_test =
    (* [Arch_index_errch.error_arg_ok] returns [true] unconditionally for
       these two shapes, so [earlier] accepts any argument list. *)
    earlier.error_arg = None || earlier.error_type = None || earlier.error_type = Some ""
    (* ...or the two apply the identical test, so neither can distinguish. *)
    || (earlier.error_arg = later.error_arg
       && earlier.error_type = later.error_type
       && earlier.unwrap = later.unwrap)
  in
  covers && no_narrower_test

(** See .mli. *)
let check_reachable (t : t) : (unit, string) result =
  let rec go seen_before = function
    | [] -> Ok ()
    | (c : channel) :: rest ->
        let shadowed_by p =
          List.find_opt (fun earlier -> claims ~earlier ~later:c p) seen_before
        in
        let verdict =
          if c.type_paths = [] then None
          else
            (* Every one of [c]'s spellings must be claimed for [c] to be
               unreachable; one free spelling is enough to keep it alive. *)
            List.fold_left
              (fun acc p ->
                match acc with
                | None -> None (* an earlier path was already free *)
                | Some found -> (
                    match shadowed_by p with
                    | None -> None
                    | Some earlier -> Some ((p, earlier) :: found)))
              (Some []) c.type_paths
        in
        (match verdict with
        | Some ((p, (earlier : channel)) :: _) ->
            Error
              (Printf.sprintf
                 "arch-errors: channel %s: carrier type '%s' is already claimed by channel \
                  '%s', declared earlier — channel selection is first-match-wins, so %s could \
                  never own a carrier and every query on it would answer NOT_A_CARRIER(%s) \
                  about code it never examined. Reorder the channels so the more specific one \
                  comes first, or merge the two declarations into one."
                 c.name p earlier.name c.name c.name)
        | _ -> go (seen_before @ [c]) rest)
  in
  go [] t.channels

(* A channel that came out of {!builtin} UNTOUCHED: same name, and every
   declared list still structurally identical to the built-in's ([merge]
   replaces a channel wholesale, so a profile or user file that redeclares
   [\[channel.option\]] produces a channel that is no longer this).

   Used to decide whose declarations may fail a [--errors-strict] run. The
   pre-existing [builtin_names] waiver on the FATAL carrier rule compares
   names only, which is right there (a built-in carrier absent from a small
   corpus is not a bug, whoever last edited the channel); for strict it is
   not enough — a user who redeclares [option] IS responsible for the paths
   they then wrote, and a name-only test would waive them. *)
let is_untouched_builtin (c : channel) =
  match List.find_opt (fun (b : channel) -> b.name = c.name) builtin.channels with
  | Some b -> canon_channel b = canon_channel c
  | None -> false

let validate (t : t) (s : seen) ~strict ?(builtin_names = []) () : (unit, string) result =
  (* (channel, message): the channel is carried so [--errors-strict] can tell
     a declaration the operator wrote from one they merely inherited. *)
  let warnings = ref [] in
  let fatal = ref None in
  List.iter
    (fun (c : channel) ->
      (if c.type_paths <> [] && !fatal = None && not (List.mem c.name builtin_names) then
         let all_missed =
           List.for_all
             (fun p ->
               match Hashtbl.find_opt s.types p with Some flag -> not !flag | None -> true)
             c.type_paths
         in
         if all_missed then
           fatal :=
             Some
               (Printf.sprintf
                  "arch-errors: channel %s: carrier type matched nothing in the indexed corpus"
                  c.name)) ;
      let note_miss tbl p =
        match Hashtbl.find_opt tbl p with
        | Some flag when not !flag ->
            warnings :=
              (c, Printf.sprintf "arch-errors: channel %s: '%s' matched nothing" c.name p)
              :: !warnings
        | _ -> ()
      in
      List.iter (note_miss s.values) (declared_value_paths c) ;
      List.iter (note_miss s.types) (declared_type_paths c))
    t.channels ;
  match !fatal with
  | Some msg -> Error msg
  | None ->
      let warnings = List.rev !warnings in
      List.iter (fun (_, w) -> Printf.eprintf "%s\n%!" w) warnings ;
      (* FIX (review round 1, HIGH, same root as the lift/unwrap one): only
         declarations the OPERATOR is responsible for may fail a strict run.
         Before this, an untouched built-in dragged its own Stdlib paths into
         every strict verdict — and one of them, ['Stdlib.option'], is a
         spelling the compiler NEVER prints (it prints the predefined type
         as bare [option]), so [--errors-strict] was unsatisfiable by
         construction for any corpus and any config, not merely awkward. *)
      let operator_warnings =
        List.filter (fun ((c : channel), _) -> not (is_untouched_builtin c)) warnings
      in
      if strict && operator_warnings <> [] then
        Error
          (Printf.sprintf
             "arch-errors: --errors-strict: %d declaration(s) matched nothing"
             (List.length operator_warnings))
      else Ok ()

(* -------------------------------------------------------------------------- *)
(* Inline tests                                                              *)
(* -------------------------------------------------------------------------- *)

let string_contains ~needle haystack =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let%test "of_toml round trip: a minimal channel parses" =
  match
    of_toml
      "[channel.myres]\ntype = \"Fx.Res.t\"\nunderlying = [\"Stdlib.result\"]\nerror_arg = 2\n\
       binds = [\"Fx.Res.bind\"]\n"
  with
  | Ok { channels = [c]; summaries = [] } ->
      c.name = "myres"
      && c.type_paths = ["Fx.Res.t"; "Stdlib.result"]
      && c.error_arg = Some 2
      && c.binds = ["Fx.Res.bind"]
  | _ -> false

let%test "of_toml: origins/handlers/transforms/converters array-of-tables decode" =
  match
    of_toml
      "[channel.myres]\ntype = \"Fx.Res.t\"\norigins = [{path = \"Fx.Error\", arg = 1}]\n\
       handlers = [{path = \"Fx.Res.value\"}]\n\
       transforms = [{path = \"Fx.Res.map_error\", mode = \"replace\", arg = 1}]\n\
       converters = [{path = \"Fx.catch\", from = \"exception\", to = \"myres\", arg = 1}]\n"
  with
  | Ok { channels = [c]; _ } ->
      c.origins = [("Fx.Error", 1)]
      && c.handlers = [("Fx.Res.value", 1)]
      && c.transforms = [("Fx.Res.map_error", Replace, 1)]
      && c.converters = [("Fx.catch", "exception", "myres", 1, None)]
  | _ -> false

let%test "of_toml: unknown key in a channel table is a naming error" =
  match of_toml "[channel.myres]\ntype = \"Fx.Res.t\"\nbogus = 1\n" with
  | Error msg -> string_contains ~needle:"bogus" msg
  | Ok _ -> false

let%test "of_toml: unknown top-level key is a naming error" =
  match of_toml "[nonsense]\nfoo = 1\n" with
  | Error msg -> string_contains ~needle:"nonsense" msg
  | Ok _ -> false

let%test "of_toml: a genuine TOML syntax error is passed through" =
  match of_toml "foo.bar.baz = " with Error _ -> true | Ok _ -> false

let%test "merge: override replaces a same-named channel, keeps others, preserves order" =
  let base =
    {
      channels =
        [
          { exception_channel with name = "a" }; { exception_channel with name = "b" };
        ];
      summaries = [];
    }
  in
  let override = { channels = [{ result_channel with name = "b" }]; summaries = [] } in
  let m = merge base override in
  List.map (fun (c : channel) -> c.name) m.channels = ["a"; "b"]
  && (List.find (fun (c : channel) -> c.name = "b") m.channels).error_arg = Some 2

let%test "digest: stable across reformatting of the same declarations" =
  let a =
    of_toml "[channel.myres]\ntype=\"Fx.Res.t\"\nbinds=[\"Fx.Res.bind\",\"Fx.Res.bind2\"]\n"
  in
  let b =
    of_toml
      "[channel.myres]\n  type   =   \"Fx.Res.t\"\n  binds = [ \"Fx.Res.bind2\" , \
       \"Fx.Res.bind\" ]\n"
  in
  match (a, b) with Ok ta, Ok tb -> digest ta = digest tb | _ -> false

let%test "digest: changes when a declared list changes" =
  let a = of_toml "[channel.myres]\ntype=\"Fx.Res.t\"\nbinds=[\"Fx.Res.bind\"]\n" in
  let b = of_toml "[channel.myres]\ntype=\"Fx.Res.t\"\nbinds=[\"Fx.Res.bind\",\"Fx.Res.other\"]\n" in
  match (a, b) with Ok ta, Ok tb -> digest ta <> digest tb | _ -> false

let%test "validate: an unseen non-carrier path is a warning, not fatal" =
  let cfg = { channels = [{ exception_channel with name = "e"; sinks = ["Stdlib.ignore"] }]; summaries = [] } in
  let s = create cfg in
  match validate cfg s ~strict:false () with
  | Ok () -> unmatched s = ["Stdlib.ignore"]
  | Error _ -> false

let%test "validate: --errors-strict promotes a miss to fatal" =
  let cfg = { channels = [{ exception_channel with name = "e"; sinks = ["Stdlib.ignore"] }]; summaries = [] } in
  let s = create cfg in
  match validate cfg s ~strict:true () with Error _ -> true | Ok () -> false

let%test "validate: a channel whose carrier type matches nothing is always fatal" =
  let cfg = { channels = [{ result_channel with name = "r" }]; summaries = [] } in
  let s = create cfg in
  match validate cfg s ~strict:false () with Error _ -> true | Ok () -> false

(* Review round 1, HIGH (FR-027): a channel shadowed by an earlier one. *)
let%test "check_reachable: the builtins alone are all reachable" =
  check_reachable builtin = Ok ()

let%test "check_reachable: a second channel on the same carrier type is refused" =
  (* Exactly the shipped profile's old [tzoption] shape. *)
  let tzoption = { option_channel with name = "tzoption" } in
  let cfg = { channels = builtin.channels @ [tzoption]; summaries = [] } in
  match check_reachable cfg with
  | Error msg ->
      (* The message must name BOTH channels: which one is dead, and what
         killed it. *)
      string_contains ~needle:"tzoption" msg && string_contains ~needle:"'option'" msg
  | Ok () -> false

let%test "check_reachable: only the SHADOWED channel is refused, not the earlier one" =
  let tzoption = { option_channel with name = "tzoption" } in
  (* Declared FIRST, so it is [option] that becomes unreachable. *)
  let cfg = { channels = [tzoption; option_channel]; summaries = [] } in
  match check_reachable cfg with
  | Error msg -> string_contains ~needle:"channel option:" msg
  | Ok () -> false

let%test "check_reachable: a distinguishing error_type keeps a shared carrier reachable" =
  (* Two [result] channels that differ in the error type they accept are
     genuinely both selectable — refusing them would be a false positive. *)
  let a = { result_channel with name = "a"; error_type = Some "Fx.err_a" } in
  let b = { result_channel with name = "b"; error_type = Some "Fx.err_b" } in
  check_reachable { channels = [a; b]; summaries = [] } = Ok ()

let%test "check_reachable: one unclaimed spelling is enough to stay reachable" =
  let later = { option_channel with name = "wide"; type_paths = ["option"; "My.opt"] } in
  check_reachable { channels = [option_channel; later]; summaries = [] } = Ok ()

let%test "check_reachable: a wildcard earlier channel shadows a matching literal" =
  let wide = { result_channel with name = "wide"; type_paths = ["Tz_*.result"] } in
  let narrow = { result_channel with name = "narrow"; type_paths = ["Tz_alpha.result"] } in
  match check_reachable { channels = [wide; narrow]; summaries = [] } with
  | Error _ -> true
  | Ok () -> false

let%test "check_reachable: a literal earlier channel does NOT shadow a wider wildcard" =
  let narrow = { result_channel with name = "narrow"; type_paths = ["Tz_alpha.result"] } in
  let wide = { result_channel with name = "wide"; type_paths = ["Tz_*.result"] } in
  check_reachable { channels = [narrow; wide]; summaries = [] } = Ok ()

(* Review round 1, HIGH: [lift]/[unwrap] are TYPE paths. Seeded into the
   VALUE set they were unreachable — [note_value_path] is never called with
   a type constructor's path — so they reported "matched nothing" forever. *)
let%test "validate: a lift path is found by note_type_path, not note_value_path" =
  let chan = { result_channel with name = "r"; lift = ["Lwt.t"]; unwrap = ["Tr.trace"] } in
  let cfg = { channels = [chan]; summaries = [] } in
  let s = create cfg in
  note_value_path s "Lwt.t" ;
  note_value_path s "Tr.trace" ;
  (* Still unmatched: a value occurrence says nothing about a type path. *)
  List.mem "Lwt.t" (unmatched s)
  && List.mem "Tr.trace" (unmatched s)
  &&
  (note_type_path s "Lwt.t" ;
   note_type_path s "Tr.trace" ;
   not (List.mem "Lwt.t" (unmatched s) || List.mem "Tr.trace" (unmatched s)))

let%test "validate: an unmatched lift path does not make the channel fatal" =
  (* Only [type_paths] carries the "carrier matched nothing" FATAL rule. *)
  let chan = { result_channel with name = "r"; lift = ["Lwt.t"] } in
  let cfg = { channels = [chan]; summaries = [] } in
  let s = create cfg in
  note_type_path s "result" ;
  match validate cfg s ~strict:false () with Ok () -> true | Error _ -> false

let%test "validate: an UNTOUCHED built-in's miss does not fail --errors-strict" =
  (* [Stdlib.option] is a spelling the compiler never prints, so a strict run
     that counted built-in misses could never succeed anywhere. *)
  let cfg = { channels = builtin.channels; summaries = [] } in
  let s = create cfg in
  match validate cfg s ~strict:true ~builtin_names:["exception"; "result"; "option"] () with
  | Ok () -> true
  | Error _ -> false

let%test "validate: REDECLARING a built-in puts it back under --errors-strict" =
  let redeclared = { option_channel with sinks = ["Fx.never_there"] } in
  let cfg = { channels = [redeclared]; summaries = [] } in
  let s = create cfg in
  match validate cfg s ~strict:true ~builtin_names:["option"] () with
  | Error _ -> true
  | Ok () -> false

let%test "validate: a matched carrier type is not fatal" =
  let cfg = { channels = [{ result_channel with name = "r" }]; summaries = [] } in
  let s = create cfg in
  note_type_path s "result" ;
  match validate cfg s ~strict:false () with Ok () -> true | Error _ -> false
