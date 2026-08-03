(* Known-slop fixture: every case below MUST be detected. *)
let g x = x + 1
let h x = x - 1

(* 1. rung-0 duplicate conjunct *)
let f1 a b = if a && b && a then 1 else 2

(* 2. rung-0 absorption: a && (a || b) === a *)
let f2 a b = if a && (a || b) then 1 else 2

(* 3. rung-2 double negation *)
let f3 a = if a && not (not a) then 1 else 2

(* 4. rung-2 `= true` normalisation *)
let f4 a = if a && a = true then 1 else 2

(* 5. tautology *)
let f5 a = if a || not a then 1 else 2

(* 6. contradiction *)
let f6 a = if a && not a then 1 else 2

(* 7. rung-3 same-subject comparison: x > 5 implies x > 0 *)
let f7 x = if x > 5 && x > 0 then g x else h x

(* 8. rung-3 contradictory bounds *)
let f8 x = if x < 3 && x > 10 then g x else h x

(* 9. path-sensitive: inner guard implied by outer *)
let f9 x = if x > 10 then (if x > 2 then g x else h x) else 0

(* 10. path-sensitive: inner guard excluded by outer *)
let f10 x = if x > 10 then (if x < 4 then g x else h x) else 0

(* 11. identical arms *)
let f11 a x = if a then g x else g x

(* 12. TYPEDTREE ONLY. Arm 2's guard is subsumed by arm 1's, but each arm binds
   its OWN `m`. Relating them by NAME is the unsoundness that made the
   compare-chain idiom (ok20) report a live branch dead on a 3.3M-line corpus.
   Relating them by SCRUTINEE IDENTITY is sound: every arm of a match filters
   the same scrutinee, so an arm whose pattern is a bare variable binds a name
   that IS the scrutinee. The Typedtree frontend records that alias and detects
   this; the Parsetree frontend has no stamps, cannot establish the identity,
   and correctly stays silent. *)
let f12 n = match n with m when m > 5 -> g m | m when m > 100 -> h m | m -> m

(* 12b. descending cascade is NOT slop and must not fire *)
let ok7 n = match n with m when m > 100 -> g m | m when m > 5 -> h m | m -> m

(* --- these must NOT fire (true negatives) --- *)
let ok1 a b = if a && b then 1 else 2
let ok2 x = if x > 5 && x < 100 then g x else h x
let ok3 () = while true do () done            (* idiom, not a defect *)
let ok4 r = if !r && !r then 1 else 2          (* unstable: deref, never merge *)
let ok5 () = if g 0 > 0 && g 0 > 0 then 1 else 2 (* unstable: unlisted call *)
let ok6 x = if x > 5 then (if x > 10 then 1 else 2) else 0 (* genuinely refines *)

(* --- rung 1: alias / copy propagation --- *)

(* 13. the canonical LLM shape: rebind then test both *)
let f13 x = let a = x in if a && x then 1 else 2

(* 14. alias through a comparison *)
let f14 n = let limit = n in if limit > 5 && n > 5 then 1 else 2

(* 15. alias chain *)
let f15 x = let a = x in let b = a in if b && x then 1 else 2

(* --- must NOT fire --- *)
let ok8 x y = let a = x in if a && y then 1 else 2   (* different values *)
let ok9 r = let a = !r in if a && !r then 1 else 2   (* unstable RHS: no alias *)

(* --- rung 4 (SMT): coupling no canonicalisation rung can see --------------- *)

(* 16. same pair, different operators — two distinct syntactic atoms *)
let f16 x y = if x > y && y > x then 1 else 2

(* 17. equality vs disequality on the same closed literal *)
let f17 s = if s = "alpha" && s <> "alpha" then 1 else 2

(* 18. two different closed literals *)
let f18 s = if s = "alpha" && s = "beta" then 1 else 2

(* 19. constructors *)
let f19 v = if v = None && v = Some 3 then 1 else 2

(* 20. a length is never negative *)
let f20 s = if String.length s >= 0 && String.length s > 3 then 1 else 2

(* 21. cross-subject path condition *)
let f21 x y = if x > y then (if y > x then g x else h x) else 0

(* 22. arithmetic coupling that survives wrapping *)
let f22 x = if x - x > 0 then 1 else 2

(* --- must NOT fire --- *)
let ok10 x y = if x > 5 && y > 3 then 1 else 2
(* Neither of these is decidable under OCaml's ACTUAL semantics: int wraps at 63
   bits. `x + 1 > x` is false at max_int, and `x + 1 <= x - 1` is TRUE at max_int
   (x+1 wraps to min_int). An LIA encoding would wrongly prove both dead. The
   BitVec 63 encoding gets both right, which is the whole reason §6.3 forbids
   LIA for OCaml ints. *)
let ok11 x = if x + 1 > x then 1 else 2
let ok11b x = if x + 1 <= x - 1 then 1 else 2
let ok12 s t = if s = "alpha" && t = "beta" then 1 else 2

(* --- rung 2: ordering comparisons with no literal --- *)

(* 23. same pair, mirrored operators — one atom after orientation *)
let f23 x y = if x < y && y > x then 1 else 2

(* 24. mirrored, non-strict *)
let f24 x y = if x <= y && y >= x then 1 else 2

(* --- rung 3: char intervals --- *)

(* 25. a char range subsumes a narrower one *)
let f25 c = if c >= 'a' && c >= 'c' && c <= 'z' then 1 else 2

(* 26. contradictory char bounds *)
let f26 c = if c < 'a' && c > 'z' then 1 else 2

(* --- allowlist --- *)

(* 27. String.trim is pure and first-order: the two atoms merge *)
let f27 s = if String.trim s = "" && String.trim s = "" then 1 else 2

(* --- must NOT fire --- *)
let ok13 x y z = if x < y && y < z then 1 else 2      (* genuine chain *)
let ok14 c = if c >= 'a' && c <= 'z' then 1 else 2    (* genuine range *)
let ok15 f l = if List.exists f l && List.exists f l then 1 else 2 (* higher-order: f may be impure *)

(* --- floats: NaN breaks the identities (§6.3). None of these may fire. --- *)

(* `x <> x` IS the idiomatic NaN test — true when x is NaN, so not constant *)
let ok16 (x : float) = if x <> x then 1 else 2
let ok17 (x : float) (y : float) = if x <> x then 0 else if y <> y then 1 else 2
(* is_finite: `x = x` excludes NaN and is load-bearing *)
let ok18 (x : float) = x = x && x <> infinity && x <> neg_infinity
(* the NaN-tolerant equality idiom *)
let ok19 (a : float) (b : float) = a = b || (a <> a && b <> b)

(* --- guard scoping: a rebound name invalidates guards mentioning it ------- *)
(* The compare-chain idiom. Each `c` is a NEW binding, so the outer
   `not (c <> 0)` says nothing about the inner `c`. Must NOT fire. *)
let ok20 a b x y =
  let c = compare a b in
  if c <> 0 then c
  else
    let c = compare x y in
    if c <> 0 then c else 0

(* Same shape through a function parameter rebinding the name. *)
let ok21 n =
  if n = 0 then 0
  else (fun n -> if n = 0 then 1 else 2) (n - 1)
