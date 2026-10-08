import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import ChevronRight from '@cardstack/boxel-icons/chevron-right';

export interface HomeRailItem {
  label: string;
  meta?: string;
  onOpen?: () => void;
  /** One primary action per rail item at most — e.g. Acknowledge. */
  action?: { label: string; run: () => void };
}

export interface HomeRail {
  title: string;
  items: HomeRailItem[];
  emptyLabel?: string;
}

interface Signature {
  Args: {
    greeting: string;
    /** e.g. "L2 Support · on duty" */
    identity?: string;
    /**
     * Rails IN OBLIGATION ORDER — the caller decides, but the contract is:
     * things someone is waiting on first (acks), then breach risk, then the
     * rest. The first rail's action is the page's one primary button.
     */
    rails: HomeRail[];
  };
  Element: HTMLElement;
}

/**
 * Workspace Home — the generic landing contract: identity strip
 * plus "my work" rails, ranked by obligation. Takes queries' RESULTS and
 * actions; contains no domain strings of its own.
 */
export class WorkspaceHome extends GlimmerComponent<Signature> {
  run = (item: HomeRailItem) => item.action?.run();
  open = (item: HomeRailItem) => item.onOpen?.();

  <template>
    <div class='home' ...attributes>
      <header class='home-head'>
        <h2 class='home-greeting'>{{@greeting}}</h2>
        {{#if @identity}}<span class='home-identity'>{{@identity}}</span>{{/if}}
      </header>
      <div class='home-rails'>
        {{#each @rails as |rail|}}
          <section class='rail'>
            <h3 class='rail-title'>{{rail.title}} · {{rail.items.length}}</h3>
            {{#each rail.items as |item|}}
              <div class='rail-item'>
                {{#if item.onOpen}}
                  <button
                    type='button'
                    class='rail-open'
                    {{on 'click' (fn this.open item)}}
                  >
                    <span class='rail-label'>{{item.label}}</span>
                    {{#if item.meta}}<span
                        class='rail-meta'
                      >{{item.meta}}</span>{{/if}}
                    <ChevronRight
                      class='rail-cue'
                      role='presentation'
                      width='13'
                      height='13'
                    />
                  </button>
                {{else}}
                  <span class='rail-open rail-static'>
                    <span class='rail-label'>{{item.label}}</span>
                    {{#if item.meta}}<span
                        class='rail-meta'
                      >{{item.meta}}</span>{{/if}}
                  </span>
                {{/if}}
                {{#if item.action}}
                  <Button
                    @variant='primary'
                    @size='xs'
                    class='hit-ext'
                    {{on 'click' (fn this.run item)}}
                  >
                    {{item.action.label}}
                  </Button>
                {{/if}}
              </div>
            {{else}}
              <p class='rail-empty'>{{if
                  rail.emptyLabel
                  rail.emptyLabel
                  'Nothing here — clear.'
                }}</p>
            {{/each}}
          </section>
        {{/each}}
      </div>
    </div>
    <style scoped>
      .hit-ext {
        position: relative;
      }
      .hit-ext::after {
        content: '';
        position: absolute;
        inset: -0.625rem 0;
      }
      .home {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .home-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .home-greeting {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
      }
      .home-identity {
        font-size: var(--boxel-font-size-xs);
        border: 1px solid var(--primary);
        color: color-mix(in oklab, var(--primary) 38%, var(--card-foreground));
        border-radius: 999px;
        padding: 0.125rem 0.625rem;
      }
      .home-rails {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
        gap: var(--boxel-sp-xs);
        align-items: start;
      }
      .rail {
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        background: var(--card);
        padding: var(--boxel-sp-sm);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
      }
      .rail-title {
        margin: 0 0 var(--boxel-sp-4xs);
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .rail-item {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
      }
      .rail-open {
        flex: 1;
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
        text-align: left;
        background: none;
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius-sm);
        padding: var(--boxel-sp-5xs) var(--boxel-sp-4xs);
        font: inherit;
        color: inherit;
      }
      button.rail-open {
        cursor: pointer;
        transition: border-color 120ms ease-out;
      }
      button.rail-open:hover,
      button.rail-open:focus-visible {
        border-color: var(--primary);
      }
      button.rail-open:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }
      .rail-label {
        font-weight: 500;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.25;
        overflow: hidden;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
        flex: 1;
        min-width: 0;
      }
      .rail-meta {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .rail-cue {
        flex: none;
        align-self: center;
        color: var(--muted-foreground);
      }
      .rail-empty {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--boxel-success);
      }
      @media (prefers-reduced-motion: reduce) {
        button.rail-open {
          transition: none;
        }
      }
    </style>
  </template>
}

export default WorkspaceHome;
