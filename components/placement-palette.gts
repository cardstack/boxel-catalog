import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { gt, eq } from '@cardstack/boxel-ui/helpers';
import { BoxelInput, Pill } from '@cardstack/boxel-ui/components';

import type { PlacementField } from '../fields/placement/placement-vocabulary';
import {
  placedItemIds,
  itemKey,
} from '../fields/placement/placement-vocabulary';

// One candidate the palette can offer. Deliberately a plain shape rather
// than a CardDef: the Placement family works for things that are not cards
// (a seat number, an SKU, a row from an import), and a host that does have
// cards passes `id: card.id` and keeps its own lookup.
export interface PlacementItem {
  id: string;
  title: string;
  // Free-text bucket the palette groups by when `groupBy` is on — a role, a
  // department, a category. The palette has no opinion on the vocabulary.
  group?: string;
  // Secondary line, shown under the title when the rail is wide enough.
  detail?: string;
  hue?: string;
}

interface PalettePaletteSignature {
  Args: {
    items: PlacementItem[];
    // What is already on the board. Placed items leave the rail, so the
    // palette always reads as "what is left to do".
    placements?: PlacementField[];
    // Show placed items greyed out instead of removing them — useful when
    // the board is a review surface rather than a work surface.
    keepPlaced?: boolean;
    onDragStart?: (item: PlacementItem, event: DragEvent) => void;
    onSelect?: (item: PlacementItem) => void;
    groupBy?: boolean;
    searchable?: boolean;
    emptyLabel?: string;
    heading?: string;
  };
  Blocks: {
    /** Replace a chip's content while keeping the chip chrome. */
    chip?: [PlacementItem];
  };
  Element: HTMLElement;
}

// The DataTransfer key the palette writes and PlacementDropZone reads. Shared
// through the module rather than retyped at both ends, so a rename cannot
// silently break the handshake.
export const PLACEMENT_DRAG_TYPE = 'application/x-boxel-placement';

/**
 * The source rail of things not yet placed.
 *
 * This is the piece a kanban does not have: on a board every card already
 * sits in a column, so there is no "not yet anywhere" state to render. A
 * placement board starts with a pool and an empty plan, and the rail is
 * where the remaining work is visible. It shrinks as the plan fills, which
 * is the progress signal — no separate counter needed.
 */
export class PlacementPalette extends GlimmerComponent<PalettePaletteSignature> {
  @tracked search = '';
  @tracked draggingId: string | undefined;

  get placedIds(): Set<string> {
    return placedItemIds(this.args.placements ?? []);
  }

  get available(): PlacementItem[] {
    let items = (this.args.items ?? []).filter(Boolean);
    if (!this.args.keepPlaced) {
      items = items.filter((i) => !this.placedIds.has(itemKey(i.id)));
    }
    let needle = this.search.trim().toLowerCase();
    if (!needle) {
      return items;
    }
    return items.filter((i) =>
      [i.title, i.group, i.detail]
        .filter(Boolean)
        .some((v) => v!.toLowerCase().includes(needle)),
    );
  }

  // Groups in first-seen order — not alphabetical, because the host's own
  // ordering usually carries meaning (seniority, priority, floor number) and
  // re-sorting would destroy it.
  get groups(): { name: string; items: PlacementItem[] }[] {
    if (!this.args.groupBy) {
      return [{ name: '', items: this.available }];
    }
    let order: string[] = [];
    let buckets = new Map<string, PlacementItem[]>();
    for (let item of this.available) {
      let name = item.group || 'Ungrouped';
      if (!buckets.has(name)) {
        buckets.set(name, []);
        order.push(name);
      }
      buckets.get(name)!.push(item);
    }
    return order.map((name) => ({ name, items: buckets.get(name)! }));
  }

  get isEmpty(): boolean {
    return this.available.length === 0;
  }

  // "All placed" and "no matches" are different states and must not share a
  // message — one is success, the other is a dead-end the user can fix by
  // clearing the search.
  get emptyMessage(): string {
    if (this.search.trim()) {
      return `Nothing matches “${this.search.trim()}”`;
    }
    if ((this.args.items ?? []).length === 0) {
      return this.args.emptyLabel ?? 'Nothing to place';
    }
    return 'Everything is placed';
  }

  isPlaced = (item: PlacementItem): boolean =>
    this.placedIds.has(itemKey(item.id));

  setSearch = (value: string) => {
    this.search = value;
  };

