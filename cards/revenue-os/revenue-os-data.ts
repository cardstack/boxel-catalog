import type { CardDef } from '@cardstack/base/card-api';
import type { SegmentOption } from '@cardstack/pretui/components/segmented-control';
import type { SelectOption } from '@cardstack/pretui/components/select';
import { PIPELINE_STAGES } from '../crm/opportunity';
import { InvoiceStatusField, type Invoice } from '../commerce/invoice';
import type { Hue } from '../../components/state-pill';
import { statusHue } from '../../fields/status/status';

// The scoring rules are the app's domain knowledge; the Classify block only
// carries the classifier contract (criteria + facts in, label/score out).
export const LEAD_SCORING_CRITERIA = `Score this sales lead 0-100 for how likely it is to become a paying customer, and label it: "hot" (70-100), "warm" (40-69), or "cold" (0-39).
Signals, strongest first:
- Status progression: qualified is strong, contacted is moderate, new is neutral, disqualified scores near 0.
- Source and campaign agreement: a lead whose source matches its campaign's type (e.g. source "webinar" from a webinar campaign) shows real engagement; a lead with no campaign from "website" or "referral" is normal inbound, not a penalty.
- Campaign health: a running or completed campaign is a live channel; a canceled campaign weakens attribution.
- Firmographics: a named company and a business email domain (not gmail/yahoo/hotmail/outlook) suggest a real buyer.
Score conservatively when facts are missing rather than assuming the best.`;

export const OPEN_INVOICE_STATUSES = ['sent', 'viewed', 'partial'];
export const INVOICE_IMPORT_STATUSES = [
  'draft',
  'sent',
  'viewed',
  'partial',
  'paid',
  'void',
];

export const OPEN_STAGES = PIPELINE_STAGES.filter(
  (s) => s !== 'closed won' && s !== 'closed lost',
);

export const TABS: SegmentOption[] = [
  { value: 'pipeline', label: 'Pipeline' },
  { value: 'dashboard', label: 'Dashboard' },
  { value: 'accounts', label: 'Accounts' },
  { value: 'invoices', label: 'Invoices' },
  { value: 'leads', label: 'Leads' },
  { value: 'territories', label: 'Territories' },
  { value: 'proposals', label: 'Proposals' },
  { value: 'quotes', label: 'Quotes' },
];

export const INVOICE_FILTERS: SegmentOption[] = [
  { value: 'open', label: 'Unpaid' },
  { value: 'overdue', label: 'Overdue' },
  { value: 'paid', label: 'Paid' },
  { value: 'all', label: 'All' },
];

export const CLOSE_WINDOW_OPTIONS: SelectOption[] = [
  { value: 'all', label: 'Any close date' },
  { value: 'week', label: 'Closing this week' },
  { value: 'month', label: 'Closing this month' },
  { value: 'quarter', label: 'Closing this quarter' },
];

export const BOARD_SORT_OPTIONS: SelectOption[] = [
  { value: 'value', label: 'Highest value' },
  { value: 'probability', label: 'Most likely' },
  { value: 'stale', label: 'Stalest first' },
];

export const PERIOD_OPTIONS: SelectOption[] = [
  { value: 'month', label: 'This month' },
  { value: 'quarter', label: 'This quarter' },
  { value: 'year', label: 'This year' },
];

// Every total and trend in the console is in one currency. Amounts recorded in
// any other currency are left out of the sums rather than added as if they
// were dollars.
export const BASE_CURRENCY = 'USD';

interface MoneyLike {
  amount?: number | null;
  currency?: { code?: string | null } | null;
}

export function inBase(value: MoneyLike | null | undefined): number {
  if (!value) return 0;
  let code = value.currency?.code?.trim().toUpperCase() || BASE_CURRENCY;
  return code === BASE_CURRENCY ? (value.amount ?? 0) : 0;
}

// An invoice's currency is its line items'; one with none priced is treated
// as base, matching how its totals format.
export function isBaseInvoice(invoice: Invoice): boolean {
  let item = (invoice.lineItems ?? []).find((li) => li?.unitPrice);
  let code =
    item?.unitPrice?.currency?.code?.trim().toUpperCase() || BASE_CURRENCY;
  return code === BASE_CURRENCY;
}

export interface TrendPoint {
  label: string;
  value: number;
}

// Overdue is derived, not a stored status, so it takes its hue here.
export function invoiceHue(status: string | null | undefined): Hue {
  return status === 'overdue' ? 'red' : statusHue(InvoiceStatusField, status);
}

export function invoiceStatus(item: CardDef): string {
  return (item as Invoice).displayStatus ?? '';
}

// A due date is a calendar day, not an instant — an ISO round-trip moves it
// back one for anyone east of UTC.
export function asCalendarDay(at: Date): string {
  let month = String(at.getMonth() + 1).padStart(2, '0');
  let day = String(at.getDate()).padStart(2, '0');
  return `${at.getFullYear()}-${month}-${day}`;
}

export function stopThen(action: (...args: any[]) => void) {
  return (event: Event) => {
    event.stopPropagation();
    action(event);
  };
}
