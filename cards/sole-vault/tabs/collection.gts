import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Spinner } from '@cardstack/pretui/components/spinner';
import { StatePill } from '../../../components/state-pill';
import { Table } from '../../../components/table';
import ArchiveIcon from '@cardstack/boxel-icons/archive';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';
import PlusIcon from '@cardstack/boxel-icons/plus';
import type { SoleVaultView } from '../sole-vault-app';

interface Signature {
  Args: {
    tracker: SoleVaultView;
  };
}

export class CollectionTab extends GlimmerComponent<Signature> {
  <template>
    <section class='pane pane--collection'>
      <div class='toolbar'>
        <div class='toolbar-left'>
          <div class='search'>
            {{! A text input: @type='search' renders the dark search variant. }}
            <Input
              @type='text'
              @value={{@tracker.search}}
              @onInput={{@tracker.setSearch}}
              @placeholder='Search your collection'
              aria-label='Search your collection'
              autocomplete='off'
            />
          </div>
          <FilterChips
            class='badges'
            @options={{@tracker.saleOptions}}
            @value={{@tracker.saleFilter}}
            @onValueChange={{@tracker.setSaleFilter}}
            @label='Filter your collection'
          />
        </div>
        <div class='toolbar-right'>
          <SegmentedControl
            @options={{@tracker.viewOptions}}
            @value={{@tracker.view}}
            @onValueChange={{@tracker.setView}}
            @label='View'
          />
          <Button
            @tone='primary'
            @appearance='accent'
            {{on 'click' @tracker.addCollectionItem}}
          >
            <PlusIcon width='16' height='16' role='presentation' />
            Add Item
          </Button>
        </div>
      </div>

