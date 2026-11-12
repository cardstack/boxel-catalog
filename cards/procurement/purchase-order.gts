import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { concat, fn, get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';

import { LineItem } from '../commerce/line-item';
import { Vendor } from './vendor';
import { Rfq } from './rfq';
import { ProcurementBudget } from './procurement-budget';
import { PONumberField } from './po-number-field';
import { ApprovalChainField } from '../hr/approval-chain-field';
import { sumLineItems } from '../commerce/line-item-totals';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import ApprovePurchaseOrderCommand from './commands/approve-purchase-order-command';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

export const PO_STATUSES = [
  'draft',
  'pending-approval',
  'approved',
  'sent',
  'partially-received',
  'received',
  'closed',
  'rejected',
];

export const PO_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  'pending-approval': 'Pending Approval',
  approved: 'Approved',
  sent: 'Sent',
  'partially-received': 'Partially Received',
  received: 'Received',
  closed: 'Closed',
  rejected: 'Rejected',
};

export const PO_STATUS_COLORS: Record<string, StateColor> = {
  draft: stateColor('slate'),
  'pending-approval': stateColor('amber'),
  approved: stateColor('blue'),
  sent: stateColor('blue'),
  'partially-received': stateColor('amber'),
  received: stateColor('green'),
  closed: stateColor('slate'),
  rejected: stateColor('red'),
};

export const PO_STATUS_HUES: Record<
  string,
  'slate' | 'amber' | 'blue' | 'green' | 'red'
> = {
  draft: 'slate',
  'pending-approval': 'amber',
  approved: 'blue',
  sent: 'blue',
  'partially-received': 'amber',
  received: 'green',
  closed: 'slate',
  rejected: 'red',
};

export const POStatusField = markDefinition(
  enumField(StringField, {
    options: PO_STATUSES.map((value) => ({
      value,
      label: PO_STATUS_LABELS[value],
    })),
    displayName: 'PO Status',
  }),
);

// Threshold routing — the single most recognizable "real procurement"
// feature. The route is computed from the PO total at issue time and stored
// on the card (`approvalRoute`) so the applied policy stays auditable even
// if thresholds change later. Step ROLE labels are positional per route:
// the shared ApprovalStepField deliberately has no role field, so the roles
// live here in the module that owns the routing policy.
export const PO_APPROVAL_THRESHOLDS = {
  auto: 1_000, // below this: auto-approved
  manager: 10_000, // below this: one Manager step; at/above: Finance → VP
};

export type PoApprovalRoute = 'auto' | 'manager' | 'finance-vp';

export function poApprovalRouteFor(total: number): PoApprovalRoute {
  if (total < PO_APPROVAL_THRESHOLDS.auto) {
    return 'auto';
  }
  if (total < PO_APPROVAL_THRESHOLDS.manager) {
    return 'manager';
  }
  return 'finance-vp';
}

export const PO_ROUTE_STEP_ROLES: Record<PoApprovalRoute, string[]> = {
  auto: [],
  manager: ['Manager'],
  'finance-vp': ['Finance', 'VP'],
};

export const PO_ROUTE_LABELS: Record<PoApprovalRoute, string> = {
  auto: 'Auto (under $1k)',
  manager: 'Manager ($1k–$10k)',
  'finance-vp': 'Finance → VP ($10k+)',
};

type PoTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';
const PO_TONES: Record<string, PoTone> = {
  draft: 'neutral',
  'pending-approval': 'warning',
  approved: 'info',
  sent: 'info',
  'partially-received': 'warning',
  received: 'success',
  closed: 'neutral',
  rejected: 'danger',
};
const STEP_TONES: Record<string, PoTone> = {
  approved: 'success',
  pending: 'warning',
  rejected: 'danger',
};

function poDate(d?: Date | string | null, opts?: Intl.DateTimeFormatOptions) {
  if (!d) return '';
  let date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString(
    'en-US',
    opts ?? { month: 'short', day: 'numeric', year: 'numeric' },
  );
}

function poMoney(n: number, code = 'USD') {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: code,
    maximumFractionDigits: 0,
  }).format(n);
}

