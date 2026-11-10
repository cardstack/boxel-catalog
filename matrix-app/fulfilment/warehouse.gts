import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import AddressField from 'https://cardstack.com/base/address';
import { type Coordinate } from '@cardstack/catalog/components/map-render';
import EmailField from 'https://cardstack.com/base/email';
import enumField from 'https://cardstack.com/base/enum';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import WarehouseIcon from '@cardstack/boxel-icons/building-warehouse';
// Cyclic with inventory-stock.gts (it links to Warehouse); safe because the
// binding is only read inside the constructor, not at module evaluation.
import { InventoryStock } from './inventory-stock';
import { CompoundAtom } from './fulfilment-ui';
import { FitTile } from '../shared/fit-tile';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';

// A warehouse is not always a building you own. A 3PL holds your stock and
// ships it for you; a dropship "location" holds nothing at all and exists so an
// order can be allocated somewhere. Treating all three as the same card is what
// lets allocation logic stay in one place.
export const WAREHOUSE_TYPES = [
  { value: 'owned', label: 'Owned' },
  { value: 'third_party', label: '3PL' },
  { value: 'dropship', label: 'Dropship (virtual)' },
];

export const WarehouseTypeField = enumField(StringField, {
  options: WAREHOUSE_TYPES,
  displayName: 'Warehouse Type',
});

