# QA Scope — arch-serve

**Date:** 2026-06-25
**Status:** VALIDATED

## Quality Gates

```bash
# Gate 1: Build
opam exec -- dune build

# Gate 2: Full test suite (must not regress)
opam exec -- dune test

# Gate 3: Smoke tests
BIN="./_build/default/bin/arch_serve/arch_serve.exe"

# Build self-index DB first if not present
[ -f /tmp/self.db ] || opam exec -- ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe \
  --build-dir=_build/default/lib/arch_index \
  --db-path=/tmp/self.db \
  --schema-path=architecture-schema.sql

opam exec -- "$BIN" /tmp/self.db --port 7372 &
PID=$!
sleep 1

# CHECK-1: root serves HTML with arch-serve in title
curl -sf http://localhost:7372/ | grep -q '<title>.*arch-serve' && echo "CHECK-1 OK" || echo "CHECK-1 FAIL"

# CHECK-3: /api/modules has_mli is boolean
curl -sf http://localhost:7372/api/modules | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d, 'empty response'
assert all(isinstance(m['has_mli'],bool) for m in d), 'has_mli not bool'
print('CHECK-3 OK')
"

# CHECK-4: /api/functions filter works, booleans correct
curl -sf 'http://localhost:7372/api/functions?exposed=1&min_score=0' | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert all(m['exposed']==True for m in d), 'exposed filter broken'
assert all(isinstance(m['has_pre'],bool) for m in d), 'has_pre not bool'
print('CHECK-4 OK')
"

# CHECK-5: /api/graph/neighborhood returns correct schema
curl -sf 'http://localhost:7372/api/graph/neighborhood?name=parse&depth=1' | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert 'nodes' in d and 'edges' in d and 'truncated' in d, 'schema wrong'
if d['nodes']:
    n=d['nodes'][0]; assert all(k in n for k in ['id','name','module_id','exposed','comment_quality_score']), 'node schema'
if d['edges']:
    e=d['edges'][0]; assert all(k in e for k in ['caller_id','callee_id','kind']), 'edge schema'
print('CHECK-5 OK')
"

# CHECK-6/7: /api/reaches returns correct shape
curl -sf 'http://localhost:7372/api/reaches?from=parse&to=find_tag_positions' | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert d['result'] in ('PATH_EXISTS','NO_MUST_PATH'), 'bad result'
assert isinstance(d['path'],list), 'path not list'
if d['result']=='PATH_EXISTS':
    assert all(isinstance(x,int) for x in d['path']), 'path not int IDs'
print('CHECK-6/7 OK:', d['result'])
"

# CHECK-7: unknown function → 404
STATUS=$(curl -s -o /dev/null -w "%{http_code}" 'http://localhost:7372/api/reaches?from=nonexistent_fn_xyz&to=parse')
[ "$STATUS" = "404" ] && echo "CHECK-7 OK: 404" || echo "CHECK-7 FAIL: $STATUS"

# CHECK-8: SIGINT → exit 0
kill -INT $PID; wait $PID 2>/dev/null; CODE=$?
[ "$CODE" = "0" ] && echo "CHECK-8 OK: exit 0" || echo "CHECK-8 FAIL: exit $CODE"
```

## Behaviors to Validate Manually in Browser

After starting the server against `/tmp/self.db`:

1. **Function table loads** — sidebar shows all functions with dot/name/score/flags columns
2. **Module filter** — select a module → table filters to that module's functions
3. **Exposed toggle** — check → only exposed functions shown
4. **Score slider** — drag to 30 → only functions with score ≥ 30 shown
5. **Row click → neighborhood graph** — click any function row → URL becomes `#/n/<name>?depth=2`, force graph renders
6. **Focus node** — selected function has accent halo, pinned near center
7. **Depth controls** — click 1/3 → graph updates without full reset (existing node positions preserved)
8. **Node single-click** — non-focus node dims everything except its neighbors
9. **Node double-click** — re-centers graph on that node (URL updates)
10. **Details panel** — shows signature, score bar, has_pre/has_post flags, callees with kind glyphs
11. **Edge styles** — MUST edges solid gray-blue, MAY dashed amber, MAY_TOP dotted violet+⊤
12. **Module view** — switch to Module tab → select a module → layered DAG renders
13. **Layered DAG** — functions at discrete horizontal layers, top-to-bottom
14. **Back-edges** — if any exist in the module, shown as curved right-side arcs
15. **Force↔layered toggle** — switches layout without re-fetching
16. **Path query** — in details panel, "Reaches…" → pick a target → marching-ants animate on path
17. **NO_MUST_PATH** — for an unreachable function → panel shows "cannot definitely reach" (NOT "no path exists")
18. **`/` shortcut** — focuses search box
19. **SIGINT** — Ctrl-C stops server cleanly

## Regression Check

```bash
# Existing test suite must still pass (no regression from new code)
opam exec -- dune test
```
