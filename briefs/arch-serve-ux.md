# arch-serve UI/UX Design

**Date:** 2026-06-25
**Status:** DRAFT — design spec for implementer
**Companion to:** `briefs/arch-serve-intake.md`
**Audience:** OCaml engineers exploring their own call graph. Single-user, localhost, dark theme, no build step.

---

## 0. Design principles (the opinionated frame)

These drive every decision below. When two options tie, the one that better serves these wins.

1. **The graph is the product; everything else is navigation.** The neighborhood canvas gets the most pixels and the most polish. Sidebar and panels are instruments for steering it.
2. **Soundness is a feature, not a footnote.** This index distinguishes `MUST` / `MAY_ENUMERATED` / `MAY_TOP` edges precisely *because* it is sound. The UI must make that distinction legible at a glance, not bury it in a tooltip. A developer should be able to look at a graph and answer "could this reach `exec`?" with confidence.
3. **No surprises, no spinners-of-doom.** Target scale (≤ few thousand functions, ≤ 10k edges) is small enough that every query returns in well under a second. We never paginate the graph render; we *cap* it and tell the user we capped it.
4. **Keyboard-first, mouse-complete.** This is a dev tool. Power users will live on `/` (search) and `j/k` (table nav). But nothing requires the keyboard.
5. **State lives in the URL.** Every view is a deep link: `#/n/find_tag_positions?depth=2`. Reload-safe, shareable in a bug report, back-button works. This is cheap with the hash router and pays for itself the first time someone pastes a link into a PR.

---

## 1. Layout architecture

