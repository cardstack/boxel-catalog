import {
  CardDef,
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/boxel-ui/components';
import { not } from '@cardstack/boxel-ui/helpers';

import StatusField, { nextStatuses, statusOption } from '../status';
import PriorityField from '../../priority/priority';
import DueDateField from '../../due-date/due-date';
import CreatedAtField from '../../created-at/created-at';

/**
 * One record wearing all four record fields at once, so a reader sees how
 * they compose and which moves the Status graph allows from here.
 */
export class TaskRecordExample extends CardDef {
  static displayName = 'Task Record Example';

  @field title = contains(StringField);
  @field status = contains(StatusField);
  @field priority = contains(PriorityField);
  @field dueDate = contains(DueDateField);
  @field createdAt = contains(CreatedAtField);

  static isolated = class Isolated extends Component<typeof this> {
    get next() {
      return nextStatuses(StatusField, this.args.model.status);
    }
    get isTerminal() {
      return statusOption(StatusField, this.args.model.status)?.terminal;
    }
    move = (value: string) => {
      this.args.model.status = value;
    };

    <template>
      <article class='task'>
        <header>
          <span class='eyebrow'>Record fields</span>
          <h1>{{@model.title}}</h1>
        </header>

        <dl class='facts'>
          <dt>Status</dt>
          <dd><@fields.status /></dd>
          <dt>Priority</dt>
          <dd><@fields.priority /></dd>
          <dt>Due</dt>
          <dd><@fields.dueDate /></dd>
          <dt>Created</dt>
          <dd><@fields.createdAt /></dd>
        </dl>

        <section class='moves'>
          <h2>Allowed moves from {{@model.status}}</h2>
          {{#if this.isTerminal}}
            <p class='hint'>Terminal status: only a deliberate re-open follows.</p>
          {{/if}}
          <div class='buttons'>
            {{#each this.next as |option|}}
              <Button
                @kind='secondary'
                @size='small'
                @disabled={{not @canEdit}}
                {{on 'click' (fn this.move option.value)}}
              >
                {{option.value}}
              </Button>
            {{/each}}
          </div>
          <p class='hint'>The list comes from
            <code>nextStatuses(StatusField, status)</code>; anything not offered
            here is not a legal transition.</p>
        </section>

        <section class='atoms'>
          <h2>In a dense row</h2>
          <div class='row'>
            <@fields.status @format='atom' />
            <@fields.priority @format='atom' />
            <@fields.dueDate @format='atom' />
            <@fields.createdAt @format='atom' />
          </div>
        </section>
      </article>
      <style scoped>
        .task {
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 640px;
          margin-inline: auto;
          padding: var(--boxel-sp-lg);
          font-family: var(--font-sans, var(--boxel-font-family));
          color: var(--foreground, var(--boxel-dark));
        }
        header {
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .facts {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: var(--boxel-sp-xs) var(--boxel-sp);
          margin: 0;
          padding: var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
        }
        dt {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
        }
        .buttons {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .hint {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
        }
      </style>
    </template>
  };
}
