import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import enumField from '@cardstack/base/enum';
import { realmURL } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';

import { LineItem } from '../commerce/line-item';
import { Vendor } from './vendor';
import { VendorQuote } from './vendor-quote';
import { PurchaseRequisition } from './purchase-requisition';
import { on } from '@ember/modifier';
import { concat } from '@ember/helper';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import {
  CompactFitted,
  CompactRow,
  type CompactTag,
} from '../commerce/compact-parts';
import { lineTotal, sumLineItems } from '../commerce/line-item-totals';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import AwardRfqCommand from './commands/award-rfq-command';
import SendRfqCommand from './commands/send-rfq-command';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

export const RFQ_STATUSES = [
  'draft',
  'sent',
  'comparing',
  'awarded',
  'cancelled',
];

export const RFQ_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  sent: 'Sent',
  comparing: 'Comparing',
  awarded: 'Awarded',
  cancelled: 'Cancelled',
};

export const RFQ_STATUS_COLORS: Record<string, StateColor> = {
  draft: stateColor('slate'),
  sent: stateColor('blue'),
  comparing: stateColor('amber'),
  awarded: stateColor('green'),
  cancelled: stateColor('red'),
};

export const RfqStatusField = enumField(StringField, {
  options: RFQ_STATUSES.map((value) => ({
    value,
    label: RFQ_STATUS_LABELS[value],
  })),
  displayName: 'RFQ Status',
});

type Tone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';
const STATUS_TONES: Record<string, Tone> = {
  draft: 'neutral',
  sent: 'info',
  comparing: 'warning',
  awarded: 'success',
  cancelled: 'danger',
};

// DateField holds local midnight; compact-parts' fmtDate reads UTC and shows the day before.
function fmtDate(d?: Date | string | null, year = true): string {
  if (!d) return '';
  let date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
  });
}

function money(n: number | undefined, code = 'USD'): string {
  if (n === undefined || !Number.isFinite(n)) return '—';
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code,
      maximumFractionDigits: 0,
    }).format(n);
  } catch {
    return `${n}`;
  }
}

function safe<T>(read: () => T, fallback: T): T {
  try {
    return read() ?? fallback;
  } catch {
    return fallback;
  }
}

interface QuoteRow {
  quote: VendorQuote;
  vendor: string;
  total: number;
  lead?: number;
  meta: string;
  tag?: { label: string; tone: Tone };
}

