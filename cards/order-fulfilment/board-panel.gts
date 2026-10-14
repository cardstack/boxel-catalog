import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { OrderFulfilmentDesk } from './order-fulfilment-desk';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Board } from '../../components/board';
import { money } from '../fulfilment/fulfilment-format';
import { Input } from '@cardstack/pretui/components/input';
import { Button as PretButton } from '@cardstack/pretui/components/button';
import { pct, asOrder } from './order-fulfilment-helpers';

export const BoardPanel: TemplateOnlyComponent<{
  Args: { desk: OrderFulfilmentDesk };
}> = <template>
  <div class='collection-toolbar'>
    <div class='toolbar-left'>
      <div class='search'>
        <Input
          @type='search'
          @value={{@desk.boardSearch}}
          @onInput={{@desk.setBoardSearch}}
          @placeholder='Search order number, customer or SKU'
          autocomplete='off'
          aria-label='Search order number, customer or SKU'
        />
      </div>
    </div>
    <div class='toolbar-right'>
      <PretButton
        @tone='primary'
        @size='s'
        class='add-btn'
        {{on 'click' @desk.createOrder}}
      ><PlusIcon width='16' height='16' role='presentation' />
        <span class='add-label'>Add Order</span></PretButton>
    </div>
  </div>

  <Board
    class='ofb-host'
    @items={{@desk.boardOrders}}
    @columns={{@desk.boardColumns}}
    @columnKeyFor={{@desk.columnKeyFor}}
    @onMove={{@desk.moveOrder}}
    @onOpen={{@desk.openCard}}
    @cardSize='regular-tile'
    @boardLabel='Order fulfilment board'
    @emptyMessage={{@desk.boardEmptyMessage}}
  >
    <:card as |card|>
      {{#let (asOrder card) as |order|}}
        <div class='board-card'>
          <div class='bc-top'>
            <span class='bc-num'>{{order.orderNumber}}</span>
            {{#if order.isExpress}}
              <span class='bc-flash'>{{order.priority}}</span>
            {{/if}}
          </div>
          <div class='bc-cust'>{{order.customerName}}</div>
          <div class='bc-meta'>
            <span>{{order.itemCount}} items</span>
            <span class='bc-total'>{{money
                order.total.amount
                order.currencyCode
              }}</span>
          </div>
          {{#if order.warehouseCode}}
            <span class='bc-wh'>{{order.warehouseCode}}</span>
          {{/if}}
        </div>
      {{/let}}
    </:card>
  </Board>

  {{#if @desk.pickLists.length}}
    <section class='sub'>
      <h2>Pick lists on the floor</h2>
      <ul class='rows'>
        {{#each @desk.pickLists as |pl|}}
          <li>
            {{! Native button: the row holds several facts, more than a Button label. }}
            <button
              type='button'
              class='row-btn'
              {{on 'click' (fn @desk.openCard pl)}}
            >
              <span class='mono strong'>{{pl.pickListNumber}}</span>
              <span class='muted'>{{pl.assignedTo}}</span>
              <span class='bar'><span
                  class='bar-fill'
                  style={{pct pl.progressPercent}}
                ></span></span>
              <span class='mono'>{{pl.doneCount}}/{{pl.route.length}}</span>
            </button>
          </li>
        {{/each}}
      </ul>
    </section>
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

    .ofb-host {
      flex: 1;
      min-height: 26.25rem;
    }
    .board-card {
      display: flex;
      flex-direction: column;
      gap: 0.1875rem;
      height: 100%;
      padding: 0.625rem 0.6875rem;
      box-sizing: border-box;
      border: 1px solid var(--border);
      border-radius: 0.25rem;
      background: var(--card);
      color: var(--card-foreground);
      text-align: left;
      cursor: pointer;
      transition: border-color 120ms ease-out;
    }
    .ofb-host :deep([role='listitem']:focus-visible) {
      outline: 2px solid var(--ring);
      outline-offset: 2px;
    }
    .board-card:hover {
      border-color: var(--_perf);
    }
    .board-card:hover .bc-num {
      text-decoration: underline;
      text-underline-offset: 0.125rem;
    }
    .bc-top {
      display: flex;
      justify-content: space-between;
      gap: 0.375rem;
      align-items: baseline;
    }
    .bc-num {
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-sm);
      font-weight: 800;
    }
    .bc-flash {
      font-size: var(--boxel-font-size-2xs);
      font-weight: 800;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      padding: 0.0625rem 0.3125rem;
      border-radius: 2px;
      border: 1px dashed var(--_perf);
    }
    .bc-cust {
      margin: 0;
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .bc-meta {
      margin-top: auto;
      display: flex;
      justify-content: space-between;
      gap: 0.375rem;
      font-family: var(--font-mono);
      font-variant-numeric: tabular-nums;
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
    }
    .bc-total {
      font-weight: 800;
      color: var(--card-foreground);
    }
    .bc-wh {
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      letter-spacing: 0.1em;
      color: var(--muted-foreground);
    }

    .sub {
      border-top: 1px solid var(--border);
      padding-top: var(--boxel-sp);
    }
    .sub h2 {
      margin: 0 0 var(--boxel-sp-xs);
      font-size: var(--boxel-font-size-2xs);
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }

    .rows {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: 0.0625rem;
    }
    .row-btn {
      width: 100%;
      display: grid;
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding: 0.4375rem 0.5rem;
      border: 0;
      border-radius: 0.1875rem;
      background: transparent;
      font-family: inherit;
      font-size: inherit;
      font-weight: inherit;
      line-height: inherit;
      font-size: var(--boxel-font-size-sm);
      text-align: left;
      color: inherit;
      cursor: pointer;
    }
    .row-btn {
      grid-template-columns: 9rem minmax(0, 1fr) minmax(0, 1fr) auto auto;
    }
    .row-btn:hover {
      background: var(--_sunk);
    }
    .row-btn:focus-visible {
      outline: 2px solid var(--ring);
    }
    .mono {
      font-family: var(--font-mono);
    }
    .strong {
      font-weight: 700;
    }
    .muted {
      color: var(--muted-foreground);
      font-size: var(--boxel-font-size-xs);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .bar {
      height: 0.25rem;
      border-radius: 62.5rem;
      background: color-mix(in oklch, var(--foreground) 10%, transparent);
      overflow: hidden;
    }
    .bar-fill {
      display: block;
      height: 100%;
      background: color-mix(in oklch, var(--foreground) 50%, transparent);
    }
    .rows[aria-busy='true'] {
      gap: 0.5rem;
      padding: 0.375rem 0;
    }
  </style>
</template>;