A three-region shell: fixed top **header bar**, left **sidebar** (function table + filters), and the **main stage** (graph canvas or module view), with a **details panel** that slides in from the right over the stage.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  arch-serve   [ ⌕ search function…            ]   ◧ Neighborhood ◧ Module   ⓘ │  ← header (48px)
├────────────────────┬─────────────────────────────────────────────────────────┤
│ FILTERS            │                                                          │
│  Module  [all  ▾]  │                                                          │
│  ☑ exposed only    │                  M A I N   S T A G E                     │
│  score ≥ [▓▓▓░░] 30│                  (D3 force canvas /                      │
│                    │                   module DAG)                            │
│ FUNCTIONS (144)    │                                          ┌──────────────┐│
│ ┌────────────────┐ │                                          │ DETAILS      ││
│ │● find_tag_pos… │ │            ◉───MUST──▶◉                   │ find_tag_…   ││
│ │  exec_query    │ │           ╱         ╲                    │ sig: string→ ││
│ │● parse_comment │ │     ◉◀┄┄MAY_TOP┄┄┄◉   ◉                  │ ◆ exposed    ││
│ │  …             │ │                                          │ score 58/75  ││
│ └────────────────┘ │  ┌─ legend ──────────────┐               │ [reaches…]   ││
│  ◀ 1 2 3 … ▶       │  │ ━ MUST  ┅ ENUM  ⌁ TOP │               └──────────────┘│
├────────────────────┴──┴───────────────────────┴─────────────────────────────┤
│  18 modules · 144 fns · 2376 calls · neighborhood: 24 nodes / 41 edges shown   │  ← statusbar (24px)
└────────────────────────────────────────────────────────────────────────────────┘
```

Concrete dimensions (judgment call — chosen for 1440px laptop, the realistic target):

- Header: `48px` tall, full width, `position: sticky`.
- Sidebar: `320px` fixed width, full height between header and statusbar, independently scrollable. Collapsible to `0` with `[` (toggle) to reclaim canvas for big graphs.
- Main stage: fills remaining width. The SVG/canvas is `100%`/`100%` of it.
- Details panel: `360px`, `position: absolute; right: 0`, slides in over the stage (does not reflow the canvas — reflowing would restart the force sim, which is jarring). Dismissable with `Esc` or a `×`.
- Statusbar: `24px`, full width, monospace, muted. Shows global counts + current render counts. This is where "capped at 400 nodes" warnings live.

Rationale for panel-over-stage rather than push-stage: a force simulation that resizes mid-flight re-runs layout and the graph "jumps." Overlaying keeps the sim stable. We accept that the panel occludes the right ~25% of the canvas; the user can pan.

---

## 2. Neighborhood view (primary)

### 2.1 Entering a starting function

Three entry points, all converging on the same action `focus(name)`:

1. **Header search box** (primary). Always visible. Focused by `/` from anywhere. As-you-type autocomplete against an in-memory function list.
   - On first load, `app.js` fetches `GET /api/functions` once (full list, ~144 rows here, a few thousand at target — trivially cacheable client-side) and builds a flat array `[{id,name,module_id,signature,exposed,score}]`. Autocomplete filters this in JS; **no per-keystroke network call.**
   - Match strategy: case-insensitive substring on `name`, ranked by (a) prefix match first, (b) shorter name, (c) exposed first. Show up to 10 results in a dropdown; each row shows `name` left, dimmed `module basename` right.
   - `Enter` or click → `focus(name)` → navigate to `#/n/<name>?depth=<current>`.
2. **Sidebar table row click** → `focus(name)` (same path).
3. **Deep link** — loading `#/n/find_tag_positions?depth=2` directly focuses it. This is the shareable case.

`focus(name)` calls `GET /api/graph/neighborhood?name=X&depth=N`, receives `{nodes, edges}`, and (re)builds the simulation.

### 2.2 Node visual encoding

Each node carries three independent signals. We map them to three independent visual channels so they never collide:

| Signal | Channel | Encoding |
|---|---|---|
| **Module membership** | **Hue** | Categorical color from the module palette (§7). One color per module, assigned stably by `module_id`. |
| **`exposed` (public API)** | **Border** | Exposed → bright `2px` ring in the node's hue lightened; internal → no ring, flat fill. Public API "pops." |
| **`comment_quality_score` (0–75)** | **Size** | Radius `r = 6 + (score/75)*8` → range `6–14px`. Well-documented functions are visibly larger. Null score → minimum radius + a subtle dashed outline meaning "unscored." |

The **focused** node gets a distinct treatment regardless of the above: a `3px` accent-colored halo (`--accent`, §7) and it's pinned to canvas center on first layout (`fx/fy` set, released after the user drags it). This guarantees the user never loses "where am I."

Node label: function `name` in monospace, `11px`, rendered as an SVG `<text>` *below* the node, shown always for the focused node and its direct neighbors, and on hover for everything else (label clutter is the #1 force-graph readability killer — we hide by default beyond hop-1).

Shape: **all nodes are circles.** I considered squares-for-modules or diamonds-for-exposed; rejected — shape is a weak channel and we already have border for exposed. Keep one shape, vary the three channels above. (Judgment call: consistency over cleverness.)

### 2.3 Edge visual encoding — the soundness channel

Edge `kind` is the most important non-structural signal. It gets **both stroke style and color** (redundant encoding, deliberately, because it's load-bearing):

| `kind` | Meaning | Stroke | Color | Arrowhead |
|---|---|---|---|---|
| `MUST` | Definite call — will happen on some path | solid, `1.5px` | `--edge-must` (neutral light gray-blue) | solid filled |
| `MAY_ENUMERATED` | Possible call, target known (e.g. through a known set of variants/handlers) | dashed `4 3` | `--edge-may` (amber) | open/hollow |
| `MAY_TOP` | Possible call, **target unknown at compile time** (higher-order / dynamic dispatch the analyzer couldn't pin down) | dotted `1 4` | `--edge-top` (magenta/violet) | hollow + small ⊤ glyph at midpoint |

The `MAY_TOP` styling is intentionally the most visually distinct — see §6 for the framing. Arrowheads are SVG `marker` defs; three markers (one per kind) so color matches the line.

Directionality: arrow points **caller → callee** (the call flows that way). Curved edges (quadratic bezier) so reciprocal call pairs (A↔B) don't overdraw into one line — offset them symmetrically.

### 2.4 Depth control

A segmented control in the header (or floating top-left of the canvas): `depth: 1 · 2 · 3`. Default `2` (judgment call: 1 is usually too sparse to be interesting, 3 can explode on hub functions). Changing depth re-queries `?depth=N` and re-lays-out, animating new nodes in.

Beyond the global depth, **per-node expansion**: double-click any non-focused node to make *it* the new focus (re-query centered there). This is the core navigation loop — walk the graph node by node. A breadcrumb of recently-focused functions lives in the header (`parse ▸ tokenize ▸ scan`) so back-tracking is one click; it mirrors the hash history.

Collapse: a node that was expanded shows a small filled dot badge; clicking the badge prunes its sub-tree from view (client-side filter, no re-query) for decluttering hub nodes.

### 2.5 Node click → details

- **Single click**: select. Opens/updates the details panel (§5), highlights the node (halo), and dims everything not adjacent to it (lower opacity on non-neighbor nodes/edges → instant "what does this touch" read). Does **not** re-query or move focus.
- **Double click**: re-focus (new neighborhood query centered here).
- **Drag**: pin the node (`fx/fy` set); shift-drag or double-pin-click releases it. Pinned nodes get a tiny pin glyph.

### 2.6 Path highlighting (reaches / reachable-from)

Triggered from the details panel quick actions (§5) or a header "Path" mode. Two query directions:

- **Reaches**: "from selected → target". User picks a target via the same autocomplete. Call `GET /api/reaches?from=X&to=Y`.
- **Reachable-from**: symmetric, swap args.

Response is `{result: "PATH_EXISTS" | "NO_MUST_PATH", path: [...]}`.

UX on response:

- `PATH_EXISTS`: ensure all `path` nodes are present in the current render (if some are outside the neighborhood, fetch a union or just render the path as its own minimal graph — see below), then **animate the path**: nodes and edges along `path` go full-opacity accent color, everything else drops to `0.15` opacity. A "flow" animation (animated stroke-dashoffset marching ants along path edges, ~1.5s) draws the eye from source to target. The path is also listed textually in the panel as a clickable chain `from ▸ … ▸ to`, each hop hover-syncing with the canvas node.
- `NO_MUST_PATH`: this is a meaningful, sound answer — *there is no guaranteed (MUST) call path*. Show a clear, non-alarming banner in the panel: **"No MUST path. `X` cannot definitely reach `Y` through guaranteed calls."** with a secondary line: *"A MAY path may still exist via `MAY_TOP` edges (unknown targets) — soundness can't rule it out."* Offer a button "Show MAY edges along frontier" if we later add that. The distinction between "provably cannot reach via MUST" and "we cannot prove it cannot reach via TOP" is exactly the soundness story; the copy must not say "no path exists" (false).

When the path includes nodes outside the current neighborhood: simplest correct behavior for v1 — render a **dedicated path graph**: just the `path` nodes in a left-to-right chain (we have an ordered list), using the same node/edge styling. Add a "← back to neighborhood" chip. This sidesteps trying to merge two force layouts. (Judgment call: a clean chain beats a half-correct union render.)

### 2.7 Performance & density

At target scale this is mostly about *visual* density, not compute. Concrete measures:

- **Render cap**: never draw more than `400` nodes / `800` edges at once. If a neighborhood query exceeds it, render the closest-by-hop subset and show a statusbar warning: `⚠ neighborhood truncated to 400/612 nodes — reduce depth or focus a leaf`. The cap is a constant in `app.js`.
- **SVG vs Canvas**: use **SVG** for ≤ ~600 nodes (clean crisp edges, easy hit-testing, CSS-able). It's well within SVG's comfort zone at our scale and buys us hover/click/markers for free. Do **not** reach for `<canvas>` — the complexity isn't justified below ~2k visible nodes, and we cap at 400.
- **Force sim tuning** (§9 has params): cap iterations, use `simulation.alphaDecay` tuned so it settles in ~2s, and **freeze on settle** (`on('end')` → stop ticking) to keep the CPU/laptop-fan quiet. Re-heat (`alpha(0.3).restart()`) only on structural change or drag.
- **Zoom/pan**: `d3.zoom` on the root `<g>`, scale extent `[0.2, 4]`. Scroll = zoom, drag-on-background = pan, drag-on-node = move node. Double-click background = reset-to-fit (`fitToView()` computes bbox and transforms). A `[⊹ fit]` button too.
- **Label LOD**: at zoom < 0.6, hide hop-2+ labels entirely; at zoom > 1.5, show all labels. Cheap `opacity` toggles on a zoom listener.
- **Hover hit-area**: nodes get an invisible `r+4` hit circle so small (low-score) nodes are still grabbable.

---

## 3. Module view (secondary)

### 3.1 How it differs

The module view answers a different question: *"what's the internal shape of this one file?"* It is bounded (one module's functions) and the natural reading is **hierarchical/topological**, not organic. So:

- **Layout**: a layered DAG (top→bottom, callers above callees) rather than force-directed. We compute layers ourselves (no dagre dependency — it'd need bundling and our graphs are small; a simple longest-path layering is enough, §9). Cycles (recursion / mutual recursion) are common in real code, so the layout must tolerate back-edges: break cycles for layering, then draw back-edges as visibly curved "return" arcs in a muted style.
- **All nodes labeled, always.** A module is small (tens of functions); no LOD needed. Labels right of node, monospace.
- **Same color hue** for the whole module (it's one module) — so here we *re-purpose the hue channel*: shade nodes by `exposed` (the module's public surface in full hue, internals in a desaturated tint) so the public API of the file reads top-of-mind. Border still marks exposed; size still maps score. (We free up hue because module-membership is constant here.)
- Edges: only intra-module calls (`/api/graph/module` already filters). Same kind styling as §2.3 — a module with many `MAY_TOP` internal calls is itself an interesting signal.

### 3.2 Module selector

A dropdown in the header (replaces the depth control when in Module mode), listing modules by `path`, grouped/sorted by directory. Each entry shows `basename` prominent, dimmed dir prefix, and a right-aligned `lines · fns` count. Selecting → `#/m/<module_id>` → `GET /api/graph/module?module_id=N`. The sidebar table auto-filters to that module for cross-reference.

Also: clicking the colored module swatch on any node's details panel jumps to that module's view.

### 3.3 Topology rendering

- Roots (functions called by nothing inside the module — likely entry points / exposed API) sink to the top layer; pure leaves to the bottom. This makes the file's "call frontier" readable top-down.
- Within a layer, order nodes to minimize edge crossings via a single barycenter pass (good enough; §9).
- Provide a `[force ⇄ layered]` toggle for users who prefer the organic view even within a module. Default layered.

---

## 4. Function table (sidebar)

### 4.1 Columns & ordering

Compact, dense, monospace-leaning. Columns (left→right):

1. **status dot** — module-hue filled circle; ring if `exposed`. (Doubles as the color legend tie-in to the graph.)
2. **name** — monospace, truncate with ellipsis + title tooltip. Primary column, widest.
3. **score** — `comment_quality_score` as a tiny 0–75 micro-bar (5-segment) + numeric on hover. Right-aligned.
4. **flags** — small glyphs: `◆` exposed, `⊤` has `MAY_TOP` callees (`has_violators`-adjacent), `¶` has intent/doc. Only render glyphs that apply.

`signature` is *not* a column (too wide); it shows on row hover as a tooltip and in the details panel. `module` is not a column because the dot encodes it and the table is usually module-filtered.

Default sort: **exposed first, then score descending, then name**. Rationale: the public, well-documented API is what people look for first.

### 4.2 Filters

A small filter block pinned at the top of the sidebar, above the list:

- **Module** dropdown — `[all ▾]` + one entry per module (same data as §3.2). → sets `module_id` query param.
- **Exposed toggle** — `☐ exposed only` checkbox → `exposed=1`.
- **Score threshold** — a slider `0–75` with live numeric readout `score ≥ 30`. → `min_score=N`. Debounced 200ms before firing `GET /api/functions?…`.

All three compose into one request: `GET /api/functions?module_id=N&exposed=1&min_score=N`. The result count updates the `FUNCTIONS (n)` header live. A `[clear filters]` link appears when any filter is non-default.

### 4.3 Row interactions

- **Single click** → `focus(name)` in the *current* main view (neighborhood by default). This is the primary "I want to look at this function" gesture.
- **Hover** → preview: highlight the corresponding node in the canvas if present (sync table↔graph), show signature tooltip.
- Keyboard: `j/k` move selection, `Enter` focuses, `/` jumps to search. Selected row gets an accent left-border.

### 4.4 Sorting & pagination

- **Sorting**: click column headers to sort (name, score). Small ▲/▼ indicator. Sorting is client-side over the already-fetched page — but see pagination.
- **Pagination**: the API supports it; the table fetches in pages of **100**. At our scale most filtered views fit one page. Use a lightweight `◀ 1 2 3 … ▶` pager at the sidebar bottom, *or* infinite-scroll (load next page on scroll-near-bottom). **Decision: infinite scroll** — fewer clicks, and for a dev scanning a list it's the expected behavior. Keep a "showing N of M" line. (If the API's pagination contract is offset/limit, `app.js` tracks offset and appends.)

---

## 5. Details panel

Opens on node/row single-click. Sections top→bottom:

```
┌─ DETAILS ───────────────────────────── × ┐
│ find_tag_positions          ◆ exposed     │  ← name (mono, bold) + exposed badge
│ ● arch_index_comment_parser.ml            │  ← module swatch + path (click → module view)
│                                           │
│ string -> (int * int * string) list       │  ← signature, monospace, syntax-tinted
│                                           │
│ Comment quality  ▓▓▓▓▓▓░░  58/75          │  ← score bar
│ ⊤ pre  ✓ post  ⚠ violators                │  ← contract flags (has_pre/has_post/has_violators)
│                                           │
│ ¶ Intent                                  │
│   Locates @tag markers and returns their  │  ← intent text
│   line/col spans.                          │
│                                           │
│ Defined  lines 42–67                       │  ← line_start/line_end
│                                           │
│ Calls (out) ─────────────────────────     │
│   ━▶ scan_line          parser.ml:48       │  ← callees, grouped by kind, call_site links
│   ┅▶ dispatch_tag       parser.ml:55       │
│   ⌁▶ (unknown)          parser.ml:61       │  ← MAY_TOP rendered explicitly
│ Called by (in) ──────────────────────     │
│   ━▶ parse_comment      parser.ml:12       │
│                                           │
│ ▸ Reaches…   ▸ Reachable from…            │  ← quick actions
└───────────────────────────────────────────┘
```

Details:

- **Signature** rendered monospace with light token tinting (types one color, arrows/punct muted). A tiny "copy" affordance.
- **Contract flags** (`has_pre`, `has_post`, `has_violators`): show as a compact row. `has_violators` is the one to draw attention to (amber `⚠`) since it means something downstream broke a contract — but keep it factual, not red-alarm.
- **Intent**: the one-line doc summary if present; if absent, a muted "no intent recorded" with a hint that `comment_quality_score` is low.
- **Call site links** (`call_site` = `"file.ml:42"`): rendered as monospace chips. Since we're local and read-only, clicking copies the `file:line` to clipboard (and, if we can detect an editor, optionally fires an `editor://` / `vscode://file/...` deep link — best-effort, behind a setting). At minimum: copy-to-clipboard with a toast.
- **Callees/callers** grouped by `kind` with the kind glyph, so the `MAY_TOP` calls are visually flagged right in the list. Each is clickable → selects that function (does not lose current focus unless double-clicked).
- **Quick actions**: `Reaches…` / `Reachable from…` open the autocomplete to pick the other endpoint, then run the §2.6 path flow.

---

## 6. Edge-kind legend & soundness callout

### 6.1 The persistent legend

A small, always-visible legend docked bottom-left of the canvas (collapsible). Three rows, each showing the exact stroke + color + label used on the canvas:

```
━━▶  MUST            definite call
┅┅▶  MAY_ENUMERATED  possible, target known
⌁⌁▶  MAY_TOP   ⊤     possible, target UNKNOWN (sound over-approx.)
```

Hovering each row dims all edges of other kinds on the canvas — a quick "show me only the MUST graph" gesture. (A trio of toggle checkboxes here doubles as edge-kind filters: untick `MAY_TOP` to see the conservative MUST/ENUM-only graph.)

### 6.2 Explaining MAY_TOP without confusing anyone

This is the single most important piece of copy in the app. The framing, used in the `ⓘ` help popover and as the `MAY_TOP` tooltip:

> **MAY_TOP (⊤) — "could call something we can't name."**
> When a function calls through a value the analyzer can't resolve at compile time (a higher-order argument, a stored callback, dynamic dispatch), we don't guess. We record a `MAY_TOP` edge meaning *"this might call anything."*
>
> This is **by design and means the index is *sound*** — it never claims a call is impossible when it might happen. A `MAY_TOP` edge is **not a bug or a missing analysis**; it's an honest "unknown." When you ask *"can X reach Y?"*, a `MUST`-only answer is provable; the presence of `MAY_TOP` edges is why we say "no **MUST** path" rather than "no path."

Key copy rules the implementer must hold to:
- Never label `MAY_TOP` as "error", "warning", "unresolved" in a pejorative sense, or color it red. Magenta/violet reads as "special/attention" not "broken."
- The `⊤` glyph (top symbol) is used consistently everywhere `MAY_TOP` appears (legend, edge midpoint, callee list, table flag).
- Reachability answers always phrase MUST vs MAY explicitly (see §2.6 `NO_MUST_PATH` copy).

---

## 7. Color palette & typography

### 7.1 Palette (dark theme)

Base surfaces — a true-dark, slightly blue-cool neutral set (easy on eyes, lets categorical hues pop):

| Token | Hex | Use |
|---|---|---|
| `--bg-0` | `#0d1117` | app background (stage) |
| `--bg-1` | `#161b22` | sidebar / panel surfaces |
| `--bg-2` | `#21262d` | raised elements, hover rows, inputs |
| `--bg-3` | `#30363d` | borders, dividers |
| `--fg-0` | `#e6edf3` | primary text |
| `--fg-1` | `#9da7b3` | secondary text |
| `--fg-2` | `#6e7681` | muted / disabled / statusbar |
| `--accent` | `#58a6ff` | focus halo, selection, links, primary action |
| `--accent-2` | `#2dd4bf` | path-highlight flow (teal, distinct from accent blue) |

Edge-kind colors (load-bearing, must stay distinct on `--bg-0`):

| Token | Hex | Kind |
|---|---|---|
| `--edge-must` | `#adbac7` | MUST (neutral, the "default reality") |
| `--edge-may` | `#e3b341` | MAY_ENUMERATED (amber) |
| `--edge-top` | `#bc8cff` | MAY_TOP (violet — special, not alarming) |
| `--warn` | `#f0883e` | `has_violators`, truncation warnings |

Module categorical palette — 12 colors, color-blind-considerate, assigned `module_id % 12`. Chosen to be distinguishable on dark bg and from the edge colors:

```
#58a6ff #3fb950 #e3b341 #ff7b72 #bc8cff #39c5cf
#db61a2 #f0883e #6cb6ff #8ddb8c #f2cc60 #ffb3ba
```

(For >12 modules we vary lightness on a second cycle. At 18 modules we get two near-identical-hue pairs — acceptable; the table dot + label disambiguate. If exact distinctness matters later, switch to a generated HCL ramp.)

### 7.2 Typography

- **UI text**: system font stack — `-apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`. No web-font download (self-contained constraint; system stack is free and familiar).
- **Code / signatures / call sites / table names**: monospace stack — `"SF Mono", "JetBrains Mono", "Fira Code", ui-monospace, "Cascadia Code", Menlo, Consolas, monospace`. We rely on the user's installed mono; no font embedding (keeps the binary small; devs have a mono font). If we *did* embed one it'd be JetBrains Mono subset — but **decision: don't embed, use the stack.**
- Sizes: base `13px` (dense dev-tool scale), `11px` for graph labels & statusbar, `15px` for panel/section headers. Line-height `1.45` for prose (intent), `1.2` for dense lists.

### 7.3 Tailwind-like utility naming for `style.css`

No Tailwind (no build step), but adopt a small, predictable utility vocabulary plus BEM-ish component classes so the CSS is greppable:

- Utilities: `.row`, `.col`, `.gap-1/2/3`, `.p-2`, `.muted`, `.mono`, `.truncate`, `.flex-1`, `.hidden`, `.scroll-y`.
- Components: `.app`, `.app__header`, `.sidebar`, `.sidebar__filters`, `.ftable`, `.ftable__row`, `.ftable__row--selected`, `.stage`, `.panel`, `.panel--open`, `.legend`, `.legend__row`, `.statusbar`, `.badge`, `.badge--exposed`, `.chip`, `.edge--must/--may/--top`, `.node`, `.node--focus`, `.node--exposed`, `.node--dim`.
- All colors via the CSS custom properties above on `:root` — single source of truth, themeable later.

---

## 8. Micro-interactions & polish

- **Hover states**:
  - Node hover → `1.15×` radius bump (`transform: scale`, transition `120ms`), show label, raise it (`raise()`), tooltip with `name` + signature + module.
  - Edge hover → thicken `+1px`, surface a tooltip with `caller → callee · kind · call_site`.
  - Table row hover → `--bg-2` fill, sync-highlight the canvas node.
- **Tooltips**: single shared tooltip element, repositioned (cheaper than per-element). `120ms` delay in, instant out. Monospace for code bits.
- **Transitions on graph change**:
  - New nodes **fade + grow in** from the focus node's position (`r: 0 → r`, opacity `0 → 1`, `300ms` staggered).
  - Removed nodes fade+shrink out before the sim drops them.
  - Depth change / re-focus: don't hard-cut. Keep shared nodes, animate their positions to the new layout (`d3` join with key = function id), add/remove the delta. This continuity is what makes graph-walking feel smooth.
  - Path highlight: dim transition `200ms`, then marching-ants on path edges.
- **Empty states** (these matter for a dev tool — they teach):
  - No search results → dropdown shows "no function matches `xyz`".
  - Neighborhood of an isolated node (no calls in/out) → render the single focus node centered with copy beneath: *"`foo` makes no recorded calls and is called by nothing in the index. It may be dead code, an entry point, or only reached via `MAY_TOP`."* (Again, the sound framing.)
  - Empty filtered table → "No functions match these filters." + `[clear filters]`.
  - `reaches` with `NO_MUST_PATH` → §2.6 banner.
  - First load, nothing focused → stage shows a friendly hint card: "Search a function (`/`) or pick one from the list to start." plus 3 example links (the highest-score exposed functions, fetched from `/api/functions?exposed=1`).
- **Keyboard shortcuts** (show via `?` overlay):
  - `/` focus search · `Esc` close panel / clear path-highlight / blur search
  - `j` / `k` table nav · `Enter` focus selected · `o` open details for selected
  - `1` / `2` / `3` set depth · `f` fit-to-view · `[` toggle sidebar
  - `n` / `m` switch Neighborhood / Module view · `?` shortcuts overlay
  - `r` start "reaches" from selected
- **Toasts**: bottom-center, `--bg-2`, auto-dismiss `2s` — for "copied `file.ml:42`", "truncated render", etc.
- **Loading**: queries are sub-second; show a subtle top progress shimmer only if a request exceeds `150ms` (avoids spinner flash on fast responses).
- **Reduced motion**: respect `prefers-reduced-motion` — drop the marching-ants and stagger, keep instant state changes.

---

## 9. Implementation notes (D3 + vanilla JS patterns)

### 9.1 App structure (single `app.js`, no framework)

- **Hash router**: `window.onhashchange` → parse `#/n/<name>?depth=N` | `#/m/<id>` → dispatch to `renderNeighborhood` / `renderModule`. URL is the single source of view state (§0.5).
- **State**: one module-scoped object `const S = { allFns: [], view, focus, depth, selected, filters, sim, ... }`. No reactive framework; explicit `render*()` calls after state mutation. Keep it boring.
- **Data fetch**: tiny `api(path)` helper wrapping `fetch().then(r=>r.json())`. Cache `/api/functions` (full list) and `/api/modules` in `S` on boot.
- **DOM**: build static shell in `index.html`; `app.js` only touches dynamic regions (table body, panel, svg). Use a minimal `h(tag, attrs, children)` helper for the table/panel rather than string templating (avoids XSS on function names/signatures — escape via `textContent`, never `innerHTML`, for any DB-sourced string).

### 9.2 Force simulation (neighborhood)

```js
const sim = d3.forceSimulation(nodes)
  .force("link", d3.forceLink(edges).id(d => d.id).distance(60).strength(0.5))
  .force("charge", d3.forceManyBody().strength(-220).distanceMax(320))
  .force("collide", d3.forceCollide(d => d.r + 6))
  .force("center", d3.forceCenter(W/2, H/2))
  .force("x", d3.forceX(W/2).strength(0.04))   // gentle gravity, keeps disconnected bits on-screen
  .force("y", d3.forceY(H/2).strength(0.04))
  .alphaDecay(0.045)                            // settles ~2s
  .on("tick", ticked)
  .on("end", () => sim.stop());                 // freeze when settled (quiet fan)
```

- **Data join with stable keys**: `selection.data(nodes, d => d.id)` so re-focus/depth changes diff instead of rebuild (enables the §8 position-animation continuity). Same for edges keyed by `caller_id-callee_id-kind`.
- **Pin focus** first layout: `focusNode.fx = W/2; focusNode.fy = H/2;` release after `2.5s` or on user drag.
- **Curved edges**: render edges as `<path>` with a quadratic bezier; compute a perpendicular offset per edge so A→B and B→A separate. Arrow `marker-end` per kind.
- **Zoom**: `d3.zoom().scaleExtent([0.2,4]).on("zoom", e => g.attr("transform", e.transform))`; `fitToView()` computes node bbox → `d3.zoomIdentity.translate(...).scale(...)` with `transition().duration(400)`.
- **Drag**: standard `d3.drag` setting `fx/fy` on start/drag; on end leave pinned (explicit unpin gesture).

### 9.3 Module view (layered DAG — no dagre)

Bundling dagre violates "keep it simple, plain JS." Our graphs are tens of nodes; a hand-rolled layering is ~50 lines:

1. **Break cycles**: DFS, mark back-edges (edges to a node on the current stack); exclude them from layering.
2. **Layer assignment (longest-path)**: `layer(v) = 1 + max(layer(u) for u→v in DAG)`, roots at layer 0. One memoized pass.
3. **Order within layer**: one barycenter sweep (median of neighbor x-positions) to cut crossings — good enough at our scale.
4. **Position**: `y = layer * 90`, `x = orderIndex * 120`, center each layer. Draw forward edges as straight/slightly-curved top→bottom; **back-edges** as wide right-side bezier arcs in muted style (visually "this is a loop").
5. Reuse the *same* node/edge rendering code as neighborhood (same `<g>`, markers, styling) — only the positioning source differs (fixed `x/y` vs sim). Wrap both behind a `layout` strategy so the render path is shared.

`[force ⇄ layered]` toggle just swaps which strategy populates `x/y` (force → run sim; layered → compute above, set `fx/fy`).

### 9.4 Path highlight

- Build a `Set` of path node ids and a `Set` of path edge keys from the `reaches` response. One pass over selections: add `.node--dim` / `.edge--dim` to non-members, accent class to members.
- Marching ants: animate `stroke-dashoffset` via a CSS keyframe class `.edge--flow` on path edges (`--accent-2`). Pure CSS, no JS rAF needed.
- If path nodes are outside current graph → render the dedicated chain layout (§2.6) using the layered strategy with a single column ordering = path order.

### 9.5 Table

- Render once into a `<div>` virtualized only if a filtered list exceeds ~500 rows (windowing). Below that, plain DOM is fine at our scale — **decision: no virtualization in v1**, infinite-scroll append in pages of 100 keeps the DOM bounded naturally.
- Sort: keep the fetched array in `S.tableRows`, sort in place, re-render rows. Column-header click toggles `sortKey/sortDir`.
- Sync highlight: maintain `id → <tr>` and `id → <g.node>` maps so hover in either place can `classList.toggle` the other in O(1).

### 9.6 Assets / bundling

- `d3.min.js` shipped as a static embedded asset (per intake, via `ppx_blob`). Use the full `d3` UMD or, to shave size, a custom bundle of only `d3-selection`, `d3-force`, `d3-zoom`, `d3-drag`, `d3-transition`, `d3-shape` — but **decision: ship full `d3.min.js`** for v1 simplicity; revisit if binary size is a problem.
- All API URLs are relative (`/api/...`) so it works on whatever port the server picked.
- Escape every DB-sourced string via `textContent`. Function names/signatures are developer-controlled, but defense-in-depth is one line and free.

### 9.7 Suggested file layout (matches intake)

```
bin/arch_serve/static/
  index.html   — static shell: header, sidebar skeleton, stage <svg>, panel, statusbar, legend
  style.css    — :root tokens, utilities, component classes (§7.3)
  app.js       — router, state, fetch, table, force/layered render, panel, path-highlight
  d3.min.js    — embedded D3 (v7)
```

---

## 10. Build-order recommendation (for the implementer)

Ship in vertical slices, each independently demoable:

1. **Shell + table + filters** against `/api/modules` + `/api/functions`. No graph yet. Validates layout, palette, filtering, keyboard nav.
2. **Neighborhood force graph** with node/edge encodings + legend + details panel (no path queries). The core value.
3. **Path highlighting** (`/api/reaches`) + soundness copy. The differentiator.
4. **Module view** (layered DAG).
5. **Polish pass**: transitions, empty states, shortcuts overlay, toasts, reduced-motion.

Each slice keeps `app.js` runnable and the binary buildable. Slice 1–2 deliver ~80% of the daily-driver value.
