// Pretui — Toolbar: a header strip with a title, eyebrow, meta and trailing actions.
import type { TemplateOnlyComponent } from '@ember/component/template-only';

export interface ToolbarSignature {
  Args: { title?: string; eyebrow?: string; meta?: string };
  Blocks: { default: [] };
  Element: HTMLDivElement;
}

export const Toolbar: TemplateOnlyComponent<ToolbarSignature> = <template>
  <div class='pretui-toolbar' data-test-pretui-toolbar ...attributes>
    <div class='pretui-toolbar-id'>
      {{#if @eyebrow}}<span class='pretui-eyebrow'>{{@eyebrow}}</span>{{/if}}
      {{#if @title}}<h2>{{@title}}</h2>{{/if}}
      {{#if @meta}}<span class='pretui-toolbar-meta'>{{@meta}}</span>{{/if}}
    </div>
    <div class='pretui-toolbar-actions'>{{yield}}</div>
  </div>
  <style scoped>
    @layer PretComponent {
      .pretui-toolbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        min-height: 2.75rem;
      }
      .pretui-toolbar-id {
        display: grid;
        gap: var(--boxel-sp-6xs);
        min-width: 0;
      }
      .pretui-toolbar-id h2 {
        margin: 0;
        font-size: var(--boxel-font-size-md);
        font-weight: 700;
        letter-spacing: -0.02em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .pretui-eyebrow {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 500;
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .pretui-toolbar-meta {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .pretui-toolbar-actions {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex: none;
      }
    }
  </style>
</template>;
