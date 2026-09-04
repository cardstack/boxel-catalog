import GlimmerComponent from '@glimmer/component';
import { CardContainer } from '@cardstack/boxel-ui/components';

// Created to avoid duplicating the field-example card's styles across every
// field Spec (each Spec previously redefined this block twice -- once in
// Isolated, once in Edit -- with its own border/background/radius). Reuses
// CardContainer for those (per pret-ui-theming Rule 4: don't restate
// CardContainer's defaults) and only adds the layout this card needs.
export interface FieldExampleSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FieldExample extends GlimmerComponent<FieldExampleSignature> {
  <template>
    <CardContainer
      @displayBoundaries={{true}}
      class='field-example'
      ...attributes
    >
      {{yield}}
    </CardContainer>
    <style scoped>
      .field-example {
        padding: var(--boxel-sp-xs);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}
