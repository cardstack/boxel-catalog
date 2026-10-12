import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';
import BuildingIcon from '@cardstack/boxel-icons/building';
import Building2Icon from '@cardstack/boxel-icons/building-2';
import LayersIcon from '@cardstack/boxel-icons/layers';
import DoorIcon from '@cardstack/boxel-icons/door';

import {
  Tree,
  buildTree,
  type TreeNode,
  type TreeRowMeta,
} from '@cardstack/catalog/components/tree';
import type { Location } from '@cardstack/catalog/cards/events/location';

export interface LocationCounts {
  /** Things at this exact location. */
  assets?: number;
  /** Alarms at this exact location — overdue PM, assets down. */
  overdue?: number;
}

interface Signature {
  Args: {
    /** Every location the estate knows (any card with `id`, `name`, `kind`, `parentId`). */
    locations: Location[];
    /** Per-location counts keyed by card id; rolled up over descendants for display. */
    counts?: Record<string, LocationCounts>;
    selectedId?: string;
    /** Called with the id, or undefined when the selection is cleared. */
    onSelect?: (id: string | undefined) => void;
    defaultExpanded?: boolean;
    emptyMessage?: string;
  };
  Element: HTMLElement;
}

interface Rollup {
  assets: number;
  overdue: number;
}

const KIND_ICONS: Record<string, unknown> = {
  site: MapPinIcon,
  campus: MapPinIcon,
  building: BuildingIcon,
  warehouse: Building2Icon,
  floor: LayersIcon,
  room: DoorIcon,
  area: DoorIcon,
};

/**
 * The site → building → floor → room tree, with per-node counts rolled up
 * over descendants, click-to-select. Consumes the shared Tree block for the
 * mechanics (carets, indentation, expansion memory) and supplies only the
 * row: a kind glyph, the name, and two numbers that matter.
 *
 * Works for any card set with `id`, `name`, `kind` and `parentId` — it is the
 * Asset Register's location facet and the Maintenance Home's estate map, and
 * a warehouse or a school could mount it unchanged.
 */
export class LocationTree extends GlimmerComponent<Signature> {
  get roots(): TreeNode<Location>[] {
    let items = (this.args.locations ?? []).filter(Boolean);
    return buildTree(items, (l) => (l as Location).parentId ?? undefined);
  }

  get rollups(): Map<string, Rollup> {
    let counts = this.args.counts ?? {};
    let map = new Map<string, Rollup>();
    let walk = (node: TreeNode<Location>): Rollup => {
      let own = counts[node.item.id ?? ''] ?? {};
      let total: Rollup = {
        assets: own.assets ?? 0,
        overdue: own.overdue ?? 0,
      };
      for (let child of node.children) {
        let c = walk(child);
        total.assets += c.assets;
        total.overdue += c.overdue;
      }
      if (node.item.id) map.set(node.item.id, total);
      return total;
    };
    this.roots.forEach(walk);
    return map;
  }

  rollupFor = (loc: Location): Rollup => {
    return this.rollups.get(loc.id ?? '') ?? { assets: 0, overdue: 0 };
  };

  iconFor = (loc: Location) => {
    let kind = (loc.kind ?? '').toLowerCase();
    return KIND_ICONS[kind] ?? MapPinIcon;
  };

  select = (loc: Location) => {
    let id = loc.id;
    this.args.onSelect?.(this.args.selectedId === id ? undefined : id);
  };

  <template>
    <nav class='loc-tree' aria-label='Locations' ...attributes>
      <Tree
        @roots={{this.roots}}
        @defaultExpanded={{@defaultExpanded}}
        @emptyMessage={{if @emptyMessage @emptyMessage 'No locations yet'}}
      >
        <:row as |loc meta|>
          {{#let (this.rollupFor loc) (this.iconFor loc) as |r Icon|}}
            <button
              type='button'
              class='loc-row
                {{if (eq loc.id @selectedId) "is-selected"}}
                {{if r.overdue "has-alarm"}}'
              aria-pressed={{if (eq loc.id @selectedId) 'true' 'false'}}
              {{on 'click' (fn this.select loc)}}
            >
              <Icon class='loc-icon' title={{loc.kind}} />
              <span class='loc-name'>{{loc.name}}</span>
              <span class='loc-counts'>
                {{#if r.overdue}}<span
                    class='loc-alarm'
                    title='overdue or down'
                  >{{r.overdue}}</span>{{/if}}
                <span
                  class='loc-assets'
                  title='assets here and below'
                >{{r.assets}}</span>
              </span>
              {{#if (this.hasDescendants meta)}}
                <span class='sr-only'>{{meta.descendantCount}}
                  places below</span>
              {{/if}}
            </button>
          {{/let}}
        </:row>
      </Tree>
    </nav>
    <style scoped>
      .loc-tree {
        color: var(--foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .loc-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: 100%;
        min-height: 2.25rem;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border: 0;
        border-radius: var(--boxel-border-radius-sm);
        background: transparent;
        color: inherit;
        text-align: left;
        cursor: pointer;
      }
      .loc-row:hover {
        background: var(--muted);
      }
      .loc-row:focus-visible {
        outline: 2px solid var(--ring, var(--primary));
        outline-offset: -2px;
      }
      .loc-row.is-selected {
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
        color: var(--foreground);
        font-weight: 600;
      }
      .loc-icon {
        width: 1rem;
        height: 1rem;
        flex: none;
        color: var(--muted-foreground);
      }
      .is-selected .loc-icon {
        color: var(--foreground);
      }
      .loc-name {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .loc-counts {
        display: flex;
        gap: var(--boxel-sp-4xs);
        align-items: center;
        font-variant-numeric: tabular-nums;
        font-size: var(--boxel-font-size-xs);
      }
      .loc-assets {
        min-width: 1.5rem;
        text-align: center;
        padding: 0 var(--boxel-sp-5xs);
        border-radius: 999px;
        background: var(--muted);
        color: var(--muted-foreground);
      }
      .loc-alarm {
        min-width: 1.5rem;
        text-align: center;
        padding: 0 var(--boxel-sp-5xs);
        border-radius: 999px;
        background: color-mix(
          in oklab,
          var(--destructive, var(--foreground)) 16%,
          var(--card)
        );
        color: var(--destructive, var(--foreground));
        font-weight: 600;
      }
      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
      }
    </style>
  </template>

  hasDescendants = (meta: TreeRowMeta) => meta.descendantCount > 0;
}

export default LocationTree;
