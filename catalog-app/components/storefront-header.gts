import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { cn } from '@cardstack/boxel-ui/helpers';
import { IconSearch, BoxelIcon } from '@cardstack/boxel-ui/icons';

interface TabOption {
  tabId: string;
  displayName: string;
}

interface StorefrontHeaderSignature {
  Args: {
    tabs: TabOption[];
    activeTabId: string;
    onSelectTab: (tabId: string) => void;
    searchValue?: string;
    onSearchInput: (value: string) => void;
  };
  Element: HTMLElement;
}

export default class StorefrontHeader extends GlimmerComponent<StorefrontHeaderSignature> {
  private onInput = (event: Event) => {
    this.args.onSearchInput((event.target as HTMLInputElement).value);
  };

  <template>
    <header class='storefront-header' data-test-storefront-header ...attributes>
      <div class='header-inner'>
        <a href='#' class='brand' aria-label='Boxel Catalog home'>
          <BoxelIcon class='brand-mark' aria-hidden='true' />
          <span class='brand-name'>Boxel
            <span class='brand-name-soft'>Catalog</span></span>
        </a>

        <nav class='nav' aria-label='Catalog sections'>
          {{#each @tabs as |tab|}}
            <button
              type='button'
              class={{cn 'nav-link' is-active=(this.isActive tab.tabId)}}
              data-test-storefront-tab={{tab.tabId}}
              {{on 'click' (fn @onSelectTab tab.tabId)}}
            >
              {{tab.displayName}}
            </button>
          {{/each}}
        </nav>

        <div class='search'>
          <IconSearch class='search-icon' width='16' height='16' />
          <input
            type='search'
            class='search-input'
            placeholder='Search by keyword'
            aria-label='Search by keyword'
            value={{@searchValue}}
            data-test-storefront-search
            {{on 'input' this.onInput}}
          />
        </div>
      </div>
    </header>

    <style scoped>
      .storefront-header {
        position: sticky;
        top: 0;
        z-index: 30;
        background: color-mix(
          in srgb,
          var(--background, #ece9e1) 86%,
          transparent
        );
        backdrop-filter: blur(0.625rem);
        border-bottom: 1px solid var(--border, #ddd8cb);
      }
      .header-inner {
        max-width: 80rem;
        margin: 0 auto;
        padding: 0 2rem;
        height: 4rem;
        display: flex;
        align-items: center;
        gap: 2rem;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 0.625rem;
        flex-shrink: 0;
        text-decoration: none;
        color: var(--foreground, #16161c);
      }
      .brand-mark {
        width: 1.75rem;
        height: 1.75rem;
        flex-shrink: 0;
        --icon-color: var(--foreground, #16161c);
      }
      .brand-name {
        font: 600 0.8125rem/1.1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        letter-spacing: -0.01em;
      }
      .brand-name-soft {
        color: var(--muted-foreground, #8a8578);
      }
      .nav {
        display: flex;
        align-items: center;
        gap: 0.125rem;
        margin-left: 0.375rem;
      }
      .nav-link {
        padding: 0.5rem 0.8125rem;
        border: none;
        background: transparent;
        border-radius: 999px;
        font: 500 0.8125rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #7b766a);
        cursor: pointer;
        transition: all 120ms ease;
      }
      .nav-link:hover {
        color: var(--foreground, #16161c);
      }
      .nav-link.is-active {
        color: var(--foreground, #16161c);
        background: var(--card, #fff);
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
      }
      .search {
        margin-left: auto;
        position: relative;
        display: flex;
        align-items: center;
      }
      .search-icon {
        position: absolute;
        left: 0.9375rem;
        color: var(--primary, #00b886);
        pointer-events: none;
      }
      .search-input {
        width: 17rem;
        height: 2.5rem;
        padding: 0 1.125rem 0 2.75rem;
        background: var(--card, #fff);
        border: 1px solid var(--border, #ddd8cb);
        border-radius: 999px;
        color: var(--foreground, #16161c);
        font: 500 0.8125rem var(--font-sans, 'IBM Plex Sans', sans-serif);
        outline: none;
      }
      .search-input:focus {
        border-color: var(--accent, #16e098);
        box-shadow: 0 0 0 3px
          color-mix(in srgb, var(--accent, #16e098) 18%, transparent);
      }

      @container (max-width: 56rem) {
        .nav {
          display: none;
        }
      }
    </style>
  </template>

  isActive = (tabId: string) => tabId === this.args.activeTabId;
}