// Every format reads the same facts, so isolated, embedded and fitted agree.
function rfqFacts(m: Rfq | undefined) {
  let status = m?.status || 'draft';
  let lines = safe(() => (m?.lineItems ?? []).filter(Boolean), []);
  let invited = safe(() => (m?.invitedVendors ?? []).filter(Boolean), []);
  let quotes = safe(() => (m?.quotes ?? []).filter(Boolean), []);
  let est = sumLineItems(lines as any);
  let code = est.code ?? 'USD';
  let rows: QuoteRow[] = quotes.map((q) => {
    let total = Number(safe(() => q.totalAmount, 0)) || 0;
    let lead = safe(() => q.leadTimeDays, undefined as number | undefined);
    let vendor = safe(
      () => q.vendor?.name || q.vendor?.cardTitle || q.cardTitle,
      'Vendor',
    );
    let meta = [
      money(total, code),
      lead !== undefined ? `${lead}-day lead` : '',
      q.validUntil ? `valid to ${fmtDate(q.validUntil)}` : '',
      q.notes ? q.notes.replace(/\.$/, '').toLowerCase() : '',
    ]
      .filter(Boolean)
      .join(' · ');
    return { quote: q, vendor, total, lead, meta };
  });
  let priced = rows.filter((r) => r.total > 0);
  let low = priced.reduce<QuoteRow | undefined>(
    (a, r) => (!a || r.total < a.total ? r : a),
    undefined,
  );
  let high = priced.reduce<QuoteRow | undefined>(
    (a, r) => (!a || r.total > a.total ? r : a),
    undefined,
  );
  let fast = rows
    .filter((r) => r.lead !== undefined)
    .reduce<
      QuoteRow | undefined
    >((a, r) => (!a || r.lead! < a.lead! ? r : a), undefined);
  if (low) low.tag = { label: 'lowest', tone: 'success' };
  if (fast && fast !== low) fast.tag = { label: 'fastest', tone: 'info' };
  let awardedId = safe(
    () => m?.awardedQuote?.id,
    undefined as string | undefined,
  );
  let awarded = rows.find((r) => r.quote.id === awardedId);
  if (awarded) awarded.tag = { label: 'awarded', tone: 'success' };
  let spread = low && high ? high.total - low.total : undefined;
  let quotesIn = `${rows.length} / ${invited.length || rows.length}`;
  let deadline = fmtDate(m?.responseDeadline);
  return {
    status,
    statusLabel: RFQ_STATUS_LABELS[status]?.toLowerCase() ?? status,
    tone: STATUS_TONES[status] ?? 'neutral',
    title: m?.cardTitle || 'Untitled RFQ',
    sub: `${invited.length} vendors invited · ${lines.length} lines`,
    subShort: `${invited.length} vendors · ${lines.length} lines`,
    lines: lines.map((l: any) => ({
      description: l?.description || '—',
      meta: `${l?.quantity ?? 0} × ${money(l?.unitPrice?.amount, code)} estimate`,
      total: money(lineTotal(l), code),
    })),
    rows,
    low,
    high,
    fast,
    awarded,
    quotesIn,
    quotesOf: `${rows.length} of ${invited.length || rows.length}`,
    lowest: low ? money(low.total, code) : '—',
    lowestFact: low
      ? `Lowest ${money(low.total, code)} · ${low.vendor}`
      : 'No quotes yet',
    highest: high ? money(high.total, code) : '—',
    fastest: fast ? `${fast.lead} days` : '—',
    estimate: money(est.total, code),
    spread: spread !== undefined ? money(spread, code) : '—',
    spreadPct:
      spread !== undefined && low?.total
        ? `${((spread / low.total) * 100).toFixed(1)}% between quotes`
        : 'needs two quotes',
    deadline: deadline || '—',
    deadlineShort: fmtDate(m?.responseDeadline, false) || '—',
    deadlineYear: m?.responseDeadline
      ? `${new Date(m.responseDeadline as any).getFullYear()}`
      : 'no deadline',
    lineCount: `${lines.length}`,
    awardedText: awarded ? awarded.vendor : 'not yet',
  };
}

class RfqIsolated extends Component<typeof Rfq> {
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked message: string | undefined;

  get f() {
    return rfqFacts(this.args.model as Rfq);
  }
  get isDraft() {
    return this.f.status === 'draft';
  }
  get canAward() {
    return this.f.status === 'comparing' || this.f.status === 'sent'
      ? Boolean(this.f.low)
      : false;
  }

