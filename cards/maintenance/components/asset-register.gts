import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Select, type SelectOption } from '@cardstack/pretui/components/select';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Table, type TableColumn } from '@cardstack/catalog/components/table';

import {
  CollectionToolbar,
  type ToolbarBadge,
} from '../../../components/collection-toolbar';
import { LocationTree } from './location-tree';
import type { Asset } from '../asset';
import type { Location } from '../../events/location';
import type { AssetCategory } from '../asset-category';
import { ASSET_STATUS_HUE, CRITICALITY } from '../maintenance-vocabulary';
import { matchesSearch } from '../utils/display';

type ViewMode = 'grid' | 'list' | 'table';

interface Signature {
  Args: {
    assets: Asset[];
    locations: Location[];
    categories: AssetCategory[];
    onOpen?: (asset: Asset) => void;
    onAdd?: () => void;
  };
  Element: HTMLElement;
}

const VIEW_OPTIONS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

const chipOptions = (badges: ToolbarBadge[]) =>
  badges.map((b) => ({ value: b.id, label: b.label, count: b.count }));

/**
 * The estate's asset list — search, status/criticality/category facets and a
 * location tree, sharing one filtered row set across grid/list/table. Each
 * row's one visual anchor is the tag chip (the monospace Record Identifier),
 * the same anchor Asset's own fitted format uses.
 *
 * Any register of tagged, located, owned things
 * (an IT hardware register, a fleet register) can mount this against its own
 * item shape as long as it carries tag/name/status/criticality/location.
 */
export class AssetRegister extends GlimmerComponent<Signature> {
  @tracked search = '';
  @tracked statusBadge = 'all';
  @tracked criticalityBadge = 'all';
  @tracked categoryId = 'all';
  @tracked locationId: string | undefined;
  @tracked view: ViewMode = 'grid';

  setSearch = (v: string) => (this.search = v);
  setStatusBadge = (id: string) => (this.statusBadge = id);
  setCriticalityBadge = (id: string) => (this.criticalityBadge = id);
  setCategory = (value: string) => {
    this.categoryId = value || 'all';
  };

  get categoryOptions(): SelectOption[] {
    return [
      { value: 'all', label: 'All categories' },
      ...(this.args.categories ?? [])
        .filter(Boolean)
        .map((c) => ({ value: c.id, label: c.name ?? 'Untitled' })),
    ];
  }

  get statusChips() {
    return chipOptions(this.statusBadges);
  }

  get criticalityChips() {
    return chipOptions(this.criticalityBadges);
  }
  setLocation = (id: string | undefined) => (this.locationId = id);
  setView = (id: string) => (this.view = id as ViewMode);

  get assets(): Asset[] {
    return (this.args.assets ?? []).filter(Boolean);
  }

  get statusBadges(): ToolbarBadge[] {
    let counts = new Map<string, number>();
    for (let a of this.assets)
      counts.set(a.status ?? '', (counts.get(a.status ?? '') ?? 0) + 1);
    let ids = Array.from(
      new Set(this.assets.map((a) => a.status).filter(Boolean)),
    ) as string[];
    return [
      { id: 'all', label: 'All', count: this.assets.length },
      ...ids.map((id) => ({
        id,
        label: id.replace(/-/g, ' '),
        count: counts.get(id) ?? 0,
      })),
    ];
  }

  get criticalityBadges(): ToolbarBadge[] {
    let counts = new Map<string, number>();
    for (let a of this.assets) {
      let v = a.criticality?.level;
      if (v) counts.set(v, (counts.get(v) ?? 0) + 1);
    }
    return [
      { id: 'all', label: 'All', count: this.assets.length },
      ...CRITICALITY.map((c) => ({
        id: c.value,
        label: c.value,
        count: counts.get(c.value) ?? 0,
      })),
    ];
  }

  // Drives the Filters button's count badge — how many of the two axes
  // (status, criticality) have moved off "all", so a collapsed filter set
  // stays legible without reopening the dropdown.
  get activeFilterCount(): number {
    let n = 0;
    if (this.statusBadge !== 'all') n++;
    if (this.criticalityBadge !== 'all') n++;
    return n;
  }

