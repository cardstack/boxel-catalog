// Prints the files a PR's preview realm needs, one per line: each folder the
// PR touches, whole, plus every file those reach by relative path. Imports
// through `@cardstack/catalog/` resolve to the catalog realm and need nothing.
//
// Usage: node scripts/preview-paths.mjs <changed-path>...

import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';

const CLUSTER_ROOTS = new Set(['cards', 'fields', 'components']);
const SKIPPED_ROOTS = new Set(['tests', 'scripts', 'node_modules']);
const SKIPPED_FILES = new Set([
  'README.md',
  'AGENTS.md',
  'LICENSE',
  'package.json',
  'package-lock.json',
]);

function unitOf(path) {
  let parts = path.split('/');
  if (parts.some((p) => p.startsWith('.'))) return null;
  if (parts.length === 1) return SKIPPED_FILES.has(path) ? null : path;
  let [root] = parts;
  if (SKIPPED_ROOTS.has(root)) return null;
  // A capitalized top-level folder holds instances of one type (Spec,
  // Category, Theme…): only the file itself, not every instance of the type.
  if (/^[A-Z]/.test(root)) return path;
  if (CLUSTER_ROOTS.has(root)) {
    return parts.length > 2 ? parts.slice(0, 2).join('/') : path;
  }
  return root;
}

const isFile = (p) => existsSync(p) && statSync(p).isFile();

const out = new Set();
const queue = [];
function add(path) {
  path = normalize(path);
  if (path.startsWith('..') || out.has(path) || !isFile(path)) return;
  out.add(path);
  queue.push(path);
}
function addTree(path) {
  if (isFile(path)) return add(path);
  if (!existsSync(path)) return;
  for (let entry of readdirSync(path, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    let child = join(path, entry.name);
    entry.isDirectory() ? addTree(child) : add(child);
  }
}
function resolveRef(from, ref) {
  let base = normalize(join(dirname(from), ref));
  for (let candidate of [base, `${base}.gts`, `${base}.ts`, `${base}.json`]) {
    if (isFile(candidate)) return candidate;
  }
  return null;
}

for (let unit of new Set(process.argv.slice(2).map(unitOf))) {
  if (unit) addTree(unit);
}
while (queue.length) {
  let file = queue.shift();
  let source = readFileSync(file, 'utf8');
  let refs = [];
  if (/\.(gts|ts|js)$/.test(file)) {
    for (let m of source.matchAll(/(?:from|import)\s*\(?\s*['"](\.{1,2}\/[^'"]+)['"]/g)) {
      refs.push(m[1]);
    }
  } else if (file.endsWith('.json')) {
    for (let m of source.matchAll(/"(?:module|self)"\s*:\s*"(\.{1,2}\/[^"]+)"/g)) {
      refs.push(m[1]);
    }
  }
  for (let ref of refs) {
    let target = resolveRef(file, ref);
    if (target) add(target);
  }
}
process.stdout.write([...out].sort().join('\n'));
