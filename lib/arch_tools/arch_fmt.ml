(** Result rendering, reproducing the sqlite3 shell's output modes.

    The bash tools shelled out to [sqlite3 -box]; the selftests and every human habit are built
    on that exact shape, so it is reproduced rather than improved on. [list] is the machine
    form and is what the MCP server and CI use — a one-line verdict inside ~400 box-drawing
    characters spends a reader's attention (or an agent's context) on borders.

    {1 What "reproducing sqlite3" is pinned against}

    Every rule below was read off {b sqlite 3.45.1 on Linux} by probing, and the differential
    gate ({!scripts/query-port-diff.sh}) compares this renderer to that binary byte for byte.
    Two shapes are worth naming because the sqlite shell has changed them before and a
    divergence would be silent:

    - {b Row separator in [-csv].} 3.45 emits LF. RFC 4180 says CRLF, and the shell's
      [.mode csv] has used [\r\n] in other builds. Measured, not assumed.
    - {b Numeric alignment in [-box] / [-markdown].} 3.45 left-aligns every data cell,
      including integers; some versions right-align numeric columns.

    Neither is reproduced from a specification — both are measured. If the sqlite the gate runs
    against changes either one, the gate reports it as a diff, which is the intended mechanism:
    this file has no independent claim to correctness beyond matching the binary it replaced. *)

type mode = Box | List | Json | Csv | Line | Markdown

let mode_of_string = function
  | "box" -> Some Box
  | "list" -> Some List
  | "json" -> Some Json
  | "csv" -> Some Csv
  | "line" -> Some Line
  | "markdown" -> Some Markdown
  | _ -> None

(** Display width in terminal cells, not bytes.

    Box borders are aligned by counting CHARACTERS, and the payload here is routinely UTF-8:
    module paths, and the ⊤ and — that appear in every verdict string. Counting bytes would
    make every row containing one of them ragged. This counts UTF-8 code points, which is right
    for the Latin/symbol text this tool emits (it does not attempt East-Asian double-width). *)
let display_width s =
  let n = ref 0 in
  String.iter (fun c -> if Char.code c land 0xC0 <> 0x80 then incr n) s ;
  !n

let pad s w =
  let d = w - display_width s in
  if d <= 0 then s else s ^ String.make d ' '

(* sqlite3 CENTRES the header and left-aligns the data, in both -box and -markdown. Left
   padding is floor(slack/2), right is the remainder. Getting this wrong is invisible in a
   unit test and glaring in a golden-file diff. *)
let centre s w =
  let d = w - display_width s in
  if d <= 0 then s else String.make (d / 2) ' ' ^ s ^ String.make (d - (d / 2)) ' '

let repeat s n = String.concat "" (List.init n (fun _ -> s))

let box headers rows =
  let cols = List.length headers in
  if cols = 0 then ""
  else
    let widths =
      List.mapi
        (fun i h ->
          List.fold_left
            (fun acc r -> max acc (display_width (List.nth r i)))
            (display_width h) rows)
        headers
    in
    let rule l m r =
      l ^ String.concat m (List.map (fun w -> repeat "\xe2\x94\x80" (w + 2)) widths) ^ r
    in
    let line ?(align = pad) cells =
      "\xe2\x94\x82 "
      ^ String.concat " \xe2\x94\x82 " (List.map2 align cells widths)
      ^ " \xe2\x94\x82"
    in
    String.concat "\n"
      ([ rule "\xe2\x94\x8c" "\xe2\x94\xac" "\xe2\x94\x90"; line ~align:centre headers;
         rule "\xe2\x94\x9c" "\xe2\x94\xbc" "\xe2\x94\xa4" ]
      @ List.map line rows
      @ [ rule "\xe2\x94\x94" "\xe2\x94\xb4" "\xe2\x94\x98" ])

(* sqlite3's shell quotes a CSV field containing the separator, a quote, any byte <= 0x20
   (which includes a plain SPACE) or any byte >= 0x80 (so every field carrying a UTF-8
   character). Neither of the last two is in RFC 4180 and both are easy to miss — these verdict
   strings contain spaces, em dashes and ⊤, so all three clauses fire in practice. Determined by
   probing `sqlite3 -csv`, not assumed. *)
let csv_cell s =
  let needs =
    String.exists (fun c -> c = ',' || c = '"' || Char.code c <= 0x20 || Char.code c >= 0x80) s
  in
  if needs then "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\"" else s

