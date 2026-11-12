import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { Chip } from '@cardstack/pretui/components/chip';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import {
  ALERT_STYLE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  CompactFitted,
  CompactRow,
  type CompactTag,
} from '../commerce/compact-parts';

// DateField hands back local midnight, so format in local time (a UTC
// formatter shows the previous day west of Greenwich).
function fmtDate(d?: Date | null, year = true): string {
  return d
    ? d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: year ? 'numeric' : undefined,
      })
    : '';
}

import { PurchaseOrder } from './purchase-order';
import ReceiveGoodsCommand from './commands/receive-goods-command';

export type MatchState = 'matched' | 'short' | 'over';
type Tone = CompactTag['tone'];

export function matchStateOf(
  ordered?: number | null,
  received?: number | null,
): MatchState {
  let o = ordered ?? 0;
  let r = received ?? 0;
  if (r < o) {
    return 'short';
  }
  if (r > o) {
    return 'over';
  }
  return 'matched';
}

const LINE_TONE: Record<string, Tone> = {
  matched: 'success',
  short: 'warning',
  over: 'danger',
};
const MATCH: Record<string, { label: string; tone: Tone; hint: string }> = {
  matched: {
    label: 'Matched',
    tone: 'success',
    hint: 'no short or over lines',
  },
  partial: { label: 'Partial', tone: 'warning', hint: 'short lines' },
  over: { label: 'Over', tone: 'danger', hint: 'over-receipt, check notes' },
  empty: { label: 'No lines', tone: 'neutral', hint: 'nothing recorded' },
};

// One received line, checked against the PO's ordered quantity. qtyOrdered
// is a SNAPSHOT taken when the receipt is recorded — the receipt is an audit
// document and must keep saying what was ordered at the time, even if the PO
// is later edited.
export class ReceiptLineField extends FieldDef {
  static displayName = 'Receipt Line';

  @field description = contains(StringField);
  @field qtyOrdered = contains(NumberField);
  @field qtyReceived = contains(NumberField);
  @field note = contains(StringField);

