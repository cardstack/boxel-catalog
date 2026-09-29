import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import {
  getComponent,
  type BoxComponent,
  type CardContext,
  type CardDef,
} from 'https://cardstack.com/base/card-api';
import { Button } from '@cardstack/boxel-ui/components';
import { not } from '@cardstack/boxel-ui/helpers';
import SwitchSubmodeCommand from '@cardstack/boxel-host/commands/switch-submode';
import { identifyCard, moduleFrom } from '@cardstack/runtime-common';

// Pieces of the Gold Spec Card Group page, one page per card cluster: the page
// shell, the file links, and a card rendered in every format.

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const here: string = import.meta.url;

/** The catalog root, which every path on the page is relative to. */
export const catalogRoot = new URL('../', here).href;
const CATALOG_PREFIX = '@cardstack/catalog/';
const SOURCE_EXTENSION = /\.g?ts$/;

function fromCatalogRoot(url: string): string {
  if (url.startsWith(catalogRoot)) {
    return url.slice(catalogRoot.length);
  }
  if (url.startsWith(CATALOG_PREFIX)) {
    return url.slice(CATALOG_PREFIX.length);
  }
  return url;
}

/** A card's source file relative to the catalog root, read off its own class. */
export function cardSourcePath(card: CardDef): string {
  let ref = identifyCard(card.constructor as typeof CardDef);
  if (!ref) {
    return '';
  }
  let path = fromCatalogRoot(moduleFrom(ref));
  return SOURCE_EXTENSION.test(path) ? path : `${path}.gts`;
}

/** A card instance's JSON file relative to the catalog root. */
export function cardInstancePath(card: CardDef): string {
  return card.id ? `${fromCatalogRoot(card.id)}.json` : '';
}

/** A file path; clicking opens the file in code mode. */
export class SourceLink extends GlimmerComponent<{
  Args: { path: string; context?: CardContext };
}> {
  get url() {
    return new URL(this.args.path, catalogRoot).href;
  }
  open = async () => {
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      return;
    }
    await new SwitchSubmodeCommand(commandContext).execute({
      submode: 'code',
      codePath: this.url,
    });
  };
  <template>
    <Button
      class='source-link'
      @kind='text-only'
      @size='extra-small'
      @disabled={{not @context.commandContext}}
      title='Open {{@path}} in code mode'
      {{on 'click' this.open}}
    ><code>{{@path}}</code></Button>
    <style scoped>
      .source-link code {
        font-family: var(--font-mono);
        font-size: var(--boxel-caption-font-size);
      }
    </style>
  </template>
}

/**
 * One linked card in every format: fitted at the badge, strip, tile and card
 * sizes, then embedded and atom, then isolated behind a disclosure. The card
 * is a shared example, so this only renders it.
 */
export class CardFormats extends GlimmerComponent<{
  Args: { card: CardDef };
}> {
  get Card(): BoxComponent {
    return getComponent(this.args.card);
  }
  <template>
    <div class='fits'>
      <figure class='fit fit-badge'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted badge, 150 × 65</figcaption>
      </figure>
      <figure class='fit fit-strip'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted strip, 250 × 65</figcaption>
      </figure>
      <figure class='fit fit-tile'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted tile, 180 × 170</figcaption>
      </figure>
      <figure class='fit fit-card'>
        <div class='fit-box'><this.Card @format='fitted' /></div>
        <figcaption>Fitted card, 400 × 170</figcaption>
      </figure>
    </div>
    <div class='flows'>
      <div class='embedded'><this.Card @format='embedded' /></div>
      <span class='atom'><this.Card @format='atom' /></span>
    </div>
    <details class='isolated'>
      <summary>Isolated</summary>
      <this.Card @format='isolated' />
    </details>
    <style scoped>
      .fits {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        gap: var(--boxel-sp-sm);
      }
      .fit {
        display: grid;
        gap: var(--boxel-sp-5xs);
        margin: 0;
      }
      .fit-box {
        overflow: hidden;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      .fit-badge .fit-box {
        width: 9.375rem;
        height: 4.0625rem;
      }
      .fit-strip .fit-box {
        width: 15.625rem;
        height: 4.0625rem;
      }
      .fit-tile .fit-box {
        width: 11.25rem;
        height: 10.625rem;
      }
      .fit-card .fit-box {
        width: 25rem;
        height: 10.625rem;
      }
      figcaption,
      summary {
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
        color: var(--muted-foreground);
      }
      .flows {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp);
      }
      .embedded {
        flex: 1 1 22rem;
        max-width: 36rem;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
      }
      summary {
        cursor: pointer;
      }
      .isolated[open] > summary {
        margin-block-end: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

/**
 * The page frame: intro, a sticky sidebar and the sections column. Sections are yielded, so their card styling reaches them
 * through `:deep()`.
 */
export class DemoShell extends GlimmerComponent<{
  Args: { eyebrow: string; title: string; intro?: string };
  Blocks: { nav: []; default: [] };
}> {
  <template>
    <article class='showcase'>
      <header class='intro'>
        <span class='eyebrow'>{{@eyebrow}}</span>
        <h1>{{@title}}</h1>
        {{#if @intro}}<p>{{@intro}}</p>{{/if}}
      </header>
      <div class='layout'>
        <aside class='sidebar' aria-label='Building blocks'>
          {{yield to='nav'}}
        </aside>
        <div class='blocks'>
          {{yield}}
        </div>
      </div>
    </article>
    <style scoped>
      .showcase {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        max-width: 70rem;
        margin-inline: auto;
      }
      .intro {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .intro p,
      .blocks :deep(.hint) {
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
        color: var(--muted-foreground);
      }
      .eyebrow,
      .sidebar :deep(.group-label) {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .layout {
        display: grid;
        grid-template-columns: 11rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp-lg);
      }
      .sidebar {
        position: sticky;
        top: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp);
      }
      .sidebar :deep(.nav-group) {
        display: grid;
        gap: var(--boxel-sp-2xs);
      }
      .blocks {
        display: grid;
        gap: var(--boxel-sp-lg);
      }
      .blocks :deep(.block) {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        scroll-margin-top: var(--boxel-sp);
      }
      /* mirror the rail's active stop on the section itself */
      .blocks :deep(.block.is-active) {
        box-shadow: 0 0 0 2px var(--ring);
      }
      @container (width < 40rem) {
        .layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .sidebar {
          position: static;
        }
      }
    </style>
  </template>
}

/** Scrolls to a section inside the page that holds the clicked nav stop. */
export function scrollToSection(id: string, event: Event) {
  let root = (event.currentTarget as HTMLElement).closest('.showcase');
  root
    ?.querySelector(`[data-sect='${id}']`)
    ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
}
