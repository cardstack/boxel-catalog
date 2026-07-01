import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { type CardContext } from 'https://cardstack.com/base/card-api';
import {
  type Query,
  type SearchEntryWireQuery,
  searchEntryWireQueryFromQuery,
} from '@cardstack/runtime-common';

import { cn } from '@cardstack/boxel-ui/helpers';
import { PILL_TYPE_KEYS, typeMetaForKey } from '../listing/listing-type-meta';

interface PillModel {
  key: string; // 'all' | type key
  label: string;
  colorVar: string;
  query: Query;
}

interface CountSignature {
  Args: {
    query: Query;
    realms: string[];
    context?: CardContext;
  };
  Element: HTMLElement;
}

// Reads the whole-set total for a type query from the search response meta,
// without loading the cards into the page.
class PillCount extends GlimmerComponent<CountSignature> {
  get wireQuery(): SearchEntryWireQuery {
    return {
      ...searchEntryWireQueryFromQuery(this.args.query),
      realms: this.args.realms,
      page: { size: 1 },
    };
  }

  <template>
    {{#if @context.searchResultsComponent}}
      <@context.searchResultsComponent @query={{this.wireQuery}} as |results|>
        {{#unless results.isLoading}}
          <span class='count'>{{results.meta.page.total}}</span>
        {{/unless}}
      </@context.searchResultsComponent>
    {{/if}}
    <style scoped>
      .count {
        opacity: 0.55;
        font-variant-numeric: tabular-nums;
      }
    </style>
  </template>
}

interface PillsSignature {
  Args: {
    listingModule: string;
    activeKey: string; // 'all' or a type key
    onSelect: (key: string) => void;
    realms: string[];
    context?: CardContext;
  };
  Element: HTMLElement;
}

export default class TypeFilterPills extends GlimmerComponent<PillsSignature> {
  private queryForName(name: string): Query {
    return {
      filter: {
        on: {
          // @ts-expect-error module href is a string; CodeRef typing is stricter
          module: this.args.listingModule,
          name,
        },
      },
    };
  }

  get pills(): PillModel[] {
    let all: PillModel = {
      key: 'all',
      label: 'All',
      colorVar: '--foreground',
      query: this.queryForName('Listing'),
    };
    let typed = PILL_TYPE_KEYS.map((key) => {
      let meta = typeMetaForKey(key);
      let name = meta.label + 'Listing';
      return {
        key,
        label: meta.label,
        colorVar: meta.colorVar,
        query: this.queryForName(name),
      };
    });
    return [all, ...typed];
  }

  private dotStyle = (colorVar: string) =>
    htmlSafe(`background: var(${colorVar}, #16161c);`);

  private isActive = (key: string) => key === this.args.activeKey;

  <template>
    <div class='type-pills' data-test-type-pills ...attributes>
      {{#each this.pills key='key' as |pill|}}
        <button
          type='button'
          class={{cn 'pill' is-active=(this.isActive pill.key)}}
          data-test-type-pill={{pill.key}}
          {{on 'click' (fn @onSelect pill.key)}}
        >
          <span class='pill-dot' style={{this.dotStyle pill.colorVar}}></span>
          {{pill.label}}
          <PillCount
            @query={{pill.query}}
            @realms={{@realms}}
            @context={{@context}}
          />
        </button>
      {{/each}}
    </div>

    <style scoped>
      .type-pills {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem;
      }
      .pill {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5625rem 0.9375rem;
        border-radius: 999px;
        cursor: pointer;
        font: 600 0.78rem/1 var(--font-sans, 'IBM Plex Sans', sans-serif);
        transition: all 130ms ease;
        border: 1px solid var(--border, #ddd8cb);
        background: var(--card, #fff);
        color: var(--foreground, #46433c);
      }
      .pill.is-active {
        border-color: var(--foreground, #16161c);
        background: var(--foreground, #16161c);
        color: var(--background, #fff);
      }
      .pill-dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
      }
    </style>
  </template>
}
