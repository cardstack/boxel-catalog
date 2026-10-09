import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import type { CardDef } from '@cardstack/base/card-api';
import type { Opportunity } from '@cardstack/catalog/cards/crm/opportunity';
import {
  PIPELINE_STAGES,
  STAGE_COLORS,
} from '@cardstack/catalog/cards/crm/pipeline-stage-field';

// Sales Pipeline — a Kanban board of Opportunities grouped by pipeline
// stage, with sort and close-window filtering. It takes `@items` from the
// consumer rather than running its own query, so it works the same over a
// live realm search or a fixed list.

export type BoardSortMode = 'value' | 'probability' | 'stale';
export type CloseWindow = 'all' | 'week' | 'month' | 'quarter';

const SORT_OPTIONS = [
  { value: 'value', label: 'Value' },
  { value: 'probability', label: 'Probability' },
  { value: 'stale', label: 'Stalest' },
];

const WINDOW_OPTIONS = [
  { value: 'all', label: 'All' },
  { value: 'week', label: 'This week' },
  { value: 'month', label: 'This month' },
  { value: 'quarter', label: 'This quarter' },
];

interface SalesPipelineSignature {
  Args: {
    items?: Opportunity[];
    onOpen?: (item: Opportunity) => void;
    /**
     * A deal's value for the value sort, in one currency. Without it, deals
     * sort by amount within each currency.
     */
    valueFor?: (item: Opportunity) => number;
  };
  Element: HTMLElement;
}

/** The last moment of the current calendar week, month or quarter. */
function closeWindowEnd(window: CloseWindow): Date | undefined {
  if (window === 'all') return undefined;
  let now = new Date();
  let y = now.getFullYear();
  let m = now.getMonth();
  if (window === 'week') {
    // Weeks end on Sunday.
    let daysToSunday = (7 - now.getDay()) % 7;
    return new Date(y, m, now.getDate() + daysToSunday, 23, 59, 59, 999);
  }
  if (window === 'month') {
    return new Date(y, m + 1, 0, 23, 59, 59, 999);
  }
  let quarterEndMonth = Math.floor(m / 3) * 3 + 3;
  return new Date(y, quarterEndMonth, 0, 23, 59, 59, 999);
}

export default class SalesPipeline extends GlimmerComponent<SalesPipelineSignature> {
  @tracked sortMode: BoardSortMode = 'value';
  @tracked closeWindow: CloseWindow = 'all';

  boardColumns: BoardColumn[] = PIPELINE_STAGES.map((s) => ({
    key: s,
    label: s,
    color: STAGE_COLORS[s],
  }));

  columnKeyFor = (item: CardDef) => (item as Opportunity)?.stage ?? undefined;

  openItem = (item: CardDef) => {
    this.args.onOpen?.(item as Opportunity);
  };

  get boardItems(): Opportunity[] {
    let items = this.args.items ?? [];
    let closesBy = closeWindowEnd(this.closeWindow);
    if (closesBy) {
      // A forecast window looks forward: a deal with no close date has not
      // been forecast at all, so it cannot be claimed to close in one.
      let from = new Date();
      from.setHours(0, 0, 0, 0);
      items = items.filter((o) => {
        if (!o.closeDate) return false;
        let at = new Date(o.closeDate);
        return at >= from && at <= closesBy;
      });
    }
    let sorted = [...items];
    if (this.sortMode === 'value') {
      let valueFor =
        this.args.valueFor ?? ((o: Opportunity) => o.value?.amount ?? 0);
      let code = (o: Opportunity) => o.value?.currency?.code ?? '';
      // Amounts in different currencies aren't comparable as they stand, so
      // without a consumer's `@valueFor` they sort within each currency.
      sorted.sort((a, b) =>
        !this.args.valueFor && code(a) !== code(b)
          ? code(a).localeCompare(code(b))
          : valueFor(b) - valueFor(a),
      );
    } else if (this.sortMode === 'probability') {
      sorted.sort(
        (a, b) => (b.effectiveProbability ?? 0) - (a.effectiveProbability ?? 0),
      );
    } else if (this.sortMode === 'stale') {
      sorted.sort((a, b) => (b.daysInStage ?? 0) - (a.daysInStage ?? 0));
    }
    return sorted;
  }

  setSortMode = (mode: string) => {
    this.sortMode = mode as BoardSortMode;
  };

  setCloseWindow = (window: string) => {
    this.closeWindow = window as CloseWindow;
  };

  <template>
    <div class='sales-pipeline' ...attributes>
      <div class='sp-controls'>
        <SegmentedControl
          @label='Sort cards by'
          @options={{SORT_OPTIONS}}
          @value={{this.sortMode}}
          @onValueChange={{this.setSortMode}}
        />
        <SegmentedControl
          @label='Closing within'
          @options={{WINDOW_OPTIONS}}
          @value={{this.closeWindow}}
          @onValueChange={{this.setCloseWindow}}
        />
      </div>
      <Board
        @items={{this.boardItems}}
        @columns={{this.boardColumns}}
        @columnKeyFor={{this.columnKeyFor}}
        @onOpen={{this.openItem}}
      >
        <:card as |item|>
          {{item.cardTitle}}
        </:card>
      </Board>
    </div>
    <style scoped>
      .sales-pipeline {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sp-controls {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}