      {{#if @tracker.vaultError}}
        <p class='empty' role='alert'>
          <ArchiveIcon width='22' height='22' aria-hidden='true' />
          The vault could not load:
          {{@tracker.vaultError}}
        </p>
      {{else if @tracker.vaultLoading}}
        <p class='empty' role='status'><Spinner />Opening the vault…</p>
      {{else if @tracker.filteredItems.length}}
        {{#if (eq @tracker.view 'table')}}
          {{! Same `filteredItems` the grid and list read — one filter, so
          the three views cannot show different row counts. }}
          <div class='table-wrap'>
            <Table
              @columns={{@tracker.itemColumns}}
              @items={{@tracker.filteredItems}}
              @onRowClick={{@tracker.open}}
              @rowKey='id'
              @pageSize={{25}}
              @caption='Your collection'
              @emptyMessage='No pairs match this filter.'
            />
          </div>
        {{else}}
          <ul class='wall {{if (eq @tracker.view "list") "wall--list"}}'>
            {{#each @tracker.filteredItems as |item|}}
              <li>
                {{! Native button: the tile holds a photo, figures and status, which Pret UI Button does not lay out. }}
                <button
                  type='button'
                  class='tile'
                  {{on 'click' (fn @tracker.open item)}}
                >
                  {{! THE SNEAKER WALL: the
                  collection reads as a curated store, not a
                  spreadsheet, which means the photo leads. Falls back
                  to a quiet glyph rather than leaving a blank tile
                  when an item has no photo yet. }}
                  <div class='tile-thumb'>
                    {{#if item.photos.primaryUrl}}
                      <img
                        src={{item.photos.primaryUrl}}
                        alt=''
                        loading='lazy'
                      />
                    {{else}}
                      <ArchiveIcon
                        class='tile-thumb-icon'
                        width='24'
                        height='24'
                        aria-hidden='true'
                      />
                    {{/if}}
                  </div>
                  <div class='tile-body'>
                    {{! Fields read straight off the instance — the pattern this
                  realm actually uses for live-query results (see
                  client-filter-playground.gts). Every value here is a
                  plain attribute or a denormalized computed field, which
                  is why the row needs no link resolution. }}
                    <span class='tile-title'>{{item.itemTitle}}</span>
                    <span class='tile-meta'>
                      {{#if item.variantLabel}}<span
                        >{{item.variantLabel}}</span>{{/if}}
                      {{#if item.condition.code}}<span
                          class='tile-grade'
                        >{{item.condition.code}}</span>{{/if}}
                    </span>
                    {{! StatePill (the realm's own Pill wrapper), not
                    hand-rolled chip spans. It derives its dilution from
                    the SAME hue and from the card's own
                    --card/--card-foreground pair, at percentages that
                    were contrast-checked against every hue — which a
                    hand-tuned color-mix toward `transparent` is not, and
                    which does not follow a linked theme. }}
                    <span class='tile-foot'>
                      {{#if item.verified}}
                        <StatePill @label='Verified' @hue='green' />
                      {{/if}}
                      {{#if item.forSale}}
                        <StatePill @label='For sale' @hue='amber' />
                      {{/if}}
                    </span>
                  </div>
                  {{! The STATIC open cue. A :hover rule alone only pays out
                  after the pointer has arrived, and the pointer only
                  arrives if something already suggested it should — so a
                  row that looks inert at rest never gets hovered. }}
                  <ChevronRightIcon
                    class='tile-open'
                    width='16'
                    height='16'
                    role='presentation'
                  />
                </button>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{else}}
        <p class='empty'>
          <ArchiveIcon width='22' height='22' aria-hidden='true' />
          {{if
            @tracker.items.length
            'No pairs match this filter.'
            'Nothing catalogued yet — add your first pair.'
          }}
        </p>
      {{/if}}
    </section>
    <style scoped>
      .toolbar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-wrap: wrap;
        margin-bottom: 1rem;
      }
      .toolbar-left {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex: 1 1 auto;
        min-width: 0;
        flex-wrap: nowrap;
      }
      .toolbar-right {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex: 0 0 auto;
        margin-left: auto;
      }
      .search {
        flex: 0 1 28rem;
        min-width: 8rem;
      }
      .badges {
        display: flex;
        flex-wrap: wrap;
        gap: 0.35rem;
        min-width: 0;
      }
      .pane {
        animation: stage-enter 240ms cubic-bezier(0.16, 1, 0.3, 1) both;
      }
      @media (prefers-reduced-motion: reduce) {
        .pane {
          animation: none;
        }
      }
      .wall,
      .ledger-list,
      .ledger-rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .wall {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
        gap: 1.25rem;
      }
      .wall.wall--list {
        grid-template-columns: 1fr;
        gap: 0.6rem;
      }
      .table-wrap {
        /* The table scrolls sideways inside its own wrapper; the page never
           does. */
        overflow-x: auto;
      }
      .tile,
      .o-row {
        position: relative;
        display: block;
        width: 100%;
        text-align: left;
        padding: 0;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: inherit;
        font: inherit;
        cursor: pointer;
        overflow: hidden;
        box-shadow: var(--shadow-xs);
        transition:
          transform 180ms cubic-bezier(0.16, 1, 0.3, 1),
          box-shadow 180ms cubic-bezier(0.16, 1, 0.3, 1),
          border-color 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .tile:hover,
      .tile:focus-visible,
      .o-row:hover,
      .o-row:focus-visible {
        transform: translateY(-3px);
        box-shadow: var(--shadow-lg);
        border-color: color-mix(in oklch, var(--primary) 55%, var(--_hairline));
      }
      .tile:focus-visible,
      .o-row:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .tile-open {
        position: absolute;
        top: 0.75rem;
        right: 0.75rem;
        color: var(--muted-foreground);
        transition: transform 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .tile:hover .tile-open,
      .tile:focus-visible .tile-open {
        color: var(--foreground);
        transform: translateX(2px);
      }
      @media (prefers-reduced-motion: reduce) {
        .tile,
        .o-row,
        .cert,
        .tile-open {
          transition: none;
        }
        .tile:hover,
        .tile:focus-visible,
        .o-row:hover,
        .o-row:focus-visible,
        .cert:hover,
        .cert:focus-visible {
          transform: none;
        }
        .tile:hover .tile-open,
        .tile:focus-visible .tile-open {
          transform: none;
        }
      }
      .tile {
        display: grid;
        grid-template-rows: auto minmax(0, 1fr);
      }
      .tile-thumb {
        aspect-ratio: 1 / 1;
        background: var(--_raised);
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }
      .tile-thumb img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .tile-thumb-icon {
        color: var(--muted-foreground);
        opacity: 0.5;
      }
      .tile-body {
        display: grid;
        align-content: start;
        gap: 0.3rem;
        padding: 0.9rem;
      }
      .wall--list .tile {
        grid-template-rows: none;
        grid-template-columns: 3.5rem minmax(0, 1fr);
        align-items: center;
      }
      .wall--list .tile-thumb {
        width: 3.5rem;
        height: 3.5rem;
        aspect-ratio: auto;
      }
      .wall--list .tile-body {
        padding: 0.5rem 0.9rem;
      }
      .tile-title {
        font-weight: 700;
        font-size: 0.9375rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .tile-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 0.6rem;
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .tile-grade {
        font-weight: 700;
        color: var(--foreground);
        text-transform: capitalize;
      }
      .tile-foot {
        display: flex;
        flex-wrap: wrap;
        gap: 0.35rem;
      }
      .empty {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.6rem;
        padding: 2rem;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: var(--muted-foreground);
        font-size: 0.9375rem;
        box-shadow: var(--shadow-xs);
      }
      @container vault (width < 860px) {
        .toolbar-left {
          flex-wrap: wrap;
        }
      }
      @container vault (width < 460px) {
        .wall {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>
  </template>
}
