import { RelatedList, relatedSearch } from '../crm/record-views';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { formatMoney, hasNumber } from '../crm/utils';
import { CompactFitted, CompactRow, fmtDate, orEmpty } from './compact-parts';
import { Deal } from './deal';

const QUOTE_TONE: Record<string, 'success' | 'danger' | 'info' | 'neutral'> = {
  won: 'success',
  lost: 'danger',
  expired: 'danger',
  sent: 'info',
};

// What every format reads off the proposal, in one place.
function facts(m?: Proposal) {
  // Quotes link to their proposal (Quote.proposal); the proposal holds no quotes field.
  let quotes: any[] = [];
  let latest = quotes[quotes.length - 1];
  let deal = m?.deal;
  let amount = deal?.value?.amount;
  let money = hasNumber(amount)
    ? formatMoney(amount, deal?.value?.currency?.code)
    : '';
  let tags = [
    ...(latest
      ? [
          {
            label: `v${latest.version ?? 1} ${latest.status ?? ''}`.trim(),
            tone: QUOTE_TONE[latest.status] ?? 'neutral',
          },
        ]
      : []),
    ...(quotes.length
      ? [
          {
            label: `${quotes.length} quote${quotes.length === 1 ? '' : 's'}`,
            tone: 'neutral' as const,
          },
        ]
      : []),
  ];
  return {
    quotes,
    latest,
    money,
    amount,
    tags,
    lead: tags.slice(0, 1),
    leadLabel: tags[0]?.label,
    sub: [deal?.cardTitle, money].filter(Boolean).join(' · '),
    fact: [money, tags[1]?.label].filter(Boolean).join(' · '),
    quoteText: quotes
      .map((q) => `v${q.version ?? 1} ${q.status ?? ''}`.trim())
      .join(', '),
    stage: deal?.stage ?? '',
    close: fmtDate(deal?.closeDate),
    account: deal?.account?.cardTitle ?? '',
  };
}

export class Proposal extends CardDef {
  static displayName = 'Proposal';
  static icon = FileTextIcon;

