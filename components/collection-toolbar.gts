import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { hash } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { Input } from '@cardstack/pretui/components/input';
import { Popover } from '@cardstack/pretui/components/popover';
import FilterIcon from '@cardstack/boxel-icons/filter';

export interface ToolbarBadge {
  id: string;
  label: string;
  count: number;
}

interface Signature {
  Args: {
    search: string;
    onSearch: (value: string) => void;
    placeholder?: string;
    /** Single visible filter row — omit when the consumer has more than one
        filter axis and uses the `filters` block (a dropdown) instead.
        'all' MUST be index 0 — the caller builds the array in that order. */
    badges?: ToolbarBadge[];
    activeBadge?: string;
    onBadge?: (id: string) => void;
    /** How many filter values differ from their defaults — shown as a count
        on the Filters button so a collapsed filter set stays legible. */
    activeFilterCount?: number;
  };
  Blocks: {
    /** More than one filter axis (Assets: status AND criticality) — rendered
        inside one "Filters" dropdown instead of stacking a badge row per
        axis. Mutually exclusive with `@badges` in practice, not enforced. */
    filters: [{ close: () => void }];
    /** Right group: view switcher, then the `+ Add <Noun>` action. */
    right: [];
  };
  Element: HTMLElement;
}

/**
 * The one collection shell (boxel-search-with-filter §7), built ONCE and
 * reused on every collection tab: search (with the icon, un-inverted) +
 * either an inline badge row (one filter axis) or a single "Filters"
 * dropdown (two or more axes, e.g. Asset status + criticality) pinned left;
 * the caller's view switcher + add action pinned right. Everything fits on
 * one line at any width — a second or third always-visible filter row is
 * exactly the layout this block exists to prevent.
 *
 * Wrapping the input in `.search` is deliberate — BoxelInput puts a passed
 * class on the <input>, whose parent is its own grid, so flex sizing must
 * land on this wrapper.
 */
// FilterChips' options from the toolbar's badges.
function badgeOptions(badges: ToolbarBadge[]) {
  return badges.map((b) => ({ value: b.id, label: b.label, count: b.count }));
}

function noop() {}

export const CollectionToolbar: TemplateOnlyComponent<Signature> = <template>
  <div class='collection-toolbar' ...attributes>
    <div class='toolbar-left'>
      <div class='search'>
        <Input
          @type='search'
          @value={{@search}}
          @onInput={{@onSearch}}
          @placeholder={{if @placeholder @placeholder 'Search…'}}
          aria-label={{if @placeholder @placeholder 'Search'}}
          autocomplete='off'
        />
      </div>
      {{#if @badges.length}}
        <FilterChips
          class='badges'
          @options={{badgeOptions @badges}}
          @value={{@activeBadge}}
          @onValueChange={{if @onBadge @onBadge noop}}
        />
      {{/if}}
      {{#if (has-block 'filters')}}
        <Popover @label='Filters'>
          <:trigger as |_open toggle|>
            <Button
              class='filters-trigger'
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              {{on 'click' toggle}}
            >
              <FilterIcon width='14' height='14' role='presentation' />
              Filters
              {{#if @activeFilterCount}}
                <span class='filters-count'>{{@activeFilterCount}}</span>
              {{/if}}
            </Button>
          </:trigger>
          <:default as |close|>
            <div class='filters-panel'>
              {{yield (hash close=close) to='filters'}}
            </div>
          </:default>
        </Popover>
      {{/if}}
    </div>
    <div class='toolbar-right'>
      {{yield to='right'}}
    </div>
  </div>
  <style scoped>
    .collection-toolbar {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex-wrap: wrap;
      container-type: inline-size;
    }
    .toolbar-left {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex: 1 1 auto;
      min-width: 0;
      flex-wrap: nowrap;
      justify-content: flex-start;
    }
    @container (width < 51rem) {
      .toolbar-left {
        flex-wrap: wrap;
      }
    }
    .toolbar-right {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex: 0 0 auto;
      margin-left: auto;
    }
    .search {
      flex: 0 1 24rem;
      min-width: 8rem;
    }
    /* BoxelInput @type='search' defaults to inverted colours — forward the
         card's own tokens instead. */
    .search :deep(.search) {
      --boxel-input-search-background-color: var(--card);
      --boxel-input-search-color: var(--foreground);
    }
    .search :deep(.search-icon) {
      --boxel-input-search-icon-color: var(--muted-foreground);
    }
    .badges {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-4xs);
      min-width: 0;
    }
    .filters-trigger {
      gap: var(--boxel-sp-5xs);
      white-space: nowrap;
      flex: 0 0 auto;
    }
    .filters-count {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 1.1rem;
      height: 1.1rem;
      padding: 0 0.3rem;
      border-radius: 999px;
      background: color-mix(in oklab, var(--primary) 16%, transparent);
      color: var(--primary-ink);
      font-size: var(--boxel-font-size-xs);
      font-variant-numeric: tabular-nums;
    }
    /* A FIXED width, not min-width — the chip rows wrap inside it instead
         of growing the panel wide enough to overlap whatever sits to the
         right of the trigger in the toolbar row (the view switcher, the Add
         button). A compact anchored popover, not a second toolbar row. */
    .filters-panel {
      display: grid;
      gap: var(--boxel-sp-sm);
      padding: var(--boxel-sp-sm);
      width: 20rem;
    }
  </style>
</template>;

export default CollectionToolbar;
