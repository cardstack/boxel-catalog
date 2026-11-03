import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import ImageDef from '@cardstack/base/image-file-def';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  codeRef,
  realmURL,
  searchEntryWireQueryFromQuery,
  type Query,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import LibraryIcon from '@cardstack/boxel-icons/library';
import SearchIcon from '@cardstack/boxel-icons/search';
import { MONTHS, CATEGORIES } from './aac-activity';

// @ts-expect-error import.meta is supported by the Boxel host
const here: string = import.meta.url;

type GroupBy = 'month' | 'category';

function currentMonth() {
  return String(new Date().getMonth() + 1).padStart(2, '0');
}

// Every activity in the workspace in one live grid, narrowed by month or
// category and a title search. New activities appear on their own once they
// have a month or category, so the page never needs updating by hand.
class LibraryIsolated extends Component<typeof ActivityLibrary> {
  @tracked groupBy: GroupBy = 'month';
  @tracked selected = '';
  @tracked search = '';

  thisMonth = currentMonth();

  get activityRef() {
    return codeRef(here, './aac-activity', 'AacActivity');
  }

  get realms(): string[] {
    const url = this.args.model?.[realmURL];
    return url ? [url.href] : [];
  }

  get options() {
    return this.groupBy === 'month' ? MONTHS : CATEGORIES;
  }

  get selectedLabel() {
    const option = this.options.find((o) => o.value === this.selected);
    if (option) return option.label;
    return this.groupBy === 'month' ? 'All months' : 'All categories';
  }

  get query(): SearchEntryWireQuery {
    const ref = this.activityRef;
    const every: NonNullable<Query['filter']>[] = [{ type: ref }];
    if (this.selected) {
      const key = this.groupBy === 'month' ? 'month' : 'categories';
      every.push({ on: ref, eq: { [key]: this.selected } });
    }
    const term = this.search.trim();
    if (term) {
      every.push({ on: ref, contains: { title: term } });
    }
    const q = searchEntryWireQueryFromQuery({
      filter: { every },
      sort: [
        { by: 'month', on: ref, direction: 'asc' },
        { by: 'title', on: ref, direction: 'asc' },
      ],
    });
    return {
      ...q,
      realms: this.realms,
      filter: {
        ...q.filter,
        eq: { ...q.filter?.eq, htmlQuery: { eq: { format: 'fitted' } } },
      },
    };
  }

  setGroupBy = (groupBy: GroupBy) => {
    this.groupBy = groupBy;
    this.selected = '';
  };

  select = (value: string) => {
    this.selected = this.selected === value ? '' : value;
  };

  updateSearch = (event: Event) => {
    this.search = (event.target as HTMLInputElement).value;
  };

