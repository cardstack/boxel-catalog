import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  BoxelInput,
  BoxelButton,
  BoxelDropdown,
  Pill,
} from '@cardstack/boxel-ui/components';
import { DropdownArrowFilled } from '@cardstack/boxel-ui/icons';
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
export const CollectionToolbar: TemplateOnlyComponent<Signature> = <template>
  <div class='collection-toolbar' ...attributes>
    <div class='toolbar-left'>
      <div class='search'>
        <BoxelInput
          @type='search'
          @value={{@search}}
          @onInput={{@onSearch}}
          @placeholder={{if @placeholder @placeholder 'Search…'}}
          autocomplete='off'
        />
      </div>
      {{#if @badges.length}}
        <div class='badges' role='group' aria-label='Filter'>
          {{#each @badges as |b|}}
            <Pill
              @kind='button'
              class='badge
                {{if (eq @activeBadge b.id) "badge-on"}}
                {{unless b.count "badge-zero"}}'
              aria-pressed='{{eq @activeBadge b.id}}'
              {{on 'click' (fn @onBadge b.id)}}
            >
              <:default>{{b.label}}
                <span class='badge-count'>{{b.count}}</span></:default>
            </Pill>
          {{/each}}
        </div>
      {{/if}}
      {{#if (has-block 'filters')}}
        <BoxelDropdown>
          <:trigger as |bindings|>
            <BoxelButton class='filters-trigger' {{bindings}}>
              <FilterIcon width='14' height='14' role='presentation' />
              Filters
              {{#if @activeFilterCount}}
                <span class='filters-count'>{{@activeFilterCount}}</span>
              {{/if}}
              <DropdownArrowFilled
                class='filters-arrow'
                width='10'
                height='10'
              />
            </BoxelButton>
          </:trigger>
          <:content as |dd|>
            <div class='filters-panel'>
              {{yield dd to='filters'}}
            </div>
          </:content>
        </BoxelDropdown>
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
      --boxel-input-search-background-color: var(--card, var(--boxel-light));
      --boxel-input-search-color: var(--foreground, var(--boxel-dark));
    }
    .search :deep(.search-icon) {
      --boxel-input-search-icon-color: var(
        --muted-foreground,
        var(--boxel-450)
      );
    }
    .badges {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-4xs);
      min-width: 0;
    }
    .badge {
      flex: 0 0 auto;
      white-space: nowrap;
      position: relative;
    }
    /* WCAG 2.5.8: the pill stays 24px tall, the hit area is ~44px. */
    .badge::after {
      content: '';
      position: absolute;
      inset: -0.625rem 0;
    }
    .badge-on {
      --pill-background-color: color-mix(
        in oklab,
        var(--primary, var(--boxel-highlight)) 12%,
        var(--card, var(--boxel-light))
      );
      --pill-font-color: color-mix(
        in oklab,
        var(--primary, var(--boxel-highlight)) 38%,
        var(--card-foreground, var(--boxel-dark))
      );
      --pill-border-color: var(--primary, var(--boxel-highlight));
    }
    .badge-zero {
      opacity: 0.6;
    }
    .badge-count {
      font-variant-numeric: tabular-nums;
      opacity: 0.75;
      margin-left: 0.25rem;
    }
    .filters-trigger {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-height: 32px;
      padding: 0 var(--boxel-sp-xs);
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
      background: color-mix(
        in oklab,
        var(--primary, var(--boxel-highlight)) 16%,
        transparent
      );
      color: var(--primary, var(--boxel-highlight));
      font-size: var(--boxel-font-size-xs);
      font-variant-numeric: tabular-nums;
    }
    .filters-arrow {
      opacity: 0.6;
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
