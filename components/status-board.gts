import GlimmerComponent from '@glimmer/component';
import type { CardDef } from '@cardstack/base/card-api';

import { Board, type BoardColumn } from '@cardstack/catalog/components/board';
import {
  canTransition,
  type StatusFieldClass,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { stateColor } from '@cardstack/catalog/components/state-pill';

interface Signature {
  Args: {
    /** Records to lay out, holes tolerated. */
    items?: (CardDef | undefined)[];
    /** The configured statusField class — its options ARE the columns, in order. */
    statusField: StatusFieldClass;
    /** Reads a record's current status value. */
    statusOf: (item: CardDef) => string | undefined;
    /**
     * Called only for drags the field's transition graph allows; an illegal
     * drop is refused here so no consumer forgets to check.
     */
    onMove?: (item: CardDef, statusValue: string) => void;
    /** An illegal drag, if the consumer wants to explain instead of ignore. */
    onRejected?: (item: CardDef, from: string | undefined, to: string) => void;
    onOpen?: (item: CardDef) => void;
    onAddCard?: (statusValue: string | null) => void;
    hideEmpty?: boolean;
    boardLabel?: string;
  };
  Blocks: {
    card: [CardDef];
  };
  Element: HTMLElement;
}

/**
 * A board whose columns are a lifecycle. The catalog Board owns the kanban
 * mechanics and the statusField factory owns the option set, colours and
 * transition graph; this block is the join — columns derive
 * from `statusOptions` (never re-declared by the consumer), and a drag that
 * the transition graph forbids is refused here instead of trusting every
 * consumer to remember `canTransition`.
 */
export class StatusBoard extends GlimmerComponent<Signature> {
  get columns(): BoardColumn[] {
    return this.args.statusField.statusOptions.map((option: StatusOption) => ({
      key: option.value,
      label: option.label ?? option.value,
      color: stateColor(option.hue ?? 'slate').ring,
    }));
  }

  get items(): CardDef[] {
    return (this.args.items ?? []).filter(Boolean) as CardDef[];
  }

  columnKeyFor = (item: CardDef) => this.args.statusOf(item);

  cardComponent = (card: CardDef) => {
    return (card.constructor as typeof CardDef).getComponent(card);
  };

  handleMove = (item: CardDef, columnKey: string) => {
    let from = this.args.statusOf(item);
    if (from === columnKey) {
      return;
    }
    if (canTransition(this.args.statusField, from, columnKey)) {
      this.args.onMove?.(item, columnKey);
    } else {
      this.args.onRejected?.(item, from, columnKey);
    }
  };

  <template>
    <Board
      @items={{this.items}}
      @columns={{this.columns}}
      @columnKeyFor={{this.columnKeyFor}}
      @onMove={{if @onMove this.handleMove}}
      @onOpen={{@onOpen}}
      @onAddCard={{@onAddCard}}
      @hideEmpty={{@hideEmpty}}
      @boardLabel={{@boardLabel}}
      ...attributes
    >
      <:card as |item|>
        {{#if (has-block 'card')}}
          {{yield item to='card'}}
        {{else}}
          {{#let (this.cardComponent item) as |C|}}
            <C @format='fitted' />
          {{/let}}
        {{/if}}
      </:card>
    </Board>
  </template>
}

export default StatusBoard;
