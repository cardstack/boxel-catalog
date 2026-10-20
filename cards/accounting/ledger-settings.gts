import { linksTo } from '@cardstack/base/card-api';
import { RealmConfig } from '@cardstack/base/realm-config';

// The books' settings live in the realm's own configuration (realm.json → config), because that is
// what a card operation can read: realmConfig().closedThrough and so on. Cards reach the same values
// through a link to the realm's config card. Every setting is optional, and an unset one reads as
// its default here and in the operations alike.
//
//   closedThrough    yyyy-mm-dd; nothing dated on or before it posts. Default: none.
//   materiality      integer cents; a journal entry at or above it needs a reviewer. Default: none.
//   chart            account codes a journal line may use. Default: any code.
//   currency         ISO 4217 code of the home currency. Default: USD.
//   fiscalYearStart  month the fiscal year starts, 1–12. Default: 1 (January).

export interface BooksSettings {
  closedThrough: string;
  materialityMinor: number | undefined;
  chart: string[] | undefined;
  currency: string;
  fiscalYearStart: number;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const CURRENCY = /^[A-Z]{3}$/;

export function booksSettings(config: unknown): BooksSettings {
  let c = (config && typeof config === 'object' ? config : {}) as Record<
    string,
    unknown
  >;
  let start = Number(c.fiscalYearStart);
  return {
    closedThrough:
      typeof c.closedThrough === 'string' && ISO_DATE.test(c.closedThrough)
        ? c.closedThrough
        : '',
    materialityMinor:
      typeof c.materiality === 'number' ? c.materiality : undefined,
    chart: Array.isArray(c.chart) ? c.chart.map(String) : undefined,
    currency:
      typeof c.currency === 'string' && CURRENCY.test(c.currency)
        ? c.currency
        : 'USD',
    fiscalYearStart:
      Number.isInteger(start) && start >= 1 && start <= 12 ? start : 1,
  };
}

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
