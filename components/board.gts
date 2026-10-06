import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import type { CardDef } from 'https://cardstack.com/base/card-api';
import type {
  KanbanColumnConfig,
  KanbanPlacement,
} from '@cardstack/boxel-ui/components';
import type { FittedFormatId } from '@cardstack/boxel-ui/helpers';
import { Board as PretBoard } from '@cardstack/pretui/components/board';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { COMPACT_EMPTY_STYLE } from './pretui-helpers';

export interface BoardColumn {
  key: string;
  label?: string;
  color?: string;
  wipLimit?: number;
}

interface PendingMove {
  from: string | undefined;
  to: string;
}

function itemAt(items: CardDef[], index: number): CardDef | undefined {
  return items[index];
}

function isThenable(value: unknown): value is PromiseLike<unknown> {
  return typeof (value as PromiseLike<unknown>)?.then === 'function';
}

interface BoardSignature {
  Args: {
    boardLabel?: string;
    cardSize?: FittedFormatId;
    columnKeyFor: (item: CardDef) => string | undefined;
    columns: BoardColumn[];
    /** Replaces the board when no card sits in any column. */
    emptyMessage?: string;
    hideEmpty?: boolean;
    items: CardDef[];
    onAddCard?: (columnKey: string | null) => void;
    /**
     * Return `false`, or a promise that rejects or resolves `false`, to refuse
     * the move; the card goes back to its column. Otherwise the card stays
     * where it was dropped until the item's own column changes.
     */
    onMove?: (item: CardDef, columnKey: string) => unknown;
    onOpen?: (item: CardDef) => void;
    onSelect?: (item: CardDef | undefined) => void;
  };
  Blocks: {
    card: [CardDef];
  };
  Element: HTMLElement;
}

/**
 * A kanban over any cards, on Pret UI `Board`. Pret UI's board places
 * positions; this block adds the card-level contract: which column a card sits
 * in (`columnKeyFor`) and what to do when a drag crosses columns (`onMove`).
 */
export class Board extends GlimmerComponent<BoardSignature> {
  @tracked private pending = new Map<CardDef, PendingMove>();
  @tracked private saving = 0;

  columnOf(item: CardDef): string | undefined {
    let actual = this.args.columnKeyFor(item) ?? this.args.columns[0]?.key;
    let move = this.pending.get(item);
    // A pending move holds only until the item's own column changes, so a
    // save that lands, or a change from elsewhere, always wins.
    return move && move.from === actual ? move.to : actual;
  }

  get placements(): KanbanPlacement[] {
    let known = new Set(this.args.columns.map((c) => c.key));
    let counters = new Map<string, number>();
    let result: KanbanPlacement[] = [];
    this.args.items.forEach((item, index) => {
      if (!item) return;
      let columnId = this.columnOf(item);
      // A card whose column is not on this board is not drawn: placing it in
      // the first column would misreport where it is.
      if (columnId === undefined || !known.has(columnId)) return;
      let sortOrder = (counters.get(columnId) ?? 0) + 1;
      counters.set(columnId, sortOrder);
      result.push({ columnId, index, sortOrder });
    });
    return result;
  }

  get kanbanColumns(): KanbanColumnConfig[] {
    let counts = new Map<string, number>();
    for (let p of this.placements) {
      counts.set(p.columnId, (counts.get(p.columnId) ?? 0) + 1);
    }
    return this.args.columns.map((c, i) => ({
      key: c.key,
      label: c.label ?? c.key,
      color: c.color ?? null,
      collapsed: this.args.hideEmpty && !(counts.get(c.key) ?? 0) ? true : null,
      sortOrder: i,
      wipLimit: c.wipLimit ?? null,
    }));
  }

  get emptyMessage(): string | undefined {
    return this.placements.length === 0 ? this.args.emptyMessage : undefined;
  }

  cardComponent = (card: CardDef) => {
    return (card.constructor as typeof CardDef).getComponent(card);
  };

  private setPending(item: CardDef, move: PendingMove | undefined) {
    let next = new Map(this.pending);
    if (move) {
      next.set(item, move);
    } else {
      next.delete(item);
    }
    this.pending = next;
  }

  private async move(item: CardDef, to: string) {
    let from = this.args.columnKeyFor(item) ?? this.args.columns[0]?.key;
    this.setPending(item, { from, to });
    let result = this.args.onMove?.(item, to);
    if (result === false) {
      this.setPending(item, undefined);
      return;
    }
    if (!isThenable(result)) {
      return;
    }
    this.saving++;
    try {
      await result;
    } catch (e) {
      console.error('Board move failed; reverting', e);
    } finally {
      this.saving--;
      this.setPending(item, undefined);
    }
  }

  @action handleChange(next: KanbanPlacement[]) {
    for (let placement of next) {
      let item = this.args.items[placement.index];
      if (item && this.columnOf(item) !== placement.columnId) {
        this.move(item, placement.columnId);
      }
    }
  }

  @action handleOpen(index: number) {
    let item = this.args.items[index];
    if (item) this.args.onOpen?.(item);
  }

  @action handleSelect(index: number | null) {
    this.args.onSelect?.(index === null ? undefined : this.args.items[index]);
  }

  <template>
    <div class='board {{if this.saving "saving"}}' ...attributes>
      {{#if this.emptyMessage}}
        <EmptyState
          @title={{this.emptyMessage}}
          @texture={{false}}
          @size='s'
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{else}}
        <PretBoard
          class='plane'
          @boardLabel={{@boardLabel}}
          @cardSize={{@cardSize}}
          @columns={{this.kanbanColumns}}
          @hideEmpty={{@hideEmpty}}
          @placements={{this.placements}}
          @onChange={{this.handleChange}}
          @onOpen={{this.handleOpen}}
          @onSelect={{this.handleSelect}}
          @onAddCard={{@onAddCard}}
        >
          <:card as |placement|>
            {{#let (itemAt @items placement.index) as |item|}}
              {{#if item}}
                {{#if (has-block 'card')}}
                  {{yield item to='card'}}
                {{else}}
                  {{#let (this.cardComponent item) as |C|}}
                    <C @format='fitted' />
                  {{/let}}
                {{/if}}
              {{/if}}
            {{/let}}
          </:card>
          <:ghost as |index|>
            {{#let (itemAt @items index) as |item|}}
              {{#if item}}
                {{#if (has-block 'card')}}
                  {{yield item to='card'}}
                {{else}}
                  {{#let (this.cardComponent item) as |C|}}
                    <C @format='fitted' />
                  {{/let}}
                {{/if}}
              {{/if}}
            {{/let}}
          </:ghost>
        </PretBoard>
      {{/if}}
    </div>
    <style scoped>
      .board {
        width: 100%;
        height: 100%;
        overflow-x: auto;
      }
      .saving .plane {
        opacity: 0.75;
      }
    </style>
  </template>
}

export default Board;
