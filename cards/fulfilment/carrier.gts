import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import TruckIcon from '@cardstack/boxel-icons/truck';
import CreditCard from '@cardstack/boxel-icons/credit-card';
import Receipt from '@cardstack/boxel-icons/receipt';
import Route from '@cardstack/boxel-icons/route';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
// Cyclic with shipment.gts (it links to Carrier); the binding is read only in
// the constructor, never at module evaluation.
import { Shipment } from './shipment';
import { isShipmentException } from './shipment-status';
import StatusChip from './fulfilment-status-chip';
import { LoadingRows } from './fulfilment-ui';
import {
  ALERT_STYLE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { Token } from '@cardstack/pretui/components/token';
import { eq } from '@cardstack/boxel-ui/helpers';

const ACCOUNT_FACTS = [
  { key: 'Account number', value: 'accountNumber' },
  { key: 'Tracking URL', value: 'trackingUrlPattern' },
  { key: 'Dimensional divisor', value: 'dimDivisor' },
  { key: 'Countries', value: 'supportedCountries' },
];

// A carrier's service level: the promise, and what it costs.
//
// The rate is real data on the card, not a call to an API the platform does not
// have. Rate shopping in this app compares configured rates — which is honest,
// and is also how a small business actually works before it integrates.
export class CarrierServiceField extends FieldDef {
  static displayName = 'Carrier Service';

  @field code = contains(StringField);
  @field serviceName = contains(StringField);
  @field deliveryDaysMin = contains(NumberField);
  @field deliveryDaysMax = contains(NumberField);
  @field baseRate = contains(AmountWithCurrency);
  @field perKgRate = contains(NumberField);
  @field supportsTracking = contains(BooleanField);

  get speedLabel() {
    let min = this.deliveryDaysMin;
    let max = this.deliveryDaysMax ?? min;
    if (min == null) {
      return undefined;
    }
    if (min === max) {
      return min === 1 ? 'Next day' : `${min} days`;
    }
    return `${min}–${max} days`;
  }

  static embedded = class Embedded extends Component<
    typeof CarrierServiceField
  > {
    <template>
      <div class='svc'>
        <span class='svc-name'>{{if
            @model.serviceName
            @model.serviceName
            'Unnamed service'
          }}</span>
        <span class='svc-speed'>{{if
            @model.speedLabel
            @model.speedLabel
            '—'
          }}</span>
        <span class='svc-rate'>
          {{#if @model.baseRate.amount}}
            <@fields.baseRate @format='atom' />
          {{else}}
            —
          {{/if}}
        </span>
        <span class='svc-perkg'>
          {{#if @model.perKgRate}}
            +{{@model.perKgRate}}/kg
          {{else}}
            —
          {{/if}}
        </span>
      </div>

      <style scoped>
        .svc {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 6rem 5rem 5.5rem;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-2xs) 0;
          font-size: 0.85rem;
        }
        .svc-name {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .svc-speed,
        .svc-perkg {
          color: var(--muted-foreground);
          font-size: 0.78rem;
        }
        .svc-rate,
        .svc-perkg {
          text-align: right;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .svc-rate {
          font-weight: 700;
          color: var(--foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof CarrierServiceField> {
    <template>
      <span class='svc-atom'>{{@model.serviceName}}</span>
      <style scoped>
        .svc-atom {
          font-size: 0.85em;
          font-weight: 600;
        }
      </style>
    </template>
  };
}

// What a service costs to send a given billable weight. Exported as a pure
// function so the ship desk, the shipment card and any future rules engine all
// price a parcel the same way.
export function quoteService(
  service: CarrierServiceField | undefined,
  billableWeightKg: number | undefined,
): number | undefined {
  if (!service) {
    return undefined;
  }
  let base = service.baseRate?.amount;
  if (base == null) {
    return undefined;
  }
  let perKg = service.perKgRate ?? 0;
  let weight = billableWeightKg ?? 0;
  return Math.round((base + perKg * weight) * 100) / 100;
}

export class Carrier extends CardDef {
  static displayName = 'Carrier';
  static icon = TruckIcon;

  @field code = contains(StringField);
  @field carrierName = contains(StringField);
  @field isActive = contains(BooleanField);
  @field accountNumber = contains(StringField);
  @field services = containsMany(CarrierServiceField);
  @field supportedCountries = containsMany(StringField);

  // `{number}` is substituted by TrackingNumberField. Storing the pattern here
  // is what lets a shipment link out to any carrier without this app knowing
  // any carrier's URL scheme.
  @field trackingUrlPattern = contains(StringField);

  // Volume-to-weight divisor. Carriers differ (5000 and 6000 are both common),
  // so the parcel field takes it as data rather than assuming one.
  @field dimDivisor = contains(NumberField);

  // The carrier's own colour, carried as data. It is never used as text —
  // only as a diluted fill and border — because a brand hue cannot be
  // contrast-checked against a theme in advance.
  @field brandHue = contains(StringField);

  @field onTimeDeliveries = contains(NumberField);
  @field totalDeliveries = contains(NumberField);

  @field onTimePercent = contains(NumberField, {
    computeVia: function (this: Carrier) {
      let total = this.totalDeliveries ?? 0;
      if (total <= 0) {
        return undefined;
      }
      return Math.round(((this.onTimeDeliveries ?? 0) / total) * 100);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Carrier) {
      return this.carrierName?.length ? this.carrierName : 'Untitled Carrier';
    },
  });

  get cheapestService() {
    let priced = (this.services ?? []).filter(
      (s) => s?.baseRate?.amount != null,
    );
    if (!priced.length) {
      return undefined;
    }
    return priced.reduce((a, b) =>
      (a.baseRate?.amount ?? 0) <= (b.baseRate?.amount ?? 0) ? a : b,
    );
  }

  get fastestService() {
    let timed = (this.services ?? []).filter((s) => s?.deliveryDaysMin != null);
    if (!timed.length) {
      return undefined;
    }
    return timed.reduce((a, b) =>
      (a.deliveryDaysMin ?? 99) <= (b.deliveryDaysMin ?? 99) ? a : b,
    );
  }

  static isolated = class Isolated extends Component<typeof Carrier> {
    // The on-time figure on the card is lifetime history. What decides whether
    // you hand them the next parcel is what they are holding RIGHT NOW, which
    // only the shipments pointing at this carrier can answer.
    private shipmentQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.shipmentQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(Shipment);
          let id = this.args.model?.id;
          if (!ref || !id) {
            return undefined;
          }
          return { filter: { on: ref, every: [{ eq: { 'carrier.id': id } }] } };
        },
        () => this.realms,
        { isLive: true },
      );
    }

    // A live query resolving AFTER first paint is why this card asserted "no
    // shipments" about data it had not received. `getCards` publishes `isLoading`
    // and nothing here read it. Guarded on emptiness too, so a background
    // refresh of an already-populated list does not flash a skeleton.
    get isQueryLoading() {
      let q = this.shipmentQuery as any;
      return (
        Boolean(q?.isLoading) && !(q?.instances ?? []).filter(Boolean).length
      );
    }

    private get realms(): string[] | undefined {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    }

    // `getCards` returns a SearchResource, whose `errors` the exported duck type
    // omits — so it is reached by cast. Without reading it a failed query is
    // indistinguishable from an empty realm, and the section would assert
    // "there are none" when the truth is "we could not look".
    // Rows name real cards; opening them is the next step of the task, and a
    // <button> gets the keyboard path and focus ring for free.
    open = (card: any) => {
      (this.args as any).viewCard?.(card, 'isolated');
    };

    get queryError(): string | undefined {
      let entries = (this.shipmentQuery as any)?.errors as any[] | undefined;
      if (!entries?.length) {
        return undefined;
      }
      return entries[0]?.error?.message ?? 'The query failed.';
    }

    get shipments(): any[] {
      return (this.shipmentQuery?.instances ?? []).filter(Boolean);
    }

    get inFlight(): any[] {
      return this.shipments.filter((s) => s.status && s.status !== 'delivered');
    }

    // Stat prints a string verbatim, and an empty one as its dash.
    get onTimeText() {
      let pct = this.args.model?.onTimePercent;
      return pct ? `${pct}%` : '';
    }

    get troubled(): any[] {
      return this.inFlight.filter(
        (s) => s.isLate || isShipmentException(s.status),
      );
    }

    <template>
      <article class='carrier'>
        <header class='hd'>
          <div class='hd-id'>
            {{#if @model.code}}<Token
                class='code'
                @value={{@model.code}}
              />{{/if}}
            <h1 class='name'>{{@model.carrierName}}</h1>
          </div>
          <div class='hd-stats'>
            <Stat
              class='stat'
              @label='On time'
              @value={{this.onTimeText}}
              @roll={{false}}
            />
            <Stat
              class='stat'
              @label='Deliveries'
              @value={{if @model.totalDeliveries @model.totalDeliveries ''}}
            />
            <Stat
              class='stat'
              @label='Services'
              @value={{if @model.services.length @model.services.length 0}}
            />
            <Stat
              class='stat'
              @label='In flight'
              @value={{this.inFlight.length}}
              @roll={{false}}
            />
            <Stat
              class='stat {{if this.troubled.length "alarm"}}'
              @label='Troubled'
              @value={{this.troubled.length}}
              @roll={{false}}
            />
          </div>
        </header>

        <section class='sec'>
          <h2><Route class='sec-icon' role='presentation' />With them now</h2>
          {{#if this.queryError}}
            <Alert
              @tone='danger'
              @title='Could not read shipments for this carrier.'
              style={{ALERT_STYLE.danger}}
            >{{this.queryError}}</Alert>
            {{! Loading is not empty. Space is reserved so the section does not
              jump when the query lands. }}
          {{else if this.isQueryLoading}}
            <LoadingRows />
          {{else if this.inFlight.length}}
            <ul class='cs-rows'>
              {{#each this.inFlight as |s|}}
                <li class='cs-row-li'>
                  <button
                    type='button'
                    class='cs-row {{if s.isLate "cs-late"}}'
                    {{on 'click' (fn this.open s)}}
                  >
                    <Token class='cs-num' @value={{s.shipmentNumber}} />
                    <span class='cs-svc'>{{if
                        s.serviceLevel
                        s.serviceLevel
                        ''
                      }}</span>
                    <span class='cs-dest'>{{if
                        s.latestEvent.location
                        s.latestEvent.location
                        ''
                      }}</span>
                    <span class='cs-state'><StatusChip
                        @label={{s.statusStyle.label}}
                        @hue={{s.statusStyle.hue}}
                      /></span>
                  </button>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='Nothing with this carrier right now'
            />
          {{/if}}
        </section>

        <section class='sec'>
          <h2><Receipt class='sec-icon' role='presentation' />Services and rates</h2>
          <div class='svc-head'>
            <span>Service</span>
            <span>Transit</span>
            <span>Base</span>
            <span>Per kg</span>
          </div>
          {{#if @model.services.length}}
            <@fields.services @format='embedded' />
          {{else}}
            <EmptyState
              class='empty'
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='No services configured'
              @message='Rate shopping will skip this carrier until at least one service has a base rate.'
            />
          {{/if}}
        </section>

        <section class='sec'>
          <h2><CreditCard class='sec-icon' role='presentation' />Account</h2>
          <KeyValue class='kv' @items={{ACCOUNT_FACTS}}>
            <:value as |item|>
              {{#if (eq item.value 'accountNumber')}}
                {{#if @model.accountNumber}}<Token
                    @value={{@model.accountNumber}}
                  />{{else}}—{{/if}}
              {{else if (eq item.value 'trackingUrlPattern')}}
                <span class='mono wrap'>{{if
                    @model.trackingUrlPattern
                    @model.trackingUrlPattern
                    'Not configured — tracking numbers will not link out'
                  }}</span>
              {{else if (eq item.value 'dimDivisor')}}
                <span class='mono'>{{if
                    @model.dimDivisor
                    @model.dimDivisor
                    '—'
                  }}</span>
              {{else}}
                {{if
                  @model.supportedCountries.length
                  (join @model.supportedCountries)
                  '—'
                }}
              {{/if}}
            </:value>
          </KeyValue>
        </section>
      </article>

      <style scoped>
        .carrier {
          /* Type scale, mapped to the house 1.333 modular scale rather than the
             28 hand-picked rem values these cards used to carry — 44 of which
             fell below 12px, under the smallest token the design system has. */
          --t-micro: var(--boxel-font-size-xs);
          --t-sm: var(--boxel-font-size-sm);
          --t-body: var(--boxel-font-size);
          --t-lg: var(--boxel-font-size-lg);
          --t-xl: var(--boxel-font-size-xl);
          /* Isolated gets NO container from the host — every ancestor up to the
             panel is `container-type: normal`, so an `@container` rule here is
             inert until this declares its own. `inline-size`, not `size`: the
             card scrolls, and `size` needs a definite block size. */
          container-type: inline-size;
          container-name: card-iso;

          /* ONE panel primitive. Every full-width tinted block on this card —
             section, note, alert, callout — takes its ground, inset and radius
             from here, because a background makes spacing VISIBLE: while
             sections were separated by whitespace alone, a note padded
             `sp-sm` and a section padded `sp-lg` looked the same. Tint them
             both and their text edges no longer line up down the page, and
             every gap between them reads as a mis-registration rather than a
             rhythm. The inset is the thing that must agree; the tint only
             exposed it. */
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          --panel-pad: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          --panel-radius: var(--radius);
          /* The ONE vertical rhythm. It used to be `margin-top` on `.sec` plus a
             `.cols .sec { margin-top: 0 }` override for the side-by-side case —
             two mechanisms for one relationship, and `.cols` itself had neither,
             so the measured gap above a two-column group was 0px while the gap
             above a stacked section was 28.4px. A tinted panel colliding with
             the text above it is what that 0 looks like. */
          --panel-gap: var(--boxel-sp-xl);
          --ful-rule: color-mix(in oklch, var(--foreground) 12%, transparent);

          display: flex;
          flex-direction: column;
          gap: var(--panel-gap);
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
        }
        .hd {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp);
          align-items: flex-end;
          justify-content: space-between;
          padding-bottom: var(--boxel-sp);
          border-bottom: 0.125rem solid var(--ful-rule);
        }
        /* Pret UI Token for the carrier code, on the muted ink. The body
           knob lands the pill at the micro size. */
        .hd .code {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(var(--t-micro) + 3.5px);
          margin-inline: 0;
        }
        .name {
          margin: 0.1rem 0 0;
          font-size: var(--t-xl);
          line-height: 1.05;
          color: var(--foreground);
        }
        .hd-stats {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-lg);
        }
        /* Pret UI Stat: the knob keeps the figure at the old large size. */
        .stat {
          --text-stat: var(--t-lg);
        }
        .sec {
          /* A surface, not just a gap. Sections were told apart only by spacing,
             and their headings were 12px uppercase muted — pixel-identical to
             every table column label on the card, so "where does a section
             start" had no answer. The ground is mixed toward --foreground so it
             follows the theme in both modes rather than being a grey. */
          padding: var(--panel-pad);
          border-radius: var(--panel-radius);
          background-color: var(--panel-bg);
        }
        .sec h2 {
          /* The section heading is now the loudest uppercase thing on the card:
             --foreground against the column labels' --muted-foreground. Weight
             alone (500 vs 400) was not a readable difference. */
          display: flex;
          align-items: center;
          gap: 0.4375rem;
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--foreground);
        }
        .svc-head {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 6rem 5rem 5.5rem;
          gap: var(--boxel-sp-xs);
          padding-bottom: 0.25rem;
          border-bottom: 1px solid var(--border);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .svc-head span:nth-child(n + 3) {
          text-align: right;
        }
        /* Pret UI KeyValue: label and value sizes and the column gap. */
        .kv {
          --text-ui: var(--t-micro);
          --text-ui-md: var(--t-sm);
          --space-6: 1.25rem;
        }
        .mono {
          font-family: var(--font-mono);
        }
        .wrap {
          overflow-wrap: anywhere;
        }
        /* Room between a compact EmptyState and what sits above it. */
        .empty {
          margin-top: var(--boxel-sp-xs);
        }

        /* Section icons: one size, one muted colour, everywhere. They make the
           card scannable by shape; they must never compete with the heading. */
        h2 .sec-icon {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
          flex: 0 0 auto;
          color: var(--muted-foreground);
        }

        /* One collapse stop. The card is rendered in a resizable stack panel, so
           this fires when a second card opens beside it — not only on a phone. */
        @container card-iso (width < 720px) {
          .cols,
          .grid,
          .two {
            grid-template-columns: 1fr;
          }
        }

        .hd-stats .alarm {
          color: var(--destructive-ink);
        }
        .cs-rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .cs-row {
          display: grid;
          grid-template-columns: 9rem 9rem minmax(0, 1fr) 7rem;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: 0.375rem 0;
          border-top: 1px solid var(--ful-rule);
          font-size: var(--t-sm);
        }
        /* Pret UI Token for the shipment number, on the primary ink. */
        .cs-row .cs-num {
          --pretui-token-hue: var(--primary-ink);
          --text-body: calc(var(--t-sm) + 3.5px);
          justify-self: start;
          margin-inline: 0;
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .cs-svc,
        .cs-dest {
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cs-state {
          text-align: right;
        }
        /* A late row's number takes the danger ink. */
        .cs-row.cs-late .cs-num {
          --pretui-token-hue: var(--destructive-ink);
        }

        .cs-row-li {
          list-style: none;
        }
        /* The row became a button: strip the chrome, keep the grid, and give it a
           real affordance. 160ms sits inside the 150-300ms micro-interaction
           window; `prefers-reduced-motion` removes it rather than shortening it. */
        button.cs-row {
          width: 100%;
          border: 0;
          border-top: 1px solid var(--ful-rule);
          background: none;
          font: inherit;
          color: inherit;
          text-align: left;
          cursor: pointer;
          transition: background-color 160ms ease-out;
        }
        button.cs-row:hover {
          background-color: color-mix(
            in oklch,
            var(--foreground) 5%,
            transparent
          );
        }
        button.cs-row:focus-visible {
          outline: 0.125rem solid var(--ring);
          outline-offset: -0.125rem;
        }
        @media (prefers-reduced-motion: reduce) {
          button.cs-row {
            transition: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Carrier> {
    <template>
      <div class='c-emb'>
        <span class='c-code'>{{#if @model.code}}<Token
              class='c-token'
              @value={{@model.code}}
            />{{/if}}</span>
        <span class='c-name'>{{@model.carrierName}}</span>
        <span class='c-slot'>{{#if
            @model.onTimePercent
          }}{{@model.onTimePercent}}% on time{{else}}—{{/if}}</span>
      </div>

      <style scoped>
        .c-emb {
          display: grid;
          grid-template-columns: 5.5rem minmax(0, 1fr) 8rem;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.9rem;
        }
        .c-code {
          min-width: 0;
        }
        /* Pret UI Token for the carrier code, on the muted ink. */
        .c-code .c-token {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(0.7rem + 3.5px);
          margin-inline: 0;
        }
        .c-name {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .c-slot {
          text-align: right;
          font-size: 0.78rem;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Carrier> {
    <template>
      <span class='c-atom'>{{if
          @model.carrierName
          @model.carrierName
          @model.code
        }}</span>
      <style scoped>
        .c-atom {
          font-weight: 600;
          font-size: 0.85em;
        }
      </style>
    </template>
  };

  // Fitted. Progressive: badge shows the carrier code only; strip adds the
  // name; tile adds the on-time figure; card adds the cheapest service.
  static fitted = class Fitted extends Component<typeof Carrier> {
    <template>
      <article class='fit'>
        <div class='r-head'>
          <div class='eyebrow'>
            <TruckIcon class='glyph' />
            <span class='code'>{{@model.code}}</span>
          </div>
          <h3 class='headline'>{{@model.carrierName}}</h3>
        </div>
        <div class='r-body'>
          {{#if @model.cheapestService}}
            <p class='cheapest'>
              from
              <strong>{{@model.cheapestService.serviceName}}</strong>
              {{@model.cheapestService.speedLabel}}
            </p>
          {{/if}}
        </div>
        <div class='r-meta'>
          {{#if @model.onTimePercent}}
            <span class='ontime'>{{@model.onTimePercent}}% on time</span>
          {{/if}}
          <span class='count'>{{@model.services.length}} services</span>
        </div>
      </article>

      <style scoped>
        .fit {
          --type-ratio: 1.24;
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          /* The block-axis budget. `--type-base` is driven mostly by `cqi`, which
             is huge in a wide, short cell (a 691x105 strip gave 15px, and the
             25px number it produced needed a 30px line box in a row that only
             had 22px — a 12px shear straight through the digits). Capping the
             SCALE against `cqb` fixes every role at once, where capping each
             display role individually did not: in a tall cell the cqi term still
             governs, so tiles are unchanged. */
          --type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb - 0.6 * var(--ar)), 10cqb),
            1.0625rem
          );
          --meta-size: max(
            0.6875rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --glyph-size: max(0.6875rem, min(3cqi, 14cqb));
          --headline-size: max(
            0.6875rem,
            min(calc(var(--type-base) * pow(var(--type-ratio), 2)), 26cqb)
          );
          --pad: clamp(0.375rem, calc(0.125rem + 1.7cqi), 0.875rem);

          width: 100%;
          height: 100%;
          box-sizing: border-box;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 0.125rem;
          padding: var(--pad);
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        /* The card's own icon, the same one its isolated view uses — the
           fitted's visual anchor. It sits on the quiet eyebrow row so it can
           never compete with the headline, and it is the first thing dropped
           at the badge quantum. */
        .eyebrow {
          display: flex;
          align-items: center;
          gap: 0.25rem;
          min-width: 0;
        }
        .glyph {
          flex: none;
          width: var(--glyph-size);
          height: var(--glyph-size);
          color: var(--muted-foreground);
        }
        .r-head {
          grid-area: head;
          overflow: hidden;
          min-height: 0;
        }
        .r-body {
          grid-area: body;
          overflow: hidden;
          min-height: 0;
        }
        .r-meta {
          grid-area: meta;
          overflow: hidden;
          min-height: 0;
          display: flex;
          gap: 0.5rem;
          justify-content: space-between;
          align-items: baseline;
          font-size: var(--meta-size);
          color: var(--muted-foreground);
        }
        .code {
          display: block;
          font-family: var(--font-mono);
          font-size: var(--meta-size);
          font-weight: 700;
          letter-spacing: 0.14em;
          color: var(--muted-foreground);
        }
        .headline {
          margin: 0;
          font-size: var(--headline-size);
          line-height: 1.2;
          font-weight: 700;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .cheapest {
          margin: 0.25rem 0 0;
          font-size: var(--meta-size);
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        .cheapest strong {
          color: var(--card-foreground);
        }
        .ontime {
          font-variant-numeric: tabular-nums;
          font-weight: 700;
        }

        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: auto;
          }
          .eyebrow,
          .r-body,
          .r-meta {
            display: none;
          }
          .headline {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (50px < height <= 130px) {
          .r-body {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .count {
            display: none;
          }
        }
      </style>
    </template>
  };
}

function join(list: string[] | undefined) {
  return (list ?? []).join(', ');
}

export default Carrier;
