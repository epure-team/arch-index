(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Pure per-function control-flow graph with post-dominance.

    Mirrors the Go backend's [alwaysExec] (callgraph-go/main.go): blocks are
    int-indexed; terminal blocks (no successors) and diverging terminators
    (noreturn heads) edge to one virtual exit; the set of blocks that
    post-dominate the entry — i.e. run on EVERY execution of the function — is
    computed by the standard iterative intersection fixpoint on the reversed
    CFG. A block outside that set is "conditional"; a block unreachable from
    the entry is dead code (calls there are recorded but demoted).

    No Typedtree dependency: the walker lowers expressions onto this graph. *)

type t = {
  mutable n_blocks : int;
  mutable succs : int list array;  (* successor lists, grown on demand *)
  mutable terminated : bool array;
      (* block ends in a diverging terminator: no fall-through may be added *)
}

let entry = 0

let create () =
  {n_blocks = 1; succs = Array.make 16 []; terminated = Array.make 16 false}

let ensure_capacity g =
  if g.n_blocks > Array.length g.succs then begin
    let cap = max 16 (2 * Array.length g.succs) in
    let s = Array.make cap [] in
    Array.blit g.succs 0 s 0 (Array.length g.succs) ;
    g.succs <- s ;
    let t = Array.make cap false in
    Array.blit g.terminated 0 t 0 (Array.length g.terminated) ;
    g.terminated <- t
  end

(** Allocate a fresh, empty block. *)
let new_block g =
  let b = g.n_blocks in
  g.n_blocks <- g.n_blocks + 1 ;
  ensure_capacity g ;
  b

(** Add an edge [a → b]. Ignored if [a] is terminated (a diverging terminator
    admits no fall-through successor; its virtual-exit / handler edges are
    added explicitly BEFORE termination is recorded). *)
let add_edge g a b = if not g.terminated.(a) then g.succs.(a) <- b :: g.succs.(a)

(** Mark [b] as ending in a diverging terminator (noreturn head). The block
    keeps whatever successors it already has (e.g. a handler-dispatch edge);
    [seal]-time it will also receive a virtual-exit edge. Subsequent
    [add_edge b _] calls are no-ops, so straight-line fall-through after the
    terminator lands in a NEW block with no incoming edge (entry-unreachable). *)
let terminate g b = g.terminated.(b) <- true

type verdict = {
  always : bool array;  (* block post-dominates entry → calls can be MUST *)
  reachable : bool array;  (* block reachable from entry *)
}

(** Compute post-dominance of the entry and entry-reachability.

    Terminal blocks (no successors) and terminated blocks flow to a virtual
    exit [n]. If NO block flows to the exit (e.g. [while true do () done] with
    no other path out), nothing is guaranteed to complete: [always] is all
    false (sound: everything demotes). *)
let solve g =
  let n = g.n_blocks in
  let exit = n in
  (* successor lists including virtual-exit edges *)
  let succ =
    Array.init n (fun i ->
        if g.terminated.(i) || g.succs.(i) = [] then exit :: g.succs.(i)
        else g.succs.(i))
  in
  let has_exit = Array.exists (fun l -> List.mem exit l) succ in
  let reachable = Array.make n false in
  (* entry-reachability: simple DFS over real successors *)
  let rec visit b =
    if b < n && not reachable.(b) then begin
      reachable.(b) <- true ;
      List.iter (fun s -> if s < n then visit s) g.succs.(b)
    end
  in
  visit entry ;
  if not has_exit then {always = Array.make n false; reachable}
  else begin
    (* pdom.(i) : bool array over 0..n — the set of nodes post-dominating i.
       Init: full set for real blocks, {exit} for the exit. Iterate
       pdom(i) = {i} ∪ ∩_{s ∈ succ(i)} pdom(s) to fixpoint.

       Post-dominance is a BACKWARD dataflow problem and blocks are allocated
       roughly in program order (successors after predecessors), so iterating
       in DESCENDING index order propagates facts from the exit in ~2 passes
       instead of one-block-per-pass (which made a 2000-branch function take
       minutes). One scratch row is reused across all blocks — no per-block
       allocation. *)
    let pdom = Array.init (n + 1) (fun _ -> Array.make (n + 1) true) in
    Array.fill pdom.(exit) 0 (n + 1) false ;
    pdom.(exit).(exit) <- true ;
    let next = Array.make (n + 1) true in
    let changed = ref true in
    while !changed do
      changed := false ;
      for i = n - 1 downto 0 do
        Array.fill next 0 (n + 1) true ;
        List.iter
          (fun s ->
            let ps = pdom.(s) in
            for k = 0 to n do
              next.(k) <- next.(k) && ps.(k)
            done)
          succ.(i) ;
        next.(i) <- true ;
        let row = pdom.(i) in
        let diff = ref false in
        for k = 0 to n do
          if next.(k) <> row.(k) then begin
            diff := true ;
            row.(k) <- next.(k)
          end
        done ;
        if !diff then changed := true
      done
    done ;
    (* a block runs on every execution iff it post-dominates the entry AND is
       reachable from the entry (an unreachable block trivially "post-dominates"
       nothing meaningful — it never runs). *)
    let always = Array.init n (fun j -> pdom.(entry).(j) && reachable.(j)) in
    {always; reachable}
  end

(** [always_exec v b] — does block [b] run on every execution? *)
let always_exec v b = b < Array.length v.always && v.always.(b)

(** [reachable v b] — is block [b] reachable from the entry? *)
let reachable v b = b < Array.length v.reachable && v.reachable.(b)
