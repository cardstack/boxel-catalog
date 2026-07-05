// S05 — reference hygiene: no localhost, no leftover dev/user-realm URLs from
// packaging, intra-package references relative. Absolute URLs are legal ONLY
// for the base realm, the catalog realm itself, boxel-icons, and bare npm-style
// specifiers (@cardstack/*, ember, @glimmer, @ember, tracked-built-ins, lodash, etc.).
import { instances, relationshipsOf } from '../lib/json-walk.mjs';
import { importDecls } from '../lib/gts-scan.mjs';

const ALLOWED_URL_PREFIXES = [
  'https://cardstack.com/base/',
  'https://app.boxel.ai/catalog/',
  'https://realms-staging.stack.cards/catalog/',
  'https://stack.cards/catalog/',
  'https://boxel-icons.boxel.ai/',
];

function classifyUrl(url) {
  if (/localhost|127\.0\.0\.1/.test(url)) return 'localhost';
  if (!/^https?:\/\//.test(url)) return 'not-absolute';
  if (ALLOWED_URL_PREFIXES.some((p) => url.startsWith(p))) return 'allowed';
  if (/^https:\/\/(app\.boxel\.ai|realms-staging\.stack\.cards|stack\.cards)\//.test(url)) {
    return 'foreign-realm'; // a realm host but NOT the catalog realm — dev/user realm leftover
  }
  return 'external';
}

export default {
  id: 's05-relative-refs',
  title: 'Reference hygiene (relative refs, no dev-realm leftovers)',
  phase: 'static',
  run(ctx) {
    const findings = [];

    // JSON: adoptsFrom modules + relationship links
    for (const [rel, doc] of instances(ctx)) {
      const spots = [];
      const mod = doc?.data?.meta?.adoptsFrom?.module;
      if (typeof mod === 'string') spots.push(['data.meta.adoptsFrom.module', mod]);
      for (const [key, val] of Object.entries(relationshipsOf(doc))) {
        const self = val?.links?.self;
        if (typeof self === 'string') spots.push([`data.relationships["${key}"].links.self`, self]);
      }
      for (const [loc, url] of spots) {
        const kind = classifyUrl(url);
        if (kind === 'localhost') {
          findings.push({
            rule: 'refs/localhost',
            severity: 'error',
            file: rel,
            loc,
            message: `localhost URL (${url.slice(0, 60)}) — will not resolve in the catalog realm`,
          });
        } else if (kind === 'foreign-realm') {
          findings.push({
            rule: 'refs/dev-realm-leftover',
            severity: 'error',
            file: rel,
            loc,
            message: `URL points at a non-catalog realm (${url.slice(0, 70)}…) — packaging did not rewrite this reference`,
            suggestion: 'Re-run packaging (collect-submission-files rewrites realm URLs to relative paths)',
            fixRef: 'catalog-card-factory/references/packaging.md',
          });
        }
      }
    }

    // GTS imports
    for (const [rel, src] of ctx.gtsSources) {
      for (const imp of importDecls(src)) {
        if (!/^https?:\/\//.test(imp.source)) {
          if (/localhost|127\.0\.0\.1/.test(imp.source)) {
            findings.push({
              rule: 'refs/localhost',
              severity: 'error',
              file: rel,
              loc: `line ${imp.line}`,
              message: `localhost import (${imp.source})`,
            });
          }
          continue; // relative or bare specifier — fine
        }
        const kind = classifyUrl(imp.source);
        if (kind === 'foreign-realm') {
          findings.push({
            rule: 'refs/dev-realm-leftover',
            severity: 'error',
            file: rel,
            loc: `line ${imp.line}`,
            message: `Import from a non-catalog realm (${imp.source.slice(0, 70)}…) — packaging did not rewrite this module reference`,
            fixRef: 'catalog-card-factory/references/packaging.md',
          });
        } else if (kind === 'external') {
          findings.push({
            rule: 'refs/external-module',
            severity: 'warn',
            file: rel,
            loc: `line ${imp.line}`,
            message: `Import from external host (${imp.source.slice(0, 70)}) — CDN imports are allowed but must be deliberate`,
            suggestion: 'If this is a library, consider the integrate-*-via-cdn patterns; otherwise vendor it into the package',
          });
        }
      }
    }
    return findings;
  },
};
