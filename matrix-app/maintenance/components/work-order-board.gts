import GlimmerComponent from '@glimmer/component';

import type { CardDef } from '@cardstack/base/card-api';
import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import { canTransition } from '@cardstack/catalog/fields/status/status';

import { WorkOrder } from '../work-order';
import { WorkOrderStatusField, WO_STATUS_HUE } from '../maintenance-vocabulary';

const COLUMNS: BoardColumn[] = [
  { key: 'requested', label: 'Requested' },
  { key: 'approved', label: 'Approved' },
  { key: 'scheduled', label: 'Scheduled' },
  { key: 'in-progress', label: 'In progress' },
  { key: 'on-hold', label: 'On hold' },
  { key: 'completed', label: 'Completed' },
  { key: 'closed', label: 'Closed' },
  { key: 'cancelled', label: 'Cancelled' },
];

interface Signature {
  Args: {
    workOrders: WorkOrder[];
    onOpen?: (workOrder: WorkOrder) => void;
    onChange?: (workOrder: WorkOrder) => void;
  };
  Element: HTMLElement;
}

/**
 * The Work Order kanban. It wraps the
 * shared catalog `Board` (drag engine + columns are `KanbanPlane`'s) with
 * the WO status graph. `canTransition` (the same status field graph the
 * board.gts status pill uses) refuses an illegal drag — e.g. dragging a
 * card straight from `in-progress` back to `requested` — by simply not
 * writing the new status; the card's column is derived live from
 * `wo.status`, so an unwritten move snaps back on re-render.
 */
export class WorkOrderBoard extends GlimmerComponent<Signature> {
  columns = COLUMNS;

  // The Board hands its items back as CardDef; these are Work Orders.
  columnKeyFor = (item: CardDef) => (item as WorkOrder).status ?? undefined;

  handleMove = (item: CardDef, columnKey: string) => {
    let wo = item as WorkOrder;
    if (!canTransition(WorkOrderStatusField, wo.status, columnKey)) {
      return false;
    }
    (wo as any).status = columnKey;
    if (columnKey === 'scheduled' && !wo.scheduledFor) {
      wo.scheduledFor = new Date();
    }
    this.args.onChange?.(wo);
    return true;
  };

  handleOpen = (item: CardDef) => {
    this.args.onOpen?.(item as WorkOrder);
  };

  hueFor = (status: string) => WO_STATUS_HUE[status] ?? 'slate';

  <template>
    <div class='wob' ...attributes>
      <Board
        @boardLabel='Work Orders'
        @items={{@workOrders}}
        @columns={{this.columns}}
        @columnKeyFor={{this.columnKeyFor}}
        @onMove={{this.handleMove}}
        @onOpen={{this.handleOpen}}
        @hideEmpty={{false}}
      />
    </div>
    <style scoped>
      .wob {
        height: 100%;
        min-height: 24rem;
      }
    </style>
  </template>
}

export default WorkOrderBoard;
