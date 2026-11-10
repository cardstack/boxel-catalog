import { Component, type CardDef } from '@cardstack/base/card-api';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Table } from '@cardstack/pretui/components/table';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
} from '@cardstack/pretui/components/sidebar';
import PlusIcon from '@cardstack/boxel-icons/plus';
import ColumnsIcon from '@cardstack/boxel-icons/columns-3';
import ClockIcon from '@cardstack/boxel-icons/clock';
import AlertIcon from '@cardstack/boxel-icons/triangle-alert';
import BuildingIcon from '@cardstack/boxel-icons/building-2';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import CartIcon from '@cardstack/boxel-icons/shopping-cart';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';

import { VendorProfile } from '../procurement/vendor-profile';
import { Vendor, contractFacts } from '../procurement/vendor';
import { Rfq, RFQ_STATUS_LABELS } from '../procurement/rfq';
import {
  PurchaseOrder,
  PO_STATUS_LABELS,
  PO_ROUTE_LABELS,
  type PoApprovalRoute,
  poFacts,
} from '../procurement/purchase-order';
import { GoodsReceipt } from '../procurement/goods-receipt';

import type { VendorOnboardingApp } from './vendor-onboarding-app';

type Tone = 'neutral' | 'ok' | 'warn' | 'bad' | 'info';

// The console's tone names, as Pret UI StatusChip tones
const CHIP_TONE = {
  neutral: 'neutral',
  ok: 'success',
  warn: 'warning',
  bad: 'danger',
  info: 'info',
} as const;
const chipTone = (tone: Tone) => CHIP_TONE[tone];

interface Cell {
  text: string;
  kind?: 'name' | 'mono' | 'meta' | 'status' | 'end';
  tone?: Tone;
}
interface Row {
  id: string;
  card: CardDef;
  cells: Cell[];
}
interface Column {
  label: string;
  end?: boolean;
}
interface Section {
  id: string;
  title: string;
  hint: string;
  columns: Column[];
  rows: Row[];
  empty: string;
}
interface StatTile {
  label: string;
  value: string;
  hint: string;
  tone: Tone;
}

const STAGES = [
  {
    key: 'intake',
    label: 'Intake',
    tone: 'neutral' as Tone,
    hint: 'Paperwork received, nobody has looked yet',
  },
  {
    key: 'under-review',
    label: 'Under Review',
    tone: 'warn' as Tone,
    hint: 'Compliance documents being checked',
  },
  {
    key: 'approved',
    label: 'Approved',
    tone: 'info' as Tone,
    hint: 'Cleared to onboard: run Onboard Vendor to activate',
  },
  {
    key: 'onboarded',
    label: 'Onboarded',
    tone: 'ok' as Tone,
    hint: 'Active vendor record; invitable to RFQs',
  },
  {
    key: 'rejected',
    label: 'Rejected',
    tone: 'bad' as Tone,
    hint: 'Vetting failed; reasons in notes',
  },
];
const STAGE_LABEL = Object.fromEntries(STAGES.map((s) => [s.key, s.label]));
const STAGE_TONE = Object.fromEntries(STAGES.map((s) => [s.key, s.tone]));

const TABS = [
  {
    key: 'board',
    label: 'Onboarding board',
    group: 'vetting',
    icon: ColumnsIcon,
  },
  {
    key: 'review',
    label: 'Awaiting review',
    group: 'vetting',
    icon: ClockIcon,
  },
  {
    key: 'lapsed',
    label: 'Lapsed compliance',
    group: 'vetting',
    icon: AlertIcon,
  },
  { key: 'vendors', label: 'Vendors', group: 'proc', icon: BuildingIcon },
  { key: 'rfqs', label: 'RFQs', group: 'proc', icon: FileTextIcon },
  { key: 'orders', label: 'Purchase orders', group: 'proc', icon: CartIcon },
  {
    key: 'receipts',
    label: 'Goods receipts',
    group: 'proc',
    icon: ReceiptIcon,
  },
];

const RFQ_TONE: Record<string, Tone> = {
  draft: 'neutral',
  sent: 'info',
  comparing: 'warn',
  awarded: 'ok',
  cancelled: 'bad',
};
const PO_TONE: Record<string, Tone> = {
  draft: 'neutral',
  'pending-approval': 'warn',
  approved: 'info',
  sent: 'info',
  'partially-received': 'warn',
  received: 'ok',
  closed: 'ok',
  rejected: 'bad',
};
const MATCH: Record<string, { label: string; tone: Tone }> = {
  matched: { label: 'Matched', tone: 'ok' },
  partial: { label: 'Short', tone: 'warn' },
  over: { label: 'Over', tone: 'bad' },
  empty: { label: 'No lines', tone: 'neutral' },
};

const DAY = 86_400_000;
const today = () => new Date(new Date().toDateString());
const daysBetween = (a: Date, b: Date) =>
  Math.round((b.getTime() - a.getTime()) / DAY);
const fmtDate = (d?: Date | null) =>
  d
    ? d.toLocaleDateString('en-GB', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
      })
    : '—';
const usd = (n: number) =>
  new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(n);
const plural = (n: number, one: string, many = `${one}s`) =>
  `${n} ${n === 1 ? one : many}`;

const SEARCH_FORMS = [
  { name: 'full', minWidth: 14 },
  { name: 'menu', minWidth: 0 },
];
const FILTER_FORMS = [
  { name: 'full', minWidth: 22 },
  { name: 'menu', minWidth: 0 },
];
const PRIMARY_FORMS = [{ name: 'full', minWidth: 9 }];