  get filteredAssets(): Asset[] {
    return this.assets.filter((a) => {
      if (this.statusBadge !== 'all' && a.status !== this.statusBadge)
        return false;
      if (
        this.criticalityBadge !== 'all' &&
        a.criticality?.level !== this.criticalityBadge
      )
        return false;
      if (this.categoryId !== 'all' && a.categoryId !== this.categoryId)
        return false;
      if (this.locationId && a.locationId !== this.locationId) return false;
      return matchesSearch(
        this.search,
        a.tag,
        a.name,
        a.categoryName,
        a.locationName,
        a.serialNumber,
      );
    });
  }

  get locationCounts(): Record<string, { assets: number; overdue: number }> {
    let out: Record<string, { assets: number; overdue: number }> = {};
    for (let a of this.assets) {
      let id = a.locationId;
      if (!id) continue;
      let entry = (out[id] ??= { assets: 0, overdue: 0 });
      entry.assets += 1;
      if (a.status === 'out-of-service') entry.overdue += 1;
    }
    return out;
  }

  hueFor = (status?: string | null) =>
    ASSET_STATUS_HUE[status ?? ''] ?? 'slate';

  criticalityHueFor = (value?: string | null) =>
    CRITICALITY.find((c) => c.value === value)?.hue ?? 'slate';

  open = (asset: Asset) => this.args.onOpen?.(asset);
  add = () => this.args.onAdd?.();

  // The Table yields its rows as CardDef; these read them back as Assets.
  openRow = (item: unknown) => this.args.onOpen?.(item as Asset);
  asAsset = (item: unknown) => item as Asset;
  cellText = (item: unknown, key: string) =>
    String((item as Record<string, unknown>)[key] ?? '');

  get columns(): TableColumn[] {
    return [
      { key: 'tag', label: 'Tag' },
      { key: 'name', label: 'Name' },
      { key: 'categoryName', label: 'Category' },
      { key: 'locationName', label: 'Location' },
      { key: 'status', label: 'Status' },
      { key: 'criticality', label: 'Criticality' },
    ];
  }

