#!/usr/bin/env bash
# selftest-decision-lint.sh — the Parsetree frontend's alias environment, and the SMT pipe.
#
# decision-lint canonicalises `let a = x in a && x` by resolving the alias, which is what lets it
# prove the second conjunct removable. On the Typedtree that is safe for free: Ident stamps make
# shadowing unrepresentable. On the PARSETREE there are only names, so an alias is valid exactly
# as long as every name involved still denotes what it denoted when the alias was recorded —
# BOTH the alias name and every name in its stored right-hand side.
#
# The direction matters: a missed alias costs recall, a leaked one produces a "delete this"
# verdict about code that does something else. So this asserts BOTH sides — every shadowing form
# must be silent, and the genuine aliases must still be found, or "fixing" a leak by switching
# resolution off would pass.
#
# Assertions are on the (kind, snippet) SET, not on line numbers: an earlier version of this
# script checked a line that a leak would not have reported anyway, so one of its five cases was
# vacuous.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
fails=0; note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
command -v python3 >/dev/null 2>&1 || { echo "selftest-decision-lint: python3 required" >&2; exit 2; }

BIN=""
for cand in "$HERE/_build/default/poc/decision-lint/bin/decision_lint.exe" \
            "$HERE/poc/decision-lint/_build/default/bin/decision_lint.exe"; do
  [ -x "$cand" ] && { BIN="$cand"; break; }
done
[ -n "$BIN" ] || { echo "selftest-decision-lint: decision_lint not built — run: dune build" >&2; exit 2; }

SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT

# ══════════════════════════════════════════════════════════════════════════════
# PART 1: alias scoping
# ══════════════════════════════════════════════════════════════════════════════
cat > "$SRC/shadow.ml" <<'ML'
(* ---- GENUINE aliases: nothing is rebound, so these MUST still be reported ---- *)
let genuine_and (p : bool) =
  let a = p in
  a && p

let genuine_rel (q : int) =
  let b = q in
  b > 0 && q > 0

(* ---- the alias NAME is rebound ---- *)
let relet (p : bool) (q : bool) =
  let a = p in
  let a = q in
  a && p

