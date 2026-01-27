import { getService } from '@universal-ember/test-support';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ENV from '@cardstack/host/config/environment';

// TODO: monorepo should improve the import alias
import type * as AudioFieldModule from '@cardstack/catalog/../fields/audio';
import type * as ColorFieldModule from '@cardstack/catalog/../fields/color';
import type * as DateFieldModule from '@cardstack/catalog/../fields/date';
import type * as DateRangeFieldModule from '@cardstack/catalog/../fields/date/date-range';
import type * as DayFieldModule from '@cardstack/catalog/../fields/date/day';
import type * as MonthFieldModule from '@cardstack/catalog/../fields/date/month';
import type * as MonthDayFieldModule from '@cardstack/catalog/../fields/date/month-day';
import type * as MonthYearFieldModule from '@cardstack/catalog/../fields/date/month-year';
import type * as QuarterFieldModule from '@cardstack/catalog/../fields/date/quarter';
import type * as WeekFieldModule from '@cardstack/catalog/../fields/date/week';
import type * as YearFieldModule from '@cardstack/catalog/../fields/date/year';
import type * as DatetimeFieldModule from '@cardstack/catalog/../fields/date-time';
import type * as DatetimeStampFieldModule from '@cardstack/catalog/../fields/datetime-stamp';
import type * as ImageFieldModule from '@cardstack/catalog/../fields/image';
import type * as MultipleImageFieldModule from '@cardstack/catalog/../fields/multiple-image';
import type * as NumberFieldModule from '@cardstack/catalog/../fields/number';
import type * as RecurringPatternFieldModule from '@cardstack/catalog/../fields/recurring-pattern';
import type * as TimeFieldModule from '@cardstack/catalog/../fields/time';
import type * as DurationFieldModule from '@cardstack/catalog/../fields/time/duration';
import type * as RelativeTimeFieldModule from '@cardstack/catalog/../fields/time/relative-time';
import type * as TimeRangeFieldModule from '@cardstack/catalog/../fields/time/time-range';
import type * as TimePeriodFieldModule from '@cardstack/catalog/../fields/time-period';

type AudioField = (typeof AudioFieldModule)['default'];
let AudioField: AudioField;

type ColorField = (typeof ColorFieldModule)['default'];
let ColorField: ColorField;

type CatalogDateField = (typeof DateFieldModule)['default'];
let CatalogDateField: CatalogDateField;

type CatalogDatetimeField = (typeof DatetimeFieldModule)['default'];
let CatalogDatetimeField: CatalogDatetimeField;

type DatetimeStampField = (typeof DatetimeStampFieldModule)['default'];
let DatetimeStampField: DatetimeStampField;

type DayField = (typeof DayFieldModule)['default'];
let DayField: DayField;

type DateRangeField = (typeof DateRangeFieldModule)['default'];
let DateRangeField: DateRangeField;

type MonthDayField = (typeof MonthDayFieldModule)['default'];
let MonthDayField: MonthDayField;

type YearField = (typeof YearFieldModule)['default'];
let YearField: YearField;

type MonthField = (typeof MonthFieldModule)['default'];
let MonthField: MonthField;

type MonthYearField = (typeof MonthYearFieldModule)['default'];
let MonthYearField: MonthYearField;

type WeekField = (typeof WeekFieldModule)['default'];
let WeekField: WeekField;

type QuarterField = (typeof QuarterFieldModule)['default'];
let QuarterField: QuarterField;

type TimeField = (typeof TimeFieldModule)['default'];
let TimeField: TimeField;

type TimeRangeField = (typeof TimeRangeFieldModule)['default'];
let TimeRangeField: TimeRangeField;

type DurationField = (typeof DurationFieldModule)['default'];
let DurationField: DurationField;

type RelativeTimeField = (typeof RelativeTimeFieldModule)['default'];
let RelativeTimeField: RelativeTimeField;

type TimePeriodField = (typeof TimePeriodFieldModule)['default'];
let TimePeriodField: TimePeriodField;

type RecurringPatternField = (typeof RecurringPatternFieldModule)['default'];
let RecurringPatternField: RecurringPatternField;

type CatalogImageField = (typeof ImageFieldModule)['default'];
let CatalogImageField: CatalogImageField;

