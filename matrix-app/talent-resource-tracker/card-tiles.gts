import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type { CardDef } from '@cardstack/base/card-api';
import type { FittedFormatId } from '@cardstack/boxel-ui/helpers';
import { Grid } from '../../ui-component/components/grid';
import { getComponent } from './shared';

interface Signature {
  Args: {
    cards: CardDef[];
    size: FittedFormatId;
    /** one full-width column, for rows rather than tiles */
    list?: boolean;
    /** makes each tile a button that opens its card */
    onOpen?: (card: CardDef) => void;
    /** a flat theme-muted fill with no shadow, instead of a raised tile */
    flat?: boolean;
  };
}

// Cards drawn by their own fitted format in the kit Grid, each one a
// keyboard-reachable target that opens the card.
export class CardTiles extends GlimmerComponent<Signature> {
  keydown = (card: CardDef, event: KeyboardEvent) => {
    // a fitted template's own controls handle their own keys
    if (event.target !== event.currentTarget) {
      return;
    }
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      this.args.onOpen?.(card);
    }
  };

  open = (card: CardDef, event: Event) => {
    let target = event.target as HTMLElement | null;
    if (target?.closest('button, a, input') && target !== event.currentTarget) {
      return;
    }
    this.args.onOpen?.(card);
  };

  <template>
    <Grid
      @items={{@cards}}
      @size={{@size}}
      @viewFormat={{if @list 'list' 'grid'}}
      @fullWidthItem={{@list}}
      as |card Item|
    >
      <Item>
        {{#let (getComponent card) as |CardComponent|}}
          <div
            class='card-tile'
            data-flat={{if @flat 'true'}}
            role={{if @onOpen 'button'}}
            tabindex={{if @onOpen '0'}}
            {{on 'click' (fn this.open card)}}
            {{on 'keydown' (fn this.keydown card)}}
          >
            {{#if CardComponent}}
              <CardComponent @format='fitted' />
            {{/if}}
          </div>
        {{/let}}
      </Item>
    </Grid>
    <style scoped>
      .card-tile {
        box-sizing: border-box;
        height: 100%;
        border-radius: var(--radius);
        overflow: hidden;
        box-shadow: var(--shadow-md);
      }
      .card-tile[data-flat] {
        background: var(--muted);
        box-shadow: none;
      }
      .card-tile[role='button'] {
        cursor: pointer;
      }
      .card-tile:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
    </style>
  </template>
}
