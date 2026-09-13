#!/usr/bin/env node
'use strict';
// Independent contract assertions: no expected results are supplied by the OCaml probe.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const binary = process.env.ARCH_GUARD || path.join(root, '_build/default/bin/arch_guard/arch_guard.exe');
const probe = process.env.ARCH_GUARD_DOMAIN_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/domain_probe.exe');
const fixtureProbe = process.env.ARCH_GUARD_FIXTURE_PROBE || path.join(root, '_build/default/tezt/fixtures/arch_guard/fixture_probe.exe');
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
function report(cmt) { return JSON.parse(success(binary, ['--cmt', cmt, '--format', 'json'])); }
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
function census(r) {
  assert.equal(r.census.artifacts, r.inputs.length);
  assert.equal(r.census.total_sites, r.sites.length);
  const names = {NONZERO: 'nonzero', ZERO: 'zero', MAY_ZERO: 'may_zero', UNREACHABLE: 'unreachable', UNSUPPORTED: 'unsupported'};
  for (const [status, name] of Object.entries(names)) assert.equal(r.census[name], r.sites.filter(s => s.status === status).length);
  assert.equal(r.census.numeric_covered, r.census.nonzero + r.census.zero + r.census.may_zero + r.census.unreachable);
  assert.equal(r.census.total_sites, r.census.numeric_covered + r.census.unsupported);
  assert.equal(r.census.precision_gain_sites, r.census.nonzero + r.census.unreachable);
}
function numeric() {
  const cases = [
    ['let f () = let a = 2 in let b = a in 10 / b', 'NONZERO'],
    ['let f () = let a = 2 in let a = 0 in 10 / a', 'ZERO'],
    ['let f () = let a = 2 in let a = 0 and b = a in 10 / b', 'NONZERO'],
    ['let f d = if 0 <> d then 10 / d else 0', 'NONZERO'],
    ['let f d = if 0 = d then 10 / d else 0', 'ZERO'],
    ['let f d = if d == 0 then 10 / d else 0', 'ZERO'],
    ['let f d = if d != 0 then 10 / d else 0', 'NONZERO'],
    ['let f d = if d > 0 then 10 / d else 0', 'MAY_ZERO'],
    ['let f () = if false then 10 / 2 else 0', 'UNREACHABLE'],
    ['let f () = if false then [|10 / 2|] else [||]', 'UNSUPPORTED'],
    ['let f () = if false then (fun () -> 10 / 2) else (fun () -> 0)', 'NONZERO'],
    ['let f () = let d = 2 in (fun () -> 10 / d)', 'MAY_ZERO'],
    ['let f g = let d = g () in 10 / d', 'MAY_ZERO'],
    ['let f g d = g (10 / d)', 'MAY_ZERO'],
    ['let f () = let d = 3 - 3 in 10 / d', 'ZERO'],
    ['let f () = let d = 2 * 3 + 1 in 10 / d', 'NONZERO'],
    ['let f () = let d = -2 in 10 / d', 'NONZERO'],
    ['let f b = let d = if b then 2 else 3 in 10 / d', 'NONZERO'],
    ['let f () = let (d, _) = (2, 0) in 10 / d', 'UNSUPPORTED'],
    ['let rec f d = 10 / d', 'UNSUPPORTED'],
    ['let f ?(d=2) () = 10 / d', 'UNSUPPORTED'],
    ['let f = function d -> 10 / d', 'UNSUPPORTED'],
    ['let f d = lazy (10 / d)', 'UNSUPPORTED'],
    ['let f d = false && (10 / d = 0)', 'UNSUPPORTED'],
    // OCaml 5.3 emits Tpat_alias(Tpat_any, d) for an annotated parameter:
    // alias patterns are explicitly outside the selected fragment.
    ['type integer = int\nlet f (d : integer) = if d <> 0 then 10 / d else 0', 'UNSUPPORTED'],
    ['type integer = int\nlet f () = 10 / (2 : integer)', 'NONZERO'],
  ];
  cases.forEach(([source, expected], index) => withFixture(source + '\n', cmt => {
    const r = report(cmt); census(r); assert.equal(r.sites.length, 1, `numeric case ${index}: site count`);
    assert.equal(r.sites[0].status, expected, `numeric case ${index}: ${source}; reasons=${r.sites[0].reasons}`);
  }));
  const source = fs.readFileSync(path.join(root, 'tezt/fixtures/arch_guard/inventory.ml'), 'utf8');
  const expected = new Map([[1,'NONZERO'],[2,'UNSUPPORTED'],[3,'UNSUPPORTED'],[4,'UNSUPPORTED'],[5,'UNSUPPORTED'],[8,'UNSUPPORTED'],[10,'NONZERO'],[11,'NONZERO'],[12,'MAY_ZERO'],[13,'UNREACHABLE'],[14,'MAY_ZERO'],[15,'ZERO']]);
  return withFixture(source, cmt => {
    const r = report(cmt); census(r);
    assert.equal(r.sites.length, expected.size);
    for (const s of r.sites) { assert.equal(s.status, expected.get(s.location.start.line), `site line ${s.location.start.line}`); expected.delete(s.location.start.line); }
    assert.equal(expected.size, 0);
    return {additionalCases:cases.length, census:r.census};
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
    return r.census;
  });
}
function keys(object, names) { assert.deepEqual(Object.keys(object).sort(), names.split(' ').sort()); }
function validateReport(r) {
  keys(r, 'schema_version tool analysis outcome inputs sites census');
  assert.equal(r.schema_version, 1);
  keys(r.tool, 'name version compiler_version int_bits');
  assert.equal(r.tool.name, 'arch-guard'); assert.equal(r.tool.version, '0.1.0');
  assert.equal(typeof r.tool.compiler_version, 'string'); assert([31,63].includes(r.tool.int_bits));
  keys(r.analysis, 'mode fragment domain assumptions limitations');
  assert.equal(r.analysis.mode, 'experimental-report-only');
  assert.equal(r.analysis.fragment, 'ocaml-int-acyclic-v1');
  assert.equal(r.analysis.domain, 'constant-zero-v1');
  for (const list of [r.analysis.assumptions, r.analysis.limitations]) { assert(Array.isArray(list)); list.forEach(x => assert.equal(typeof x, 'string')); }
  assert.match(r.analysis.assumptions.join(' '), /trusted.*same-compiler.*same-target/);
  assert.match(r.analysis.limitations.join(' '), /no machine-checked proof/);
  assert.equal(r.outcome, r.sites.length ? 'classified' : 'empty_inventory');
  keys(r.census, 'artifacts total_sites numeric_covered nonzero zero may_zero unreachable unsupported precision_gain_sites');
  Object.values(r.census).forEach(n => assert(Number.isSafeInteger(n) && n >= 0));
  census(r);
  const seen = new Set();
  r.inputs.forEach(i => { keys(i, 'path sha256 module source bytes'); assert(path.isAbsolute(i.path)); assert.match(i.sha256, /^[a-f0-9]{64}$/); assert.equal(typeof i.module, 'string'); assert(i.source === null || typeof i.source === 'string'); assert(Number.isSafeInteger(i.bytes) && i.bytes >= 0); });
  assert.deepEqual(r.inputs.map(i => i.path), r.inputs.map(i => i.path).sort());
  r.sites.forEach(s => {
    keys(s, 'artifact id primitive integer_kind operand location status reasons');
    assert(r.inputs.some(i => i.path === s.artifact));
    assert(Number.isSafeInteger(s.id) && s.id > 0);
    const identity = `${s.artifact}:${s.id}`; assert(!seen.has(identity)); seen.add(identity);
    assert(['NONZERO','ZERO','MAY_ZERO','UNREACHABLE','UNSUPPORTED'].includes(s.status));
    const families = {'%divint':'int','%modint':'int','%int32_div':'int32','%int32_mod':'int32','%int64_div':'int64','%int64_mod':'int64','%nativeint_div':'nativeint','%nativeint_mod':'nativeint'};
    assert.equal(s.integer_kind, families[s.primitive]); assert(Object.hasOwn(families,s.primitive));
    keys(s.operand, 'slot category representation'); assert.equal(s.operand.slot, 2);
    assert(['integer_literal','identifier','other','missing'].includes(s.operand.category));
    assert(s.operand.representation === null || typeof s.operand.representation === 'string');
    if (s.operand.category === 'identifier' && s.operand.representation !== null) assert(Buffer.byteLength(s.operand.representation) <= 256);
    if (['other','missing'].includes(s.operand.category)) assert.equal(s.operand.representation,null);
    keys(s.location, 'file start end ghost'); assert.equal(typeof s.location.ghost, 'boolean');
    for (const p of [s.location.start, s.location.end]) {
      keys(p, 'line column offset');
      if (p.line === null) assert.deepEqual(p, {line: null, column: null, offset: null});
      else { assert(p.line >= 1); assert(p.column >= 1); assert(p.offset >= 0); }
    }
    assert(s.reasons.length > 0); assert.deepEqual(s.reasons, [...new Set(s.reasons)].sort());
    const closed = ['divisor_nonzero_if_reached','divisor_zero_if_reached','divisor_may_be_zero','contradictory_supported_branch','unsupported_arity','unsupported_labels','missing_operand','unsupported_integer_kind','unsupported_operand_type','unsupported_function_parameters','unsupported_function_cases','unsupported_recursive_binding','unsupported_binding_pattern','unsupported_short_circuit','unsupported_effect_primitive','operand_spelling_omitted','location_unavailable','ghost_location'];
    for (const reason of s.reasons) assert(closed.includes(reason) || /^unsupported_expression:T(?:exp|cl)_[a-z_]+$/.test(reason), `unknown reason ${reason}`);
  });
  const tuple = s => [s.artifact,s.location.start.offset,s.location.end.offset,s.primitive,s.id];
  function compare(a,b) {
    a=tuple(a); b=tuple(b);
    for (let i=0;i<a.length;i++) {
      if (a[i] === b[i]) continue;
      if (a[i] === null) return -1;
      if (b[i] === null) return 1;
      return a[i] < b[i] ? -1 : 1;
    }
    return 0;
  }
  assert.deepEqual(r.sites, [...r.sites].sort(compare));
}
function reportMode() {
  const boundary = outputBoundary();
  withFixture('let empty = 1\n', cmt => {
    const r = report(cmt); validateReport(r); assert.equal(r.sites.length, 0);
    assert.match(success(binary, ['--cmt', cmt]), /No matching immediate primitive occurrences in supplied artifacts\./);
  });
  return withFixture('let f d = 10 / d\n', (cmt, dir) => {
    const r = report(cmt); validateReport(r);
    for (const location of ['invalid','ghost','cross-file','backwards','max-column']) {
      const output = path.join(dir, `${location}.cmt`);
      success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation','implementation','--location',location]);
      const mutated = report(output); validateReport(mutated); const s = mutated.sites[0];
      assert.equal(mutated.sites.length, 1);
      if (location === 'ghost') { assert(s.location.ghost); assert(s.reasons.includes('ghost_location')); }
      if (location === 'invalid') { assert.equal(s.location.file, null); assert.equal(s.location.start.line, null); }
      if (['cross-file','backwards','invalid'].includes(location)) { assert.equal(s.location.end.line, null); assert(s.reasons.includes('location_unavailable')); }
      if (location === 'max-column') assert.equal(s.location.start.column, Number(1n << BigInt(mutated.tool.int_bits - 1)));
    }
    const output = path.join(dir, 'spelling.cmt');
    success(fixtureProbe, ['rewrite','--input',cmt,'--output',output,'--annotation','implementation','--long-identifier']);
    const s = report(output).sites[0]; assert.equal(s.operand.representation, null); assert(s.reasons.includes('operand_spelling_omitted'));
    const text = success(binary, ['--cmt', cmt]);
    for (const [name, n] of Object.entries(r.census)) assert(text.includes(`${name}: ${n}\n`));
    assert.match(text, /MAY_ZERO %divint/);
    assert.match(text, /fixture\.ml:1:/, 'text must expose application source location');
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
  return {scope:'explicit owned lib/arch_index artifacts only', census:r.census};
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
