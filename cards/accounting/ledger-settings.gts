import { linksTo } from '@cardstack/base/card-api';
import { RealmConfig } from '@cardstack/base/realm-config';

// The books' settings live in the realm's own configuration (realm.json → config), because that is
// what a card operation can read: realmConfig().closedThrough and so on. Cards reach the same values
// through a link to the realm's config card. Every setting is optional, and an unset one reads as
// its default here and in the operations alike. A setting that is set but malformed is reported in
// `invalid` rather than replaced by its default: the operations read the raw value, so the settings
// view must show what is blocking a post, not hide it.
//
//   closedThrough    yyyy-mm-dd; nothing dated on or before it posts. Default: none.
//   materiality      integer cents; a journal entry at or above it needs a reviewer. Default: none.
//   chart            account codes (text) a document may post to. Default: any code.
//   currency         ISO 4217 code of the home currency. Default: USD.
//   fiscalYearStart  month the fiscal year starts, 1–12. Default: 1 (January).
//   taxCodes         each tax code's rates: { "WA-SEA": [{ "agency": "wa-dor", "ratePpm": 65000 }, …] };
//                    a code with no rates is exempt. Default: none, so only sales without codes post.

export type SettingKey =
  | 'closedThrough'
  | 'materiality'
  | 'chart'
  | 'currency'
  | 'fiscalYearStart'
  | 'taxCodes';

export type TaxCodeSettings = Record<
  string,
  { agency: string; ratePpm: number }[]
>;

export interface BooksSettings {
  closedThrough: string;
  materialityMinor: number | undefined;
  chart: string[] | undefined;
  currency: string;
  fiscalYearStart: number;
  taxCodes: TaxCodeSettings | undefined;
  // Each setting that is set but malformed, with what is wrong with it.
  invalid: Partial<Record<SettingKey, string>>;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const CURRENCY = /^[A-Z]{3}$/;
const shown = (v: unknown) => JSON.stringify(v);

export function booksSettings(config: unknown): BooksSettings {
  let c = (config && typeof config === 'object' ? config : {}) as Record<
    string,
    unknown
  >;
  let invalid: BooksSettings['invalid'] = {};
  let set = (k: SettingKey) => c[k] !== undefined && c[k] !== null;
  let closedOk =
    typeof c.closedThrough === 'string' && ISO_DATE.test(c.closedThrough);
  if (set('closedThrough') && !closedOk)
    invalid.closedThrough = `Not a yyyy-mm-dd date: ${shown(c.closedThrough)}`;
  let materialityOk =
    typeof c.materiality === 'number' && Number.isInteger(c.materiality);
  if (set('materiality') && !materialityOk)
    invalid.materiality = `Not a whole number of cents: ${shown(c.materiality)}`;
  let chartOk =
    Array.isArray(c.chart) && c.chart.every((x) => typeof x === 'string');
  if (set('chart') && !chartOk)
    invalid.chart =
      'Not a list of codes written as text, such as ["1000", "1100"]';
  let currencyOk = typeof c.currency === 'string' && CURRENCY.test(c.currency);
  if (set('currency') && !currencyOk)
    invalid.currency = `Not an ISO 4217 code: ${shown(c.currency)}`;
  let startOk =
    Number.isInteger(c.fiscalYearStart) &&
    (c.fiscalYearStart as number) >= 1 &&
    (c.fiscalYearStart as number) <= 12;
  if (set('fiscalYearStart') && !startOk)
    invalid.fiscalYearStart = `Not a month number from 1 to 12: ${shown(c.fiscalYearStart)}`;
  // The codes are kept as the operations read them, raw; any malformed code is named.
  let taxCodesOk =
    !!c.taxCodes &&
    typeof c.taxCodes === 'object' &&
    !Array.isArray(c.taxCodes);
  let badCodes = taxCodesOk
    ? Object.entries(c.taxCodes as Record<string, unknown>)
        .filter(
          ([, rates]) =>
            !Array.isArray(rates) ||
            !rates.every(
              (r) =>
                r &&
                typeof r.agency === 'string' &&
                Number.isInteger(r.ratePpm) &&
                r.ratePpm >= 0,
            ),
        )
        .map(([code]) => code)
    : [];
  if (set('taxCodes') && !taxCodesOk)
    invalid.taxCodes =
      'Not tax codes with their rates, such as { "WA": [{ "agency": "wa-dor", "ratePpm": 95000 }] }';
  else if (badCodes.length)
    invalid.taxCodes = `Rates aren't a list of { agency, ratePpm } with ratePpm a whole number for ${badCodes.join(', ')}`;
  return {
    closedThrough: closedOk ? (c.closedThrough as string) : '',
    materialityMinor: materialityOk ? (c.materiality as number) : undefined,
    chart: chartOk ? (c.chart as string[]) : undefined,
    currency: currencyOk ? (c.currency as string) : 'USD',
    fiscalYearStart: startOk ? (c.fiscalYearStart as number) : 1,
    taxCodes: taxCodesOk ? (c.taxCodes as TaxCodeSettings) : undefined,
    invalid,
  };
}

// The accounts the cluster's documents post to on their own, whatever a document names: receivables,
// payables, sales tax, opening balance equity and the two cost-of-sales accounts. A chart without
// them still takes postings to them, so the Ledger flags it.
export const FIXED_ACCOUNTS = ['1100', '2000', '2200', '3900', '5000', '5100'];

/** The realm's config card, which holds the books' settings. */
export const settingsLink = () =>
  linksTo(RealmConfig, { query: { page: { size: 1 } } });

/** The settings a card reads through its settings link. */
export const settingsOf = (card: { settings?: unknown }) =>
  booksSettings((card.settings as { config?: unknown } | undefined)?.config);

/** The first month (yyyy-mm) of the fiscal year that `month` falls in. */
export function fiscalYearStartOf(month: string, startMonth: number): string {
  let [y, m] = month.split('-').map(Number);
  if (!y || !m) return '';
  let year = m >= startMonth ? y : y - 1;
  return `${year}-${String(startMonth).padStart(2, '0')}`;
}

/** The first and last months (yyyy-mm) of the fiscal year that starts in `year`. */
export function fiscalYearMonths(
  year: string | number,
  startMonth: number,
): { fromMonth: string; toMonth: string } {
  let y = Number(year);
  if (!y) return { fromMonth: '', toMonth: '' };
  let end = startMonth === 1 ? 12 : startMonth - 1,
    endYear = startMonth === 1 ? y : y + 1;
  return {
    fromMonth: `${y}-${String(startMonth).padStart(2, '0')}`,
    toMonth: `${endYear}-${String(end).padStart(2, '0')}`,
  };
}