  startDrag = (item: PlacementItem, event: DragEvent) => {
    this.draggingId = item.id;
    // Two payloads on purpose: the private type carries the id for our own
    // drop zones, and `text/plain` keeps the drag legible to anything else
    // on the page (and to the browser's own drag image).
    event.dataTransfer?.setData(PLACEMENT_DRAG_TYPE, item.id);
    event.dataTransfer?.setData('text/plain', item.title ?? item.id);
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
    }
    this.args.onDragStart?.(item, event);
  };

  endDrag = () => {
    this.draggingId = undefined;
  };

  select = (item: PlacementItem) => {
    this.args.onSelect?.(item);
  };

  <template>
    <section
      class='palette'
      aria-label={{if @heading @heading 'Unplaced items'}}
      ...attributes
    >
      <header class='palette-head'>
        <h3 class='palette-title'>{{if @heading @heading 'To place'}}</h3>
        <Pill
          class='palette-count'
          @kind='default'
        >{{this.available.length}}</Pill>
      </header>

      {{#if @searchable}}
        <div class='palette-search'>
          <BoxelInput
            @type='search'
            @value={{this.search}}
            @onInput={{this.setSearch}}
            @placeholder='Search'
            aria-label='Search unplaced items'
          />
        </div>
      {{/if}}

      {{#if this.isEmpty}}
        <p class='palette-empty' role='status'>{{this.emptyMessage}}</p>
      {{else}}
        {{#each this.groups key='name' as |group|}}
          <div class='palette-group'>
            {{#if (gt group.name.length 0)}}
              <h4 class='group-name'>{{group.name}}</h4>
            {{/if}}
            <ul class='chip-list'>
              {{#each group.items key='id' as |item|}}
                <li>
                  <button
                    type='button'
                    class='chip
                      {{if (eq this.draggingId item.id) "dragging"}}
                      {{if (this.isPlaced item) "placed"}}'
                    draggable='true'
                    data-placement-item={{item.id}}
                    title={{item.title}}
                    {{on 'dragstart' (fn this.startDrag item)}}
                    {{on 'dragend' this.endDrag}}
                    {{on 'click' (fn this.select item)}}
                  >
                    {{#if (has-block 'chip')}}
                      {{yield item to='chip'}}
                    {{else}}
                      <span class='chip-title'>{{item.title}}</span>
                      {{#if item.detail}}
                        <span class='chip-detail'>{{item.detail}}</span>
                      {{/if}}
                    {{/if}}
                  </button>
                </li>
              {{/each}}
            </ul>
          </div>
        {{/each}}
      {{/if}}
    </section>

    <style scoped>
      .palette {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        padding: var(--boxel-sp);
        background: var(--background, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
      }
      .palette-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .palette-title {
        margin: 0;
        font: 600 var(--boxel-font-sm);
        letter-spacing: var(--boxel-lsp-sm);
      }
      .palette-count {
        --pill-font-color: var(--muted-foreground, var(--boxel-450));
      }
      .palette-empty {
        margin: 0;
        padding: var(--boxel-sp) 0;
        text-align: center;
        font: var(--boxel-font-sm);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .palette-group + .palette-group {
        margin-top: var(--boxel-sp-sm);
      }
      .group-name {
        margin: 0 0 var(--boxel-sp-xxs);
        font: 500 var(--boxel-font-xs);
        text-transform: uppercase;
        letter-spacing: var(--boxel-lsp-lg);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .chip-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxxs);
      }
      .chip {
        width: 100%;
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 2px;
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        text-align: left;
        font: var(--boxel-font-sm);
        color: inherit;
        background: var(--muted, var(--boxel-100));
        border: 1px solid transparent;
        border-radius: var(--radius-sm, var(--boxel-border-radius-sm));
        cursor: grab;
      }
      .chip:hover {
        border-color: var(--border, var(--boxel-300));
      }
      .chip:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 1px;
      }
      .chip.dragging {
        opacity: 0.5;
        cursor: grabbing;
      }
      /* Only reachable with `keepPlaced` — the chip stays for reference but
         must not read as available work. */
      .chip.placed {
        opacity: 0.45;
        cursor: default;
      }
      .chip-title {
        font-weight: 500;
      }
      .chip-detail {
        font: var(--boxel-font-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      /* A narrow rail drops the secondary line rather than wrapping it into
         a two-line chip, which would halve how many fit on screen. */
      @container (width < 180px) {
        .chip-detail {
          display: none;
        }
      }
    </style>
  </template>
}

export default PlacementPalette;
