#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {parseLog, validCell, successfulSourceOnlyDiagnostic} = require('./check-self.js');

const log = `recalibrate: baseline e8d072ec491c05637cacb76e4fe1b99367aa119f = e8d072e
recalibrate: head              = 1234567890abcdef
recalibrate: building baseline…
recalibrate: building head…

── golden (descriptive, measured over _build/default/lib/arch_index)
   A base bin/base src          modules: 25 functions: 999 calls: 6332
   B  NEW bin/base src          modules: 25 functions: 999 calls: 6332
   C base bin/ NEW src          modules: 25 functions: 1000 calls: 6340
   D  NEW bin/ NEW src          modules: 25 functions: 1000 calls: 6340
   → attributable to source change only (B = A).

── ceiling (ratchet, measured over _build/default)
   A base bin/base src          500
   B  NEW bin/base src          500
   C base bin/ NEW src          501
   D  NEW bin/ NEW src          501
   → attributable to source change only (B = A).
   ✗ STALE: pinned reference differs from D.
`;

try {
  const parsed = parseLog(Buffer.from(log));
  assert.equal(parsed.baseline, 'e8d072ec491c05637cacb76e4fe1b99367aa119f');
  assert.equal(parsed.head, '1234567890abcdef');
  assert.equal(parsed.builtBase, true); assert.equal(parsed.builtHead, true);
  assert.equal(parsed.sourceOnly.golden, true); assert.equal(parsed.sourceOnly.ceiling, true);
  assert.equal(successfulSourceOnlyDiagnostic(parsed, Buffer.from(log), '1234567890abcdef1234567890abcdef12345678'), true,
    'a stale diagnostic remains valid pre-refresh attribution evidence');
  assert.equal(parsed.cells.golden.D, 'modules: 25 functions: 1000 calls: 6340');
  assert.equal(parsed.cells.ceiling.A, '500');
  assert.equal(validCell('golden', parsed.cells.golden.A), true);
  assert.equal(validCell('ceiling', parsed.cells.ceiling.A), true);
  assert.equal(validCell('golden', 'modules: 0 functions: 1 calls: 1'), false);
  assert.equal(validCell('ceiling', '05'), false);
  assert.equal(validCell('ceiling', '0'), false);
  assert.throws(() => parseLog(Buffer.from(log.replace('   B  NEW bin/base src          500', '   A  NEW bin/base src          500'))), /repeats ceiling cell A/);
  assert.throws(() => parseLog(Buffer.from(log.replace('── ceiling', '── golden'))), /repeats golden metric/);
  const noSourceOnly = parseLog(Buffer.from(log.replace('   → attributable to source change only (B = A).', '   → BEHAVIOURAL.')));
  assert.equal(successfulSourceOnlyDiagnostic(noSourceOnly, Buffer.from(log.replace('   → attributable to source change only (B = A).', '   → BEHAVIOURAL.')), '1234567890abcdef1234567890abcdef12345678'), false);
  assert.equal(successfulSourceOnlyDiagnostic(parsed, Buffer.from(log + 'recalibrate: refusal-class=degraded metric=golden\n'), '1234567890abcdef1234567890abcdef12345678'), false);
  console.log('PASS CHECK5 parser: complete unique 2x2 and malformed-cell refusals');
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
