import { RelatedList, relatedSearch } from '../crm/record-views';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  resolveRRIReference,
  type RealmResourceIdentifier,
} from '@cardstack/runtime-common';
import {
  Component,
  contains,
  containsMany,
  field,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import MarkdownField from '@cardstack/base/markdown';
import BriefcaseIcon from '@cardstack/boxel-icons/briefcase';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { fmtDate, orEmpty } from './compact-parts';
import { Opportunity } from '../crm/opportunity';
import { Contact } from '../crm/contact';
import { formatMoney, hasNumber } from '../crm/utils';
import { IsoFrame } from '../shared/compact-sheet';

function stageTone(stage?: string) {
  if (stage === 'closed won') return 'success' as const;
  if (stage === 'closed lost') return 'danger' as const;
  if (stage === 'proposal' || stage === 'negotiation') return 'info' as const;
  return 'neutral' as const;
}

// What every format reads off the deal, in one place.
function facts(m?: Deal) {
  let amount = m?.value?.amount;
  let code = m?.value?.currency?.code;
  let p = m?.effectiveProbability;
  let weighted =
    typeof amount === 'number' && typeof p === 'number'
      ? (amount * p) / 100
      : undefined;
  let sub = [m?.account?.cardTitle, m?.owner?.cardTitle]
    .filter(Boolean)
    .join(' · ');
  let close = fmtDate(m?.closeDate, false);
  let fact = [
    hasNumber(amount) ? formatMoney(amount, code) : '',
    hasNumber(p) ? `${p}%` : '',
    close ? `closes ${close}` : '',
  ]
    .filter(Boolean)
    .join(' · ');
  let tags = [
    ...(m?.stage ? [{ label: m.stage, tone: stageTone(m.stage) }] : []),
    ...(hasNumber(p) ? [{ label: `${p}%`, tone: 'neutral' as const }] : []),
  ];
  return {
    lead: tags.slice(0, 1),
    amount,
    code,
    p,
    weighted,
    sub,
    fact,
    money: hasNumber(amount) ? formatMoney(amount, code) : '',
    weightedText: hasNumber(weighted) ? formatMoney(weighted, code) : '',
    closeText: fmtDate(m?.closeDate),
    competitors: (m?.competitors ?? []).join(', '),
    pText: hasNumber(p) ? `${p}%` : '—',
    tags,
  };
}

export class Deal extends Opportunity {
  static displayName = 'Deal';
  static icon = BriefcaseIcon;

  @field terms = contains(MarkdownField);
  @field competitors = containsMany(StringField);
  @field decisionMakers = linksToMany(Contact);

  static atom = class Atom extends Component<typeof Deal> {
    <template>
      <span class='atom'>
        <Avatar @name='Deal' @shape='square' @size={{16}} />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
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

  static fitted = class Fitted extends Component<typeof Deal> {
    get f() {
      return facts(this.args.model as Deal);
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar @name='Deal' @shape='square' @size={{20}} /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#each this.f.tags as |t|}}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{this.f.sub}}</:subtitle>
        <:fact>{{this.f.fact}}</:fact>
        <:metric><Metric @value={{this.f.money}} @label='Value' /></:metric>
        <:details>
          {{#if this.f.weightedText}}<Detail
              @label='Weighted'
              @value={{this.f.weightedText}}
            />{{/if}}
          {{#if this.f.closeText}}<Detail
              @label='Close date'
              @value={{this.f.closeText}}
            />{{/if}}
          {{#if @model.account}}<Detail @label='Account'><@fields.account
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.daysInStage}}<Detail
              @label='Days in stage'
              @value='{{@model.daysInStage}}'
            />{{/if}}
          {{#if this.f.competitors}}<Detail
              @label='Competitors'
              @value={{this.f.competitors}}
            />{{/if}}
          {{#if @model.owner}}<Detail @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.decisionMakers.length}}<Detail
              @label='Decision makers'
              @value='{{@model.decisionMakers.length}}'
            />{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Deal> {
    get f() {
      return facts(this.args.model as Deal);
    }
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (this.f.weightedText) {
        rows.push({ key: 'Weighted', value: this.f.weightedText });
      }
      if (this.f.closeText)
        rows.push({ key: 'Close date', value: this.f.closeText });
      if (m?.daysInStage)
        rows.push({ key: 'Days in stage', value: `${m.daysInStage}` });
      if (this.f.competitors)
        rows.push({ key: 'Competitors', value: this.f.competitors });
      if (m?.decisionMakers?.length) {
        rows.push({
          key: 'Decision makers',
          value: `${m.decisionMakers.length}`,
        });
      }
      if (m?.account) rows.push({ key: 'Account', value: '' });
      if (m?.owner) rows.push({ key: 'Owner', value: '' });
      return rows;
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <Avatar @name='Deal' @shape='square' @size={{24}} />
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
            {{#if (eq row.key 'Account')}}<@fields.account
                @format='atom'
                @displayContainer={{false}}
              />
            {{else if (eq row.key 'Owner')}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />
            {{else}}{{row.value}}{{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          font-size: 0.75rem;
          line-height: 1.25;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
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
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0 0.625rem 0.5rem;
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
          row-gap: 0;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Deal> {
    private rel = (path: string, name: string, field: string) =>
      relatedSearch(
        this,
        this.args.context,
        () => this.args.model,
        // @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
        resolveRRIReference(path, import.meta.url as RealmResourceIdentifier),
        name,
        field,
      );
    activityCardsSearch = this.rel('../crm/activity', 'Activity', 'about.id');
    get activityCards(): any[] {
      return ((this.activityCardsSearch?.instances ?? []) as any[]).filter(
        Boolean,
      );
    }
    proposalCardsSearch = this.rel('./proposal', 'Proposal', 'deal.id');
    get proposalCards(): any[] {
      return ((this.proposalCardsSearch?.instances ?? []) as any[]).filter(
        Boolean,
      );
    }
    quoteCardsSearch = this.rel('./quote', 'Quote', 'deal.id');
    get quoteCards(): any[] {
      return ((this.quoteCardsSearch?.instances ?? []) as any[]).filter(
        Boolean,
      );
    }
    get f() {
      return facts(this.args.model as Deal);
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (this.f.money) rows.push({ key: 'Value', value: this.f.money });
      if (hasNumber(this.f.p)) {
        rows.push({
          key: 'Probability',
          value: `${this.f.p}% (${typeof m?.probability === 'number' ? 'override' : 'stage default'})`,
        });
      }
      if (this.f.weightedText)
        rows.push({ key: 'Weighted', value: this.f.weightedText });
      if (this.f.closeText)
        rows.push({ key: 'Close date', value: this.f.closeText });
      if (m?.daysInStage)
        rows.push({ key: 'Days in stage', value: `${m.daysInStage}` });
      if (this.f.competitors)
        rows.push({ key: 'Competitors', value: this.f.competitors });
      if (m?.decisionMakers?.length) {
        rows.push({
          key: 'Decision makers',
          value: `${m.decisionMakers.length}`,
        });
      }
      return rows;
    }
    get linked(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.account) rows.push({ key: 'Account', value: '' });
      if (m?.owner) rows.push({ key: 'Owner', value: '' });
      return rows;
    }
    <template>
      <IsoFrame>
        <article class='dp'>
          <header class='dh'>
            <Avatar @name='Deal' @shape='square' @size={{24}} />
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
              @label='Value'
              @tone='info'
              @value={{orEmpty this.f.amount}}
              @style='currency'
              @currency={{this.f.code}}
              @maximumFractionDigits={{0}}
              @roll={{false}}
              @hint={{this.f.code}}
            />
            <Stat
              @label='Probability'
              @value={{this.f.pText}}
              @roll={{false}}
              @hint='stage default'
            />
            <Stat
              @label='Weighted'
              @value={{orEmpty this.f.weighted}}
              @style='currency'
              @currency={{this.f.code}}
              @maximumFractionDigits={{0}}
              @roll={{false}}
              @hint='value × probability'
            />
            <Stat
              @label='Days in stage'
              @value={{orEmpty @model.daysInStage}}
              @roll={{false}}
            />
          </div>
          <div class='cols'>
            <div>
              {{#if @model.terms}}
                <section>
                  <h2>Terms</h2>
                  <div class='pad'><@fields.terms /></div>
                </section>
              {{/if}}
              {{#if @model.competitors.length}}
                <section>
                  <h2>Competitors</h2>
                  <ul class='rows'>{{#each @model.competitors as |c|}}<li
                      >{{c}}</li>{{/each}}</ul>
                </section>
              {{/if}}
              {{#if @model.decisionMakers.length}}
                <section>
                  <h2>Decision makers</h2>
                  <div class='people'><@fields.decisionMakers
                      @format='atom'
                      @displayContainer={{false}}
                    /></div>
                </section>
              {{/if}}
              <RelatedList
                @title='Activity'
                @cards={{this.activityCards}}
                @empty='No activity logged'
              />
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
                  <:value as |row|>
                    {{#if (eq row.key 'Account')}}<@fields.account
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else}}<@fields.owner
                        @format='atom'
                        @displayContainer={{false}}
                      />{{/if}}
                  </:value>
                </KeyValue>
              </section>
              <RelatedList
                @title='Proposals'
                @cards={{this.proposalCards}}
                @empty='No proposal yet'
              />
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
      </IsoFrame>
      <style scoped>
        .dp {
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.25;
          color: var(--card-foreground);
        }
        .dh {
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
          margin: 0;
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
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .pad {
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .rows > li {
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-block-start: 1px solid var(--border);
        }
        .people {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
          row-gap: 0;
        }
      </style>
    </template>
  };
}
