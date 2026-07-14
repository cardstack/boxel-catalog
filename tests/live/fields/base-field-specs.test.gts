import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | base field specs', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('base realm field specs in catalog have correct shape and refs', async function (assert) {
      // _search speaks the entry wire grammar: the type anchor is `item.on`,
      // field paths inside operators are `item.`-prefixed, and card
      // attributes come back on `included` card resources selected by the
      // `fields[entry]` sparse fieldset.
      let response = await fetch(`${realmURL}_search`, {
        method: 'QUERY',
        headers: {
          Accept: 'application/vnd.card+json',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          filter: {
            'item.on': {
              module: 'https://cardstack.com/base/spec',
              name: 'Spec',
            },
            every: [{ eq: { 'item.specType': 'field' } }],
          },
          fields: { entry: ['item.specType', 'item.ref'] },
          page: { size: 100 },
        }),
      });
      assert.ok(response.ok, `_search returned ${response.status}`);

      let { included = [] } = await response.json();
      let specs = included.filter((resource: any) => resource.type === 'card');

      assert.ok(
        specs.length >= 1,
        `expected at least one field spec in catalog, found ${specs.length}`,
      );

      // Only enforce the base-realm-shape invariants on specs whose ref
      // actually points at the base realm. The catalog also contains custom
      // field specs (slider, rating, audio, etc.) whose ref.module is a URL
      // inside the catalog realm — those have a different shape and are out
      // of scope for this assertion.
      let baseRealmSpecs = specs.filter((spec: any) =>
        spec.attributes?.ref?.module?.startsWith?.(
          'https://cardstack.com/base/',
        ),
      );

      assert.ok(
        baseRealmSpecs.length >= 1,
        `expected at least one base-realm field spec, found ${baseRealmSpecs.length} of ${specs.length} total`,
      );

      for (let spec of baseRealmSpecs) {
        let id = spec.id;
        let attrs = spec.attributes ?? {};
        let ref = attrs.ref;

        assert.strictEqual(
          attrs.specType,
          'field',
          `${id}: specType is "field"`,
        );
        assert.ok(
          typeof ref?.name === 'string' && ref.name.length > 0,
          `${id}: ref.name is non-empty`,
        );
      }
    });
  });
}
