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
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
// Cyclic with shipment.gts (it links to Carrier); the binding is read only in
// the constructor, never at module evaluation.
import { Shipment } from './shipment';
import { isShipmentException } from './shipment-status';
import { CompoundAtom } from './fulfilment-ui';
import { money } from './fulfilment-format';
import { FitTile } from '../shared/fit-tile';

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
        <span class='lead'>
          <span class='strong'>{{if
              @model.serviceName
              @model.serviceName
              'Unnamed service'
            }}</span>
          <span class='meta'>{{serviceMeta @model}}</span>
        </span>
        <span class='st' data-tone={{if @model.supportsTracking 'ok'}}><span
            class='dot'
          ></span>{{if @model.supportsTracking 'tracked' 'untracked'}}</span>
      </div>
      <style scoped>
        .svc {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-height: 1.75rem;
          padding: 0 var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
          font-size: 0.75rem;
        }
        .lead {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .strong {
          flex: none;
          font-weight: 600;
          color: var(--foreground);
        }
        .meta {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .st {
          flex: none;
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
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
      this.args.viewCard?.(card, 'isolated');
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

    <template>
      <article class='car'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>{{carrierMark
                @model.code
              }}</span>
            <div class='id'>
              <h1 class='name'>{{@model.cardTitle}}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            {{#if @model.onTimePercent}}
              <span
                class='st'
                data-tone={{onTimeTone @model.onTimePercent}}
              ><span class='dot'></span>{{@model.onTimePercent}}% on time</span>
            {{/if}}
            <span class='st' data-tone={{if @model.isActive 'ok'}}><span
                class='dot'
              ></span>{{if @model.isActive 'active' 'inactive'}}</span>
          </div>
        </header>

        <div class='stats'>
          <div class='stat'>
            <span
              class='st cap'
              data-tone={{onTimeTone @model.onTimePercent}}
            ><span class='dot'></span>On time</span>
            <span class='num'>{{if
                @model.onTimePercent
                (concat @model.onTimePercent '%')
                '—'
              }}</span>
            <span class='meta'>{{deliveriesLine @model}}</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Services</span>
            <span class='num'>{{count @model.services}}</span>
            <span class='meta'>{{serviceNames @model.services}}</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Countries</span>
            <span class='num'>{{count @model.supportedCountries}}</span>
            <span class='meta'>{{join @model.supportedCountries}}</span>
          </div>
        </div>

        <section class='blk'>
          <h2>Services</h2>
          {{#if @model.services.length}}
            {{#each @fields.services as |Svc|}}
              <Svc @format='embedded' />
            {{/each}}
          {{else}}
            <p class='row meta'>No services configured — rate shopping skips
              this carrier.</p>
          {{/if}}
        </section>

        <section class='blk'>
          <h2>Account</h2>
          <dl class='kv'>
            <dt class='cap'>Code</dt>
            <dd class='mono'>{{dash @model.code}}</dd>
            <dt class='cap'>Account number</dt>
            <dd class='mono'>{{dash @model.accountNumber}}</dd>
            <dt class='cap'>Volumetric divisor</dt>
            <dd class='mono'>{{dash @model.dimDivisor}}</dd>
            <dt class='cap'>Supported countries</dt>
            <dd>{{dash (join @model.supportedCountries)}}</dd>
            <dt class='cap'>Tracking URL</dt>
            <dd class='mono'>{{dash @model.trackingUrlPattern}}</dd>
          </dl>
        </section>

        <section class='blk'>
          <h2>Linked</h2>
          <dl class='kv'>
            <dt class='cap'>Shipment</dt>
            <dd class='links'>
              {{#if this.queryError}}
                <span class='meta'>Could not read shipments:
                  {{this.queryError}}</span>
              {{else if this.isQueryLoading}}
                <span class='meta'>Loading…</span>
              {{else}}
                {{#each this.shipments as |s|}}
                  <button
                    type='button'
                    class='link'
                    {{on 'click' (fn this.open s)}}
                  >
                    <span class='amark' aria-hidden='true'>Sh</span>
                    <span class='strong'>{{s.shipmentNumber}}</span>
                    <span class='st' data-tone={{shipmentTone s.status}}><span
                        class='dot'
                      ></span>{{lower s.statusStyle.label}}</span>
                  </button>
                {{else}}
                  —
                {{/each}}
              {{/if}}
            </dd>
          </dl>
        </section>
      </article>

      <style scoped>
        .car {
          container-type: inline-size;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
        }
        .ihead {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .who {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .mark,
        .amark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 700;
          color: var(--foreground);
        }
        .amark {
          width: 1rem;
          height: 1rem;
          font-size: 0.5rem;
        }
        .id {
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.8125rem;
          font-weight: 600;
          letter-spacing: normal;
          text-transform: none;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .bar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='bad'] {
          --tone: var(--destructive);
        }
        .st[data-tone='warn'] {
          --tone: var(--warning);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          border-top: 1px solid var(--border);
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          min-width: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .stat + .stat {
          border-left: 1px solid var(--border);
        }
        .stat .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .num {
          font-size: 1.375rem;
          font-weight: 700;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        @container (max-width: 30rem) {
          .stats {
            grid-template-columns: minmax(0, 1fr);
          }
          .stat + .stat {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
        }
        .blk h2 {
          margin: 0;
          padding: var(--boxel-sp-sm) var(--boxel-sp-sm) var(--boxel-sp-4xs);
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: normal;
          text-transform: none;
        }
        .row {
          display: flex;
          align-items: center;
          min-height: 1.75rem;
          margin: 0;
          padding: 0 var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .kv {
          display: grid;
          grid-template-columns: minmax(7rem, 9.5rem) minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          display: flex;
          align-items: center;
          min-height: 1.75rem;
          margin: 0;
          border-top: 1px solid var(--border);
        }
        .kv dt {
          padding-left: var(--boxel-sp-sm);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-sm);
          min-width: 0;
          overflow-wrap: anywhere;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .links {
          flex-wrap: wrap;
          gap: var(--boxel-sp-5xs) var(--boxel-sp-sm);
          padding-block: var(--boxel-sp-5xs);
        }
        .link {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          padding: 0;
          border: 0;
          background: none;
          color: inherit;
          font: inherit;
          cursor: pointer;
        }
        .link .strong {
          font-family: var(--font-mono);
          font-weight: 600;
        }
        .link:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 2px;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Carrier> {
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>{{carrierMark
              @model.code
            }}</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          {{#if @model.onTimePercent}}
            <span class='st' data-tone={{onTimeTone @model.onTimePercent}}><span
                class='dot'
              ></span>{{@model.onTimePercent}}% on time</span>
          {{/if}}
        </header>
        <dl class='kv'>
          <dt>On time</dt>
          <dd class='mono'>{{if
              @model.totalDeliveries
              (concat
                (dash @model.onTimeDeliveries) ' / ' @model.totalDeliveries
              )
              '—'
            }}</dd>
          <dt>Services</dt>
          <dd class='mono'>{{count @model.services}}</dd>
          {{#each @model.services as |svc|}}
            <dt>{{svc.serviceName}}</dt>
            <dd>{{serviceShort svc}}</dd>
          {{/each}}
          <dt>Countries</dt>
          <dd>{{dash (join @model.supportedCountries)}}</dd>
          <dt>Dim divisor</dt>
          <dd class='mono'>{{dash @model.dimDivisor}}</dd>
          <dt>Account</dt>
          <dd class='mono'>{{dash @model.accountNumber}}</dd>
          <dt>Tracking</dt>
          <dd>{{trackingHost @model.trackingUrlPattern}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 700;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          margin: 0;
          font-size: 0.8125rem;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .st {
          flex: none;
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='bad'] {
          --tone: var(--destructive);
        }
        .st[data-tone='warn'] {
          --tone: var(--warning);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
        .kv {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          display: flex;
          align-items: center;
          min-height: 1.75rem;
          margin: 0;
          border-top: 1px solid var(--border);
        }
        .kv dt {
          padding-left: var(--boxel-sp-sm);
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-sm);
          min-width: 0;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Carrier> {
    <template>
      <CompoundAtom
        @mark={{carrierMark @model.code}}
        @name={{if @model.carrierName @model.carrierName @model.code}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof Carrier> {
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>{{carrierMark
              @model.code
            }}</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span
            class='st'
            data-tone={{onTimeTone @model.onTimePercent}}
          ><span class='dot'></span><span class='st-text'>{{if
                @model.onTimePercent
                (concat @model.onTimePercent '% on time')
                (if @model.isActive 'active' 'inactive')
              }}</span></span></:status>
        <:fact>{{count @model.services}}
          services ·
          {{dash (join @model.supportedCountries)}}</:fact>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          width: 2rem;
          height: 2rem;
          margin-right: var(--boxel-sp-xs);
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-weight: 700;
          color: var(--foreground);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
          max-width: 100%;
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='bad'] {
          --tone: var(--destructive);
        }
        .st[data-tone='warn'] {
          --tone: var(--warning);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
        .st-text {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

function join(list: string[] | undefined) {
  return (list ?? []).join(', ');
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function count(list: unknown[] | undefined) {
  return (list ?? []).length;
}

function concat(...parts: unknown[]) {
  return parts.join('');
}

function lower(s: string | undefined) {
  return s ? s.toLowerCase() : '—';
}

function metaLine(m: Partial<Carrier>) {
  let parts = [m.code, m.accountNumber ? `account ${m.accountNumber}` : null];
  return parts.filter(Boolean).join(' · ') || '—';
}

function deliveriesLine(m: Partial<Carrier>) {
  return m.totalDeliveries
    ? `${m.onTimeDeliveries ?? 0} of ${m.totalDeliveries} deliveries`
    : 'no deliveries yet';
}

function serviceNames(services: CarrierServiceField[] | undefined) {
  return (services ?? [])
    .map((s) => s.serviceName)
    .filter(Boolean)
    .join(', ');
}

function rateText(s: Partial<CarrierServiceField>) {
  let base = s.baseRate?.amount;
  if (base == null) return undefined;
  let code = (s.baseRate as any)?.currency?.code ?? 'GBP';
  let text = money(base, code);
  return s.perKgRate ? `${text} + ${money(s.perKgRate, code)} / kg` : text;
}

function serviceMeta(s: Partial<CarrierServiceField>) {
  return [s.code, s.speedLabel, rateText(s)].filter(Boolean).join(' · ') || '—';
}

function serviceShort(s: CarrierServiceField) {
  let days =
    s.deliveryDaysMin == null
      ? undefined
      : s.deliveryDaysMax != null && s.deliveryDaysMax !== s.deliveryDaysMin
        ? `${s.deliveryDaysMin}–${s.deliveryDaysMax} d`
        : `${s.deliveryDaysMin} d`;
  let base = s.baseRate?.amount;
  let code = (s.baseRate as any)?.currency?.code ?? 'GBP';
  return (
    [days, base != null ? money(base, code) : undefined]
      .filter(Boolean)
      .join(' · ') || '—'
  );
}

function trackingHost(pattern: string | undefined) {
  if (!pattern) return '—';
  try {
    return new URL(pattern.replace('{number}', 'x')).hostname.replace(
      /^www\./,
      '',
    );
  } catch {
    return pattern;
  }
}

function shipmentTone(status: string | undefined) {
  if (status === 'delivered') return 'ok';
  return isShipmentException(status) ? 'bad' : undefined;
}

export default Carrier;

function carrierMark(code?: string | null) {
  return (code ?? '').slice(0, 2).toUpperCase();
}

function onTimeTone(pct?: number | null) {
  if (pct == null) {
    return undefined;
  }
  return pct >= 90 ? 'ok' : pct >= 75 ? 'warn' : 'bad';
}
