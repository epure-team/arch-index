#!/usr/bin/env node
'use strict';
// Serialize the root's bounded endpoint review, not a roster GO/keep decision.
// Exact evidence bytes are pinned: this is not an auto-approval tool for new runs.
const fs = require('node:fs'), path = require('node:path');
const crypto = require('node:crypto'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const evidenceHash = '8811a7e0b1d93c25eb5e40c2f680112add0d54e2a7f764f1a2aa1668e094c909';
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const bag = rows => rows.map(r => JSON.stringify(r)).sort();
const span = (loc,row) => loc.file === row.target_path && loc.start === row.target_line_start && loc.end === row.target_line_end;
function main() {
  const [input, output, reviewer] = process.argv.slice(2);
  if (!input || !output || reviewer !== 'root-compiler-endpoint-review')
    throw Error('usage: reviewed-witness.js EVIDENCE OUTPUT root-compiler-endpoint-review');
  const raw = fs.readFileSync(input), x = JSON.parse(raw);
  assert.equal(hash(raw), evidenceHash, 'only the inspected evidence is approved');
  assert.equal(hash(fs.readFileSync(path.join(__dirname,'uid-witness.ml'))), x.probe_sha256);
  assert.equal(x.summary.unknown_site_buckets, 0);
  assert.equal(x.witnesses.length, 810);
  const inputDir = path.join(root,'improvement/2026-09-14-tezos-resolution/2026-09-13T22-46-20-980Z-candidate-993803');
  for (const [file, digest] of Object.entries(x.input_sha256))
    assert.equal(hash(fs.readFileSync(path.join(inputDir,file))), digest);
  for (const artifact of x.artifacts) {
    assert(artifact.source_digest_matches && artifact.original_matches_build_copy);
    assert.equal(hash(fs.readFileSync(artifact.cmt)), artifact.sha256);
    assert.equal(hash(fs.readFileSync(path.join('/home/mathias/dev/tezos/tezos',artifact.source))), artifact.original_sha256);
  }
  const reviewed_at = new Date().toISOString();
  const meta = detail => ({reviewed_by:reviewer, reviewed_at,
    source_evidence:`compiler UID evidence sha256:${evidenceHash}; ${detail}; structural policy separately covered by native tests; not roster approval`});
  const transitions = [], residuals = [];
  for (const w of x.witnesses) {
    assert.deepEqual(w.findings, []);
    const matches = w.assignments.flatMap(a => {
      assert.equal(a.matches.length, a.old_rows);
      assert.equal(a.identifiers.length, a.old_rows);
      const remaining = [...a.identifiers];
      for (const m of a.matches) {
        const ids = remaining.filter(id => same(id.loc,m.identifier_loc));
        assert(ids.length > 0 && ids.every(id => same(id,ids[0])), 'unambiguous native occurrence multiset');
        remaining.splice(remaining.indexOf(ids[0]),1);
        assert.equal(m.uid_bindings.length, 1, 'unique native target binding');
        const b = m.uid_bindings[0];
        assert(b.arity > 0 && (span(b.binding_loc,m.target) || span(b.body_loc,m.target)));
        assert(ids[0].occurrences.some(o => o.result.kind === 'Resolved'
          && o.resolved_bindings.some(found => same(found,b))), 'compiler resolved body');
        assert(ids[0].occurrences.flatMap(o=>o.resolved_bindings).every(found=>same(found,b)), 'no competing resolved endpoint');
        assert(ids[0].val_uid_bindings.every(found=>same(found,b)), 'direct UID agrees when available');
        assert.equal(m.before.edge_form,m.target.edge_form);
        transitions.push({before:m.before, after:m.target,
          ...meta(`${w.key[0]} offset ${m.identifier_offset}; body ${b.uid} at ${b.body_loc.start}:${b.body_loc.column}`)});
      }
      assert.equal(remaining.length,0);
      return a.matches;
    });
    assert.deepEqual(bag(matches.map(m=>m.before)),bag(w.removed), 'every removed occurrence reviewed');
    const tops = w.added.filter(r=>r.kind==='MAY_TOP');
    assert.deepEqual(bag(matches.map(m=>m.target)),bag(w.added.filter(r=>r.kind!=='MAY_TOP')));
    assert.equal(tops.length,w.residuals.length);
    // Multiple identical TOP rows have no syntactic ordinal in the database.
    // Consume their multiplicity once per distinct native overapplication.
    const usedHeads = new Set();
    for (const [i,r] of w.residuals.entries()) {
      const app = r.application;
      const heads = matches.filter(m=>same(m.identifier_loc,app.head_loc)
        && m.applied_heads.some(a=>same(a,app)));
      assert.equal(heads.length,1,'unique consumed head for residual');
      const m = heads[0], b = m.uid_bindings[0];
      assert(!usedHeads.has(m)); usedHeads.add(m);
      assert(r.overapplied_bindings.some(found=>same(found,b)));
      assert(Number.isInteger(app.supplied) && app.supplied>b.arity);
      const after = tops[i];
      assert.equal(after.call_site,`${app.loc.file}:${app.loc.start}`);
      assert.equal(after.top_anchor,after.call_site);
      assert.equal(after.top_reason,'callback_param');
      assert.equal(after.callee_name,'*TOP*');
      residuals.push({after,head:{before:m.before,after:m.target},arity:b.arity,arguments:app.supplied,
        ...meta(`${w.key[0]} application offset ${app.loc.start_offset}; body ${b.uid}; supplied ${app.supplied} > arity ${b.arity}`)});
    }
  }
  assert.equal(transitions.length,831); assert.equal(residuals.length,34);
  const result = {baseline_digest:x.provenance.baseline_digest,candidate_digest:x.provenance.candidate_digest,
    retention_authorized:false,evidence_sha256:evidenceHash,transitions,residuals};
  fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
  console.log(`PASS exact reviewed witness: ${transitions.length} transitions, ${residuals.length} return residuals; no keep authorization`);
}
try { main(); } catch (error) {
  console.error(error.stack || error);
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
