import {
  CardDef,
  Component,
  field,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import TableIcon from '@cardstack/boxel-icons/table';
import { eq } from '@cardstack/boxel-ui/helpers';

import { Table, type TableColumn } from '../table';
import { Board, type BoardColumn } from '../board';
import { StatePill } from '../state-pill';
import StatusField, {
  canTransition,
  statusHue,
} from '../../fields/status/status';
import PriorityField, { priorityOption } from '../../fields/priority/priority';
import { dueness } from '../../fields/due-date/due-date';
import { TaskRecordExample } from '../../fields/status/example/task-record-example';

const STRIPE: Record<string, string> = {
  overdue: 'sev-over',
  today: 'sev-note',
  soon: 'sev-note',
};

function task(item: CardDef): TaskRecordExample {
  return item as TaskRecordExample;
}

function statusOf(item: CardDef) {
  return task(item).status;
}

function priorityOf(item: CardDef) {
  return task(item).priority;
}

function statusHueOf(item: CardDef) {
  return statusHue(StatusField, task(item).status);
}

function priorityHueOf(item: CardDef) {
  return priorityOption(PriorityField, task(item).priority)?.hue;
}

/**
 * The same task records shown two ways: a Table with Status and Priority pills
 * yielded into cells, and a Board whose columns are the Status field's option
 * set and whose moves are gated by its transition graph.
 */
export class RecordViewsExample extends CardDef {
  static displayName = 'Record Views Example';
  static icon = TableIcon;

  @field records = linksToMany(TaskRecordExample);

  static isolated = class Isolated extends Component<typeof this> {
    columns: TableColumn[] = [
      { key: 'title', label: 'Task', value: (t) => task(t).title },
      { key: 'status', label: 'Status', sortValue: (t) => task(t).status },
      {
        key: 'priority',
        label: 'Priority',
        showAbove: 480,
        sortValue: (t) => task(t).priority,
      },
      {
        key: 'due',
        label: 'Due',
        showAbove: 640,
        value: (t) => task(t).dueDate?.toLocaleDateString(),
        sortValue: (t) => task(t).dueDate?.getTime(),
      },
      {
        key: 'created',
        label: 'Created',
        showAbove: 900,
        value: (t) => task(t).createdAt?.toLocaleDateString(),
        sortValue: (t) => task(t).createdAt?.getTime(),
      },
    ];

    boardColumns: BoardColumn[] = StatusField.statusOptions.map((o) => ({
      key: o.value,
      label: o.label ?? o.value,
    }));

    get items(): CardDef[] {
      return ((this.args.model.records ?? []) as CardDef[]).filter(Boolean);
    }

    rowClass = (item: CardDef) => {
      let state = dueness(task(item).dueDate);
      return state ? STRIPE[state] : undefined;
    };

    columnKeyFor = (item: CardDef) => task(item).status;

    onMove = (item: CardDef, key: string) => {
      if (canTransition(StatusField, task(item).status, key)) {
        task(item).status = key;
      }
    };

    <template>
      <article class='views'>
        <section>
          <h2>Table</h2>
          <Table
            @items={{this.items}}
            @columns={{this.columns}}
            @rowClass={{this.rowClass}}
            @pageSize={{5}}
            @caption='Tasks'
            @emptyMessage='No tasks linked'
          >
            <:cell as |item column|>
              {{#if (eq column.key 'status')}}
                <StatePill
                  @label={{statusOf item}}
                  @hue={{statusHueOf item}}
                  @dot={{true}}
                />
              {{else if (eq column.key 'priority')}}
                <StatePill
                  @label={{priorityOf item}}
                  @hue={{priorityHueOf item}}
                />
              {{/if}}
            </:cell>
          </Table>
        </section>

        <section class='board-section'>
          <h2>Board</h2>
          <p class='hint'>Columns are the Status field's option set. A drag that
            the transition graph does not allow snaps back.</p>
          <Board
            @boardLabel='Tasks'
            @items={{this.items}}
            @columns={{this.boardColumns}}
            @columnKeyFor={{this.columnKeyFor}}
            @onMove={{this.onMove}}
          />
        </section>
      </article>
      <style scoped>
        .views {
          display: grid;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          font-family: var(--font-sans, var(--boxel-font-family));
          color: var(--foreground, var(--boxel-dark));
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .hint {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .board-section {
          min-height: 420px;
          display: grid;
          grid-template-rows: auto auto 1fr;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='rv-fitted'>
        <TableIcon class='icon' />
        <span class='name'>{{@model.cardInfo.name}}</span>
      </div>
      <style scoped>
        .rv-fitted {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          flex: none;
        }
      </style>
    </template>
  };
}
