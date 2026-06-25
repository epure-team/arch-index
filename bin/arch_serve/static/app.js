/* arch-serve SPA — vanilla JS + D3 v7 */
'use strict';

// ── State ────────────────────────────────────────────────────────────────
const S = {
  allFns: [],
  allModules: [],
  view: 'neighborhood',
  focus: null,
  depth: 2,
  selectedId: null,
  tableOffset: 0,
  tableFns: [],
  sim: null,
  simNodes: [],
  simEdges: [],
  kindFilter: { MUST: true, MAY_ENUMERATED: true, MAY_TOP: true },
  pathMode: false,
  sidebarVisible: true,
  filters: { module_id: null, exposed: false, min_score: 0 },
  debounceTimer: null,
};

// ── API ──────────────────────────────────────────────────────────────────
const api = (path) => fetch(path).then(r => {
  if (!r.ok) return r.json().then(e => Promise.reject(e));
  return r.json();
});

// ── Safe DOM helper ──────────────────────────────────────────────────────
function h(tag, attrs, children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') el.className = v;
    else if (k === 'style') el.style.cssText = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v);
  }
  for (const child of (children || [])) {
    if (typeof child === 'string') el.appendChild(document.createTextNode(child));
    else if (child) el.appendChild(child);
  }
  return el;
}

function toast(msg) {
  const t = h('div', { class: 'toast' }, [msg]);
  document.getElementById('toast-container').appendChild(t);
  setTimeout(() => { t.classList.add('fade-out'); setTimeout(() => t.remove(), 300); }, 2000);
}

// ── Module color palette ─────────────────────────────────────────────────
const MOD_COLORS = Array.from({ length: 12 }, (_, i) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--mod-${i}`).trim()
);
function modColor(moduleId) {
  const style = getComputedStyle(document.documentElement);
  return style.getPropertyValue(`--mod-${moduleId % 12}`).trim() || '#58a6ff';
}

// ── Boot ─────────────────────────────────────────────────────────────────
async function boot() {
  try {
    [S.allModules, S.allFns] = await Promise.all([
      api('/api/modules'),
      api('/api/functions'),
    ]);
    populateModuleDropdown();
    populateModuleViewSelect();
    applyFilters();
    updateStatusbar();
    buildHintCard();
    setupSearch();
    window.addEventListener('hashchange', onHashChange);
    onHashChange();
  } catch (e) {
    document.getElementById('statusbar').textContent = 'Error loading data from server.';
    console.error(e);
  }
}

function updateStatusbar(extra) {
  const sb = document.getElementById('statusbar');
  const base = `${S.allModules.length} modules · ${S.allFns.length} functions`;
  sb.textContent = extra ? `${base} · ${extra}` : base;
}

function buildHintCard() {
  const links = document.getElementById('hint-card-links');
  links.innerHTML = '';
  const top = [...S.allFns]
    .filter(f => f.exposed && f.comment_quality_score != null)
    .sort((a, b) => b.comment_quality_score - a.comment_quality_score)
    .slice(0, 3);
  top.forEach(fn => {
    const a = h('span', { class: 'hint-card__link', onclick: () => navigate(fn.name) }, [fn.name]);
    links.appendChild(a);
  });
}

// ── Hash router ──────────────────────────────────────────────────────────
function onHashChange() {
  const hash = location.hash;
  const nMatch = hash.match(/^#\/n\/([^?]+)(?:\?depth=(\d))?$/);
  const mMatch = hash.match(/^#\/m\/(\d+)$/);
  if (nMatch) {
    S.view = 'neighborhood';
    S.focus = decodeURIComponent(nMatch[1]);
    S.depth = parseInt(nMatch[2] || String(S.depth));
    showNeighborhoodControls();
    renderNeighborhood(S.focus, S.depth);
  } else if (mMatch) {
    S.view = 'module';
    showModuleControls();
    renderModule(parseInt(mMatch[1]));
  }
}

function navigate(name, depth) {
  const d = depth || S.depth;
  location.hash = `#/n/${encodeURIComponent(name)}?depth=${d}`;
}

function navigateModule(moduleId) {
  location.hash = `#/m/${moduleId}`;
}

function showNeighborhoodControls() {
  document.getElementById('depth-controls').style.display = '';
  document.getElementById('module-view-select').hidden = true;
  document.getElementById('btn-neighborhood').classList.add('btn--active');
  document.getElementById('btn-module').classList.remove('btn--active');
}

function showModuleControls() {
  document.getElementById('depth-controls').style.display = 'none';
  document.getElementById('module-view-select').hidden = false;
  document.getElementById('btn-module').classList.add('btn--active');
  document.getElementById('btn-neighborhood').classList.remove('btn--active');
}

