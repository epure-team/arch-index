#!/usr/bin/env node
'use strict';
/* A report over registry-gated evidence. It has no baseline and no gate: those
 * belong to the following consumer slice. */
const cp=require('child_process'), crypto=require('crypto'), path=require('path');
function fail(m){throw new Error(m)}
function canonical(v){if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])]));return v}
function digest(v){return crypto.createHash('sha256').update(JSON.stringify(canonical(v))).digest('hex')}
function report(sidecars){
  if(!sidecars||sidecars.schema_version!==1||sidecars.analysis!=='ffi_connector_sidecars'||typeof sidecars.registry_digest!=='string'||!Array.isArray(sidecars.connectors))fail('invalid registry sidecar envelope');
  const rows=sidecars.connectors.map(c=>{if(!c||typeof c.id!=='string'||typeof c.mechanism!=='string'||typeof c.status!=='string')fail('invalid connector result');return {id:c.id,mechanism:c.mechanism,version:c.version,status:c.status,reason:c.reason||null,summary:c.summary||null};}).sort((a,b)=>a.id.localeCompare(b.id));
  const count=status=>rows.filter(x=>x.status===status).length;
  const evidence={schema_version:1,analysis:'ffi_registry_report',registry_digest:sidecars.registry_digest,
    scope:'read-only registry-gated FFI evidence; no SQLite write, graph edge, reachability verdict, policy gate or MUST claim',
    connectors:rows,summary:{connectors:rows.length,computed:count('COMPUTED'),not_analysed:count('NOT_ANALYSED'),refused:count('REFUSED'),frontiers:count('FRONTIER')}};
  return {...evidence,report_digest:digest(evidence)};
}
function cli(){const a=process.argv.slice(2);if(a.length!==3||a[0]!=='--registry')fail('usage: ffi-registry-report.js --registry REGISTRY.json CORPUS_ROOT');const r=cp.spawnSync(process.execPath,[path.join(__dirname,'ffi-connector-sidecars.js'),'--registry',a[1],a[2]],{encoding:'utf8',maxBuffer:64*1024*1024});if(r.error||r.status!==0)fail('registry sidecars unavailable');let x;try{x=JSON.parse(r.stdout)}catch(_){fail('registry sidecars produced invalid JSON')}process.stdout.write(JSON.stringify(report(x),null,2)+'\n')}
if(require.main===module){try{cli()}catch(e){process.stderr.write(`ffi-registry-report: ${e.message}\n`);process.exitCode=2}}
module.exports={canonical,digest,report};
