import type { TableColumn } from '../../components/table';
import { formatMoney } from '../commerce/line-item-totals';

import type { PurchaseRequisition } from '../procurement/purchase-requisition';
import type { Rfq } from '../procurement/rfq';
import type { PurchaseOrder } from '../procurement/purchase-order';
import type { GoodsReceipt } from '../procurement/goods-receipt';
import type { Invoice } from '../commerce/invoice';
import type { VendorProfile } from '../procurement/vendor-profile';

export const TABS = [
  { key: 'dashboard', label: 'Dashboard' },
  { key: 'vendors', label: 'Vendors' },
  { key: 'requisitions', label: 'Requisitions' },
  { key: 'rfqs', label: 'RFQs' },
  { key: 'pos', label: 'Purchase Orders' },
  { key: 'receipts', label: 'Receipts' },
  { key: 'invoices', label: 'Invoices' },
] as const;

// The stations of the P2P rail — the app's signature element. Each station
// is an HONEST affordance: clicking it lands on that stage's tab,
// pre-filtered to exactly the records its count was computed from.
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

// ---- station math (each count = exactly what its click shows) ----------
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

// Per-tab status badges: 'all' is index 0, always; each count is derived
// from the same collection the list renders.
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
        { id: 'match', label: 'In flight', count: inApFlight(r.apInvoices).length },
        {
          id: 'exception',
          label: 'Exception',
          count: r.apInvoices.filter((i) => i.status === 'exception').length,
        },
        {
          id: 'approved',
          label: 'Approved / paid',
          count: r.apInvoices.filter((i) =>
            ['approved-for-payment', 'partial', 'paid'].includes(i.status ?? ''),
          ).length,
        },
      ];
    default:
      return [];
  }
}

// ---- table columns per tab (a design decision, not schema-derived) ------
export const PO_COLUMNS: TableColumn[] = [
  { key: 'poNumber', label: 'PO #', value: (i: any) => i.poNumber },
  { key: 'status', label: 'Status', value: (i: any) => i.status },
  {
    key: 'total',
    label: 'Total',
    align: 'right',
    value: (i: any) => formatMoney(i.totalAmount ?? 0, 'USD'),
    sortValue: (i: any) => i.totalAmount ?? 0,
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
    value: (i: any) => formatMoney(i.estimatedTotal ?? 0, 'USD'),
    sortValue: (i: any) => i.estimatedTotal ?? 0,
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
