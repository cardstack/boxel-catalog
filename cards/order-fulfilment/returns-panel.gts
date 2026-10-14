import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { OrderFulfilmentDesk } from './order-fulfilment-desk';
import CardList from '@cardstack/base/components/card-list';
import { Table } from '../../components/table';
import { on } from '@ember/modifier';
import PlusIcon from '@cardstack/boxel-icons/plus';
import StatusChip from '../fulfilment/fulfilment-status-chip';
import { Input } from '@cardstack/pretui/components/input';
import { Button as PretButton } from '@cardstack/pretui/components/button';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { VIEW_OPTIONS, eq, asReturn } from './order-fulfilment-helpers';

export const ReturnsPanel: TemplateOnlyComponent<{
  Args: { desk: OrderFulfilmentDesk };
}> = <template>
  <div class='collection-toolbar'>
    <div class='toolbar-left'>
      <div class='search'>
        <Input
          @type='search'
          @value={{@desk.returnsSearch}}
          @onInput={{@desk.setReturnsSearch}}
          @placeholder='Search RMA, customer, reason or order'
          autocomplete='off'
          aria-label='Search RMA, customer, reason or order'
        />
      </div>
      <FilterChips
        class='filters'
        @options={{@desk.returnsChipOptions}}
        @value={{@desk.returnsStatus}}
        @onValueChange={{@desk.chooseReturnsStatus}}
        @label='Filter returns'
      />
    </div>
    <div class='toolbar-right'>
      <SegmentedControl
        @label='View'
        @options={{VIEW_OPTIONS}}
        @value={{@desk.returnsView}}
        @onValueChange={{@desk.setReturnsView}}
      />
      <PretButton
        @tone='primary'
        @size='s'
        class='add-btn'
        {{on 'click' @desk.createReturn}}
      ><PlusIcon width='16' height='16' role='presentation' />
        <span class='add-label'>Add Return</span></PretButton>
    </div>
  </div>

  {{#if @desk.returnsQuery}}
    {{#if (@desk.isCardListView @desk.returnsView)}}
      <CardList
        @context={{@desk.args.context}}
        @query={{@desk.returnsQuery}}
        @realms={{@desk.realmList}}
        @format='fitted'
        @isLive={{true}}
        @viewOption={{@desk.viewOptionFor @desk.returnsView}}
      />
    {{else}}
      <Table
        @items={{@desk.returnsRows}}
        @columns={{@desk.returnsColumns}}
        @pageSize={{10}}
        @onRowClick={{@desk.openCard}}
        @emptyMessage={{if
          @desk.returnsLoading
          'Loading returns…'
          'No returns match this filter.'
        }}
      >
        <:cell as |row column|>
          {{#let (asReturn row) as |rma|}}
            {{#if (eq column.key 'state')}}
              <StatusChip
                @label={{rma.statusStyle.label}}
                @hue={{rma.statusStyle.hue}}
              />
            {{/if}}
          {{/let}}
        </:cell>
      </Table>
    {{/if}}
  {{else}}
    <p class='empty'>No returns match this filter.</p>
  {{/if}}
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

    .empty {
      padding: var(--boxel-sp);
      font-size: 0.85rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;
