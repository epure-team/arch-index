#!/usr/bin/env node
'use strict';
// Independent contract assertions: no expected results are supplied by the OCaml probe.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const {census,validateReport,validateTextProjection} = require('../tezt/fixtures/arch_guard/checker_report_oracle.js');
const numericCases = require('../tezt/fixtures/arch_guard/checker_numeric_cases.js');
const root = path.resolve(__dirname, '..');
const binary = process.env.ARCH_GUARD || path.join(root, '_build/default/bin/arch_guard/arch_guard.exe');
const probe = process.env.ARCH_GUARD_DOMAIN_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/domain_probe.exe');
const fixtureProbe = process.env.ARCH_GUARD_FIXTURE_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/fixture_probe.exe');
const effectFixtureProbe = process.env.ARCH_GUARD_EFFECT_FIXTURE_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/effect_fixture_probe.exe');
const changedReadProbe = process.env.ARCH_GUARD_CHANGED_READ_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/changed_read_probe.exe');
const cap = 16 * 1024 * 1024;
function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {encoding: 'utf8', timeout: 120000, maxBuffer: cap, ...options});
  if (result.error || result.signal || result.status === null) throw new Error(`execution failed: ${command}: ${result.error || result.signal}`);
  if (Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr) > cap) throw new Error('combined process output exceeds 16 MiB');
  return result;
}
function success(command, args, options) {
  const result = run(command, args, options);
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}: ${result.stderr}`);
  return result.stdout;
}
function withFixture(source, action) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-guard-check-'));
  try {
    fs.writeFileSync(path.join(dir, 'fixture.ml'), source);
    success(process.env.ARCH_GUARD_OCAMLC || 'ocamlc', ['-bin-annot', '-c', 'fixture.ml'], {cwd: dir});
    return action(path.join(dir, 'fixture.cmt'), dir);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
}
function withNamedFixture(sourceName, source, action) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'arch-guard-named-'));
  try {
    fs.writeFileSync(path.join(dir,sourceName),source);
    success(process.env.ARCH_GUARD_OCAMLC || 'ocamlc',['-bin-annot','-c',sourceName],{cwd:dir});
    return action(path.join(dir,sourceName.replace(/\.ml$/,'.cmt')),dir);
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
}
function report(cmt) { return JSON.parse(success(binary, ['--cmt', cmt, '--format', 'json'])); }
function rewrite(input, output, args) {
  const mutation = JSON.parse(success(fixtureProbe, ['rewrite','--input',input,'--output',output,'--annotation','implementation',...args]));
  assert.equal(mutation.ok, true);
  return mutation;
}
const constant = n => ({kind: 'const', value: String(n)});
const bottom = {kind: 'bottom'}, top = {kind: 'top'}, nonzero = {kind: 'nonzero'};
function contains(a, n) {
  if (a.kind === 'bottom') return false;
  if (a.kind === 'top') return true;
  if (a.kind === 'nonzero') return n !== 0n;
  assert.equal(a.kind, 'const');
  return BigInt(a.value) === n;
}
// Inclusion between the four concretization shapes, independent of transfer code.
function subset(a,b) {
  if (a.kind === 'bottom' || b.kind === 'top') return true;
  if (a.kind === 'const') return contains(b,BigInt(a.value));
  return a.kind === b.kind;
}
function domain() {
  let checked = 0, lawAssertions = 0, pending = [];
  function flush() {
    if (!pending.length) return;
    const input = pending.map((p, id) => JSON.stringify({...p.request, id})).join('\n') + '\n';
    const rows = success(probe, [], {input}).trim().split('\n').map(line => JSON.parse(line));
    assert.equal(rows.length, pending.length, 'probe response cardinality');
    rows.forEach((row, id) => { assert.equal(row.id, id); pending[id].check(row.result); checked++; });
    pending = [];
  }
  function request(width, op, args, check) {
    pending.push({request: {width, op, args}, check});
    if (pending.length >= 4000) flush();
  }
  for (const width of [3, 4, 5, 6, 7, 8, 31, 63]) {
    const min = -(1n << BigInt(width - 1)), max = -min - 1n;
    const values = width <= 8 ? Array.from({length: Number(max - min + 1n)}, (_, i) => min + BigInt(i))
      : [...new Set([min, min + 1n, -2n, -1n, 0n, 1n, 2n, max - 1n, max])];
    const wrap = n => BigInt.asIntN(width, n);
    for (const a of values) {
      request(width, 'neg', [constant(a)], result => {
        assert(contains(result, wrap(-a)), `neg containment width=${width} a=${a}`);
        assert.deepEqual(result, -a >= min && -a <= max ? constant(-a) : top);
      });
      for (const b of values) for (const op of ['add', 'sub', 'mul']) {
        const exact = op === 'add' ? a + b : op === 'sub' ? a - b : a * b;
        request(width, op, [constant(a), constant(b)], result => {
          assert(contains(result, wrap(exact)), `${op} containment width=${width} a=${a} b=${b}`);
          assert.deepEqual(result, exact >= min && exact <= max ? constant(exact) : top);
        });
      }
    }
    const abstracts = [bottom, top, nonzero, ...values.map(constant)];
    for (const a of abstracts) {
      for (const op of ['restrict_eq_zero', 'restrict_ne_zero']) request(width, op, [a], result => {
        for (const n of values) assert.equal(contains(result, n), contains(a, n) && (op === 'restrict_eq_zero' ? n === 0n : n !== 0n), `${op} width=${width}`);
        if (a.kind === 'const' && a.value !== '0' && op === 'restrict_ne_zero') assert.deepEqual(result, a);
      });
      request(width, 'join', [a, bottom], result => assert.deepEqual(result, a));
      request(width, 'join', [a, a], result => assert.deepEqual(result, a));
      for (const b of [bottom, top, nonzero, constant(0n), constant(1n)]) {
        request(width, 'join', [a, b], result => {
          for (const n of values) if (contains(a, n) || contains(b, n)) assert(contains(result, n), 'join upper bound');
        });
        for (const op of ['add', 'sub', 'mul']) request(width, op, [a, b], result => {
          if (a.kind === 'bottom' || b.kind === 'bottom') { assert.deepEqual(result, bottom); return; }
          // Exhaust all represented concrete values at small widths, extrema samples at native widths.
          for (const x of values) if (contains(a, x)) for (const y of values) if (contains(b, y)) {
            const n = op === 'add' ? x + y : op === 'sub' ? x - y : x * y;
            assert(contains(result, wrap(n)), `${op} abstract containment width=${width}`);
          }
        });
      }
    }
    // Cache actual probe transfers before checking laws; no expected transfer is
    // computed by the probe. Exhaustive abstract states at small widths.
    const count=abstracts.length, tables={}, unary={};
    for (const op of ['join','add','sub','mul']) {
      tables[op]=new Array(count*count);
      abstracts.forEach((a,i) => abstracts.forEach((b,j) => request(width,op,[a,b],r => { tables[op][i*count+j]=r; })));
    }
    for (const op of ['neg','restrict_eq_zero','restrict_ne_zero']) {
      unary[op]=new Array(count);
      abstracts.forEach((a,i) => request(width,op,[a],r => { unary[op][i]=r; }));
    }
    flush();
    const key=a => a.kind === 'const' ? `const:${a.value}` : a.kind;
    const indices=new Map(abstracts.map((a,i) => [key(a),i]));
    const join=(i,j) => tables.join[i*count+j];
    for (let i=0;i<count;i++) for (let j=0;j<count;j++) {
      assert.deepEqual(join(i,j),join(j,i),'join commutativity'); lawAssertions++;
      assert(subset(abstracts[i],join(i,j)) && subset(abstracts[j],join(i,j)),'join upper bound'); lawAssertions++;
      // For any upper bound k, the actual join is below it: least-upper-bound law.
      for (let k=0;k<count;k++) {
        if (subset(abstracts[i],abstracts[k]) && subset(abstracts[j],abstracts[k])) {
          assert(subset(join(i,j),abstracts[k]),'join leastness'); lawAssertions++;
        }
        const ij=indices.get(key(join(i,j))), jk=indices.get(key(join(j,k)));
        assert.notEqual(ij,undefined); assert.notEqual(jk,undefined);
        assert.equal(key(join(ij,k)),key(join(i,jk)),'join associativity'); lawAssertions++;
      }
      if (!subset(abstracts[i],abstracts[j])) continue;
      for (const op of Object.keys(unary)) {
        assert(subset(unary[op][i],unary[op][j]),`${op} monotonicity`); lawAssertions++;
      }
      for (const [op,table] of Object.entries(tables)) for (let k=0;k<count;k++) {
        assert(subset(table[i*count+k],table[j*count+k]),`${op} left monotonicity`);
        assert(subset(table[k*count+i],table[k*count+j]),`${op} right monotonicity`); lawAssertions+=2;
      }
    }
  }
  flush();
  return {checked, lawAssertions, exhaustiveWidths: [3, 4, 5, 6, 7, 8], sampledWidths: [31, 63]};
}
function numeric() {
  numericCases.forEach(([source, expected, reason], index) => withFixture(source + '\n', cmt => {
    const r = report(cmt); validateReport(r); assert.equal(r.sites.length, 1, `numeric case ${index}: site count`);
    assert.equal(r.sites[0].status, expected, `numeric case ${index}: ${source}; reasons=${r.sites[0].reasons}`);
    assert.deepEqual(r.sites[0].reasons, [reason], `numeric case ${index}: exact reasons`);
  }));
  const source = fs.readFileSync(path.join(root, 'tezt/fixtures/arch_guard/inventory.ml'), 'utf8');
  const expected = new Map([[1,'NONZERO'],[2,'UNSUPPORTED'],[3,'UNSUPPORTED'],[4,'UNSUPPORTED'],[5,'UNSUPPORTED'],[8,'UNSUPPORTED'],[10,'NONZERO'],[11,'NONZERO'],[12,'MAY_ZERO'],[13,'UNREACHABLE'],[14,'MAY_ZERO'],[15,'ZERO']]);
  return withFixture(source, cmt => {
    const r = report(cmt); validateReport(r);
    assert.equal(r.sites.length, expected.size);
    for (const s of r.sites) { assert.equal(s.status, expected.get(s.location.start.line), `site line ${s.location.start.line}`); expected.delete(s.location.start.line); }
    assert.equal(expected.size, 0);
    const r1Source = fs.readFileSync(path.join(root,'tezt/fixtures/arch_guard/r1_cases.ml'),'utf8');
    const r1 = withFixture(r1Source, (r1Cmt,r1Dir) => {
      const native=report(r1Cmt);
      for (const kind of ['non-native','unresolved']) for (const slot of [1,2]) {
        const output=path.join(r1Dir,`guard-${kind}-${slot}.cmt`);
        const evidence=rewrite(r1Cmt,output,['--guard-operand-type',kind,'--guard-operand-slot',String(slot)]);
        assert.equal(evidence.guard_operand_type_changed,true);
        const changed=report(output); validateReport(changed);
        assert.equal(changed.sites[1].status,'MAY_ZERO'); assert.deepEqual(changed.sites[1].reasons,['divisor_may_be_zero']);
      }
      return native;
    });
    validateReport(r1); assert.equal(r1.sites.length,36);
    const expectedR1 = numericCases.r1Expected;
    r1.sites.forEach((site,index) => { assert.equal(site.id,index+1); assert.equal(site.status,expectedR1[index][0]); assert.deepEqual(site.reasons,expectedR1[index][1]); });
    assert.deepEqual(r1.census,{artifacts:1,total_sites:36,numeric_covered:19,nonzero:6,zero:2,may_zero:11,unreachable:0,unsupported:17,precision_gain_sites:6});
    const effectSource=fs.readFileSync(path.join(root,'tezt/fixtures/arch_guard/effect_fixture.ml'),'utf8');
    const effects=withFixture(effectSource,(effectSeed,effectDir) => ['%perform','%resume','%runstack','%reperform'].map(name => {
      const output=path.join(effectDir,`${name.slice(1)}.cmt`);
      const evidence=JSON.parse(success(effectFixtureProbe,['--input',effectSeed,'--output',output,'--primitive',name]));
      assert.equal(evidence.changed,true); assert.equal(evidence.scope,'test-only Typedtree effect-primitive application seam');
      const changed=report(output); validateReport(changed); assert.equal(changed.sites.length,1);
      assert.equal(changed.sites[0].status,'UNSUPPORTED'); assert.deepEqual(changed.sites[0].reasons,['unsupported_effect_primitive']);
      return name;
    }));
    return {additionalCases:numericCases.length, originalInventory:r.census, r1:r1.census, effects};
  });
}
function rejected(args, pattern) {
  const r = run(binary, args);
  assert.equal(r.status, 2, r.stderr);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, pattern);
}
function inventory() {
  const source = [
    'let a () = 10 / 2', 'let b () = 10 mod 2',
    'let c () = Int32.div 10l 2l', 'let d () = Int32.rem 10l 2l',
    'let e () = Int64.div 10L 2L', 'let f () = Int64.rem 10L 2L',
    'let g () = Nativeint.div 10n 2n', 'let h () = Nativeint.rem 10n 2n',
    'let partial = ( / ) 1', 'let alias = ( / )', 'let indirect () = alias 10 2',
    'let shadow () = let ( / ) x y = x + y in 10 / 2',
  ].join('\n');
  return withFixture(source, (cmt, dir) => {
    const r = report(cmt); census(r);
    const primitives = ['%divint','%modint','%int32_div','%int32_mod','%int64_div','%int64_mod','%nativeint_div','%nativeint_mod','%divint'];
    assert.deepEqual(r.sites.map(s => s.primitive), primitives);
    assert.deepEqual(r.sites.map(s => s.id), primitives.map((_, i) => i + 1));
    r.sites.slice(0, 8).forEach(s => assert.deepEqual(s.operand, {slot: 2, category: 'integer_literal', representation: '2'}));
    assert.deepEqual(r.sites[8].operand, {slot: 2, category: 'missing', representation: null});
    assert.deepEqual(report(cmt), r);
    const dedup = JSON.parse(success(binary, ['--cmt', cmt, '--cmt', './fixture.cmt', '--format', 'json'], {cwd: dir}));
    assert.deepEqual(dedup, r);
    const copy = path.join(dir, 'copy.cmt'); fs.copyFileSync(cmt, copy);
    rejected(['--cmt', cmt, '--cmt', copy], /duplicate module\/source/);
    fs.writeFileSync(path.join(dir,'second.ml'),'let second () = 20 mod 3\n');
    success(process.env.ARCH_GUARD_OCAMLC || 'ocamlc',['-bin-annot','-c','second.ml'],{cwd:dir});
    const second = path.join(dir,'second.cmt');
    const forward = success(binary,['--cmt',cmt,'--cmt',second,'--format','json']);
    const reversed = success(binary,['--cmt',second,'--cmt',cmt,'--format','json']);
    assert.equal(reversed,forward,'distinct accepted artifacts must render byte-identically when reversed');

    const inventorySource=fs.readFileSync(path.join(root,'tezt/fixtures/arch_guard/inventory.ml'),'utf8');
    const seams=withFixture(inventorySource,(seed,seamDir) => {
      const mutate=(name,args,flag='application_changed') => {
        const output=path.join(seamDir,`${name}.cmt`); const evidence=rewrite(seed,output,args);
        assert.equal(evidence[flag],true,`${name}: requested mutation flag`); const value=report(output); validateReport(value); return value;
      };
      const later=mutate('later',['--application-shape','later-saturation','--target-site','2']);
      assert.equal(later.sites.length,12); assert.deepEqual(later.sites[1].operand,{slot:2,category:'missing',representation:null});
      assert.equal(later.sites[1].status,'UNSUPPORTED'); assert.deepEqual(later.sites[1].reasons,['missing_operand','unsupported_arity']);
      const over=mutate('over',['--application-shape','overapplied','--target-site','1']);
      assert.deepEqual(over.sites[0].operand,{slot:2,category:'integer_literal',representation:'2'}); assert.deepEqual(over.sites[0].reasons,['unsupported_arity']);
      const labelled=mutate('labelled',['--application-shape','labelled-operand','--target-site','1']);
      assert.deepEqual(labelled.sites[0].operand,{slot:2,category:'integer_literal',representation:'2'}); assert.deepEqual(labelled.sites[0].reasons,['unsupported_labels']);
      const missing=mutate('missing',['--application-shape','missing-second-slot','--target-site','1']);
      assert.deepEqual(missing.sites[0].operand,{slot:2,category:'missing',representation:null}); assert.deepEqual(missing.sites[0].reasons,['missing_operand','unsupported_arity','unsupported_operand_type']);
      const all=mutate('over-all',['--application-shape','overapplied-all']);
      assert.equal(all.sites.length,12); assert.deepEqual(all.sites[2].reasons,['unsupported_arity','unsupported_expression:Texp_while']);
      for (const kind of ['non-native','unresolved']) for (const slot of [1,2]) {
        const typed=mutate(`type-${kind}-${slot}`,['--operand-type',kind,'--operand-slot',String(slot),'--target-site','1'],'operand_type_changed');
        assert.deepEqual(typed.sites[0].reasons,['unsupported_operand_type']);
      }
      for (const bytes of [256,257]) {
        const spellingReport=mutate(`identifier-${bytes}`,['--identifier-bytes',String(bytes)],'identifier_changed');
        const spelling=spellingReport.sites.find(site => site.operand.representation === null ? site.reasons.includes('operand_spelling_omitted') : site.operand.representation.startsWith('é'));
        assert(spelling,'mutated UTF-8 identifier site must remain inventoried');
        if (bytes===256) { assert.equal(Buffer.byteLength(spelling.operand.representation),256); assert(!spelling.reasons.includes('operand_spelling_omitted')); }
        else { assert.equal(spelling.operand.representation,null); assert(spelling.reasons.includes('operand_spelling_omitted')); }
      }
      const duplicate=mutate('duplicate',['--duplicate-coordinates'],'duplicate_coordinates');
      assert.equal(duplicate.sites.length,12); assert.equal(new Set(duplicate.sites.map(s=>s.id)).size,12);
      assert.equal(new Set(duplicate.sites.map(s=>`${s.location.start.offset}:${s.location.end.offset}`)).size,1);
      withFixture('let f numerator divisor = numerator / divisor\n',(operandSeed,operandDir) => {
        const typeOutput=path.join(operandDir,'type-slot.cmt');
        const typeEvidence=rewrite(operandSeed,typeOutput,['--operand-type','unresolved','--operand-slot','1']);
        assert.deepEqual(typeEvidence.observed_operand_types.filter(row => row.site === 1).map(row => row.type),['unresolved','int'],'operand type mutation honors requested slot');
        const identifierOutput=path.join(operandDir,'identifier-slot.cmt');
        const identifierEvidence=rewrite(operandSeed,identifierOutput,['--identifier-bytes','257','--operand-slot','1']);
        assert.equal(identifierEvidence.identifier_changed,true);
        const identifierSite=report(identifierOutput).sites[0];
        assert.equal(identifierSite.operand.representation,null,'identifier byte mutation always targets original slot 2');
        assert(identifierSite.reasons.includes('operand_spelling_omitted'));
      });
      return {cases:12};
    });
    return {base:r.census,seams};
  });
}
function assertReportMutationRejected(reportValue, mutate, label) {
  const changed = structuredClone(reportValue);
  mutate(changed);
  assert.throws(() => validateReport(changed), assert.AssertionError, label);
}
function reportMode() {
  const boundary = outputBoundary();
  withFixture('let empty = 1\n', cmt => {
    const r = report(cmt); validateReport(r); assert.equal(r.sites.length, 0);
    assert.match(success(binary, ['--cmt', cmt]), /No matching immediate primitive occurrences in supplied artifacts\./);
  });
  const projectionSource=fs.readFileSync(path.join(root,'tezt/fixtures/arch_guard/inventory.ml'),'utf8');
  withFixture(projectionSource,cmt => {
    const json=report(cmt); validateReport(json);
    assert.deepEqual([...new Set(json.sites.map(site=>site.status))].sort(),['MAY_ZERO','NONZERO','UNREACHABLE','UNSUPPORTED','ZERO']);
    const text=success(binary,['--cmt',cmt,'--format','text']); validateTextProjection(text,json);
    const omitted=text.replace(/ artifact=[^ ]+/, '');
    assert.throws(() => validateTextProjection(omitted,json),assert.AssertionError,'same projection oracle rejects an omitted required site field');
    const firstSiteLine=text.split('\n').find(line=>/^(?:NONZERO|ZERO|MAY_ZERO|UNREACHABLE|UNSUPPORTED) /.test(line));
    const duplicated=text.replace(`${firstSiteLine}\n`,`${firstSiteLine}\n${firstSiteLine}\n`);
    assert.throws(() => validateTextProjection(duplicated,json),assert.AssertionError,'same projection oracle rejects a duplicate site line');
    const unsupportedIndex=json.sites.findIndex(site=>site.status==='UNSUPPORTED'); assert(unsupportedIndex>=0);
    assertReportMutationRejected(json,changed => { changed.sites[unsupportedIndex].reasons=['divisor_may_be_zero']; },'UNSUPPORTED rejects a numeric-only reason');
    assertReportMutationRejected(json,changed => { changed.sites[unsupportedIndex].reasons=['ghost_location']; },'UNSUPPORTED requires an actual exclusion reason');
    const numericIndex=json.sites.findIndex(site=>site.status==='NONZERO'); assert(numericIndex>=0);
    assertReportMutationRejected(json,changed => { changed.sites[numericIndex].reasons=['divisor_nonzero_if_reached','unsupported_arity']; },'numeric status rejects an exclusion reason');
  });
  for (const sourceName of ['source space.ml','source id=.ml','source\nname.ml']) withNamedFixture(sourceName,'let f d = 10 / d\n',(cmt,dir) => {
    const moved=path.join(dir,`artifact ${sourceName.replace(/\.ml$/,'')} id=.cmt`); fs.renameSync(cmt,moved);
    const json=report(moved); validateReport(json);
    validateTextProjection(success(binary,['--cmt',moved,'--format','text']),json);
  });
  return withFixture('let f d = 10 / d\n', (cmt, dir) => {
    const r = report(cmt); validateReport(r);
    assertReportMutationRejected(r, changed => {
      changed.sites[0].reasons = ['divisor_nonzero_if_reached'];
    }, 'status-aware oracle must reject a wrong but vocabulary-valid semantic reason');
    for (const location of ['invalid','ghost','cross-file','backwards','max-column']) {
      const output = path.join(dir, `${location}.cmt`);
      success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation','implementation','--location',location]);
      const mutated = report(output); validateReport(mutated); const s = mutated.sites[0];
      const exactColumns=location==='max-column' ? new Map([[`${s.artifact}:${s.id}`,(1n<<BigInt(mutated.tool.int_bits-1)).toString()]]) : new Map();
      validateTextProjection(success(binary,['--cmt',output,'--format','text']),mutated,exactColumns);
      assert.equal(mutated.sites.length, 1);
      if (location === 'ghost') { assert(s.location.ghost); assert(s.reasons.includes('ghost_location')); }
      if (location === 'invalid') { assert.equal(s.location.file, null); assert.equal(s.location.start.line, null); }
      if (['cross-file','backwards','invalid'].includes(location)) { assert.equal(s.location.end.line, null); assert(s.reasons.includes('location_unavailable')); }
      if (location === 'max-column') assert.equal(s.location.start.column, Number(1n << BigInt(mutated.tool.int_bits - 1)));
    }
    const output = path.join(dir, 'spelling.cmt');
    success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation','implementation','--long-identifier']);
    const s = report(output).sites[0]; assert.equal(s.operand.representation, null); assert(s.reasons.includes('operand_spelling_omitted'));
    const text = success(binary, ['--cmt', cmt]); validateTextProjection(text,r);
    return {metadataCases: 6, boundary, census: r.census};
  });
}
function outputBoundary() {
  return withFixture('let f () = 10 / 2\n', (cmt, dir) => {
    function sized(name, n) {
      const output = path.join(dir, name);
      success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation','implementation','--first-location-file-bytes',String(n)]);
      // Keep reported bytes and all path/module name lengths constant during calibration.
      fs.truncateSync(output, 32 * 1024 * 1024);
      return output;
    }
    const baseline = sized('s00.cmt',1);
    const json = JSON.stringify(report(baseline));
    const filenameBytes = cap - Buffer.byteLength(json) + 1;
    const exact = sized('s01.cmt',filenameBytes);
    const over = sized('s02.cmt',filenameBytes + 1);
    // Reject over-size reports before testing the large inclusive success.
    rejected(['--cmt',over,'--format','json'], /exceeds 16 MiB/);
    rejected(['--cmt',over,'--format','text'], /exceeds 16 MiB/);
    const out = success(binary,['--cmt',exact,'--format','json']);
    assert.equal(Buffer.byteLength(out),cap,'complete stdout must fit the inclusive output bound');
    assert.equal(JSON.parse(out).sites[0].location.file.length,filenameBytes);
    return {jsonBytesInclusive:cap, jsonBytesRejected:cap+1};
  });
}
function inputs() {
  const traversal = traversalBoundaries();
  const evidence = withFixture('let f () = 10 / 2\n', (cmt, dir) => {
    // Private shared-reader seam, not a timed filesystem race or installed CLI run.
    success(changedReadProbe,['--stable',cmt]);
    const changed=run(changedReadProbe,[cmt]);
    assert.equal(changed.status,2); assert.equal(changed.stdout,'');
    assert.match(changed.stderr,/input changed while being read/);
    rejected([], /required/);
    rejected(['--cmt', path.join(dir, 'missing.cmt')], /No such file/);
    rejected(['--cmt', dir], /regular file/);
    const link = path.join(dir, 'link.cmt'); fs.symlinkSync(cmt, link);
    rejected(['--cmt', link], /symlink/);
    const hard = path.join(dir, 'hard.cmt'); fs.linkSync(cmt, hard);
    rejected(['--cmt', cmt, '--cmt', hard], /duplicate module\/source/);
    const malformed = path.join(dir, 'malformed.cmt'); fs.writeFileSync(malformed, 'not a compiler artifact');
    rejected(['--cmt', cmt, '--cmt', malformed], /malformed|incompatible|not a CMT/);
    const incompatible = path.join(dir,'incompatible.cmt');
    const bytes = fs.readFileSync(cmt);
    assert.equal(bytes.subarray(0,8).toString(),'Caml1999','fixture compiler magic prerequisite');
    bytes.write('000',9,3,'ascii'); fs.writeFileSync(incompatible,bytes);
    rejected(['--cmt',incompatible],/incompatible compiler artifact/);
    rejected(['--cmt', cmt, '--format', 'xml'], /text or json/);
    rejected(['--unknown'], /unknown/);
    for (const annotation of ['interface','packed','partial-implementation','partial-interface']) {
      const output = path.join(dir, `${annotation}.cmt`);
      success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation',annotation]);
      rejected(['--cmt', cmt, '--cmt', output], /annotation is unsupported/);
    }
    const padded = path.join(dir, 'padded.cmt'); fs.copyFileSync(cmt, padded);
    fs.truncateSync(padded, 32 * 1024 * 1024);
    assert.equal(report(padded).inputs[0].bytes, 32 * 1024 * 1024);
    fs.truncateSync(padded, 32 * 1024 * 1024 + 1);
    rejected(['--cmt', padded], /exceeds 32 MiB/);
    const paths = [];
    for (let i = 0; i < 129; i++) {
      const source = `unit_${i}.ml`;
      fs.writeFileSync(path.join(dir, source), 'let n = 0\n');
      success(process.env.ARCH_GUARD_OCAMLC || 'ocamlc', ['-bin-annot','-c',source], {cwd: dir});
      paths.push(path.join(dir, `unit_${i}.cmt`));
    }
    const args = paths.slice(0,128).flatMap(p => ['--cmt',p]);
    const r = JSON.parse(success(binary, [...args,'--format','json']));
    assert.equal(r.inputs.length,128); assert.equal(r.sites.length,0);
    rejected([...args,'--cmt',paths[128]], /input count exceeds 128/);
    // Distinct, genuine modules padded with trailing bytes: valid CMT readers ignore padding.
    paths.slice(0,8).forEach(p => fs.truncateSync(p,32 * 1024 * 1024));
    const aggregate = paths.slice(0,8).flatMap(p => ['--cmt',p]);
    assert.equal(JSON.parse(success(binary,[...aggregate,'--format','json'])).inputs.length,8);
    const byte = path.join(dir,'one-byte.cmt'); fs.writeFileSync(byte,'x');
    rejected([...aggregate,'--cmt',byte], /aggregate input size exceeds 256 MiB/);
    return {annotationClasses:4, inputCountBoundary:[128,129], fileBytesBoundary:[33554432,33554433], aggregateBytesInclusive:268435456};
  });
  return {evidence,traversal,changedRead:'deterministic shared-reader seam; installed CLI error atomicity checked separately'};
}
function traversalBoundaries() {
  return withFixture('let seed = 0\n', (_cmt,dir) => {
    function compile(name, source) {
      fs.writeFileSync(path.join(dir,`${name}.ml`),source);
      success(process.env.ARCH_GUARD_OCAMLC || 'ocamlc',['-bin-annot','-c',`${name}.ml`],{cwd:dir});
      return path.join(dir,`${name}.cmt`);
    }
    const inspect = cmt => JSON.parse(success(fixtureProbe,['inspect','--input',cmt]));
    const nodes = [];
    const source = Array.from({length:1000},(_,i) => `let n${i} = 0`).join('\n');
    for (let i=0;i<100;i++) {
      const cmt = compile(`nodes_${i}`,source);
      const counts=inspect(cmt);
      assert.equal(counts.expression_nodes,1000); assert.equal(counts.max_expression_depth,1); assert.equal(counts.target_sites,0);
      nodes.push(cmt);
    }
    const nodeArgs = nodes.flatMap(p => ['--cmt',p]);
    assert.equal(JSON.parse(success(binary,[...nodeArgs,'--format','json'])).census.total_sites,0);
    const extra = compile('extra','let x = 0\n');
    rejected([...nodeArgs,'--cmt',extra],/expression node count exceeds 100000/);
    const sites = [];
    const siteSource = Array.from({length:1000},(_,i) => `let f${i} () = 10 / 2`).join('\n');
    for (let i=0;i<10;i++) {
      const cmt = compile(`sites_${i}`,siteSource); assert.equal(inspect(cmt).target_sites,1000); sites.push(cmt);
    }
    const siteArgs = sites.flatMap(p => ['--cmt',p]);
    assert.equal(JSON.parse(success(binary,[...siteArgs,'--format','json'])).census.total_sites,10000);
    const extraSite = compile('extra_site','let f () = 10 / 2\n');
    rejected([...siteArgs,'--cmt',extraSite],/site count exceeds 10000/);
    const nested = n => `let f () = ${'if true then ('.repeat(n)}10 / 2${') else 0'.repeat(n)}\n`;
    const base = compile('depth_base',nested(0)); const baseDepth = inspect(base).max_expression_depth;
    const exact = compile('depth_exact',nested(512-baseDepth));
    assert.equal(inspect(exact).max_expression_depth,512); assert.equal(report(exact).sites.length,1);
    const over = compile('depth_over',nested(513-baseDepth));
    assert.equal(inspect(over).max_expression_depth,513);
    rejected(['--cmt',over],/expression recursion depth exceeds 512/);
    return {expressionNodes:[100000,100001],sites:[10000,10001],depth:[512,513]};
  });
}
function owned() {
  const directory = path.join(root,'_build/default/lib/arch_index/.arch_index.objs/byte');
  // Only this explicit owned library directory; never recursively discover an external corpus.
  const artifacts = fs.readdirSync(directory).filter(n => n.endsWith('.cmt') && n.startsWith('arch_index__')).sort().map(n => path.join(directory,n));
  if (!artifacts.length) throw new Error('owned library artifacts missing; build @install first');
  const r = JSON.parse(success(binary,[...artifacts.flatMap(p => ['--cmt',p]),'--format','json']));
  validateReport(r);
  for (const args of [['--help'],['--version']]) {
    const direct=run(binary,args); assert.equal(direct.status,0,direct.stderr);
    const dispatched=run(path.join(root,'arch-guard'),args); assert.equal(dispatched.status,0,dispatched.stderr);
  }
  const isolated=fs.mkdtempSync(path.join(os.tmpdir(),'arch-guard-wrapper-'));
  try {
    const wrapper=path.join(isolated,'arch-guard'); fs.copyFileSync(path.join(root,'arch-guard'),wrapper); fs.chmodSync(wrapper,0o755);
    const before=fs.readdirSync(isolated).sort(); const missing=run(wrapper,['--version']);
    assert.equal(missing.status,2); assert.equal(missing.stdout,''); assert.match(missing.stderr,/binary not found; build arch_guard/);
    assert.deepEqual(fs.readdirSync(isolated).sort(),before,'wrapper must not build or install as a side effect');
  } finally { fs.rmSync(isolated,{recursive:true,force:true}); }
  const installPath=path.join(root,'_build/default/arch-index.install');
  const install=fs.readFileSync(installPath,'utf8');
  assert.match(install,/arch_guard(?:\.exe)?/,'fresh install manifest contains public arch_guard executable');
  assert.doesNotMatch(install,/lib\/arch_guard|arch_index__Arch_guard|META.*guard/,'private arch_guard library payload must not be installed');
  for (const executable of [probe,fixtureProbe,effectFixtureProbe,changedReadProbe]) assert(fs.statSync(executable).isFile(),`private probe missing: ${executable}`);
  return {scope:'explicit owned lib/arch_index artifacts only', census:r.census, publicCli:true, privateLibraryInstalled:false, probes:4};
}
try {
  const mode = process.argv[2];
  if (mode === '--assertion-control') assert.fail('deliberate assertion control');
  if (mode === '--execution-control') success('/nonexistent/arch-guard-checker-control', []);
  const modes = {domain, numeric, inventory, report: reportMode, inputs, owned, 'output-boundary':outputBoundary};
  if (!modes[mode]) throw new Error(`mode not implemented yet: ${mode}`);
  console.log(JSON.stringify({mode, result: modes[mode]()}));
} catch (error) {
  console.error(error.stack || String(error));
  process.exitCode = error instanceof assert.AssertionError ? 1 : 2;
}
