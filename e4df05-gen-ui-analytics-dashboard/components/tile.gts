import GlimmerComponent from '@glimmer/component';
import type { BaseDef, BoxComponent } from '@cardstack/base/card-api';

function getComponent(
  cardOrField: BaseDef | undefined | null,
): BoxComponent | undefined {
  if (!cardOrField) {
    return;
  }
  let constructor = cardOrField.constructor as typeof BaseDef | undefined;
  if (typeof constructor?.getComponent !== 'function') {
    return;
  }
  return constructor.getComponent(cardOrField);
}

interface TileSignature {
  Args: {
    card: any;
  };
  Element: HTMLElement;
}

// one dashboard tile: renders the linked card's embedded format
class Tile extends GlimmerComponent<TileSignature> {
  get component(): BoxComponent | undefined {
    return getComponent(this.args.card);
  }

  <template>
    {{#if this.component}}
      {{#let this.component as |CardComponent|}}
        <CardComponent @format='embedded' />
      {{/let}}
    {{/if}}
  </template>
}

export default Tile;
