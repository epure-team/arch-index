#!/usr/bin/env node
// CHECK-2 (spec FR-002) — REGRESSION GUARD. A module alias must still resolve to
// the implementation it forwards to.
//
// This is GREEN at origin/main@cde3aad and must stay green. It is here because
// the abandoned rebase/sound-qual branch BROKE exactly this case (to
// MAY_TOP/NULL) while fixing CHECK-1's defect, and no gate saw it — that
// regression, repo-wide MAY_TOP 660 -> 875, is what made its round 2 a NO-GO.
//
// The shape: library `foo` owns BOTH bar.ml (unit Foo__Bar) and a main module
// foo.ml whose entire content is `module Bar = Bar` (unit Foo). A reference
// `Foo.Bar.baz` then has two structurally valid readings —
//   (a) Foo is the library wrapper, Bar a unit inside it   -> Foo__Bar
//   (b) Foo IS the compilation unit, Bar nested inside it  -> Foo
// and BOTH units exist, so both readings are live.
//
// Note for anyone tempted to disambiguate this with cmt_imports interface
// digests (the abandoned branch's approved round-3 design): it does not work.
// The caller imports ALL THREE of Foo, Foo__ and Foo__Bar, because it genuinely
// depends on the alias AND on the implementation the alias forwards to. Verified
// with ocamlobjinfo; see briefs/qualified-unit-resolution-research.md Finding 3.
// What DOES decide it is that an alias defines no function, so only reading (a)
// has a row to resolve against.
//
//   0 = still resolves   1 = regressed   >=2 = setup failure

const { buildAndIndex, query, verdict, setupFail } = require("./lib/fixture");

const files = {
  "dune-project": "(lang dune 3.0)\n",

  "libfoo/dune": "(library (name foo))\n",
  // bar.ml -> unit Foo__Bar. The real implementation lives here.
  "libfoo/bar.ml": "let baz () = 42\n",
  // foo.ml is the library's MAIN module -> unit Foo. Pure alias: defines no
  // function of its own, which is precisely what breaks the tie.
  "libfoo/foo.ml": "module Bar = Bar\n",

  "app/dune": "(executable (name main) (libraries foo))\n",
  "app/main.ml": "let run () = Foo.Bar.baz ()\nlet () = ignore (run ())\n",
};

const { db } = buildAndIndex("alias", files);

const rows = query(
  db,
  `SELECT c.kind || '|' || COALESCE(tm.path, '<unresolved>')
     FROM calls c
     LEFT JOIN functions tf ON c.callee_id = tf.id
     LEFT JOIN modules   tm ON tf.module_id = tm.id
    WHERE c.callee_name = 'Foo.Bar.baz';`
);

if (rows.length !== 1) {
  setupFail(`expected exactly one Foo.Bar.baz call site, got ${rows.length}: ${JSON.stringify(rows)}`);
}

const [kind, resolved] = rows[0].split("|");

// Both halves matter. Resolving to the right file with kind=MAY_TOP would still
// be the regression this guard exists to catch: the abandoned branch kept
// finding nothing and degraded the edge, rather than mis-resolving it.
const ok = resolved === "libfoo/bar.ml" && kind === "MUST";

verdict(ok, {
  pass: `Foo.Bar.baz -> ${resolved} (${kind}) — alias still resolves through to the implementation`,
  fail:
    `alias resolution regressed:\n` +
    `  Foo.Bar.baz -> ${resolved} (${kind})\n` +
    `  expected     libfoo/bar.ml (MUST)\n` +
    `  a MAY_TOP here means both readings were treated as live and the edge was\n` +
    `  degraded instead of resolved — the exact round-2 regression of rebase/sound-qual`,
});
