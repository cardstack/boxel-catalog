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
      min-width: 0;
      flex-wrap: nowrap;
      justify-content: flex-start;
    }
    .toolbar-right {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      flex: 0 0 auto;
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
      overflow: visible;
    }
    @container ful-panel (width < 56.25rem) {
    }
    @container ful-panel (width < 51.25rem) {
      .toolbar-left {
        flex-wrap: wrap;
      }
    }
    @container ful-panel (width < 26.875rem) {
      .add-label {
        position: absolute;
        width: 0.0625rem;
        height: 0.0625rem;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
      }
    }

    .empty {
      padding: var(--boxel-sp);
      font-size: var(--boxel-font-size-sm);
      color: var(--muted-foreground);
    }
  </style>
</template>;
