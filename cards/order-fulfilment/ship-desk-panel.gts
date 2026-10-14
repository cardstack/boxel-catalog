import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { OrderFulfilmentDesk } from './order-fulfilment-desk';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { money } from '../fulfilment/fulfilment-format';
import { Button as PretButton } from '@cardstack/pretui/components/button';
import { eq, lt, isNumber } from './order-fulfilment-helpers';
import { List } from '@cardstack/pretui/components/list';
import { Item } from '@cardstack/pretui/components/item';

export const ShipDeskPanel: TemplateOnlyComponent<{
  Args: { desk: OrderFulfilmentDesk };
}> = <template>
  <p class='desk-note'>Two steps. First a packed order becomes a parcel; then
    the parcel gets a rate and a carrier.</p>

  <section class='sub'>
    <h2>Step 1 · Packed, needs a parcel
      <span class='count'>{{@desk.ordersAwaitingShipment.length}}</span></h2>
    {{#if @desk.ordersLoading}}
      <ul class='rows' aria-busy='true'>
        <li class='sk-line'></li>
        <li class='sk-line'></li>
      </ul>
    {{else}}
      <ul class='rows'>
        {{#each @desk.ordersAwaitingShipment as |o|}}
          <li class='await-row'>
            {{! Native button: the row holds several facts, more than a Button label. }}
            <button
              type='button'
              class='row-btn await-btn'
              {{on 'click' (fn @desk.openCard o)}}
            >
              <span class='mono strong link'>{{o.orderNumber}}</span>
              <span class='muted'>{{o.customerName}}</span>
              <span class='muted'>{{o.itemCount}} items</span>
              <span class='mono'>{{money o.total.amount o.currencyCode}}</span>
              <span aria-hidden='true'></span>
            </button>
            <PretButton
              @tone='primary'
              @size='s'
              class='mk-parcel'
              {{on 'click' (fn @desk.createShipmentFor o)}}
            >Create parcel</PretButton>
          </li>
        {{else}}
          <li class='empty'>No packed order is waiting for a parcel. Move an
            order to Packing on the board and it appears here.</li>
        {{/each}}
      </ul>
    {{/if}}
  </section>

  <section class='sub'>
    <h2>Step 2 · Labelled, ready to dispatch
      <span class='count'>{{@desk.shipDeskQueue.length}}</span></h2>
    {{#if @desk.shipmentsLoading}}
      <ul class='rows' aria-busy='true'>
        <li class='sk-line'></li>
        <li class='sk-line'></li>
      </ul>
    {{else if @desk.shipDeskQueue.length}}
      <List
        @items={{@desk.shipDeskQueue}}
        @key={{@desk.queueKey}}
        @label='Parcels to rate'
        @selectionMode='single'
        @selected={{@desk.selectedQueueKeys}}
        @onSelectionChange={{@desk.chooseQueued}}
        @rowLabel={{@desk.queueLabel}}
      >
        <:item as |s|>
          <Item @title={{s.shipmentNumber}} />
        </:item>
      </List>

      {{#if @desk.selectedShipment}}
        <div class='ship'>
          <div class='ship-parcel'>
            <h3>Parcel</h3>
            <p class='ship-num'>{{@desk.selectedShipment.shipmentNumber}}</p>
            <p class='muted'>Order
              {{@desk.selectedShipment.orderNumber}}
              · from
              {{@desk.selectedShipment.originCode}}</p>
            <dl class='kv'>
              <div>
                <dt>Measured</dt>
                <dd>{{@desk.selectedShipment.parcel.sizeLabel}}</dd>
              </div>
              <div>
                <dt>Weight</dt>
                <dd>{{@desk.selectedShipment.parcel.weight}} kg</dd>
              </div>
              <div>
                <dt>Customer paid</dt>
                <dd>{{money
                    @desk.selectedShipment.customerPaid.amount
                    @desk.selectedShipment.customerPaid.currency.code
                  }}</dd>
              </div>
            </dl>

            <PretButton
              @tone='primary'
              class='dispatch'
              {{on 'click' (fn @desk.openCard @desk.selectedShipment)}}
            >Open shipment to dispatch</PretButton>
          </div>

          <div class='ship-rates'>
            <h3>Rate comparison</h3>
            <p class='rates-note'>Priced from the services configured on your
              carrier cards, against this parcel's billable weight. No carrier
              API is called.</p>
            <ul class='rate-list'>
              {{#each @desk.rateOptions as |opt|}}
                <li
                  class='rate
                    {{if (eq opt.key @desk.cheapestOption.key) "best"}}'
                >
                  <div class='rate-id'>
                    {{#if (eq opt.key @desk.cheapestOption.key)}}
                      <span class='tagline'>Cheapest</span>
                    {{else if (eq opt.key @desk.fastestOption.key)}}
                      <span class='tagline'>Fastest</span>
                    {{/if}}
                    <span class='rate-name'>{{opt.carrierName}}
                      {{opt.serviceName}}</span>
                    <span class='muted'>{{opt.speed}}
                      ·
                      {{opt.billable}}
                      kg billable</span>
                  </div>
                  <div class='rate-nums'>
                    <span class='rate-cost'>{{money
                        opt.cost
                        opt.currency
                      }}</span>
                    {{#if (isNumber opt.margin)}}
                      <span
                        class='rate-margin {{if (lt opt.margin 0) "neg"}}'
                      >{{money opt.margin opt.currency}} margin</span>
                    {{/if}}
                  </div>
                </li>
              {{else}}
                <li class='empty'>No carrier has a priced service yet. Add one
                  on a Carrier card and it appears here.</li>
              {{/each}}
            </ul>
          </div>
        </div>
      {{/if}}
    {{else}}
      <ul class='rows'>
        <li class='empty'>Nothing has a label yet. Create a parcel above and it
          arrives here for rating and dispatch.</li>
      </ul>
    {{/if}}
  </section>
  <style scoped>
    .sub {
      border-top: 1px solid var(--border);
      padding-top: var(--boxel-sp);
    }
    .sub h2,
    .ship h2,
    .ship h3 {
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
    .row-btn:focus-visible,
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

    .ship {
      display: grid;
      gap: var(--boxel-sp-lg);
      grid-template-columns: minmax(0, 1fr);
    }
    @container ful-panel (width > 45rem) {
      .ship {
        grid-template-columns: minmax(13.75rem, 0.8fr) minmax(0, 1.4fr);
      }
    }
    .ship-num {
      margin: 0;
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-lg);
      font-weight: 800;
    }
    .kv {
      display: grid;
      gap: 0.3125rem;
      margin: var(--boxel-sp-sm) 0 0;
    }
    .kv div {
      display: grid;
      grid-template-columns: 8rem minmax(0, 1fr);
      gap: var(--boxel-sp-xs);
      font-size: var(--boxel-font-size-sm);
    }
    .kv dt {
      color: var(--muted-foreground);
    }
    .kv dd {
      margin: 0;
      font-family: var(--font-mono);
    }
    .dispatch {
      width: 100%;
      margin-top: var(--boxel-sp);
    }

    .rates-note {
      margin: 0 0 var(--boxel-sp-sm);
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
      max-width: 52ch;
    }
    .rate-list {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: 0.375rem;
    }
    .rate {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp);
      justify-content: space-between;
      align-items: center;
      padding: var(--boxel-sp-sm);
      border: 1px solid var(--border);
      border-radius: 0.25rem;
    }
    .rate.best {
      border-width: 2px;
      border-color: var(--_perf);
    }
    .rate-id {
      display: flex;
      flex-direction: column;
      gap: 0.125rem;
      min-width: 0;
    }
    .tagline {
      font-size: var(--boxel-font-size-2xs);
      font-weight: 800;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .rate-name {
      font-weight: 700;
    }
    .rate-nums {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 0.125rem;
      font-family: var(--font-mono);
      font-variant-numeric: tabular-nums;
    }
    .rate-cost {
      font-size: var(--boxel-font-size-md);
      font-weight: 800;
    }
    .rate-margin {
      font-size: var(--boxel-font-size-xs);
      color: var(--muted-foreground);
    }
    .rate-margin.neg {
      font-weight: 800;
      color: var(--destructive-ink);
    }
    .sk-line {
      display: block;
      height: 0.75rem;
      border-radius: 0.1875rem;
      background: var(--_sunk);
    }
    .rows[aria-busy='true'] {
      gap: 0.5rem;
      padding: 0.375rem 0;
    }
    @media (prefers-reduced-motion: no-preference) {
      .sk-line {
        animation: sk-pulse 1.4s ease-in-out infinite;
      }
    }
    .desk-note {
      margin: 0;
      font-size: var(--boxel-font-size-sm);
      color: var(--muted-foreground);
    }
    .sub h2 .count {
      margin-left: 0.4375rem;
      padding: 0.0625rem 0.375rem;
      border-radius: 62.5rem;
      font-family: var(--font-mono);
      font-variant-numeric: tabular-nums;
      letter-spacing: 0;
      background: var(--_sunk);
      color: var(--foreground);
    }
    .await-row {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
    }
    .await-btn {
      flex: 0 1 46rem;
      min-width: 0;
      grid-template-columns:
        9rem minmax(0, 14rem) minmax(0, 6rem)
        max-content minmax(0, 1fr);
    }
    .link {
      text-decoration: underline;
      text-decoration-color: var(--_perf);
      text-underline-offset: 0.125rem;
      color: var(--foreground);
    }
    .await-btn:hover .link,
    .await-btn:focus-visible .link {
      text-decoration-color: currentColor;
    }

    .empty {
      padding: var(--boxel-sp);
      font-size: var(--boxel-font-size-sm);
      color: var(--muted-foreground);
    }
  </style>
</template>;
