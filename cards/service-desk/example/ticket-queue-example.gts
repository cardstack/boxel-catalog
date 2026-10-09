import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import InboxIcon from '@cardstack/boxel-icons/inbox';

import { Ticket } from '@cardstack/catalog/cards/service-desk/ticket';
import { QueueView } from '../components/queue-view';
import { WorkRail } from '../components/work-rail';
import type { Lens } from '../utils/queue-lens';

// Usage page for the ticket queue blocks: the list on its own, with its stat
// strip, then the rail driving the same list, the way a desk lays them side
// by side.
class TicketQueueExampleIsolated extends Component<typeof TicketQueueExample> {
  @tracked lens: Lens = 'open';
  @tracked queueName: string | undefined;

  get tickets(): Ticket[] {
    return (this.args.model.tickets ?? []).filter(Boolean) as Ticket[];
  }

  setLens = (lens: Lens) => (this.lens = lens);
  setQueue = (name: string | undefined) => (this.queueName = name);
  clearQueue = () => (this.queueName = undefined);

  <template>
    <div class='demo'>
      <section>
        <h2>Queue View on its own</h2>
        <QueueView @tickets={{this.tickets}} @context={{@context}} />
      </section>
      <section>
        <h2>Work Rail driving the Queue View</h2>
        <div class='split'>
          <WorkRail
            @tickets={{this.tickets}}
            @lens={{this.lens}}
            @onLens={{this.setLens}}
            @queueName={{this.queueName}}
            @onQueue={{this.setQueue}}
          />
          <QueueView
            @tickets={{this.tickets}}
            @lens={{this.lens}}
            @onLens={{this.setLens}}
            @queueName={{this.queueName}}
            @onClearQueue={{this.clearQueue}}
            @context={{@context}}
          />
        </div>
      </section>
    </div>
    <style scoped>
      .demo {
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-xl);
      }
      section {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .split {
        display: grid;
        grid-template-columns: 14rem minmax(0, 1fr);
        gap: var(--boxel-sp);
        align-items: start;
      }
      h2 {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export class TicketQueueExample extends CardDef {
  static displayName = 'Ticket Queue Example';
  static icon = InboxIcon;

  @field tickets = linksToMany(() => Ticket);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TicketQueueExample) {
      return 'Ticket queue blocks over the open tickets';
    },
  });

  static isolated = TicketQueueExampleIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <InboxIcon class='ic' />
        <span class='name'>{{@model.cardTitle}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .ic {
          width: 1.125rem;
          height: 1.125rem;
          flex: none;
        }
        .name {
          font-weight: 600;
        }
      </style>
    </template>
  };
}
