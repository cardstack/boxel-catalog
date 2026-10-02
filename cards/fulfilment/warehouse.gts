import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { cached } from '@glimmer/tracking';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import AddressField from 'https://cardstack.com/base/address';
import {
  MapRender,
  type Coordinate,
} from '@cardstack/catalog/components/map-render';
import EmailField from 'https://cardstack.com/base/email';
import enumField from 'https://cardstack.com/base/enum';
import { htmlSafe } from '@ember/template';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import WarehouseIcon from '@cardstack/boxel-icons/building-warehouse';
import Gauge from '@cardstack/boxel-icons/gauge';
import Layers from '@cardstack/boxel-icons/layers';
import MapPin from '@cardstack/boxel-icons/map-pin';
import User from '@cardstack/boxel-icons/user';
import Boxes from '@cardstack/boxel-icons/boxes';
// Cyclic with inventory-stock.gts (it links to Warehouse); safe because the
// binding is only read inside the constructor, not at module evaluation.
import { InventoryStock } from './inventory-stock';
import { LoadingRows, StatusPill, type StatusHue } from './fulfilment-ui';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat } from '@cardstack/pretui/components/stat';
import { Token } from '@cardstack/pretui/components/token';
import { eq } from '@cardstack/boxel-ui/helpers';

const CONTACT_FACTS = [
  { key: 'Person', value: 'contactPerson' },
  { key: 'Email', value: 'contactEmail' },
  { key: 'Phone', value: 'contactPhone' },
  { key: 'Hours', value: 'operatingHours' },
];

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

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class WarehouseIsolated extends Component<typeof Warehouse> {
  // MapRender takes a list; this card has one point. The wrapper exists so the
  // template does not build a fresh array on every re-render, which would
  // remount the map.
  // `@cached` for identity, not speed: MapRender's modifier rebuilds its layers
  // on `coordinates !== lastCoordinates`, so a getter returning a fresh array
  // each render would re-fit the map on every unrelated re-render.
  @cached
  get mapPoints(): Coordinate[] {
    let point = (this.args.model as Warehouse)?.mapPoint;
    return point ? [point] : [];
  }

  // `LeafletMapConfig` is not exported from map-render, so this is typed
  // structurally rather than by import. Every enrichment the component offers
  // is opt-in and stays off: a warehouse card wants to show where the building
  // is, not restaurants near it.
  mapConfig = {
    disableMapClick: true,
    showGoogleMapsLink: true,
  };

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
    (this.args as any).viewCard?.(card, 'isolated');
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

  get unitsOnHand() {
    return this.rows.reduce((n, r) => n + (r.quantityOnHand ?? 0), 0);
  }

  get unitsAvailable() {
    return this.rows.reduce((n, r) => n + (r.quantityAvailable ?? 0), 0);
  }

  get needsAttention(): any[] {
    return this.rows.filter(
      (r) => r.stockState === 'low' || r.stockState === 'out',
    );
  }

  <template>
    <article class='wh'>
      <header class='hd'>
        <div>
          {{#if @model.code}}<Token
              class='code'
              @value={{@model.code}}
            />{{/if}}
          <h1 class='name'>{{@model.warehouseName}}</h1>
          {{#if @model.locationLabel}}
            <p class='loc'>{{@model.locationLabel}}</p>
          {{/if}}
        </div>
        <div class='hd-type'>
          <@fields.warehouseType @format='atom' />
          {{#unless @model.isActive}}
            <StatePill @label='Inactive' @hue='red' />
          {{/unless}}
        </div>
      </header>

      {{#unless @model.isVirtual}}
        {{! Above the fold, because it is the answer — capacity and address are
            supporting detail. }}
        <div class='wh-stats'>
          <Stat
            class='stat'
            @label='SKUs held'
            @value={{this.rows.length}}
            @roll={{false}}
          />
          <Stat
            class='stat'
            @label='Units on hand'
            @value={{this.unitsOnHand}}
            @roll={{false}}
          />
          <Stat
            class='stat'
            @label='Available'
            @value={{this.unitsAvailable}}
            @roll={{false}}
          />
          <Stat
            class='stat {{if this.needsAttention.length "alarm"}}'
            @label='Needs attention'
            @value={{this.needsAttention.length}}
            @roll={{false}}
          />
        </div>
      {{/unless}}

      {{#if @model.isVirtual}}
        <Alert class='virtual-note' @tone='info' style={{ALERT_STYLE.info}}>This
          is a virtual location. Stock is never counted here — orders allocated
          to it are forwarded to the supplier, who ships direct.</Alert>
      {{else if @model.utilizationPercent}}
        <section class='sec'>
          <h2><Gauge class='sec-icon' role='presentation' />Capacity</h2>
          <div class='cap-head'>
            <span class='cap-count'>{{@model.occupiedBins}}
              of
              {{@model.totalBins}}
              bins filled</span>
            <StatusPill
              @label={{@model.capacityBand.label}}
              @hue={{@model.capacityBand.pill}}
            />
          </div>
          {{! Pret UI ProgressBar: occupied bins against total bins, filled
              with the capacity band's hue. Hidden from assistive tech, as the
              other rails are: cap-count and the pill say the same in text. }}
          <ProgressBar
            class='cap-rail'
            style={{capStyle @model.capacityBand.hue}}
            @value={{if @model.occupiedBins @model.occupiedBins 0}}
            @max={{@model.totalBins}}
            aria-hidden='true'
          />
        </section>
      {{/if}}

      <div class='cols'>
        <section class='sec'>
          <h2><MapPin class='sec-icon' role='presentation' />Address</h2>
          <@fields.address @format='embedded' />
          {{! The catalog's shared Leaflet renderer, consumed rather than
              rebuilt. It has no opinion about warehouses — it takes a list of
              coordinates, so the card supplies exactly one. }}
          {{#if @model.mapPoint}}
            <div class='wh-map'>
              <MapRender
                @coordinates={{this.mapPoints}}
                @mapConfig={{this.mapConfig}}
              />
            </div>
          {{else}}
            <p class='wh-map-empty'>
              <MapPin width='18' height='18' role='presentation' />
              No coordinates on this warehouse yet. Add a latitude and longitude
              to place it on the map.
            </p>
          {{/if}}
        </section>

        <section class='sec'>
          <h2><User class='sec-icon' role='presentation' />Contact</h2>
          <KeyValue class='kv' @items={{CONTACT_FACTS}}>
            <:value as |item|>
              {{#if (eq item.value 'contactPerson')}}
                {{if @model.contactPerson @model.contactPerson '—'}}
              {{else if (eq item.value 'contactEmail')}}
                <@fields.contactEmail @format='atom' />
              {{else if (eq item.value 'contactPhone')}}
                <span class='mono'>{{if
                    @model.contactPhone
                    @model.contactPhone
                    '—'
                  }}</span>
              {{else}}
                {{if @model.operatingHours @model.operatingHours '—'}}
              {{/if}}
            </:value>
          </KeyValue>
        </section>
      </div>

      {{#unless @model.isVirtual}}
        <section class='sec'>
          <h2><Boxes class='sec-icon' role='presentation' />Stock on hand</h2>
          {{#if this.queryError}}
            <Alert
              @tone='danger'
              @title='Could not read stock for this warehouse.'
              style={{ALERT_STYLE.danger}}
            >{{this.queryError}}</Alert>
          {{else if this.needsAttention.length}}
            <ul class='wh-rows'>
              {{#each this.needsAttention as |row|}}
                <li class='wh-row-li'>
                  <button
                    type='button'
                    class='wh-row wh-{{row.stockState}}'
                    {{on 'click' (fn this.open row)}}
                  >
                    {{#if row.sku}}<Token
                        class='wr-sku'
                        @value={{row.sku}}
                      />{{else}}<span class='wr-sku'>—</span>{{/if}}
                    <span class='wr-name'>{{if
                        row.productName
                        row.productName
                        ''
                      }}</span>
                    <span class='wr-bin'>{{if
                        row.binLocation
                        row.binLocation
                        ''
                      }}</span>
                    <span class='wr-qty'>{{row.quantityAvailable}}</span>
                    <span class='wr-state'><StatusPill
                        @label={{row.stockStateLabel}}
                        @hue={{row.stockStateHue}}
                      /></span>
                  </button>
                </li>
              {{/each}}
            </ul>
            <p class='hint'>{{this.rows.length}}
              rows in total; the
              {{this.needsAttention.length}}
              at or below their reorder point are listed. Open the Inventory tab
              for the rest.</p>
            {{! Loading is not empty. Space is reserved so the section does not
            jump when the query lands. }}
          {{else if this.isQueryLoading}}
            <LoadingRows />
          {{else if this.rows.length}}
            <p class='hint'>All
              {{this.rows.length}}
              stock rows here are above their reorder point.</p>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No stock rows reference this warehouse yet'
            />
          {{/if}}
        </section>
      {{/unless}}

      {{#if @model.zones.length}}
        <section class='sec'>
          <h2><Layers class='sec-icon' role='presentation' />Zones</h2>
          <ul class='zones'>
            {{#each @model.zones as |zone|}}
              <li><StatePill @label={{zone}} /></li>
            {{/each}}
          </ul>
        </section>
      {{/if}}
    </article>

    <style scoped>
      .wh {
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
        justify-content: space-between;
        align-items: flex-start;
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--ful-rule);
      }
      /* Pret UI Token for the warehouse code, on the muted ink. The body
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
      }
      .loc {
        margin: 0.25rem 0 0;
        font-size: var(--t-sm);
        color: var(--muted-foreground);
      }
      .hd-type {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      /* Same ground as a section, so it must have the same inset and the same
         corner. It used to be `sp-sm` with square corners against sections at
         `sp-lg` with an 8px radius: identical tint, two different surfaces,
         and its text sat visibly left of every heading below it. */
      /* MapRender is width:100% / height:100%, so the host owns the box. A
         definite height is mandatory — without it the map collapses to zero
         and Leaflet initialises against an empty rect. */
      .wh-map {
        margin-top: var(--boxel-sp-sm);
        height: 13.75rem;
        border-radius: var(--panel-radius);
        overflow: hidden;
        border: 1px solid var(--border);
      }
      .wh-map-empty {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin: var(--boxel-sp-sm) 0 0;
        font-size: var(--t-sm);
        color: var(--muted-foreground);
      }
      /* Pret UI Alert, info tone, for the virtual-location note; the tone's
         inks come from ALERT_STYLE and the size from the body knob. */
      .virtual-note {
        --text-ui-md: var(--t-sm);
        margin: var(--boxel-sp) 0 0;
      }
      .cols {
        display: grid;
        gap: var(--boxel-sp-lg);
        grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
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
      /* Pret UI KeyValue: label and value sizes and the column gap. */
      .kv {
        --text-ui: var(--t-micro);
        --text-ui-md: var(--t-sm);
        --space-6: 1.25rem;
      }
      /* Pret UI EmptyState, compact: no texture, 1rem padding, and the title
         at the body size. */
      .empty {
        --space-9: 1rem;
        --space-6: 1rem;
        --text-heading: var(--boxel-font-size);
      }
      .mono {
        font-family: var(--font-mono);
      }
      .zones {
        display: flex;
        flex-wrap: wrap;
        gap: 0.375rem;
        margin: 0;
        padding: 0;
        list-style: none;
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

      .wh-stats {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xl);
        margin: var(--boxel-sp) 0 0;
        padding-bottom: var(--boxel-sp);
        border-bottom: 1px solid var(--ful-rule);
      }
      /* Pret UI Stat: the knob keeps the figures at the old large size. */
      .stat {
        --text-stat: var(--t-lg);
      }
      .wh-stats .alarm {
        color: var(--destructive-ink);
      }
      .wh-rows {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .wh-row {
        display: grid;
        grid-template-columns: 6rem minmax(0, 1fr) 5rem 4rem 4.5rem;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: 0.375rem 0;
        border-top: 1px solid var(--ful-rule);
        font-size: var(--t-sm);
      }
      .wr-bin,
      .wr-qty {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
      }
      /* Pret UI Token for the SKU, on the muted ink. */
      .wh-row .wr-sku {
        --pretui-token-hue: var(--muted-foreground);
        --text-body: calc(var(--t-sm) + 3.5px);
        justify-self: start;
        margin-inline: 0;
        max-width: 100%;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .wr-name {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .wr-bin {
        color: var(--muted-foreground);
      }
      .wr-qty {
        text-align: right;
        font-weight: 700;
      }
      .wr-state {
        text-align: right;
      }
      .wh-out .wr-qty {
        color: var(--destructive-ink);
      }
      .wh-low .wr-qty {
        color: var(--attention-ink);
      }

      .wh-row-li {
        list-style: none;
      }
      /* The row became a button: strip the chrome, keep the grid, and give it a
         real affordance. 160ms sits inside the 150-300ms micro-interaction
         window; `prefers-reduced-motion` removes it rather than shortening it. */
      button.wh-row {
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
      button.wh-row:hover {
        background-color: color-mix(
          in oklch,
          var(--foreground) 5%,
          transparent
        );
      }
      button.wh-row:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: -0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        button.wh-row {
          transition: none;
        }
      }
      .cap-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        margin-bottom: 0.3125rem;
        font-size: var(--t-sm);
      }
      .cap-count {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
      }
      /* Pret UI ProgressBar for the capacity rail. Its track reads --inset,
         which sits within a shade of the section panel, so the track and the
         height are set here, and the fill takes the band's hue. */
      .cap-rail :deep(.pretui-progress) {
        height: 0.5rem;
        border-radius: 0.25rem;
        background-color: color-mix(
          in oklch,
          var(--foreground) 10%,
          transparent
        );
      }
      .cap-rail :deep(.pretui-progress-fill) {
        border-radius: 0;
        background-color: var(--cap-hue);
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
    | { key: string; label: string; hue: string; pill: StatusHue }
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
      <div class='wh-emb'>
        <span class='wh-code'>{{#if @model.code}}<Token
              class='wh-token'
              @value={{@model.code}}
            />{{/if}}</span>
        <span class='wh-name'>{{@model.warehouseName}}</span>
        <span class='wh-slot'>{{if
            @model.locationLabel
            @model.locationLabel
            '—'
          }}</span>
        <span class='wh-slot'>{{#if
            @model.utilizationPercent
          }}{{@model.utilizationPercent}}% full{{else}}—{{/if}}</span>
      </div>

      <style scoped>
        /* A CardDef's embedded template must supply its OWN inset. The host wraps
           a linksTo render in a CardContainer that draws a rounded boundary and
           deliberately adds no padding — field-component.gts:513 says so in as
           many words, because padding there would move the container-query
           breakpoints the card reasons about. With none on either side the text
           sits flush against the pill, which is what "Northline Supply" looked
           like inside Supplied by. FieldDef embeddeds get no boundary and so
           never showed this. */
        .wh-emb {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: grid;
          grid-template-columns: 6rem minmax(0, 1fr) 9rem 5.5rem;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.9rem;
        }
        .wh-code {
          min-width: 0;
        }
        /* Pret UI Token for the warehouse code, on the muted ink. */
        .wh-code .wh-token {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(0.7rem + 3.5px);
          margin-inline: 0;
        }
        .wh-name {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .wh-slot {
          text-align: right;
          font-size: 0.78rem;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        @container (width < 380px) {
          .wh-emb {
            grid-template-columns: 5rem minmax(0, 1fr) 5rem;
          }
          .wh-slot:nth-of-type(1) {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Warehouse> {
    <template>
      <span class='wh-atom'>{{if
          @model.code
          @model.code
          @model.warehouseName
        }}</span>
      <style scoped>
        .wh-atom {
          font-family: var(--font-mono);
          font-size: 0.85em;
          font-weight: 700;
          letter-spacing: 0.06em;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Warehouse> {
    <template>
      <article class='fit'>
        <div class='r-head'>
          <div class='eyebrow'>
            <WarehouseIcon class='glyph' />
            <span class='code'>{{@model.code}}</span>
          </div>
          <h3 class='headline'>{{@model.warehouseName}}</h3>
        </div>
        <div class='r-body'>
          {{#if @model.locationLabel}}
            <p class='loc'>{{@model.locationLabel}}</p>
          {{/if}}
          {{#if @model.utilizationPercent}}
            {{! Pret UI ProgressBar, hidden from assistive tech: the meta row
                prints the same percentage. }}
            <ProgressBar
              class='gauge'
              @value={{@model.utilizationPercent}}
              aria-hidden='true'
            />
          {{/if}}
        </div>
        <div class='r-meta'>
          {{#if @model.utilizationPercent}}
            <span class='pct'>{{@model.utilizationPercent}}% full</span>
          {{else if @model.isVirtual}}
            <span class='pct'>Virtual</span>
          {{/if}}
          <span class='zn'>{{@model.zones.length}} zones</span>
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
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          grid-area: head;
        }
        .r-body {
          grid-area: body;
        }
        .r-meta {
          grid-area: meta;
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
        .loc {
          margin: 0.1875rem 0 0;
          font-size: var(--meta-size);
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 1;
          overflow: hidden;
        }
        /* Pret UI ProgressBar for the gauge. Its --inset track all but
           vanishes on the card, so the track and fill keep their old mixes. */
        .gauge {
          margin-top: 0.375rem;
        }
        .gauge :deep(.pretui-progress) {
          background-color: color-mix(
            in oklch,
            var(--card-foreground) 12%,
            transparent
          );
        }
        .gauge :deep(.pretui-progress-fill) {
          background-color: color-mix(
            in oklch,
            var(--card-foreground) 55%,
            transparent
          );
        }
        .pct {
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
        @container fitted-card (50px < height <= 105px) {
          .r-body {
            display: none;
          }
        }
        @container fitted-card (105px < height <= 130px) {
          .gauge {
            display: none;
          }
        }
        @container fitted-card (width <= 130px) {
          .zn {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Warehouse;

function capStyle(hue: string | undefined) {
  return htmlSafe(`--cap-hue: ${hue ?? 'var(--muted-foreground)'}`);
}
