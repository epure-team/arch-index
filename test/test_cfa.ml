(* The oracle uses sorted lists and repeated full scans, not the production
   worklist, set representation, join or equality implementation. The copied
   kernel is Dune's exact source copy, never a second implementation. *)
module C = Arch_index_cfa

type operation = Target of int * string | Reason of int * string | Copy of int * int

let normalize = List.sort_uniq String.compare
let union a b = normalize (a @ b)

let oracle size operations =
  let targets = Array.make size [] and reasons = Array.make size [] in
  List.iter (function
    | Target (i, x) -> targets.(i) <- union targets.(i) [x]
    | Reason (i, x) -> reasons.(i) <- union reasons.(i) [x]
    | Copy _ -> ()) operations ;
  let changed = ref true in
  while !changed do
    changed := false ;
    List.iter (function
      | Copy (src, dst) ->
          let ts = union targets.(src) targets.(dst)
          and rs = union reasons.(src) reasons.(dst) in
          if ts <> targets.(dst) || rs <> reasons.(dst) then changed := true ;
          targets.(dst) <- ts ; reasons.(dst) <- rs
      | Target _ | Reason _ -> ()) operations
  done ;
  Array.init size (fun i -> targets.(i), reasons.(i))

let apply domain cells = function
  | Target (i, x) -> C.seed_target domain cells.(i) x
  | Reason (i, x) -> C.seed_reason domain cells.(i) x
  | Copy (src, dst) -> C.copy domain ~src:cells.(src) ~dst:cells.(dst)

let snapshot domain cells =
  Array.map (fun cell ->
    let v = C.value domain cell in
    C.String_set.elements v.targets, C.String_set.elements v.reasons) cells

let check_snapshot label expected actual =
  Alcotest.(check (array (pair (list string) (list string)))) label expected actual

let check_operations label size operations =
  let domain = C.create () in
  let cells = Array.init size (fun _ -> C.fresh domain) in
  List.iter (apply domain cells) operations ;
  C.solve domain ;
  check_snapshot label (oracle size operations) (snapshot domain cells)

let test_mixed_chain () =
  let operations = [Target (0, "f"); Reason (1, "opaque"); Copy (0, 1); Copy (1, 2)] in
  check_operations "mixed chain" 3 operations ;
  check_snapshot "original mixed inline assertion" [|["f"], ["opaque"]|]
    [|(oracle 3 operations).(2)|]

let test_cycle () =
  check_operations "seeded finite cycle" 2 [Copy (0, 1); Copy (1, 0); Target (0, "f")]

let test_exhaustive () =
  (* Every directed graph on three nodes, including self loops. Each is checked
     in forward, reverse, and duplicated order with both semantic components. *)
  for mask = 0 to 511 do
    let edges = ref [] in
    for src = 0 to 2 do
      for dst = 0 to 2 do
        if mask land (1 lsl (3 * src + dst)) <> 0 then
          edges := Copy (src, dst) :: !edges
      done
    done ;
    let operations = Target (0, "f") :: Reason (2, "callback_param") :: !edges in
    check_operations (Printf.sprintf "graph %d forward" mask) 3 operations ;
    check_operations (Printf.sprintf "graph %d reversed" mask) 3 (List.rev operations) ;
    check_operations (Printf.sprintf "graph %d duplicated" mask) 3 (operations @ operations)
  done

let test_bottom_and_unknown () =
  let domain = C.create () in
  let cells = Array.init 3 (fun _ -> C.fresh domain) in
  C.copy domain ~src:cells.(0) ~dst:cells.(1) ;
  C.copy domain ~src:cells.(1) ~dst:cells.(0) ;
  C.seed_reason domain cells.(2) "callback_param" ;
  C.seed_reason domain cells.(2) "callback_param" ;
  C.solve domain ;
  check_snapshot "unseeded cycle is bottom; same-kind reason is idempotent"
    [|[], []; [], []; [], ["callback_param"]|] (snapshot domain cells)

let test_late_updates () =
  let domain = C.create () in
  let cells = Array.init 4 (fun _ -> C.fresh domain) in
  let operations = ref [] in
  let batch label next =
    operations := !operations @ next ;
    List.iter (apply domain cells) next ;
    C.solve domain ;
    check_snapshot label (oracle 4 !operations) (snapshot domain cells)
  in
  batch "initial bottom cycle" [Copy (0, 1); Copy (1, 0)] ;
  batch "seed entering visited cycle" [Target (0, "f")] ;
  batch "reason entering visited cycle" [Reason (1, "dropped_node")] ;
  batch "copy after solve" [Copy (1, 2); Copy (2, 3)] ;
  batch "late independent target and duplicate" [Target (3, "g"); Copy (3, 0); Copy (3, 0)] ;
  batch "second solve idempotent" []

let test_long_chain () =
  let size = 2000 in
  let edges = List.init (size - 1) (fun i -> Copy (i, i + 1)) in
  check_operations "long chain" size (Target (0, "f") :: Reason (0, "opaque") :: edges)

(* Machine-readable probe for CHECK-1. A solve operation emits every cell's
   normalized product value. Invalid input is a setup error (exit 2), never an
   assertion failure or a successful empty run. *)
let run_probe () =
  let open Yojson.Basic.Util in
  let input = Yojson.Basic.from_channel stdin in
  let size = input |> member "cells" |> to_int in
  if size < 1 || size > 10000 then invalid_arg "cells must be in 1..10000" ;
  let domain = C.create () in
  let cells = Array.init size (fun _ -> C.fresh domain) in
  let snapshots = ref [] in
  input |> member "operations" |> to_list |> List.iter (function
    | `List [`String "target"; `Int i; `String x] -> apply domain cells (Target (i, x))
    | `List [`String "reason"; `Int i; `String x] -> apply domain cells (Reason (i, x))
    | `List [`String "copy"; `Int src; `Int dst] -> apply domain cells (Copy (src, dst))
    | `List [`String "solve"] ->
        C.solve domain ; snapshots := snapshot domain cells :: !snapshots
    | _ -> invalid_arg "invalid CFA probe operation") ;
  if !snapshots = [] then invalid_arg "probe requires at least one solve" ;
  let strings xs = `List (List.map (fun x -> `String x) xs) in
  let json = `List (List.rev_map (fun values ->
    `List (Array.to_list values |> List.map (fun (targets, reasons) ->
      `Assoc ["targets", strings targets; "reasons", strings reasons]))) !snapshots) in
  Yojson.Basic.to_channel stdout json ; print_newline ()

let () =
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--probe" then
    (try run_probe () with exn ->
      prerr_endline ("CFA probe setup error: " ^ Printexc.to_string exn) ; exit 2)
  else
    Alcotest.run "CFA finite inclusion"
      ["domain", [
        Alcotest.test_case "mixed target/reason chain" `Quick test_mixed_chain;
        Alcotest.test_case "finite seeded cycle" `Quick test_cycle;
        Alcotest.test_case "all three-node graphs and orderings" `Quick test_exhaustive;
        Alcotest.test_case "bottom, unknown and duplicate reasons" `Quick test_bottom_and_unknown;
        Alcotest.test_case "late seeds, copies and repeated solve" `Quick test_late_updates;
        Alcotest.test_case "long chain" `Quick test_long_chain]]
