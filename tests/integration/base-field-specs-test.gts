import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { catalogRealmURL, setupCatalogRealm } from '../helpers/catalog-realm';

module('Integration | catalog field specs (moved from base)', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  test('every field spec in the catalog has correct shape and uses @cardstack/base/ refs', async function (assert) {
    let response = await fetch(`${catalogRealmURL}_search`, {
      method: 'QUERY',
      headers: {
        Accept: 'application/vnd.card+json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        filter: {
          on: { module: '@cardstack/base/spec', name: 'Spec' },
          every: [{ eq: { specType: 'field' } }],
        },
      }),
    });
    assert.ok(response.ok, `_search returned ${response.status}`);

    let { data: specs = [] } = await response.json();

    assert.ok(
      specs.length >= 1,
      `expected at least one field spec in catalog, found ${specs.length}`,
    );

    for (let spec of specs) {
      let id = spec.id;
      let attrs = spec.attributes ?? {};
      let ref = attrs.ref;

      assert.strictEqual(attrs.specType, 'field', `${id}: specType is "field"`);
      assert.ok(
        typeof ref?.module === 'string' &&
          ref.module.startsWith('@cardstack/base/'),
        `${id}: ref.module uses @cardstack/base/ form (got ${ref?.module})`,
      );
      assert.ok(
        typeof ref?.name === 'string' && ref.name.length > 0,
        `${id}: ref.name is non-empty`,
      );
    }
  });
});