type MultipleImageField = (typeof MultipleImageFieldModule)['default'];
let MultipleImageField: MultipleImageField;

type CatalogNumberField = (typeof NumberFieldModule)['default'];
let CatalogNumberField: CatalogNumberField;

let catalogRealmURL = ensureTrailingSlash(ENV.resolvedCatalogRealmURL);
let initialized = false;

async function initialize() {
  if (initialized) return;

  let loader = getService('loader-service').loader;

  AudioField = (
    await loader.import<typeof AudioFieldModule>(
      `${catalogRealmURL}fields/audio`,
    )
  ).default;

  ColorField = (
    await loader.import<typeof ColorFieldModule>(
      `${catalogRealmURL}fields/color`,
    )
  ).default;

  CatalogDateField = (
    await loader.import<typeof DateFieldModule>(`${catalogRealmURL}fields/date`)
  ).default;

  CatalogDatetimeField = (
    await loader.import<typeof DatetimeFieldModule>(
      `${catalogRealmURL}fields/date-time`,
    )
  ).default;

  DatetimeStampField = (
    await loader.import<typeof DatetimeStampFieldModule>(
      `${catalogRealmURL}fields/datetime-stamp`,
    )
  ).default;

  DayField = (
    await loader.import<typeof DayFieldModule>(
      `${catalogRealmURL}fields/date/day`,
    )
  ).default;

  DateRangeField = (
    await loader.import<typeof DateRangeFieldModule>(
      `${catalogRealmURL}fields/date/date-range`,
    )
  ).default;

  MonthDayField = (
    await loader.import<typeof MonthDayFieldModule>(
      `${catalogRealmURL}fields/date/month-day`,
    )
  ).default;

  YearField = (
    await loader.import<typeof YearFieldModule>(
      `${catalogRealmURL}fields/date/year`,
    )
  ).default;

  MonthField = (
    await loader.import<typeof MonthFieldModule>(
      `${catalogRealmURL}fields/date/month`,
    )
  ).default;

  MonthYearField = (
    await loader.import<typeof MonthYearFieldModule>(
      `${catalogRealmURL}fields/date/month-year`,
    )
  ).default;

  WeekField = (
    await loader.import<typeof WeekFieldModule>(
      `${catalogRealmURL}fields/date/week`,
    )
  ).default;

  QuarterField = (
    await loader.import<typeof QuarterFieldModule>(
      `${catalogRealmURL}fields/date/quarter`,
    )
  ).default;

  TimeField = (
    await loader.import<typeof TimeFieldModule>(`${catalogRealmURL}fields/time`)
  ).default;

  TimeRangeField = (
    await loader.import<typeof TimeRangeFieldModule>(
      `${catalogRealmURL}fields/time/time-range`,
    )
  ).default;

  DurationField = (
    await loader.import<typeof DurationFieldModule>(
      `${catalogRealmURL}fields/time/duration`,
    )
  ).default;

  RelativeTimeField = (
    await loader.import<typeof RelativeTimeFieldModule>(
      `${catalogRealmURL}fields/time/relative-time`,
    )
  ).default;

  TimePeriodField = (
    await loader.import<typeof TimePeriodFieldModule>(
      `${catalogRealmURL}fields/time-period`,
    )
  ).default;

  RecurringPatternField = (
    await loader.import<typeof RecurringPatternFieldModule>(
      `${catalogRealmURL}fields/recurring-pattern`,
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

  CatalogNumberField = (
    await loader.import<typeof NumberFieldModule>(
      `${catalogRealmURL}fields/number`,
    )
  ).default;

  initialized = true;
}

export function setupCatalogRealm(hooks: NestedHooks) {
  hooks.beforeEach(initialize);
}

export {
  AudioField,
  ColorField,
  CatalogDateField,
  CatalogDatetimeField,
  DatetimeStampField,
  DayField,
  DateRangeField,
  MonthDayField,
  YearField,
  MonthField,
  MonthYearField,
  WeekField,
  QuarterField,
  TimeField,
  TimeRangeField,
  DurationField,
  RelativeTimeField,
  TimePeriodField,
  RecurringPatternField,
  CatalogImageField,
  MultipleImageField,
  CatalogNumberField,
};
