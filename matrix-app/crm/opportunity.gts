import { Button } from '@cardstack/pretui/components/button';
import { on } from '@ember/modifier';
import { array, hash } from '@ember/helper';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  type BaseDefComponent,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import PercentageField from 'https://cardstack.com/base/percentage';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import TrendingUpIcon from '@cardstack/boxel-icons/trending-up';
import { eq } from '@cardstack/boxel-ui/helpers';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Account } from './account';
import { User } from './user';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { CompactFitted, CompactRow } from '../commerce/compact-parts';
import {
  RecordEmbedded,
  RecordPage,
  RelatedList,
  relatedSearch,
  shortDate,
  usd,
} from './record-views';
import { createLinked, relatedRealm } from './record-views';
import { hasNumber } from './utils';
// EXTRACTED to its own module (Revenue Ops Console build) so Pipeline Stage
// is a standalone, Spec-able block instead of private to this file. Kept as
// a re-export below so every existing consumer of `./opportunity`
// (`deal.gts`, `revenue-os.gts`, `board-demo.gts`) needs zero edits.
import {
  PipelineStageField as StageField,
  PIPELINE_STAGES,
  STAGE_DEFAULT_PROBABILITY,
  STAGE_COLORS,
  stageSlug,
} from './pipeline-stage-field';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;

export { PIPELINE_STAGES, STAGE_DEFAULT_PROBABILITY, STAGE_COLORS, stageSlug };

/** The stage pill's hue, from the Pipeline Stage field's own option table. */
function stageHue(stage: string | undefined) {
  return statusHue(StageField, stage);
}

export class Opportunity extends CardDef {
  static displayName = 'Opportunity';
  static icon = TrendingUpIcon;

  @field name = contains(StringField);
  @field account = linksTo(Account);
  @field owner = linksTo(User);
  @field value = contains(AmountWithCurrency);
  @field stage = contains(StageField);
  @field probability = contains(PercentageField);
  @field closeDate = contains(DateField);
  // Written by whoever moves the stage. An event fact rather than a derived
  // value: how long a deal has sat still is not recoverable after the fact.
  @field lastStageChangedAt = contains(DateField);

  @field daysInStage = contains(NumberField, {
    computeVia: function (this: Opportunity) {
      if (!this.lastStageChangedAt) return 0;
      let days = Math.floor(
        (Date.now() - new Date(this.lastStageChangedAt).getTime()) / 86400000,
      );
      return days > 0 ? days : 0;
    },
  });

