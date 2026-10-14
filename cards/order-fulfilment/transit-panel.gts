import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { OrderFulfilmentDesk } from './order-fulfilment-desk';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import ChevronRight from '@cardstack/boxel-icons/chevron-right';
import { ShipmentTracker } from '../fulfilment/shipment-tracker';
import StatusChip from '../fulfilment/fulfilment-status-chip';
import { stamp } from '../fulfilment/fulfilment-format';
import { Input } from '@cardstack/pretui/components/input';
import { Button as PretButton } from '@cardstack/pretui/components/button';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { eq } from './order-fulfilment-helpers';

export const TransitPanel: TemplateOnlyComponent<{
  Args: { desk: OrderFulfilmentDesk };
}> = <template>
  <div class='collection-toolbar'>
    <div class='toolbar-left'>
      <div class='search'>
        <Input
          @type='search'
          @value={{@desk.transitSearch}}
          @onInput={{@desk.setTransitSearch}}
          @placeholder='Search shipment, order, carrier or tracking number'
          autocomplete='off'
          aria-label='Search shipment, order, carrier or tracking number'
        />
      </div>
      <FilterChips
        class='filters'
        @options={{@desk.transitChipOptions}}
        @value={{@desk.transitStatus}}
        @onValueChange={{@desk.chooseTransitStatus}}
        @label='Filter transit'
      />
    </div>
  </div>

  {{#if @desk.showAttentionBanner}}
    <section class='alert-box'>
      <h2>Needs attention</h2>
      <ul class='rows'>
        {{#each @desk.needsAttention as |s|}}
          <li>
            {{! Native button: the row holds several facts, more than a Button label. }}
            <button
              type='button'
              class='row-btn'
              {{on 'click' (fn @desk.openCard s)}}
            >
              <span class='mono strong'>{{s.shipmentNumber}}</span>
              <span class='muted'>{{s.latestEvent.statusDescription}}</span>
              <span class='muted'>{{s.latestEvent.location}}</span>
            </button>
          </li>
        {{/each}}
      </ul>
    </section>
  {{/if}}

  {{#if @desk.shipmentsLoading}}
    <ul class='transit' aria-busy='true'>
      <li class='transit-card skeleton'><span
          class='sk-line sk-head'
        ></span><span class='sk-line'></span></li>
      <li class='transit-card skeleton'><span
          class='sk-line sk-head'
        ></span><span class='sk-line'></span></li>
      <li class='transit-card skeleton'><span
          class='sk-line sk-head'
        ></span><span class='sk-line'></span></li>
    </ul>
  {{else}}
    <ul class='transit'>
      {{#each @desk.transitVisible as |s|}}
        <li class='transit-card'>
          {{! Native button: the row holds several facts, more than a Button label. }}
          <button
            type='button'
            class='transit-head'
            {{on 'click' (fn @desk.openCard s)}}
          >
            <span class='mono strong'>{{s.shipmentNumber}}</span>
            <span class='muted'>{{s.carrierLabel}}
              {{s.serviceLevel}}</span>
            <StatusChip
              @label={{s.statusStyle.label}}
              @hue={{s.statusStyle.hue}}
            />
            <ChevronRight
              class='transit-open'
              width='16'
              height='16'
              role='presentation'
            />
          </button>
          {{#if (eq s.status 'delivered')}}
            <dl class='dlv'>
              <div>
                <dt>Delivered</dt>
                <dd>{{stamp s.deliveredAt}}</dd>
              </div>
              <div>
                <dt>Against promise</dt>
                {{#if s.deliveryWindow.latest}}
                  <dd class={{if s.isLate 'neg'}}>{{if
                      s.isLate
                      'Late'
                      'On time'
                    }}</dd>
                {{else}}
                  <dd class='muted'>No promised window</dd>
                {{/if}}
              </div>
              <div class='dlv-pod'>
                <dt>Proof of delivery</dt>
                <dd>{{if
                    s.proofOfDelivery
                    s.proofOfDelivery
                    'Not recorded'
                  }}</dd>
              </div>
            </dl>
          {{/if}}
          <ShipmentTracker
            @status={{s.status}}
            @events={{s.trackingEvents}}
            @deliveryWindow={{s.deliveryWindow}}
            @compact={{true}}
          />
        </li>
      {{else}}
        <li class='empty'>{{@desk.transitEmptyMessage}}</li>
      {{/each}}
    </ul>
    {{#if @desk.transitHiddenCount}}
      <PretButton
        @tone='neutral'
        @appearance='outlined'
        @size='s'
        class='more-btn'
        {{on 'click' @desk.showMoreTransit}}
      >Show
        {{@desk.transitHiddenCount}}
        more</PretButton>
    {{/if}}
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
    @container ful-panel (width < 51.25rem) {
      .toolbar-left {
        flex-wrap: wrap;
      }
    }
    .alert-box h2 {
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

    .alert-box {
      padding: var(--boxel-sp-sm);
      border-left: 0.1875rem solid
        color-mix(in oklch, var(--destructive) 55%, transparent);
      background: color-mix(in oklch, var(--destructive) 7%, transparent);
    }
    .transit {
      margin: 0;
      padding: 0;
      list-style: none;
      display: grid;
      gap: var(--boxel-sp);
      grid-template-columns: repeat(auto-fit, minmax(18.75rem, 1fr));
    }
    .transit-card {
      display: flex;
      flex-direction: column;
      gap: var(--boxel-sp-sm);
      padding: var(--boxel-sp-sm);
      border: 1px solid var(--border);
      border-radius: 0.25rem;
      transition:
        border-color 120ms ease-out,
        box-shadow 120ms ease-out;
    }
    .transit-card:hover,
    .transit-card:focus-within {
      border-color: var(--_perf);
      box-shadow: 0 0.0625rem 0.5rem -0.25rem
        color-mix(in oklch, var(--foreground) 30%, transparent);
    }
    .transit-head .muted {
      flex: 1 1 auto;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .transit-open {
      flex: none;
      color: var(--muted-foreground);
      transition:
        transform 120ms ease-out,
        color 120ms ease-out;
    }
    .transit-card:hover .transit-open,
    .transit-card:focus-within .transit-open {
      color: var(--foreground);
      transform: translateX(0.125rem);
    }
    .transit-card:hover .transit-head .mono,
    .transit-card:focus-within .transit-head .mono {
      text-decoration: underline;
      text-underline-offset: 0.125rem;
    }
    .transit-head:focus-visible {
      outline: 2px solid var(--ring);
      outline-offset: 2px;
    }
    .dlv {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 0.25rem var(--boxel-sp-sm);
      margin: 0;
      padding: var(--boxel-sp-xs) 0;
      border-top: 1px solid var(--_rule);
      border-bottom: 1px solid var(--_rule);
    }
    .dlv-pod {
      grid-column: 1 / -1;
    }
    .dlv dt {
      font-size: var(--boxel-font-size-2xs);
      letter-spacing: 0.1em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .dlv dd {
      margin: 0;
      font-size: var(--boxel-font-size-sm);
    }
    .skeleton {
      gap: var(--boxel-sp-xs);
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
    .sk-head {
      height: 1.125rem;
      width: 60%;
    }
    @media (prefers-reduced-motion: no-preference) {
      .sk-line {
        animation: sk-pulse 1.4s ease-in-out infinite;
      }
    }
    .more-btn {
      align-self: center;
    }
    .transit-head {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      border: 0;
      background: transparent;
      padding: 0;
      font-family: inherit;
      font-size: inherit;
      font-weight: inherit;
      line-height: inherit;
      text-align: left;
      color: inherit;
      cursor: pointer;
    }

    .empty {
      padding: var(--boxel-sp);
      font-size: var(--boxel-font-size-sm);
      color: var(--muted-foreground);
    }
  </style>
</template>;
