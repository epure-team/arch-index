#!/usr/bin/env node
// ts-morph arch_index shim — embedded via ppx_blob in ts_enricher.ml
// Usage: node ts_shim.js <project_root>
// Output: newline-delimited JSON records to stdout, one per symbol
// Stderr: diagnostic messages
// Exit 1 if ts-morph unavailable or project has no tsconfig.json
'use strict';

const path = require('path');
const fs = require('fs');

const projectRoot = process.argv[2];
if (!projectRoot) {
  process.stderr.write('Usage: ts_shim.js <project_root>\n');
  process.exit(1);
}

// Require ts-morph; exit 1 if not installed in the target project.
let Project;
try {
  const tsMorphPath = require.resolve('ts-morph', { paths: [projectRoot, __dirname] });
  ({ Project } = require(tsMorphPath));
} catch (_) {
  process.stderr.write('ts-morph not available in project or globally\n');
  process.exit(1);
}

// Find tsconfig.json in project root or common locations.
function findTsConfig(root) {
  const candidates = [
    path.join(root, 'tsconfig.json'),
    path.join(root, 'tsconfig.base.json'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return null;
}

const tsConfigPath = findTsConfig(projectRoot);
if (!tsConfigPath) {
  process.stderr.write('No tsconfig.json found in ' + projectRoot + '\n');
  process.exit(1);
}

let project;
try {
  project = new Project({
    tsConfigFilePath: tsConfigPath,
    skipAddingFilesFromTsConfig: false,
    skipFileDependencyResolution: true,
  });
} catch (err) {
  process.stderr.write('ts-morph init error: ' + String(err.message || err) + '\n');
  process.exit(1);
}

function emit(record) {
  process.stdout.write(JSON.stringify(record) + '\n');
}

function safeTypeSig(node, fn) {
  try { return fn(node); } catch (_) { return null; }
}

try {
  for (const src of project.getSourceFiles()) {
    const filePath = src.getFilePath();

    // Top-level functions
    for (const fn of src.getFunctions()) {
      const name = fn.getName();
      if (!name) continue;
      const params = fn.getParameters().map(p => {
        try { return p.getName() + ': ' + p.getType().getText(p); } catch (_) { return p.getName(); }
      }).join(', ');
      const ret = safeTypeSig(fn, f => f.getReturnType().getText(f));
      emit({
        name,
        file_path: filePath,
        line: fn.getStartLineNumber(),
        end_line: fn.getEndLineNumber(),
        kind: 'function',
        type_sig: '(' + params + ')' + (ret ? ': ' + ret : ''),
        exported: fn.isExported(),
      });
    }

    // Classes and their methods
    for (const cls of src.getClasses()) {
      const clsName = cls.getName();
      if (!clsName) continue;
      const clsExported = cls.isExported();
      for (const method of cls.getMethods()) {
        const mName = method.getName();
        const params = method.getParameters().map(p => {
          try { return p.getName() + ': ' + p.getType().getText(p); } catch (_) { return p.getName(); }
        }).join(', ');
        const ret = safeTypeSig(method, m => m.getReturnType().getText(m));
        emit({
          name: clsName + '.' + mName,
          file_path: filePath,
          line: method.getStartLineNumber(),
          end_line: method.getEndLineNumber(),
          kind: 'method',
          type_sig: '(' + params + ')' + (ret ? ': ' + ret : ''),
          exported: clsExported,
        });
      }
    }

    // Interfaces
    for (const iface of src.getInterfaces()) {
      const ifaceName = iface.getName();
      if (!ifaceName) continue;
      emit({
        name: ifaceName,
        file_path: filePath,
        line: iface.getStartLineNumber(),
        end_line: iface.getEndLineNumber(),
        kind: 'interface',
        type_sig: null,
        exported: iface.isExported(),
      });
    }

    // Exported type aliases
    for (const typeAlias of src.getTypeAliases()) {
      const taName = typeAlias.getName();
      if (!typeAlias.isExported()) continue;
      const sig = safeTypeSig(typeAlias, t => t.getType().getText(t));
      emit({
        name: taName,
        file_path: filePath,
        line: typeAlias.getStartLineNumber(),
        end_line: typeAlias.getEndLineNumber(),
        kind: 'type',
        type_sig: sig,
        exported: true,
      });
    }
  }
} catch (err) {
  process.stderr.write('ts-morph analysis error: ' + String(err.message || err) + '\n');
  process.exit(1);
}
