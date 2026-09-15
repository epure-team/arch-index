'use strict';
/* Compile and run the compiler-only recursive witness.  This wrapper is an
   input/provenance boundary, not a product or database oracle. */
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const source=path.join(__dirname,'recursive-witness.ml');
const sha256=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function checked(command,args,cwd){
  const r=cp.spawnSync(command,args,{cwd,encoding:'utf8',timeout:120000,maxBuffer:512*1024*1024});
  if(r.error||r.signal||r.status!==0)
    throw Error(`${command} recursive witness setup ${r.status}: ${r.error||r.signal||r.stderr}`);
  return r.stdout;
}
function probeRecords(files){
  if(!Array.isArray(files)||files.length===0||new Set(files).size!==files.length)
    throw Error('nonempty unique native CMT input list required');
  for(const file of files)
    if(typeof file!=='string'||!path.isAbsolute(file)||!file.endsWith('.cmt')||!fs.statSync(file).isFile())
      throw Error('probe input must be an absolute regular CMT file');
  const inputHashes=files.map(sha256),sourceHash=sha256(source);
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-recursive-open-witness-'));
  try{
    fs.copyFileSync(source,path.join(temp,'recursive_witness.ml'),fs.constants.COPYFILE_EXCL);
    const binary=path.join(temp,'probe');
    const compiler=['ocamlfind','ocamlopt','-package','compiler-libs.common','-linkpkg',
      '-o',binary,'recursive_witness.ml'];
    if(fs.existsSync(path.join(root,'_opam')))
      checked('opam',['exec',`--switch=${root}`,'--',...compiler],temp);
    else checked(compiler[0],compiler.slice(1),temp);
    const records=JSON.parse(checked(binary,files,temp));
    if(!Array.isArray(records)||records.length!==files.length)
      throw Error('native witness did not return exactly one record per input');
    records.forEach((record,index)=>{
      if(record.schema_version!=='recursive-open-witness-v1'||record.cmt!==files[index])
        throw Error('native witness schema/input ordering mismatch');
      if(sha256(files[index])!==inputHashes[index]) throw Error('CMT changed during native witness');
    });
    if(sha256(source)!==sourceHash) throw Error('witness source changed during execution');
    return records;
  }finally{fs.rmSync(temp,{recursive:true,force:true});}
}
module.exports={probeRecords};
if(require.main===module){
  try{console.log(JSON.stringify(probeRecords(process.argv.slice(2))));}
  catch(error){console.error('RECURSIVE_WITNESS_SETUP:',error.stack||error);process.exitCode=2;}
}
