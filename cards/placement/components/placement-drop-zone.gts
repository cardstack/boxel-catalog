import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Menu } from '@cardstack/pretui/components/menu';

import type {
  PlacementZoneField,
  PlacementField,
} from '@cardstack/catalog/fields/placement/placement-vocabulary';
import {
  occupancyOf,
  placementsIn,
} from '@cardstack/catalog/fields/placement/placement-vocabulary';
import {
  PLACEMENT_DRAG_TYPE,
  type PlacementItem,
  type PlacementMenuItems,
} from '@cardstack/catalog/components/placement-palette';

// The placed chip being dragged, if the drag started in a zone. DataTransfer
// payloads are unreadable until the drop, so this is how a full zone can
// still take its own chips back for a reorder.
let draggingPlaced: { itemId: string; zoneKey: string } | undefined;

function isPlacementDrag(event: DragEvent): boolean {
  return Boolean(event.dataTransfer?.types.includes(PLACEMENT_DRAG_TYPE));
}

interface DropZoneSignature {
  Args: {
    zone: PlacementZoneField;
    // Every placement on the board, not just this zone's — the component
    // filters. Passing the whole list keeps the parent from maintaining one
    // array per zone, which is how a board drifts out of sync with itself.
    placements: PlacementField[];
    // Resolve an itemId to something renderable. The zone stores ids, never
    // objects, so the host stays the single owner of what an item *is*.
    itemFor: (itemId: string) => PlacementItem | undefined;
    onDropItem?: (itemId: string, zoneKey: string) => void;
    // Dropped ON an existing placement: insert before it. This is the
    // within-zone reorder a bare zone drop cannot express — dropping on the
    // zone background still means "this zone, at the end".
    onReorder?: (itemId: string, beforeItemId: string, zoneKey: string) => void;
    onRemove?: (itemId: string, zoneKey: string) => void;
    onSelect?: (item: PlacementItem) => void;
    // Keyboard-operable actions for a placed item (move up / down, move to
    // another zone, remove), shown as a menu beside its chip. Takes the place
    // of the bare remove button.
    menuFor?: (item: PlacementItem) => PlacementMenuItems;
    // Refuse drops entirely (a locked table, a closed shift). The zone greys
    // and the drop is a no-op; the chip snaps back and nothing is written.
    isLocked?: boolean;
    // Refuse drops once capacity is reached, instead of allowing an
    // over-capacity draft. Off by default: seeing the conflict beats having
    // the drag silently swallowed.
    enforceCapacity?: boolean;
    compact?: boolean;
  };
  Blocks: {
    chip?: [PlacementItem];
  };
  Element: HTMLElement;
}

/**
 * One zone on a placement board: a seat, a shelf slot, a room, a shift.
 *
 * **Not a kanban column.** boxel-ui's `KanbanPlane` already owns the
 * columns-of-cards case, and the catalog's `Board` block wraps it — use
 * those when the layout *is* N vertical lists. This exists for the case
 * kanban cannot express: zones positioned freely by the host, in a seating
 * chart, a floor plan, a shelf diagram. The host decides where the zone
 * sits; this component only owns what happens inside it.
 */
export class PlacementDropZone extends GlimmerComponent<DropZoneSignature> {
  @tracked isDragOver = false;
  @tracked dropBeforeId: string | undefined;

  get occupancy() {
    return occupancyOf(this.args.zone, this.args.placements ?? []);
  }

  get zoneKey(): string {
    return this.args.zone?.key ?? '';
  }

  get placed(): PlacementItem[] {
    return placementsIn(this.zoneKey, this.args.placements ?? [])
      .map((p) => (p.itemId ? this.args.itemFor(p.itemId) : undefined))
      .filter(Boolean) as PlacementItem[];
  }

  accepts(event: DragEvent): boolean {
    if (this.args.isLocked || !isPlacementDrag(event)) {
      return false;
    }
    if (!(this.args.enforceCapacity && this.occupancy.isFull)) {
      return true;
    }
    // A reorder inside a full zone does not change its occupancy.
    return draggingPlaced?.zoneKey === this.zoneKey;
  }

  // Shown only when there is a ceiling — an unlimited zone with "3" next to
  // it invites the reader to wonder what the other number was.
  get capacityLabel(): string {
    let { count, capacity } = this.occupancy;
    return capacity == null ? `${count}` : `${count} / ${capacity}`;
  }

