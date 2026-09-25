// Static verifier for relative Dart imports in the AIDRA app.
//
// Catches, for every .dart file under lib/ and test/:
//   1. BROKEN     - a relative import that does not resolve to a real file
//   2. UNUSED     - every name exported by the target is absent from the body
//                   (matters because analysis_options.yaml sets
//                    unused_import to error)
//   3. AMBIGUOUS  - the same top-level name exported by two imported targets
//                   that is also used in the importing file's body
//
// Name extraction understands classes, mixins, enums, typedefs, named AND
// unnamed extensions (members included), top-level functions and top-level
// final/const/var/late variables, and follows `export` barrels.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, resolve, relative, posix } from 'node:path';

const ROOTS = ['lib', 'test'];
const files = [];

function walk(dir) {
  for (const entry of readdirSync(dir).sort()) {
    const full = resolve(dir, entry);
    if (statSync(full).isDirectory()) walk(full);
    else if (full.endsWith('.dart')) files.push(full);
  }
}
for (const root of ROOTS) {
  try {
    if (statSync(root).isDirectory()) walk(root);
  } catch {
    /* root missing */
  }
}

/** Collapse `\r\n` so line-based reasoning is stable. */
const read = (path) => readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const rel = (p) => relative(process.cwd(), p).split('\\').join('/');

/** Only real top-level types can collide in a way Dart rejects; extension
 *  members and locals must be excluded or `key:`/`label:`/`color:` named
 *  arguments show up as false ambiguities. */
function exportedTypes(path) {
  let src;
  try {
    src = read(path);
  } catch {
    return new Set();
  }
  const out = new Set();
  for (const m of src.matchAll(
    /^(?:@\w+(?:\([^)]*\))?\s*\n\s*)*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+([A-Za-z_]\w*)/gm,
  ))
    out.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:base\s+|sealed\s+)?(?:mixin|enum)\s+([A-Za-z_]\w*)/gm))
    out.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:extension\s+type\s+|typedef\s+)([A-Za-z_]\w*)/gm))
    out.add(m[1]);
  return out;
}

/** A file with only comments/imports/exports declares nothing of its own but
 *  may re-export a barrel, so we resolve those transitively. */
const BODYLESS = /^\s*$/;

