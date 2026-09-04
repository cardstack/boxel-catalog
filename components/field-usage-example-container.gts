import GlimmerComponent from '@glimmer/component';

// Created to avoid duplicating this page-level container's styles across
// every field Spec (each Spec previously redefined this block twice --
// once in its Isolated component, once in Edit). Centralizing it here
// makes future theming/token updates a single-file change instead of a
// 6+ file find-and-replace.
export interface FieldUsageExampleContainerSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FieldUsageExampleContainer extends GlimmerComponent<FieldUsageExampleContainerSignature> {
  <template>
    <article class='field-usage-example-container' ...attributes>
      {{yield}}
    </article>
    <style scoped>
      .field-usage-example-container {
        --boxel-spec-background-color: var(--boxel-200);
        --boxel-spec-code-ref-background-color: var(--boxel-100);
        --boxel-spec-code-ref-text-color: var(--boxel-dark);

        height: 100%;
        min-height: max-content;
        padding: var(--boxel-sp);
        background-color: var(--boxel-spec-background-color);
      }
    </style>
  </template>
}