  dragEnter = (e: Event) => {
    let event = e as DragEvent;
    if (!this.accepts(event)) {
      return;
    }
    event.preventDefault();
    this.isDragOver = true;
  };

  dragOver = (e: Event) => {
    let event = e as DragEvent;
    if (!this.accepts(event)) {
      return;
    }
    event.preventDefault();
  };

  dragLeave = (e: Event) => {
    let event = e as DragEvent;
    // Moving between the zone's own children also fires dragleave on it.
    let to = event.relatedTarget as Node | null;
    if (to && (event.currentTarget as HTMLElement).contains(to)) {
      return;
    }
    this.isDragOver = false;
    this.dropBeforeId = undefined;
  };

  drop = (e: Event) => {
    let event = e as DragEvent;
    this.isDragOver = false;
    let before = this.dropBeforeId;
    this.dropBeforeId = undefined;
    let accepted = this.accepts(event);
    draggingPlaced = undefined;
    if (!accepted) {
      return;
    }
    event.preventDefault();
    let itemId = event.dataTransfer?.getData(PLACEMENT_DRAG_TYPE);
    if (!itemId || before === itemId) {
      return;
    }
    if (before && this.args.onReorder) {
      this.args.onReorder(itemId, before, this.zoneKey);
      return;
    }
    this.args.onDropItem?.(itemId, this.zoneKey);
  };

  // Chip-level targets. The handler stops propagation so the zone underneath
  // does not also treat the drop as a plain "append to this zone".
  dragOverChip = (target: PlacementItem, event: DragEvent) => {
    if (!this.accepts(event) || !this.args.onReorder) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.dropBeforeId = target.id;
  };

  dragLeaveChip = (target: PlacementItem) => {
    if (this.dropBeforeId === target.id) {
      this.dropBeforeId = undefined;
    }
  };

  isDropBefore = (item: PlacementItem): boolean =>
    this.dropBeforeId === item.id;