/** Extract the set of top-level names a file makes visible to importers. */
function exportedNames(path, seen = new Set()) {
  if (seen.has(path)) return new Set();
  seen.add(path);

  let src;
  try {
    src = read(path);
  } catch {
    return new Set();
  }

  const names = new Set();

  // Follow `export 'x.dart';` barrels.
  for (const m of src.matchAll(/^\s*export\s+'([^']+)'\s*;?/gm)) {
    if (m[1].startsWith('package:') || m[1].startsWith('dart:')) continue;
    const barrel = resolve(dirname(path), m[1]);
    for (const n of exportedNames(barrel, seen)) names.add(n);
  }

  // Top-level declarations.
  for (const m of src.matchAll(
    /^(?:@\w+(?:\([^)]*\))?\s*\n\s*)*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+class\s+)*class\s+([A-Za-z_]\w*)/gm,
  ))
    names.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:base\s+|sealed\s+)?(?:mixin|enum)\s+([A-Za-z_]\w*)/gm))
    names.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:extension\s+type\s+|typedef\s+)([A-Za-z_]\w*)/gm))
    names.add(m[1]);

  // Extensions: named ones export the extension name, unnamed ones export the
  // member names. Cover both by collecting the name (if any) and the members.
  for (const m of src.matchAll(/^\s*extension\s+([A-Za-z_]\w*)?[^{]*\{/gm)) {
    if (m[1]) names.add(m[1]);

    const open = m.index + m[0].length - 1;
    let depth = 0;
    let i = open;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') {
        depth--;
        if (depth === 0) break;
      }
    }
    const body = src.slice(open, i);
    // Members: `Type get name`, `Type name(`, `static ...`.
    for (const mm of body.matchAll(/(?:get|set)\s+([A-Za-z_]\w*)/g)) names.add(mm[1]);
    for (const mm of body.matchAll(/([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(/g)) names.add(mm[1]);
  }

  // Top-level functions. The return type may be lowercase (double, int, bool,
  // String, void, num, dynamic) so a capitalised-only pattern under-collects
  // and reports live imports as unused.
  for (const m of src.matchAll(
    /^(?!(?:if|for|while|return|switch|case|else|do|try|await|yield|assert|final|const|var|late)\b)[A-Za-z_]\w*(?:<[^;{}]*>)?\??\s+([a-z]\w*)\s*(?:<[^>]*>)?\s*\(/gm,
  ))
    names.add(m[1]);

  // Top-level variables and providers.
  for (const m of src.matchAll(
    /^(?:final|const|late\s+final|late|var)\s+(?:[A-Za-z_][\w<>,?\s.]*?\s+)?([a-z_]\w*)\s*(?:=|;|\()/gm,
  ))
    names.add(m[1]);
  for (const m of src.matchAll(
    /^(?:final|const)\s+[A-Za-z_][\w<>,?\s.]*\s+([A-Za-z_]\w*)\s*=/gm,
  ))
    names.add(m[1]);

  // Private names are not visible across files.
  for (const n of [...names]) if (n.startsWith('_')) names.delete(n);
  return names;
}

/** Split a file into its import directives and the remaining body. */
function splitSource(src) {
  const importRe = /^\s*import\s+(?:'([^']+)'|"([^"]+)")\s*(?:as\s+\w+\s*)?(?:show\s+([^;]+?))?\s*;/gms;
  const imports = [];
  for (const m of src.matchAll(importRe)) {
    imports.push({ spec: m[1] ?? m[2], show: m[3], raw: m[0] });
  }
  const body = src.replace(importRe, '\n').replace(/^\s*(library|export)[^;]*;/gm, '\n');
  return { imports, body };
}

const IDENT = /[A-Za-z_]\w*/g;

const broken = [];
const unused = [];
const ambiguous = [];

for (const file of files) {
  const src = read(file);
  const { imports, body } = splitSource(src);
  const bodyWords = new Set(body.match(IDENT) ?? []);

  const byName = new Map(); // exported name -> [importer spec]

  for (const imp of imports) {
    // Anything without a scheme is resolved relative to the importing file.
    if (imp.spec.startsWith('dart:') || imp.spec.startsWith('package:')) continue;

    const target = resolve(dirname(file), imp.spec);

    let exists = true;
    try {
      statSync(target);
    } catch {
      exists = false;
    }
    if (!exists) {
      broken.push(`${rel(file)} -> ${imp.spec}`);
      continue;
    }

    let names = exportedNames(target);
    if (imp.show) {
      const shown = imp.show.split(',').map((s) => s.trim().split(/\s+as\s+/)[0].trim());
      for (const n of names) if (!shown.includes(n)) names.delete(n);
    }

    for (const n of exportedTypes(target)) {
      if (!byName.has(n)) byName.set(n, []);
      byName.get(n).push(imp.spec);
    }

    const bodyIsEmpty = BODYLESS.test(body);
    const used = names.size > 0 && [...names].some((n) => bodyWords.has(n));
    // A bodyless file is a barrel/aggregator: re-exports are the point.
    if (!used && !bodyIsEmpty && names.size > 0) {
      unused.push(`${rel(file)} -> ${imp.spec}  [targets export: ${[...names].slice(0, 6).join(', ')}${names.size > 6 ? ', …' : ''}]`);
    }
    if (names.size === 0 && !bodyIsEmpty) {
      unused.push(`${rel(file)} -> ${imp.spec}  [target exposes NO top-level names]`);
    }
  }

  for (const [name, specs] of byName) {
    const distinct = [...new Set(specs)];
    if (distinct.length > 1 && bodyWords.has(name)) {
      ambiguous.push(`${relative(process.cwd(), file).split('\\').join('/')}: ${name} from ${distinct.join(' | ')}`);
    }
  }
}

const section = (title, rows) => {
  console.log(`\n${title} (${rows.length})`);
  console.log(rows.length ? rows.map((r) => '  - ' + r).join('\n') : '  none');
};

console.log(`Checked ${files.length} Dart files.`);
section('BROKEN IMPORTS', broken);
section('UNUSED IMPORTS', unused);
section('AMBIGUOUS NAMES', ambiguous);
console.log(
  `\nTotal: ${broken.length + unused.length + ambiguous.length} issue(s).`,
);
