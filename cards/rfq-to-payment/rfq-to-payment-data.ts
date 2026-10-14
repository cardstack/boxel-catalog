import type { TableColumn } from '../../components/table';
import { formatMoney, sumLineItems } from '../commerce/line-item-totals';

import type { PurchaseRequisition } from '../procurement/purchase-requisition';
import type { Rfq } from '../procurement/rfq';
import type { PurchaseOrder } from '../procurement/purchase-order';
import type { GoodsReceipt } from '../procurement/goods-receipt';
import type { Invoice } from '../commerce/invoice';
import type { VendorProfile } from '../procurement/vendor-profile';

export const TAB_OPTIONS = [
  { value: 'dashboard', label: 'Dashboard' },
  { value: 'vendors', label: 'Vendors' },
  { value: 'requisitions', label: 'Requisitions' },
  { value: 'rfqs', label: 'RFQs' },
  { value: 'pos', label: 'Purchase Orders' },
  { value: 'receipts', label: 'Receipts' },
  { value: 'invoices', label: 'Invoices' },
];

export const VIEW_OPTIONS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

// A line item with no currency code is priced in USD, the line item's own
// default.
const DEFAULT_CURRENCY = 'USD';

// The currency of a record priced by its line items.
export function currencyOf(record: {
  lineItems?: { unitPrice?: { currency?: { code?: string } } }[];
}): string {
  return sumLineItems(record.lineItems ?? []).code ?? DEFAULT_CURRENCY;
}

export interface PoValueBucket {
  key: string;
  label: string;
  hue: 'warning' | 'primary' | 'success';
  count: number;
  totalLabel: string;
  barStyle: string;
}

// PO value by lifecycle bucket: where the money is right now. Amounts in
// different currencies are never added together. When the purchase orders
// span more than one currency, each bucket lists a total per currency and
// the bars compare PO counts instead of value.
export function poValueBuckets(pos: PurchaseOrder[]): {
  buckets: PoValueBucket[];
  mixedCurrency: boolean;
} {
  let defs: {
    key: string;
    label: string;
    statuses: string[];
    hue: PoValueBucket['hue'];
  }[] = [
    {
      key: 'pending',
      label: 'Pending approval',
      statuses: ['pending-approval'],
      hue: 'warning',
    },
    {
      key: 'committed',
      label: 'Approved · committed',
      statuses: ['approved', 'sent', 'partially-received'],
      hue: 'primary',
    },
    {
      key: 'received',
      label: 'Received · actual',
      statuses: ['received', 'closed'],
      hue: 'success',
    },
  ];
  let mixedCurrency = new Set(pos.map(currencyOf)).size > 1;
  let rows = defs.map((def) => {
    let members = pos.filter((p) => def.statuses.includes(p.status ?? ''));
    let totals = new Map<string, number>();
    for (let po of members) {
      let code = currencyOf(po);
      totals.set(code, (totals.get(code) ?? 0) + (po.totalAmount ?? 0));
    }
    let amount = [...totals.values()].reduce((a, b) => a + b, 0);
    return { def, members, totals, amount };
  });
  let measure = (r: (typeof rows)[number]) =>
    mixedCurrency ? r.members.length : r.amount;
  let max = Math.max(1, ...rows.map(measure));
  return {
    mixedCurrency,
    buckets: rows.map((r) => ({
      key: r.def.key,
      label: r.def.label,
      hue: r.def.hue,
      count: r.members.length,
      totalLabel: r.totals.size
        ? [...r.totals]
            .map(([code, total]) => formatMoney(total, code))
            .join(' · ')
        : formatMoney(0, pos.length ? currencyOf(pos[0]) : DEFAULT_CURRENCY),
      barStyle: `width: ${Math.round((measure(r) / max) * 100)}%;`,
    })),
  };
}

// The stations of the Procure-to-Pay rail. Clicking a station lands on its
// stage's tab, filtered to exactly the records its count was computed from.
export interface Station {
  key: string;
  tab: string;
  label: string;
  filterLabel: string;
}

