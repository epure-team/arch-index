'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const source=path.join(__dirname,'open-body-witness.ml');
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function checked(command,args,cwd) {
  const r=cp.spawnSync(command,args,{cwd,encoding:'utf8',timeout:120000,maxBuffer:512*1024*1024});
  if(r.error||r.signal||r.status!==0)throw Error(`${command} probe setup ${r.status}: ${r.error||r.signal||r.stderr}`);
  return r.stdout;
}
function probeRecords(files) {
  if(!Array.isArray(files)||!files.length||new Set(files).size!==files.length)
    throw Error('nonempty unique native CMT input list required');
  for(const f of files)if(typeof f!=='string'||!path.isAbsolute(f)||!f.endsWith('.cmt')||!fs.statSync(f).isFile())
    throw Error('probe input must be an absolute CMT regular file');
  const hashes=files.map(hash),sourceHash=hash(source);
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-body-probe-'));
  try {
    fs.copyFileSync(source,path.join(temp,'open_body_witness.ml'),fs.constants.COPYFILE_EXCL);
    const binary=path.join(temp,'probe');
    const compiler=['ocamlfind','ocamlopt','-package','compiler-libs.common','-linkpkg',
      '-o',binary,'open_body_witness.ml'];
    if(fs.existsSync(path.join(root,'_opam')))
      checked('opam',['exec',`--switch=${root}`,'--',...compiler],temp);
    else checked(compiler[0],compiler.slice(1),temp);
    const records=JSON.parse(checked(binary,files,temp));
    if(!Array.isArray(records)||records.length!==files.length)
      throw Error('native probe did not return every input');
    records.forEach((record,i)=>{
      if(record.schema_version!=='open-body-witness-v2'||record.cmt!==files[i])
        throw Error('native probe schema/input ordering mismatch');
      if(hash(files[i])!==hashes[i])throw Error('CMT changed during native probe');
    });
    if(hash(source)!==sourceHash)throw Error('native probe source changed during execution');
    return records;
  } finally {fs.rmSync(temp,{recursive:true});}
}
module.exports={probeRecords};
if(require.main===module){
  try{console.log(JSON.stringify(probeRecords(process.argv.slice(2))));}
  catch(e){console.error('OPEN_BODY_PROBE_SETUP:',e.stack||e);process.exitCode=2;}
}
