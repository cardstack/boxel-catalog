import { module, test } from 'qunit';

import { toCatalogPrefixForm } from '../../../utils/catalog-prefix-form';

const CATALOG = 'https://app.boxel.ai/catalog/';
const unresolve = (url: string) =>
  url.startsWith(CATALOG)
    ? `@cardstack/catalog/${url.slice(CATALOG.length)}`
    : url;

function instance(doc: object) {
  return JSON.stringify({ data: doc }, null, 2) + '\n';
}

export function runTests() {
  module('Catalog | submission - catalog prefix form', function () {
    test('an adoptsFrom module and a relationship link into the catalog take the prefix', function (assert) {
      let content = instance({
        meta: {
          adoptsFrom: {
            module: `${CATALOG}catalog-app/listing/listing`,
            name: 'CardListing',
          },
        },
        relationships: {
          'tags.0': { links: { self: `${CATALOG}Tag/dashboard` } },
        },
      });
      let out = JSON.parse(
        toCatalogPrefixForm(content, 'a/CardListing/1.json', unresolve),
      );
      assert.strictEqual(
        out.data.meta.adoptsFrom.module,
        '@cardstack/catalog/catalog-app/listing/listing',
      );
      assert.strictEqual(
        out.data.relationships['tags.0'].links.self,
        '@cardstack/catalog/Tag/dashboard',
      );
    });

    test('a catalog URL held as a field value stays a URL, even when it equals a rewritten one', function (assert) {
      let module = `${CATALOG}catalog-app/listing/listing`;
      let content = instance({
        meta: { adoptsFrom: { module, name: 'CardListing' } },
        attributes: {
          website: module,
          thumbnailURL: `${CATALOG}images/x.png`,
        },
      });
      let out = JSON.parse(
        toCatalogPrefixForm(content, 'a/CardListing/1.json', unresolve),
      );
      assert.strictEqual(out.data.attributes.website, module);
      assert.strictEqual(
        out.data.attributes.thumbnailURL,
        `${CATALOG}images/x.png`,
      );
    });

    test('a link into another realm is left alone, and so is a file with nothing to rewrite', function (assert) {
      let content = instance({
        relationships: {
          other: { links: { self: 'https://app.boxel.ai/me/x/Card/1' } },
        },
      });
      assert.strictEqual(
        toCatalogPrefixForm(content, 'a/Card/1.json', unresolve),
        content,
      );
    });

    test('static and dynamic imports from the catalog take the prefix; other URLs in code stay', function (assert) {
      let content = [
        `import { Listing } from '${CATALOG}catalog-app/listing/listing';`,
        `const m = await import("${CATALOG}x/y");`,
        `const img = '<img src="${CATALOG}assets/hero.png">';`,
        `const u = new URL('${CATALOG}x');`,
      ].join('\n');
      assert.strictEqual(
        toCatalogPrefixForm(content, 'a/x.gts', unresolve),
        [
          `import { Listing } from '@cardstack/catalog/catalog-app/listing/listing';`,
          `const m = await import("@cardstack/catalog/x/y");`,
          `const img = '<img src="${CATALOG}assets/hero.png">';`,
          `const u = new URL('${CATALOG}x');`,
        ].join('\n'),
      );
    });

    test('invalid JSON and files that are neither JSON nor code are returned unchanged', function (assert) {
      let broken = `{"data": {"meta": {"adoptsFrom": {"module": "${CATALOG}x"`;
      assert.strictEqual(
        toCatalogPrefixForm(broken, 'a/Card/1.json', unresolve),
        broken,
      );
      let readme = `import x from '${CATALOG}x'`;
      assert.strictEqual(
        toCatalogPrefixForm(readme, 'a/README.md', unresolve),
        readme,
      );
    });
  });
}
