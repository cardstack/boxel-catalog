// Pretui — CollapsedTurn: a settled conversation turn folded to a one-line receipt.
import Component from '@glimmer/component';
import { on } from '@ember/modifier';

export interface CollapsedTurnSignature {
  Args: { summary: string; onExpand?: () => void };
  Element: HTMLButtonElement;
}

// Settled history earns its quiet: a receipt of counts, not content.
export class CollapsedTurn extends Component<CollapsedTurnSignature> {
  expand = () => this.args.onExpand?.();
  <template>
    <button
      type='button'
      class='pretui-collapsed'
      data-test-pretui-collapsed-turn
      {{on 'click' this.expand}}
      ...attributes
    >
      <span class='pretui-collapsed-check'>✓</span>{{@summary}}
    </button>
    <style scoped>
      @layer PretComponent {
        .pretui-collapsed {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          height: 1.5rem;
          padding: 0
            calc(
              var(--boxel-sp-3xs) * var(--pretui-capsule-base, 1.35) +
                var(--boxel-sp-sm) * var(--pretui-radius-encroach, 0.35)
            );
          border-radius: var(--boxel-border-radius-lg);
          border: 0;
          background: var(--inset);
          box-shadow: 0 0 0 1px var(--border);
          font-family: inherit;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          cursor: pointer;
          font-variant-numeric: tabular-nums;
        }
        .pretui-collapsed:hover {
          background: var(--hover);
        }
        .pretui-collapsed-check {
          color: var(--success);
        }
      }
    </style>
  </template>
}
