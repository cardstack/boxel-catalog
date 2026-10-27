// Pretui — ResultCard: the settled outcome of an agent run.
import Component from '@glimmer/component';
import { on } from '@ember/modifier';

export interface ResultCardSignature {
  Args: {
    eyebrow?: string;
    title: string;
    lines?: string[];
    onMenu?: () => void;
  };
  Element: HTMLDivElement;
}

// What you approve is card-shaped, never a JSON blob.
export class ResultCard extends Component<ResultCardSignature> {
  menu = () => this.args.onMenu?.();
  <template>
    <div class='pretui-resultcard' data-test-pretui-result-card ...attributes>
      <div class='pretui-resultcard-head'>
        {{#if @eyebrow}}<span class='pretui-eyebrow'>{{@eyebrow}}</span>{{/if}}
        <span class='pretui-resultcard-title'>{{@title}}</span>
        {{#if @onMenu}}
          <button
            type='button'
            class='pretui-resultcard-menu'
            aria-label='More'
            {{on 'click' this.menu}}
          >⋯</button>
        {{/if}}
      </div>
      {{#each @lines as |line|}}<div
          class='pretui-resultcard-line'
        >{{line}}</div>{{/each}}
    </div>
    <style scoped>
      @layer PretComponent {
        .pretui-resultcard {
          background: var(--field);
          border-radius: var(--boxel-border-radius-sm);
          box-shadow: 0 0 0 1px var(--border);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .pretui-resultcard-head {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
        }
        .pretui-resultcard-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-eyebrow {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .pretui-resultcard-menu {
          margin-left: auto;
          color: var(--subtle-foreground);
          cursor: pointer;
          letter-spacing: 0.1em;
          border: 0;
          background: none;
          font-family: inherit;
        }
        .pretui-resultcard-line {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      }
    </style>
  </template>
}