class WarehouseIsolated extends Component<typeof Warehouse> {
  // The question someone opens a warehouse to answer is "what is sitting here
  // and what needs attention" — which lives on InventoryStock, pointing in.
  private stockQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.stockQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(InventoryStock);
        let id = this.args.model?.id;
        if (!ref || !id) {
          return undefined;
        }
        return {
          filter: { on: ref, every: [{ eq: { 'warehouse.id': id } }] },
        };
      },
      () => this.realms,
      { isLive: true },
    );
  }

  // A live query resolving AFTER first paint is why this card asserted "no
  // stock rows" about data it had not received. `getCards` publishes `isLoading`
  // and nothing here read it. Guarded on emptiness too, so a background
  // refresh of an already-populated list does not flash a skeleton.
  get isQueryLoading() {
    let q = this.stockQuery as any;
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
    let entries = (this.stockQuery as any)?.errors as any[] | undefined;
    if (!entries?.length) {
      return undefined;
    }
    return entries[0]?.error?.message ?? 'The query failed.';
  }

  get rows(): any[] {
    return (this.stockQuery?.instances ?? []).filter(Boolean);
  }

  <template>
    <article class='wh'>
      <header class='ihead'>
        <div class='who'>
          <span class='mark' aria-hidden='true'>WH</span>
          <div class='id'>
            <h1 class='name'>{{@model.cardTitle}}</h1>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
        </div>
        <div class='bar'>
          {{#if @model.capacityBand}}
            <span class='st' data-tone={{bandTone @model}}><span
                class='dot'
              ></span>{{lower @model.capacityBand.label}}</span>
          {{/if}}
          <span class='st' data-tone={{if @model.isActive 'ok'}}><span
              class='dot'
            ></span>{{if @model.isActive 'active' 'inactive'}}</span>
        </div>
      </header>

      <div class='stats'>
        <div class='stat'>
          <span class='st cap' data-tone={{bandTone @model}}><span
              class='dot'
            ></span>Utilisation</span>
          <span class='num'>{{pct @model.utilizationPercent}}</span>
          <span class='meta'>{{binsLine @model}}</span>
        </div>
        <div class='stat'>
          <span class='st cap'><span class='dot'></span>Zones</span>
          <span class='num'>{{count @model.zones}}</span>
          <span class='meta'>{{dash (join @model.zones)}}</span>
        </div>
        <div class='stat'>
          <span class='st cap' data-tone={{bandTone @model}}><span
              class='dot'
            ></span>Free bins</span>
          <span class='num'>{{freeBins @model}}</span>
          <span class='meta'>{{if
              @model.capacityBand
              (lower @model.capacityBand.label)
              '—'
            }}</span>
        </div>
      </div>

      <section class='blk'>
        <h2>Capacity</h2>
        <dl class='kv'>
          <dt class='cap'>Bins used</dt>
          <dd class='mono'>{{binsUsed @model}}</dd>
        </dl>
        {{#if @model.totalBins}}
          <div class='rail'>
            <ProgressBar
              @value={{if @model.occupiedBins @model.occupiedBins 0}}
              @max={{@model.totalBins}}
              aria-hidden='true'
            />
          </div>
        {{/if}}
      </section>

      <section class='blk'>
        <h2>Contact</h2>
        <dl class='kv'>
          <dt class='cap'>Contact</dt>
          <dd>{{dash @model.contactPerson}}</dd>
          <dt class='cap'>Email</dt>
          <dd>{{dash @model.contactEmail}}</dd>
          <dt class='cap'>Phone</dt>
          <dd>{{dash @model.contactPhone}}</dd>
          <dt class='cap'>Hours</dt>
          <dd>{{dash @model.operatingHours}}</dd>
        </dl>
      </section>

      <section class='blk'>
        <h2>Address</h2>
        <dl class='kv'>
          <dt class='cap'>Street</dt>
          <dd>{{street @model}}</dd>
          <dt class='cap'>City</dt>
          <dd>{{cityLine @model}}</dd>
          <dt class='cap'>Country</dt>
          <dd>{{dash @model.address.country.name}}</dd>
          <dt class='cap'>Coordinates</dt>
          <dd class='mono'>{{coords @model}}</dd>
        </dl>
      </section>

      <section class='blk'>
        <h2>Linked</h2>
        <dl class='kv'>
          <dt class='cap'>Stock</dt>
          <dd class='links'>
            {{#if this.queryError}}
              <span class='meta'>Could not read stock:
                {{this.queryError}}</span>
            {{else if this.isQueryLoading}}
              <span class='meta'>Loading…</span>
            {{else}}
              {{#each this.rows as |r|}}
                <button
                  type='button'
                  class='link'
                  {{on 'click' (fn this.open r)}}
                >
                  <span class='strong mono'>{{r.cardTitle}}</span>
                  <span class='st' data-tone={{stockTone r.stockState}}><span
                      class='dot'
                    ></span>{{r.stockState}}</span>
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
      .wh {
        container-type: inline-size;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        color: var(--card-foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
      }
      .rail {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
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
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
      }
      .link:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
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
      .mark {
        flex: none;
        display: inline-grid;
        place-items: center;
        width: 1.375rem;
        height: 1.375rem;
        border-radius: calc(var(--radius) * 0.6);
        background-color: var(--muted);
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 700;
        color: var(--foreground);
      }
      .id {
        min-width: 0;
      }
      .name {
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        letter-spacing: normal;
        text-transform: none;
      }
      .meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
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
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
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
        font-size: var(--boxel-font-size-lg);
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
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        letter-spacing: normal;
        text-transform: none;
      }
      .row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        width: 100%;
        min-height: 1.75rem;
        margin: 0;
        padding: 0 var(--boxel-sp-sm);
        border: 0;
        border-top: 1px solid var(--border);
        background: none;
        color: inherit;
        font-family: inherit;
        font-size: inherit;
        font-weight: inherit;
        line-height: inherit;
        text-align: start;
      }
      button.row {
        cursor: pointer;
      }
      @media (hover: hover) {
        button.row:hover {
          background-color: var(--muted);
        }
      }
      button.row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }


      .strong {
        flex: none;
        font-weight: 600;
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
        overflow-wrap: break-word;
        min-width: 0;
      }
      .mono {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
      }
    </style>
  </template>
}

export class Warehouse extends CardDef {
  static displayName = 'Warehouse';
  static icon = WarehouseIcon;

  @field code = contains(StringField);
  @field warehouseName = contains(StringField);
  @field warehouseType = contains(WarehouseTypeField);
  @field isActive = contains(BooleanField);
  @field address = contains(AddressField);

  // Plain coordinates rather than a geo field: the only thing this card needs
  // them for is plotting, and a bare pair keeps the card usable in realms that
  // do not have the catalog's geo blocks.
  @field latitude = contains(NumberField);
  @field longitude = contains(NumberField);

  @field contactPerson = contains(StringField);
  @field contactEmail = contains(EmailField);
  @field contactPhone = contains(StringField);
  @field operatingHours = contains(StringField);

  // Bin-level granularity is optional. A spare-room operation has no bins and
  // reports no utilisation rather than a fake 0%.
  @field totalBins = contains(NumberField);
  @field occupiedBins = contains(NumberField);
  @field zones = containsMany(StringField);

  @field utilizationPercent = contains(NumberField, {
    computeVia: function (this: Warehouse) {
      let total = this.totalBins ?? 0;
      if (total <= 0) {
        return undefined;
      }
      return Math.round(((this.occupiedBins ?? 0) / total) * 100);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Warehouse) {
      return this.warehouseName?.length
        ? this.warehouseName
        : 'Untitled Warehouse';
    },
  });

  // Near-full is a WARNING, not an achievement — the accent green the default
  // progress bar uses read as "good" at 92% occupancy. The band is also rendered
  // as text, so the signal survives for anyone who cannot use the colour. `hue`
  // fills the rail and `pill` colours the pill, from the same status token.
  get capacityBand():
    | { key: string; label: string; hue: string; pill: Hue }
    | undefined {
    let pct = this.utilizationPercent;
    if (pct == null) {
      return undefined;
    }
    if (pct >= 90) {
      return {
        key: 'full',
        label: 'Almost full',
        hue: 'var(--destructive)',
        pill: 'red',
      };
    }
    if (pct >= 75) {
      return {
        key: 'tight',
        label: 'Filling up',
        hue: 'var(--attention)',
        pill: 'attention',
      };
    }
    return {
      key: 'ok',
      label: 'Room to spare',
      hue: 'var(--success)',
      pill: 'green',
    };
  }

  get isVirtual() {
    return this.warehouseType === 'dropship';
  }

  get locationLabel() {
    let city = this.address?.city;
    let country = this.address?.country?.code ?? this.address?.country?.name;
    return [city, country].filter(Boolean).join(', ') || undefined;
  }

  // The coordinate pair was populated on every warehouse instance and drawn by
  // nothing — the fields existed, the data was real, and no template read it.
  // This is the read side. Returns undefined rather than a (0,0) marker when
  // either half is missing, because the Gulf of Guinea is not a warehouse.
  get mapPoint(): Coordinate | undefined {
    let lat = this.latitude;
    let lng = this.longitude;
    if (lat == null || lng == null) {
      return undefined;
    }
    return {
      id: this.id ?? this.code ?? 'warehouse',
      lat,
      lng,
      name: this.warehouseName ?? this.code ?? 'Warehouse',
      address: this.address?.fullAddress ?? this.locationLabel,
    };
  }

  static isolated = WarehouseIsolated;

  static embedded = class Embedded extends Component<typeof Warehouse> {
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>WH</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          {{#if @model.capacityBand}}
            <span class='st' data-tone={{bandTone @model}}><span
                class='dot'
              ></span>{{lower @model.capacityBand.label}}</span>
          {{/if}}
        </header>
        <dl class='kv'>
          <dt>Bins used</dt>
          <dd class='mono'>{{binsUsed @model}}</dd>
          <dt>Utilisation</dt>
          <dd class='mono'>{{pct @model.utilizationPercent}}</dd>
          <dt>Zones</dt>
          <dd>{{dash (join @model.zones)}}</dd>
          <dt>Type</dt>
          <dd>{{typeLabel @model.warehouseType}}</dd>
          <dt>Contact</dt>
          <dd>{{dash @model.contactPerson}}</dd>
          <dt>Phone</dt>
          <dd>{{dash @model.contactPhone}}</dd>
          <dt>Hours</dt>
          <dd>{{dash @model.operatingHours}}</dd>
          <dt>Address</dt>
          <dd>{{street @model}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
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
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
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
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-sm);
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Warehouse> {
    <template>
      <CompoundAtom
        @mark='WH'
        @name={{if @model.warehouseName @model.warehouseName @model.code}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof Warehouse> {
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>WH</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='st' data-tone={{bandTone @model}}><span
              class='dot'
            ></span><span class='st-text'>{{fitStatus
                @model
              }}</span></span></:status>
        <:fact>{{binsUsed @model}}
          bins ·
          {{pct @model.utilizationPercent}}
          full</:fact>
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
          font-size: var(--boxel-font-size-2xs);
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

export default Warehouse;

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function join(list: string[] | undefined) {
  return (list ?? []).join(', ');
}

function count(list: unknown[] | undefined) {
  return (list ?? []).length;
}

function lower(s: string | undefined) {
  return s ? s.toLowerCase() : '—';
}

function pct(n: number | undefined) {
  return n == null ? '—' : `${Math.round(n)}%`;
}

function typeLabel(v: string | undefined) {
  return WAREHOUSE_TYPES.find((t) => t.value === v)?.label ?? '—';
}

function bandTone(m: Partial<Warehouse>) {
  let key = m?.capacityBand?.key;
  return key === 'full'
    ? 'bad'
    : key === 'tight'
      ? 'warn'
      : key
        ? 'ok'
        : undefined;
}

function stockTone(state: string | undefined) {
  return state === 'out'
    ? 'bad'
    : state === 'low'
      ? 'warn'
      : state === 'ok'
        ? 'ok'
        : undefined;
}

function metaLine(m: Partial<Warehouse>) {
  let a = m?.address;
  let place = [a?.city, a?.postalCode].filter(Boolean).join(' ');
  let type = WAREHOUSE_TYPES.find((t) => t.value === m?.warehouseType)?.label;
  return [m?.code, type, place].filter(Boolean).join(' · ') || '—';
}

function binsUsed(m: Partial<Warehouse>) {
  return m?.totalBins ? `${m.occupiedBins ?? 0} / ${m.totalBins}` : '—';
}

function binsLine(m: Partial<Warehouse>) {
  return m?.totalBins
    ? `${m.occupiedBins ?? 0} of ${m.totalBins} bins`
    : 'no bins recorded';
}

function freeBins(m: Partial<Warehouse>) {
  return m?.totalBins ? String(m.totalBins - (m.occupiedBins ?? 0)) : '—';
}

function street(m: Partial<Warehouse>) {
  let a = m?.address;
  return [a?.addressLine1, a?.addressLine2].filter(Boolean).join(', ') || '—';
}

function cityLine(m: Partial<Warehouse>) {
  let a = m?.address;
  return [a?.city, a?.postalCode].filter(Boolean).join(' ') || '—';
}

function coords(m: Partial<Warehouse>) {
  return m?.latitude != null && m?.longitude != null
    ? `${m.latitude}, ${m.longitude}`
    : '—';
}

function fitStatus(m: Partial<Warehouse>) {
  if (m?.isVirtual) return 'dropship';
  return m?.utilizationPercent != null
    ? `${Math.round(m.utilizationPercent)}% full`
    : m?.isActive
      ? 'active'
      : 'inactive';
}
