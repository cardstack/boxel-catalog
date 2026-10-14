import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { OrderFulfilmentDesk } from './order-fulfilment-desk';
import CardList from '@cardstack/base/components/card-list';
import { Table } from '../../components/table';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { MapRender } from '../../components/map-render';
import StatusChip from '../fulfilment/fulfilment-status-chip';
import { money } from '../fulfilment/fulfilment-format';
import { Input } from '@cardstack/pretui/components/input';
import { Button as PretButton } from '@cardstack/pretui/components/button';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { VIEW_OPTIONS, pct, eq, asStock } from './order-fulfilment-helpers';

export const InventoryPanel: TemplateOnlyComponent<{
  Args: { desk: OrderFulfilmentDesk };
}> = <template>
  <div class='collection-toolbar'>
    <div class='toolbar-left'>
      <div class='search'>
        <Input
          @type='search'
          @value={{@desk.inventorySearch}}
          @onInput={{@desk.setInventorySearch}}
          @placeholder='Search SKU, product, bin or warehouse'
          autocomplete='off'
          aria-label='Search SKU, product, bin or warehouse'
        />
      </div>
      <FilterChips
        class='filters'
        @options={{@desk.inventoryChipOptions}}
        @value={{@desk.inventoryStatus}}
        @onValueChange={{@desk.chooseInventoryStatus}}
        @label='Filter inventory'
      />
    </div>
    <div class='toolbar-right'>
      <SegmentedControl
        @label='View'
        @options={{VIEW_OPTIONS}}
        @value={{@desk.inventoryView}}
        @onValueChange={{@desk.setInventoryView}}
      />
      <PretButton
        @tone='primary'
        @size='s'
        class='add-btn'
        {{on 'click' @desk.createStockRow}}
      ><PlusIcon width='16' height='16' role='presentation' />
        <span class='add-label'>Add Stock Row</span></PretButton>
    </div>
  </div>

  {{#if @desk.hasWarehouseMap}}
    <div class='wh-map'>
      <MapRender
        @coordinates={{@desk.warehousePoints}}
        @mapConfig={{@desk.mapConfig}}
      />
    </div>
  {{/if}}

  <div class='wh-grid'>
    {{#each @desk.warehouseSummary as |w|}}
      {{! Native button: the row holds several facts, more than a Button label. }}
      <button
        type='button'
        class='wh-tile'
        {{on 'click' (fn @desk.openCard w.warehouse)}}
      >
        <span class='wh-code'>{{w.warehouse.code}}</span>
        <span class='wh-name'>{{w.warehouse.warehouseName}}</span>
        <span class='wh-stat'>{{w.skuCount}}
          {{if (eq w.skuCount 1) 'SKU' 'SKUs'}}
          ·
          {{money w.value}}</span>
        {{#if w.isVirtual}}
          <span class='wh-virtual'>Virtual — supplier ships direct</span>
        {{else if w.utilization}}
          <span class='bar'><span
              class='bar-fill'
              style={{pct w.utilization}}
            ></span></span>
          <span class='wh-stat'>{{w.utilization}}% of bins filled</span>
        {{/if}}
      </button>
    {{/each}}
  </div>

  <section class='sub'>
    <h2>Stock rows</h2>
    {{#if @desk.inventoryQuery}}
      {{#if (@desk.isCardListView @desk.inventoryView)}}
        {{! card / list / grid are one renderer, three cell shapes }}
        <CardList
          @context={{@desk.args.context}}
          @query={{@desk.inventoryQuery}}
          @realms={{@desk.realmList}}
          @format='fitted'
          @isLive={{true}}
          @viewOption={{@desk.viewOptionFor @desk.inventoryView}}
        />
      {{else}}
        {{! Columns declared, not derived — and `@pageSize` means the
                      table owns its own paging, so a realm with a thousand stock
                      rows draws twelve and says how many there really are. }}
        <Table
          @items={{@desk.inventoryRows}}
          @columns={{@desk.inventoryColumns}}
          @pageSize={{5}}
          @onRowClick={{@desk.openCard}}
          @emptyMessage={{if
            @desk.inventoryLoading
            'Loading stock…'
            'No stock rows match this filter.'
          }}
        >
          <:cell as |row column|>
            {{#let (asStock row) as |stock|}}
              {{#if (eq column.key 'state')}}
                <StatusChip
                  @label={{stock.stockStateLabel}}
                  @hue={{stock.stockHue}}
                />
              {{/if}}
            {{/let}}
          </:cell>
        </Table>
      {{/if}}
    {{else}}
      <p class='empty'>Loading stock…</p>
    {{/if}}
  </section>
  <style scoped>
    .collection-toolbar {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex-wrap: wrap;
    }
    .toolbar-left {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex: 1 1 auto;
      /* load-bearing: without it a flex item refuses to shrink below its
           content width and the row breaks early for no visible reason */
      min-width: 0;
      /* nowrap until the container is genuinely narrow: flex decides line
           breaks from BASE sizes, so a wrappable group wraps instead of letting
           the search shrink — which would put the badges on line two while
           448px of search sat un-shrunk. Wrapping is enabled at the breakpoint
           below, after the search has had its chance to give up space. */
      flex-wrap: nowrap;
      justify-content: flex-start;
    }
    .toolbar-right {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex: 0 0 auto;
      /* the ONLY auto margin in the toolbar — never on a badge, a badge
           wrapper, or the view selector individually */
      margin-left: auto;
    }
    .toolbar-left .search {
      flex: 0 1 28rem;
      min-width: 8rem;
    }
    .filters {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-xxs);
      flex: 0 1 auto;
      min-width: 0;
      /* never a scroller and never a clipped badge: a filter whose label is
           cut mid-word ("Out" → "Ou…") is one the user cannot read */
      overflow: visible;
    }
    .add-btn {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      flex: 0 0 auto;
      white-space: nowrap;
    }
    @container ful-panel (width < 900px) {
    }
    @container ful-panel (width < 820px) {
      .toolbar-left {
        flex-wrap: wrap;
      }
    }
    @container ful-panel (width < 430px) {
      .add-label {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
      }
    }

    .sub {
      border-top: 1px solid var(--border);
      padding-top: var(--boxel-sp);
    }
    .sub h2 {
      margin: 0 0 var(--boxel-sp-xs);
      font-size: 0.7rem;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .wh-tile:hover {
      background: var(--_sunk);
    }
    .wh-tile:focus-visible {
      outline: 2px solid var(--ring);
    }
    .bar {
      height: 4px;
      border-radius: 999px;
      background: color-mix(in oklch, var(--foreground) 10%, transparent);
      overflow: hidden;
    }
    .bar-fill {
      display: block;
      height: 100%;
      background: color-mix(in oklch, var(--foreground) 50%, transparent);
    }

    .wh-grid {
      display: grid;
      gap: var(--boxel-sp-sm);
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
    }
    .wh-tile {
      display: flex;
      flex-direction: column;
      gap: 4px;
      padding: var(--boxel-sp-sm);
      border: 1px solid var(--border);
      border-radius: 4px;
      background: transparent;
      font: inherit;
      text-align: left;
      color: inherit;
      cursor: pointer;
    }
    .wh-code {
      font-family: var(--font-mono);
      font-size: 0.65rem;
      font-weight: 800;
      letter-spacing: 0.14em;
      color: var(--muted-foreground);
    }
    .wh-name {
      font-size: 1rem;
      font-weight: 700;
    }
    .wh-stat,
    .wh-virtual {
      font-size: 0.75rem;
      color: var(--muted-foreground);
    }
    .wh-map {
      flex: none;
      height: 200px;
      min-height: 200px;
      border-radius: var(--radius);
      overflow: hidden;
      border: 1px solid var(--border);
    }
    @container ful-panel (width < 560px) {
      .wh-map {
        height: 150px;
        min-height: 150px;
      }
    }

    .empty {
      padding: var(--boxel-sp);
      font-size: 0.85rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;
