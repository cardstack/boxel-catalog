import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import EmailField from 'https://cardstack.com/base/email';
import PhoneNumberField from 'https://cardstack.com/base/phone-number';
import enumField from 'https://cardstack.com/base/enum';
import { guidFor } from '@ember/object/internals';
import TargetIcon from '@cardstack/boxel-icons/target';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { Campaign } from './campaign';
import { hasNumber, labelProgress } from './utils';

const LeadStatusField = enumField(StringField, {
  options: ['new', 'contacted', 'qualified', 'converted', 'disqualified'],
  displayName: 'Lead Status',
});

const LeadSourceField = enumField(StringField, {
  options: [
    'website',
    'referral',
    'webinar',
    'ad',
    'event',
    'cold outreach',
    'other',
  ],
  displayName: 'Lead Source',
});

// Status hues for the pill. Qualified and converted are good news and
// disqualified bad news; new is the one open state that stands out, so it
// takes a category hue rather than a status one; contacted is neutral.
const STATUS_HUE: Record<string, Hue> = {
  new: 'blue',
  contacted: 'slate',
  qualified: 'green',
  converted: 'green',
  disqualified: 'red',
};

function statusHue(status: string | undefined): Hue {
  return (status && STATUS_HUE[status]) || 'slate';
}

export class Lead extends CardDef {
  static displayName = 'Lead';
  static icon = TargetIcon;

  @field name = contains(StringField);
  @field company = contains(StringField);
  @field email = contains(EmailField);
  @field phone = contains(PhoneNumberField);
  @field source = contains(LeadSourceField);
  @field status = contains(LeadStatusField);
  @field score = contains(NumberField);
  // Which specific activity produced this lead. `source` names the channel;
  // this names the campaign. The lead points at the campaign, never the
  // reverse — a campaign's lead count is a query, not a stored list.
  @field campaign = linksTo(Campaign);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Lead) {
      return this.name?.trim()?.length
        ? this.name
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Lead> {
    <template>
      <span class='lead-atom'>
        <TargetIcon class='la-icon' />
        <span class='la-name'>{{if
            @model.name
            @model.name
            'Unnamed Lead'
          }}</span>
      </span>
      <style scoped>
        .lead-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .la-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .la-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Lead> {
    <template>
      <div class='lead-row'>
        <TargetIcon class='icon' />
        <div class='info'>
          <span class='name'>{{if @model.name @model.name 'Unnamed'}}</span>
          {{#if @model.company}}
            <span class='meta'>{{@model.company}}</span>
          {{/if}}
        </div>
        <span class='score-block'>
          {{#if (hasNumber @model.score)}}
            <span class='score'>{{@model.score}}</span>
            <span class='score-caption'>score</span>
          {{else}}
            <span class='score score-none'>—</span>
          {{/if}}
        </span>
        <span class='status-col'>
          <StatePill
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
          />
        </span>
      </div>
      <style scoped>
        .lead-row {
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
        .score-block {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.0625rem;
          width: 3.25rem;
          flex-shrink: 0;
        }
        .score-none {
          color: var(--muted-foreground);
        }
        .status-col {
          display: flex;
          justify-content: center;
          width: 8.5rem;
          flex-shrink: 0;
        }
        .score {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: 0.8125rem;
          line-height: 1;
        }
        .score-caption {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Lead> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Lead';
    }
    <template>
      <div class='fitted'>
        <div class='top'>
          <TargetIcon class='icon' />
          <StatePill
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
          />
        </div>
        <span class='name'>{{this.name}}</span>
        {{#if @model.company}}
          <span class='meta line-company'>{{@model.company}}</span>
        {{/if}}
        {{#if (hasNumber @model.score)}}
          <span class='meta line-score'>Score {{@model.score}}</span>
        {{/if}}
        {{#if @model.source}}
          <span class='meta line-source'>via {{@model.source}}</span>
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
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .line-company,
        .line-score,
        .line-source {
          display: none;
        }
        @container fitted-card (min-height: 65px) {
          .line-company {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-score {
            display: block;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-source {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Lead> {
    get name() {
      return this.args.model?.name?.trim() || 'Unnamed Lead';
    }
    scoreLabelId = `${guidFor(this)}-score-label`;
    get clampedScore() {
      return Math.max(0, Math.min(100, this.args.model?.score ?? 0));
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.email) rows.push({ key: 'Email', value: 'email' });
      if (m?.phone) rows.push({ key: 'Phone', value: 'phone' });
      if (m?.source) rows.push({ key: 'Source', value: 'source' });
      return rows;
    }
    <template>
      <article class='lead-page'>
        <header class='lh'>
          <div class='lh-id'>
            <p class='doc-kind'>Lead</p>
            <h1>{{this.name}}</h1>
            {{#if @model.company}}
              <p class='company'>{{@model.company}}</p>
            {{/if}}
          </div>
          <StatePill
            class='status'
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
          />
        </header>
        {{#if (hasNumber @model.score)}}
          <section class='score-panel'>
            <span class='score-value'>{{@model.score}}</span>
            <span id={{this.scoreLabelId}} class='score-label'>lead score</span>
            <ProgressBar
              class='score-bar'
              @value={{this.clampedScore}}
              @max={{100}}
              @steps={{false}}
              {{labelProgress this.scoreLabelId}}
            />
          </section>
        {{/if}}
        <section class='panel'>
          <h2>Details</h2>
          <KeyValue class='details' @items={{this.details}}>
            <:value as |row|>
              {{#if (eq row.value 'email')}}
                <@fields.email />
              {{else if (eq row.value 'phone')}}
                <@fields.phone />
              {{else}}
                <span class='cap'>{{@model.source}}</span>
              {{/if}}
            </:value>
          </KeyValue>
        </section>
      </article>
      <style scoped>
        .lead-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .lh {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
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
          line-height: 1.1;
        }
        .company {
          margin: 0.25rem 0 0;
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .status {
          margin-bottom: 0.25rem;
        }
        .score-panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
          display: grid;
          grid-template-columns: auto 1fr;
          align-items: baseline;
          gap: 0.25rem 0.75rem;
        }
        .score-value {
          font-size: 2rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          line-height: 1;
        }
        .score-label {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI ProgressBar paints its fill with --primary, which measures
           1.20:1 against the track on a light page; the ink token is the
           guaranteed pair. */
        .score-bar {
          --primary: var(--primary-ink);
          grid-column: 1 / -1;
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
        .cap {
          text-transform: capitalize;
        }
      </style>
    </template>
  };
}
