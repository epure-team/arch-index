'use strict';

// Reuse the audited Stage-2 2x2 implementation with this task's frozen base,
// manifest and evidence directory.  The replacement assertions fail closed if
// the inherited checker changes instead of silently running the wrong inputs.
const fs = require('node:fs');
const path = require('node:path');

const inherited = path.resolve(__dirname, '../ocaml-cfa-foundation/calibrate-self.js');
let source = fs.readFileSync(inherited, 'utf8');
const replaceOnce = (before, after) => {
  const index = source.indexOf(before);
  if (index < 0 || source.indexOf(before, index + before.length) >= 0)
    throw new Error(`inherited calibrator seam changed: ${before}`);
  source = source.replace(before, after);
};
replaceOnce(
  "const BASE = 'c397efd1b2248564c05c74fdab795213dea593db';",
  "const BASE = '60cc88be2db717b0c4727b1206ab666570585df1';",
);
replaceOnce(
  "const MANIFEST = path.join(ROOT, 'briefs/ocaml-cfa-foundation-manifest.txt');",
  "const MANIFEST = path.join(ROOT, 'briefs/ocaml-cfa-propagation-manifest.txt');",
);
replaceOnce(
  "const OUTPUT_PARENT = path.join(ROOT, 'improvement/2026-09-16-cfa');",
  "const OUTPUT_PARENT = path.join(ROOT, 'improvement/2026-09-16-cfa-propagation');",
);

new Function('require', '__dirname', 'module', 'exports', source)(
  require,
  __dirname,
  module,
  exports,
);
