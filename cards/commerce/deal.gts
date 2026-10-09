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
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import {
  Opportunity,
  PIPELINE_STAGES,
} from '@cardstack/catalog/cards/crm/opportunity';
import { Contact } from '@cardstack/catalog/cards/crm/contact';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';

export class Deal extends Opportunity {
  static displayName = 'Deal';
  static icon = BriefcaseIcon;

  @field terms = contains(MarkdownField);
  @field competitors = containsMany(StringField);
  @field decisionMakers = linksToMany(Contact);

  static isolated = class Isolated extends Component<typeof Deal> {
    get weighted(): number | undefined {
      let amount = this.args.model?.value?.amount;
      let p = this.args.model?.effectiveProbability;
      if (typeof amount !== 'number' || typeof p !== 'number') return undefined;
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
    get details(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.account) rows.push({ key: 'Account', value: '' });
      if (m?.owner) rows.push({ key: 'Owner', value: '' });
      if (m?.closeDate) rows.push({ key: 'Close date', value: '' });
      if (m?.competitors?.length) {
        rows.push({ key: 'Against', value: m.competitors.join(', ') });
      }
      return rows;
    }
    <template>
      <article class='deal-page'>
        <header class='dh'>
          <div class='dh-id'>
            <p class='doc-kind'>Deal</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          {{#if (hasNumber @model.value.amount)}}
            <div class='value-block'>
              <Money
                class='value'
                @amount={{@model.value.amount}}
                @code={{@model.value.currency.code}}
              />
              {{#if (hasNumber this.weighted)}}
                <span class='weighted'><Money
                    @amount={{this.weighted}}
                    @code={{@model.value.currency.code}}
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

        {{#if this.details.length}}
          <section class='panel'>
            <h2>Details</h2>
            <KeyValue class='details' @items={{this.details}}>
              <:value as |row|>
                {{#if (eq row.key 'Account')}}
                  <div class='acct'><@fields.account @format='embedded' /></div>
                {{else if (eq row.key 'Owner')}}
                  <@fields.owner @format='atom' />
                {{else if (eq row.key 'Close date')}}
                  <@fields.closeDate />
                {{else}}
                  {{row.value}}
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        {{/if}}

        {{#if @model.decisionMakers.length}}
          <section class='panel'>
            <h2>Decision Makers</h2>
            <div class='people'>
              <@fields.decisionMakers @format='embedded' />
            </div>
          </section>
        {{/if}}

        {{#if @model.terms}}
          <section class='panel'>
            <h2>Terms</h2>
            <div class='terms'><@fields.terms /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .deal-page {
          max-width: 46rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }
        .dh {
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
          margin: 0;
          font-size: 1.75rem;
          line-height: 1.1;
        }
        .value-block {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.125rem;
        }
        .value,
        .weighted {
          font-variant-numeric: tabular-nums;
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
        /* Pret UI StepList, track variant, with every mark on an ink token
           so it holds contrast on the page in both schemes. */
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
        /* Pret UI KeyValue at the panel's text size and column gap, set on
           its own rows so nothing reaches the embedded account card. */
        .details {
          column-gap: 1.25rem;
        }
        .details > :deep(dt),
        .details > :deep(dd) {
          font-size: 0.875rem;
        }
        .acct {
          flex: 1;
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          max-width: 24rem;
        }
        .people > :deep(.contact + .contact) {
          border-top: 1px solid var(--border);
        }
        .terms {
          font-size: 0.875rem;
        }
      </style>
    </template>
  };
}
