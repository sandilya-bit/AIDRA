// Semantic checks for the AIDRA Flutter app, runnable without a Dart toolchain.
//
//   1. BALANCE     - () [] {} balance per file (syntax sanity), strings and
//                    comments stripped first
//   2. PROVIDERS   - every `ref.watch/read/listen(xProvider)` resolves to a
//                    provider declared in the file or its import closure
//   3. ENUM MEMBER - every `SomeEnum.member` names a real member of a Dart
//                    enum declared somewhere in the project
//   4. L10N KEYS   - every tr('key') exists in the English catalogue, so the
//                    UI can never render a raw key
//   5. ROUTES      - every AppRoutes.x exists
//   6. DEPS        - every package: import is declared in pubspec.yaml

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';

const files = [];
(function walk(dir) {
  for (const entry of readdirSync(dir).sort()) {
    const full = resolve(dir, entry);
    if (statSync(full).isDirectory()) walk(full);
    else if (full.endsWith('.dart')) files.push(full);
  }
})('lib');
(function walk(dir) {
  for (const entry of readdirSync(dir).sort()) {
    const full = resolve(dir, entry);
    if (statSync(full).isDirectory()) walk(full);
    else if (full.endsWith('.dart')) files.push(full);
  }
})('test');

const read = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const rel = (p) => relative(process.cwd(), p).split('\\').join('/');

/** Replace comments and string literals with spaces, preserving newlines and
 *  overall length so index math stays valid. */
function strip(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const next = src[i + 1];

    if (c === '/' && next === '/') {
      while (i < n && src[i] !== '\n') { out += ' '; i++; }
      continue;
    }
    if (c === '/' && next === '*') {
      out += '  '; i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      out += '  '; i += 2;
      continue;
    }

    const raw = c === 'r' && (next === "'" || next === '"');
    const quote = raw ? next : c;
    if (quote === "'" || quote === '"') {
      const triple = src[i + (raw ? 1 : 0) + 1] === quote && src[i + (raw ? 1 : 0) + 2] === quote;
      const start = i;
      i += raw ? 2 : 1;
      if (triple) i += 2;
      while (i < n) {
        if (!raw && src[i] === '\\') { i += 2; continue; }
        if (triple) {
          if (src[i] === quote && src[i + 1] === quote && src[i + 2] === quote) { i += 3; break; }
          i++;
        } else {
          if (src[i] === quote) { i++; break; }
          if (src[i] === '\n') break; // unterminated
          i++;
        }
      }
      out += src.slice(start, i).replace(/[^\n]/g, ' ');
      continue;
    }

    out += c;
    i++;
  }
  return out;
}

// ---------------------------------------------------------------- parsing

