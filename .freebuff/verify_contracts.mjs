// Contract checks: does `class Impl implements Interface` declare every member
// the interface requires? Dart refuses to compile otherwise, and in a
// hand-written repository-pattern codebase this is the likeliest real error.
//
// Member extraction is depth-aware: a member is declared on a line that starts
// at brace depth 0 inside the class body, so method bodies, parameter lists and
// collection literals (depth >= 1) never contribute names.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, relative } from 'node:path';

const files = [];
for (const root of ['lib', 'test']) {
  (function walk(dir) {
    let entries;
    try {
      entries = readdirSync(dir).sort();
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = resolve(dir, entry);
      if (statSync(full).isDirectory()) walk(full);
      else if (full.endsWith('.dart')) files.push(full);
    }
  })(root);
}

const read = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const rel = (p) => relative(process.cwd(), p).split('\\').join('/');

const sources = new Map();
for (const f of files) sources.set(f, read(f));

/** Balanced `{ ... }` body starting at the opening brace index. */
function bodyAt(src, open) {
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') {
      depth--;
      if (depth === 0) return src.slice(open + 1, i);
    }
  }
  return src.slice(open + 1);
}

/** Remove comments so annotations/doc text can't be parsed as declarations. */
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .split('\n')
    .map((line) => (/^\s*\/\//.test(line) ? '' : line.replace(/\s\/\/.*$/, '')))
    .join('\n');
}

const CONSTRUCTORISH = /^(?:[A-Z][\w]*)$/;

/** Top-of-body member names declared in a class/interface body. */
function memberNames(body, className) {
  const clean = stripComments(body);
  const out = new Set();

  let depth = 0;
  for (const rawLine of clean.split('\n')) {
    const startDepth = depth;
    depth += (rawLine.match(/[{[]/g) ?? []).length;
    depth -= (rawLine.match(/[}\]]/g) ?? []).length;
    if (depth < 0) depth = 0;

    if (startDepth !== 0) continue;
    let line = rawLine.trim();
    if (!line || '})],.'.includes(line[0])) continue;

    // Drop annotations (@override, @JsonKey(name: 'x')).
    let guard = 0;
    while (line.startsWith('@') && guard++ < 10) {
      const withArgs = line.match(/^@\w+\([^)]*\)\s*/);
      line = withArgs ? line.slice(withArgs[0].length) : line.replace(/^@\w+\s*/, '');
    }
    if (!line) continue;

    // Getters and setters.
    const accessor = line.match(/\b(?:get|set)\s+([A-Za-z_]\w*)/);
    if (accessor) out.add(accessor[1]);

    // Methods: identifier immediately before '('.
    const call = line.match(/([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(/);
    if (call) out.add(call[1]);

    // Fields: `Type name = ...` or `Type name;`
    const field = line.match(
      /^\s*(?:static\s+)?(?:final\s+|const\s+|late\s+|var\s+)?[A-Za-z_][\w<>,?.\s]*?\s+([A-Za-z_]\w*)\s*(?:=|;)/,
    );
    if (field) out.add(field[1]);
  }

  out.delete(className); // own constructor
  return out;
}

const CLASS_RE =
  /^[ \t]*(?:(?:abstract|sealed|final|base|interface)\s+)*class\s+([A-Za-z_]\w*)(?:<[^{]*>)?\s*(?:extends\s+[A-Za-z_]\w*(?:<[^>]*>)?[^{]*?)?\s*(?:with\s+[^{]*?)?\s*(?:implements\s+([^{]*?))?\s*\{/gm;

const classes = new Map();
const impls = [];

for (const [f, src] of sources) {
  for (const m of src.matchAll(CLASS_RE)) {
    const declaration = m[0];
    const name = m[1];
    const isAbstract = /(?:^|\s)(?:abstract|sealed)\s+class\s/.test(declaration);
    const open = m.index + declaration.length - 1;
    const body = bodyAt(src, open);

    const record = {
      name,
      abstract: isAbstract,
      members: memberNames(body, name),
      file: f,
    };
    if (!classes.has(name)) classes.set(name, record);

    const ifaceList = m[2];
    if (ifaceList) {
      impls.push({
        name,
        file: f,
        members: record.members,
        interfaces: ifaceList
          .split(',')
          .map((s) => s.trim().split('<')[0].trim())
          .filter((s) => /^[A-Za-z_]\w*$/.test(s)),
      });
    }
  }
}

const missing = [];
const external = [];

for (const impl of impls) {
  for (const iface of impl.interfaces) {
    const base = classes.get(iface);
    if (!base) {
      external.push(`${rel(impl.file)}: ${impl.name} implements ${iface} (not declared in this project — skipped)`);
      continue;
    }
    for (const member of base.members) {
      if (!impl.members.has(member)) {
        missing.push(
          `${rel(impl.file)}: ${impl.name} does not implement '${member}' of ${iface} (${rel(base.file)})`,
        );
      }
    }
  }
}

console.log(`Contract check: ${classes.size} classes, ${impls.length} implement-clause(s).\n`);

const section = (title, rows) => {
  console.log(`${title} (${rows.length})`);
  console.log(rows.length ? [...new Set(rows)].map((r) => '  - ' + r).join('\n') : '  none');
  console.log('');
};

if (process.env.SHOW_MEMBERS) {
  for (const iface of ['AuthRepository', 'ReportRepository']) {
    const c = classes.get(iface);
    console.log(`${iface} requires: ${c ? [...c.members].sort().join(', ') : 'NOT FOUND'}`);
    for (const impl of impls.filter((i) => i.interfaces.includes(iface))) {
      console.log(`  ${impl.name} provides: ${[...impl.members].sort().join(', ')}`);
    }
    console.log('');
  }
}

section('UNSATISFIED INTERFACE MEMBERS', missing);
section('EXTERNAL INTERFACES (skipped)', external);
