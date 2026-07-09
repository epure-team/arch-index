(* Unit tests for Arch_index_cfg: post-dominance of the entry over small CFGs. *)

module Cfg = Arch_index.Arch_index_cfg

(* single block, no successors: it is terminal → always-exec *)
let test_single_block () =
  let g = Cfg.create () in
  let v = Cfg.solve g in
  Alcotest.(check bool) "entry always" true (Cfg.always_exec v Cfg.entry)

(* diamond: entry → {a, b} → join. Arms conditional; join + entry always. *)
let test_diamond () =
  let g = Cfg.create () in
  let a = Cfg.new_block g and b = Cfg.new_block g and j = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry a ;
  Cfg.add_edge g Cfg.entry b ;
  Cfg.add_edge g a j ;
  Cfg.add_edge g b j ;
  let v = Cfg.solve g in
  Alcotest.(check bool) "entry" true (Cfg.always_exec v Cfg.entry) ;
  Alcotest.(check bool) "arm a" false (Cfg.always_exec v a) ;
  Alcotest.(check bool) "arm b" false (Cfg.always_exec v b) ;
  Alcotest.(check bool) "join" true (Cfg.always_exec v j)

(* loop: entry → head; head → {body, after}; body → head. Body conditional
   (may run zero times); after always. *)
let test_loop () =
  let g = Cfg.create () in
  let head = Cfg.new_block g
  and body = Cfg.new_block g
  and after = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry head ;
  Cfg.add_edge g head body ;
  Cfg.add_edge g head after ;
  Cfg.add_edge g body head ;
  let v = Cfg.solve g in
  Alcotest.(check bool) "head" true (Cfg.always_exec v head) ;
  Alcotest.(check bool) "body" false (Cfg.always_exec v body) ;
  Alcotest.(check bool) "after" true (Cfg.always_exec v after)

(* exit-less: entry → head; head → head. Nothing completes → nothing always. *)
let test_exitless () =
  let g = Cfg.create () in
  let head = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry head ;
  Cfg.add_edge g head head ;
  let v = Cfg.solve g in
  Alcotest.(check bool) "entry not always" false (Cfg.always_exec v Cfg.entry) ;
  Alcotest.(check bool) "head not always" false (Cfg.always_exec v head)

(* terminator split: entry terminated (raise); tail block gets NO edge from
   entry (add_edge is a no-op after terminate) → tail entry-unreachable,
   entry itself always (the raise always runs). *)
let test_terminator_split () =
  let g = Cfg.create () in
  Cfg.terminate g Cfg.entry ;
  let tail = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry tail ;
  (* ignored *)
  let v = Cfg.solve g in
  Alcotest.(check bool) "raise block always" true (Cfg.always_exec v Cfg.entry) ;
  Alcotest.(check bool) "tail unreachable" false (Cfg.reachable v tail) ;
  Alcotest.(check bool) "tail not always" false (Cfg.always_exec v tail)

(* both-branches-diverge: entry → {a, b}; a and b terminated; join has no
   incoming edge → unreachable; neither arm always (the other bypasses it). *)
let test_all_arms_diverge () =
  let g = Cfg.create () in
  let a = Cfg.new_block g and b = Cfg.new_block g and j = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry a ;
  Cfg.add_edge g Cfg.entry b ;
  Cfg.terminate g a ;
  Cfg.terminate g b ;
  Cfg.add_edge g a j ;
  (* ignored: a is terminated *)
  Cfg.add_edge g b j ;
  (* ignored *)
  let v = Cfg.solve g in
  Alcotest.(check bool) "entry always" true (Cfg.always_exec v Cfg.entry) ;
  Alcotest.(check bool) "arm a not always" false (Cfg.always_exec v a) ;
  Alcotest.(check bool) "arm b not always" false (Cfg.always_exec v b) ;
  Alcotest.(check bool) "join unreachable" false (Cfg.reachable v j)

(* terminator with a pre-registered handler edge (try model): edges added
   BEFORE terminate are kept — the handler is reachable but never always. *)
let test_terminator_with_handler () =
  let g = Cfg.create () in
  let handler = Cfg.new_block g and join = Cfg.new_block g in
  Cfg.add_edge g Cfg.entry handler ;
  (* dispatch edge, added before terminate *)
  Cfg.terminate g Cfg.entry ;
  Cfg.add_edge g handler join ;
  let v = Cfg.solve g in
  Alcotest.(check bool) "raise always" true (Cfg.always_exec v Cfg.entry) ;
  Alcotest.(check bool) "handler reachable" true (Cfg.reachable v handler) ;
  Alcotest.(check bool) "handler not always" false (Cfg.always_exec v handler) ;
  Alcotest.(check bool) "join not always" false (Cfg.always_exec v join)

let () =
  Alcotest.run
    "arch_index_cfg"
    [
      ( "postdom",
        [
          Alcotest.test_case "single_block" `Quick test_single_block;
          Alcotest.test_case "diamond" `Quick test_diamond;
          Alcotest.test_case "loop" `Quick test_loop;
          Alcotest.test_case "exitless" `Quick test_exitless;
          Alcotest.test_case "terminator_split" `Quick test_terminator_split;
          Alcotest.test_case "all_arms_diverge" `Quick test_all_arms_diverge;
          Alcotest.test_case
            "terminator_with_handler"
            `Quick
            test_terminator_with_handler;
        ] );
    ]