  // In Boxel, open the activity in the card stack; on the published site
  // (and anywhere without a stack) the tile is a plain link to its page.
  openActivity = (id: string, event: MouseEvent) => {
    // On the published site the link opens the song as its own page.
    if (this.args.context?.mode === 'host') return;
    if (!this.args.viewCard) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey) return;
    event.preventDefault();
    this.args.viewCard(new URL(id), 'isolated');
  };

  clearFilters = () => {
    this.selected = '';
    this.search = '';
  };

  <template>
    <article class='library'>
      <header class='mast'>
        <div class='mast-text'>
          <p class='kicker'>Songs · stories · questions</p>
          <h1><@fields.cardTitle /></h1>
          {{#if @model.tagline}}
            <p class='tagline'><@fields.tagline /></p>
          {{/if}}
        </div>
        <div class='search'>
          <SearchIcon width='20' height='20' aria-hidden='true' />
          <input
            type='search'
            placeholder='Find an activity'
            aria-label='Find an activity by name'
            value={{this.search}}
            {{on 'input' this.updateSearch}}
          />
        </div>
      </header>

      <nav class='filters' aria-label='Browse activities'>
        <div class='switch' role='group' aria-label='Browse by'>
          <button
            type='button'
            class='switch-btn {{if (eq this.groupBy "month") "on"}}'
            aria-pressed={{if (eq this.groupBy 'month') 'true' 'false'}}
            {{on 'click' (fn this.setGroupBy 'month')}}
          >By month</button>
          <button
            type='button'
            class='switch-btn {{if (eq this.groupBy "category") "on"}}'
            aria-pressed={{if (eq this.groupBy 'category') 'true' 'false'}}
            {{on 'click' (fn this.setGroupBy 'category')}}
          >By category</button>
        </div>
        <div class='chips'>
          <button
            type='button'
            class='chip {{if (eq this.selected "") "on"}}'
            aria-pressed={{if (eq this.selected '') 'true' 'false'}}
            {{on 'click' (fn this.select '')}}
          >All</button>
          {{#each this.options as |option|}}
            <button
              type='button'
              class='chip
                {{if (eq this.selected option.value) "on"}}
                {{if
                  (eq this.groupBy "month")
                  (if (eq option.value this.thisMonth) "now")
                }}'
              aria-pressed={{if (eq this.selected option.value) 'true' 'false'}}
              {{on 'click' (fn this.select option.value)}}
            >{{option.label}}</button>
          {{/each}}
        </div>
      </nav>

      <@context.searchResultsComponent
        @query={{this.query}}
        @mode='none'
        @overlays={{false}}
        as |results|
      >
        <div class='results-head'>
          <h2>{{this.selectedLabel}}</h2>
          {{#unless results.isLoading}}
            <span class='count' role='status'>
              {{results.meta.page.total}}
              {{if (eq results.meta.page.total 1) 'activity' 'activities'}}
            </span>
          {{/unless}}
        </div>
        <ul class='grid'>
          {{#each results.entries key='id' as |entry|}}
            <li class='cell'>
              <entry.component />
              <a
                class='open'
                href={{entry.id}}
                aria-label='Open activity'
                {{on 'click' (fn this.openActivity entry.id)}}
              ></a>
            </li>
          {{else}}
            <li class='empty'>
              {{#if results.isLoading}}
                Loading activities…
              {{else}}
                <p>No activities here yet.</p>
                <button
                  type='button'
                  class='chip'
                  {{on 'click' this.clearFilters}}
                >
                  Show all activities
                </button>
              {{/if}}
            </li>
          {{/each}}
        </ul>
      </@context.searchResultsComponent>
    </article>

    <style scoped>
      .library {
        --harvest: #f28c28;
        --harvest-deep: #9a3412;
        --paper: #fffaf0;
        --line: #ecdcc0;
        min-height: 100%;
        padding: clamp(16px, 3cqi, 40px);
        background: var(--paper);
        color: #1d1d1b;
        display: grid;
        align-content: start;
        gap: 20px;
        container-type: inline-size;
      }
      .mast {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-end;
        justify-content: space-between;
        gap: 16px;
        padding: clamp(16px, 3cqi, 28px);
        border-radius: 20px;
        background: #fdebd3;
      }
      .kicker {
        margin: 0;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--harvest-deep);
      }
      h1 {
        margin: 4px 0 0;
        font-size: clamp(28px, 5cqi, 44px);
        line-height: 1.05;
      }
      .tagline {
        margin: 8px 0 0;
        max-width: 36rem;
        color: #5d4a35;
      }
      .search {
        display: flex;
        align-items: center;
        gap: 8px;
        min-width: min(100%, 18rem);
        padding: 10px 14px;
        border: 2px solid var(--line);
        border-radius: 999px;
        background: #ffffff;
        color: #6b4a2b;
      }
      .search:focus-within {
        border-color: var(--harvest);
      }
      .search input {
        flex: 1;
        min-width: 0;
        border: none;
        outline: none;
        background: transparent;
        font: inherit;
        font-size: 16px;
      }
      .filters {
        display: grid;
        gap: 12px;
      }
      .switch {
        display: inline-flex;
        justify-self: start;
        padding: 4px;
        border-radius: 999px;
        background: #f3e3c8;
      }
      .switch-btn {
        padding: 8px 18px;
        border: none;
        border-radius: 999px;
        background: transparent;
        color: #6b4a2b;
        font: inherit;
        font-weight: 700;
        cursor: pointer;
      }
      .switch-btn.on {
        background: #ffffff;
        color: var(--harvest-deep);
        box-shadow: 0 1px 4px rgb(0 0 0 / 12%);
      }
      .chips {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .chip {
        padding: 7px 14px;
        border: 2px solid var(--line);
        border-radius: 999px;
        background: #ffffff;
        color: #4a3826;
        font: inherit;
        font-size: 14px;
        font-weight: 700;
        cursor: pointer;
      }
      .chip:hover {
        border-color: var(--harvest);
      }
      .chip.now {
        border-color: var(--harvest);
      }
      .chip.on {
        border-color: var(--harvest-deep);
        background: var(--harvest);
        color: #2b1406;
      }
      .chip:focus-visible,
      .switch-btn:focus-visible {
        outline: 3px solid var(--harvest-deep);
        outline-offset: 2px;
      }
      .results-head {
        display: flex;
        align-items: baseline;
        gap: 12px;
        margin-top: 4px;
      }
      h2 {
        margin: 0;
        font-size: 22px;
      }
      .count {
        color: #6b5a45;
        font-weight: 600;
      }
      .grid {
        list-style: none;
        margin: 12px 0 0;
        padding: 0;
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: 16px;
      }
      .cell {
        position: relative;
        height: 15rem;
        border-radius: 16px;
        transition:
          transform 140ms ease,
          box-shadow 140ms ease;
      }
      .cell:hover {
        transform: translateY(-3px);
        box-shadow: 0 10px 22px rgb(0 0 0 / 14%);
      }
      .open {
        position: absolute;
        inset: 0;
        border-radius: 16px;
        cursor: pointer;
      }
      .open:focus-visible {
        outline: 3px solid var(--harvest-deep);
        outline-offset: 3px;
      }
      @media (prefers-reduced-motion: reduce) {
        .cell {
          transition: none;
        }
      }
      .empty {
        grid-column: 1 / -1;
        display: grid;
        justify-items: start;
        gap: 8px;
        padding: 24px;
        border: 2px dashed var(--line);
        border-radius: 16px;
        color: #6b5a45;
      }
      .empty p {
        margin: 0;
      }
    </style>
  </template>
}

export class ActivityLibrary extends CardDef {
  static displayName = 'Activity Library';
  static icon = LibraryIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field tagline = contains(StringField);
  // The 1200×630 picture shown when the site's link is shared.
  @field shareImage = linksTo(() => ImageDef);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ActivityLibrary) {
      return (
        this.cardInfo?.name?.trim() ||
        this.title?.trim() ||
        `Untitled ${ActivityLibrary.displayName}`
      );
    },
  });

  static isolated = LibraryIsolated;

  // Page title and share-preview (OpenGraph / Twitter) tags for the site.
  static head = class Head extends Component<typeof ActivityLibrary> {
    get pageURL() {
      return this.args.model?.[realmURL]?.href ?? '';
    }
    get description() {
      return (
        this.args.model?.cardDescription?.trim() ||
        this.args.model?.tagline?.trim() ||
        ''
      );
    }
    get image() {
      return this.args.model?.shareImage?.url;
    }
    get icon() {
      return this.args.model?.cardInfo?.cardThumbnail?.url;
    }
    <template>
      {{! template-lint-disable no-forbidden-elements }}
      <title>{{@model.cardTitle}}</title>
      <meta name='description' content={{this.description}} />
      <meta property='og:type' content='website' />
      <meta property='og:site_name' content={{@model.cardTitle}} />
      <meta property='og:title' content={{@model.cardTitle}} />
      <meta property='og:description' content={{this.description}} />
      {{#if this.pageURL}}
        <meta property='og:url' content={{this.pageURL}} />
      {{/if}}
      {{#if this.image}}
        <meta property='og:image' content={{this.image}} />
        <meta property='og:image:width' content='1200' />
        <meta property='og:image:height' content='630' />
        <meta property='og:image:alt' content={{@model.cardTitle}} />
        <meta name='twitter:image' content={{this.image}} />
        <meta name='twitter:card' content='summary_large_image' />
      {{else}}
        <meta name='twitter:card' content='summary' />
      {{/if}}
      <meta name='twitter:title' content={{@model.cardTitle}} />
      <meta name='twitter:description' content={{this.description}} />
      {{#if this.icon}}
        <link rel='icon' href={{this.icon}} />
        <link rel='apple-touch-icon' href={{this.icon}} />
      {{/if}}
    </template>
  };

  static embedded = class Embedded extends Component<typeof ActivityLibrary> {
    <template>
      <div class='row'>
        <LibraryIcon width='28' height='28' aria-hidden='true' />
        <div>
          <strong><@fields.cardTitle /></strong>
          {{#if @model.tagline}}<p><@fields.tagline /></p>{{/if}}
        </div>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 12px 16px;
          background: #fdebd3;
          color: #1d1d1b;
        }
        strong {
          font-size: 1.15rem;
        }
        p {
          margin: 2px 0 0;
          color: #5d4a35;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ActivityLibrary> {
    <template>
      <div class='fit'>
        <LibraryIcon class='icon' aria-hidden='true' />
        <div class='name'><@fields.cardTitle /></div>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: minmax(0, 1fr) auto;
          justify-items: center;
          align-items: center;
          gap: 6px;
          padding: 12px;
          background: #fdebd3;
          color: #9a3412;
          overflow: hidden;
        }
        .icon {
          width: min(48px, 60%);
          height: min(48px, 100%);
        }
        .name {
          font-weight: 800;
          color: #1d1d1b;
          text-align: center;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        @container fitted-card (aspect-ratio > 1.6) or (height <= 80px) {
          .fit {
            grid-template-rows: none;
            grid-template-columns: auto minmax(0, 1fr);
            justify-items: start;
            padding: 8px 12px;
          }
          .icon {
            width: 28px;
            height: 28px;
          }
        }
      </style>
    </template>
  };
}
