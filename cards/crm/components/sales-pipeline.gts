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
  };
  Element: HTMLElement;
}

function closeWindowEnd(window: CloseWindow): Date | undefined {
  if (window === 'all') return undefined;
  let end = new Date();
  if (window === 'week') end.setDate(end.getDate() + 7);
  if (window === 'month') end.setMonth(end.getMonth() + 1);
  if (window === 'quarter') end.setMonth(end.getMonth() + 3);
  return end;
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
      sorted.sort((a, b) => (b.value?.amount ?? 0) - (a.value?.amount ?? 0));
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
