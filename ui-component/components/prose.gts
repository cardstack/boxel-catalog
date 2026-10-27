// Pretui — Prose: long-form text in the kit reading voice.
import type { TemplateOnlyComponent } from '@ember/component/template-only';

export interface ProseSignature {
  Blocks: { default: [] };
  Element: HTMLDivElement;
}

// The typographic reading surface — styles inline code per Law 3's quieter cousin.
export const Prose: TemplateOnlyComponent<ProseSignature> = <template>
  <div class='pretui-prose' data-test-pretui-prose ...attributes>{{yield}}</div>
  <style scoped>
    @layer PretComponent {
      .pretui-prose {
        max-width: 62ch;
        line-height: calc(
          var(--leading-body, 1.5rem) / var(--boxel-font-size-sm)
        );
      }
      .pretui-prose :deep(p) {
        margin: 0 0 var(--boxel-sp-sm);
      }
      .pretui-prose :deep(code) {
        font-family: var(--font-mono);
        font-size: 0.92em;
        background: var(--inset);
        padding: var(--boxel-sp-6xs) var(--boxel-sp-3xs);
        border-radius: var(--boxel-border-radius-xs);
        box-shadow: 0 0 0 1px var(--border);
      }
    }
  </style>
</template>;
