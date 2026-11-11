import { markDefinition } from '@cardstack/base/mark-definition';
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
import { Button } from '@cardstack/pretui/components/button';
import {
  DotLabel,
  IsoHead,
  IsoMark,
  IsoPage,
  Kv,
  Panel,
  SheetEmpty,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';

// A warehouse is not always a building you own. A 3PL holds your stock and
// ships it for you; a dropship "location" holds nothing at all and exists so an
// order can be allocated somewhere. Treating all three as the same card is what
// lets allocation logic stay in one place.
export const WAREHOUSE_TYPES = [
  { value: 'owned', label: 'Owned' },
  { value: 'third_party', label: '3PL' },
  { value: 'dropship', label: 'Dropship (virtual)' },
];

export const WarehouseTypeField = markDefinition(
  enumField(StringField, {
    options: WAREHOUSE_TYPES,
    displayName: 'Warehouse Type',
  }),
);

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

  get strip(): StripItem[] {
    let m = this.args.model;
    return [
      {
        label: 'Utilisation',
        value: pct(m.utilizationPercent),
        hint: binsLine(m),
        tone: statTone(bandTone(m)),
      },
      {
        label: 'Zones',
        value: String(count(m.zones)),
        hint: dash(join(m.zones)),
      },
      {
        label: 'Free bins',
        value: freeBins(m),
        hint: m.capacityBand ? lower(m.capacityBand.label) : '—',
        tone: statTone(bandTone(m)),
      },
    ];
  }

  get capacityItems() {
    return [{ key: 'Bins used', value: binsUsed(this.args.model) }];
  }

  get contactItems() {
    let m = this.args.model;
    return [
      { key: 'Contact', value: dash(m.contactPerson) },
      { key: 'Email', value: dash(m.contactEmail) },
      { key: 'Phone', value: dash(m.contactPhone) },
      { key: 'Hours', value: dash(m.operatingHours) },
    ];
  }

  get addressItems() {
    let m = this.args.model;
    return [
      { key: 'Street', value: street(m) },
      { key: 'City', value: cityLine(m) },
      { key: 'Country', value: dash(m.address?.country?.name) },
      { key: 'Coordinates', value: coords(m) },
    ];
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.cardTitle}} @meta={{metaLine @model}}>
          <:mark><IsoMark>WH</IsoMark></:mark>
          <:aside>
            {{#if @model.capacityBand}}
              <DotLabel
                @label={{lower @model.capacityBand.label}}
                @color={{toneColor (bandTone @model)}}
              />
            {{/if}}
            <DotLabel
              @label={{if @model.isActive 'active' 'inactive'}}
              @color={{if @model.isActive 'var(--success)'}}
            />
          </:aside>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
      </:head>
      <:main>
        <Panel @title='Capacity'>
          <Kv @items={{this.capacityItems}} />
          {{#if @model.totalBins}}
            <SheetLine>
              <ProgressBar
                @value={{if @model.occupiedBins @model.occupiedBins 0}}
                @max={{@model.totalBins}}
                aria-hidden='true'
              />
            </SheetLine>
          {{/if}}
        </Panel>
        <Panel @title='Stock'>
          {{#if this.queryError}}
            <SheetEmpty @title='Could not read stock: {{this.queryError}}' />
          {{else if this.isQueryLoading}}
            <SheetEmpty @title='Loading…' />
          {{else}}
            {{#each this.rows as |r|}}
              <SheetLine>
                <Button
                  @appearance='link'
                  @size='s'
                  {{on 'click' (fn this.open r)}}
                >{{r.cardTitle}}</Button>
                <DotLabel
                  @label={{r.stockState}}
                  @color={{toneColor (stockTone r.stockState)}}
                />
              </SheetLine>
            {{else}}
              <SheetEmpty @title='No stock here' />
            {{/each}}
          {{/if}}
        </Panel>
      </:main>
      <:aside>
        <Panel @title='Contact'><Kv @items={{this.contactItems}} /></Panel>
        <Panel @title='Address'><Kv @items={{this.addressItems}} /></Panel>
      </:aside>
    </IsoPage>
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

function statTone(tone: string | undefined) {
  return tone === 'bad'
    ? 'danger'
    : tone === 'warn'
      ? 'warning'
      : tone === 'ok'
        ? 'success'
        : undefined;
}

function toneColor(tone: string | undefined) {
  return tone === 'bad'
    ? 'var(--destructive)'
    : tone === 'warn'
      ? 'var(--warning)'
      : tone === 'ok'
        ? 'var(--success)'
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
