import GlimmerComponent from '@glimmer/component';
import { Board } from '@cardstack/pretui/components/board';
import type {
  KanbanColumnConfig,
  KanbanPlacement,
} from '@cardstack/boxel-ui/components';
import { canTransition } from '@cardstack/catalog/fields/status/status';

import { WorkOrder } from '../work-order';
import { WorkOrderStatusField } from '../maintenance-vocabulary';
import { WO_STATUS_LABEL, woDot } from './status-dot';

const COLUMNS: KanbanColumnConfig[] = Object.entries(WO_STATUS_LABEL).map(
  ([key, label], i) => ({
    key,
    label,
    color: 'var(--muted-foreground)',
    wipLimit: null,
    collapsed: false,
    sortOrder: i + 1,
  }),
);

interface Signature {
  Args: {
    workOrders: WorkOrder[];
    onOpen?: (workOrder: WorkOrder) => void;
    onChange?: (workOrder: WorkOrder) => void;
  };
  Element: HTMLElement;
}

/**
 * The Work Order kanban on Pret UI Board. A column is a status; a drop
 * writes the new status only when the status graph allows the move, and
 * placements are derived from `wo.status`, so a refused move snaps back.
 */
export class WorkOrderBoard extends GlimmerComponent<Signature> {
  columns = COLUMNS;

  get list(): WorkOrder[] {
    return (this.args.workOrders ?? []).filter(Boolean);
  }

  get placements(): KanbanPlacement[] {
    return this.list.map((wo, index) => ({
      index,
      columnId: wo.status ?? 'requested',
      sortOrder: wo.daySequence ?? index,
    }));
  }

  at = (index: number) => this.list[index];

  handleChange = (next: KanbanPlacement[]) => {
    for (let p of next) {
      let wo = this.list[p.index];
      if (!wo || wo.status === p.columnId || !p.columnId) continue;
      if (!canTransition(WorkOrderStatusField, wo.status, p.columnId)) continue;
      (wo as any).status = p.columnId;
      if (p.columnId === 'scheduled' && !wo.scheduledFor) {
        wo.scheduledFor = new Date();
      }
      this.args.onChange?.(wo);
    }
  };

  handleOpen = (index: number) => {
    let wo = this.list[index];
    if (wo) this.args.onOpen?.(wo);
  };

  <template>
    <div class='wob' ...attributes>
      <Board
        @boardLabel='Work orders'
        @columns={{this.columns}}
        @placements={{this.placements}}
        @onChange={{this.handleChange}}
        @onOpen={{this.handleOpen}}
      >
        <:card as |placement|>
          {{#let (this.at placement.index) as |wo|}}
            <div class='wo' style={{woDot wo.status}}>
              <span class='ref'><span
                  class='dot'
                ></span>{{wo.identifier.value}}</span>
              <span class='ttl'>{{wo.title}}</span>
              <span class='muted'>{{wo.assetName}}</span>
            </div>
          {{/let}}
        </:card>
      </Board>
    </div>
    <style scoped>
      .wob {
        block-size: 100%;
        min-block-size: 24rem;
      }
      .wo {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xs);
        min-width: 0;
      }
      .ref {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--dot);
      }
      .ttl {
        font-weight: 600;
        font-size: var(--boxel-font-size-sm);
      }
      .muted {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
      }
    </style>
  </template>
}

export default WorkOrderBoard;
