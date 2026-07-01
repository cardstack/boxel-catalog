import GlimmerComponent from '@glimmer/component';
import { type CardContext } from 'https://cardstack.com/base/card-api';

import {
  type Query,
  type SearchEntryWireQuery,
  searchEntryWireQueryFromQuery,
} from '@cardstack/runtime-common';

import { on } from '@ember/modifier';

import { CardContainer } from '@cardstack/boxel-ui/components';
import ListingFittedSkeleton from './listing-fitted-skeleton';
import { CardWithHydration } from './card-with-hydration';

interface CardsGridSignature {
  Args: {
    query: Query;
    realms: string[];
    selectedView: string;
    context?: CardContext;
    onClear?: () => void;
  };
  Element: HTMLElement;
}

export class CardsGrid extends GlimmerComponent<CardsGridSignature> {
  //default to rendering 10 skeletons
  get renderSkeletons() {
    return Array.from({ length: 10 }, (_, i) => i);
  }

  // The v2 `search-entry`-rooted query, adapted from the incoming v1 `Query`.
  // `fitted` is the default rendering, so no `htmlQuery` binding is needed.
  get searchResultsQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.args.query),
      realms: this.args.realms,
    };
  }

  <template>
    <@context.searchResultsComponent
      @query={{this.searchResultsQuery}}
      @overlays={{false}}
      as |results|
    >
      {{#if results.entries.length}}
        <ul
          class='cards {{@selectedView}}-view'
          data-test-cards-grid-cards
          ...attributes
        >
          {{#each results.entries key='id' as |card|}}
            <li
              class='{{@selectedView}}-view-container'
              data-test-card-url={{card.id}}
            >
              <CardWithHydration @card={{card}} @context={{@context}} />
            </li>
          {{/each}}
        </ul>
      {{else if results.isLoading}}
        <ul class='cards {{@selectedView}}-view' ...attributes>
          {{#each this.renderSkeletons}}
            <li class='{{@selectedView}}-view-container'>
              <CardContainer class='card' @displayBoundaries={{true}}>
                <ListingFittedSkeleton />
              </CardContainer>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <div class='no-results' data-test-no-results>
          Nothing matches that.
          {{#if @onClear}}
            <button type='button' class='clear-link' {{on 'click' @onClear}}>
              Show everything
            </button>
          {{/if}}
        </div>
      {{/if}}
    </@context.searchResultsComponent>

    <style scoped>
      .cards {
        --default-grid-view-min-width: 18.75rem;
        --default-grid-view-max-width: 1fr;
        --default-grid-view-height: 22rem;
        --default-strip-view-min-width: 49%;
        --default-strip-view-max-width: 1fr;
        --default-strip-view-height: 180px;

        display: grid;
        gap: 1.375rem;
        list-style-type: none;
        margin: 0;
        padding: var(--boxel-sp-6xs);
      }

      /* Card chrome lives on the grid cell (the fitted template must not own
         radius/background/shadow per delegated-render-control). Height comes
         from a landscape aspect-ratio so cards stay short and responsive. */
      .cards.grid-view .grid-view-container {
        aspect-ratio: 4 / 3;
        border-radius: 1rem;
        overflow: hidden;
        background: var(--card, #fff);
        box-shadow: var(--shadow-sm, 0 14px 30px -22px rgba(0, 0, 0, 0.4));
        transition:
          transform 160ms ease,
          box-shadow 160ms ease;
        /* Masonry packing (multicol): keep each card whole, space vertically. */
        break-inside: avoid;
        margin-bottom: 1.375rem;
      }
      .cards.grid-view .grid-view-container:hover {
        transform: translateY(-4px);
        box-shadow: var(--shadow-lg, 0 26px 44px -22px rgba(0, 0, 0, 0.45));
      }
      /* No-screenshot (monogram) cards are shorter than screenshot ones.
         Mirror the codebase's proven `.parent :deep(descendant:has(x))` shape
         so the child-component marker stays unscoped and :has matches. Placed
         after the base rule; equal specificity, so source order wins. */
      .cards.grid-view :deep(.grid-view-container:has([data-no-image='true'])) {
        aspect-ratio: 16 / 9;
      }

      .cards.strip-view {
        grid-template-columns: repeat(
          auto-fill,
          minmax(
            var(--strip-view-min-width, var(--default-strip-view-min-width)),
            var(--strip-view-max-width, var(--default-strip-view-max-width))
          )
        );
        grid-auto-rows: var(
          --strip-view-height,
          var(--default-strip-view-height)
        );
      }

      /* Masonry via multi-column so short (16:9) cards don't leave gaps. */
      .cards.grid-view {
        display: block;
        column-width: var(
          --grid-view-min-width,
          var(--default-grid-view-min-width)
        );
        column-gap: 1.375rem;
      }

      .cards li {
        cursor: pointer;
      }

      .cards :deep(.field-component-card.fitted-format) {
        height: 100%;
      }

      .no-results {
        grid-column: 1 / -1;
        border: 1.5px dashed var(--border, #cdc8ba);
        border-radius: 1rem;
        padding: 3.5rem;
        text-align: center;
        font: 500 0.875rem var(--font-sans, 'IBM Plex Sans', sans-serif);
        color: var(--muted-foreground, #8a8578);
      }
      .clear-link {
        border: none;
        background: transparent;
        color: var(--primary, #00b886);
        text-decoration: underline;
        cursor: pointer;
        font: inherit;
      }
    </style>
  </template>
}
