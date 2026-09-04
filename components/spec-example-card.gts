import GlimmerComponent from '@glimmer/component';

export interface SpecExampleCardSignature {
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class SpecExampleCard extends GlimmerComponent<SpecExampleCardSignature> {
  <template>
    <article class='spec-example-card' ...attributes>
      {{yield}}
    </article>
    <style scoped>
      .spec-example-card {
        border: var(--boxel-border);
        border-radius: var(--boxel-border-radius);
        background-color: var(--boxel-100);
        padding: var(--boxel-sp-xs);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}
