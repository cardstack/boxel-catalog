import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import { guidFor } from '@ember/object/internals';
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import NumberField from 'https://cardstack.com/base/number';
import DateField from 'https://cardstack.com/base/date';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import enumField from 'https://cardstack.com/base/enum';
import SpeakerphoneIcon from '@cardstack/boxel-icons/speakerphone';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { Money } from './money';
import { hasNumber, labelProgress } from './utils';

// Mirrors the channels Lead.source names, so a lead's channel and the specific
// activity it came from describe the same thing at two levels of detail.
const CampaignTypeField = enumField(StringField, {
  options: ['webinar', 'ad', 'event', 'email', 'content', 'other'],
  displayName: 'Campaign Type',
});

const CampaignStatusField = enumField(StringField, {
  options: ['planned', 'running', 'completed', 'canceled'],
  displayName: 'Campaign Status',
});

// Status hues for the pill: a live campaign is good news, a canceled one bad
// news, a planned one still needs attention; a completed one is neutral.
const STATUS_HUE: Record<string, Hue> = {
  planned: 'amber',
  running: 'green',
  completed: 'slate',
  canceled: 'red',
};

function statusHue(status: string | undefined): Hue {
  return (status && STATUS_HUE[status]) || 'slate';
}

export class Campaign extends CardDef {
  static displayName = 'Campaign';
  static icon = SpeakerphoneIcon;

  @field name = contains(StringField);
  @field campaignType = contains(CampaignTypeField);
  @field status = contains(CampaignStatusField);
  @field startDate = contains(DateField);
  @field endDate = contains(DateField);
  @field budget = contains(AmountWithCurrency);
  @field spend = contains(AmountWithCurrency);

  @field budgetUsedPercent = contains(NumberField, {
    computeVia: function (this: Campaign) {
      let budget = this.budget?.amount ?? 0;
      let spend = this.spend?.amount ?? 0;
      if (!budget) return 0;
      return Math.round((spend / budget) * 100);
    },
  });

