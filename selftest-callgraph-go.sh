#!/usr/bin/env bash
# selftest-callgraph-go.sh — PR-C end-to-end: Go Tier-1 CHA producer → arch-load → arch-query.
# Builds arch-callgraph-go from source, creates a controlled Go module with MUST/MAY_ENUMERATED/
# MAY_TOP call sites, and asserts all three soundness verdicts (REACHABLE/UNREACHABLE/UNKNOWN).
# No pre-installed binary required; no network after the initial go.sum is written.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOAD="$HERE/arch-load"; Q="$HERE/arch-query"
fails=0
note() { echo "FAIL: $*" >&2; fails=$((fails+1)); }
say()  { "$Q" "$@" 2>&1; }
command -v go     >/dev/null 2>&1 || { echo "selftest-callgraph-go: go required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "selftest-callgraph-go: python3 required" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "selftest-callgraph-go: sqlite3 required" >&2; exit 2; }

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ---------- build the producer binary ----------
BIN="$TMPDIR_ROOT/arch-callgraph-go"
cd "$HERE/callgraph-go" && go build -o "$BIN" . 2>&1 | grep -v '^$' || true
[ -x "$BIN" ] || { echo "selftest-callgraph-go: failed to build arch-callgraph-go" >&2; exit 2; }

# ---------- controlled Go module ----------
# Three entry points:
#   cleanEntry: direct() [MUST] + useInterface() [MUST] → interface d.Do() [MAY_ENUMERATED]
#               No MAY_TOP anywhere in the reachable subgraph → UNREACHABLE for island.
#   dirtyEntry: dirty() [MUST] → reflect.Value.Call [MAY_TOP → *TOP*] → UNKNOWN for island.
#   island:     completely disconnected (never called).
MOD="$TMPDIR_ROOT/testmod"
mkdir -p "$MOD"
cat > "$MOD/go.mod" <<'GOMOD'
module testcg
go 1.21
GOMOD
cat > "$MOD/main.go" <<'GOCODE'
package main

import "reflect"

// --- interface: MAY_ENUMERATED call sites ---
type Doer interface{ Do() int }
type ImplA struct{}
type ImplB struct{}
func (ImplA) Do() int { return 1 }
func (ImplB) Do() int { return 2 }

// --- direct: MUST call site ---
func direct() int { return 42 }

// --- island: never called (target for UNREACHABLE) ---
func island() int { return 99 }

// --- useInterface: calls d.Do() — MAY_ENUMERATED (CHA enumerates ImplA.Do + ImplB.Do) ---
func useInterface(d Doer) int { return d.Do() }

// --- dirty: calls reflect.Value.Call — soundiness hole → MAY_TOP anchor ---
func dirty(v interface{}) {
	reflect.ValueOf(v).Call(nil)
}

// --- gated: island is called ONLY inside an if-branch → dominance demotes the
//     otherwise-uniquely-resolved MUST edge to MAY_TOP (conditional execution).
//     So reaches gatedEntry island = no MUST path, and unreachable = UNKNOWN
//     (a MAY_TOP frontier), NOT REACHABLE and NOT UNREACHABLE. ---
func gatedEntry(b bool) int {
	if b {
		return island()
	}
	return direct()
}

// --- entry points ---
func cleanEntry() int   { return direct() + useInterface(ImplA{}) }
func dirtyEntry()       { dirty(nil) }

func main() { cleanEntry() }
GOCODE

# ---------- produce + load ----------
DB="$TMPDIR_ROOT/test.db"
"$BIN" "$MOD/..." 2>/tmp/cggo-stderr.txt | "$LOAD" "$DB" 2>/tmp/load-stderr.txt
load_rc=$?
[ "$load_rc" -eq 0 ] || { cat /tmp/cggo-stderr.txt /tmp/load-stderr.txt >&2; note "pipeline failed (exit $load_rc)"; }
[ -f "$DB" ] || { note "DB not produced"; exit 1; }

sqlite3 "$DB" "SELECT value FROM comment_db_meta WHERE key='callgraph_contract';" \
  | grep -q '^v1$' || note "DB missing callgraph_contract=v1"

# ---------- discover function names (module is 'testcg', short pkg 'testcg') ----------
# funcName() produces: testcg.direct, testcg.island, testcg.cleanEntry, testcg.dirtyEntry,
# testcg.(ImplA).Do, testcg.(ImplB).Do, testcg.useInterface, testcg.dirty
fn_direct=$(sqlite3 "$DB" "SELECT name FROM functions WHERE name LIKE '%direct%' AND name NOT LIKE '%dirty%' LIMIT 1;")
fn_island=$(sqlite3 "$DB" "SELECT name FROM functions WHERE name LIKE '%island%' LIMIT 1;")
fn_clean=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%cleanEntry%' LIMIT 1;")
fn_dirty_e=$(sqlite3 "$DB" "SELECT name FROM functions WHERE name LIKE '%dirtyEntry%' LIMIT 1;")
fn_implA=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%(ImplA).Do%' LIMIT 1;")
fn_gated=$(sqlite3 "$DB"  "SELECT name FROM functions WHERE name LIKE '%gatedEntry%' LIMIT 1;")

[ -n "$fn_direct" ] || note "function 'direct' not found in DB"
[ -n "$fn_island" ] || note "function 'island' not found in DB"
[ -n "$fn_clean"  ] || note "function 'cleanEntry' not found in DB"
[ -n "$fn_dirty_e" ] || note "function 'dirtyEntry' not found in DB"
[ -n "$fn_implA"  ] || note "function '(ImplA).Do' not found in DB"
[ -n "$fn_gated"  ] || note "function 'gatedEntry' not found in DB"

# bail early if names missing — subsequent tests would be vacuously wrong
[ "$fails" -gt 0 ] && { echo "selftest-callgraph-go: FAIL (function discovery, $fails failures)"; exit 1; }

# ---------- reaches: MUST-only under-approx ----------
say "$DB" reaches "$fn_clean" "$fn_direct" \
  | grep -q 'PATH EXISTS (must-reach)' || note "reaches $fn_clean $fn_direct should be a MUST path"
# cleanEntry→useInterface→d.Do() is MAY_ENUMERATED, NOT a MUST path
say "$DB" reaches "$fn_clean" "$fn_implA" \
  | grep -q 'no MUST path' || note "reaches $fn_clean $fn_implA should be no MUST path (via MAY_ENUMERATED)"

# ---------- unreachable: sound over-approx ----------
# cleanEntry's closure has no MAY_TOP → island is UNREACHABLE
say "$DB" unreachable "$fn_clean" "$fn_island" \
  | grep -q 'UNREACHABLE:' || note "unreachable $fn_clean $fn_island should be UNREACHABLE"
# cleanEntry reaches ImplA.Do via MAY_ENUMERATED → REACHABLE
say "$DB" unreachable "$fn_clean" "$fn_implA" \
  | grep -q 'REACHABLE (may-reach)' || note "unreachable $fn_clean $fn_implA should be REACHABLE (MAY_ENUMERATED)"
# dirtyEntry reaches a MAY_TOP (*TOP* via reflect.Value.Call) → UNKNOWN for island
say "$DB" unreachable "$fn_dirty_e" "$fn_island" \
  | grep -q 'UNKNOWN:' || note "unreachable $fn_dirty_e $fn_island should be UNKNOWN (MAY_TOP reachable)"
# Safety: island must never be UNREACHABLE from dirtyEntry (a ⊤ is reachable)
say "$DB" unreachable "$fn_dirty_e" "$fn_island" \
  | grep -q 'UNREACHABLE:' && note "unreachable $fn_dirty_e $fn_island must NOT be UNREACHABLE (has reachable MAY_TOP)"

# ---------- escapes: MAY_TOP frontier ----------
# dirtyEntry should escape (reach *TOP*)
say "$DB" escapes "$fn_dirty_e" \
  | grep -q '.' || note "escapes $fn_dirty_e should list at least one escaping function"
# cleanEntry should NOT escape (no MAY_TOP in its closure)
say "$DB" escapes "$fn_clean" 2>&1 \
  | grep -qE 'no escaping|0 functions' || {
    esc_out=$(say "$DB" escapes "$fn_clean" 2>&1)
    # accept empty output OR explicit "no escaping" message
    [ -z "$(echo "$esc_out" | grep -v '^$')" ] || \
      echo "$esc_out" | grep -q 'no escaping' || \
      note "escapes $fn_clean should have no MAY_TOP in closure (got: $esc_out)"
  }

# ---------- dominance: a conditional (if-branch) static call is NOT MUST ----------
# island is uniquely resolved but only called inside `if b`, so it must never be
# a MUST edge and never dropped. (Its demoted KIND depends on DOM_ENUM below.)
say "$DB" reaches "$fn_gated" "$fn_island" \
  | grep -q 'no MUST path' || note "reaches $fn_gated $fn_island should be no MUST path (conditional call, dominance-demoted)"
if [ "${DOM_ENUM:-1}" != 1 ]; then
  # Pre-US-4: demotion target is MAY_TOP → verdict is UNKNOWN.
  say "$DB" unreachable "$fn_gated" "$fn_island" \
    | grep -q 'UNKNOWN:' || note "unreachable $fn_gated $fn_island should be UNKNOWN (conditional call → MAY_TOP frontier)"
fi
say "$DB" unreachable "$fn_gated" "$fn_island" \
  | grep -q 'UNREACHABLE:' && note "unreachable $fn_gated $fn_island must NOT be UNREACHABLE (conditional call is still recorded)"
# Direct call in gatedEntry's other branch is ALSO conditional → no MUST path either.
say "$DB" reaches "$fn_gated" "$fn_direct" \
  | grep -q 'no MUST path' || note "reaches $fn_gated $fn_direct should be no MUST path (else-branch is conditional)"

# ---------- enumerated demotion (cfg-postdom-dominance US-4) ----------
# A conditional call with a uniquely-resolved static callee is MAY_ENUMERATED
# (candidate set of one), not MAY_TOP — so unreachable becomes decidable.
# DOM_ENUM defaults to 1 since the Go backend landed enumerated demotion
# (set DOM_ENUM=0 to test a pre-US-4 binary).
if [ "${DOM_ENUM:-1}" = 1 ]; then
  gated_kind=$(sqlite3 "$DB" "SELECT COALESCE(MAX(kind),'MISSING') FROM calls WHERE caller_name LIKE '%gatedEntry%' AND callee_name LIKE '%island%';")
  [ "$gated_kind" = "MAY_ENUMERATED" ] || note "gatedEntry→island should be MAY_ENUMERATED (enumerated demotion), got $gated_kind"
  say "$DB" unreachable "$fn_gated" "$fn_island" \
    | grep -q 'REACHABLE (may-reach)' || note "unreachable $fn_gated $fn_island should be REACHABLE (enumerated conditional callee)"
else
  echo "  (DOM_ENUM=0: enumerated-demotion assertions skipped — pre-US-4 behavior)"
fi

# ---------- cgo wrapper calls are ⊤ anchors (never MAY_ENUMERATED/MUST) ----------
# cgo synthesizes _Cfunc_* wrappers INSIDE the user's package; a call through one
# crosses into C (which may call back into arbitrary exported Go), so it must be
# reclassified to *TOP*/MAY_TOP — otherwise `unreachable` can claim UNREACHABLE
# across a C callback. Skipped when no C toolchain / CGO disabled.
if [ "$(go env CGO_ENABLED 2>/dev/null)" = 1 ] && command -v cc >/dev/null 2>&1; then
  CGOMOD="$TMPDIR_ROOT/cgomod"
  mkdir -p "$CGOMOD"
  printf 'module cgocb\ngo 1.21\n' > "$CGOMOD/go.mod"
  cat > "$CGOMOD/main.go" <<'GOCGO'
package main

/*
extern void goCallback();
static void call_go() { goCallback(); }
*/
import "C"

func island() int { return 1 }

//export goCallback
func goCallback() { island() }

func cgoBranch(b bool) {
	if b {
		C.call_go()
	}
}

func main() { cgoBranch(true) }
GOCGO
  cgo_kind=$("$BIN" "$CGOMOD" 2>/dev/null | python3 -c "
import sys,json
for line in sys.stdin:
    r=json.loads(line)
    if r.get('type')=='call' and 'cgoBranch' in r.get('caller_name',''):
        print(r['kind']); break
")
  [ "$cgo_kind" = "MAY_TOP" ] || note "cgoBranch's cgo-wrapper call should be MAY_TOP (⊤ anchor), got '${cgo_kind:-none}'"
else
  echo "  (cgo assertion skipped: CGO disabled or no C toolchain)"
fi

# ---------- edge-kind integrity: no un-kinded edges in the produced DB ----------
bad=$(sqlite3 "$DB" "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN ('MUST','MAY_ENUMERATED','MAY_TOP');")
[ "$bad" -eq 0 ] || note "DB has $bad call edges with missing/invalid kind — loader enforcement failed"

# ---------- non-zero function count ----------
nfn=$(sqlite3 "$DB" "SELECT count(*) FROM functions;")
[ "$nfn" -gt 0 ] || note "DB has 0 functions — producer emitted nothing"

if [ "$fails" -eq 0 ]; then
  echo "arch-index callgraph-go selftest: PASS"
  exit 0
else
  echo "arch-index callgraph-go selftest: FAIL ($fails)"
  exit 1
fi
