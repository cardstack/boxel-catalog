// Filesystem walking + JSON instance loading for a listing directory.
// Stdlib only — must run in CI with no npm install.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, extname, posix, dirname } from 'node:path';

const SKIP_DIRS = new Set(['.git', 'node_modules', '.boxel-history']);
const SKIP_FILES = new Set(['.conformance-report.json']);

/** Recursively list files under dir, returning repo-style relative paths (posix separators). */
export function walkFiles(rootDir) {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      if (SKIP_DIRS.has(name)) continue;
      const full = join(dir, name);
      const st = statSync(full);
      if (st.isDirectory()) walk(full);
      else if (!SKIP_FILES.has(name)) out.push(relative(rootDir, full).split('\\').join('/'));
    }
  };
  walk(rootDir);
  return out.sort();
}

/**
 * Load the listing dir into a context object shared by all gates.
 * jsonDocs: rel path -> { doc, error } (error set when unparseable — S02 reports it).
 * gtsSources: rel path (with .gts ext) -> source text.
 */
export function loadListingDir(rootDir) {
  const files = walkFiles(rootDir);
  const jsonDocs = new Map();
  const gtsSources = new Map();
  for (const rel of files) {
    const ext = extname(rel);
    if (ext === '.json') {
      const raw = readFileSync(join(rootDir, rel), 'utf8');
      try {
        jsonDocs.set(rel, { doc: JSON.parse(raw) });
      } catch (e) {
        jsonDocs.set(rel, { doc: null, error: String(e.message).slice(0, 120) });
      }
    } else if (ext === '.gts' || ext === '.gjs') {
      gtsSources.set(rel, readFileSync(join(rootDir, rel), 'utf8'));
    }
  }
  return { rootDir, files, jsonDocs, gtsSources };
}

/** True for card instance docs (skips realm.json / index.json if ever present). */
export function isInstancePath(rel) {
  return rel.endsWith('.json') && !rel.endsWith('realm.json') && !rel.endsWith('index.json');
}

/** Iterate [relPath, doc] for parseable card instance documents. */
export function* instances(ctx) {
  for (const [rel, entry] of ctx.jsonDocs) {
    if (!isInstancePath(rel) || !entry.doc) continue;
    const d = entry.doc?.data;
    if (d && typeof d === 'object') yield [rel, entry.doc];
  }
}

/** relationships map of an instance doc (always an object). */
export function relationshipsOf(doc) {
  const r = doc?.data?.relationships;
  return r && typeof r === 'object' ? r : {};
}

/** attributes map of an instance doc (always an object). */
export function attributesOf(doc) {
  const a = doc?.data?.attributes;
  return a && typeof a === 'object' ? a : {};
}

/** Resolve a relative link (e.g. "../Spec/foo") against the instance's location inside the listing dir. */
export function resolveRelative(instanceRelPath, link) {
  const base = dirname(instanceRelPath);
  return posix.normalize(posix.join(base, link));
}

/** Depth-first walk of every string value in a JSON value; cb(path, str). */
export function walkStrings(value, cb, path = '$') {
  if (typeof value === 'string') cb(path, value);
  else if (Array.isArray(value)) value.forEach((v, i) => walkStrings(v, cb, `${path}[${i}]`));
  else if (value && typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) walkStrings(v, cb, `${path}.${k}`);
  }
}