// One read of the PO for every format, so the four views never disagree.
export function poFacts(m?: PurchaseOrder | null) {
  let lines = (m?.lineItems ?? []).filter(Boolean);
  let code = lines[0]?.unitPrice?.currency?.code ?? 'USD';
  let received = m?.receivedQuantities ?? [];
  let units = lines.reduce((s, l) => s + (l.quantity ?? 0), 0);
  let got = received.reduce((s, q) => s + (q ?? 0), 0);
  let route = (m?.approvalRoute ?? '') as PoApprovalRoute;
  let roles = PO_ROUTE_STEP_ROLES[route] ?? [];
  let steps = (m?.approvalChain?.steps ?? []).filter(Boolean);
  let done = steps.filter((s) => s.decision === 'approved').length;
  let cur = steps.findIndex((s) => s.decision === 'pending');
  let next = cur >= 0 ? (roles[cur] ?? `step ${cur + 1}`) : '';
  let status = m?.status ?? 'draft';
  let vendor = m?.vendor?.cardTitle ?? (m?.vendor as any)?.name ?? '';
  let tags: { label: string; tone: PoTone }[] = [
    { label: status, tone: PO_TONES[status] ?? 'neutral' },
  ];
  if (steps.length) {
    tags.push({ label: `approval ${done} / ${steps.length}`, tone: 'info' });
  }
  let lineWord = `${lines.length} line${lines.length === 1 ? '' : 's'}`;
  let exp = m?.expectedDelivery;
  return {
    number: m?.poNumber || 'Draft PO',
    code,
    status,
    tags,
    total: poMoney(m?.totalAmount ?? 0, code),
    sub: [vendor, m?.rfq?.cardTitle?.toLowerCase(), lineWord]
      .filter(Boolean)
      .join(' · '),
    vendorLines: [vendor, lineWord].filter(Boolean).join(' · '),
    lineWord,
    lineCount: `${lines.length}`,
    approval: steps.length ? `${done} / ${steps.length}` : '—',
    approvalText: steps.length ? `${done} of ${steps.length} approved` : '—',
    approvalHint: next
      ? `${next} next`
      : steps.length
        ? 'complete'
        : 'no chain',
    waiting: next ? `step ${cur + 1} of ${steps.length}` : '',
    next,
    routeShort: roles.length ? roles.join(' → ') : route ? 'Auto' : '—',
    routeLong: PO_ROUTE_LABELS[route] ?? '—',
    expected: poDate(exp) || '—',
    expectedShort: poDate(exp, { month: 'short', day: 'numeric' }) || '—',
    expectedYear: poDate(exp, { year: 'numeric' }),
    received: `${got} / ${units}`,
    receivedText: `${got} of ${units}`,
    lines: lines.map((l, i) => ({
      name: l.description || '—',
      meta: `${l.quantity ?? 0} ordered · ${received[i] ?? 0} received · ${poMoney(
        l.unitPrice?.amount ?? 0,
        code,
      )} each`,
      amount: poMoney((l.quantity ?? 0) * (l.unitPrice?.amount ?? 0), code),
    })),
    steps: steps.map((s, i) => {
      let decided = poDate(s.decidedAt);
      let opened = poDate(s.openedAt);
      let when =
        s.decision === 'pending'
          ? opened && `Opened ${opened}`
          : decided &&
            `${s.decision === 'approved' ? 'Approved' : 'Rejected'} ${decided}`;
      return {
        title: `Step ${i + 1}${roles[i] ? ` · ${roles[i]}` : ''}`,
        meta: [when, s.comment].filter(Boolean).join(' · '),
        decision: s.decision ?? 'pending',
        tone: STEP_TONES[s.decision ?? 'pending'] ?? 'neutral',
      };
    }),
  };
}

class PurchaseOrderIsolated extends Component<typeof PurchaseOrder> {
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked message: string | undefined;

  get f() {
    return poFacts(this.args.model as PurchaseOrder);
  }
  get canDecide() {
    let model = this.args.model;
    return (
      model?.status === 'pending-approval' &&
      model?.approvalChain?.status === 'in-progress'
    );
  }
  get delivery() {
    return [
      { key: 'Approval route', value: this.f.routeLong },
      { key: 'Expected delivery', value: this.f.expected, mono: true },
      { key: 'Received', value: `${this.f.receivedText} units`, mono: true },
    ];
  }
  get linked() {
    let m = this.args.model;
    let rows = [];
    if (m?.vendor) rows.push({ key: 'Vendor', value: '' });
    if (m?.budget) rows.push({ key: 'Budget', value: '' });
    if (m?.rfq) rows.push({ key: 'RFQ', value: '' });
    return rows;
  }
  get details() {
    let m = this.args.model;
    return [
      { key: 'Total', value: this.f.total, mono: true },
      { key: 'Expected', value: this.f.expected, mono: true },
      { key: 'Route', value: this.f.routeShort },
      { key: 'Approval', value: this.f.approvalText, mono: true },
      { key: 'Received', value: this.f.receivedText, mono: true },
      { key: 'Lines', value: this.f.lineCount },
      { key: 'Vendor', value: m?.vendor?.cardTitle ?? '—' },
      { key: 'Budget', value: m?.budget?.cardTitle ?? '—' },
    ];
  }