// ── Module dropdown (sidebar filter) ────────────────────────────────────
function populateModuleDropdown() {
  const sel = document.getElementById('module-filter');
  S.allModules.forEach(m => {
    const opt = document.createElement('option');
    opt.value = String(m.id);
    opt.textContent = m.path.replace(/^.*\//, '');
    sel.appendChild(opt);
  });
}

function populateModuleViewSelect() {
  const sel = document.getElementById('module-view-select');
  S.allModules.forEach(m => {
    const opt = document.createElement('option');
    opt.value = String(m.id);
    opt.textContent = m.path.replace(/^.*\//, '');
    sel.appendChild(opt);
  });
  sel.addEventListener('change', () => {
    if (sel.value) navigateModule(parseInt(sel.value));
  });
}

// ── Filters + table ──────────────────────────────────────────────────────
function applyFilters() {
  clearTimeout(S.debounceTimer);
  S.debounceTimer = setTimeout(() => {
    const params = new URLSearchParams();
    if (S.filters.module_id) params.set('module_id', S.filters.module_id);
    if (S.filters.exposed) params.set('exposed', '1');
    if (S.filters.min_score > 0) params.set('min_score', String(S.filters.min_score));
    api(`/api/functions?${params}`)
      .then(fns => { S.tableFns = fns; S.tableOffset = 0; renderTable(fns); })
      .catch(() => {});
  }, 200);
}

function renderTable(fns) {
  const container = document.getElementById('ftable');
  container.innerHTML = '';
  document.getElementById('fn-count').textContent = fns.length;
  if (fns.length === 0) {
    const empty = h('div', { class: 'empty-state' }, [
      'No functions match these filters. ',
      h('span', { onclick: clearFilters }, ['clear filters']),
    ]);
    container.appendChild(empty);
    return;
  }
  const page = fns.slice(0, S.tableOffset + 100);
  page.forEach((fn, i) => {
    const row = buildFnRow(fn, i);
    container.appendChild(row);
  });
  if (fns.length > page.length) {
    container.addEventListener('scroll', function onScroll() {
      if (container.scrollTop + container.clientHeight > container.scrollHeight - 40) {
        container.removeEventListener('scroll', onScroll);
        S.tableOffset += 100;
        renderTable(fns);
      }
    }, { once: true });
  }
}

function buildFnRow(fn, _i) {
  const color = modColor(fn.module_id);
  const score = fn.comment_quality_score || 0;
  const flags = (fn.has_pre ? '▲' : '') + (fn.has_post ? '▼' : '') + (fn.has_violators ? '!' : '');
  const row = h('div', {
    class: 'ftrow' + (fn.name === S.focus ? ' selected' : ''),
    onclick: () => navigate(fn.name),
  }, [
    h('div', { class: 'ftrow__dot', style: `background:${color}; ${fn.exposed ? 'box-shadow:0 0 0 2px '+color+'40' : ''}` }),
    h('div', { class: 'ftrow__name' }, [fn.name]),
    h('div', { class: 'ftrow__score' }, [
      h('div', { class: 'ftrow__score-fill', style: `width:${(score/75)*100}%` }),
    ]),
    h('div', { class: 'ftrow__flags' }, [flags]),
  ]);
  return row;
}

function clearFilters() {
  S.filters = { module_id: null, exposed: false, min_score: 0 };
  document.getElementById('module-filter').value = '';
  document.getElementById('exposed-filter').checked = false;
  document.getElementById('score-filter').value = '0';
  document.getElementById('score-value').textContent = '0';
  applyFilters();
}

// ── Search / autocomplete ─────────────────────────────────────────────────
function setupSearch() {
  const input = document.getElementById('search');
  const results = document.getElementById('search-results');
  let focusedIdx = -1;

  input.addEventListener('input', () => {
    const q = input.value.trim().toLowerCase();
    if (!q) { results.hidden = true; return; }
    const matches = S.allFns
      .filter(f => f.name.toLowerCase().includes(q))
      .sort((a, b) => {
        const ap = a.name.toLowerCase().startsWith(q) ? 0 : 1;
        const bp = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        if (ap !== bp) return ap - bp;
        if (a.name.length !== b.name.length) return a.name.length - b.name.length;
        return (b.exposed ? 1 : 0) - (a.exposed ? 1 : 0);
      })
      .slice(0, 10);
    results.innerHTML = '';
    focusedIdx = -1;
    matches.forEach((fn, i) => {
      const item = h('div', {
        class: 'search-result',
        onclick: () => { navigate(fn.name); input.value = ''; results.hidden = true; },
      }, [
        h('div', { class: 'ftrow__dot', style: `background:${modColor(fn.module_id)}` }),
        h('span', {}, [fn.name]),
      ]);
      item.dataset.idx = i;
      results.appendChild(item);
    });
    results.hidden = matches.length === 0;
  });

  input.addEventListener('keydown', (e) => {
    const items = results.querySelectorAll('.search-result');
    if (e.key === 'ArrowDown') { focusedIdx = Math.min(focusedIdx + 1, items.length - 1); updateFocusedResult(items, focusedIdx); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { focusedIdx = Math.max(focusedIdx - 1, 0); updateFocusedResult(items, focusedIdx); e.preventDefault(); }
    else if (e.key === 'Enter' && focusedIdx >= 0) { items[focusedIdx].click(); e.preventDefault(); }
    else if (e.key === 'Escape') { results.hidden = true; input.blur(); }
  });

  document.addEventListener('click', (e) => {
    if (!results.contains(e.target) && e.target !== input) results.hidden = true;
  });
}

function updateFocusedResult(items, idx) {
  items.forEach((el, i) => el.classList.toggle('focused', i === idx));
  if (items[idx]) items[idx].scrollIntoView({ block: 'nearest' });
}

// ── Neighborhood graph ───────────────────────────────────────────────────
const svg = d3.select('#graph-svg');
let W = 0, H = 0;

function getStageDims() {
  const stage = document.getElementById('stage');
  W = stage.clientWidth;
  H = stage.clientHeight;
}

function initSvg() {
  getStageDims();
  svg.attr('width', W).attr('height', H);

  svg.selectAll('*').remove();

  // Arrow marker defs
  const defs = svg.append('defs');
  [
    { id: 'arrow-must', color: 'var(--edge-must)' },
    { id: 'arrow-may',  color: 'var(--edge-may)' },
    { id: 'arrow-top',  color: 'var(--edge-top)' },
  ].forEach(({ id, color }) => {
    defs.append('marker')
      .attr('id', id)
      .attr('viewBox', '0 -4 8 8')
      .attr('refX', 12)
      .attr('refY', 0)
      .attr('markerWidth', 6)
      .attr('markerHeight', 6)
      .attr('orient', 'auto')
      .append('path')
      .attr('d', 'M0,-4L8,0L0,4')
      .attr('fill', color);
  });

  // Zoom container
  const g = svg.append('g').attr('class', 'zoom-g');

  const zoom = d3.zoom()
    .scaleExtent([0.2, 4])
    .on('zoom', (event) => g.attr('transform', event.transform));
  svg.call(zoom);

  document.getElementById('fit-btn').onclick = () => fitView(g, zoom);

  return { g, zoom };
}

let gContainer = null, gZoom = null;

function nodeRadius(d) {
  return 6 + ((d.comment_quality_score || 0) / 75) * 8;
}

function arrowId(kind) {
  if (!kind || kind === 'MUST') return 'url(#arrow-must)';
  if (kind === 'MAY_ENUMERATED') return 'url(#arrow-may)';
  return 'url(#arrow-top)';
}

function linkClass(kind) {
  if (!kind || kind === 'MUST') return 'link must';
  if (kind === 'MAY_ENUMERATED') return 'link may';
  return 'link top';
}

async function renderNeighborhood(name, depth) {
  document.getElementById('hint-card').style.display = 'none';
  clearBackChip();
  S.pathMode = false;

  try {
    const data = await api(`/api/graph/neighborhood?name=${encodeURIComponent(name)}&depth=${depth}`);

    if (data.truncated) toast(`Truncated: showing ${data.nodes.length} of ≥2000 nodes`);
    updateStatusbar(`${data.nodes.length} nodes · ${data.edges.length} edges`);

    const nodes = data.nodes;
    const edges = data.edges;

    if (nodes.length === 0) {
      clearGraph();
      showIsolatedMessage(name);
      return;
    }

    if (!gContainer) {
      const init = initSvg();
      gContainer = init.g;
      gZoom = init.zoom;
    }

    // Build node lookup for edge drawing
    const nodeById = new Map(nodes.map(n => [n.id, n]));

    // Deduplicate edges (keep unique caller+callee+kind combos)
    const edgeKey = e => `${e.caller_id}:${e.callee_id}:${e.kind}`;
    const uniqueEdges = [...new Map(edges.map(e => [edgeKey(e), e])).values()];

    // Mark reciprocal pairs for curve offset
    const reciprocalSet = new Set();
    uniqueEdges.forEach(e => {
      const rev = `${e.callee_id}:${e.caller_id}:${e.kind}`;
      if (uniqueEdges.find(f => edgeKey(f) === rev)) reciprocalSet.add(edgeKey(e));
    });

    // Find seed node
    const seedNode = nodes.find(n => n.name === name) || nodes[0];

    // Incremental update: preserve existing node positions
    const existingNodeMap = new Map((S.simNodes || []).map(n => [n.id, n]));

    const newNodes = nodes.map(n => {
      const existing = existingNodeMap.get(n.id);
      return existing ? { ...n, x: existing.x, y: existing.y, vx: existing.vx, vy: existing.vy, fx: existing.fx, fy: existing.fy } : { ...n };
    });

    // Pin seed near center
    const seed = newNodes.find(n => n.name === name);
    if (seed) {
      seed.fx = W / 2;
      seed.fy = H / 2;
    }

    S.simNodes = newNodes;
    S.simEdges = uniqueEdges.map(e => ({
      ...e,
      source: newNodes.find(n => n.id === e.caller_id) || e.caller_id,
      target: newNodes.find(n => n.id === e.callee_id) || e.callee_id,
    }));

    if (!S.sim) {
      S.sim = d3.forceSimulation()
        .force('link', d3.forceLink().id(d => d.id).distance(60).strength(0.5))
        .force('charge', d3.forceManyBody().strength(-220).distanceMax(320))
        .force('collide', d3.forceCollide(d => nodeRadius(d) + 6))
        .force('center', d3.forceCenter(W / 2, H / 2))
        .force('x', d3.forceX(W / 2).strength(0.04))
        .force('y', d3.forceY(H / 2).strength(0.04))
        .alphaDecay(0.045)
        .on('tick', ticked)
        .on('end', () => S.sim.stop());
    }

    S.reciprocalSet = reciprocalSet;
    S.sim.nodes(S.simNodes);
    S.sim.force('link').links(S.simEdges);
    S.sim.alpha(0.3).restart();

    drawGraph(gContainer, S.simNodes, S.simEdges, reciprocalSet, nodeById, seedNode, name);

  } catch (e) {
    if (e && e.error) toast(e.error);
    console.error(e);
  }
}

function drawGraph(g, nodes, edges, reciprocalSet, nodeById, seedNode, focusName) {
  const edgeKey = e => `${e.caller_id}:${e.callee_id}:${e.kind}`;

  // Remove old elements not in new data
  // Links
  const linkSel = g.selectAll('.link-group')
    .data(edges, d => edgeKey(d));
  linkSel.exit().remove();
  const linkEnter = linkSel.enter().append('g').attr('class', 'link-group');
  linkEnter.append('path').attr('class', d => linkClass(d.kind))
    .attr('marker-end', d => arrowId(d.kind));
  linkEnter.filter(d => d.kind === 'MAY_TOP')
    .append('text').attr('class', 'link-label').text('⊤');

  // Nodes
  const nodeSel = g.selectAll('.node')
    .data(nodes, d => d.id);
  nodeSel.exit().remove();
  const nodeEnter = nodeSel.enter().append('g')
    .attr('class', d => 'node' + (d.name === focusName ? ' focus' : ''))
    .call(d3.drag()
      .on('start', dragstarted)
      .on('drag', dragged)
      .on('end', dragended))
    .on('click', (event, d) => {
      event.stopPropagation();
      selectNode(d, g, nodes, edges);
    })
    .on('dblclick', (event, d) => {
      event.stopPropagation();
      navigate(d.name, S.depth);
    });

  nodeEnter.append('circle')
    .attr('r', d => nodeRadius(d))
    .attr('fill', d => modColor(d.module_id))
    .attr('stroke', d => d.exposed ? 'white' : modColor(d.module_id))
    .attr('stroke-width', d => d.exposed ? 2 : 1)
    .attr('opacity', 0)
    .transition().duration(300).attr('opacity', 1);

  nodeEnter.append('text')
    .attr('dy', d => nodeRadius(d) + 11)
    .attr('text-anchor', 'middle')
    .text(d => d.name.length > 20 ? d.name.slice(0, 18) + '…' : d.name);

  // Update existing nodes
  nodeSel.attr('class', d => 'node' + (d.name === focusName ? ' focus' : ''));

  svg.on('click', () => {
    deselectAll(g);
    closePanel();
  });
}

function ticked() {
  if (!gContainer) return;
  const g = gContainer;

  g.selectAll('.link-group').each(function(d) {
    const grp = d3.select(this);
    const s = typeof d.source === 'object' ? d.source : { x: 0, y: 0 };
    const t = typeof d.target === 'object' ? d.target : { x: 0, y: 0 };
    const eKey = `${d.caller_id}:${d.callee_id}:${d.kind}`;
    const isReciprocal = S.reciprocalSet && S.reciprocalSet.has(eKey);
    const pathD = edgePath(s, t, isReciprocal, nodeRadius(t));

    grp.select('path').attr('d', pathD);
    if (d.kind === 'MAY_TOP') {
      const mx = (s.x + t.x) / 2;
      const my = (s.y + t.y) / 2;
      grp.select('text').attr('x', mx).attr('y', my);
    }
  });

  g.selectAll('.node')
    .attr('transform', d => `translate(${d.x || 0},${d.y || 0})`);

  // LOD: hide labels on far nodes at low zoom
  const currentZoom = d3.zoomTransform(svg.node()).k;
  g.selectAll('.node text').attr('display', d => {
    if (currentZoom >= 0.6) return null;
    if (d.name === S.focus) return null;
    return 'none';
  });
}

function edgePath(s, t, isReciprocal, targetRadius) {
  const dx = t.x - s.x;
  const dy = t.y - s.y;
  const len = Math.sqrt(dx * dx + dy * dy) || 1;
  const ux = dx / len;
  const uy = dy / len;
  const tx = t.x - ux * (targetRadius + 2);
  const ty = t.y - uy * (targetRadius + 2);

  if (!isReciprocal) {
    return `M${s.x},${s.y}L${tx},${ty}`;
  }
  // Curve for reciprocal pairs
  const cx = (s.x + t.x) / 2 - uy * 20;
  const cy = (s.y + t.y) / 2 + ux * 20;
  return `M${s.x},${s.y}Q${cx},${cy},${tx},${ty}`;
}

function dragstarted(event, d) {
  if (!event.active) S.sim && S.sim.alphaTarget(0.3).restart();
  d.fx = d.x; d.fy = d.y;
}
function dragged(event, d) { d.fx = event.x; d.fy = event.y; }
function dragended(event, d) {
  if (!event.active) S.sim && S.sim.alphaTarget(0);
}

function selectNode(d, g, nodes, edges) {
  S.selectedId = d.id;
  // Dim non-adjacent nodes
  const adjacent = new Set([d.id]);
  edges.forEach(e => {
    if (e.caller_id === d.id) adjacent.add(e.callee_id);
    if (e.callee_id === d.id) adjacent.add(e.caller_id);
  });
  g.selectAll('.node').classed('dimmed', n => !adjacent.has(n.id));
  g.selectAll('.link-group').classed('dimmed', e =>
    e.caller_id !== d.id && e.callee_id !== d.id);
  renderPanel(d);
}

function deselectAll(g) {
  S.selectedId = null;
  g.selectAll('.node').classed('dimmed', false);
  g.selectAll('.link-group').classed('dimmed', false);
}

function clearGraph() {
  if (gContainer) gContainer.selectAll('*').remove();
  S.sim = null; S.simNodes = []; S.simEdges = [];
  gContainer = null; gZoom = null;
}

function showIsolatedMessage(name) {
  clearGraph();
  const stage = document.getElementById('stage');
  const old = stage.querySelector('.empty-state');
  if (old) old.remove();
  const msg = h('div', { class: 'empty-state', style: 'position:absolute;inset:0' }, [
    `No call graph data for "${name}". This function has no indexed callers or callees.`
  ]);
  stage.appendChild(msg);
}

function fitView(g, zoom) {
  if (!g || !S.simNodes.length) return;
  const xs = S.simNodes.map(n => n.x || 0);
  const ys = S.simNodes.map(n => n.y || 0);
  const x0 = Math.min(...xs) - 40, x1 = Math.max(...xs) + 40;
  const y0 = Math.min(...ys) - 40, y1 = Math.max(...ys) + 40;
  const dx = x1 - x0, dy = y1 - y0;
  const scale = Math.min(0.9, Math.min(W / dx, H / dy));
  const tx = W / 2 - scale * (x0 + x1) / 2;
  const ty = H / 2 - scale * (y0 + y1) / 2;
  svg.transition().duration(400)
    .call(zoom.transform, d3.zoomIdentity.translate(tx, ty).scale(scale));
}

// ── Panel ────────────────────────────────────────────────────────────────
function renderPanel(fn) {
  const panel = document.getElementById('panel');
  const content = document.getElementById('panel-content');
  panel.hidden = false;

  const modPath = (S.allModules.find(m => m.id === fn.module_id) || {}).path || '';
  const modName = modPath.replace(/^.*\//, '').replace(/\.ml[i]?$/, '');
  const score = fn.comment_quality_score || 0;
  const color = modColor(fn.module_id);

  const el = document.createElement('div');

  // Name
  const nameEl = h('div', { class: 'panel-fn-name' }, [fn.name]);
  el.appendChild(nameEl);

  // Module
  el.appendChild(h('div', { class: 'panel-module' }, [
    h('span', { class: 'mod-swatch', style: `background:${color}` }),
    modName,
  ]));

  // Signature
  if (fn.signature) {
    el.appendChild(h('div', { class: 'panel-sig' }, [fn.signature]));
  }

  // Score
  el.appendChild(h('div', { class: 'panel-score' }, [
    h('div', { class: 'panel-score-bar' }, [
      h('div', { class: 'panel-score-fill', style: `width:${(score/75)*100}%` }),
    ]),
    h('span', { class: 'panel-score-label' }, [`${score}/75`]),
  ]));

  // Flags
  el.appendChild(h('div', { class: 'panel-flags' }, [
    h('span', { class: 'flag' + (fn.exposed ? ' active' : '') }, ['exposed']),
    h('span', { class: 'flag' + (fn.has_pre ? ' active' : '') }, ['pre']),
    h('span', { class: 'flag' + (fn.has_post ? ' active' : '') }, ['post']),
    h('span', { class: 'flag' + (fn.has_violators ? ' active' : '') }, ['violators']),
  ]));

  // Intent
  if (fn.intent) {
    el.appendChild(h('div', { class: 'panel-intent' }, [fn.intent]));
  }

  // Callees from edges
  if (S.simEdges && S.simEdges.length > 0) {
    const outgoing = S.simEdges.filter(e => {
      const src = typeof e.source === 'object' ? e.source.id : e.source;
      return src === fn.id;
    });
    const incoming = S.simEdges.filter(e => {
      const tgt = typeof e.target === 'object' ? e.target.id : e.target;
      return tgt === fn.id;
    });

    if (outgoing.length > 0) {
      el.appendChild(h('div', { class: 'panel-section-title' }, ['Calls']));
      outgoing.slice(0, 12).forEach(e => {
        const tgt = typeof e.target === 'object' ? e.target : S.simNodes.find(n => n.id === e.callee_id);
        if (!tgt) return;
        el.appendChild(h('div', { class: 'panel-edge-item', onclick: () => navigate(tgt.name) }, [
          h('span', { class: `kind-glyph ${kindClass(e.kind)}` }, [kindGlyph(e.kind)]),
          h('span', {}, [tgt.name]),
        ]));
      });
    }
    if (incoming.length > 0) {
      el.appendChild(h('div', { class: 'panel-section-title' }, ['Called by']));
      incoming.slice(0, 12).forEach(e => {
        const src = typeof e.source === 'object' ? e.source : S.simNodes.find(n => n.id === e.caller_id);
        if (!src) return;
        el.appendChild(h('div', { class: 'panel-edge-item', onclick: () => navigate(src.name) }, [
          h('span', { class: `kind-glyph ${kindClass(e.kind)}` }, [kindGlyph(e.kind)]),
          h('span', {}, [src.name]),
        ]));
      });
    }
  }

  // Reaches action
  el.appendChild(h('div', { class: 'panel-section-title' }, ['Reachability']));
  const reachesForm = h('div', { class: 'panel-reaches-form' }, []);
  const reachesInput = h('input', { type: 'text', placeholder: 'target function…' });
  const reachesBtn = h('button', { class: 'btn', onclick: () => {
    const target = reachesInput.value.trim();
    if (target) runReaches(fn.name, target, el);
  }}, ['reaches?']);
  reachesForm.appendChild(reachesInput);
  reachesForm.appendChild(reachesBtn);
  el.appendChild(reachesForm);

  const pathResultEl = h('div', { class: 'panel-path-msg' });
  el.appendChild(pathResultEl);

  content.innerHTML = '';
  content.appendChild(el);
}

function kindClass(kind) {
  if (!kind || kind === 'MUST') return 'must';
  if (kind === 'MAY_ENUMERATED') return 'may';
  return 'top';
}

function kindGlyph(kind) {
  if (!kind || kind === 'MUST') return '━▶';
  if (kind === 'MAY_ENUMERATED') return '┅▶';
  return '⊤▶';
}

function closePanel() {
  document.getElementById('panel').hidden = true;
  document.getElementById('panel-content').innerHTML = '';
}

// ── Path queries ─────────────────────────────────────────────────────────
async function runReaches(fromName, toName, panelEl) {
  const msgEl = panelEl.querySelector('.panel-path-msg');
  msgEl.textContent = 'searching…';
  try {
    const data = await api(
      `/api/reaches?from=${encodeURIComponent(fromName)}&to=${encodeURIComponent(toName)}`
    );
    if (data.result === 'PATH_EXISTS') {
      msgEl.textContent = '';
      highlightPath(data.path);
      showBreadcrumb(data.path, fromName, toName, msgEl);
    } else {
      msgEl.textContent =
        `No MUST path. \`${fromName}\` cannot definitely reach \`${toName}\` through guaranteed calls.`;
      clearPathHighlight();
    }
  } catch (e) {
    if (e && e.error) msgEl.textContent = `Unknown function: ${e.error.replace('unknown function: ', '')}`;
    else msgEl.textContent = 'Error running reaches query.';
  }
}

function highlightPath(pathIds) {
  if (!gContainer) return;
  S.pathMode = true;
  const pathSet = new Set(pathIds);

  gContainer.selectAll('.node').classed('dimmed', d => !pathSet.has(d.id));
  gContainer.selectAll('.link-group').each(function(d) {
    const isOnPath = pathSet.has(d.caller_id) && pathSet.has(d.callee_id);
    const grp = d3.select(this);
    grp.selectAll('path').classed('dimmed', !isOnPath).classed('edge--flow', isOnPath);
  });
}

function clearPathHighlight() {
  S.pathMode = false;
  if (!gContainer) return;
  gContainer.selectAll('.node').classed('dimmed', false);
  gContainer.selectAll('.link-group path').classed('dimmed', false).classed('edge--flow', false);
}

function showBreadcrumb(pathIds, fromName, toName, container) {
  const bc = h('div', { class: 'path-breadcrumb' });
  pathIds.forEach((id, i) => {
    const fn = S.simNodes.find(n => n.id === id);
    const name = fn ? fn.name : String(id);
    bc.appendChild(h('span', { class: 'hop', onclick: () => navigate(name) }, [name]));
    if (i < pathIds.length - 1) bc.appendChild(h('span', { class: 'sep' }, ['▸']));
  });
  container.innerHTML = '';
  container.appendChild(bc);
}

// ── Module view ──────────────────────────────────────────────────────────
async function renderModule(moduleId) {
  document.getElementById('hint-card').style.display = 'none';
  clearBackChip();
  S.pathMode = false;

  try {
    const data = await api(`/api/graph/module?module_id=${moduleId}`);
    const { nodes, edges } = data;

    if (nodes.length === 0) {
      clearGraph();
      const stage = document.getElementById('stage');
      const old = stage.querySelector('.empty-state');
      if (old) old.remove();
      const modPath = (S.allModules.find(m => m.id === moduleId) || {}).path || `module ${moduleId}`;
      stage.appendChild(h('div', { class: 'empty-state', style: 'position:absolute;inset:0' }, [
        `No functions indexed in ${modPath.replace(/^.*\//, '')}.`
      ]));
      return;
    }

    if (!gContainer) {
      const init = initSvg();
      gContainer = init.g;
      gZoom = init.zoom;
    } else {
      gContainer.selectAll('*').remove();
      if (S.sim) { S.sim.stop(); S.sim = null; }
    }

    updateStatusbar(`${nodes.length} nodes · ${edges.length} edges · module view`);

    S.simNodes = nodes.map(n => ({ ...n }));
    S.simEdges = edges;

    const { backEdges } = computeLayers(S.simNodes, edges);

    const nodeById = new Map(S.simNodes.map(n => [n.id, n]));
    const linkData = edges.map(e => ({
      ...e,
      source: nodeById.get(e.caller_id) || e.caller_id,
      target: nodeById.get(e.callee_id) || e.callee_id,
      isBack: backEdges.has(`${e.caller_id}-${e.callee_id}`),
    }));

    // Draw static layered layout
    const g = gContainer;

    // Links
    g.selectAll('.link-group').data(linkData).enter()
      .append('g').attr('class', 'link-group')
      .append('path')
      .attr('class', d => (d.isBack ? 'link may' : linkClass(d.kind)) + (d.isBack ? ' back-edge' : ''))
      .attr('marker-end', d => d.isBack ? '' : arrowId(d.kind))
      .attr('d', d => {
        const s = d.source, t = d.target;
        if (!s || !t || s.fx == null) return '';
        if (d.isBack) {
          const mx = Math.max(s.fx, t.fx) + 60;
          return `M${s.fx},${s.fy}C${mx},${s.fy} ${mx},${t.fy} ${t.fx},${t.fy}`;
        }
        return edgePath(s, t, false, nodeRadius(t));
      });

    // Nodes
    const nodeGrp = g.selectAll('.node').data(S.simNodes, d => d.id)
      .enter().append('g')
      .attr('class', 'node')
      .attr('transform', d => `translate(${d.fx || 0},${d.fy || 0})`)
      .on('click', (event, d) => { event.stopPropagation(); renderPanel(d); });

    nodeGrp.append('circle')
      .attr('r', d => nodeRadius(d))
      .attr('fill', d => modColor(d.module_id))
      .attr('stroke', d => d.exposed ? 'white' : modColor(d.module_id))
      .attr('stroke-width', d => d.exposed ? 2 : 1)
      .attr('opacity', d => d.exposed ? 1.0 : 0.6);

    nodeGrp.append('text')
      .attr('dy', d => nodeRadius(d) + 11)
      .attr('text-anchor', 'middle')
      .text(d => d.name.length > 18 ? d.name.slice(0, 16) + '…' : d.name);

    // Auto-fit
    setTimeout(() => fitView(g, gZoom || d3.zoom()), 50);

    // Sync module select
    const sel = document.getElementById('module-view-select');
    sel.value = String(moduleId);

  } catch (e) {
    console.error(e);
  }
}

function computeLayers(nodes, edges) {
  const visited = new Set(), stack = new Set(), backEdges = new Set();

  function dfs(id) {
    visited.add(id); stack.add(id);
    for (const e of edges.filter(e => e.caller_id === id)) {
      if (stack.has(e.callee_id)) {
        backEdges.add(`${e.caller_id}-${e.callee_id}`);
      } else if (!visited.has(e.callee_id)) {
        dfs(e.callee_id);
      }
    }
    stack.delete(id);
  }
  nodes.forEach(n => { if (!visited.has(n.id)) dfs(n.id); });

  const memo = {};
  const dagEdges = edges.filter(e => !backEdges.has(`${e.caller_id}-${e.callee_id}`));

  function getLayer(id) {
    if (id in memo) return memo[id];
    const incoming = dagEdges.filter(e => e.callee_id === id);
    memo[id] = incoming.length === 0 ? 0 :
      1 + Math.max(...incoming.map(e => getLayer(e.caller_id)));
    return memo[id];
  }

  nodes.forEach(n => { n._layer = getLayer(n.id); });

  const byLayer = {};
  nodes.forEach(n => {
    byLayer[n._layer] = byLayer[n._layer] || [];
    byLayer[n._layer].push(n);
  });

  const LAYER_H = 90, NODE_W = 130;
  const stageW = W || 800;
  Object.entries(byLayer).forEach(([l, ns]) => {
    const totalW = ns.length * NODE_W;
    const startX = stageW / 2 - totalW / 2;
    ns.forEach((n, i) => {
      n.fx = startX + i * NODE_W + NODE_W / 2;
      n.fy = 60 + parseInt(l) * LAYER_H;
    });
  });

  return { backEdges };
}

// ── Back chip ─────────────────────────────────────────────────────────────
function clearBackChip() {
  const chip = document.getElementById('back-chip');
  if (chip) chip.remove();
}

// ── Legend interaction ────────────────────────────────────────────────────
document.querySelectorAll('.legend__row').forEach(row => {
  row.addEventListener('click', () => {
    row.classList.toggle('inactive');
    const kind = row.dataset.kind;
    if (kind === 'MUST') S.kindFilter.MUST = !S.kindFilter.MUST;
    else if (kind === 'MAY_ENUMERATED') S.kindFilter.MAY_ENUMERATED = !S.kindFilter.MAY_ENUMERATED;
    else if (kind === 'MAY_TOP') S.kindFilter.MAY_TOP = !S.kindFilter.MAY_TOP;
    if (gContainer) {
      gContainer.selectAll('.link-group').style('display', d => {
        const k = d.kind || 'MUST';
        return S.kindFilter[k] ? null : 'none';
      });
    }
  });
});

// ── Filter event listeners ────────────────────────────────────────────────
document.getElementById('module-filter').addEventListener('change', e => {
  S.filters.module_id = e.target.value || null;
  applyFilters();
});
document.getElementById('exposed-filter').addEventListener('change', e => {
  S.filters.exposed = e.target.checked;
  applyFilters();
});
document.getElementById('score-filter').addEventListener('input', e => {
  S.filters.min_score = parseInt(e.target.value);
  document.getElementById('score-value').textContent = e.target.value;
  applyFilters();
});

// ── View toggle buttons ───────────────────────────────────────────────────
document.getElementById('btn-neighborhood').addEventListener('click', () => {
  if (S.focus) navigate(S.focus, S.depth);
  else { S.view = 'neighborhood'; showNeighborhoodControls(); }
});
document.getElementById('btn-module').addEventListener('click', () => {
  S.view = 'module'; showModuleControls();
  const firstModule = S.allModules[0];
  if (firstModule) navigateModule(firstModule.id);
});

// ── Depth buttons ─────────────────────────────────────────────────────────
document.querySelectorAll('.depth-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.depth-btn').forEach(b => b.classList.remove('depth-btn--active'));
    btn.classList.add('depth-btn--active');
    S.depth = parseInt(btn.dataset.depth);
    if (S.focus) navigate(S.focus, S.depth);
  });
});