  @field effectiveProbability = contains(NumberField, {
    computeVia: function (this: Opportunity) {
      if (typeof this.probability === 'number') return this.probability;
      return STAGE_DEFAULT_PROBABILITY[this.stage ?? ''] ?? 0;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Opportunity) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Opportunity> {
    <template>
      <span class='atom'>
        <Avatar @name='O P' @shape='rounded' @size={{16}} />
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

  static embedded = class Embedded extends Component<typeof Opportunity> {
    get weighted() {
      let m = this.args.model;
      let a = m?.value?.amount;
      return typeof a === 'number'
        ? (a * (m?.effectiveProbability ?? 0)) / 100
        : undefined;
    }
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let c = m?.value?.currency?.code;
      let rows: KeyValueItem[] = [];
      if (this.weighted !== undefined)
        rows.push({ key: 'Weighted', value: usd(this.weighted, c) });
      if (m?.closeDate)
        rows.push({ key: 'Close date', value: shortDate(m.closeDate, true) });
      if (m?.lastStageChangedAt)
        rows.push({
          key: 'In stage since',
          value: shortDate(m.lastStageChangedAt, true),
        });
      if (m?.account) rows.push({ key: 'Account', value: '@account' });
      if (m?.owner) rows.push({ key: 'Owner', value: '@owner' });
      return rows;
    }
    get summary() {
      let m = this.args.model;
      return [
        usd(m?.value?.amount, m?.value?.currency?.code),
        `${m?.effectiveProbability ?? 0}%`,
        m?.closeDate ? `closes ${shortDate(m.closeDate)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
    }
    get chips() {
      return [
        {
          label: this.args.model?.stage ?? '',
          hue: stageHue(this.args.model?.stage),
        },
      ];
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.account?.name, m?.owner?.name].filter(Boolean).join(' · ');
    }
    <template>
      <RecordEmbedded
        @mark='O P'
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{this.chips}}
        @summary={{this.summary}}
        @items={{this.items}}
      >
        <:value as |row|>
          {{#if (eq row.value '@account')}}
            <@fields.account @format='atom' @displayContainer={{false}} />
          {{else if (eq row.value '@owner')}}
            <@fields.owner @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Opportunity> {
    get weightedText() {
      let m = this.args.model;
      let v = m?.value?.amount;
      return typeof v === 'number'
        ? usd(
            (v * (m?.effectiveProbability ?? 0)) / 100,
            m?.value?.currency?.code,
          )
        : '—';
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.account?.name, m?.owner?.name].filter(Boolean).join(' · ');
    }
    get fact() {
      let m = this.args.model;
      return [
        usd(m?.value?.amount, m?.value?.currency?.code),
        `${m?.effectiveProbability ?? 0}%`,
        m?.closeDate ? `closes ${shortDate(m.closeDate)}` : '',
      ]
        .filter(Boolean)
        .join(' · ');
    }
    <template>
      <CompactFitted
        @mark='Opportunity'
        @title={{@model.cardTitle}}
        @sub={{this.subtitle}}
        @fact={{this.fact}}
        @big={{usd @model.value.amount @model.value.currency.code}}
        @bigLabel='Value'
        @tags={{if @model.stage (array (hash label=@model.stage tone='info'))}}
      >
        <:rows>
          <CompactRow @k='Weighted' @v={{this.weightedText}} />
          {{#if @model.closeDate}}<CompactRow
              @k='Close date'
              @v={{shortDate @model.closeDate true}}
            />{{/if}}
          {{#if @model.account}}<CompactRow @k='Account'><@fields.account
                @format='atom'
                @displayContainer={{false}}
              /></CompactRow>{{/if}}
          {{#if @model.lastStageChangedAt}}<CompactRow
              @k='In stage since'
              @v={{shortDate @model.lastStageChangedAt true}}
            />{{/if}}
          {{#if @model.owner}}<CompactRow @k='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></CompactRow>{{/if}}
        </:rows>
      </CompactFitted>
    </template>
  };

  // `BaseDefComponent` keeps a subclass's isolated view (Deal) assignable.
  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof Opportunity
  > {
    logActivity = () =>
      createLinked(
        this.args,
        new URL('./activity', moduleURL).href,
        'Activity',
        'about',
        { activityType: 'note', occurredAt: new Date().toISOString() },
      );
    closeWon = async () => {
      let ctx = (this.args.context as any)?.commandContext;
      let { default: CloseWon } = await import('./commands/close-won.gts');
      if (!ctx) return;
      await new CloseWon(ctx).execute({
        deal: this.args.model,
        realm: this.realmHref,
      } as any);
    };
    get realmHref() {
      return relatedRealm(this.args.model);
    }
    activitySearch = relatedSearch(
      this,
      this.args.context,
      () => this.args.model,
      new URL('./activity', moduleURL).href,
      'Activity',
      'about.id',
    );
    get activityCards(): any[] {
      return ((this.activitySearch?.instances ?? []) as any[]).filter(Boolean);
    }
    get c() {
      return this.args.model?.value?.currency?.code;
    }
    get weighted(): number | undefined {
      let amount = this.args.model?.value?.amount;
      let p = this.args.model?.effectiveProbability;
      if (!hasNumber(amount) || typeof p !== 'number') return undefined;
      return (amount * p) / 100;
    }
    get probabilitySource() {
      return typeof this.args.model?.probability === 'number'
        ? 'override'
        : 'stage default';
    }
    // A lost deal's rail ends at "closed lost" (an error step) instead of
    // "closed won"; a won deal is complete through its last step.
    get stages(): StepItem[] {
      let current = this.args.model?.stage;
      let lost = current === 'closed lost';
      let won = current === 'closed won';
      let list = PIPELINE_STAGES.filter((s) =>
        lost ? s !== 'closed won' : s !== 'closed lost',
      );
      let idx = list.indexOf(current as (typeof PIPELINE_STAGES)[number]);
      return list.map((label, i) => {
        let state: StepState =
          idx < 0 || i > idx
            ? 'upcoming'
            : i < idx || won
              ? 'complete'
              : lost
                ? 'error'
                : 'current';
        return { label, state };
      });
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.account?.name, m?.owner?.name].filter(Boolean).join(' · ');
    }
    get chips() {
      let m = this.args.model;
      let chips = [{ label: m?.stage ?? '', hue: stageHue(m?.stage) }];
      if (m?.daysInStage && m.daysInStage >= 30)
        chips.push({ label: `${m.daysInStage} days in stage`, hue: 'amber' });
      return chips;
    }
    get stats() {
      let m = this.args.model;
      return [
        {
          label: 'Value',
          value: m?.value?.amount ?? 0,
          currency: this.c ?? 'USD',
          hint: this.c ?? '',
          tone: 'primary',
        },
        {
          label: 'Probability',
          value: `${m?.effectiveProbability ?? 0}%`,
          hint: `${m?.stage} ${this.probabilitySource}`,
          tone: 'neutral',
        },
        {
          label: 'Weighted',
          value: this.weighted ?? 0,
          currency: this.c ?? 'USD',
          hint: 'value × probability',
          tone: 'success',
        },
        {
          label: 'Days in stage',
          value: m?.daysInStage ?? 0,
          hint: m?.lastStageChangedAt
            ? `since ${shortDate(m.lastStageChangedAt, true)}`
            : '',
          tone: 'warning',
        },
      ];
    }
    get linked(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.account) rows.push({ key: 'Account', value: '@account' });
      if (m?.owner) rows.push({ key: 'Owner', value: '@owner' });
      return rows;
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [
        { key: 'Value', value: usd(m?.value?.amount, this.c) },
        {
          key: 'Probability',
          value: `${m?.effectiveProbability ?? 0}% (${this.probabilitySource})`,
        },
        { key: 'Weighted', value: usd(this.weighted, this.c) },
      ];
      if (m?.closeDate)
        rows.push({ key: 'Close date', value: shortDate(m.closeDate, true) });
      rows.push({ key: 'Stage', value: m?.stage ?? '' });
      if (m?.lastStageChangedAt)
        rows.push({
          key: 'In stage since',
          value: shortDate(m.lastStageChangedAt, true),
        });
      return rows;
    }
    <template>
      <RecordPage
        @mark='O P'
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
        @chips={{this.chips}}
        @stats={{this.stats}}
        @linked={{this.linked}}
        @details={{this.details}}
      >
        <:actions>
          <Button @appearance='outlined' {{on 'click' this.logActivity}}>Log
            activity</Button>
          {{#unless (eq @model.stage 'closed won')}}<Button
              @appearance='accent'
              {{on 'click' this.closeWon}}
            >Close won</Button>{{/unless}}
        </:actions>
        <:main>
          <h2 class='h'>Stage</h2>
          <StepList @steps={{this.stages}} />
          <RelatedList
            @title='Activity'
            @cards={{this.activityCards}}
            @empty='No activity logged'
          />
        </:main>
        <:value as |row|>
          {{#if (eq row.value '@account')}}
            <@fields.account @format='atom' @displayContainer={{false}} />
          {{else if (eq row.value '@owner')}}
            <@fields.owner @format='atom' @displayContainer={{false}} />
          {{else}}{{row.value}}{{/if}}
        </:value>
      </RecordPage>
      <style scoped>
        .h {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          font-size: 0.75rem;
          font-weight: 700;
          border-block-end: 1px solid var(--border);
        }
      </style>
    </template>
  };
}