  run = async (make: (ctx: any) => Promise<unknown>) => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    this.error = undefined;
    this.message = undefined;
    this.busy = true;
    try {
      let result = await make(ctx);
      this.message = (result as any)?.message;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  send = () =>
    this.run((ctx) =>
      new SendRfqCommand(ctx).execute({ rfq: this.args.model } as any),
    );

  // Awards the lowest quote, the one the comparison marks.
  award = () => {
    let model = this.args.model as any;
    let realm = model?.[realmURL]?.href;
    if (!realm) {
      this.error = 'Could not determine the realm for the new PO';
      return;
    }
    return this.run((ctx) =>
      new AwardRfqCommand(ctx).execute({
        rfq: model,
        quote: this.f.low?.quote,
        realm,
      } as any),
    );
  };

  <template>
    <div class='ip'>
      <article class='card'>
        <header class='ih'>
          <Avatar @name='R Q' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{this.f.title}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>
            <Chip
              @label={{this.f.statusLabel}}
              @tone={{this.f.tone}}
              @appearance='plain'
            />
            <Chip
              @label={{concat this.f.quotesIn ' quotes'}}
              @tone='info'
              @appearance='plain'
            />
          </span>
          {{#if this.isDraft}}
            <Button
              @appearance='accent'
              @size='s'
              @disabled={{this.busy}}
              {{on 'click' this.send}}
            >Send RFQ</Button>
          {{else if this.canAward}}
            <Button
              @appearance='accent'
              @size='s'
              @disabled={{this.busy}}
              {{on 'click' this.award}}
            >Award quote</Button>
          {{/if}}
        </header>
        {{#if this.error}}
          <Alert class='flash' @tone='danger' style={{ALERT_STYLE.danger}}>
            {{this.error}}
          </Alert>
        {{/if}}
        {{#if this.message}}
          <Alert class='flash' @tone='success' style={{ALERT_STYLE.success}}>
            {{this.message}}
          </Alert>
        {{/if}}
        <div class='stats'>
          <Stat
            @label='Quotes in'
            @tone='success'
            @value={{this.f.quotesIn}}
            @roll={{false}}
            @hint='of invited vendors'
          />
          <Stat
            @label='Lowest quote'
            @tone='success'
            @value={{this.f.lowest}}
            @roll={{false}}
            @hint={{if
              this.f.low
              (concat this.f.low.vendor ' · ' this.f.low.lead '-day lead')
            }}
          />
          <Stat
            @label='Deadline'
            @value={{this.f.deadlineShort}}
            @roll={{false}}
            @hint={{this.f.deadlineYear}}
          />
          <Stat
            @label='Spread'
            @value={{this.f.spread}}
            @roll={{false}}
            @hint={{this.f.spreadPct}}
          />
        </div>
      </article>

      <div class='cols'>
        <div class='col'>
          <section class='card'>
            <h2>Quote comparison</h2>
            <ul class='ul'>
              {{#each this.f.rows as |r|}}
                <li class='li'>
                  <span class='two'>
                    <strong>{{r.vendor}}</strong>
                    <span class='meta'>{{r.meta}}</span>
                  </span>
                  {{#if r.tag}}
                    <Chip
                      @label={{r.tag.label}}
                      @tone={{r.tag.tone}}
                      @appearance='plain'
                    />
                  {{/if}}
                </li>
              {{else}}
                <li class='li meta'>No quotes received yet</li>
              {{/each}}
            </ul>
          </section>
          <section class='card'>
            <h2>Line items</h2>
            <ul class='ul'>
              {{#each this.f.lines as |l|}}
                <li class='li'>
                  <span class='two'>
                    <strong>{{l.description}}</strong>
                    <span class='meta'>{{l.meta}}</span>
                  </span>
                  <span class='mono'>{{l.total}}</span>
                </li>
              {{else}}
                <li class='li meta'>No lines yet — copy them from the
                  requisition.</li>
              {{/each}}
            </ul>
          </section>
        </div>
        <div class='col'>
          <section class='card'>
            <h2>Linked</h2>
            <dl class='kv'>
              {{#if @model.requisition}}
                <dt>Requisition</dt>
                <dd><@fields.requisition
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd>
              {{/if}}
              {{#each @fields.invitedVendors as |V|}}
                <dt>Vendor</dt>
                <dd><V @format='atom' @displayContainer={{false}} /></dd>
              {{/each}}
              {{#if @model.awardedQuote}}
                <dt>Awarded</dt>
                <dd><@fields.awardedQuote
                    @format='atom'
                    @displayContainer={{false}}
                  /></dd>
              {{/if}}
            </dl>
          </section>
          <section class='card'>
            <h2>Details</h2>
            <dl class='kv'>
              <dt>Deadline</dt><dd class='mono'>{{this.f.deadline}}</dd>
              <dt>Quotes in</dt><dd class='mono'>{{this.f.quotesOf}}</dd>
              <dt>Lowest</dt><dd class='mono'>{{this.f.lowest}}</dd>
              <dt>Highest</dt><dd class='mono'>{{this.f.highest}}</dd>
              <dt>Fastest lead</dt><dd class='mono'>{{this.f.fastest}}</dd>
              <dt>Estimate</dt><dd class='mono'>{{this.f.estimate}}</dd>
              <dt>Lines</dt><dd class='mono'>{{this.f.lineCount}}</dd>
              <dt>Awarded</dt><dd>{{this.f.awardedText}}</dd>
            </dl>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .ip {
        container-type: inline-size;
        box-sizing: border-box;
        block-size: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp-sm);
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-xs);
        background: var(--background);
        color: var(--card-foreground);
        font-family: var(--font-sans);
        font-size: 0.75rem;
        line-height: 1.25;
        --text-stat: 1.375rem;
        --text-ui-xs: 0.6875rem;
      }
      .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        min-inline-size: 0;
      }
      .ih {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.625rem;
        padding: 0.5rem 0.625rem;
      }
      .id {
        flex: 1 1 10rem;
        min-inline-size: 0;
      }
      h1 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        font-weight: 700;
      }
      .meta {
        margin: 0;
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .tags {
        display: flex;
        flex-wrap: wrap;
        gap: 0.625rem;
      }
      .flash {
        margin: 0 0.625rem 0.5rem;
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        border-block-start: 1px solid var(--border);
      }
      .stats > * {
        padding: 0.4375rem 0.625rem;
        min-inline-size: 0;
      }
      .stats > :not(:first-child) {
        border-inline-start: 1px solid var(--border);
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
        .stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .stats > :nth-child(3) {
          border-inline-start: 0;
        }
        .stats > :nth-child(n + 3) {
          border-block-start: 1px solid var(--border);
        }
      }
      h2 {
        margin: 0;
        padding: 0.4375rem 0.625rem;
        font-size: 0.75rem;
        font-weight: 700;
      }
      .ul {
        list-style: none;
        margin: 0;
        padding: 0 0 0.25rem;
      }
      .li {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        min-block-size: 1.75rem;
        padding: 0.3125rem 0.625rem;
        border-block-start: 1px solid var(--border);
      }
      .two {
        flex: 1;
        min-inline-size: 0;
        display: flex;
        flex-direction: column;
      }
      .two strong {
        font-weight: 600;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-variant-numeric: tabular-nums;
      }
      .kv {
        display: grid;
        grid-template-columns: 6.5rem minmax(0, 1fr);
        margin: 0;
        padding: 0 0.625rem 0.25rem;
      }
      .kv dt,
      .kv dd {
        margin: 0;
        min-block-size: 1.75rem;
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        min-inline-size: 0;
        border-block-start: 1px solid var(--border);
      }
      .kv dt {
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// A formal ask for competitive prices: which lines, sent to which vendors,
// with the buyer recording each inbound quote. Award converts the lowest
// quote into a draft Purchase Order via AwardRfqCommand.
export class Rfq extends CardDef {
  static displayName = 'RFQ';
  static prefersWideFormat = true;

  @field requisition = linksTo(() => PurchaseRequisition);
  @field lineItems = containsMany(LineItem);
  @field invitedVendors = linksToMany(() => Vendor);
  @field quotes = linksToMany(() => VendorQuote);
  @field status = contains(RfqStatusField);
  @field responseDeadline = contains(DateField);
  @field awardedQuote = linksTo(() => VendorQuote);

  static isolated = RfqIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return rfqFacts(this.args.model as Rfq);
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <div class='eh1'>
            <Avatar @name='R Q' @shape='square' @size={{20}} />
            <strong class='nm'>{{this.f.title}}</strong>
            <Chip
              @label={{this.f.statusLabel}}
              @tone={{this.f.tone}}
              @appearance='plain'
            />
          </div>
          <div class='eh2'>
            <span class='meta'>{{this.f.sub}}</span>
            <Chip
              @label={{concat this.f.quotesIn ' quotes'}}
              @tone='info'
              @appearance='plain'
            />
          </div>
        </header>
        <p class='fact'>{{#if this.f.low}}Lowest
            <strong>{{this.f.lowest}}</strong>
            {{this.f.low.vendor}}
            · due
            {{this.f.deadlineShort}}{{else}}No quotes yet · due
            {{this.f.deadlineShort}}{{/if}}</p>
        <dl class='kv'>
          <dt>Deadline</dt><dd class='mono'>{{this.f.deadline}}</dd>
          <dt>Quotes in</dt><dd class='mono'>{{this.f.quotesOf}}</dd>
          <dt>Lowest</dt><dd class='mono'>{{this.f.lowest}}</dd>
          <dt>Highest</dt><dd class='mono'>{{this.f.highest}}</dd>
          <dt>Fastest lead</dt><dd class='mono'>{{this.f.fastest}}</dd>
          <dt>Estimate</dt><dd class='mono'>{{this.f.estimate}}</dd>
          {{#if @model.requisition}}
            <dt>Requisition</dt>
            <dd><@fields.requisition
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
          {{#each @fields.quotes as |Q|}}
            <dt>Quote</dt>
            <dd><Q @format='atom' @displayContainer={{false}} /></dd>
          {{/each}}
          {{#each @fields.invitedVendors as |V|}}
            <dt>Vendor</dt>
            <dd><V @format='atom' @displayContainer={{false}} /></dd>
          {{/each}}
        </dl>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
          overflow-x: auto;
        }
        .eh {
          padding: 0.4375rem 0.625rem;
          display: grid;
          gap: 0.125rem;
        }
        .eh1,
        .eh2 {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.375rem 0.5rem;
        }
        .nm {
          flex: 1 1 6rem;
          min-inline-size: 0;
          font-weight: 700;
        }
        .meta {
          flex: 1 1 6rem;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-block-start: 1px solid var(--border);
        }
        .fact strong {
          font-weight: 700;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
        }
        .kv {
          display: grid;
          grid-template-columns: 6.5rem minmax(0, 1fr);
          margin: 0;
          padding: 0 0.625rem 0.25rem;
        }
        .kv dt,
        .kv dd {
          margin: 0;
          min-block-size: 1.75rem;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          min-inline-size: 0;
          border-block-start: 1px solid var(--border);
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get f() {
      return rfqFacts(this.args.model as Rfq);
    }
    <template>
      <span class='atom' title={{this.f.statusLabel}}>
        <Avatar @name='R Q' @shape='square' @size={{16}} />
        <span class='name'>{{this.f.title}}</span>
        <Chip @label='' @tone={{this.f.tone}} @appearance='plain' />
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: 0.6875rem;
          font-weight: 600;
        }
        .name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return rfqFacts(this.args.model as Rfq);
    }
    get tags(): CompactTag[] {
      return [{ label: this.f.statusLabel, tone: this.f.tone }];
    }
    <template>
      <CompactFitted
        @mark='R Q'
        @title={{this.f.title}}
        @sub={{this.f.sub}}
        @fact={{this.f.lowestFact}}
        @tags={{this.tags}}
      >
        <:rows>
          <CompactRow @k='Deadline' @v={{this.f.deadline}} />
          <CompactRow @k='Quotes in' @v={{this.f.quotesOf}} />
          <CompactRow @k='Highest' @v={{this.f.highest}} />
          <CompactRow @k='Fastest lead' @v={{this.f.fastest}} />
          <CompactRow @k='Lines' @v={{this.f.lineCount}} />
          <CompactRow @k='Awarded' @v={{this.f.awardedText}} />
          {{#each this.f.lines as |l|}}
            <CompactRow @k={{l.description}} @v={{l.total}} />
          {{/each}}
        </:rows>
      </CompactFitted>
    </template>
  };
}