// ── Panel close ───────────────────────────────────────────────────────────
document.getElementById('panel-close').addEventListener('click', closePanel);

// ── Keyboard shortcuts ────────────────────────────────────────────────────
document.addEventListener('keydown', (e) => {
  const tag = document.activeElement.tagName.toLowerCase();
  const isInput = tag === 'input' || tag === 'textarea' || tag === 'select';

  if (e.key === '?') {
    document.getElementById('shortcuts-overlay').hidden = false;
    return;
  }
  if (e.key === 'Escape') {
    document.getElementById('shortcuts-overlay').hidden = true;
    closePanel();
    clearPathHighlight();
    return;
  }
  if (isInput) return;

  switch (e.key) {
    case '/':
      e.preventDefault();
      document.getElementById('search').focus();
      break;
    case 'f':
      if (gContainer && gZoom) fitView(gContainer, gZoom);
      break;
    case '[':
      S.sidebarVisible = !S.sidebarVisible;
      document.getElementById('sidebar').classList.toggle('collapsed', !S.sidebarVisible);
      break;
    case '1': case '2': case '3': {
      const d = parseInt(e.key);
      document.querySelectorAll('.depth-btn').forEach(b => {
        b.classList.toggle('depth-btn--active', parseInt(b.dataset.depth) === d);
      });
      S.depth = d;
      if (S.focus) navigate(S.focus, d);
      break;
    }
    case 'n':
      if (S.focus) navigate(S.focus, S.depth);
      break;
    case 'm':
      S.view = 'module'; showModuleControls();
      if (S.allModules.length > 0) navigateModule(S.allModules[0].id);
      break;
    case 'j': {
      const rows = document.querySelectorAll('.ftrow');
      const sel = document.querySelector('.ftrow.selected');
      const idx = sel ? [...rows].indexOf(sel) : -1;
      if (idx < rows.length - 1) {
        if (sel) sel.classList.remove('selected');
        rows[idx + 1].classList.add('selected');
        rows[idx + 1].scrollIntoView({ block: 'nearest' });
      }
      break;
    }
    case 'k': {
      const rows = document.querySelectorAll('.ftrow');
      const sel = document.querySelector('.ftrow.selected');
      const idx = sel ? [...rows].indexOf(sel) : rows.length;
      if (idx > 0) {
        if (sel) sel.classList.remove('selected');
        rows[idx - 1].classList.add('selected');
        rows[idx - 1].scrollIntoView({ block: 'nearest' });
      }
      break;
    }
    case 'Enter': {
      const sel = document.querySelector('.ftrow.selected');
      if (sel) sel.click();
      break;
    }
    case 'r':
      document.querySelector('.panel-reaches-form input')?.focus();
      break;
  }
});

// ── Window resize ─────────────────────────────────────────────────────────
window.addEventListener('resize', () => {
  if (gContainer) {
    getStageDims();
    svg.attr('width', W).attr('height', H);
    if (S.sim) {
      S.sim.force('center', d3.forceCenter(W / 2, H / 2));
      S.sim.force('x', d3.forceX(W / 2).strength(0.04));
      S.sim.force('y', d3.forceY(H / 2).strength(0.04));
    }
  }
});

// ── Init ──────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', boot);
