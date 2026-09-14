'use strict';

// Reuse delivered multiset accounting, not its historical permission to
// improve point-free reexports. Attempt2 changes invocations only.
const previous = require('../tezos-call-resolution/comparison.js');
function compareSnapshots(before, after, options = {}) {
  const result = previous.compareSnapshots(before, after, options);
  const changedAliases = [...result.changes.removed, ...result.changes.added]
    .filter(row => row.edge_form !== null);
  if (changedAliases.length) {
    result.errors.push(`attempt2 must preserve every reexport fact: ${changedAliases.length} changed rows`);
    result.ok = false;
  }
  return result;
}
module.exports = {...previous, compareSnapshots};
