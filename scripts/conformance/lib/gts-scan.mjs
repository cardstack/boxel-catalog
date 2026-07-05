// Lightweight structural scanning of .gts card modules — regex + brace matching,
// deliberately NOT a real parser (stdlib-only constraint). Good enough for the
// conformance gates; anything subtler belongs in glint/eslint (ci-lint.yaml).

/**
 * Extract class declarations with their body spans.
 * Returns [{ name, base, exported, start, end, body }] where body is the source
 * text between the class's braces (best-effort brace matching that ignores
 * braces inside strings/template literals only crudely — fine for gate use).
 */
export function extractClasses(src) {
  const out = [];
  const re = /(export\s+)?class\s+([A-Za-z0-9_$]+)\s+extends\s+([A-Za-z0-9_$.]+)/g;
  let m;
  while ((m = re.exec(src))) {
    const braceStart = src.indexOf('{', re.lastIndex);
    if (braceStart === -1) continue;
    let depth = 0;
    let i = braceStart;
    for (; i < src.length; i++) {
      const ch = src[i];
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) break;
      }
    }
    out.push({
      exported: Boolean(m[1]),
      name: m[2],
      base: m[3],
      start: m.index,
      end: i,
      body: src.slice(braceStart + 1, i),
      line: src.slice(0, m.index).split('\n').length,
    });
  }
  return out;
}

/** Names a class ultimately extends, resolved through classes defined in the same kit. */
export function resolveBase(className, classIndex, seen = new Set()) {
  if (seen.has(className)) return className;
  seen.add(className);
  const cls = classIndex.get(className);
  if (!cls) return className;
  return resolveBase(cls.base, classIndex, seen);
}

const DEF_ROOTS = new Set(['CardDef', 'FieldDef']);

/**
 * Build a kit-wide view over all .gts sources:
 * classIndex: name -> { file, name, base, exported, body, line }
 * defs: [{ file, name, kind: 'card'|'field', exported, body, line }]
 * (Transitively resolves local inheritance: class Task extends TrackedCard extends CardDef.)
 */
export function indexKit(gtsSources) {
  const classIndex = new Map();
  for (const [file, src] of gtsSources) {
    for (const cls of extractClasses(src)) {
      classIndex.set(cls.name, { file, ...cls });
    }
  }
  const defs = [];
  for (const cls of classIndex.values()) {
    const root = resolveBase(cls.name, classIndex);
    if (DEF_ROOTS.has(root)) {
      defs.push({ ...cls, kind: root === 'CardDef' ? 'card' : 'field' });
    }
  }
  return { classIndex, defs };
}

/** static format blocks declared directly in a class body: { isolated, embedded, fitted, edit, atom } -> body text */
export function staticFormats(classBody) {
  const out = {};
  const re = /static\s+(isolated|embedded|fitted|edit|atom)\s*[:=]/g;
  let m;
  while ((m = re.exec(classBody))) {
    // capture from the match to the next `static <format>` or end of body — a
    // coarse span, only used for looking inside one format's template/styles.
    const rest = classBody.slice(m.index + m[0].length);
    const next = rest.search(/\n\s*static\s+(isolated|embedded|fitted|edit|atom|displayName|prefersWideFormat|headerColor|icon)\s*[:=]/);
    out[m[1]] = next === -1 ? rest : rest.slice(0, next);
  }
  return out;
}

/** All <style scoped> block contents in a source span. */
export function styleBlocks(span) {
  const out = [];
  const re = /<style(?:\s+scoped)?\s*>([\s\S]*?)<\/style>/g;
  let m;
  while ((m = re.exec(span))) out.push(m[1]);
  return out;
}

/** All <template> block contents (with nested style blocks stripped). */
export function templateBlocks(span) {
  const out = [];
  const re = /<template>([\s\S]*?)<\/template>/g;
  let m;
  while ((m = re.exec(span))) out.push(m[1].replace(/<style(?:\s+scoped)?\s*>[\s\S]*?<\/style>/g, ''));
  return out;
}

/** @field declarations: [{ name, kind: contains|containsMany|linksTo|linksToMany, target, thunk, line }] */
export function fieldDecls(src) {
  const out = [];
  const re = /@field\s+([A-Za-z0-9_$]+)\s*=\s*(contains|containsMany|linksTo|linksToMany)\(\s*(\(\s*\)\s*=>)?\s*([A-Za-z0-9_$.]+)?/g;
  let m;
  while ((m = re.exec(src))) {
    out.push({
      name: m[1],
      kind: m[2],
      thunk: Boolean(m[3]),
      target: m[4] ?? null,
      line: src.slice(0, m.index).split('\n').length,
    });
  }
  return out;
}

/** import specifiers: [{ names: [...], source, line }] */
export function importDecls(src) {
  const out = [];
  const re = /import\s+(?:([\s\S]*?)\s+from\s+)?['"]([^'"]+)['"]/g;
  let m;
  while ((m = re.exec(src))) {
    out.push({
      clause: (m[1] ?? '').trim(),
      source: m[2],
      line: src.slice(0, m.index).split('\n').length,
    });
  }
  return out;
}

/** Map of DateField/DateTimeField contains-fields per source: { fieldName -> 'DateField'|'DateTimeField' } */
export function dateFieldMap(src) {
  const out = {};
  const re = /@field\s+([A-Za-z0-9_$]+)\s*=\s*contains\(\s*(?:\(\s*\)\s*=>\s*)?(DateField|DateTimeField)/g;
  let m;
  while ((m = re.exec(src))) out[m[1]] = m[2];
  return out;
}

/** line number of the first occurrence of a pattern in src (1-based), or null. */
export function lineOf(src, pattern) {
  const idx = typeof pattern === 'string' ? src.indexOf(pattern) : src.search(pattern);
  if (idx === -1) return null;
  return src.slice(0, idx).split('\n').length;
}