export const STATIONS: Station[] = [
  {
    key: 'onboarding',
    tab: 'vendors',
    label: 'Onboarding',
    filterLabel: 'awaiting vetting',
  },
  {
    key: 'requisitions',
    tab: 'requisitions',
    label: 'Requisitions',
    filterLabel: 'open',
  },
  { key: 'rfqs', tab: 'rfqs', label: 'RFQs', filterLabel: 'comparing' },
  {
    key: 'approvals',
    tab: 'pos',
    label: 'Approvals',
    filterLabel: 'pending approval',
  },
  {
    key: 'receiving',
    tab: 'pos',
    label: 'Receiving',
    filterLabel: 'awaiting receipt',
  },
  {
    key: 'match',
    tab: 'invoices',
    label: 'Match & Pay',
    filterLabel: 'in AP flight',
  },
];

export interface P2PRecords {
  requisitions: PurchaseRequisition[];
  rfqs: Rfq[];
  pos: PurchaseOrder[];
  receipts: GoodsReceipt[];
  profiles: VendorProfile[];
  apInvoices: Invoice[];
}

export interface Badge {
  id: string;
  label: string;
  count: number;
}

// Each station count is exactly what its click shows.
export const awaitingVetting = (profiles: VendorProfile[]) =>
  profiles.filter((p) =>
    ['intake', 'under-review'].includes(p.status ?? 'intake'),
  );

export const inApFlight = (invoices: Invoice[]) =>
  invoices.filter((i) =>
    ['received', 'matching', 'exception', 'matched'].includes(i.status ?? ''),
  );

export const openRequisitions = (requisitions: PurchaseRequisition[]) =>
  requisitions.filter((r) =>
    ['draft', 'submitted'].includes(r.status ?? 'draft'),
  );

export const comparingRfqs = (rfqs: Rfq[]) =>
  rfqs.filter((r) => ['sent', 'comparing'].includes(r.status ?? ''));

export const pendingApprovalPos = (pos: PurchaseOrder[]) =>
  pos.filter((p) => p.status === 'pending-approval');

export const awaitingReceiptPos = (pos: PurchaseOrder[]) =>
  pos.filter((p) =>
    ['approved', 'sent', 'partially-received'].includes(p.status ?? ''),
  );

export function stationCount(key: string, r: P2PRecords): number {
  switch (key) {
    case 'onboarding':
      return awaitingVetting(r.profiles).length;
    case 'match':
      return inApFlight(r.apInvoices).length;
    case 'requisitions':
      return openRequisitions(r.requisitions).length;
    case 'rfqs':
      return comparingRfqs(r.rfqs).length;
    case 'approvals':
      return pendingApprovalPos(r.pos).length;
    case 'receiving':
      return awaitingReceiptPos(r.pos).length;
    default:
      return 0;
  }
}

// Per-tab status badges. 'all' is always first, and each count comes from
// the same records the list renders.
export function badgesFor(tab: string, r: P2PRecords): Badge[] {
  switch (tab) {
    case 'requisitions':
      return [
        { id: 'all', label: 'All', count: r.requisitions.length },
        {
          id: 'requisitions',
          label: 'Open',
          count: openRequisitions(r.requisitions).length,
        },
        {
          id: 'converted',
          label: 'Converted',
          count: r.requisitions.filter((x) => x.status === 'converted-to-rfq')
            .length,
        },
      ];
    case 'rfqs':
      return [
        { id: 'all', label: 'All', count: r.rfqs.length },
        { id: 'rfqs', label: 'Comparing', count: comparingRfqs(r.rfqs).length },
        {
          id: 'awarded',
          label: 'Awarded',
          count: r.rfqs.filter((x) => x.status === 'awarded').length,
        },
      ];
    case 'pos':
      return [
        { id: 'all', label: 'All', count: r.pos.length },
        {
          id: 'approvals',
          label: 'Pending approval',
          count: pendingApprovalPos(r.pos).length,
        },
        {
          id: 'receiving',
          label: 'Awaiting receipt',
          count: awaitingReceiptPos(r.pos).length,
        },
        {
          id: 'received',
          label: 'Received',
          count: r.pos.filter((p) =>
            ['received', 'closed'].includes(p.status ?? ''),
          ).length,
        },
      ];
    case 'receipts':
      return [
        { id: 'all', label: 'All', count: r.receipts.length },
        {
          id: 'posted',
          label: 'Posted',
          count: r.receipts.filter((g) => g.posted).length,
        },
        {
          id: 'draft-receipts',
          label: 'Draft',
          count: r.receipts.filter((g) => !g.posted).length,
        },
      ];
    case 'invoices':
      return [
        { id: 'all', label: 'All', count: r.apInvoices.length },
        {
          id: 'match',
          label: 'In flight',
          count: inApFlight(r.apInvoices).length,
        },
        {
          id: 'exception',
          label: 'Exception',
          count: r.apInvoices.filter((i) => i.status === 'exception').length,
        },
        {
          id: 'approved',
          label: 'Approved / paid',
          count: r.apInvoices.filter((i) =>
            ['approved-for-payment', 'partial', 'paid'].includes(
              i.status ?? '',
            ),
          ).length,
        },
      ];
    default:
      return [];
  }
}

