import { CardDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { KeyValue } from '@cardstack/pretui/components/key-value';

import CountField from '../count-field';
import CreatedAtField from '../../created-at/created-at';
import UpdatedAtField from '../../updated-at/updated-at-field';

const FACTS = [
  { key: 'Sessions logged', value: 'sessions' },
  { key: 'Page views', value: 'views' },
  { key: 'Shares', value: 'shares' },
  { key: 'Created', value: 'createdAt' },
  { key: 'Updated', value: 'updatedAt' },
];

/**
 * One record wearing the Count and timestamp fields, so a reader sees a large
 * count, a zero and an unset count side by side, and the two stamps in full
 * and in a dense row.
 */
export class ActivityLogExample extends CardDef {
  static displayName = 'Activity Log Example';

  @field title = contains(StringField);
  @field sessions = contains(CountField);
  @field views = contains(CountField);
  @field shares = contains(CountField);
  @field createdAt = contains(CreatedAtField);
  @field updatedAt = contains(UpdatedAtField);

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='log'>
        <header>
          <span class='eyebrow'>Count and timestamps</span>
          <h1>{{@model.title}}</h1>
        </header>

        <KeyValue @items={{FACTS}}>
          <:value as |item|>
            {{#if (eqKey item.value 'sessions')}}
              <@fields.sessions />
            {{else if (eqKey item.value 'views')}}
              <@fields.views />
            {{else if (eqKey item.value 'shares')}}
              <@fields.shares />
            {{else if (eqKey item.value 'createdAt')}}
              <@fields.createdAt />
            {{else}}
              <@fields.updatedAt />
            {{/if}}
          </:value>
        </KeyValue>

        <section>
          <h2>In a dense row</h2>
          <div class='row'>
            <@fields.views @format='atom' />
            <@fields.shares @format='atom' />
            <@fields.updatedAt @format='atom' />
          </div>
        </section>
      </article>
      <style scoped>
        .log {
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 40rem;
          margin-inline: auto;
          padding: var(--boxel-sp-lg);
          color: var(--foreground);
        }
        header {
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .eyebrow {
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
          font-size: var(--boxel-font-size-xl);
          line-height: 1.15;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          color: var(--muted-foreground);
        }
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };
}

function eqKey(a: string, b: string): boolean {
  return a === b;
}