const name = (p: VendorProfile) => p.companyName || p.cardTitle || 'Untitled';
const stageOf = (p: VendorProfile) => p.status ?? 'intake';
const complianceCell = (p: VendorProfile): Cell =>
  p.complianceOk
    ? { text: 'Compliance current', kind: 'status', tone: 'ok' }
    : { text: 'Compliance lapsed', kind: 'status', tone: 'bad' };

// Every credential on the profile that has run out, insurance included.
// Missing insurance counts too (on: null): VendorProfile.complianceOk treats
// absence as non-compliance, so this list must match the lapsed count.
function expiredCredentials(p: VendorProfile) {
  let now = today();
  let out: { name: string; issuer: string; on: Date | null }[] = [];
  if (!p.insuranceExpiry || p.insuranceExpiry < now) {
    out.push({ name: 'Insurance', issuer: '—', on: p.insuranceExpiry ?? null });
  }
  for (let c of (p.certifications ?? []).filter(Boolean)) {
    if (c.expiresOn && c.expiresOn < now) {
      out.push({
        name: c.name ?? 'Certification',
        issuer: c.issuer ?? '—',
        on: c.expiresOn,
      });
    }
  }
  return out;
}

function nextStep(p: VendorProfile): string {
  let lapsed = expiredCredentials(p)[0];
  if (lapsed) {
    return `${lapsed.on ? 'Renew' : 'Add'} ${lapsed.name}`;
  }
  return stageOf(p) === 'intake' ? 'Start review' : 'Finish the review';
}

export class VendorOnboardingConsole extends Component<
  typeof VendorOnboardingApp
