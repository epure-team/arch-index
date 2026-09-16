#!/usr/bin/env node
'use strict';

const foundation = require('../ocaml-cfa-foundation/check-domain.js');

try {
  foundation.buildProbe();
  const cases = foundation.cases().map(testCase => ({
    ...testCase,
    operations: testCase.operations.map(operation =>
      operation[0] === 'reason' && operation[2] === 'opaque'
        ? ['reason', operation[1], 'callback_param']
        : operation),
  }));
  const result = foundation.runCheck({cases});
  process.stdout.write(
    `PASS CHECK1 typed finite-domain oracle (${result.cases} cases)\n`,
  );
} catch (error) {
  process.stderr.write(
    `${error.name === 'AssertionError' ? 'ASSERTION' : 'SETUP'}: ${error.message}\n`,
  );
  process.exitCode = foundation.exitCode(error);
}