  decide = async (decision: 'approved' | 'rejected') => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    this.error = undefined;
    this.message = undefined;
    this.busy = true;
    try {
      let result = await new ApprovePurchaseOrderCommand(
        commandContext,
      ).execute({
        purchaseOrder: model,
        decision,
      } as any);
      this.message = (result as any)?.message;
    } catch (error: any) {
      this.error = error?.message ?? String(error);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <article class='po'>
      <section class='blk top'>
        <header class='ih'>
          <Avatar @name='Po' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{this.f.number}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>{{#each this.f.tags as |t|}}<Chip
                @label={{t.label}}
                @tone={{t.tone}}
                @appearance='plain'
              />{{/each}}</span>
          {{#if this.canDecide}}
            <span class='acts'>
              <Button
                @appearance='filled'
                @size='s'
                @disabled={{this.busy}}
                {{on 'click' (fn this.decide 'approved')}}
              >Approve</Button>
              <Button
                @appearance='outlined'
                @size='s'
                @disabled={{this.busy}}
                {{on 'click' (fn this.decide 'rejected')}}
              >Reject</Button>
            </span>
          {{/if}}
        </header>
        {{#if this.error}}
          <Alert
            @tone='danger'
            style={{ALERT_STYLE.danger}}
          >{{this.error}}</Alert>
        {{/if}}
        {{#if this.message}}
          <Alert
            @tone='success'
            style={{ALERT_STYLE.success}}
          >{{this.message}}</Alert>
        {{/if}}
        <div class='stats'>
          <Stat
            @label='Total'
            @tone='neutral'
            @value={{this.f.total}}
            @roll={{false}}
            @hint={{this.f.lineWord}}
          />
          <Stat
            @label='Approval'
            @tone='warning'
            @value={{this.f.approval}}
            @roll={{false}}
            @hint={{this.f.approvalHint}}
          />
          <Stat
            @label='Expected'
            @tone='neutral'
            @value={{this.f.expectedShort}}
            @roll={{false}}
            @hint={{this.f.expectedYear}}
          />
          <Stat
            @label='Received'
            @tone='neutral'
            @value={{this.f.received}}
            @roll={{false}}
            @hint='units'
          />
        </div>
      </section>
      <div class='cols'>
        <div class='col'>
          <section class='blk'>
            <h2>Line items</h2>
            {{#each this.f.lines as |l|}}
              <div class='row'>
                <div class='rmain'>
                  <b>{{l.name}}</b>
                  <span class='rmeta'>{{l.meta}}</span>
                </div>
                <span class='num'>{{l.amount}}</span>
              </div>
            {{else}}
              <p class='empty-note'>No line items yet</p>
            {{/each}}
          </section>
          <section class='blk'>
            <h2>Approval chain</h2>
            {{#each this.f.steps as |s|}}
              <div class='row'>
                <div class='rmain'>
                  <b>{{s.title}}</b>
                  <span class='rmeta'>{{s.meta}}</span>
                </div>
                <Chip
                  @label={{s.decision}}
                  @tone={{s.tone}}
                  @appearance='plain'
                />
              </div>
            {{else}}
              <p class='empty-note'>No approval chain — {{this.f.routeLong}}</p>
            {{/each}}
          </section>
        </div>
        <div class='col'>
          <section class='blk'>
            <h2>Delivery</h2>
            <KeyValue
              @items={{this.delivery}}
              @divided={{true}}
              @labelStyle='eyebrow'
              class='kv kv-pad'
            >
              <:value as |row|><span
                  class={{if (get row 'mono') 'mono'}}
                >{{row.value}}</span></:value>
            </KeyValue>
          </section>
          {{#if this.linked.length}}
            <section class='blk'>
              <h2>Linked</h2>
              <KeyValue
                @items={{this.linked}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv kv-pad'
              >
                <:value as |row|>
                  {{#if (eq row.key 'Vendor')}}<@fields.vendor
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq row.key 'Budget')}}<@fields.budget
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else}}<@fields.rfq
                      @format='atom'
                      @displayContainer={{false}}
                    />{{/if}}
                </:value>
              </KeyValue>
            </section>
          {{/if}}
          <section class='blk'>
            <h2>Details</h2>
            <KeyValue
              @items={{this.details}}
              @divided={{true}}
              @labelStyle='eyebrow'
              class='kv kv-pad'
            >
              <:value as |row|><span
                  class={{if (get row 'mono') 'mono'}}
                >{{row.value}}</span></:value>
            </KeyValue>
          </section>
        </div>
      </div>
    </article>
    <style scoped>
      .kv-pad {
        --pretui-kv-pad-inline: var(--boxel-sp-sm);
      }

      .po {
        --pretui-kv-label-font-size: 0.5625rem;
        --pretui-kv-label-color: var(--muted-foreground);
        container-type: inline-size;
        box-sizing: border-box;
        min-block-size: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp-sm);
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-xs);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.25;
        color: var(--card-foreground);
        background: var(--background);
        --text-stat: 1.375rem;

        min-height: 100%;
      }
      .blk {
        min-inline-size: 0;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow-x: auto;
      }
      .ih {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
      }
      .id {
        flex: 1 1 12rem;
        min-inline-size: 0;
      }
      h1 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-sm);
        font-weight: 700;
      }
      .meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .tags,
      .acts {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
      }
      .acts {
        gap: var(--boxel-sp-2xs);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        border-block-start: 1px solid var(--border);
        overflow: hidden;
      }
      .stats > * {
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        border-inline-end: 1px solid var(--border);
        margin-inline-end: -1px;
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        gap: var(--boxel-sp-xs);
        align-items: start;
      }
      .col {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      @container (width < 40rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      h2 {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        border-block-end: 1px solid var(--border);
      }
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-block-size: 1.75rem;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      }
      .row + .row {
        border-block-start: 1px solid var(--border);
      }
      .rmain {
        flex: 1;
        min-inline-size: 0;
        display: grid;
      }
      .rmeta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .num,
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
      }
      .num {
        color: var(--muted-foreground);
      }
      .kv {
        --boxel-sp-xs: 0.375rem;
        --boxel-sp-lg: 0.75rem;
        padding: 0 var(--boxel-sp-xs) var(--boxel-sp-4xs);
        row-gap: 0;
      }
      .empty-note {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// The binding order document. Once the approval chain completes, the PO's
// total is COMMITTED against its budget (commitment accounting) — approving
// and receiving are the only writers of those budget numbers, both via
// commands, never by hand. `poNumber` is stamped once at issue and never
// recomputed.
export class PurchaseOrder extends CardDef {
  static displayName = 'Purchase Order';
  static headerColor = '#3e4e88';

  @field poNumber = contains(PONumberField);
  @field rfq = linksTo(() => Rfq);
  @field vendor = linksTo(() => Vendor);
  @field lineItems = containsMany(LineItem);
  @field status = contains(POStatusField);
  @field approvalRoute = contains(StringField);
  @field approvalChain = contains(ApprovalChainField);
  @field budget = linksTo(() => ProcurementBudget);
  @field expectedDelivery = contains(DateField);
  // Per-line received-so-far, index-aligned with lineItems. Maintained only
  // by ReceiveGoodsCommand (partial receipts accumulate here) — never
  // hand-edited.
  @field receivedQuantities = containsMany(NumberField);

  @field totalAmount = contains(NumberField, {
    computeVia: function (this: PurchaseOrder) {
      return sumLineItems(this.lineItems ?? []).total;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PurchaseOrder) {
      return this.poNumber?.trim()?.length ? this.poNumber : 'Draft PO';
    },
  });

  static isolated = PurchaseOrderIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return poFacts(this.args.model as PurchaseOrder);
    }
    get rows() {
      let f = this.f;
      let m = this.args.model;
      let rows: any[] = [
        { key: 'Total', value: f.total, mono: true },
        { key: 'Expected', value: f.expected, mono: true },
        { key: 'Route', value: f.routeShort },
        { key: 'Approval', value: f.approvalText, mono: true },
        { key: 'Received', value: f.receivedText, mono: true },
        { key: 'Lines', value: f.lineCount },
      ];
      if (m?.vendor) rows.push({ key: 'Vendor', value: '', atom: 'vendor' });
      if (m?.budget) rows.push({ key: 'Budget', value: '', atom: 'budget' });
      return rows;
    }
    <template>
      <article class='pe'>
        <header class='eh'>
          <Avatar @name='Po' @shape='square' @size={{20}} />
          <div class='id'>
            <span class='ln'>
              <b class='nm'>{{this.f.number}}</b>
              {{#each this.f.tags as |t i|}}{{#if (eq i 0)}}<Chip
                    @label={{t.label}}
                    @tone={{t.tone}}
                    @appearance='plain'
                  />{{/if}}{{/each}}
            </span>
            <span class='ln sub'>
              <span class='meta'>{{this.f.sub}}</span>
              {{#each this.f.tags as |t i|}}{{#if (eq i 1)}}<Chip
                    @label={{t.label}}
                    @tone={{t.tone}}
                    @appearance='plain'
                  />{{/if}}{{/each}}
            </span>
          </div>
        </header>
        {{#if this.f.next}}
          <p class='fact'>Waiting on
            <b>{{this.f.next}}</b>
            ·
            {{this.f.waiting}}</p>
        {{/if}}
        <KeyValue
          @items={{this.rows}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv kv-pad'
        >
          <:value as |row|>
            {{#if (eq (get row 'atom') 'vendor')}}<@fields.vendor
                @format='atom'
                @displayContainer={{false}}
              />
            {{else if (eq (get row 'atom') 'budget')}}<@fields.budget
                @format='atom'
                @displayContainer={{false}}
              />
            {{else}}<span
                class={{if (get row 'mono') 'mono'}}
              >{{row.value}}</span>{{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }

        .pe {
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          box-sizing: border-box;
          padding: 0.5rem 0.625rem;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .eh {
          display: flex;
          flex-wrap: wrap;
          align-items: flex-start;
          gap: 0.25rem 0.5rem;
          padding-block-end: 0.375rem;
        }
        .id {
          flex: 1;
          min-inline-size: 0;
          display: grid;
          gap: 0.125rem;
        }
        .ln {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: 0.125rem 0.75rem;
        }
        .ln.sub {
          justify-content: flex-start;
        }
        .nm {
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding-block: 0.375rem;
          border-block-start: 1px solid var(--border);
        }
        .kv {
          --boxel-sp-xs: 0.375rem;
          --boxel-sp-lg: 0.75rem;
          row-gap: 0;
          border-block-start: 1px solid var(--border);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get f() {
      return poFacts(this.args.model as PurchaseOrder);
    }
    get short() {
      return (this.args.model?.status ?? 'draft').split('-')[0];
    }
    get tone() {
      return this.f.tags[0]?.tone;
    }
    <template>
      <span class='pa'>
        <Avatar @name='Po' @shape='square' @size={{16}} />
        <span class='nm'>{{this.f.number}}</span>
        <Chip
          @label={{this.short}}
          @tone={{this.tone}}
          @appearance='plain'
          class='st'
        />
      </span>
      <style scoped>
        .pa {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          max-inline-size: 100%;
          min-inline-size: 0;
          font-size: 0.75rem;
          vertical-align: middle;
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
        .st {
          flex: none;
          flex-direction: row-reverse;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return poFacts(this.args.model as PurchaseOrder);
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar @name='Po' @shape='square' @size={{20}} /></:avatar>
        <:title>{{this.f.number}}</:title>
        <:status>{{#each this.f.tags as |t|}}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{this.f.sub}}</:subtitle>
        <:fact>{{if
            this.f.next
            (concat 'Waiting on ' this.f.next ' · ' this.f.waiting)
            this.f.routeLong
          }}</:fact>
        <:metric><Metric @value={{this.f.total}} /></:metric>
        <:details>
          <Detail @label='Total' @value={{this.f.total}} class='mono' />
          <Detail @label='Expected' @value={{this.f.expected}} class='mono' />
          <Detail @label='Route' @value={{this.f.routeShort}} />
          <Detail
            @label='Approval'
            @value={{this.f.approvalText}}
            class='mono'
          />
          <Detail
            @label='Received'
            @value={{this.f.receivedText}}
            class='mono'
          />
          <Detail @label='Lines' @value={{this.f.lineCount}} />
          <Detail @label='Line items' @value=' ' />
          {{#each this.f.lines as |l|}}
            <Detail @label={{l.name}} @value={{l.amount}} class='mono' />
          {{/each}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
      </style>
    </template>
  };

  // Grouped by how a PO is actually assembled (which order is this → what's
  // on it → who signs off and against what money → when does it arrive and
  // what's been received), not schema order. Four sections, so this form
  // gets the EditSectionNav rail. totalAmount and title
  // are computed (computeVia) and deliberately excluded.
}
