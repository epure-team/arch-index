'use strict';
// Independent evidence collector; no product/comparison resolver is imported.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const tezos = '/home/mathias/dev/tezos/tezos';
const reportDir = path.join(root, 'improvement/2026-09-14-tezos-resolution/2026-09-13T22-46-20-980Z-candidate-993803');
const manifestFile = path.join(root, 'roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv');
const hash = (b, alg = 'sha256') => crypto.createHash(alg).update(b).digest('hex');
const manifestBytes = fs.readFileSync(manifestFile);
if (hash(manifestBytes) !== '9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1') throw Error('manifest changed');
const changes = JSON.parse(fs.readFileSync(path.join(reportDir, 'changes.json')));
const provenance = JSON.parse(fs.readFileSync(path.join(reportDir, 'provenance.json')));
const manifest = manifestBytes.toString().split('\n').filter(l => l && !l.startsWith('#')).map(l => {const [slice, sha256, cmt] = l.split('\t'); return {slice, sha256, cmt};});
const grouped = new Map();
for (const g of changes.changed_groups) {
  const k = JSON.stringify(g.key.slice(0, 3));
  if (!grouped.has(k)) grouped.set(k, {key: g.key.slice(0, 3), old: [], new: [], exact_group_keys: []});
  const b = grouped.get(k); b.old.push(...g.old); b.new.push(...g.new); b.exact_group_keys.push(g.key);
}
const files = [...new Set([...grouped.values()].map(g => g.key[0]))];
const native = new Map(), artifacts = [];
const probe = process.argv[2];
if (!probe) throw Error('usage: node uid-witness.js /tmp/owned/probe');
for (const source of files) {
  const dirname = path.dirname(source), stem = path.basename(source, '.ml').toLowerCase();
  const selected = manifest.filter(m => m.cmt.startsWith(`${tezos}/_build/default/${dirname}/.`) &&
    path.basename(m.cmt, '.cmt').toLowerCase().split('__').at(-1) === stem);
  if (selected.length !== 1) throw Error(`ambiguous selected artifact for ${source}: ${selected.length}`);
  const m = selected[0], before = hash(fs.readFileSync(m.cmt));
  if (before !== m.sha256) throw Error(`CMT changed ${m.cmt}`);
  const x = JSON.parse(cp.execFileSync(probe, [m.cmt], {maxBuffer: 256 * 1024 * 1024}));
  if (hash(fs.readFileSync(m.cmt)) !== before) throw Error('CMT changed during reading');
  const recordedSource = path.resolve(x.builddir, x.source);
  const compiledSource = x.builddir === '/workspace_root' ? path.join(tezos, '_build/default', x.source) : recordedSource;
  const original = path.join(tezos, source), buildOriginal = path.join(tezos, '_build/default', source);
  const sourceDigestMatches = fs.existsSync(compiledSource) && hash(fs.readFileSync(compiledSource), 'md5') === x.source_digest;
  const sourceMatchesBuildCopy = fs.existsSync(original) && fs.existsSync(buildOriginal) && hash(fs.readFileSync(original)) === hash(fs.readFileSync(buildOriginal));
  const a = {...m, source, recorded_compiled_source: recordedSource, compiled_source: compiledSource, cmt_source_digest: x.source_digest,
    source_digest_matches: sourceDigestMatches, original_matches_build_copy: sourceMatchesBuildCopy,
    original_sha256: fs.existsSync(original) ? hash(fs.readFileSync(original)) : null,
    uid_to_decl_count: x.uid_to_decl_count, occurrence_count: x.occurrence_count};
  artifacts.push(a); native.set(source, {...x, artifact: a});
}
const sameSpan = (l, r, prefix) => l.file === r[`${prefix}_path`] && l.start === r[`${prefix}_line_start`] && l.end === r[`${prefix}_line_end`];
const evidenceBindings = id => {
  const all = [...id.val_uid_bindings, ...id.occurrences.flatMap(o => o.resolved_bindings)];
  const unique = [...new Map(all.map(b => [JSON.stringify([b.uid, b.binding_loc]), b])).values()];
  if (unique.length > 1) throw Error(`ambiguous native endpoint before DB target matching: ${id.path} at ${JSON.stringify(id.loc)}`);
  return unique;
};
const rowCore = r => JSON.stringify(Object.fromEntries(Object.entries(r).filter(([k]) => !k.endsWith('_line_start') && !k.endsWith('_line_end'))));
const difference = (a,b) => {const count=new Map(); for(const x of b)count.set(rowCore(x),(count.get(rowCore(x))||0)+1);return a.filter(x=>{const k=rowCore(x),n=count.get(k)||0;if(n){count.set(k,n-1);return false;}return true;});};
const witnesses = [];
for (const g of grouped.values()) {
  const removed = difference(g.old,g.new), added = difference(g.new,g.old);
  const old = removed.filter(r => r.kind === 'MAY_TOP' && r.top_reason === 'module_param');
  const targets = added.filter(r => r.kind === 'MAY_ENUMERATED' && r.target_path === r.caller_path);
  const residuals = added.filter(r => r.callee_name === '*TOP*' && r.top_reason === 'callback_param');
  const x = native.get(g.key[0]), line = Number(g.key[2].split(':').at(-1));
  const findings = [], assignments = [], available = new Set(targets.map((_,i)=>i));
  for (const display of [...new Set(old.map(r => r.callee_name))]) {
    const rows = old.filter(r => r.callee_name === display);
    const ids = x.identifiers.filter(i => i.loc.file === g.key[0] && i.path === display &&
      (i.loc.start === line || i.callback_contexts.some(c=>c.application_loc.file===g.key[0] && c.application_loc.start===line) ||
       x.applications.some(a=>a.loc.file===g.key[0] && a.loc.start===line && a.head_loc.start_offset===i.loc.start_offset && a.head_loc.end_offset===i.loc.end_offset)));
    const detail = {old_callee: display, old_rows: rows.length, old_row_records:rows, native_occurrences: ids.length, identifiers: ids, matches: []};
    if (ids.length !== rows.length) findings.push(`identifier multiplicity ${display}: ${ids.length} != ${rows.length}`);
    for (const [ordinal,id] of ids.entries()) {
      const bindings = evidenceBindings(id).filter(b => b.arity > 0);
      const eligible = [...available].filter(i => targets[i].edge_form === rows[ordinal]?.edge_form && bindings.some(b => sameSpan(b.binding_loc, targets[i], 'target') || sameSpan(b.body_loc, targets[i], 'target')));
      const distinct = [...new Set(eligible.map(i => JSON.stringify([targets[i].target,targets[i].target_line_start,targets[i].target_line_end])))];
      if (distinct.length !== 1) {findings.push(`UID endpoint matches ${distinct.length} distinct remaining DB bodies for ${display} at offset ${id.loc.start_offset}`);continue;}
      const ti = eligible[0]; available.delete(ti);
      const bs = bindings.filter(b => sameSpan(b.binding_loc,targets[ti],'target') || sameSpan(b.body_loc,targets[ti],'target'));
      const sourceBodies = x.bindings.filter(b => b.arity > 0 && (sameSpan(b.binding_loc,targets[ti],'target') || sameSpan(b.body_loc,targets[ti],'target')));
      if (sourceBodies.length !== 1) findings.push(`target range has ${sourceBodies.length} native body anchors for ${targets[ti].target}`);
      const appliedHeads = x.applications.filter(a => a.head_loc.file === id.loc.file && a.head_loc.start_offset === id.loc.start_offset && a.head_loc.end_offset === id.loc.end_offset);
      detail.matches.push({before:rows[ordinal],identifier_offset:id.loc.start_offset,identifier_loc:id.loc,target:targets[ti],uid_bindings:bs,applied_heads:appliedHeads});
    }
    assignments.push(detail);
  }
  if (available.size) findings.push(`${available.size} target rows unmatched`);
  const representative = old[0] || targets[0] || residuals[0];
  const callerBindings = representative ? x.bindings.filter(b => sameSpan(b.binding_loc,representative,'caller') || sameSpan(b.body_loc,representative,'caller')) : [];
  const callerFunctions = representative ? x.functions.filter(l => sameSpan(l,representative,'caller')) : [];
  // Caller source ranges remain evidence, never an invented ordinal-level proof.
  if (!callerBindings.length && !callerFunctions.length) findings.push('caller range has no exact native binding/function anchor');
  if (callerBindings.length > 1 || (!callerBindings.length && callerFunctions.length > 1)) findings.push('caller source range has ambiguous native anchors');
  const callerAnchor = callerBindings.length === 1 ? callerBindings[0].body_loc : callerFunctions.length === 1 ? callerFunctions[0] : null;
  if (callerAnchor) for (const a of assignments) for (const id of a.identifiers) {
    if (id.loc.start_offset < callerAnchor.start_offset || id.loc.end_offset > callerAnchor.end_offset)
      findings.push(`identifier offset ${id.loc.start_offset} outside native caller anchor`);
  }
  const residualEvidence = [];
  if (residuals.length) {
    const applications = x.applications.filter(a => a.loc.file === g.key[0] && a.loc.start === line).flatMap(a => {
      const bs = evidenceBindings(a).filter(b => b.arity > 0 && a.supplied > b.arity && targets.some(t=>sameSpan(b.binding_loc,t,'target')||sameSpan(b.body_loc,t,'target')));
      return bs.length ? [{application:a,overapplied_bindings:bs}] : [];
    });
    residualEvidence.push(...applications);
    if (applications.length !== residuals.length) findings.push(`return residual multiplicity: ${applications.length} overapplications != ${residuals.length} new TOP rows`);
  }
  if (!x.artifact.source_digest_matches || !x.artifact.original_matches_build_copy) findings.push('source digest/build copy mismatch');
  witnesses.push({...g,removed,added,assignments,caller_bindings:callerBindings,caller_functions:callerFunctions,residuals:residualEvidence,
    status: findings.length ? 'unknown_or_ambiguous' : 'uid_endpoint_and_multiplicity_witnessed', findings});
}
const sum = arr => arr.reduce((a,b)=>a+b,0);
const covered = witnesses.filter(w => !w.findings.length), unknown = witnesses.filter(w => w.findings.length);
const result = {
  schema_version:1, purpose:'Independent compiler UID endpoint evidence, not approval or a general local-module eligibility oracle',
  provenance, input_sha256:Object.fromEntries(['changes.json','report.json','provenance.json'].map(f=>[f,hash(fs.readFileSync(path.join(reportDir,f)))])),
  probe_sha256:hash(fs.readFileSync(path.join(__dirname,'uid-witness.ml'))), runner_sha256:hash(fs.readFileSync(__filename)),
  manifest_sha256:hash(manifestBytes), artifacts,
  summary:{exact_changed_groups:changes.changed_groups.length, site_buckets:witnesses.length,
    witnessed_site_buckets:covered.length, unknown_site_buckets:unknown.length,
    witnessed_old_rows:sum(covered.map(w=>w.removed.filter(r=>r.top_reason==='module_param').length)),
    unknown_old_rows:sum(unknown.map(w=>w.removed.filter(r=>r.top_reason==='module_param').length)),
    witnessed_residual_rows:sum(covered.map(w=>w.added.filter(r=>r.callee_name==='*TOP*').length)),
    unknown_residual_rows:sum(unknown.map(w=>w.added.filter(r=>r.callee_name==='*TOP*').length)),
    findings:unknown.map(w=>({key:w.key,findings:w.findings}))}, witnesses
};
const output = process.argv[3] || path.join(root,'improvement/2026-09-14-tezos-resolution/attempt1-uid-evidence-v2.json');
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({...result.summary,findings:result.summary.findings.slice(0,15)},null,2));