(* sqlite3 -json emits a COMPACT object per row, one per line, and preserves SQL types:
   integers and reals as JSON numbers, NULL as null.

   REAL needs sqlite's own rule, which is neither OCaml's shortest-round-trip nor a plain
   printf: {b 18 significant digits, TRUNCATED rather than rounded}, with a mandatory decimal
   point. Determined by probing, not guessed —
     184.2 → 184.199999999999988   (%.18g rounds to …989)
     26.4  → 26.3999999999999985   (%.18g rounds to …986)
     0.1   → 0.100000000000000005  (%.18g rounds to …006)
     125.0 → 125.0
   All parse back to the same double, so this is presentation only; it is matched because a
   byte-identical guarantee with "except floats" attached is worth much less than a whole one. *)
(* KNOWN DIVERGENCE, stated rather than papered over: for a value large or small enough that
   [%.20g] produces an EXPONENT form, sqlite's own mantissa length does not follow a rule this
   truncation reproduces — 1e300 renders as "1.000000000000000052e+300" (19 significant digits)
   while 1e-7 renders as "9.99999999999999954e-08" (18). Those magnitudes cannot arise from any
   REAL this schema stores (the only one is a per-kLOC ratio), so the exponent string is passed
   through as-is. Every non-exponent value is byte-identical, which is what the differential gate
   against sqlite covered. *)
let json_float f =
  if Float.is_integer f && Float.abs f < 1e15 then Printf.sprintf "%.1f" f
  else
    let s = Printf.sprintf "%.20g" f in
    if String.exists (fun c -> c = 'e' || c = 'E' || c = 'n' || c = 'i') s then s
    else
      let buf = Buffer.create 24 in
      let sig_digits = ref 0 and started = ref false in
      String.iter
        (fun c ->
          if c = '-' || c = '.' then Buffer.add_char buf c
          else if !sig_digits < 18 then (
            if c <> '0' then started := true ;
            if !started then incr sig_digits ;
            Buffer.add_char buf c))
        s ;
      let s = Buffer.contents buf in
      if String.contains s '.' then s else s ^ ".0"

let json_of_cell = function
  | Arch_db.Nul -> `Null
  | Arch_db.Int i -> `Int i
  (* `Intlit passes the literal through verbatim, which is how sqlite's float text reaches the
     output unmodified by Yojson's own float printer. *)
  | Arch_db.Real f -> `Intlit (json_float f)
  | Arch_db.Text s -> `String s

let render mode typed_rows headers =
  let rows = List.map (List.map Arch_db.string_of_cell) typed_rows in
  match rows with
  | [] -> ""
  | _ -> (
      match mode with
      | Box -> box headers rows
      | List -> String.concat "\n" (List.map (String.concat "|") rows)
      | Csv ->
          (* sqlite3 runs with `.headers off`, so -csv emits DATA ONLY. Adding a header row
             here would corrupt every downstream consumer that counts on the first line
             being a record. *)
          String.concat "\n" (List.map (fun r -> String.concat "," (List.map csv_cell r)) rows)
      | Markdown ->
          let widths =
            List.mapi
              (fun i h ->
                List.fold_left (fun acc r -> max acc (display_width (List.nth r i))) (display_width h) rows)
              headers
          in
          let row ?(align = pad) cells =
            "| " ^ String.concat " | " (List.map2 align cells widths) ^ " |"
          in
          String.concat "\n"
            (row ~align:centre headers
            :: ("|" ^ String.concat "|" (List.map (fun w -> repeat "-" (w + 2)) widths) ^ "|")
            :: List.map (fun r -> row r) rows)
      | Line ->
          (* sqlite3 RIGHT-aligns the header in -line mode. Left-aligning it is the kind of
             difference no unit test would catch and every golden-file diff would. *)
          let w = List.fold_left (fun a h -> max a (display_width h)) 0 headers in
          let rpad s =
            let d = w - display_width s in
            if d <= 0 then s else String.make d ' ' ^ s
          in
          String.concat "\n\n"
            (List.map
               (fun r ->
                 String.concat "\n"
                   (List.map2 (fun h c -> Printf.sprintf "%s = %s" (rpad h) c) headers r))
               rows)
      | Json ->
          "["
          ^ String.concat ",\n"
              (List.map
                 (fun r ->
                   Yojson.Safe.to_string
                     (`Assoc (List.map2 (fun h c -> (h, json_of_cell c)) headers r)))
                 typed_rows)
          ^ "]")

let print mode headers rows =
  let s = render mode rows headers in
  if s <> "" then print_endline s
