// Pretui — SkipLink: the first focusable control, a way past the chrome to the main content.
import Component from '@glimmer/component';

export interface SkipLinkSignature {
  Args: {
    /** The in-page target (default '#main'). Give that element the matching id. */
    href?: string;
    /** The link text (default 'Skip to content'). */
    label?: string;
  };
  Element: HTMLAnchorElement;
}

/**
 * WCAG 2.4.1 Bypass Blocks. Put it first in the pane, before the header and
 * navigation. It is off screen until it receives focus, then appears at the
 * top start corner of the nearest positioned ancestor so the keyboard user can see where they are. It is a plain
 * in-page anchor, so it needs no router. The target should be focusable
 * (`tabindex='-1'` on a `<main>`) so focus actually moves there, not only the
 * scroll position.
 */
export class SkipLink extends Component<SkipLinkSignature> {
  get href(): string {
    return this.args.href ?? '#main';
  }
  get label(): string {
    return this.args.label ?? 'Skip to content';
  }
  <template>
    <a
      class='pretui-skip-link'
      href={{this.href}}
      data-test-pretui-skip-link
      ...attributes
    >{{this.label}}</a>
    <style scoped>
      @layer PretComponent {
        .pretui-skip-link {
          position: absolute;
          inset-block-start: var(--boxel-sp-xs);
          inset-inline-start: var(--boxel-sp-xs);
          z-index: var(--pretui-z-toast, 100);
          padding: var(--boxel-sp-2xs) var(--boxel-sp-sm);
          border-radius: calc(var(--radius) - 0.125rem);
          background: var(--primary);
          color: var(--primary-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-decoration: none;
          box-shadow:
            0 0 0 1px var(--border),
            var(--shadow-md);
        }
        /* Off screen but in the tab order and the accessibility tree until it
           has focus: the clip pattern, not display: none. */
        .pretui-skip-link:not(:focus) {
          inline-size: 1px;
          block-size: 1px;
          padding: 0;
          overflow: hidden;
          clip-path: inset(50%);
          white-space: nowrap;
        }
        .pretui-skip-link:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 2px;
        }
      }
    </style>
  </template>
}
