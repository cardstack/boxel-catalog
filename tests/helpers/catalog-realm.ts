import { getService } from '@universal-ember/test-support';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';

import type * as AudioFieldModule from '@cardstack/catalog/fields/audio';
import type * as AvatarFieldModule from '@cardstack/catalog/fields/avatar';
import type * as DiscreteRangeFieldModule from '@cardstack/catalog/fields/discrete-range-field';
import type * as GeoPointFieldModule from '@cardstack/catalog/fields/geo-point';
import type * as GeoSearchPointFieldModule from '@cardstack/catalog/fields/geo-search-point';
import type * as LeafletMapConfigFieldModule from '@cardstack/catalog/fields/leaflet-map-config-field';
import type * as QRCodeFieldModule from '@cardstack/catalog/fields/qr-code';
import type * as QuantityFieldModule from '@cardstack/catalog/fields/quantity';
import type * as RatingFieldModule from '@cardstack/catalog/fields/rating';
import type * as RecurringPatternFieldModule from '@cardstack/catalog/fields/recurring-pattern';
import type * as SliderFieldModule from '@cardstack/catalog/fields/slider';

type AudioField = (typeof AudioFieldModule)['default'];
let AudioField: AudioField;

type AvatarField = (typeof AvatarFieldModule)['default'];
let AvatarField: AvatarField;

type DiscreteRangeField = (typeof DiscreteRangeFieldModule)['default'];
let DiscreteRangeField: DiscreteRangeField;

type GeoPointField = (typeof GeoPointFieldModule)['default'];
let GeoPointField: GeoPointField;

type GeoSearchPointField = (typeof GeoSearchPointFieldModule)['default'];
let GeoSearchPointField: GeoSearchPointField;

type LeafletMapConfigField = (typeof LeafletMapConfigFieldModule)['default'];
let LeafletMapConfigField: LeafletMapConfigField;

type QRCodeField = (typeof QRCodeFieldModule)['default'];
let QRCodeField: QRCodeField;

type QuantityField = (typeof QuantityFieldModule)['default'];
let QuantityField: QuantityField;

type RatingField = (typeof RatingFieldModule)['default'];
let RatingField: RatingField;

type RecurringPatternField = (typeof RecurringPatternFieldModule)['default'];
let RecurringPatternField: RecurringPatternField;

type SliderField = (typeof SliderFieldModule)['default'];
let SliderField: SliderField;

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

  AvatarField = (
    await loader.import<typeof AvatarFieldModule>(
      `${catalogRealmURL}fields/avatar`,
    )
  ).default;

  DiscreteRangeField = (
    await loader.import<typeof DiscreteRangeFieldModule>(
      `${catalogRealmURL}fields/discrete-range-field`,
    )
  ).default;

  GeoPointField = (
    await loader.import<typeof GeoPointFieldModule>(
      `${catalogRealmURL}fields/geo-point`,
    )
  ).default;

  GeoSearchPointField = (
    await loader.import<typeof GeoSearchPointFieldModule>(
      `${catalogRealmURL}fields/geo-search-point`,
    )
  ).default;

  LeafletMapConfigField = (
    await loader.import<typeof LeafletMapConfigFieldModule>(
      `${catalogRealmURL}fields/leaflet-map-config-field`,
    )
  ).default;

  QRCodeField = (
    await loader.import<typeof QRCodeFieldModule>(
      `${catalogRealmURL}fields/qr-code`,
    )
  ).default;

  QuantityField = (
    await loader.import<typeof QuantityFieldModule>(
      `${catalogRealmURL}fields/quantity`,
    )
  ).default;

  RatingField = (
    await loader.import<typeof RatingFieldModule>(
      `${catalogRealmURL}fields/rating`,
    )
  ).default;

  RecurringPatternField = (
    await loader.import<typeof RecurringPatternFieldModule>(
      `${catalogRealmURL}fields/recurring-pattern`,
    )
  ).default;

  SliderField = (
    await loader.import<typeof SliderFieldModule>(
      `${catalogRealmURL}fields/slider`,
    )
  ).default;

  initialized = true;
}

export function setupCatalogRealm(hooks: NestedHooks) {
  hooks.beforeEach(initialize);
}

export {
  AudioField,
  AvatarField,
  DiscreteRangeField,
  GeoPointField,
  GeoSearchPointField,
  LeafletMapConfigField,
  QRCodeField,
  QuantityField,
  RatingField,
  RecurringPatternField,
  SliderField,
  catalogRealmURL,
};
