import Component from '@glimmer/component';
import type { BoxComponent, CardDef } from '@cardstack/base/card-api';
import { List } from '@cardstack/pretui/components/list';

interface Signature {
  Args: {
    items: readonly CardDef[];
    label: string;
    cardComponent: (card: CardDef) => BoxComponent;
    onOpen: (card: CardDef) => void;
    emptyMessage?: string;
    loading?: boolean;
    selected?: string;
    onSelect?: (card: CardDef) => void;
  };
  Blocks: { actions: [card: CardDef] };
  Element: HTMLDivElement;
}

// A list of embedded cards. The List owns the row's press and keyboard
// handling, so no control wraps the rendered card; picking a row selects it
// when `@onSelect` is given, and opens it otherwise.
export class CardList extends Component<Signature> {
  keyOf = (card: CardDef, index: number) => card.id ?? String(index);
  labelOf = (card: CardDef) => card.cardTitle ?? 'Card';

  get selected(): string[] | undefined {
    return this.args.selected ? [this.args.selected] : undefined;
  }

  activate = (card: CardDef) => {
    if (this.args.onSelect) {
      this.args.onSelect(card);
    } else {
      this.args.onOpen(card);
    }
  };

  select = (_keys: unknown, rows: CardDef[]) => {
    if (rows[0]) this.args.onSelect?.(rows[0]);
  };

  <template>
    <List
      class='card-list'
      @items={{@items}}
      @key={{this.keyOf}}
      @label={{@label}}
      @rowLabel={{this.labelOf}}
      @onActivate={{this.activate}}
      @selectionMode={{if @onSelect 'single' 'none'}}
      @selected={{this.selected}}
      @onSelectionChange={{this.select}}
      @divided={{true}}
      @emptyMessage={{@emptyMessage}}
      @loading={{@loading}}
      ...attributes
    >
      <:item as |card|>
        <div class='row'>
          {{#let (@cardComponent card) as |C|}}
            <C @format='embedded' class='row-card' />
          {{/let}}
          {{#if (has-block 'actions')}}
            <div class='row-actions'>{{yield card to='actions'}}</div>
          {{/if}}
        </div>
      </:item>
    </List>
    <style scoped>
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .row-card {
        flex: 1;
        min-width: 0;
      }
      .row-actions {
        display: flex;
        flex-shrink: 0;
        gap: var(--boxel-sp-2xs);
      }
    </style>
  </template>
}
