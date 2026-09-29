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
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Account } from './account';
import { User } from './user';
import { isAmount } from './utils';
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
      <span class='opp-atom'>
        <TrendingUpIcon class='oa-icon' />
        <span class='oa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .opp-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .oa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .oa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Opportunity> {
    <template>
      <div class='opp-row'>
        <TrendingUpIcon class='icon' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.account.name}}
            <span class='meta'>{{@model.account.name}}</span>
          {{/if}}
        </div>
        {{#if (isAmount @model.value.amount)}}
          <FormatNumber
            class='value'
            @value={{@model.value.amount}}
            @style='currency'
            @currency={{@model.value.currency.code}}
            @locale='en-US'
            @maximumFractionDigits={{unless @model.value.currency.code 2}}
          />
        {{/if}}
        <StatePill @label={{@model.stage}} @hue={{stageHue @model.stage}} />
      </div>
      <style scoped>
        .opp-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: 0.875rem;
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .value {
          font-weight: 700;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Opportunity> {
    get probabilityDisplay() {
      let p = this.args.model?.effectiveProbability;
      return typeof p === 'number' ? `${p}%` : '';
    }
    get isOpen() {
      let stage = this.args.model?.stage;
      return stage !== 'closed won' && stage !== 'closed lost';
    }
    get ageDisplay() {
      let days = this.args.model?.daysInStage;
      if (!this.isOpen || !days) return '';
      return days === 1 ? '1 day in stage' : `${days} days in stage`;
    }
    // Fitted formats take no arguments, so the threshold is the block's call
    // rather than the consumer's. Seven days is the spec's default.
    get isStuck() {
      return this.isOpen && (this.args.model?.daysInStage ?? 0) >= 7;
    }
    <template>
      <div class='fitted {{if this.isStuck "stuck"}}'>
        <div class='top'>
          <TrendingUpIcon class='icon' />
          <StatePill
            class='stage'
            @label={{@model.stage}}
            @hue={{stageHue @model.stage}}
          />
          {{#if this.isStuck}}
            <StatePill
              class='stuck-flag'
              title={{this.ageDisplay}}
              @label='stalled'
              @hue='red'
            />
          {{/if}}
        </div>
        <span class='name'>{{@model.cardTitle}}</span>
        {{#if (isAmount @model.value.amount)}}
          <FormatNumber
            class='figure'
            @value={{@model.value.amount}}
            @style='currency'
            @currency={{@model.value.currency.code}}
            @locale='en-US'
            @maximumFractionDigits={{unless @model.value.currency.code 2}}
          />
        {{/if}}
        {{#if @model.account.name}}
          <span class='meta line-account'>{{@model.account.name}}</span>
        {{/if}}
        {{#if this.probabilityDisplay}}
          <span class='meta line-prob'>{{this.probabilityDisplay}}
            likely{{#if @model.closeDate}}
              · closes
              <@fields.closeDate />{{/if}}</span>
        {{/if}}
        {{#if this.ageDisplay}}
          <span class='meta line-age'>{{this.ageDisplay}}</span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        .top {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .icon {
          width: 1.125rem;
          height: 1.125rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .figure {
          font-weight: 700;
          font-size: 0.9375rem;
          flex-shrink: 0;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex-shrink: 0;
        }
        .stage {
          min-width: 0;
        }
        .line-account,
        .line-prob,
        .line-age {
          display: none;
        }
        .stuck-flag {
          margin-left: auto;
          flex-shrink: 0;
        }
        /* A stalled deal reads as needing attention at every size, including
           the badge tier where the age line itself is hidden. */
        .fitted.stuck {
          box-shadow: inset 0.1875rem 0 0 var(--destructive);
        }
        /* Short cells (strips, badges, the edit-form link pill): a column
           cannot fit, and flex would shear the one shrinkable row mid-glyph
           (Rule 1: hide whole rows, never shrink one into a clip). Below
           90px the card re-lays as ONE centered row. */
        @container fitted-card (max-height: 90px) {
          .fitted {
            flex-direction: row;
            align-items: center;
            gap: 0.5rem;
            padding: 0.25rem 0.75rem;
          }
          .top {
            display: contents;
          }
          .name {
            flex: 0 1 auto;
            min-width: 0;
          }
          .figure {
            margin-left: auto;
            font-size: 0.8125rem;
          }
          .stage {
            order: 4;
          }
          .stuck-flag {
            order: 5;
            margin-left: 0;
          }
        }
        /* Narrow badge: name (and the stalled alert) are the survivors —
           data is all-or-nothing, a hidden figure beats a truncated one. */
        @container fitted-card (max-height: 90px) and (max-width: 220px) {
          .figure,
          .stage {
            display: none;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-account {
            display: block;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-prob,
          .line-age {
            display: block;
          }
        }
      </style>
    </template>
  };

  // `BaseDefComponent` keeps a subclass's isolated view (Deal) assignable.
  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof Opportunity
  > {
    get weighted(): number | undefined {
      let amount = this.args.model?.value?.amount;
      let p = this.args.model?.effectiveProbability;
      if (!isAmount(amount) || typeof p !== 'number') return undefined;
      return ((amount as number) * p) / 100;
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
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.account) rows.push({ key: 'Account', value: 'account' });
      if (m?.owner) rows.push({ key: 'Owner', value: 'owner' });
      if (m?.closeDate) rows.push({ key: 'Close date', value: 'closeDate' });
      return rows;
    }
    <template>
      <article class='opp-page'>
        <header class='oh'>
          <div class='oh-id'>
            <p class='doc-kind'>{{@model.constructor.displayName}}</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          {{#if (isAmount @model.value.amount)}}
            <div class='value-block'>
              <FormatNumber
                class='value'
                @value={{@model.value.amount}}
                @style='currency'
                @currency={{@model.value.currency.code}}
                @locale='en-US'
                @maximumFractionDigits={{unless @model.value.currency.code 2}}
              />
              {{#if (isAmount this.weighted)}}
                <span class='weighted'><FormatNumber
                    @value={{this.weighted}}
                    @style='currency'
                    @currency={{@model.value.currency.code}}
                    @locale='en-US'
                    @maximumFractionDigits={{unless
                      @model.value.currency.code
                      2
                    }}
                  />
                  weighted ·
                  {{@model.effectiveProbability}}% ({{this.probabilitySource}})</span>
              {{/if}}
            </div>
          {{/if}}
        </header>

        <StepList
          class='stepper'
          @steps={{this.stages}}
          @variant='track'
          @label='Pipeline stage'
        />

        <section class='panel'>
          <h2>Details</h2>
          <KeyValue class='details' @items={{this.details}}>
            <:value as |row|>
              {{#if (eq row.value 'account')}}
                <div class='acct'><@fields.account @format='embedded' /></div>
              {{else if (eq row.value 'owner')}}
                <@fields.owner @format='atom' />
              {{else}}
                <@fields.closeDate />
              {{/if}}
            </:value>
          </KeyValue>
        </section>
      </article>
      <style scoped>
        .opp-page {
          max-width: 46rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }
        .oh {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1rem;
          flex-wrap: wrap;
        }
        .doc-kind {
          margin: 0 0 0.125rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          font-size: 1.75rem;
          line-height: 1.1;
        }
        .value-block {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.125rem;
        }
        .value {
          font-size: 1.5rem;
          font-weight: 700;
          line-height: 1.1;
        }
        .weighted {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        /* Pret UI StepList, track variant. Its knobs put every mark on a
           guaranteed pair with the page: the current step's number takes
           --foreground, and its bar, the complete check and the lost step's
           label and glyph take ink tokens. The defaults measure 1.31:1 for
           the current bar (--primary on a light page) and 1.87:1 for the
           current number (--primary-foreground with no disc behind it, on a
           dark page). */
        .stepper {
          --pretui-step-current-marker-fg: var(--foreground);
          --pretui-step-current-bar: var(--primary-ink);
          --pretui-step-complete-marker-fg: var(--success-ink);
          --pretui-step-error-tone: var(--destructive-ink);
          --pretui-step-error-marker-fg: var(--destructive-ink);
          text-transform: capitalize;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 0.75rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue at the panel's text size and column gap */
        .details {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1.25rem;
        }
        .acct {
          flex: 1;
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          max-width: 24rem;
        }
      </style>
    </template>
  };
}
