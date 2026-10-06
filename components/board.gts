import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
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
  /** The item's stored column when the drag landed. */
  from: string | undefined;
  to: string;
  /** Set once the stored column moves off `from`; a retired hold never returns. */
  retired: boolean;
}

function itemAt(items: CardDef[], index: number): CardDef | undefined {
  return items[index];
}

function isThenable(value: unknown): value is PromiseLike<unknown> {
  return typeof (value as PromiseLike<unknown>)?.then === 'function';
}

function cardComponent(card: CardDef) {
  return (card.constructor as typeof CardDef).getComponent(card);
}

const FittedCard: TemplateOnlyComponent<{ Args: { card: CardDef } }> =
  <template>
    {{#let (cardComponent @card) as |C|}}
      <C @format='fitted' />
    {{/let}}
  </template>;

interface BoardSignature {
  Args: {
    boardLabel?: string;
    cardSize?: FittedFormatId;
    columnKeyFor: (item: CardDef) => string | undefined;
    columns: BoardColumn[];
    /**
     * Shown in place of the board when there are no items. Ignored when
     * `onAddCard` is set, since the columns' add buttons are the way in.
     */
    emptyMessage?: string;
    hideEmpty?: boolean;
    items: CardDef[];
    onAddCard?: (columnKey: string | null) => void;
    /**
     * Called when a drag crosses columns, with the column the card was dragged
     * from as shown on the board. The card holds its new column until the
     * item's own column changes. Returning `false`, throwing, or a promise
     * that rejects or resolves `false` refuses the move and the card goes
     * back. Without `onMove` the board is read-only and a drag snaps back.
     */
    onMove?: (
      item: CardDef,
      columnKey: string,
      fromColumnKey: string,
    ) => unknown;
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

  storedColumn(item: CardDef): string | undefined {
    return this.args.columnKeyFor(item) ?? this.args.columns[0]?.key;
  }

  columnOf(item: CardDef): string | undefined {
    let stored = this.storedColumn(item);
    let move = this.pending.get(item);
    if (!move || move.retired) {
      return stored;
    }
    if (stored !== move.from) {
      // The save landed, or something else moved the item: the stored column
      // wins from here on, even if it later returns to `from`.
      move.retired = true;
      return stored;
    }
    return move.to;
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
    if (this.args.onAddCard || this.args.items.some(Boolean)) {
      return undefined;
    }
    return this.args.emptyMessage;
  }

  private hold(item: CardDef, move: PendingMove) {
    let next = new Map([...this.pending].filter(([, m]) => !m.retired));
    next.set(item, move);
    this.pending = next;
  }

  /** Drops the hold only if it is still the one this move set. */
  private release(item: CardDef, move: PendingMove) {
    if (this.pending.get(item) !== move) {
      return;
    }
    let next = new Map(this.pending);
    next.delete(item);
    this.pending = next;
  }

  private async move(item: CardDef, to: string, shownFrom: string) {
    let onMove = this.args.onMove;
    if (!onMove) {
      return;
    }
    let move: PendingMove = {
      from: this.storedColumn(item),
      to,
      retired: false,
    };
    this.hold(item, move);
    let result: unknown;
    try {
      result = onMove(item, to, shownFrom);
    } catch (e) {
      console.error('Board move failed; reverting', e);
      this.release(item, move);
      return;
    }
    if (result === false) {
      this.release(item, move);
      return;
    }
    if (!isThenable(result)) {
      return;
    }
    this.saving++;
    try {
      if ((await result) === false) {
        this.release(item, move);
      }
    } catch (e) {
      console.error('Board move failed; reverting', e);
      this.release(item, move);
    } finally {
      this.saving--;
    }
  }

  @action handleChange(next: KanbanPlacement[]) {
    for (let placement of next) {
      let item = this.args.items[placement.index];
      let shownFrom = item ? this.columnOf(item) : undefined;
      if (item && shownFrom !== undefined && shownFrom !== placement.columnId) {
        void this.move(item, placement.columnId, shownFrom);
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
                  <FittedCard @card={{item}} />
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
                  <FittedCard @card={{item}} />
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
