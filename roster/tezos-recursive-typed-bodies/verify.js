#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const b=require('./baseline.js');
const {snapshotDatabase,compareSnapshots,ComparisonInputError}=require('./comparison.js');

function candidate(witnessFile) {
  const state=b.state(),baselineRecord=b.loadFrozen();
  const producerHash=b.fileSha256(b.CURRENT_PRODUCER),schemaHash=b.fileSha256(b.CURRENT_SCHEMA);
  if(schemaHash!==b.EXPECTED.schemaSha256)throw new ComparisonInputError('candidate schema changed');
  const manifest=b.readManifest({expected:b.EXPECTED});
  const old=b.frozenSnapshot(baselineRecord,manifest);
  const output=fs.mkdtempSync(path.join(b.ROOT,'improvement/2026-09-14-tezos-resolution/attempt5-candidate-'));
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-recursive-candidate-'));
  try {
    const db=path.join(temp,'candidate.db');
    b.produce(b.CURRENT_PRODUCER,b.CURRENT_SCHEMA,db,b.makeSelection(temp,manifest));
    const next=snapshotDatabase(db,{expectedArtifactSuffixes:manifest.destinationSuffixes});
    const witness=witnessFile?require('./witness.js').loadWitness(witnessFile,old,next,manifest)
      :{transitions:[],residuals:[],sha256:null};
    if(!Array.isArray(witness.transitions)||!Array.isArray(witness.residuals))
      throw new ComparisonInputError('native validator must return canonical permissions');
    const result=compareSnapshots(old,next,{approvedTransitions:witness.transitions,approvedResiduals:witness.residuals});
    b.readManifest({expected:b.EXPECTED});b.loadFrozen();
    if(b.fileSha256(b.CURRENT_PRODUCER)!==producerHash||b.fileSha256(b.CURRENT_SCHEMA)!==schemaHash)
      throw new ComparisonInputError('candidate producer or schema changed during comparison');
    b.assertStateUnchanged(state,b.state());
    const changedSites=new Set([...result.changes.removed,...result.changes.added]
      .map(r=>JSON.stringify([r.caller_path,r.caller,r.call_site])));
    const changed=rows=>rows.filter(r=>changedSites.has(JSON.stringify([r.caller_path,r.caller,r.call_site])));
    const provenance={created_at:new Date().toISOString(),baseline_digest:old.digest,
      baseline_provenance_sha256:b.PROVENANCE_SHA256,candidate_digest:next.digest,
      candidate_rows:next.row_count,producer_sha256:producerHash,schema_sha256:schemaHash,
      manifest_sha256:b.EXPECTED.manifestSha256,selected:manifest.records.length,
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
  } catch(e){console.error('LOCAL_RECURSIVE_VERIFY_SETUP:',e.stack||e);process.exitCode=2;}
}
module.exports={candidate};
