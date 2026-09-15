#!/usr/bin/env node
'use strict';
// Fresh 2x2 attribution only. Never changes a reference or a ratchet constant.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const cp=require('node:child_process'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'improvement/2026-09-15-ocaml-cfa/calibration');
function run(bin,args,cwd=root) {
  const r=cp.spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:64*1024*1024});
  if(r.error||r.status!==0) throw new Error(`${bin} ${args.join(' ')}: ${r.error||r.status}\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const status=()=>run('git',['status','--porcelain=v1','--untracked-files=all']);
const lines=x=>x.trim().split('\n').filter(Boolean);
const manifest=fs.readFileSync(path.join(root,'briefs/ocaml-data-preservation-manifest.txt'),'utf8').split('\n');
const excluded=new Set(manifest.filter(x=>x.startsWith('dirty=')).map(x=>x.slice(6)));
const entries=manifest.slice(manifest.indexOf('---')+1).filter(Boolean);
const inScope=f=>!excluded.has(f)&&entries.some(e=>e.endsWith('/')?f.startsWith(e):f===e);
const files=[...new Set([...lines(run('git',['diff','--name-only','HEAD'])),...lines(run('git',['ls-files','--others','--exclude-standard']))])].filter(inScope).sort();
for(const f of files) if(path.isAbsolute(f)||f.split('/').includes('..')) throw new Error('unsafe snapshot path');
const inventory=files.map(file=>({file,sha256:sha(fs.readFileSync(path.join(root,file)))}));
const before=status(),base=run('git',['rev-parse','HEAD']).trim();
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'evidence.json'),JSON.stringify({verdict:'RUNNING'})+'\n');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-data-calibration-'));
const trees=[path.join(temporary,'base'),path.join(temporary,'candidate')],made=[];
const evidence={base,snapshot:inventory,snapshot_sha256:sha(JSON.stringify(inventory)),cells:{},temporary};
function query(db,sql){return JSON.parse(run('sqlite3',['-readonly','-json',db,sql])||'[]');}
try {
  for(const tree of trees){run('git',['worktree','add','--detach',tree,base]);made.push(tree);}
  for(const file of files){const dst=path.join(trees[1],file);fs.mkdirSync(path.dirname(dst),{recursive:true});fs.copyFileSync(path.join(root,file),dst);}
  for(const [i,tree] of trees.entries()){
    console.log(`fresh build ${i}: ${tree}`);
    fs.writeFileSync(path.join(out,`build-${i}.log`),run('opam',['exec',`--switch=${root}`,'--','dune','build','--root','.'],tree));
  }
  for(const [scope,relative] of [['ceiling','_build/default'],['origin','_build/default/lib/arch_index']]){
    for(const [label,engine,corpus] of [['A',0,0],['B',1,0],['C',0,1],['D',1,1]]){
      console.log(`index ${scope}/${label}`);
      const db=path.join(temporary,`${scope}-${label}.db`);
      const exe=path.join(trees[engine],'_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
      const log=run(exe,['--build-dir',path.join(trees[corpus],relative),'--db-path',db,'--schema-path',path.join(trees[engine],'architecture-schema.sql')],trees[corpus]);
      fs.writeFileSync(path.join(out,`${scope}-${label}.log`),log);
      const totals=query(db,"SELECT (SELECT count(*) FROM modules) modules,(SELECT count(*) FROM functions) functions,(SELECT count(*) FROM calls) calls,(SELECT count(*) FROM exn_origins) origins,(SELECT count(*) FROM calls WHERE kind='MUST' AND callee_id IS NULL AND callee_name NOT LIKE 'Stdlib.%') must_null")[0];
      const groups=query(db,'SELECT channel,form,escapes,count(*) count FROM exn_origins GROUP BY channel,form,escapes ORDER BY channel,form,escapes');
      const modules=query(db,'SELECT path FROM modules ORDER BY path').map(x=>x.path);
      const calls=query(db,'SELECT caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form,count(*) n FROM calls GROUP BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form ORDER BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form');
      const external=query(db,"SELECT m.path,c.callee_name,count(*) n FROM calls c JOIN functions f ON f.id=c.caller_id JOIN modules m ON m.id=f.module_id WHERE c.kind='MUST' AND c.callee_id IS NULL AND c.callee_name NOT LIKE 'Stdlib.%' GROUP BY m.path,c.callee_name ORDER BY m.path,c.callee_name");
      evidence.cells[`${scope}-${label}`]={totals,groups,modules,calls_sha256:sha(JSON.stringify(calls)),external};
    }
  }
  for(const scope of ['ceiling','origin'])for(const [a,b]of [['A','B'],['C','D']])assert.deepEqual(evidence.cells[`${scope}-${a}`],evidence.cells[`${scope}-${b}`],`behavior delta ${scope}/${a}-${b}`);
  for(const entry of inventory)assert.equal(sha(fs.readFileSync(path.join(root,entry.file))),entry.sha256,`source changed: ${entry.file}`);
  assert.equal(status(),before,'active checkout changed during calibration');
  evidence.verdict='SOURCE_ONLY';
  fs.writeFileSync(path.join(out,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log(JSON.stringify({verdict:evidence.verdict,snapshot:evidence.snapshot_sha256,cells:Object.fromEntries(Object.entries(evidence.cells).map(([k,v])=>[k,v.totals]))}));
}finally{
  // Only exact worktrees created successfully by this invocation are removed.
  for(const tree of made.reverse())run('git',['worktree','remove','--force',tree]);
  assert.equal(path.dirname(temporary),os.tmpdir());assert(path.basename(temporary).startsWith('arch-data-calibration-'));
  fs.rmSync(temporary,{recursive:true});
  console.log(`removed owned worktrees and build artifacts: ${temporary}`);
}