let arm (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  match q with
  | a -> a && p

let param (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  let k = fun a -> a && p in
  k q

(* An object binds `val a` for every method, and no pattern in the file shows it. *)
let obj (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  let o = object
    val a = q
    method m = a && p
  end in
  o#m

(* `open` can rebind a name to M.<name> with no pattern at all. *)
module M = struct let a = false end
let opened (p : bool) =
  let a = p in
  ignore a ;
  let open M in
  a && p

(* ---- the alias's RIGHT-HAND SIDE is rebound (the alias name is untouched) ---- *)
(* Chasing: x -> y -> 5 through the CURRENT env turns a live decision into `if 5 > 0`. *)
let chase (y : int) =
  let x = y in
  let y = 5 in
  ignore y ;
  x > 0

(* Merging: both atoms print to the key "y" and one reads as removable. *)
let merge (y : bool) (f : unit -> bool) =
  let x = y in
  let y = f () in
  x && y
ML

OUT="$("$BIN" "$SRC" 2>/dev/null)"
printf '%s' "$OUT" | python3 -c '
import json,sys
got=set()
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")=="finding": got.add((o["kind"], o["snippet"]))
want={("DEAD_SUBTERM","a && p"), ("DEAD_SUBTERM","(b > 0) && (q > 0)")}
missing = want - got
assert not missing, ("the genuine aliases were not resolved at all — every guard below would then be vacuous", sorted(missing))
extra = got - want
assert not extra, ("an alias survived a construct that rebound a name it depends on", sorted(extra))
' 2>/dev/null || note "an alias must not survive a rebinding of its name OR of a name in its RHS (and the genuine ones must still be found)"

# ══════════════════════════════════════════════════════════════════════════════
# PART 2: the SMT pipe, against stub solvers
#
# z3 answers a (check-sat) with one verdict, but it also writes `(error "…")` to STDOUT for a
# malformed assertion, and some builds print a banner. Taking literally the next line reported
# the error as unknown and left the real verdict buffered, where it became the answer to the
# NEXT query — every later result shifted by one, silently, with no way to notice from outside.
#
# The commit that fixed this claimed verification against a stub solver. That stub was not in
# the tree, so the claim was a commit message rather than an artefact. Here it is.
# ══════════════════════════════════════════════════════════════════════════════
mkdir -p "$SRC/rel"
cat > "$SRC/rel/rel.ml" <<'ML'
(* Relational atoms the enumeration tier cannot settle, so the SMT tier is actually reached. *)
let a (x : int) = if x > 0 && x > 1 then 1 else 2
let b (x : int) (y : int) = if x > y && y > x then 1 else 2
let c (x : int) = if x >= 3 && x >= 1 then 1 else 2
ML

STUB="$SRC/stub"; mkdir -p "$STUB"

# (1) NOISY: a banner at startup, then `(error …)` before every verdict. Every answer is `sat`,
#     i.e. "satisfiable" — which proves nothing, so a correct reader emits no SMT finding at all.
#     A desynced reader attaches verdicts to the wrong queries and can manufacture one.
cat > "$STUB/z3" <<'SH'
#!/usr/bin/env bash
echo "Z3 version 4.99 - synthetic stub"
while IFS= read -r line; do
  case "$line" in
    *"(check-sat)"*) echo '(error "line 1: synthetic noise")'; echo "sat";;
  esac
done
SH
chmod +x "$STUB/z3"
NOISY="$(PATH="$STUB:$PATH" timeout 60 "$BIN" "$SRC/rel" 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || note "a solver that prefixes every verdict with a banner and an (error …) line must not hang or crash the run (rc=$rc)"
printf '%s' "$NOISY" | python3 -c '
import json,sys
solver=None; smt_findings=[]
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")=="smt": solver=o.get("solver")
    if o.get("type")=="finding" and o["kind"].startswith("SMT_"): smt_findings.append(o)
assert solver=="z3", ("the probe must skip the banner and accept the solver", solver)
assert not smt_findings, ("every stub answer was `sat`, which proves nothing — an SMT finding means reads desynced", smt_findings)
' 2>/dev/null || note "an (error …) line must not shift the verdict stream onto the following queries"

# (2) MUTE: answers the probe, then goes silent. The fuel in the reader bounds the LINES read,
#     not the waiting, so without a deadline on the read this hangs the analysis forever.
cat > "$STUB/z3" <<'SH'
#!/usr/bin/env bash
first=1
while IFS= read -r line; do
  case "$line" in
    *"(check-sat)"*)
      if [ $first -eq 1 ]; then echo "sat"; first=0; fi ;;   # probe only; then never answer
  esac
done
SH
chmod +x "$STUB/z3"
PATH="$STUB:$PATH" timeout 60 "$BIN" "$SRC/rel" >/dev/null 2>&1
mrc=$?
[ $mrc -ne 124 ] || note "a solver that answers the probe then goes silent must not hang the analysis (no deadline on the read)"

# (3) ABSENT: open_process spawns a shell, which succeeds even with no z3 — the solver must be
#     reported absent, not present-and-silently-dead.
TIMEOUT_BIN="$(command -v timeout)"
mkdir -p "$SRC/empty"
ABS="$(env -i PATH="$SRC/empty" HOME="$HOME" "$TIMEOUT_BIN" 60 "$BIN" "$SRC/rel" 2>/dev/null)"; arc=$?
[ $arc -eq 0 ] || note "a missing z3 must degrade to UNKNOWN, not kill the process (rc=$arc)"
printf '%s' "$ABS" | python3 -c '
import json,sys
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    try: o=json.loads(l)
    except Exception: continue
    if o.get("type")=="smt":
        assert o.get("solver")=="absent", o
        break
else:
    raise AssertionError("no smt census line")
' 2>/dev/null || note "with no z3 on PATH the run must report solver=absent"

if [ "$fails" -eq 0 ]; then echo "selftest-decision-lint: PASS"; else echo "selftest-decision-lint: $fails FAILURE(S)"; exit 1; fi