  // A placed chip is draggable too, writing the same payload the palette
  // writes — that is what makes zone→zone a single drag instead of
  // "remove, find it again in the rail, drag it back".
  startDragPlaced = (item: PlacementItem, event: DragEvent) => {
    if (this.args.isLocked) {
      event.preventDefault();
      return;
    }
    draggingPlaced = { itemId: item.id, zoneKey: this.zoneKey };
    event.dataTransfer?.setData(PLACEMENT_DRAG_TYPE, item.id);
    event.dataTransfer?.setData('text/plain', item.title ?? item.id);
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
    }
  };

  endDragPlaced = () => {
    draggingPlaced = undefined;
  };

  remove = (itemId: string) => {
    this.args.onRemove?.(itemId, this.zoneKey);
  };

  select = (item: PlacementItem) => {
    this.args.onSelect?.(item);
  };

  <template>
    <section
      class='zone
        {{if this.isDragOver "drag-over"}}
        {{if @isLocked "locked"}}
        {{if this.occupancy.isOver "over"}}
        {{if this.occupancy.isFull "full"}}
        {{if @compact "compact"}}'
      aria-label={{@zone.displayLabel}}
      data-placement-zone={{this.zoneKey}}
      {{on 'dragenter' this.dragEnter}}
      {{on 'dragover' this.dragOver}}
      {{on 'dragleave' this.dragLeave}}
      {{on 'drop' this.drop}}
      ...attributes
    >
      <header class='zone-head'>
        <h4 class='zone-label'>{{@zone.displayLabel}}</h4>
        <span
          class='zone-count'
          title='{{this.occupancy.count}} placed'
        >{{this.capacityLabel}}</span>
      </header>

      {{#if @zone.note}}
        <p class='zone-note'>{{@zone.note}}</p>
      {{/if}}

      <ul class='zone-items'>
        {{#each this.placed key='id' as |item|}}
          <li
            class='placed-chip {{if (this.isDropBefore item) "drop-before"}}'
            {{on 'dragover' (fn this.dragOverChip item)}}
            {{on 'dragleave' (fn this.dragLeaveChip item)}}
          >
            <button
              type='button'
              class='placed-open'
              title={{item.title}}
              draggable={{if @isLocked false true}}
              {{on 'dragstart' (fn this.startDragPlaced item)}}
              {{on 'dragend' this.endDragPlaced}}
              {{on 'click' (fn this.select item)}}
            >
              {{#if (has-block 'chip')}}
                {{yield item to='chip'}}
              {{else}}
                {{item.title}}
              {{/if}}
            </button>
            {{#if @isLocked}}
              {{! A locked zone keeps what it holds. }}
            {{else if @menuFor}}
              <Menu
                @items={{@menuFor item}}
                @label='Move {{item.title}}'
                @align='end'
              >
                <:trigger as |_open toggle|>
                  <IconButton
                    class='placed-menu'
                    @label='Move {{item.title}}'
                    @variant='ghost'
                    @size='xs'
                    {{on 'click' toggle}}
                  >⋯</IconButton>
                </:trigger>
              </Menu>
            {{else if @onRemove}}
              <IconButton
                class='placed-remove'
                @label='Remove {{item.title}}'
                @variant='ghost'
                @size='xs'
                {{on 'click' (fn this.remove item.id)}}
              >×</IconButton>
            {{/if}}
          </li>
        {{/each}}
      </ul>

      {{#if (eq this.placed.length 0)}}
        <p class='zone-empty'>
          {{#if @isLocked}}Locked{{else}}Drop here{{/if}}
        </p>
      {{/if}}

      {{#if this.occupancy.isOver}}
        <p class='zone-warning' role='status'>Over capacity</p>
      {{/if}}
    </section>

    <style scoped>
      .zone {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
        min-width: 0;
        padding: var(--boxel-sp-xs);
        background: var(--card);
        color: var(--foreground);
        /* Dashed until something is in it: an empty zone should read as an
           invitation, not as a finished container. */
        border: 1px dashed var(--border);
        border-radius: var(--radius);
        transition:
          border-color 120ms ease-out,
          background 120ms ease-out;
      }
      .zone:not(:has(.zone-empty)) {
        border-style: solid;
      }
      .zone.drag-over {
        border-color: var(--ring);
        border-style: solid;
        background: color-mix(in oklch, var(--ring) 8%, var(--card));
      }
      .zone.locked {
        opacity: 0.6;
        background: var(--muted);
      }
      /* Over capacity is a data state, consumed diluted so it tints the zone
         without shouting over the content inside it. */
      .zone.over {
        border-color: var(--destructive);
        background: color-mix(in oklch, var(--destructive) 6%, var(--card));
      }
      .zone-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xxs);
      }
      .zone-label {
        margin: 0;
        font: 600 var(--boxel-font-sm);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .zone-count {
        flex: none;
        font: var(--boxel-font-xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .zone.over .zone-count {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .zone-note,
      .zone-empty,
      .zone-warning {
        margin: 0;
        font: var(--boxel-font-xs);
        color: var(--muted-foreground);
      }
      .zone-empty {
        padding: var(--boxel-sp-xs) 0;
        text-align: center;
      }
      .zone-warning {
        color: var(--destructive-ink);
        font-weight: 600;
      }
      .zone-items {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
      }
      .placed-chip {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxxs);
        border-radius: var(--radius-sm);
        background: var(--muted);
      }
      /* The insertion line for a within-zone reorder. A top border rather
         than a moving placeholder, so the list never reflows mid-drag. */
      .placed-chip.drop-before {
        box-shadow: inset 0 0.125rem 0 0 var(--ring);
      }
      .placed-open {
        flex: 1;
        min-width: 0;
        padding: var(--boxel-sp-xxxs) var(--boxel-sp-xxs);
        text-align: left;
        font: var(--boxel-font-sm);
        color: inherit;
        background: none;
        border: 0;
        border-radius: inherit;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        cursor: grab;
      }
      .placed-open:active {
        cursor: grabbing;
      }
      .placed-open:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: -0.125rem;
      }
      .placed-menu,
      .placed-remove {
        flex: none;
        color: var(--muted-foreground);
      }
      .placed-remove:hover {
        color: var(--destructive-ink);
      }
      /* A compact zone (a seat, a locker) has room for the label and the
         count and nothing else. */
      .zone.compact .zone-note,
      .zone.compact .zone-empty {
        display: none;
      }
      @container (width < 140px) {
        .zone-note {
          display: none;
        }
      }
    </style>
  </template>
}

export default PlacementDropZone;
