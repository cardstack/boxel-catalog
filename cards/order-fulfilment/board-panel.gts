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
        {{! Plain div. It used to carry role='button' and tabindex='0'
                    with only a click handler: Enter and Space bubbled to the
                    plane, which starts a keyboard DRAG, so the card could be
                    focused but never opened from the keyboard — and the always-0
                    tabindex fought the plane's own rover model, putting a tab
                    stop on every card. The plane already opens a card on tap via
                    @onOpen, so that is now the single path in and the click
                    handler here was also firing openCard a second time. }}
        <div class='board-card'>
          <div class='bc-top'>
            <span class='bc-num'>{{order.orderNumber}}</span>
            {{#if order.isExpress}}
              <span class='bc-flash'>{{order.priority}}</span>
            {{/if}}
          </div>
          {{! A div rather than a p. The original reason — the wrapper
                      carried role='button', which may not contain semantic
                      descendants — no longer applies now that the card face is a
                      plain div, but a card face is a label, not prose, so a div
                      is still the honest element. }}
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

    .ofb-host {
      flex: 1;
      min-height: 420px;
    }
    .board-card {
      display: flex;
      flex-direction: column;
      gap: 3px;
      height: 100%;
      padding: 10px 11px;
      box-sizing: border-box;
      border: 1px solid var(--border);
      border-radius: 4px;
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
      text-underline-offset: 2px;
    }
    .bc-top {
      display: flex;
      justify-content: space-between;
      gap: 6px;
      align-items: baseline;
    }
    .bc-num {
      font-family: var(--font-mono);
      font-size: 0.82rem;
      font-weight: 800;
    }
    .bc-flash {
      font-size: 0.6rem;
      font-weight: 800;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      padding: 1px 5px;
      border-radius: 2px;
      border: 1px dashed var(--_perf);
    }
    .bc-cust {
      margin: 0;
      font-size: 0.78rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .bc-meta {
      margin-top: auto;
      display: flex;
      justify-content: space-between;
      gap: 6px;
      font-family: var(--font-mono);
      font-variant-numeric: tabular-nums;
      font-size: 0.72rem;
      color: var(--muted-foreground);
    }
    .bc-total {
      font-weight: 800;
      color: var(--card-foreground);
    }
    .bc-wh {
      font-family: var(--font-mono);
      font-size: 0.62rem;
      letter-spacing: 0.1em;
      color: var(--muted-foreground);
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

    .rows {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: 1px;
    }
    .row-btn {
      width: 100%;
      display: grid;
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding: 7px 8px;
      border: 0;
      border-radius: 3px;
      background: transparent;
      font: inherit;
      font-size: 0.85rem;
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
      font-size: 0.8rem;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
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
    .rows[aria-busy='true'] {
      gap: 8px;
      padding: 6px 0;
    }
  </style>
</template>;