  @field isOverBudget = contains(BooleanField, {
    computeVia: function (this: Campaign) {
      let budget = this.budget?.amount ?? 0;
      return budget > 0 && (this.spend?.amount ?? 0) > budget;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Campaign) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Campaign> {
    <template>
      <span class='campaign-atom'>
        <SpeakerphoneIcon class='ca-icon' />
        <span class='ca-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .campaign-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .ca-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .ca-name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Campaign> {
    <template>
      <div class='campaign'>
        <SpeakerphoneIcon class='icon' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.campaignType}}
            <span class='meta'>{{@model.campaignType}}</span>
          {{/if}}
        </div>
        <Money
          class='figure'
          @amount={{@model.spend.amount}}
          @code={{@model.spend.currency.code}}
        />
        <span class='status-col'>
          <StatePill
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
          />
        </span>
      </div>
      <style scoped>
        .campaign {
          display: flex;
          align-items: center;
          gap: 0.625rem;
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
          text-transform: capitalize;
        }
        .figure {
          font-weight: 600;
        }
        /* Constant-width slot so rows line up whatever the status. */
        .status-col {
          display: flex;
          justify-content: center;
          width: 6rem;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Campaign> {
    <template>
      <div class='fitted'>
        <div class='top'>
          <SpeakerphoneIcon class='icon' />
          <StatePill
            class='status'
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
          />
        </div>
        <span class='name'>{{@model.cardTitle}}</span>
        {{#if (hasNumber @model.spend.amount)}}
          <Money
            class='figure'
            @amount={{@model.spend.amount}}
            @code={{@model.spend.currency.code}}
          />
        {{/if}}
        {{#if @model.campaignType}}
          <span class='meta line-type'>{{@model.campaignType}}</span>
        {{/if}}
        {{#if @model.budget.amount}}
          <span
            class='meta line-budget {{if @model.isOverBudget "over"}}'
          >{{@model.budgetUsedPercent}}% of
            <Money
              @amount={{@model.budget.amount}}
              @code={{@model.budget.currency.code}}
            /></span>
        {{/if}}
        {{#if @model.endDate}}
          <span class='meta line-dates'>Ran
            <@fields.startDate />
            –
            <@fields.endDate /></span>
        {{else if @model.startDate}}
          <span class='meta line-dates'>Since <@fields.startDate /></span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          padding: 0.625rem 0.75rem;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          overflow: hidden;
          color: var(--foreground);
        }
        .top {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .icon {
          width: 1rem;
          height: 1rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .status {
          margin-left: auto;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .figure {
          font-weight: 700;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          text-transform: capitalize;
        }
        .over {
          color: var(--destructive-ink);
          font-weight: 600;
        }
        .line-type,
        .line-budget,
        .line-dates {
          display: none;
        }
        /* Each taller tier adds a line, so a tile fills its box. */
        @container fitted-card (min-height: 170px) {
          .line-type,
          .line-budget {
            display: block;
          }
          .line-type {
            margin-top: auto;
          }
        }
        @container fitted-card (min-height: 215px) {
          .line-dates {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Campaign> {
    noteId = `${guidFor(this)}-budget-note`;
    get barValue() {
      return Math.min(this.args.model?.budgetUsedPercent ?? 0, 100);
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.startDate) rows.push({ key: 'Started', value: 'startDate' });
      if (m?.endDate) rows.push({ key: 'Ended', value: 'endDate' });
      return rows;
    }
    <template>
      <article class='campaign-page'>
        <header class='ch'>
          <div class='ch-id'>
            <p class='doc-kind'>Campaign</p>
            <h1>{{@model.cardTitle}}</h1>
            <p class='status-line'>{{@model.campaignType}}{{#if @model.status}}
                ·
                {{@model.status}}{{/if}}</p>
          </div>
        </header>

        {{#if (hasNumber @model.budget.amount)}}
          <section class='panel'>
            <h2>Budget</h2>
            <div class='spend-row'>
              <Money
                class='spend'
                @amount={{@model.spend.amount}}
                @code={{@model.spend.currency.code}}
              />
              <span class='of'>of
                <Money
                  @amount={{@model.budget.amount}}
                  @code={{@model.budget.currency.code}}
                /></span>
            </div>
            <ProgressBar
              class='bar {{if @model.isOverBudget "bar-over"}}'
              @value={{this.barValue}}
              @max={{100}}
              @steps={{false}}
              {{labelProgress this.noteId}}
            />
            <p
              id={{this.noteId}}
              class='bar-note {{if @model.isOverBudget "over"}}'
            >
              {{@model.budgetUsedPercent}}% spent{{#if @model.isOverBudget}}
                — over budget{{/if}}
            </p>
          </section>
        {{/if}}

        <section class='panel'>
          <h2>Details</h2>
          <KeyValue class='details' @items={{this.details}}>
            <:value as |row|>
              {{#if (eq row.value 'startDate')}}
                <@fields.startDate />
              {{else}}
                <@fields.endDate />
              {{/if}}
            </:value>
          </KeyValue>
          <p class='hint'>Leads attributed to this campaign are counted by
            querying leads that point at it — a campaign does not hold a list of
            them.</p>
        </section>
      </article>
      <style scoped>
        .campaign-page {
          max-width: 42rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .ch {
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1.25rem;
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
          font-size: 1.625rem;
        }
        .status-line {
          margin: 0.25rem 0 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          text-transform: capitalize;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          padding: 1rem 1.125rem;
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
        .spend-row {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
        }
        .spend {
          font-size: 1.5rem;
          font-weight: 700;
        }
        .of {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        /* Pret UI ProgressBar paints its fill with --primary, which measures
           1.20:1 against the track on a light page, so the bar takes the ink
           token, and the destructive ink once the campaign is over budget. */
        .bar {
          --primary: var(--primary-ink);
          margin-top: 0.625rem;
        }
        .bar-over {
          --primary: var(--destructive-ink);
        }
        .bar-note {
          margin: 0.375rem 0 0;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .over {
          color: var(--destructive-ink);
          font-weight: 600;
        }
        /* Pret UI KeyValue at the panel's text size and column gap */
        .details {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1rem;
        }
        .hint {
          margin: 0.875rem 0 0;
          font-size: 0.75rem;
          line-height: 1.5;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
