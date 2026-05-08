import { getService } from '@universal-ember/test-support';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';

import type * as AudioFieldModule from '@cardstack/catalog-realm/fields/audio';
import type * as ImageFieldModule from '@cardstack/catalog-realm/fields/image';
import type * as MultipleImageFieldModule from '@cardstack/catalog-realm/fields/multiple-image';
import type * as RecurringPatternFieldModule from '@cardstack/catalog-realm/fields/recurring-pattern';
import type * as TimePeriodFieldModule from '@cardstack/catalog-realm/fields/time-period';

type AudioField = (typeof AudioFieldModule)['default'];
let AudioField: AudioField;

type CatalogImageField = (typeof ImageFieldModule)['default'];
let CatalogImageField: CatalogImageField;

type MultipleImageField = (typeof MultipleImageFieldModule)['default'];
let MultipleImageField: MultipleImageField;

type RecurringPatternField = (typeof RecurringPatternFieldModule)['default'];
let RecurringPatternField: RecurringPatternField;

type TimePeriodField = (typeof TimePeriodFieldModule)['default'];
let TimePeriodField: TimePeriodField;

let catalogRealmURL = ensureTrailingSlash(
  ENV.resolvedCatalogRealmURL ?? 'http://localhost:4201/catalog/',
);
let initialized = false;

async function initialize() {
  if (initialized) return;

  let loader = getService('loader-service').loader;

  AudioField = (
    await loader.import<typeof AudioFieldModule>(
      `${catalogRealmURL}fields/audio`,
    )
  ).default;

  CatalogImageField = (
    await loader.import<typeof ImageFieldModule>(
      `${catalogRealmURL}fields/image`,
    )
  ).default;

  MultipleImageField = (
    await loader.import<typeof MultipleImageFieldModule>(
      `${catalogRealmURL}fields/multiple-image`,
    )
  ).default;

  RecurringPatternField = (
    await loader.import<typeof RecurringPatternFieldModule>(
      `${catalogRealmURL}fields/recurring-pattern`,
    )
  ).default;

  TimePeriodField = (
    await loader.import<typeof TimePeriodFieldModule>(
      `${catalogRealmURL}fields/time-period`,
    )
  ).default;

  initialized = true;
}

export function setupCatalogRealm(hooks: NestedHooks) {
  hooks.beforeEach(initialize);
}

export {
  AudioField,
  CatalogImageField,
  MultipleImageField,
  RecurringPatternField,
  TimePeriodField,
  catalogRealmURL,
};