  @field matchState = contains(StringField, {
    computeVia: function (this: ReceiptLineField) {
      return matchStateOf(this.qtyOrdered, this.qtyReceived);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get tone() {
      return LINE_TONE[this.args.model?.matchState ?? 'matched'];
    }
    <template>
      <div class='line'>
        <span class='two'>
          <strong>{{if @model.description @model.description '—'}}</strong>
          <span class='meta'>{{@model.qtyOrdered}}
            ordered ·
            {{@model.qtyReceived}}
            received{{#if @model.note}} · {{@model.note}}{{/if}}</span>
        </span>
        <Chip
          @label={{@model.matchState}}
          @tone={{this.tone}}
          @appearance='plain'
        />
      </div>
      <style scoped>
        .line {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
          min-block-size: 1.75rem;
          padding: 0.4375rem 0.625rem;
          font-size: 0.75rem;
          line-height: 1.25;
        }
        .two {
          display: flex;
          flex-direction: column;
          min-inline-size: 0;
        }
        .two strong {
          font-weight: 600;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

function grFacts(m?: GoodsReceipt) {
  let lines = (m?.lines ?? []).filter(Boolean);
  let ordered = lines.reduce((s, l) => s + (l.qtyOrdered ?? 0), 0);
  let received = lines.reduce((s, l) => s + (l.qtyReceived ?? 0), 0);
  let po = m?.purchaseOrder?.poNumber ?? '';
  let by = m?.receivedBy ?? '';
  let day = fmtDate(m?.receivedOn, false);
  let match = MATCH[m?.matchResult ?? 'empty'] ?? MATCH.empty;
  let posted = m?.posted ? 'posted' : 'draft';
  let tags: CompactTag[] = [
    { label: posted, tone: m?.posted ? 'success' : 'neutral' },
    { label: match.label.toLowerCase(), tone: match.tone },
  ];
  return {
    lines,
    ordered,
    received,
    by,
    day,
    full: fmtDate(m?.receivedOn) || '—',
    year: m?.receivedOn ? String(m.receivedOn.getFullYear()) : '',
    match,
    tags,
    postedTag: tags[0],
    matchTag: tags[1],
    postedYes: m?.posted ? 'Yes' : 'No',
    sub: [po, by && `received by ${by}`].filter(Boolean).join(' · '),
    fact: `${received} of ${ordered} in${day ? ` · ${day}` : ''}`,
    count: `${lines.length} line${lines.length === 1 ? '' : 's'}`,
  };
}

class GoodsReceiptIsolated extends Component<typeof GoodsReceipt> {
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked message: string | undefined;

  post = async () => {
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
      let result = await new ReceiveGoodsCommand(commandContext).execute({
        receipt: model,
      } as any);
      this.message = (result as any)?.message;
    } catch (error: any) {
      this.error = error?.message ?? String(error);
    } finally {
      this.busy = false;
    }
  };

  get f() {
    return grFacts(this.args.model as GoodsReceipt);
  }
  get receipt(): KeyValueItem[] {
    return [
      { key: 'Received on', value: this.f.full },
      { key: 'Received by', value: this.f.by || '—' },
      { key: 'Posted', value: this.f.postedTag.label },
    ];
  }
  get details(): KeyValueItem[] {
    return [
      { key: 'Received on', value: this.f.full },
      { key: 'Received by', value: this.f.by || '—' },
      { key: 'Ordered', value: `${this.f.ordered}` },
      { key: 'Received', value: `${this.f.received}` },
      { key: 'Match', value: this.f.match.label },
      { key: 'Posted', value: this.f.postedYes },
      { key: 'Lines', value: `${this.f.lines.length}` },
    ];
  }
  <template>
    <article class='gr'>
      <div class='card'>
        <header class='ih'>
          <Avatar @name='Goods Receipt' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{@model.title}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>{{#each this.f.tags as |t|}}<Chip
                @label={{t.label}}
                @tone={{t.tone}}
                @appearance='plain'
              />{{/each}}</span>
          {{#unless @model.posted}}
            <Button
              @appearance='accent'
              @disabled={{this.busy}}
              {{on 'click' this.post}}
            >Post receipt</Button>
          {{/unless}}
        </header>
        <div class='stats'>
          <Stat
            @label='Received'
            @tone={{this.f.match.tone}}
            @value='{{this.f.received}} / {{this.f.ordered}}'
            @roll={{false}}
            @hint={{this.f.count}}
          />
          <Stat
            @label='Match'
            @tone={{this.f.match.tone}}
            @value={{this.f.match.label}}
            @roll={{false}}
            @hint={{this.f.match.hint}}
          />
          <Stat
            @label='Received on'
            @tone='neutral'
            @value={{if this.f.day this.f.day '—'}}
            @roll={{false}}
            @hint={{this.f.year}}
          />
        </div>
      </div>

      {{#if this.error}}
        <Alert @tone='danger' style={{ALERT_STYLE.danger}}>
          {{this.error}}
        </Alert>
      {{/if}}
      {{#if this.message}}
        <Alert @tone='success' style={{ALERT_STYLE.success}}>
          {{this.message}}
        </Alert>
      {{/if}}

      <div class='cols'>
        <div class='col'>
          <section class='card'>
            <h2>Lines</h2>
            <div class='lines'>
              {{#each @fields.lines as |Line|}}
                <Line />
              {{else}}
                <EmptyState
                  style={{COMPACT_EMPTY_STYLE}}
                  @texture={{false}}
                  @title='No lines recorded'
                />
              {{/each}}
            </div>
          </section>
        </div>
        <div class='col'>
          <section class='card'>
            <h2>Receipt</h2>
            <KeyValue
              @items={{this.receipt}}
              @divided={{true}}
              @labelStyle='eyebrow'
              class='kv kv-pad'
            />
          </section>
          {{#if @model.purchaseOrder}}
            <section class='card'>
              <h2>Linked</h2>
              <KeyValue
                @items={{LINKED}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv kv-pad'
              >
                <:value><@fields.purchaseOrder
                    @format='atom'
                    @displayContainer={{false}}
                  /></:value>
              </KeyValue>
            </section>
          {{/if}}
          <section class='card'>
            <h2>Details</h2>
            <KeyValue
              @items={{this.details}}
              @divided={{true}}
              @labelStyle='eyebrow'
              class='kv kv-pad'
            />
          </section>
        </div>
      </div>
    </article>
    <style scoped>
      .kv-pad {
        --pretui-kv-pad-inline: var(--boxel-sp-sm);
      }

      .gr {
        container-type: inline-size;
        box-sizing: border-box;
        block-size: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.25;
        color: var(--card-foreground);
        --text-stat: 1.375rem;
        --text-ui-xs: 0.6875rem;
        --pretui-kv-label-font-size: 0.5625rem;
        --pretui-kv-label-color: var(--muted-foreground);
        --pretui-kv-label-font-family: var(--font-mono);
        --pretui-kv-label-font-weight: 600;
        --pretui-kv-label-letter-spacing: 0.13em;

        background: var(--background);
        min-height: 100%;
      }
      /* the root scrolls; its blocks keep their own height instead of shrinking */
      .gr > * {
        flex: none;
      }
      .card {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .ih {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
      }
      .id {
        flex: 1;
        min-inline-size: 10rem;
      }
      h1 {
        margin: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .tags {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        border-block-start: 1px solid var(--border);
      }
      .stats > * {
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
      }
      .stats > :not(:first-child) {
        border-inline-start: 1px solid var(--border);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
        gap: var(--boxel-sp-xs);
        align-items: start;
      }
      .col {
        display: flex;
        flex-direction: column;
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
      .lines > * + * {
        border-block-start: 1px solid var(--border);
      }
      .kv {
        padding: 0 var(--boxel-sp-xs);
        row-gap: 0;
        --boxel-sp-xs: 0.35rem;
        --boxel-sp-lg: 0.75rem;
      }
    </style>
  </template>
}

const LINKED: KeyValueItem[] = [{ key: 'Purchase order', value: '' }];

// A record of what physically arrived against one PO — the receiving half of
// the two-way match. Multiple receipts can accumulate against the same PO
// (partial receiving); ReceiveGoodsCommand is the single writer that creates
// these, flips the PO's status, and moves the received value from the
// budget's `committed` to `actual`.
export class GoodsReceipt extends CardDef {
  static displayName = 'Goods Receipt';

  @field purchaseOrder = linksTo(() => PurchaseOrder);
  @field receivedOn = contains(DateField);
  @field receivedBy = contains(StringField);
  @field lines = containsMany(ReceiptLineField);
  // Set only by ReceiveGoodsCommand when the receipt is applied to its PO
  // and budget — a posted receipt is immutable in spirit and cannot be
  // posted twice.
  @field posted = contains(BooleanField);

  @field matchResult = contains(StringField, {
    computeVia: function (this: GoodsReceipt) {
      let lines = (this.lines ?? []).filter(Boolean);
      if (!lines.length) {
        return 'empty';
      }
      if (lines.some((l) => l.matchState === 'over')) {
        return 'over';
      }
      if (lines.some((l) => l.matchState === 'short')) {
        return 'partial';
      }
      return 'matched';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: GoodsReceipt) {
      let d = this.receivedOn;
      let day = d
        ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : '';
      return day ? `Goods Receipt · ${day}` : 'Goods Receipt';
    },
  });

  static isolated = GoodsReceiptIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return grFacts(this.args.model as GoodsReceipt);
    }
    get items(): KeyValueItem[] {
      let rows: KeyValueItem[] = [
        { key: 'Received on', value: this.f.full },
        { key: 'Received by', value: this.f.by || '—' },
        { key: 'Ordered', value: `${this.f.ordered}` },
        { key: 'Received', value: `${this.f.received}` },
        { key: 'Match', value: this.f.match.label },
        { key: 'Posted', value: this.f.postedYes },
      ];
      if (this.args.model?.purchaseOrder) {
        rows.push({ key: 'Purchase order', value: '' });
      }
      return rows;
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <div class='eh1'>
            <Avatar @name='Goods Receipt' @shape='square' @size={{20}} />
            <strong class='nm'>{{@model.title}}</strong>
            <Chip
              @label={{this.f.postedTag.label}}
              @tone={{this.f.postedTag.tone}}
              @appearance='plain'
            />
          </div>
          <div class='eh2'>
            <span class='meta'>{{this.f.sub}}</span>
            <Chip
              @label={{this.f.matchTag.label}}
              @tone={{this.f.matchTag.tone}}
              @appearance='plain'
            />
          </div>
        </header>
        <p class='fact'><strong>{{this.f.received}}
            of
            {{this.f.ordered}}</strong>
          in ·
          {{this.f.full}}</p>
        <KeyValue
          @items={{this.items}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv kv-pad'
        >
          <:value as |row|>
            {{#if (eq row.key 'Purchase order')}}<@fields.purchaseOrder
                @format='atom'
                @displayContainer={{false}}
              />{{else}}{{row.value}}{{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }

        .emb {
          font-size: 0.75rem;
          line-height: 1.25;
          color: var(--card-foreground);
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          --pretui-kv-label-font-family: var(--font-mono);
          --pretui-kv-label-font-weight: 600;
          --pretui-kv-label-letter-spacing: 0.13em;
        }
        .eh {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          padding: 0.5rem 0.625rem;
          border-block-end: 1px solid var(--border);
        }
        .eh1,
        .eh2 {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 0.375rem;
        }
        .nm {
          flex: 1;
          min-inline-size: 0;
          font-weight: 700;
        }
        .meta {
          flex: 1;
          min-inline-size: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-block-end: 1px solid var(--border);
        }
        .kv {
          padding: 0 0.625rem;
          row-gap: 0;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get f() {
      return grFacts(this.args.model as GoodsReceipt);
    }
    <template>
      <span class='atom'>
        <Avatar @name='Goods Receipt' @shape='square' @size={{16}} />
        <span class='name'>{{@model.title}}</span>
        <Chip
          @label={{this.f.matchTag.label}}
          @tone={{this.f.matchTag.tone}}
          @appearance='plain'
        />
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
      return grFacts(this.args.model as GoodsReceipt);
    }
    <template>
      <CompactFitted
        @mark='Goods Receipt'
        @title={{@model.title}}
        @sub={{this.f.sub}}
        @fact={{this.f.fact}}
        @big='{{this.f.received}} / {{this.f.ordered}}'
        @bigLabel={{this.f.match.label}}
        @tags={{this.f.tags}}
      >
        <:rows>
          <CompactRow @k='Received on' @v={{this.f.full}} />
          <CompactRow @k='Received by' @v={{if this.f.by this.f.by '—'}} />
          <CompactRow @k='Ordered' @v='{{this.f.ordered}}' />
          <CompactRow @k='Received' @v='{{this.f.received}}' />
          <CompactRow @k='Match' @v={{this.f.match.label}} />
          <CompactRow @k='Posted' @v={{this.f.postedYes}} />
          {{#each this.f.lines as |l|}}
            <CompactRow
              @k={{if l.description l.description '—'}}
              @v='{{l.qtyReceived}} / {{l.qtyOrdered}}'
            />
          {{/each}}
        </:rows>
      </CompactFitted>
    </template>
  };

  // Grouped by how a receipt is recorded at the dock (who signed for it and
  // when → against which PO → what actually arrived, line by line), not
  // schema order. Three sections — no nav rail (edit-card Rule 0).
  // matchResult and title are computed (computeVia) and deliberately
  // excluded.
}
