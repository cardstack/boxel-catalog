// Prints the files a PR's preview realm needs, one per line: each folder the
// PR touches, whole, plus every file those reach by relative path. Imports
// through `@cardstack/catalog/` resolve to the catalog realm and need nothing.
//
// Usage: node scripts/preview-paths.mjs < changed-paths.txt (one per line),
// from the realm's root.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { pathToFileURL } from 'node:url';

const CLUSTER_ROOTS = new Set(['cards', 'fields', 'components']);
const SKIPPED_ROOTS = new Set(['tests', 'scripts', 'node_modules']);
const SKIPPED_FILES = new Set([
  'README.md',
  'AGENTS.md',
  'LICENSE',
  'package.json',
  'package-lock.json',
  // The catalog's own realm config: a preview keeps its realm's.
  'realm.json',
  'index.json',
]);

export function unitOf(path) {
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

const stat = (p) => statSync(p, { throwIfNoEntry: false });
const isFile = (p) => stat(p)?.isFile() ?? false;

// Relative references in code: imports, and `new URL('./…', import.meta.url)`.
const CODE_REFS = [
  /(?:from|import)\s*\(?\s*['"](\.{1,2}\/[^'"]+)['"]/g,
  /new\s+URL\(\s*['"](\.{1,2}\/[^'"]+)['"]\s*,\s*import\.meta\.url/g,
];
// Relative references in JSON: any string value that is a relative path.
const JSON_REF = /:\s*"(\.{1,2}\/[^"]+)"/g;

function resolveRef(from, ref) {
  let base = normalize(join(dirname(from), ref));
  for (let candidate of [
    base,
    `${base}.gts`,
    `${base}.ts`,
    `${base}.js`,
    `${base}.json`,
  ]) {
    if (isFile(candidate)) return candidate;
  }
  return null;
}

/** The files a preview of `changed` needs, relative to the current directory. */
export function previewPaths(changed) {
  let out = new Set();
  let queue = [];
  let add = (path) => {
    path = normalize(path);
    if (path.startsWith('..') || out.has(path) || !isFile(path)) return;
    out.add(path);
    queue.push(path);
  };
  let addTree = (path) => {
    let s = stat(path);
    if (!s) return;
    if (s.isFile()) return add(path);
    for (let entry of readdirSync(path, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) continue;
      let child = join(path, entry.name);
      entry.isDirectory() ? addTree(child) : add(child);
    }
  };
  for (let unit of new Set(changed.map(unitOf))) {
    if (unit) addTree(unit);
  }
  while (queue.length) {
    let file = queue.shift();
    let source = readFileSync(file, 'utf8');
    let patterns = /\.(gts|ts|js)$/.test(file)
      ? CODE_REFS
      : file.endsWith('.json')
        ? [JSON_REF]
        : [];
    for (let pattern of patterns)
      for (let m of source.matchAll(pattern)) {
        let target = resolveRef(file, m[1]);
        if (target) add(target);
      }
  }
  return [...out].sort();
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  let changed = readFileSync(0, 'utf8').split('\n').filter(Boolean);
  process.stdout.write(
    previewPaths(changed)
      .map((p) => `${p}\n`)
      .join(''),
  );
}
