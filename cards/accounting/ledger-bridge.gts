// From the operational documents to the books. Quotes, invoices and payments in the commerce
// cluster and purchase orders in procurement run the business in decimal amounts with a currency on
// every line; the books post integer cents in one home currency. These turn one into the params of
// the accounting `…From…` operations, which create a draft that links back to its source. Nothing
// here writes: a draft is checked when it posts, like any other.

/** A source document the books can't take as it stands, with why. */
export class BridgeRefusal extends Error {}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}/;

/** A DateField value (a Date) or an ISO string, as the yyyy-mm-dd the books store. */
export function isoDay(value: unknown): string {
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    let m = String(value.getMonth() + 1).padStart(2, '0'),
      d = String(value.getDate()).padStart(2, '0');
    return `${value.getFullYear()}-${m}-${d}`;
  }
  return typeof value === 'string' && ISO_DATE.test(value)
    ? value.slice(0, 10)
    : '';
}

export const toMinor = (amount: unknown) =>
  Math.round((Number(amount) || 0) * 100);
const toThousandths = (qty: unknown) => Math.round((Number(qty) || 0) * 1000);

interface LineItemLike {
  description?: string | null;
  quantity?: number | null;
  unitPrice?: { amount?: number | null; currency?: { code?: string } } | null;
}

/** The one currency a set of line items is in, refusing a mix or one that isn't the books'. */
export function currencyOf(
  items: (LineItemLike | undefined)[],
  homeCurrency: string,
): string {
  let codes = new Set(
    items
      .filter(Boolean)
      .map((l) => l!.unitPrice?.currency?.code || homeCurrency),
  );
  if (codes.size > 1)
    throw new BridgeRefusal(
      `Its lines are in more than one currency (${[...codes].join(', ')}). The books take one currency per document.`,
    );
  let [code] = [...codes];
  if (code && code !== homeCurrency)
    throw new BridgeRefusal(
      `It's in ${code} and the books are kept in ${homeCurrency}. Documents in another currency come with multicurrency.`,
    );
  return homeCurrency;
}

/** Commerce line items as the books' sale lines, each posting to `incomeAccount`. */
export function saleLinesFrom(
  items: (LineItemLike | undefined)[],
  incomeAccount: string,
) {
  return items.filter(Boolean).map((l) => ({
    sku: null,
    description: l!.description ?? null,
    qty: toThousandths(l!.quantity),
    priceMinor: toMinor(l!.unitPrice?.amount),
    amountMinor: toMinor(
      (Number(l!.quantity) || 0) * (Number(l!.unitPrice?.amount) || 0),
    ),
    account: incomeAccount,
    cls: null,
    loc: null,
  }));
}

/**
 * Purchase order or vendor invoice lines as the books' bill lines, each debiting `expenseAccount`.
 * With `quantities` (a purchase order's received quantities, line by line), a line bills what was
 * received; lines with nothing received are left out.
 */
export function billLinesFrom(
  items: (LineItemLike | undefined)[],
  expenseAccount: string,
  quantities?: (number | null | undefined)[],
) {
  return items
    .map((l, i) => ({ l, qty: quantities ? quantities[i] : l?.quantity }))
    .filter(({ l, qty }) => l && (Number(qty) || 0) > 0)
    .map(({ l, qty }) => ({
      account: expenseAccount,
      sku: null,
      qty: toThousandths(qty),
      unitCostMinor: toMinor(l!.unitPrice?.amount),
      amountMinor: toMinor(
        (Number(qty) || 0) * (Number(l!.unitPrice?.amount) || 0),
      ),
      lot: null,
      debitAccount: expenseAccount,
      description: l!.description ?? null,
      cls: null,
      loc: null,
    }));
}

// A commerce invoice is a vendor's bill (accounts payable) when it answers a purchase order or sits
// in one of the payable statuses; otherwise it bills a customer.
const PAYABLE_STATUSES = new Set([
  'received',
  'matching',
  'matched',
  'exception',
  'approved-for-payment',
]);
export const isPayable = (invoice: {
  status?: string | null;
  purchaseOrder?: unknown;
}) => !!invoice.purchaseOrder || PAYABLE_STATUSES.has(invoice.status ?? '');

/** The last path segment of a card id, for document numbers that say where they came from. */
export const tail = (id: string | undefined) =>
  (id ?? '').split('/').pop()?.toUpperCase() ?? '';