  <template>
    <div class='reg' ...attributes>
      <div class='reg-side'>
        <h3 class='reg-side-title'>Locations</h3>
        <LocationTree
          @locations={{@locations}}
          @counts={{this.locationCounts}}
          @selectedId={{this.locationId}}
          @onSelect={{this.setLocation}}
          @defaultExpanded={{true}}
        />
      </div>
      <div class='reg-main'>
        <CollectionToolbar
          @search={{this.search}}
          @onSearch={{this.setSearch}}
          @placeholder='Search tag, name, serial…'
          @activeFilterCount={{this.activeFilterCount}}
        >
          <:filters>
            <div class='filter-group'>
              <span class='filter-group-l'>Status</span>
              <FilterChips
                class='badges'
                @options={{this.statusChips}}
                @value={{this.statusBadge}}
                @onValueChange={{this.setStatusBadge}}
                @label='Filter by status'
              />
            </div>
            <div class='filter-group'>
              <span class='filter-group-l'>Criticality</span>
              <FilterChips
                class='badges'
                @options={{this.criticalityChips}}
                @value={{this.criticalityBadge}}
                @onValueChange={{this.setCriticalityBadge}}
                @label='Filter by criticality'
              />
            </div>
          </:filters>
          <:right>
            <Select
              class='cat-select'
              @options={{this.categoryOptions}}
              @value={{this.categoryId}}
              @onValueChange={{this.setCategory}}
              @label='Category'
            />
            <SegmentedControl
              @label='View'
              @options={{VIEW_OPTIONS}}
              @value={{this.view}}
              @onValueChange={{this.setView}}
            />
            {{#if @onAdd}}
              <Button
                @tone='primary'
                @appearance='accent'
                {{on 'click' this.add}}
              >
                <PlusIcon width='16' height='16' role='presentation' />
                Add asset
              </Button>
            {{/if}}
          </:right>
        </CollectionToolbar>

        {{#if (eq this.view 'table')}}
          <div class='reg-table'>
            <Table
              @items={{this.filteredAssets}}
              @columns={{this.columns}}
              @onRowClick={{this.openRow}}
              @caption='Assets'
              @pageSize={{25}}
            >
              <:cell as |row col|>
                {{#let (this.asAsset row) as |a|}}
                  {{#if (eq col.key 'status')}}
                    <StatePill
                      @label={{a.status}}
                      @hue={{this.hueFor a.status}}
                      @dot={{true}}
                    />
                  {{else if (eq col.key 'criticality')}}
                    <StatePill
                      @label={{a.criticality.level}}
                      @hue={{this.criticalityHueFor a.criticality.level}}
                    />
                  {{else if (eq col.key 'tag')}}
                    <code class='tag-chip'>{{a.tag}}</code>
                  {{else}}
                    {{this.cellText row col.key}}
                  {{/if}}
                {{/let}}
              </:cell>
            </Table>
          </div>
        {{else}}
          <ul class='reg-rows reg-rows--{{this.view}}'>
            {{#each this.filteredAssets as |a|}}
              <li>
                <button
                  type='button'
                  class='row'
                  {{on 'click' (fn this.open a)}}
                >
                  <code class='tag-chip'>{{a.tag}}</code>
                  <span class='row-name'>{{a.name}}</span>
                  <span class='row-cat'>{{a.categoryName}}</span>
                  <span class='row-loc'>{{a.locationName}}</span>
                  <StatePill
                    @label={{a.status}}
                    @hue={{this.hueFor a.status}}
                    @dot={{true}}
                  />
                  <StatePill
                    @label={{a.criticality.level}}
                    @hue={{this.criticalityHueFor a.criticality.level}}
                  />
                </button>
              </li>
            {{else}}
              <li class='empty'>
                <EmptyState
                  style={{COMPACT_EMPTY_STYLE}}
                  @title='No assets match this search or filter'
                  @texture={{false}}
                />
              </li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
    </div>
    <style scoped>
      .reg {
        container-type: inline-size;
        display: grid;
        grid-template-columns: 21rem 1fr;
        align-items: start;
        gap: var(--boxel-sp);
        min-width: 0;
        color: var(--foreground);
      }
      @container (width < 55rem) {
        .reg {
          grid-template-columns: 1fr;
        }
      }
      .reg-side {
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-lg);
        background: var(--card);
        padding: var(--boxel-sp-sm);
        box-shadow: var(--shadow-2xs);
      }
      .reg-side-title {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }
      .reg-main {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .cat-select {
        min-width: 12rem;
      }
      /* Rendered inside CollectionToolbar's Filters dropdown — same
         shape/spacing as its own inline chip row. */
      .filter-group {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .filter-group-l {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .badges {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }
      .reg-table {
        overflow-x: auto;
      }
      .reg-rows {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .reg-rows--grid {
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .reg-rows--grid .row {
        flex-direction: column;
        align-items: flex-start;
        min-height: 7rem;
      }
      .row {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-xs);
        width: 100%;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        background: var(--card);
        color: inherit;
        font: inherit;
        text-align: left;
        cursor: pointer;
        min-height: 3rem;
        box-sizing: border-box;
        box-shadow: var(--shadow-2xs);
        transition:
          border-color 150ms ease-out,
          background-color 150ms ease-out,
          transform 150ms ease-out;
      }
      .row:hover,
      .row:focus-visible {
        border-color: var(--primary);
        background: color-mix(in oklch, var(--primary) 5%, var(--card));
        transform: translateY(-1px);
        box-shadow: var(--shadow-sm);
      }
      .row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .row:active {
        transform: translateY(0) scale(0.995);
        transition-duration: 80ms;
      }
      @media (prefers-reduced-motion: reduce) {
        .row {
          transition:
            border-color 150ms ease-out,
            background-color 150ms ease-out;
        }
        .row:hover,
        .row:focus-visible,
        .row:active {
          transform: none;
        }
      }
      .row-name {
        font-weight: 600;
        flex: 1;
        min-width: 8rem;
      }
      .row-cat,
      .row-loc {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
        flex: 1;
        min-width: 6rem;
      }
      .tag-chip {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .empty {
        grid-column: 1 / -1;
      }
    </style>
  </template>
}

export default AssetRegister;
