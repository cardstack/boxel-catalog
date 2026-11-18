const CATALOG_PREFIX = '@cardstack/catalog/';
// A static or dynamic import of an absolute URL. It is a text match, so it
// also matches such text inside a comment or a string literal.
const IMPORT_SPECIFIER =
  /(\bfrom\s*|\bimport\s*\(?\s*)(['"])(https?:\/\/[^'"]+)\2/g;

// What's left absolute in a submitted file points outside the submission.
// Where it names code — an instance's adoptsFrom module or relationship
// link, or a module's import — a reference into the catalog realm is spelled
// with the catalog prefix, so the files read the same in whichever
// environment's catalog they land. A URL anywhere else, such as an image's
// src or a field's value, has to stay a URL and is left alone.
export function toCatalogPrefixForm(
  content: string,
  path: string,
  unresolve: (url: string) => string,
): string {
  let toPrefix = (url: string) => {
    let prefixed = unresolve(url);
    return prefixed.startsWith(CATALOG_PREFIX) ? prefixed : url;
  };
  if (path.endsWith('.json')) {
    let doc: unknown;
    try {
      doc = JSON.parse(content);
    } catch {
      return content;
    }
    let changed = false;
    let rewrite = (record: Record<string, unknown>, key: string) => {
      let value = record[key];
      if (typeof value === 'string') {
        let prefixed = toPrefix(value);
        if (prefixed !== value) {
          record[key] = prefixed;
          changed = true;
        }
      }
    };
    let walk = (node: unknown, key?: string) => {
      if (Array.isArray(node)) {
        node.forEach((item) => walk(item));
      } else if (node && typeof node === 'object') {
        let record = node as Record<string, unknown>;
        if (key === 'adoptsFrom') {
          rewrite(record, 'module');
        }
        if (key === 'links') {
          rewrite(record, 'self');
        }
        for (let [k, v] of Object.entries(record)) {
          walk(v, k);
        }
      }
    };
    walk(doc);
    if (!changed) {
      return content;
    }
    let trailing = content.endsWith('\n') ? '\n' : '';
    return JSON.stringify(doc, null, 2) + trailing;
  }
  if (/\.(gts|ts|js)$/.test(path)) {
    return content.replace(
      IMPORT_SPECIFIER,
      (_match, lead: string, quote: string, url: string) =>
        `${lead}${quote}${toPrefix(url)}${quote}`,
    );
  }
  return content;
}
