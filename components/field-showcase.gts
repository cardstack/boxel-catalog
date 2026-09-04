import GlimmerComponent from '@glimmer/component';

// Created to avoid duplicating this page-level container's styles across
// every field Spec (each Spec previously redefined this block twice --
// once in its Isolated component, once in Edit). Centralizing it here
// makes future theming/token updates a single-file change instead of a
// 6+ file find-and-replace.
export interface FieldShowcaseSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FieldShowcase extends GlimmerComponent<FieldShowcaseSignature> {
  <template>
    <article class='field-showcase' ...attributes>
      {{yield}}
    </article>
    <style scoped>
      .field-showcase {
        --field-showcase-background-color: var(--boxel-200);

        height: 100%;
        min-height: max-content;
        padding: var(--boxel-sp);
        background-color: var(--field-showcase-background-color);
      }
    </style>
  </template>
}