// Table columns per tab.
export const PO_COLUMNS: TableColumn[] = [
  { key: 'poNumber', label: 'PO #', value: (i: any) => i.poNumber },
  { key: 'status', label: 'Status', value: (i: any) => i.status },
  {
    key: 'total',
    label: 'Total',
    align: 'right',
    value: (i: any) => formatMoney(i.totalAmount ?? 0, currencyOf(i)),
    sortValue: (i: any) =>
      `${currencyOf(i)} ${(i.totalAmount ?? 0).toFixed(2).padStart(18, '0')}`,
  },
  {
    key: 'route',
    label: 'Approval route',
    showAbove: 640,
    value: (i: any) => i.approvalRoute,
  },
];

export const RFQ_COLUMNS: TableColumn[] = [
  { key: 'title', label: 'RFQ', value: (i: any) => i.title },
  { key: 'status', label: 'Status', value: (i: any) => i.status },
  {
    key: 'quotes',
    label: 'Quotes',
    align: 'right',
    value: (i: any) => {
      try {
        return (i.quotes ?? []).filter(Boolean).length;
      } catch {
        return 0;
      }
    },
  },
];

export const REQUISITION_COLUMNS: TableColumn[] = [
  { key: 'title', label: 'Requisition', value: (i: any) => i.title },
  { key: 'requester', label: 'Requester', value: (i: any) => i.requester },
  { key: 'status', label: 'Status', value: (i: any) => i.status },
  {
    key: 'total',
    label: 'Est. total',
    align: 'right',
    value: (i: any) => formatMoney(i.estimatedTotal ?? 0, currencyOf(i)),
    sortValue: (i: any) =>
      `${currencyOf(i)} ${(i.estimatedTotal ?? 0).toFixed(2).padStart(18, '0')}`,
  },
];

export const INVOICE_COLUMNS: TableColumn[] = [
  {
    key: 'number',
    label: 'Invoice',
    value: (i: any) => i.invoiceNumber || i.cardTitle,
  },
  { key: 'status', label: 'Status', value: (i: any) => i.status },
  {
    key: 'po',
    label: 'Against PO',
    showAbove: 640,
    value: (i: any) => {
      try {
        return i.purchaseOrder?.poNumber;
      } catch {
        return undefined;
      }
    },
  },
  {
    key: 'resolutions',
    label: 'Resolutions',
    align: 'right',
    value: (i: any) => (i.varianceResolutions ?? []).length,
  },
];

export const RECEIPT_COLUMNS: TableColumn[] = [
  { key: 'title', label: 'Receipt', value: (i: any) => i.title },
  {
    key: 'posted',
    label: 'Posted',
    value: (i: any) => (i.posted ? 'posted' : 'draft'),
  },
  { key: 'match', label: 'Match', value: (i: any) => i.matchResult },
  {
    key: 'by',
    label: 'Received by',
    showAbove: 640,
    value: (i: any) => i.receivedBy,
  },
];