  @field title = contains(StringField);
  @field narrative = contains(MarkdownField);
  @field deal = linksTo(Deal);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Proposal) {
      return this.title?.trim()?.length
        ? this.title
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Proposal> {
    <template>
      <span class='atom'>
        <Avatar @name='Proposal' @shape='square' @size={{16}} />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-inline-size: 0;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Proposal> {
    get f() {
      return facts(this.args.model as Proposal);
    }
    <template>
      <CompactFitted
        @mark='Proposal'
        @title={{@model.cardTitle}}
        @sub={{this.f.sub}}
        @fact={{this.f.fact}}
        @big={{this.f.money}}
        @bigLabel='Deal value'
        @tags={{this.f.tags}}
      >
        <:rows>
          {{#if this.f.stage}}<CompactRow
              @k='Stage'
              @v={{this.f.stage}}
            />{{/if}}
          {{#if this.f.quoteText}}<CompactRow
              @k='Quotes'
              @v={{this.f.quoteText}}
            />{{/if}}
          {{#if @model.deal}}<CompactRow @k='Deal'><@fields.deal
                @format='atom'
                @displayContainer={{false}}
              /></CompactRow>{{/if}}
          {{#if this.f.close}}<CompactRow
              @k='Close date'
              @v={{this.f.close}}
            />{{/if}}
        </:rows>
      </CompactFitted>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Proposal> {
    get f() {
      return facts(this.args.model as Proposal);
    }
    get items(): KeyValueItem[] {
      let rows: KeyValueItem[] = [];
      if (this.f.stage) rows.push({ key: 'Stage', value: this.f.stage });
      if (this.f.quoteText)
        rows.push({ key: 'Quotes', value: this.f.quoteText });
      if (this.f.close) rows.push({ key: 'Close date', value: this.f.close });
      if (this.args.model?.deal) rows.push({ key: 'Deal', value: '' });
      return rows;
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <Avatar @name='Proposal' @shape='square' @size={{24}} />
          <div class='id'>
            <strong>{{@model.cardTitle}}</strong>
            <span class='meta'>{{this.f.sub}}</span>
          </div>
          {{#each this.f.lead as |t|}}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}
        </header>
        <p class='fact'>{{this.f.fact}}</p>
        <KeyValue
          @items={{this.items}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv'
        >
          <:value as |row|>
            {{#if (eq row.key 'Deal')}}<@fields.deal
                @format='atom'
                @displayContainer={{false}}
              />
            {{else}}{{row.value}}{{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .emb {
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: var(--boxel-font-size-2xs);
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.25;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .id {
          flex: 1;
          min-inline-size: 0;
          display: flex;
          flex-direction: column;
        }
        .id strong,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta,
        .fact {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact {
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .kv {
          padding-inline: var(--boxel-sp-xs);
          row-gap: 0;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Proposal> {
    private rel = (path: string, name: string, field: string) =>
      relatedSearch(
        this,
        this.args.context,
        () => this.args.model,
        // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
        new URL(path, import.meta.url).href,
        name,
        field,
      );
    quoteCardsSearch = this.rel('./quote', 'Quote', 'proposal.id');
    get quoteCards(): any[] {
      return ((this.quoteCardsSearch?.instances ?? []) as any[]).filter(
        Boolean,
      );
    }
    get f() {
      return facts(this.args.model as Proposal);
    }
    get linked(): KeyValueItem[] {
      let rows: KeyValueItem[] = [];
      if (this.args.model?.deal) rows.push({ key: 'Deal', value: '' });
      return rows;
    }
    get details(): KeyValueItem[] {
      let rows: KeyValueItem[] = [];
      if (this.args.model?.deal?.cardTitle)
        rows.push({ key: 'Deal', value: this.args.model.deal.cardTitle });
      if (this.f.money) rows.push({ key: 'Deal value', value: this.f.money });
      if (this.f.stage) rows.push({ key: 'Stage', value: this.f.stage });
      if (this.f.quoteText)
        rows.push({ key: 'Quotes', value: this.f.quoteText });
      if (this.f.account) rows.push({ key: 'Account', value: this.f.account });
      if (this.f.close) rows.push({ key: 'Close date', value: this.f.close });
      return rows;
    }
    <template>
      <article class='pp'>
        <header class='ph'>
          <Avatar @name='Proposal' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{@model.cardTitle}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>{{#each this.f.tags as |t|}}<Chip
                @label={{t.label}}
                @tone={{t.tone}}
                @appearance='plain'
              />{{/each}}</span>
        </header>
        <div class='stats'>
          <Stat
            @label='Deal value'
            @tone='info'
            @value={{orEmpty this.f.amount}}
            @style='currency'
            @currency={{@model.deal.value.currency.code}}
            @maximumFractionDigits={{0}}
            @roll={{false}}
            @hint={{this.f.stage}}
          />
          <Stat
            @label='Quotes'
            @tone='success'
            @value={{this.quoteCards.length}}
            @roll={{false}}
            @hint={{this.f.leadLabel}}
          />
          <Stat @label='Close date' @value={{this.f.close}} @roll={{false}} />
        </div>
        <div class='cols'>
          <div>
            {{#if @model.narrative}}
              <div class='pad'><@fields.narrative /></div>
            {{/if}}
          </div>
          <div>
            <section>
              <h2>Linked</h2>
              <KeyValue
                @items={{this.linked}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv'
              >
                <:value>
                  <@fields.deal @format='atom' @displayContainer={{false}} />
                </:value>
              </KeyValue>
            </section>
            <RelatedList
              @title='Quotes'
              @cards={{this.quoteCards}}
              @empty='No quotes yet'
            />
            <section>
              <h2>Details</h2>
              <KeyValue
                @items={{this.details}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv'
              />
            </section>
          </div>
        </div>
      </article>
      <style scoped>
        .pp {
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: var(--boxel-font-size-2xs);
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .ph {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
        }
        .id {
          flex: 1;
          min-inline-size: 0;
        }
        h1 {
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
        .stats > :not(:first-child) {
          border-inline-start: 1px solid var(--border);
        }
        .stats > * {
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
          border-block-start: 1px solid var(--border);
        }
        .cols > div {
          min-inline-size: 0;
        }
        .cols > div + div {
          border-inline-start: 1px solid var(--border);
        }
        @container (width < 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .cols > div + div {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
        h2 {
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .pad {
          padding: var(--boxel-sp-xs);
        }
        .kv {
          padding-inline: var(--boxel-sp-xs);
          row-gap: 0;
        }
      </style>
    </template>
  };
}
