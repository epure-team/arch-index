'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');

function keys(object,names) { assert.deepEqual(Object.keys(object).sort(),names.split(' ').sort()); }
function census(r) {
  assert.equal(r.census.artifacts,r.inputs.length); assert.equal(r.census.total_sites,r.sites.length);
  const names={NONZERO:'nonzero',ZERO:'zero',MAY_ZERO:'may_zero',UNREACHABLE:'unreachable',UNSUPPORTED:'unsupported'};
  for (const [status,name] of Object.entries(names)) assert.equal(r.census[name],r.sites.filter(s=>s.status===status).length);
  assert.equal(r.census.numeric_covered,r.census.nonzero+r.census.zero+r.census.may_zero+r.census.unreachable);
  assert.equal(r.census.total_sites,r.census.numeric_covered+r.census.unsupported);
  assert.equal(r.census.precision_gain_sites,r.census.nonzero+r.census.unreachable);
}
function validateReport(r) {
  keys(r,'schema_version tool analysis outcome inputs sites census'); assert.equal(r.schema_version,1);
  keys(r.tool,'name version compiler_version int_bits'); assert.equal(r.tool.name,'arch-guard'); assert.equal(r.tool.version,'0.1.0');
  assert.equal(typeof r.tool.compiler_version,'string'); assert([31,63].includes(r.tool.int_bits));
  keys(r.analysis,'mode fragment domain assumptions limitations'); assert.equal(r.analysis.mode,'experimental-report-only');
  assert.equal(r.analysis.fragment,'ocaml-int-acyclic-v1'); assert.equal(r.analysis.domain,'constant-zero-v1');
  for (const list of [r.analysis.assumptions,r.analysis.limitations]) { assert(Array.isArray(list)); list.forEach(x=>assert.equal(typeof x,'string')); }
  assert.match(r.analysis.assumptions.join(' '),/trusted.*same-compiler.*same-target/); assert.match(r.analysis.limitations.join(' '),/no machine-checked proof/);
  assert.equal(r.outcome,r.sites.length?'classified':'empty_inventory');
  keys(r.census,'artifacts total_sites numeric_covered nonzero zero may_zero unreachable unsupported precision_gain_sites');
  Object.values(r.census).forEach(n=>assert(Number.isSafeInteger(n)&&n>=0)); census(r);
  const seen=new Set();
  r.inputs.forEach(i=>{ keys(i,'path sha256 module source bytes'); assert(path.isAbsolute(i.path)); assert.match(i.sha256,/^[a-f0-9]{64}$/); assert.equal(typeof i.module,'string'); assert(i.source===null||typeof i.source==='string'); assert(Number.isSafeInteger(i.bytes)&&i.bytes>=0); });
  assert.deepEqual(r.inputs.map(i=>i.path),r.inputs.map(i=>i.path).sort());
  const semantic={NONZERO:'divisor_nonzero_if_reached',ZERO:'divisor_zero_if_reached',MAY_ZERO:'divisor_may_be_zero',UNREACHABLE:'contradictory_supported_branch'};
  const semanticReasons=Object.values(semantic);
  const exclusions=['unsupported_arity','unsupported_labels','missing_operand','unsupported_integer_kind','unsupported_operand_type','unsupported_function_parameters','unsupported_function_cases','unsupported_recursive_binding','unsupported_binding_pattern','unsupported_short_circuit','unsupported_effect_primitive'];
  const closed=[...semanticReasons,...exclusions,'operand_spelling_omitted','location_unavailable','ghost_location'];
  const families={'%divint':'int','%modint':'int','%int32_div':'int32','%int32_mod':'int32','%int64_div':'int64','%int64_mod':'int64','%nativeint_div':'nativeint','%nativeint_mod':'nativeint'};
  r.sites.forEach(s=>{
    keys(s,'artifact id primitive integer_kind operand location status reasons'); assert(r.inputs.some(i=>i.path===s.artifact)); assert(Number.isSafeInteger(s.id)&&s.id>0);
    const identity=`${s.artifact}:${s.id}`; assert(!seen.has(identity)); seen.add(identity); assert(Object.hasOwn(families,s.primitive)); assert.equal(s.integer_kind,families[s.primitive]);
    keys(s.operand,'slot category representation'); assert.equal(s.operand.slot,2); assert(['integer_literal','identifier','other','missing'].includes(s.operand.category));
    assert(s.operand.representation===null||typeof s.operand.representation==='string'); if (s.operand.category==='identifier'&&s.operand.representation!==null) assert(Buffer.byteLength(s.operand.representation)<=256);
    if (['other','missing'].includes(s.operand.category)) assert.equal(s.operand.representation,null);
    keys(s.location,'file start end ghost'); assert.equal(typeof s.location.ghost,'boolean'); for (const p of [s.location.start,s.location.end]) { keys(p,'line column offset'); if (p.line===null) assert.deepEqual(p,{line:null,column:null,offset:null}); else { assert(p.line>=1); assert(p.column>=1); assert(p.offset>=0); } }
    assert.deepEqual(s.reasons,[...new Set(s.reasons)].sort()); assert(s.reasons.length>0); for (const reason of s.reasons) assert(closed.includes(reason)||/^unsupported_expression:T(?:exp|cl)_[a-z_]+$/.test(reason),`unknown reason ${reason}`);
    const actual=s.reasons.filter(reason=>semanticReasons.includes(reason));
    if (s.status==='UNSUPPORTED') { assert.deepEqual(actual,[],'UNSUPPORTED cannot carry numeric semantic reasons'); assert(s.reasons.some(reason=>exclusions.includes(reason)||/^unsupported_expression:T(?:exp|cl)_[a-z_]+$/.test(reason)),'UNSUPPORTED needs an actual exclusion reason'); }
    else { assert.deepEqual(actual,[semantic[s.status]],`${s.status} must carry exactly its conditional semantic reason`); assert(!s.reasons.some(reason=>exclusions.includes(reason)||/^unsupported_expression:T(?:exp|cl)_[a-z_]+$/.test(reason)),`${s.status} cannot carry exclusion reasons`); }
  });
  const tuple=s=>[s.artifact,s.location.start.offset,s.location.end.offset,s.primitive,s.id];
  const compare=(a,b)=>{ a=tuple(a); b=tuple(b); for(let i=0;i<a.length;i++){ if(a[i]===b[i])continue; if(a[i]===null)return -1; if(b[i]===null)return 1; return a[i]<b[i]?-1:1; } return 0; };
  assert.deepEqual(r.sites,[...r.sites].sort(compare));
}
function validateTextProjection(text,r,exactUnsafeColumns=new Map()) {
  assert(text.includes(`inputs: ${r.inputs.length} (supplied accepted artifacts only)\n`)); assert(text.includes(`compiler_version: ${r.tool.compiler_version}\n`)); assert(text.includes(`int_bits: ${r.tool.int_bits}\n`));
  for (const s of r.analysis.assumptions) assert(text.includes(`assumption: ${s}\n`),`missing assumption: ${s}`); for (const s of r.analysis.limitations) assert(text.includes(`limitation: ${s}\n`),`missing limitation: ${s}`);
  const siteLines=text.split('\n').filter(line=>/^(?:NONZERO|ZERO|MAY_ZERO|UNREACHABLE|UNSUPPORTED) /.test(line)); assert.equal(siteLines.length,r.sites.length,'text must contain exactly one line per JSON site');
  for (const site of r.sites) { const key=`${site.artifact}:${site.id}`; const column=Number.isSafeInteger(site.location.start.column)?String(site.location.start.column):exactUnsafeColumns.get(key); if(site.location.start.line!==null) assert.equal(typeof column,'string',`unsafe coordinate requires fixture-supplied exact decimal: ${key}`); const source=site.location.file===null?'?':JSON.stringify(site.location.file); const location=site.location.start.line===null?'?:?:?':`${source}:${site.location.start.line}:${column}`; assert(text.includes(`${site.status} ${site.primitive} artifact=${JSON.stringify(site.artifact)} id=${site.id} location=${location} reasons=${site.reasons.join(',')}\n`),`missing exact text projection for ${site.artifact}#${site.id}`); }
  for (const [name,n] of Object.entries(r.census)) assert(text.includes(`${name}: ${n}\n`),`missing census ${name}`); assert.match(text,/Report-only/); assert.match(text,/conditional/);
}
module.exports={census,validateReport,validateTextProjection};