function declaredNames(src) {
  const names = new Set();
  for (const m of src.matchAll(
    /^(?:@\w+(?:\([^)]*\))?\s*\n\s*)*(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*class\s+([A-Za-z_]\w*)/gm,
  )) names.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:base\s+|sealed\s+)?(?:mixin|enum)\s+([A-Za-z_]\w*)/gm)) names.add(m[1]);
  for (const m of src.matchAll(/^\s*(?:extension\s+type\s+|typedef\s+)([A-Za-z_]\w*)/gm)) names.add(m[1]);
  for (const m of src.matchAll(/^\s*extension\s+([A-Za-z_]\w*)/gm)) names.add(m[1]);
  for (const m of src.matchAll(/^(?:final|const|late\s+final|late|var)\s+(?:[A-Za-z_][\w<>,?\s.]*?\s+)?([a-z_]\w*)\s*(?:=|;|\()/gm))
    names.add(m[1]);
  for (const m of src.matchAll(/^(?:Future<\S+>|Stream<\S+>|[A-Z]\w*(?:<[^;{]*>)?\??)\s+([a-z]\w*)\s*(?:<[^>]*>)?\s*\(/gm))
    names.add(m[1]);
  return names;
}

/** enum name -> member names */
function enumMembers(src) {
  const out = new Map();
  for (const m of src.matchAll(/\benum\s+([A-Za-z_]\w*)\s*(?:with\s+[^{]+)?\{/g)) {
    const open = m.index + m[0].length - 1;
    let depth = 0;
    let i = open;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) break; }
    }
    const body = src.slice(open + 1, i);
    const head = body.split(';')[0];
    const members = new Set();
    let parts = [''];
    let d = 0;
    for (const ch of head) {
      if ('([{<'.includes(ch)) d++;
      else if (')]}>'.includes(ch)) d--;
      if (ch === ',' && d === 0) parts.push('');
      else parts[parts.length - 1] += ch;
    }
    for (const part of parts) {
      const id = part.match(/^\s*([A-Za-z_]\w*)/);
      if (id) members.add(id[1]);
    }
    if (members.size) out.set(m[1], members);
  }
  return out;
}

const sources = new Map();
for (const f of files) sources.set(f, read(f));
const stripped = new Map();
for (const f of files) stripped.set(f, strip(sources.get(f)));

// Global enum index (any file may declare enums).
const allEnums = new Map();
for (const [f, src] of stripped) {
  for (const [name, members] of enumMembers(src)) {
    if (!allEnums.has(name)) allEnums.set(name, { members, file: f });
  }
}

// Import closure of visible top-level names, per file.
const closureCache = new Map();
function closure(file, stack = new Set()) {
  if (closureCache.has(file)) return closureCache.get(file);
  if (stack.has(file)) return new Set();
  stack.add(file);
  const src = sources.get(file) ?? '';
  const names = new Set(declaredNames(src));
  const importRe = /^\s*import\s+['"]([^'"]+)['"]/gm;
  for (const m of src.matchAll(importRe)) {
    const spec = m[1];
    if (spec.startsWith('package:aidra/')) {
      const target = resolve('lib', spec.slice('package:aidra/'.length));
      for (const n of closure(target, stack)) names.add(n);
    } else if (!spec.startsWith('dart:') && !spec.startsWith('package:')) {
      // Bare specs such as 'auth_providers.dart' are relative too.
      const target = resolve(dirname(file), spec);
      for (const n of closure(target, stack)) names.add(n);
      // Also pull in whatever that file re-exports.
      const tsrc = sources.get(target);
      if (tsrc) {
        for (const em of tsrc.matchAll(/^\s*export\s+['"]([^'"]+)['"]/gm)) {
          const es = em[1];
          if (es.startsWith('dart:') || es.startsWith('package:')) continue;
          for (const n of closure(resolve(dirname(target), es), stack)) names.add(n);
        }
      }
    } else if (spec.startsWith('package:') && /\/src\//.test(spec)) {
      // ignore
    }
  }
  closureCache.set(file, names);
  return names;
}

// ---------------------------------------------------------------- checks

const balance = [];
for (const [f, src] of stripped) {
  const stack = [];
  const pairs = { ')': '(', ']': '[', '}': '{' };
  let line = 1;
  let bad = null;
  for (const ch of src) {
    if (ch === '\n') line++;
    if ('([{'.includes(ch)) stack.push({ ch, line });
    else if (')]}'.includes(ch)) {
      const top = stack.pop();
      if (!top || top.ch !== pairs[ch]) { bad = `unmatched '${ch}' at line ${line}`; break; }
    }
  }
  if (!bad && stack.length) bad = `unclosed '${stack[stack.length - 1].ch}' opened at line ${stack[stack.length - 1].line}`;
  if (bad) balance.push(`${rel(f)}: ${bad}`);
}

const providers = [];
const enumMisses = [];
const l10nMisses = [];
const routeMisses = [];

const enKeys = (() => {
  const src = sources.get(resolve('lib/app/l10n/app_strings.dart')) ?? '';
  const block = src.match(/'en':\s*<String,\s*String>\{([\s\S]*?)\n\s*\},\n\s*'hi'/);
  const keys = new Set();
  if (!block) return keys;
  for (const m of block[1].matchAll(/'([^']+)':/g)) keys.add(m[1]);
  return keys;
})();

const routeNames = (() => {
  const src = sources.get(resolve('lib/app/router/app_router.dart')) ?? '';
  const block = src.match(/class\s+AppRoutes\s*\{([\s\S]*?)\n\}/);
  const names = new Set();
  if (!block) return names;
  for (const m of block[1].matchAll(/static\s+const\s+String\s+([A-Za-z_]\w*)/g)) names.add(m[1]);
  return names;
})();

for (const [f, src] of sources) {
  const code = stripped.get(f);
  const visible = closure(f);

  // 2. provider resolution
  for (const m of code.matchAll(/\bref\s*\.\s*(?:watch|read|listen)\s*\(\s*([A-Za-z_]\w*)/g)) {
    const name = m[1];
    if (!name.endsWith('Provider')) continue;
    if (visible.has(name)) continue;
    const globals = [...sources.keys()].filter((g) => declaredNames(sources.get(g)).has(name));
    providers.push(
      globals.length
        ? `${rel(f)}: ${name} used but NOT IMPORTED (declared in ${globals.map(rel).join(', ')})`
        : `${rel(f)}: ${name} does not exist anywhere (typo?)`,
    );
  }

  // 3. enum members
  for (const m of code.matchAll(/\b([A-Z]\w+)\.([a-z]\w*)\b/g)) {
    const [, type, member] = m;
    if (!allEnums.has(type)) continue;
    const members = allEnums.get(type).members;
    // `.name`, `.values`, `.index` and extension getters are always fine.
    if (['name', 'values', 'index', 'hashCode', 'runtimeType'].includes(member)) continue;
    if (members.has(member)) continue;
    if (/\b(?:get|set)\s+[A-Za-z_]\w*/.test('') ) { /* noop */ }
    // Extension getters declared on the enum live in app_enums.dart.
    const ext = sources.get(resolve('lib/core/constants/app_enums.dart')) ?? '';
    if (new RegExp(`(?:get|set)\\s+${member}\\b`).test(ext)) continue;
    const anyExt = [...sources.values()].some((s) => new RegExp(`(?:get|set)\\s+${member}\\b`).test(s));
    if (anyExt) continue;
    enumMisses.push(`${rel(f)}: ${type}.${member} — member not in {${[...members].join(', ')}}`);
  }

  // 4. localization keys
  for (const m of code.matchAll(/\btr\(\s*'([^']+)'\s*\)/g)) {
    if (!enKeys.has(m[1])) l10nMisses.push(`${rel(f)}: tr('${m[1]}') missing from English catalogue`);
  }
  for (const m of code.matchAll(/AppStrings\.lookup\([^,]+,\s*'([^']+)'/g)) {
    if (!enKeys.has(m[1])) l10nMisses.push(`${rel(f)}: AppStrings.lookup '${m[1]}' missing`);
  }

  // 5. routes
  for (const m of code.matchAll(/\bAppRoutes\.([A-Za-z_]\w*)/g)) {
    if (!routeNames.has(m[1])) routeMisses.push(`${rel(f)}: AppRoutes.${m[1]} is not declared`);
  }
}

// 6. pubspec dependency coverage
const pubspec = read('pubspec.yaml');
const deps = new Set();
for (const head of ['dependencies', 'dev_dependencies']) {
  const block = pubspec.match(new RegExp(`^${head}:\\n([\\s\\S]*?)^\\S`, 'm'));
  if (block) for (const m of block[1].matchAll(/^\s{2}([a-z_]+):/gm)) deps.add(m[1]);
}
const depFlags = [];
for (const [f, src] of sources) {
  for (const m of src.matchAll(/^\s*import\s+'package:([a-z_]+)\//gm)) {
    if (m[1] === 'aidra') continue;
    if (!deps.has(m[1])) depFlags.push(`${rel(f)}: package:${m[1]}/ is not in pubspec dependencies`);
  }
}

const section = (title, rows) => {
  console.log(`\n${title} (${rows.length})`);
  console.log(rows.length ? [...new Set(rows)].map((r) => '  - ' + r).join('\n') : '  none');
};

console.log(`Semantic checks over ${files.length} Dart files.`);
console.log(`Localization catalogue (en): ${enKeys.size} keys · AppRoutes: ${routeNames.size} · Enums: ${allEnums.size}`);
section('SYNTAX / BALANCE', balance);
section('UNRESOLVED PROVIDERS', providers);
section('INVALID ENUM MEMBERS', enumMisses);
section('MISSING L10N KEYS', l10nMisses);
section('UNKNOWN ROUTES', routeMisses);
section('UNDECLARED PACKAGE DEPS', depFlags);
