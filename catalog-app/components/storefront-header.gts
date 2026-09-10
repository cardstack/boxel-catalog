import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { BoxelButton, BoxelInput } from '@cardstack/boxel-ui/components';
import { cn } from '@cardstack/boxel-ui/helpers';
import { BoxelIcon } from '@cardstack/boxel-ui/icons';

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
  private onInput = (value: string) => {
    this.args.onSearchInput(value);
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
            <BoxelButton
              @kind='text-only'
              @size='auto'
              class={{cn 'nav-link' is-active=(this.isActive tab.tabId)}}
              data-test-storefront-tab={{tab.tabId}}
              {{on 'click' (fn @onSelectTab tab.tabId)}}
            >
              {{tab.displayName}}
            </BoxelButton>
          {{/each}}
        </nav>

        <div class='search'>
          {{! div.search below is tag-qualified so this wrapper's own layout
              rules don't leak onto BoxelInput's internal element, which also
              carries a literal 'search' class when @type='search'. }}
          <BoxelInput
            @type='search'
            class='search-input'
            placeholder='Search by keyword'
            aria-label='Search by keyword'
            @value={{@searchValue}}
            data-test-storefront-search
            @onInput={{this.onInput}}
          />
        </div>
      </div>
    </header>

    <style scoped>
      .storefront-header {
        position: sticky;
        top: 0;
        z-index: 30;
        background-color: color-mix(
          in oklch,
          var(--background) 86%,
          transparent
        );
        backdrop-filter: blur(0.625rem);
        border-bottom: 1px solid var(--border);
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
        color: var(--foreground);
      }
      .brand-mark {
        width: 1.75rem;
        height: 1.75rem;
        flex-shrink: 0;
        --icon-color: var(--foreground);
      }
      .brand-name {
        font: 600 0.8125rem/1.1 var(--font-sans);
        letter-spacing: -0.01em;
      }
      .brand-name-soft {
        color: var(--muted-foreground);
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
        background-color: transparent;
        border-radius: 62.4375rem;
        font: 500 0.8125rem/1 var(--font-sans);
        color: var(--muted-foreground);
        cursor: pointer;
        transition: all 120ms ease;
      }
      .nav-link:hover {
        color: var(--foreground);
      }
      .nav-link.is-active {
        color: var(--foreground);
        background-color: var(--card);
        box-shadow: 0 1px 4px
          color-mix(in oklch, var(--shadow-color) 6%, transparent);
      }
      div.search {
        margin-left: auto;
        position: relative;
        display: flex;
        align-items: center;
      }
      .search-input {
        --boxel-input-search-background-color: var(--card);
        --boxel-input-search-color: var(--foreground);
        --boxel-input-search-icon-color: var(--primary);
        width: 17rem;
        height: 2.5rem;
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: 62.4375rem;
        color: var(--foreground);
        font: 500 0.8125rem var(--font-sans);
        outline: none;
      }
      .search-input:focus {
        border-color: var(--accent);
        box-shadow: 0 0 0 3px
          color-mix(in oklch, var(--accent) 18%, transparent);
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
