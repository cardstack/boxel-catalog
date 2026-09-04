import GlimmerComponent from '@glimmer/component';

export interface SpecContainerSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class SpecContainer extends GlimmerComponent<SpecContainerSignature> {
  <template>
    <article class='spec-container' ...attributes>
      {{yield}}
    </article>
    <style scoped>
      .spec-container {
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
