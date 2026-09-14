#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const b=require('../tezos-residual-targets/baseline.js');
const frozen=require('./prepare-baseline.js');
const {snapshotDatabase,compareSnapshots,ComparisonInputError}=require('./comparison.js');
function loadFrozen() {
  const file=path.join(frozen.directory,'provenance.json');
  const record=JSON.parse(fs.readFileSync(file));
  frozen.validateRecord(record);frozen.checkArtifacts(record);
  return {record,hash:b.fileSha256(file)};
}
function sourceHashes() {
  const files=['lib/arch_index/arch_index_cmt.ml','lib/arch_index/call_graph_extractor.ml',
    'roster/tezos-open-bodies/comparison.js','roster/tezos-open-bodies/verify.js',
    'roster/tezos-open-bodies/open-body-witness.ml','roster/tezos-open-bodies/run-probe.js',
    'roster/tezos-open-bodies/prepare-baseline.js','roster/tezos-open-bodies/witness.js'];
  return Object.fromEntries(files.map(p=>[p,fs.existsSync(path.join(b.ROOT,p))
    ?b.fileSha256(path.join(b.ROOT,p)):null]));
}
function candidate(witnessFile) {
  const state=frozen.state(),sources=sourceHashes(),baselineRecord=loadFrozen();
  const producerHash=b.fileSha256(b.CURRENT_PRODUCER),schemaHash=b.fileSha256(b.CURRENT_SCHEMA);
  if(schemaHash!==frozen.expected.schemaSha256)throw new ComparisonInputError('candidate schema changed');
  const manifest=b.readManifest();
  const old=snapshotDatabase(baselineRecord.record.db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
  b.validateSnapshot(old,frozen.expected);
  const output=fs.mkdtempSync(path.join(b.ROOT,'improvement/2026-09-14-tezos-resolution/attempt3-candidate-'));
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-body-candidate-'));
  try {
    const db=path.join(temp,'candidate.db');
    b.produce(b.CURRENT_PRODUCER,b.CURRENT_SCHEMA,db,b.makeSelection(temp,manifest));
    const next=snapshotDatabase(db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
    const witness=witnessFile?require('./witness.js').loadWitness(witnessFile,old,next,manifest)
      :{transitions:[],residuals:[],sha256:null};
    const result=compareSnapshots(old,next,{approvedTransitions:witness.transitions,approvedResiduals:witness.residuals});
    b.readManifest();
    if(loadFrozen().hash!==baselineRecord.hash||b.fileSha256(b.CURRENT_PRODUCER)!==producerHash
      ||b.fileSha256(b.CURRENT_SCHEMA)!==schemaHash||JSON.stringify(sourceHashes())!==JSON.stringify(sources))
      throw new ComparisonInputError('frozen baseline, source or producer changed during comparison');
    b.assertStateUnchanged(state,frozen.state());
    const changedSites=new Set([...result.changes.removed,...result.changes.added]
      .map(r=>JSON.stringify([r.caller_path,r.caller,r.call_site])));
    const changed=rows=>rows.filter(r=>changedSites.has(JSON.stringify([r.caller_path,r.caller,r.call_site])));
    const provenance={created_at:new Date().toISOString(),baseline_digest:old.digest,
      baseline_provenance_sha256:baselineRecord.hash,candidate_digest:next.digest,
      candidate_rows:next.row_count,producer_sha256:producerHash,schema_sha256:schemaHash,
      manifest_sha256:frozen.expected.manifestSha256,selected:410,source_hashes:sources,
      state,witness_file:witnessFile,witness_sha256:witness.sha256,
      source_status_unchanged:true,input_hashes_unchanged:true};
    fs.writeFileSync(path.join(output,'changes.json'),JSON.stringify({...result.changes,
      before_positioned:changed(old.positioned_rows),after_positioned:changed(next.positioned_rows)},null,2)+'\n',{flag:'wx'});
    fs.writeFileSync(path.join(output,'provenance.json'),JSON.stringify(provenance,null,2)+'\n',{flag:'wx'});
    const report={verdict:result.ok?'PASS':'REFUSE',retention_authorized:false,
      witnessed:!!witnessFile,classification:result.neutral?'neutral':'candidate',
      summary:result.summary,slices:result.slices,errors:result.errors,
      baseline_digest:old.digest,candidate_digest:next.digest,output};
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
    console.log(JSON.stringify({...report,errors:report.errors.slice(0,5)},null,2));
    return result.ok?0:1;
  } finally {fs.rmSync(temp,{recursive:true});}
}
if(require.main===module) {
  try {
    const args=process.argv.slice(2);
    if(args.length===0)process.exitCode=candidate(null);
    else if(args.length===2&&args[0]==='--witness')process.exitCode=candidate(path.resolve(args[1]));
    else throw new ComparisonInputError('usage: verify.js [--witness FILE]');
  } catch(e){console.error('OPEN_BODY_VERIFY_SETUP:',e.stack||e);process.exitCode=2;}
}
module.exports={candidate};
