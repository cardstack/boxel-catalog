import GlimmerComponent from '@glimmer/component';
import { CardContainer } from '@cardstack/boxel-ui/components';

// Created to avoid duplicating the field-example card's styles across every
// field Spec (each Spec previously redefined this block twice -- once in
// Isolated, once in Edit -- with its own border/background/radius). Reuses
// CardContainer for those (per pret-ui-theming Rule 4: don't restate
// CardContainer's defaults) and only adds the layout this card needs.
export interface FieldShowcaseCardSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FieldShowcaseCard extends GlimmerComponent<FieldShowcaseCardSignature> {
  <template>
    <CardContainer
      @displayBoundaries={{true}}
      class='field-showcase-card'
      ...attributes
    >
      {{yield}}
    </CardContainer>
    <style scoped>
      .field-showcase-card {
        padding: var(--boxel-sp-xs);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}
