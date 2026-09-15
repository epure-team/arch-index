#!/usr/bin/env node
'use strict';
// Attribution diagnostic, not an automatic permission to raise a ratchet.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const output=path.join(root,'improvement/2026-09-15-ocaml-cfa/self-source-growth');
const frozen=path.join(root,'improvement/2026-09-15-ocaml-cfa/stage1-baseline');
const current=path.join(root,'_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
function run(command,args){return cp.execFileSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:64*1024*1024});}
try {
  fs.mkdirSync(output,{recursive:true});
  const results={};
  for(const [name,producer] of [['old-engine',path.join(frozen,'producer.exe')],['new-engine',current]]) {
    const db=path.join(output,`${name}.db`);
    const log=run(producer,['--build-dir',path.join(root,'_build/default'),'--db-path',db,'--schema-path',path.join(root,'architecture-schema.sql')]);
    fs.writeFileSync(path.join(output,`${name}.log`),log);
    const callRows=JSON.parse(run('sqlite3',['-readonly','-json',db,'SELECT caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form,count(*) n FROM calls GROUP BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form ORDER BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form']));
    const external=JSON.parse(run('sqlite3',['-readonly','-json',db,"SELECT m.path,f.name,c.callee_name,count(*) AS n FROM calls c JOIN functions f ON f.id=c.caller_id JOIN modules m ON m.id=f.module_id WHERE c.kind='MUST' AND c.callee_id IS NULL AND c.callee_name NOT LIKE 'Stdlib.%' GROUP BY m.path,f.name,c.callee_name ORDER BY m.path,f.name,c.callee_name"]));
    results[name]={canonical_rows:callRows.reduce((n,x)=>n+x.n,0),canonical_sha256:crypto.createHash('sha256').update(JSON.stringify(callRows)).digest('hex'),must_null:external.reduce((n,x)=>n+x.n,0),external};
  }
  assert.deepEqual(results['new-engine'],results['old-engine'],'same current CMT corpus must be neutral between engines');
  const report={same_current_corpus:true,results,limitation:'same-source engine comparison; not a pristine two-source 2x2 calibration'};
  fs.writeFileSync(path.join(output,'evidence.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({ok:true,...results['new-engine'],external:undefined}));
}catch(error){console.error(error.stack);process.exitCode=error instanceof assert.AssertionError?1:2;}