> {
  @tracked activeTab = 'board';
  @tracked filter = 'all';
  @tracked searchText = '';

  private profileList: ReturnType<getCards> | undefined;
  private vendorList: ReturnType<getCards> | undefined;
  private rfqList: ReturnType<getCards> | undefined;
  private poList: ReturnType<getCards> | undefined;
  private receiptList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let live = { isLive: true as const };
    let realms = () => this.realms;
    let queryFor = (type: any) => () => {
      let ref = identifyCard(type);
      return ref ? { filter: { type: ref } } : undefined;
    };
    let ctx = this.args.context;
    this.profileList = ctx?.getCards(
      this,
      queryFor(VendorProfile),
      realms,
      live,
    );
    this.vendorList = ctx?.getCards(this, queryFor(Vendor), realms, live);
    this.rfqList = ctx?.getCards(this, queryFor(Rfq), realms, live);
    this.poList = ctx?.getCards(this, queryFor(PurchaseOrder), realms, live);
    this.receiptList = ctx?.getCards(
      this,
      queryFor(GoodsReceipt),
      realms,
      live,
    );
  }

  private get realms(): string[] | undefined {
    let url = this.args.model?.[realmURL];
    return url ? [url.href] : undefined;
  }

  // CRUD functions reach the card only in interactive contexts, so their
  // absence marks prerender, where the query-heavy console must not mount.
  get isInteractive() {
    return Boolean(this.args.viewCard);
  }

  get isLoading() {
    return [
      this.profileList,
      this.vendorList,
      this.rfqList,
      this.poList,
      this.receiptList,
    ].some((l) => l?.isLoading);
  }

  private list<T>(l: ReturnType<getCards> | undefined): T[] {
    return ((l?.instances ?? []) as T[]).filter(Boolean);
  }
  get profiles() {
    return this.list<VendorProfile>(this.profileList);
  }
  get vendors() {
    return this.list<Vendor>(this.vendorList);
  }
  get rfqs() {
    return this.list<Rfq>(this.rfqList);
  }
  get pos() {
    return this.list<PurchaseOrder>(this.poList);
  }
  get receipts() {
    return this.list<GoodsReceipt>(this.receiptList);
  }

  private inStage = (...keys: string[]) =>
    this.profiles.filter((p) => keys.includes(stageOf(p)));
  get waiting() {
    return this.inStage('intake', 'under-review');
  }
  get lapsed() {
    return this.profiles.filter((p) => !p.complianceOk);
  }
  get approved() {
    return this.inStage('approved');
  }

  // ---- navigation ------------------------------------------------------
  setTab = (key: string) => {
    this.activeTab = key;
    this.filter = 'all';
    this.searchText = '';
  };
  setFilter = (value: string) => {
    this.filter = value;
  };
  setSearch = (value: string) => {
    this.searchText = value;
  };

  private navItem = (t: (typeof TABS)[number]) => {
    let counts: Record<string, number> = {
      board: this.profiles.length,
      review: this.waiting.length,
      lapsed: this.lapsed.length,
      vendors: this.vendors.length,
    };
    let n = counts[t.key];
    return {
      ...t,
      active: t.key === this.activeTab,
      badge: n ? String(n) : undefined,
    };
  };
  get navVetting() {
    return TABS.filter((t) => t.group === 'vetting').map(this.navItem);
  }
  get navProcurement() {
    return TABS.filter((t) => t.group === 'proc').map(this.navItem);
  }

  get tab() {
    return TABS.find((t) => t.key === this.activeTab) ?? TABS[0];
  }
  get eyebrow() {
    return `Vendor Onboarding · ${
      this.tab.group === 'vetting' ? 'Vendor vetting' : 'Procurement'
    }`;
  }
  get pageTitle() {
    return this.activeTab === 'board' ? 'Vendor Onboarding' : this.tab.label;
  }

  get pageSub(): string {
    if (this.isLoading) {
      return 'Loading…';
    }
    switch (this.activeTab) {
      case 'review': {
        let oldest = Math.max(
          0,
          ...this.waiting.map((p) => this.daysWaiting(p)),
        );
        return `${plural(this.waiting.length, 'profile')} waiting on your review · oldest has waited ${plural(oldest, 'day')}`;
      }
      case 'lapsed':
        return `${plural(this.lapsed.length, 'profile')} with a missing or expired credential · approval and RFQ awards are blocked`;
      case 'vendors':
        return `${plural(this.vendors.length, 'active vendor')} · ${plural(this.approved.length, 'approved profile')} ready to onboard`;
      case 'rfqs': {
        let open = this.rfqs.filter(
          (r) => !['awarded', 'cancelled'].includes(r.status ?? ''),
        );
        let sent = this.rfqs.filter((r) => r.status === 'sent');
        return `${plural(open.length, 'open request')} for quotation · ${sent.length} waiting on quotes`;
      }
      case 'orders': {
        let pending = this.pos.filter((p) => p.status === 'pending-approval');
        let partial = this.pos.filter((p) => p.status === 'partially-received');
        return `${plural(pending.length, 'order')} waiting on approval · ${partial.length} partially received`;
      }
      case 'receipts': {
        let unposted = this.receipts.filter((r) => !r.posted);
        let short = this.receipts.filter((r) => r.matchResult === 'partial');
        let over = this.receipts.filter((r) => r.matchResult === 'over');
        return `${plural(unposted.length, 'receipt')} not posted · ${short.length} short, ${over.length} over`;
      }
      default: {
        if (!this.profiles.length) {
          return 'No vendor profiles yet. Add one to start vetting.';
        }
        if (!this.waiting.length && !this.lapsed.length) {
          return 'Pipeline clear: every profile vetted, every credential current.';
        }
        return `${plural(this.waiting.length, 'profile')} waiting on your review · ${this.lapsed.length} with lapsed compliance`;
      }
    }
  }

  // ---- stat strip ------------------------------------------------------
  private n = (x: number) => (this.isLoading ? '–' : String(x));

  get stats(): StatTile[] {
    let n = this.n;
    switch (this.activeTab) {
      case 'review': {
        let blocked = this.waiting.filter((p) => !p.complianceOk);
        return [
          {
            label: 'Awaiting review',
            value: n(this.waiting.length),
            hint: 'intake + under review',
            tone: 'warn',
          },
          {
            label: 'Intake',
            value: n(this.inStage('intake').length),
            hint: 'nobody has looked yet',
            tone: 'neutral',
          },
          {
            label: 'Under review',
            value: n(this.inStage('under-review').length),
            hint: 'documents being checked',
            tone: 'warn',
          },
          {
            label: 'Blocked by compliance',
            value: n(blocked.length),
            hint: "can't be approved yet",
            tone: 'bad',
          },
        ];
      }
      case 'lapsed': {
        let creds = this.profiles.flatMap(expiredCredentials);
        let soon = new Date(today().getTime() + 90 * DAY);
        let expiring = this.profiles.filter(
          (p) =>
            p.complianceOk &&
            ((p.insuranceExpiry && p.insuranceExpiry < soon) ||
              (p.certifications ?? []).some(
                (c) => c?.expiresOn && c.expiresOn < soon,
              )),
        );
        return [
          {
            label: 'Lapsed profiles',
            value: n(this.lapsed.length),
            hint: 'award blocked',
            tone: 'bad',
          },
          {
            label: 'Expired credentials',
            value: n(creds.length),
            hint: 'insurance + certifications',
            tone: 'bad',
          },
          {
            label: 'Expiring in 90 days',
            value: n(expiring.length),
            hint: 'renew before they lapse',
            tone: 'warn',
          },
          {
            label: 'Compliant',
            value: n(this.profiles.length - this.lapsed.length),
            hint: 'every credential current',
            tone: 'ok',
          },
        ];
      }
      case 'vendors': {
        let spend = this.vendors.reduce((s, v) => s + (v.spendYtd ?? 0), 0);
        let ending = this.vendors.filter(
          (v) => contractFacts(v).state === 'expiring',
        );
        return [
          {
            label: 'Active vendors',
            value: n(this.vendors.length),
            hint: 'invitable to RFQs',
            tone: 'ok',
          },
          {
            label: 'Ready to onboard',
            value: n(this.approved.length),
            hint: 'approved profiles',
            tone: 'info',
          },
          {
            label: 'Spend YTD',
            value: this.isLoading ? '–' : usd(spend),
            hint: 'across active vendors',
            tone: 'neutral',
          },
          {
            label: 'Contracts ending soon',
            value: n(ending.length),
            hint: 'renew or replace',
            tone: 'warn',
          },
        ];
      }
      case 'rfqs': {
        let c = (s: string) => this.rfqs.filter((r) => r.status === s).length;
        return [
          {
            label: 'Open',
            value: n(this.rfqs.length - c('awarded') - c('cancelled')),
            hint: 'draft, sent or comparing',
            tone: 'neutral',
          },
          {
            label: 'Waiting on quotes',
            value: n(c('sent')),
            hint: 'sent to vendors',
            tone: 'info',
          },
          {
            label: 'Comparing',
            value: n(c('comparing')),
            hint: 'quotes in, pick one',
            tone: 'warn',
          },
          {
            label: 'Awarded',
            value: n(c('awarded')),
            hint: 'turned into an order',
            tone: 'ok',
          },
        ];
      }
      case 'orders': {
        let open = this.pos.filter(
          (p) => !['closed', 'rejected', 'received'].includes(p.status ?? ''),
        );
        let c = (...s: string[]) =>
          this.pos.filter((p) => s.includes(p.status ?? '')).length;
        let committed = open.reduce((s, p) => s + (p.totalAmount ?? 0), 0);
        return [
          {
            label: 'Open orders',
            value: n(open.length),
            hint: 'not yet received',
            tone: 'neutral',
          },
          {
            label: 'Pending approval',
            value: n(c('pending-approval')),
            hint: 'on an approval route',
            tone: 'warn',
          },
          {
            label: 'Awaiting delivery',
            value: n(c('approved', 'sent', 'partially-received')),
            hint: 'sent to the vendor',
            tone: 'info',
          },
          {
            label: 'Committed spend',
            value: this.isLoading ? '–' : usd(committed),
            hint: 'open orders',
            tone: 'neutral',
          },
        ];
      }
      case 'receipts': {
        let c = (s: string) =>
          this.receipts.filter((r) => r.matchResult === s).length;
        return [
          {
            label: 'Receipts',
            value: n(this.receipts.length),
            hint: 'against purchase orders',
            tone: 'neutral',
          },
          {
            label: 'Matched',
            value: n(c('matched')),
            hint: 'every line as ordered',
            tone: 'ok',
          },
          {
            label: 'Short',
            value: n(c('partial')),
            hint: 'fewer than ordered',
            tone: 'warn',
          },
          {
            label: 'Over',
            value: n(c('over')),
            hint: 'more than ordered',
            tone: 'bad',
          },
        ];
      }
      default:
        return [
          {
            label: 'Profiles',
            value: n(this.profiles.length),
            hint: `across ${STAGES.length} stages`,
            tone: 'neutral',
          },
          {
            label: 'Awaiting review',
            value: n(this.waiting.length),
            hint: 'intake + under review',
            tone: 'warn',
          },
          {
            label: 'Ready to onboard',
            value: n(this.approved.length),
            hint: 'approved, run Onboard Vendor',
            tone: 'info',
          },
          {
            label: 'Compliant',
            value: n(this.profiles.length - this.lapsed.length),
            hint: 'insurance + certifications current',
            tone: 'ok',
          },
          {
            label: 'Lapsed compliance',
            value: n(this.lapsed.length),
            hint: 'award blocked',
            tone: 'bad',
          },
        ];
    }
  }

  // ---- toolbar ---------------------------------------------------------
  get filterOptions(): { value: string; label: string }[] {
    let all = { value: 'all', label: 'All' };
    let stage = (k: string) => ({ value: k, label: STAGE_LABEL[k] });
    switch (this.activeTab) {
      case 'board':
        return [all, ...STAGES.map((s) => stage(s.key))];
      case 'review':
      case 'lapsed':
        return [all, stage('intake'), stage('under-review')];
      case 'rfqs':
        return [
          all,
          ...Object.entries(RFQ_STATUS_LABELS).map(([value, label]) => ({
            value,
            label,
          })),
        ];
      case 'orders':
        return [
          all,
          ...[
            'pending-approval',
            'approved',
            'sent',
            'partially-received',
            'received',
          ].map((value) => ({ value, label: PO_STATUS_LABELS[value] })),
        ];
      case 'receipts':
        return [
          all,
          ...['matched', 'partial', 'over'].map((value) => ({
            value,
            label: MATCH[value].label,
          })),
        ];
      default:
        return [];
    }
  }
  get filterMenuItems() {
    return this.filterOptions.map((o) => ({
      label: o.label,
      value: o.value,
      group: 'filter',
      checked: o.value === this.filter,
      onSelect: () => this.setFilter(o.value),
    }));
  }

  get noun() {
    return (
      {
        board: 'profiles',
        review: 'profiles',
        lapsed: 'profiles',
        vendors: 'vendors',
        rfqs: 'RFQs',
        orders: 'orders',
        receipts: 'receipts',
      } as Record<string, string>
    )[this.activeTab];
  }

  private matches = (text: string, status: string) =>
    (this.filter === 'all' || this.filter === status) &&
    (!this.searchText ||
      text.toLowerCase().includes(this.searchText.toLowerCase()));

  get canAddProfile() {
    return ['board', 'review'].includes(this.activeTab);
  }

  // ---- board -----------------------------------------------------------
  get lanes() {
    let shown = this.profiles.filter((p) =>
      this.matches(
        `${name(p)} ${p.contactName ?? ''} ${p.serviceCategory ?? ''}`,
        stageOf(p),
      ),
    );
    return STAGES.filter(
      (s) => this.filter === 'all' || this.filter === s.key,
    ).map((s) => ({
      ...s,
      cards: shown
        .filter((p) => stageOf(p) === s.key)
        .map((p) => ({
          card: p,
          name: name(p),
          meta: [p.contactName, p.serviceCategory].filter(Boolean).join(' · '),
          compliance: complianceCell(p),
          fact: this.factOf(p),
        })),
    }));
  }

  private factOf(p: VendorProfile): string {
    let lapsed = expiredCredentials(p)[0];
    if (lapsed) {
      return lapsed.on
        ? `${lapsed.name} expired ${fmtDate(lapsed.on)}`
        : 'No insurance on file';
    }
    if (stageOf(p) === 'onboarded') {
      return 'Vendor record active';
    }
    if (stageOf(p) === 'rejected') {
      return p.notes || 'Vetting failed';
    }
    return p.insuranceExpiry
      ? `Insurance until ${fmtDate(p.insuranceExpiry)}`
      : 'No insurance on file';
  }

  daysWaiting = (p: VendorProfile) => {
    let created = p.lifecycle?.createdAt;
    return created ? Math.max(0, daysBetween(created, today())) : 0;
  };

  // ---- table tabs ------------------------------------------------------
  get sections(): Section[] {
    switch (this.activeTab) {
      case 'review':
        return [this.reviewSection];
      case 'lapsed':
        return [this.lapsedSection];
      case 'vendors':
        return [this.vendorSection, this.readySection];
      case 'rfqs':
        return [this.rfqSection];
      case 'orders':
        return [this.orderSection];
      case 'receipts':
        return [this.receiptSection];
      default:
        return [];
    }
  }

  private get reviewSection(): Section {
    let rows = [...this.waiting]
      .sort((a, b) => this.daysWaiting(b) - this.daysWaiting(a))
      .filter((p) =>
        this.matches(`${name(p)} ${p.contactName ?? ''}`, stageOf(p)),
      )
      .map((p) => ({
        id: p.id,
        card: p as CardDef,
        cells: [
          { text: name(p), kind: 'name' },
          {
            text:
              [p.contactName, p.serviceCategory].filter(Boolean).join(' · ') ||
              '—',
            kind: 'meta',
          },
          {
            text: STAGE_LABEL[stageOf(p)],
            kind: 'status',
            tone: STAGE_TONE[stageOf(p)],
          },
          complianceCell(p),
          { text: fmtDate(p.insuranceExpiry), kind: 'mono' },
          { text: String(this.daysWaiting(p)), kind: 'end' },
          { text: nextStep(p) },
        ] as Cell[],
      }));
    return {
      id: 'review',
      title: 'Review queue',
      hint: 'Oldest first. Open a profile to approve or reject it.',
      columns: [
        { label: 'Vendor' },
        { label: 'Owner' },
        { label: 'Stage' },
        { label: 'Compliance' },
        { label: 'Insurance until' },
        { label: 'Days waiting', end: true },
        { label: 'Next step' },
      ],
      rows,
      empty: 'Nothing waiting on your review.',
    };
  }

  private get lapsedSection(): Section {
    let now = today();
    let rows = this.lapsed
      .filter((p) => this.matches(name(p), stageOf(p)))
      .flatMap((p) =>
        expiredCredentials(p).map((c, i) => ({
          id: `${p.id}#${i}`,
          card: p as CardDef,
          cells: [
            { text: name(p), kind: 'name' },
            { text: p.contactName || '—', kind: 'meta' },
            {
              text: STAGE_LABEL[stageOf(p)],
              kind: 'status',
              tone: STAGE_TONE[stageOf(p)],
            },
            { text: c.name },
            { text: c.issuer, kind: 'meta' },
            { text: c.on ? fmtDate(c.on) : 'Not on file', kind: 'mono' },
            {
              text: c.on ? String(daysBetween(c.on, now)) : '—',
              kind: 'end',
            },
            {
              text: c.on
                ? `Request a renewed ${c.name}`
                : `Request ${c.name} documents`,
            },
          ] as Cell[],
        })),
      );
    return {
      id: 'lapsed',
      title: 'Expired credentials',
      hint: 'Approval and RFQ awards stay blocked until each one is renewed.',
      columns: [
        { label: 'Vendor' },
        { label: 'Owner' },
        { label: 'Stage' },
        { label: 'Credential' },
        { label: 'Issuer' },
        { label: 'Expired on' },
        { label: 'Days lapsed', end: true },
        { label: 'Action' },
      ],
      rows,
      empty: 'Every credential is current.',
    };
  }

  private get vendorSection(): Section {
    let rows = this.vendors
      .filter((v) =>
        this.matches(`${v.name ?? ''} ${v.contactName ?? ''}`, 'all'),
      )
      .map((v) => {
        let len = v.contractLength;
        return {
          id: v.id,
          card: v as CardDef,
          cells: [
            { text: v.name || v.cardTitle || 'Untitled', kind: 'name' },
            { text: v.contactName || '—', kind: 'meta' },
            { text: v.serviceCategory || '—' },
            { text: fmtDate(v.contractStart), kind: 'mono' },
            {
              text:
                len?.value != null
                  ? `${len.value} ${len.unit ?? ''}`.trim()
                  : '—',
              kind: 'mono',
            },
            {
              text:
                typeof v.performanceRating === 'number'
                  ? `${v.performanceRating} / 5`
                  : '—',
              kind: 'mono',
            },
            {
              text: typeof v.spendYtd === 'number' ? usd(v.spendYtd) : '—',
              kind: 'end',
            },
            {
              text: v.website
                ? String(v.website).replace(/^https?:\/\//, '')
                : '—',
              kind: 'meta',
            },
          ] as Cell[],
        };
      });
    return {
      id: 'vendors',
      title: 'Active vendors',
      hint: 'Onboarded vendors, invitable to RFQs.',
      columns: [
        { label: 'Vendor' },
        { label: 'Contact' },
        { label: 'Category' },
        { label: 'Contract start' },
        { label: 'Length' },
        { label: 'Performance' },
        { label: 'Spend YTD', end: true },
        { label: 'Website' },
      ],
      rows,
      empty: 'No active vendors yet.',
    };
  }

  private get readySection(): Section {
    let rows = this.approved.map((p) => ({
      id: p.id,
      card: p as CardDef,
      cells: [
        { text: name(p), kind: 'name' },
        { text: p.contactName || '—', kind: 'meta' },
        complianceCell(p),
        {
          text:
            (p.certifications ?? [])[0]?.name ||
            (p.insuranceExpiry
              ? `Insurance until ${fmtDate(p.insuranceExpiry)}`
              : '—'),
        },
        { text: 'Open to run Onboard Vendor' },
      ] as Cell[],
    }));
    return {
      id: 'ready',
      title: 'Ready to onboard',
      hint: 'Approved profiles. Onboard Vendor creates the vendor record.',
      columns: [
        { label: 'Vendor' },
        { label: 'Owner' },
        { label: 'Compliance' },
        { label: 'Credential' },
        { label: 'Action' },
      ],
      rows,
      empty: 'No approved profiles waiting.',
    };
  }

  private get rfqSection(): Section {
    let rows = this.rfqs
      .filter((r) => this.matches(r.cardTitle ?? '', r.status ?? 'draft'))
      .map((r) => {
        let status = r.status ?? 'draft';
        let invited = (r.invitedVendors ?? []).filter(Boolean);
        return {
          id: r.id,
          card: r as CardDef,
          cells: [
            { text: r.cardTitle || 'Untitled RFQ', kind: 'name' },
            { text: r.requisition?.cardTitle || '—', kind: 'meta' },
            { text: String((r.lineItems ?? []).length), kind: 'end' },
            {
              text: invited.map((v) => v.name || v.cardTitle).join(', ') || '—',
              kind: 'meta',
            },
            {
              text: String((r.quotes ?? []).filter(Boolean).length),
              kind: 'end',
            },
            { text: fmtDate(r.responseDeadline), kind: 'mono' },
            {
              text: RFQ_STATUS_LABELS[status] ?? status,
              kind: 'status',
              tone: RFQ_TONE[status],
            },
          ] as Cell[],
        };
      });
    return {
      id: 'rfqs',
      title: 'Requests for quotation',
      hint: 'Only compliant vendors can be awarded.',
      columns: [
        { label: 'RFQ' },
        { label: 'Requisition' },
        { label: 'Lines', end: true },
        { label: 'Invited vendors' },
        { label: 'Quotes', end: true },
        { label: 'Response deadline' },
        { label: 'Status' },
      ],
      rows,
      empty: 'No RFQs in this view.',
    };
  }

  private get orderSection(): Section {
    let rows = this.pos
      .filter((p) =>
        this.matches(
          `${p.poNumber ?? ''} ${p.vendor?.name ?? ''}`,
          p.status ?? 'draft',
        ),
      )
      .map((p) => {
        let status = p.status ?? 'draft';
        return {
          id: p.id,
          card: p as CardDef,
          cells: [
            { text: p.poNumber || 'Draft PO', kind: 'name' },
            { text: p.vendor?.name || '—' },
            { text: p.rfq?.cardTitle || '—', kind: 'meta' },
            {
              text: PO_ROUTE_LABELS[p.approvalRoute as PoApprovalRoute] ?? '—',
              kind: 'meta',
            },
            { text: fmtDate(p.expectedDelivery), kind: 'mono' },
            { text: poFacts(p).total, kind: 'end' },
            {
              text: PO_STATUS_LABELS[status] ?? status,
              kind: 'status',
              tone: PO_TONE[status],
            },
          ] as Cell[],
        };
      });
    return {
      id: 'orders',
      title: 'Purchase orders',
      hint: 'Orders placed with onboarded vendors.',
      columns: [
        { label: 'Order' },
        { label: 'Vendor' },
        { label: 'From RFQ' },
        { label: 'Approval route' },
        { label: 'Expected delivery' },
        { label: 'Total', end: true },
        { label: 'Status' },
      ],
      rows,
      empty: 'No purchase orders in this view.',
    };
  }

  private get receiptSection(): Section {
    let rows = this.receipts
      .filter((r) =>
        this.matches(
          `${r.cardTitle ?? ''} ${r.receivedBy ?? ''}`,
          r.matchResult ?? 'empty',
        ),
      )
      .map((r) => {
        let match = MATCH[r.matchResult ?? 'empty'] ?? MATCH.empty;
        return {
          id: r.id,
          card: r as CardDef,
          cells: [
            { text: r.cardTitle || 'Receipt', kind: 'name' },
            {
              text: [r.receivedBy, fmtDate(r.receivedOn)]
                .filter(Boolean)
                .join(' · '),
              kind: 'meta',
            },
            { text: r.purchaseOrder?.poNumber || '—', kind: 'mono' },
            { text: String((r.lines ?? []).length), kind: 'end' },
            { text: match.label, kind: 'status', tone: match.tone },
            r.posted
              ? { text: 'Posted', kind: 'status', tone: 'ok' }
              : { text: 'Not posted', kind: 'status', tone: 'neutral' },
          ] as Cell[],
        };
      });
    return {
      id: 'receipts',
      title: 'Goods receipts',
      hint: 'Each receipt is matched line by line against its order.',
      columns: [
        { label: 'Receipt' },
        { label: 'Received by' },
        { label: 'Purchase order' },
        { label: 'Lines', end: true },
        { label: 'Match' },
        { label: 'Posted' },
      ],
      rows,
      empty: 'No receipts in this view.',
    };
  }

  // ---- actions ---------------------------------------------------------
  openCard = (card: CardDef) => {
    this.args.viewCard?.(card, 'isolated');
  };

  addProfile = () => {
    let ref = identifyCard(VendorProfile);
    let realm = this.args.model?.[realmURL];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, {
      realmURL: realm,
      doc: {
        data: { attributes: { status: 'intake' }, meta: { adoptsFrom: ref } },
      },
    });
  };

  SEARCH_FORMS = SEARCH_FORMS;
  FILTER_FORMS = FILTER_FORMS;
  PRIMARY_FORMS = PRIMARY_FORMS;

  <template>
    <div class='app'>
      {{#if this.isInteractive}}
        <Sidebar
          class='shell'
          @label='Vendor Onboarding'
          @collapsible='rail'
          @railBreakpoint={{1100}}
          @mobileBreakpoint={{720}}
          @bordered={{true}}
          @scroll='content'
          @resizable={{true}}
        >
          <:header as |bar|>
            <div class='brand'>
              <span class='brand-mark' aria-hidden='true'>Vo</span>
              {{#unless bar.collapsed}}
                <span class='brand-name'><small>Procurement</small>Vendor
                  Onboarding</span>
              {{/unless}}
            </div>
          </:header>
          <:nav as |bar|>
            <SidebarGroup @label='Vendor vetting' @hideLabel={{bar.collapsed}}>
              {{#each this.navVetting key='key' as |item|}}
                <SidebarItem
                  @label={{item.label}}
                  @badge={{unless bar.collapsed item.badge}}
                  @active={{item.active}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.setTab item.key}}
                >
                  <:icon><item.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
            <SidebarGroup @label='Procurement' @hideLabel={{bar.collapsed}}>
              {{#each this.navProcurement key='key' as |item|}}
                <SidebarItem
                  @label={{item.label}}
                  @badge={{unless bar.collapsed item.badge}}
                  @active={{item.active}}
                  @collapsed={{bar.collapsed}}
                  @onClick={{fn this.setTab item.key}}
                >
                  <:icon><item.icon aria-hidden='true' /></:icon>
                </SidebarItem>
              {{/each}}
            </SidebarGroup>
          </:nav>
          <:default>
            <main class='main'>
              <header class='head'>
                <p class='cap'>{{this.eyebrow}}</p>
                <h1>{{this.pageTitle}}</h1>
                <p class='meta' role='status'>{{this.pageSub}}</p>
              </header>

              <section
                class='strip n{{this.stats.length}}'
                aria-label='Key numbers'
              >
                {{#each this.stats as |s|}}
                  <div class='stat'>
                    <span class='st'><span class='dot {{s.tone}}' aria-hidden='true'></span><span
                        class='cap'
                      >{{s.label}}</span></span>
                    <span class='num'>{{s.value}}</span>
                    <span class='meta'>{{s.hint}}</span>
                  </div>
                {{/each}}
              </section>

              <LayoutControl @label='{{this.tab.label}} toolbar' as |lc|>
                <lc.Slot
                  @id='search'
                  @priority={{2}}
                  @forms={{this.SEARCH_FORMS}}
                  @label='Search'
                >
                  <label class='search'>
                    <VisuallyHidden>Search {{this.noun}}</VisuallyHidden>
                    <SearchInput
                      @placeholder='Search {{this.noun}}'
                      @value={{this.searchText}}
                      @onInput={{this.setSearch}}
                    />
                  </label>
                </lc.Slot>
                {{#if this.filterOptions.length}}
                  <lc.Slot
                    @id='filter'
                    @priority={{1}}
                    @forms={{this.FILTER_FORMS}}
                    @label='Filter'
                    @menuItems={{this.filterMenuItems}}
                  >
                    <SegmentedControl
                      @label='Filter'
                      @options={{this.filterOptions}}
                      @value={{this.filter}}
                      @onValueChange={{this.setFilter}}
                    />
                  </lc.Slot>
                {{/if}}
                <span class='grow'></span>
                {{#if this.canAddProfile}}
                  <lc.Slot
                    @id='add'
                    @priority={{0}}
                    @pinned={{true}}
                    @forms={{this.PRIMARY_FORMS}}
                    @label='Add profile'
                  >
                    <Button
                      @icon={{PlusIcon}}
                      {{on 'click' this.addProfile}}
                    >Add profile</Button>
                  </lc.Slot>
                {{/if}}
              </LayoutControl>

              {{#if (eq this.activeTab 'board')}}
                <section class='block' aria-labelledby='h-pipe'>
                  <div class='sh'>
                    <h2 id='h-pipe'>Vetting pipeline</h2>
                    <span class='meta hint'>Open a profile to move it.
                      Onboarding happens from the profile.</span>
                    <span class='mono end-auto'>{{this.profiles.length}}
                      profiles</span>
                  </div>
                  <div
                    class='board'
                    role='group'
                    aria-label='Vendor vetting pipeline'
                  >
                    {{#each this.lanes key='key' as |lane|}}
                      <section class='lane' aria-labelledby='lane-{{lane.key}}'>
                        <header class='lh'>
                          <h3 id='lane-{{lane.key}}' class='st'><span
                              class='dot {{lane.tone}}'
                              aria-hidden='true'
                            ></span><span class='cap'>{{lane.label}}</span></h3>
                          <span class='mono'>{{lane.cards.length}}</span>
                          <p class='meta lane-hint'>{{lane.hint}}</p>
                        </header>
                        <ul class='ul'>
                          {{#each lane.cards as |c|}}
                            <li class='bi'>
                              <Button
                                @appearance='link'
                                class='who'
                                {{on 'click' (fn this.openCard c.card)}}
                              ><Avatar @name={{c.name}} @size={{20}} /><span
                                  class='nm'
                                >{{c.name}}</span></Button>
                              <span class='meta'>{{if c.meta c.meta '—'}}</span>
                              <StatusChip
                                @value={{c.compliance.text}}
                                @tone={{chipTone c.compliance.tone}}
                                @appearance='plain'
                                @dot={{true}}
                              />
                              <span class='meta'>{{c.fact}}</span>
                            </li>
                          {{else}}
                            <li class='bi meta'>—</li>
                          {{/each}}
                        </ul>
                        {{#if (eq lane.key 'intake')}}
                          <div class='lane-add'>
                            <Button
                              @appearance='plain'
                              @icon={{PlusIcon}}
                              {{on 'click' this.addProfile}}
                            >Add profile</Button>
                          </div>
                        {{/if}}
                      </section>
                    {{/each}}
                  </div>
                </section>
              {{/if}}

              {{#each this.sections key='id' as |sec|}}
                <section class='block' aria-labelledby='h-{{sec.id}}'>
                  <div class='sh'>
                    <h2 id='h-{{sec.id}}'>{{sec.title}}</h2>
                    <span class='meta hint'>{{sec.hint}}</span>
                    <span class='mono end-auto'>{{sec.rows.length}}
                      {{this.noun}}</span>
                  </div>
                  {{#if sec.rows.length}}
                    <div class='tw'>
                      <Table @labelledBy='h-{{sec.id}}' @framed={{false}}>
                        <:head>
                          <tr>
                            {{#each sec.columns as |c|}}
                              <th
                                scope='col'
                                class={{if c.end 'end'}}
                              >{{c.label}}</th>
                            {{/each}}
                          </tr>
                        </:head>
                        <:body>
                          {{#each sec.rows key='id' as |row|}}
                            <tr>
                              {{#each row.cells as |cell i|}}
                                {{#if (eq i 0)}}
                                  <th scope='row' class='rh'>
                                    <Button
                                      @appearance='link'
                                      class='who'
                                      {{on 'click' (fn this.openCard row.card)}}
                                    ><Avatar
                                        @name={{cell.text}}
                                        @size={{16}}
                                      /><span
                                        class='nm'
                                      >{{cell.text}}</span></Button>
                                  </th>
                                {{else if (eq cell.kind 'status')}}
                                  <td><span class='st strong'><span
                                        class='dot {{cell.tone}}'
                                      ></span>{{cell.text}}</span></td>
                                {{else}}
                                  <td class={{cell.kind}}>{{cell.text}}</td>
                                {{/if}}
                              {{/each}}
                            </tr>
                          {{/each}}
                        </:body>
                      </Table>
                    </div>
                  {{else}}
                    <div class='es'>
                      <EmptyState
                        @size='s'
                        @title={{if this.isLoading 'Loading…' sec.empty}}
                      />
                    </div>
                  {{/if}}
                </section>
              {{/each}}
            </main>
          </:default>
        </Sidebar>
      {{else}}
        <EmptyState
          @size='s'
          @title='Vendor Onboarding'
          @message='Vendor profiles move intake → under review → approved → onboarded here. Open the app to work the pipeline.'
        />
      {{/if}}
    </div>
    <style scoped>
      .app {
        container-type: inline-size;
        display: flex;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.35;
        --control-height: 1.625rem;
        /* shortcut: Pret UI parts ignore --control-height until CS-14733 merges, then drop the two lines below. */
        --pretui-button-h: 1.625rem;
        --pretui-seg-h: 1.625rem;
      }
      .shell {
        flex: 1;
        block-size: 100%;
        min-block-size: 0;
      }
      .main {
        box-sizing: border-box;
        min-inline-size: 0;
        padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .cap,
      th {
        margin: 0;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-xs);
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .head {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      h1 {
        font-family: var(--boxel-heading-font-family, var(--font-sans));
        font-weight: 400;
        font-size: var(--boxel-font-size-2xl);
        line-height: 1;
        text-transform: uppercase;
      }
      h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
      }
      .grow {
        flex: 1;
      }
      .strong {
        font-weight: 600;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
      }
      .brand-mark {
        display: inline-grid;
        place-items: center;
        inline-size: 1.5rem;
        block-size: 1.5rem;
        border-radius: var(--radius);
        background: var(--primary);
        color: var(--primary-foreground);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .brand-name {
        display: grid;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .brand-name small {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }

      /* status: dot + text */
      .st {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
        white-space: nowrap;
      }
      .dot {
        flex: none;
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
      }
      .dot.ok {
        background: var(--success);
      }
      .dot.warn {
        background: var(--warning);
      }
      .dot.bad {
        background: var(--destructive);
      }
      .dot.info {
        background: var(--info);
      }

      /* blocks: radius only on the outer card, flat inside */
      .block,
      .strip {
        background: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .sh {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .end-auto {
        margin-inline-start: auto;
        white-space: nowrap;
      }
      @container (max-width: 40rem) {
        .hint {
          display: none;
        }
      }

      /* stat strip: joined tiles, every tile draws its own dividers */
      .strip {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
      }
      .strip.n5 {
        grid-template-columns: repeat(5, minmax(0, 1fr));
      }
      @container (max-width: 60rem) {
        .strip.n5 {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
      }
      @container (max-width: 40rem) {
        .strip,
        .strip.n5 {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .stat {
        display: grid;
        gap: var(--boxel-sp-5xs);
        min-inline-size: 0;
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        box-shadow:
          1px 0 0 var(--border),
          0 1px 0 var(--border);
      }
      .num {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }

      /* board: five lanes, flat, full-height dividers */
      .board {
        display: grid;
        grid-template-columns: repeat(5, minmax(11rem, 1fr));
        overflow-x: auto;
      }
      .lane {
        min-inline-size: 0;
      }
      .lane + .lane {
        border-inline-start: 1px solid var(--border);
      }
      .lh {
        display: grid;
        grid-template-columns: 1fr auto;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .lane-hint {
        grid-column: 1 / -1;
      }
      .ul {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .bi {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border-block-end: 1px solid var(--border);
      }
      .lane-add {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xxs);
      }
      /* Pret UI link Button holding the Avatar and name */
      .who {
        --pretui-button-h: auto;
        --pretui-button-px: 0;
        --pretui-button-gap: var(--boxel-sp-xxs);
        min-inline-size: 0;
        max-inline-size: 100%;
      }
      .nm {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-weight: 600;
      }

      /* tables: 28px rows, mono caps head, hairlines */
      .tw {
        overflow-x: auto;
        padding-inline: var(--boxel-sp-xs);
        --pretui-table-head-height: 1.5rem;
        --inset: var(--card);
        --stripe: transparent;
      }
      th,
      td {
        padding-block: 0;
        text-align: start;
        white-space: nowrap;
        vertical-align: middle;
      }
      td,
      th.rh {
        block-size: 1.75rem;
      }
      th.rh {
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0;
        text-transform: none;
        color: var(--foreground);
      }
      td.mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
      }
      td.meta {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .end,
      td.end {
        text-align: end;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
      }
      th.end {
        font-size: var(--boxel-font-size-xs);
      }
      .es {
        padding: var(--boxel-sp-xs);
      }
      .search {
        display: block;
        min-inline-size: 14rem;
      }
    </style>
  </template>
}
