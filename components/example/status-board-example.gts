import {
  CardDef,
  Component,
  field,
  linksToMany,
} from '@cardstack/base/card-api';
import SquareKanbanIcon from '@cardstack/boxel-icons/square-kanban';
import { tracked } from '@glimmer/tracking';

import { Task, TaskStatusField } from '../../cards/tasks/task';
import { StatusBoard } from '../status-board';

class StatusBoardExampleIsolated extends Component<typeof StatusBoardExample> {
  @tracked rejection: string | undefined;

  statusOf = (item: CardDef) => (item as Task).status;

  // Writes the status straight onto the task so the example can be played
  // with; an app routes the move through its own status-writing command.
  move = (item: CardDef, statusValue: string) => {
    this.rejection = undefined;
    (item as Task).status = statusValue;
  };

  reject = (item: CardDef, from: string | undefined, to: string) => {
    this.rejection = `${(item as Task).cardTitle}: ${from ?? 'unset'} → ${to} is not a transition Task allows.`;
  };

  <template>
    <div class='demo'>
      <StatusBoard
        @boardLabel='Tasks by status'
        @items={{@model.records}}
        @statusField={{TaskStatusField}}
        @statusOf={{this.statusOf}}
        @onMove={{this.move}}
        @onRejected={{this.reject}}
      />
      {{#if this.rejection}}
        <p class='rejection' role='status'>{{this.rejection}}</p>
      {{/if}}
    </div>
    <style scoped>
      .rejection {
        margin: var(--boxel-sp-sm) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--destructive, var(--boxel-danger));
      }
      .demo {
        height: 100%;
        min-height: 480px;
        padding: 1rem;
        box-sizing: border-box;
      }
    </style>
  </template>
}

/**
 * A campaign's tasks laid out by the Task lifecycle. Dragging a card moves it
 * when Task's transition graph allows the move and explains the refusal when
 * it does not, e.g. dragging Done back to Not Started.
 */
export class StatusBoardExample extends CardDef {
  static displayName = 'Status Board Example';
  static icon = SquareKanbanIcon;

  @field records = linksToMany(() => Task);

  static isolated = StatusBoardExampleIsolated;
}
