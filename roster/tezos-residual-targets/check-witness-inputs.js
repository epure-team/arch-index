#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const {ComparisonInputError} = require('./comparison.js');
const {validateOneHop} = require('./check-witness.js');

const root = path.resolve(__dirname, '../..');
const sourceProbe = path.join(__dirname, 'alias-witness.ml');

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {encoding:'utf8', maxBuffer:64*1024*1024, ...options});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${(result.stderr || result.stdout).trim()}`);
  return result.stdout;
}

function expectRefusal(record, locator, label) {
  assert.throws(() => validateOneHop(record, locator), ComparisonInputError, label);
}

function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-alias-witness-inputs-'));
  try {
    const probeCopy = path.join(temp, 'alias_witness.ml');
    const probe = path.join(temp, 'alias-witness');
    const fixture = path.join(temp, 'fixture.ml');
    fs.copyFileSync(sourceProbe, probeCopy);
    fs.writeFileSync(fixture, [
      'module M : sig val alias : int -> int end = struct',
      '  let base x = x + 1',
      '  let alias = base',
      'end',
      "module Ops : sig val ( let* ) : 'a -> ('a -> 'b) -> 'b end = struct",
      '  let bind x f = f x',
      '  let ( let* ) = bind',
      'end',
      'let applied () = M.alias 1',
      'let callback () = List.map M.alias [1]',
      'let via_letop () = let open Ops in let* x = 1 in x + 1',
      'let pointfree = M.alias',
      ''
    ].join('\n'));
    const opam = args => fs.existsSync(path.join(root,'_opam'))
      ? run('opam', ['exec', `--switch=${root}`, '--', ...args], {cwd:temp})
      : run(args[0], args.slice(1), {cwd:temp});
    opam(['ocamlfind','ocamlopt','-package','compiler-libs.common','-linkpkg','-o',probe,'alias_witness.ml']);
    opam(['ocamlc','-bin-annot','-bin-annot-occurrences','-c','fixture.ml']);
    const nativeText = run(probe, [path.join(temp, 'fixture.cmt')], {cwd:temp});
    const records = JSON.parse(nativeText);
    assert.equal(records.length, 1, 'probe emits one record per CMT');
    const record = records[0];

    const appIndex = record.applications.findIndex(x => x.path.endsWith('M.alias'));
    const callbackIndex = record.identifiers.findIndex(x =>
      x.path.endsWith('M.alias') && x.callback_contexts.length > 0);
    const letopIndex = record.letops.findIndex(x => x.operators.some(op => op.path.endsWith('Ops.let*')));
    const operatorIndex = letopIndex < 0 ? -1 : record.letops[letopIndex].operators
      .findIndex(op => op.path.endsWith('Ops.let*'));
    const pointfreeIndex = record.identifiers.findIndex(x =>
      x.path.endsWith('M.alias') && x.callback_contexts.length === 0 && x.loc.start_line === 12);
    assert.ok(appIndex >= 0 && callbackIndex >= 0 && letopIndex >= 0 && operatorIndex >= 0 && pointfreeIndex >= 0,
      'fixture exposes every required native consumer');

    const app = validateOneHop(record, {bucket:'applications', index:appIndex});
    const callback = validateOneHop(record, {bucket:'identifiers', index:callbackIndex});
    const letop = validateOneHop(record, {bucket:'letops', index:letopIndex, operator_index:operatorIndex});
    assert.equal(app.syntactic_arity, 1);
    const appOccurrence = record.applications[appIndex];
    assert.notEqual(appOccurrence.val_uid, app.alias_uid, 'fixture exercises signature/implementation UID layering');
    assert.equal(appOccurrence.val_uid_declarations[0].kind, 'Value');
    assert.equal(app.supplied_some, 1);
    assert.equal(callback.consumer_context.kind, 'callback');
    assert.equal(letop.consumer_context.kind, 'letop_operator');
    assert.deepEqual(letop.occurrence_loc, record.letops[letopIndex].operators[operatorIndex].bop_loc,
      'letop normalizes the operator location, not the enclosing expression');

    expectRefusal(record, {bucket:'identifiers', index:pointfreeIndex}, 'point-free identifier');
    let bad = structuredClone(record);
    bad.applications[appIndex].slots = 0;
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'inconsistent supplied slots');
    bad = structuredClone(record);
    bad.aliases.find(x => x.alias.binding_uid === app.alias_uid).rhs_ident.unique_name = 'wrong-ident';
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'RHS Ident disagreement');
    bad = structuredClone(record);
    bad.aliases.find(x => x.alias.binding_uid === app.alias_uid).alias.binding_loc.start_offset = -1;
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'malformed position');
    bad = structuredClone(record);
    const selected = bad.aliases.find(x => x.alias.binding_uid === app.alias_uid);
    selected.rhs_val_uid = 'conflicting-body-uid';
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'UID disagreement');
    bad = structuredClone(record);
    bad.bindings = bad.bindings.filter(x => x.binding_uid !== app.body_uid);
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'body absent from same-CMT bindings');

    bad = structuredClone(record);
    bad.applications[appIndex].val_uid_bindings = [bad.aliases.find(x => x.alias.binding_uid === app.alias_uid).alias];
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'signature UID with conflicting concrete binding');
    bad = structuredClone(record);
    bad.applications[appIndex].val_uid_declarations = [];
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'missing signature declaration');
    bad = structuredClone(record);
    bad.applications[appIndex].val_uid_declarations[0].uid = 'foreign.unit.1';
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'foreign signature declaration');
    bad = structuredClone(record);
    bad.applications[appIndex].val_uid_declarations[0].name = 'other';
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'wrong signature declaration name');
    bad = structuredClone(record);
    bad.applications[appIndex].val_uid_declarations[0].is_arrow = false;
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'non-arrow signature declaration');
    bad = structuredClone(record);
    const shape = bad.applications[appIndex].occurrences.find(x => x.result.kind === 'Resolved');
    shape.result.kind = 'Resolved_alias';
    expectRefusal(bad, {bucket:'applications', index:appIndex}, 'Resolved_alias signature endpoint');

    // Exercise the actual paired admission loader, including native replay.
    const {loadWitness,validateNativePair} = require('./witness.js');
    const {fileSha256} = require('./baseline.js');
    const evidenceFile=path.join(temp,'evidence.json');
    fs.writeFileSync(evidenceFile,nativeText);
    const caller=record.bindings.find(b=>b.name==='applied');
    const before={caller_path:'fixture.ml',caller:'applied',call_site:`fixture.ml:${app.occurrence_loc.start_line}`,
      target_path:null,target:null,callee_name:'M.alias',kind:'MAY_TOP',edge_form:null,
      top_reason:'module_param',top_anchor:`fixture.ml:${app.occurrence_loc.start_line}`,
      caller_line_start:caller.binding_loc.start_line,caller_line_end:caller.binding_loc.end_line,
      target_line_start:null,target_line_end:null};
    const after={...before,target_path:'fixture.ml',target:'M.base',callee_name:'M.base',kind:'MAY_ENUMERATED',
      top_reason:null,top_anchor:null,target_line_start:app.body_binding_loc.start_line,target_line_end:app.body_binding_loc.end_line};
    const baseline={digest:'a'.repeat(64),positioned_rows:[before]},candidate={digest:'b'.repeat(64),positioned_rows:[after]};
    const manifest={records:[['fixture',fileSha256(record.cmt),record.cmt]]};
    const paired={schema_version:2,kind:'local-value-alias-one-hop',baseline_digest:baseline.digest,candidate_digest:candidate.digest,
      evidence_file:evidenceFile,evidence_sha256:fileSha256(evidenceFile),probe_sha256:fileSha256(sourceProbe),
      transitions:[{before,after,native:{cmt:record.cmt,locator:{bucket:'applications',index:appIndex}},
        reviewed_by:'synthetic fixture control only',reviewed_at:'2026-09-14',source_evidence:'native fixture'}],residuals:[]};
    const witnessFile=path.join(temp,'witness.json');
    const admission=value=>{fs.writeFileSync(witnessFile,JSON.stringify(value));return loadWitness(witnessFile,baseline,candidate,manifest)};
    assert.equal(admission(paired).transitions.length,1,'actual native-replayed paired positive');
    for(const mutate of [
      w=>{w.kind='historical-direct-uid';},
      w=>{w.candidate_digest='0'.repeat(64);},
      w=>{w.probe_sha256='0'.repeat(64);},
      w=>{w.evidence_sha256='0'.repeat(64);},
      w=>{w.transitions[0].reviewed_by=null;},
      w=>{w.transitions[0].after.target_line_start++;},
      w=>{w.transitions.push(structuredClone(w.transitions[0]));},
      w=>{w.transitions[0].native.locator.index=99999;},
    ]) {const changed=structuredClone(paired);mutate(changed);assert.throws(()=>admission(changed),ComparisonInputError);}
    assert.throws(()=>validateNativePair(record,{bucket:'applications',index:appIndex},before,{...after,target:'M.decoy',callee_name:'M.decoy'}),ComparisonInputError);
    const forged=JSON.parse(nativeText);forged[0].occurrence_count++;
    fs.writeFileSync(evidenceFile,JSON.stringify(forged));
    assert.throws(()=>admission({...paired,evidence_sha256:fileSha256(evidenceFile)}),/does not reproduce/,
      'a rehashed forged JSON file is not native evidence');
    console.log('PASS alias witness native inputs (3 positive consumers, 12 refusal controls; paired admission positive + 10 refusals)');
  } finally {
    fs.rmSync(temp, {recursive:true, force:true});
  }
}

try { main(); }
catch (error) {
  const assertion = error instanceof assert.AssertionError || error instanceof ComparisonInputError;
  process.stderr.write(`${assertion ? 'ALIAS_WITNESS_ASSERTION' : 'ALIAS_WITNESS_SETUP'}: ${error.message}\n`);
  process.exitCode = assertion ? 1 : 2;
}
