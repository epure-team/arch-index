#!/usr/bin/env node
// CHECK-1 (spec FR-001) — a qualified call resolves within the library the
// reference names, not into a same-named file in an unrelated library.
//
// RED at origin/main@cde3aad: `Liba.Api.run` resolves to libb/api.ml, stamped
// MUST. Resolution keys on the capitalised file BASENAME ("Api") in a
// project-wide last-writer-wins table, so the owning library is erased and
// whichever api.ml was indexed last wins for every library.
//
// The MUST is what makes this a soundness bug rather than a precision one: the
// edge is asserted as proven fact, so a downstream reachability query can turn a
// real violation into a PASS. Wrong-and-confident is strictly worse than
// unknown-and-honest.
//
//   0 = resolves correctly   1 = mis-attributed (bug present)   >=2 = setup failure

const { buildAndIndex, query, verdict } = require("./lib/fixture");

const files = {
  "dune-project": "(lang dune 3.0)\n",

  // Two libraries, each owning a module of the SAME basename api.ml, each
  // defining `run`. This is the homonym shape: 540 of 14452 proto_alpha
  // function names are shared this way (measured by the error-channels review),
  // so it is the common case at corpus scale, not a contrived one.
  "liba/dune": "(library (name liba))\n",
  "liba/api.ml": "let run () = 1\n",

  "libb/dune": "(library (name libb))\n",
  "libb/api.ml": "let run () = 2\n",

  // The caller links BOTH, and calls each explicitly by its own library.
  // There is exactly one correct answer per call site.
  "app/dune": "(executable (name main) (libraries liba libb))\n",
  "app/main.ml":
    "let calls_a () = Liba.Api.run ()\n" +
    "let calls_b () = Libb.Api.run ()\n" +
    "let () = ignore (calls_a () + calls_b ())\n",
};

const { db } = buildAndIndex("homonym", files);

// callee_name -> the module path it actually resolved to (or a marker).
const rows = query(
  db,
  `SELECT c.callee_name || '|' || c.kind || '|' || COALESCE(tm.path, '<unresolved>')
     FROM calls c
     LEFT JOIN functions tf ON c.callee_id = tf.id
     LEFT JOIN modules   tm ON tf.module_id = tm.id
    WHERE c.callee_name IN ('Liba.Api.run', 'Libb.Api.run')
    ORDER BY c.callee_name;`
);

const got = Object.fromEntries(
  rows.map((r) => {
    const [name, kind, resolved] = r.split("|");
    return [name, { kind, resolved }];
  })
);

const a = got["Liba.Api.run"];
const b = got["Libb.Api.run"];

if (!a || !b) {
  // Both call sites must exist at all, or the check is vacuous rather than green.
  require("./lib/fixture").setupFail(
    `expected both call sites in the index, got: ${JSON.stringify(got)}`
  );
}

// The defect is specifically CROSS-LIBRARY attribution. Assert each call lands
// in its OWN library, not merely that the two differ — two symmetrical wrong
// answers would satisfy a weaker "they differ" test.
const aOk = a.resolved === "liba/api.ml";
const bOk = b.resolved === "libb/api.ml";

verdict(aOk && bOk, {
  pass: `Liba.Api.run -> ${a.resolved} (${a.kind}), Libb.Api.run -> ${b.resolved} (${b.kind}) — each resolves within its own library`,
  fail:
    `qualified calls mis-attributed across libraries:\n` +
    `  Liba.Api.run -> ${a.resolved} (${a.kind})   expected liba/api.ml\n` +
    `  Libb.Api.run -> ${b.resolved} (${b.kind})   expected libb/api.ml\n` +
    `  resolution keys on the bare basename "Api", so the owning library is erased`,
});
