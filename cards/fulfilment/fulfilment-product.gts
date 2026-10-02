import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import BooleanField from 'https://cardstack.com/base/boolean';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import PackageIcon from '@cardstack/boxel-icons/package';
import Barcode from '@cardstack/boxel-icons/barcode';
import Boxes from '@cardstack/boxel-icons/boxes';
import Building from '@cardstack/boxel-icons/building';
import Ruler from '@cardstack/boxel-icons/ruler';
import { eq } from '@cardstack/boxel-ui/helpers';
// The catalog's image field rather than a bare url string: it accepts either a
// pasted URL or a file uploaded into the realm and resolves both to one
// `resolvedUrl`, so a consumer never has to know which way the photo arrived.
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import ParcelDimensionsField from './parcel-dimensions';
import { FulfilmentVendor } from './fulfilment-vendor';
// Cyclic with inventory-stock.gts (it links TO this card), which ES modules
// tolerate because the binding is only read inside the constructor, never at
// module-evaluation time.
import { InventoryStock } from './inventory-stock';
import { LoadingRows, StatusPill, amountText } from './fulfilment-ui';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat } from '@cardstack/pretui/components/stat';
import { Token } from '@cardstack/pretui/components/token';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import { realmURL } from 'https://cardstack.com/base/card-api';
import type Owner from '@ember/owner';

// Product (Pr) — a SKU as fulfilment sees it. Deliberately not the retail
// product card: this one carries the things you need to *move* an item (weight,
// box size, barcode, who supplies it), not the things you need to sell it.
//
// Named distinctly from the realm's existing retail `product.gts` so the two
// can coexist. A merge would force one card to carry both jobs.
const IDENTIFIER_FACTS = [
  { key: 'Barcode', value: 'barcode' },
  { key: 'Vendor SKU', value: 'vendorSku' },
];

export class FulfilmentProduct extends CardDef {
  static displayName = 'Product';
  static icon = PackageIcon;

  @field sku = contains(StringField);
  @field productName = contains(StringField);
  @field category = contains(StringField);
  @field barcode = contains(StringField);
  @field image = contains(ImageSourceField);

  // Second consumer for the parcel block: a product's shipping profile is the
  // same shape as a parcel's, so the packing station can pre-fill from it.
  @field shippingProfile = contains(ParcelDimensionsField);

  @field vendor = linksTo(() => FulfilmentVendor);
  @field vendorSku = contains(StringField);
  @field cost = contains(AmountWithCurrency);
  @field price = contains(AmountWithCurrency);

  @field isDropship = contains(BooleanField);
  @field isActive = contains(BooleanField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FulfilmentProduct) {
      return this.productName?.length ? this.productName : 'Untitled Product';
    },
  });

  get marginPercent() {
    let cost = this.cost?.amount;
    let price = this.price?.amount;
    if (!cost || !price || price <= 0) {
      return undefined;
    }
    return Math.round(((price - cost) / price) * 100);
  }

  static isolated = class Isolated extends Component<typeof FulfilmentProduct> {
    // The reason someone opens a product card in a fulfilment app is to find out
    // whether there is any. InventoryStock links TO the product, so the answer
    // is a reverse query rather than a field on this card.
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
          return { filter: { on: ref, every: [{ eq: { 'product.id': id } }] } };
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
    get queryError(): string | undefined {
      let entries = (this.stockQuery as any)?.errors as any[] | undefined;
      if (!entries?.length) {
        return undefined;
      }
      return entries[0]?.error?.message ?? 'The query failed.';
    }

    get stockRows(): any[] {
      return (this.stockQuery?.instances ?? []).filter(Boolean);
    }

    get totalAvailable() {
      return this.stockRows.reduce((n, r) => n + (r.quantityAvailable ?? 0), 0);
    }

    <template>
      <article class='prod'>
        <header class='hd'>
          {{#if @model.image.resolvedUrl}}
            <img class='hero' src={{@model.image.resolvedUrl}} alt='' />
          {{/if}}
          <div class='hd-id'>
            {{#if @model.sku}}<Token class='sku' @value={{@model.sku}} />{{/if}}
            <h1 class='name'>{{@model.productName}}</h1>
            {{#if @model.category}}
              <p class='cat'>{{@model.category}}</p>
            {{/if}}

            {{! Measured: this column was 529.3px wide holding 69px of content
                beside a 212px hero — a fill ratio of 0.33 and 143.1px of dead
                height. The three numbers used to sit in a full-width band below,
                which was 757.4px wide to show 200.6px of content: 74% of that
                row was empty. One pool of dead space filled with the other, and
                a whole horizontal band deleted. They also belong here on the
                merits — cost, price and margin are what identifies a product
                commercially, so they read with its name rather than after it. }}
            <div class='stats'>
              {{! `money` rather than the field atom: the atom drops trailing
                  zeros, so £11.50 rendered as "£ 11.5" — not a price. }}
              <Stat
                class='stat'
                @label='Cost'
                @value={{amountText
                  @model.cost.amount
                  @model.cost.currency.code
                }}
                @roll={{false}}
              />
              <Stat
                class='stat'
                @label='Price'
                @value={{amountText
                  @model.price.amount
                  @model.price.currency.code
                }}
                @roll={{false}}
              />
              <div class='q-ratio'>
                <Stat
                  class='stat stat-ratio'
                  @label='Margin'
                  @value={{if
                    @model.marginPercent
                    (percentText @model.marginPercent)
                    ''
                  }}
                  @roll={{false}}
                />
                {{! Margin is the one figure here that IS a proportion — 0–100%
                    of the price — so it gets a length as well as a number. Cost
                    and price are absolute amounts with nothing to be a
                    proportion OF, which is why they stay figures. The Pret UI
                    ProgressBar is hidden from assistive tech: the figure above
                    already says it, and a margin is not task progress. }}
                {{#if @model.marginPercent}}
                  <ProgressBar
                    class='m-rail'
                    @value={{@model.marginPercent}}
                    aria-hidden='true'
                  />
                {{/if}}
              </div>
            </div>
          </div>
          {{#if @model.isDropship}}
            <StatePill @label='Dropship — no stock held' @hue='teal' />
          {{/if}}
        </header>

        <div class='cols'>
          <section class='sec'>
            <h2><Ruler class='sec-icon' role='presentation' />Shipping profile</h2>
            <@fields.shippingProfile @format='embedded' />
            <p class='hint'>Pre-fills the packing station when this item is the
              only thing in the box.</p>
          </section>

          <section class='sec'>
            <h2><Barcode class='sec-icon' role='presentation' />Identifiers</h2>
            <KeyValue class='kv' @items={{IDENTIFIER_FACTS}}>
              <:value as |item|>
                {{#if (eq item.value 'barcode')}}
                  {{#if @model.barcode}}<Token
                      @value={{@model.barcode}}
                    />{{else}}—{{/if}}
                {{else}}
                  {{#if @model.vendorSku}}<Token
                      @value={{@model.vendorSku}}
                    />{{else}}—{{/if}}
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        </div>

        <section class='sec'>
          <h2><Boxes class='sec-icon' role='presentation' />Stock</h2>
          {{#if this.queryError}}
            <Alert
              @tone='danger'
              @title='Could not read stock for this product.'
              style={{ALERT_STYLE.danger}}
            >{{this.queryError}}</Alert>
            {{! Loading is not empty. Space is reserved so the section does not
              jump when the query lands. }}
          {{else if this.isQueryLoading}}
            <LoadingRows />
          {{else if this.stockRows.length}}
            <p class='stock-total'>
              <strong>{{this.totalAvailable}}</strong>
              available across
              {{this.stockRows.length}}
              {{if (eq this.stockRows.length 1) 'location' 'locations'}}
            </p>
            <ul class='stock-list'>
              {{#each this.stockRows as |row|}}
                <li class='stock-row'>
                  <span class='st-wh'>{{if
                      row.warehouseCode
                      row.warehouseCode
                      '—'
                    }}</span>
                  <span class='st-bin'>{{if
                      row.binLocation
                      row.binLocation
                      ''
                    }}</span>
                  <span class='st-qty'>{{row.quantityAvailable}}</span>
                  <span class='st-state'><StatusPill
                      @label={{row.stockStateLabel}}
                      @hue={{row.stockStateHue}}
                    /></span>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No stock rows reference this product yet'
              @message='Add one from the Inventory tab to start tracking it.'
            />
          {{/if}}
        </section>

        {{#if @model.vendor}}
          <section class='sec'>
            <h2><Building class='sec-icon' role='presentation' />Supplied by</h2>
            {{! The section already IS the surface — it has a ground and an inset.
                Letting the host draw its bordered card boundary in here as well
                put a pill inside a panel: two nested containers for one vendor,
                the inner one stretched full width. Passing displayContainer as
                false drops the boundary and keeps the content. }}
            <@fields.vendor @format='embedded' @displayContainer={{false}} />
          </section>
        {{/if}}
      </article>

      <style scoped>
        .prod {
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
        .hero {
          /* Was a 132px thumbnail inside a 150px header — the most identifying
             thing on the card rendered smaller than the title. */
          width: min(15rem, 28%);
          height: auto;
          aspect-ratio: 1;
          flex: 0 0 auto;
          object-fit: cover;
          border-radius: 0.375rem;
          border: 1px solid var(--ful-rule);
          background-color: color-mix(
            in oklch,
            var(--foreground) 6%,
            transparent
          );
        }
        .hd-id {
          flex: 1 1 14rem;
          min-width: 0;
          /* The column carries the stats now, so it owns its own rhythm and
             stretches to the hero's height — `align-self` beats the parent's
             `align-items: flex-start`, and `margin-top: auto` on the stats then
             seats the figures on the image's bottom edge instead of leaving them
             floating mid-column above 143px of nothing. */
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          align-self: stretch;
        }
        .hd-id .stats {
          margin-top: auto;
          padding-top: var(--boxel-sp-xs);
          border-top: 1px solid var(--ful-rule);
        }
        /* Pret UI Token for the SKU, on the muted ink. The body knob lands
           the pill at the micro size. */
        .hd-id .sku {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(var(--t-micro) + 3.5px);
          align-self: flex-start;
          margin-inline: 0;
        }
        .name {
          margin: 0.1rem 0 0;
          font-size: var(--t-xl);
          line-height: 1.05;
        }
        .cat {
          margin: 0.25rem 0 0;
          font-size: var(--t-sm);
          color: var(--muted-foreground);
        }
        /* Inside the header column now, so the gap tightens: `sp-xl` was spacing
           for a 757px band and here it would push Margin off the end. */
        .stats {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-lg);
        }
        /* Pret UI Stat: the knob keeps the figures at the old large size. A
           ratio is not an amount, so the margin is one step quieter and muted
           so the two money figures read as the pair they are. */
        .stat {
          --text-stat: var(--t-lg);
        }
        .stat-ratio {
          --text-stat: var(--t-body);
          color: var(--muted-foreground);
        }
        /* Pret UI ProgressBar for the margin length. Deliberately quiet — a
           second reading of a number already printed — so the fill is the
           muted ink rather than the primary, and the track keeps its old mix
           because --inset all but vanishes on the page. */
        .m-rail {
          margin-top: 0.25rem;
        }
        .m-rail :deep(.pretui-progress) {
          background-color: color-mix(
            in oklch,
            var(--foreground) 10%,
            transparent
          );
        }
        .m-rail :deep(.pretui-progress-fill) {
          background-color: var(--muted-foreground);
        }
        .stock-total {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--t-body);
        }
        .stock-total strong {
          font-family: var(--font-mono);
          font-size: var(--t-lg);
          font-weight: 800;
        }
        .stock-list {
          margin: 0;
          padding: 0;
          list-style: none;
          display: grid;
          gap: 0.125rem;
        }
        .stock-row {
          display: grid;
          grid-template-columns: 6rem minmax(0, 1fr) 4rem 5rem;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: 0.375rem 0;
          border-top: 1px solid var(--ful-rule);
          font-size: var(--t-sm);
        }
        .st-wh,
        .st-bin,
        .st-qty {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .st-bin {
          color: var(--muted-foreground);
        }
        .st-qty {
          text-align: right;
          font-weight: 700;
        }
        .st-state {
          text-align: right;
        }
        .cols {
          display: grid;
          gap: var(--boxel-sp-lg);
          /* `auto-fit` with a max keeps a two-line column from being handed the
             same 368px as a paragraph one. */
          grid-template-columns: repeat(auto-fit, minmax(15rem, max-content));
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
        .hint {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--t-micro);
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue: label and value sizes and the column gap. */
        .kv {
          --text-ui: var(--t-micro);
          --text-ui-md: var(--t-sm);
          --space-6: 1.25rem;
        }
        /* Pret UI EmptyState, compact: no texture, 1rem padding, and the
           title at the body size. */
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
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
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof FulfilmentProduct> {
    <template>
      <div class='p-emb'>
        {{! Pret UI EntityDisplay: the photo in the thumbnail slot, the name as
            the title and the SKU as a Token on the meta line. With no photo
            there is no visual block, so no empty gutter is reserved. }}
        {{#if @model.image.resolvedUrl}}
          <EntityDisplay
            class='p-entity'
            @variant='thumbnail'
            @title={{@model.productName}}
            @center={{true}}
          >
            <:visual><img
                class='p-thumb'
                src={{@model.image.resolvedUrl}}
                alt=''
              /></:visual>
            <:meta>{{#if @model.sku}}<Token
                  class='p-sku'
                  @value={{@model.sku}}
                />{{/if}}</:meta>
          </EntityDisplay>
        {{else}}
          <EntityDisplay
            class='p-entity'
            @title={{@model.productName}}
            @center={{true}}
          >
            <:meta>{{#if @model.sku}}<Token
                  class='p-sku'
                  @value={{@model.sku}}
                />{{/if}}</:meta>
          </EntityDisplay>
        {{/if}}
        <span class='p-slot'>{{#if @model.price.amount}}<@fields.price
              @format='atom'
            />{{else}}—{{/if}}</span>
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
        .p-emb {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: grid;
          grid-template-columns: minmax(0, 1fr) 5.5rem;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.9rem;
        }
        /* Pret UI EntityDisplay knobs: the old thumbnail size, gap and title
           size. */
        .p-entity {
          --pretui-entity-visual-size: 2.125rem;
          --space-3: var(--boxel-sp-xs);
          --text-ui-md: 0.9rem;
        }
        .p-thumb {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }
        /* Pret UI Token for the SKU, on the muted ink. */
        .p-entity .p-sku {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(0.72rem + 3.5px);
          margin-inline: 0;
        }
        .p-slot {
          text-align: right;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-weight: 700;
          color: var(--foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof FulfilmentProduct> {
    <template>
      <span class='p-atom'>{{if
          @model.sku
          @model.sku
          @model.productName
        }}</span>
      <style scoped>
        .p-atom {
          font-family: var(--font-mono);
          font-size: 0.85em;
          font-weight: 700;
          letter-spacing: 0.05em;
        }
      </style>
    </template>
  };

  // The pick card. A picker reads the SKU first and the name second, so the
  // SKU is what survives to badge size — the reverse of a normal card, and the
  // reason this fitted is hand-rolled rather than a FittedCard.
  static fitted = class Fitted extends Component<typeof FulfilmentProduct> {
    <template>
      <article class='fit {{if @model.image.resolvedUrl "has-photo"}}'>
        <div class='r-head'>
          <div class='eyebrow'>
            <PackageIcon class='glyph' />
          </div>
          <span class='sku'>{{@model.sku}}</span>
          <h3 class='headline'>{{@model.productName}}</h3>
        </div>
        <div class='r-body'>
          {{#if @model.image.resolvedUrl}}
            {{! Rule 2's first choice: a real photo outranks the drawn glyph.
                The bars stay as the no-photo state so a product without one is
                still anchored rather than showing an empty grey tile. }}
            <img
              class='photo'
              src={{@model.image.resolvedUrl}}
              alt=''
              loading='lazy'
            />
          {{else}}
            <div class='bars' aria-hidden='true'>
              <span></span><span></span><span></span><span></span><span></span>
              <span></span><span></span><span></span><span></span><span></span>
            </div>
          {{/if}}
          {{#if @model.barcode}}
            <p class='barcode'>{{@model.barcode}}</p>
          {{/if}}
        </div>
        <div class='r-meta'>
          <span class='cat'>{{if @model.category @model.category '—'}}</span>
          {{#if @model.price.amount}}
            <span class='price'><@fields.price @format='atom' /></span>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .fit {
          --type-ratio: 1.22;
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
          /* The identifier is a VALUE, so it must render in full. It is capped
             against the inline axis as well as the block axis so a real order /
             RMA / SKU always fits its box — the ellipsis below is a safety net
             for a pathological identifier, not a truncation strategy. */
          --sku-size: max(
            0.625rem,
            min(
              calc(var(--type-base) * pow(var(--type-ratio), 2)),
              26cqb,
              7.5cqi
            )
          );
          --headline-size: max(0.5625rem, var(--type-base));
          --pad: clamp(0.375rem, calc(0.125rem + 1.7cqi), 0.875rem);

          width: 100%;
          height: 100%;
          box-sizing: border-box;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
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
        .r-meta {
          display: flex;
          gap: 0.5rem;
          justify-content: space-between;
          align-items: baseline;
          font-size: var(--meta-size);
          color: var(--muted-foreground);
        }
        /* SKU is the headline here, so it takes the display size. */
        .sku {
          display: block;
          font-family: var(--font-mono);
          font-size: var(--sku-size);
          font-weight: 800;
          letter-spacing: 0.04em;
          line-height: 1.2;
          color: var(--card-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .headline {
          margin: 0.0625rem 0 0;
          font-size: var(--headline-size);
          font-weight: 500;
          line-height: 1.2;
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }
        /* The photo fills whatever the body row was given rather than claiming a
           fixed height, so it grows with the tile and never pushes the SKU or
           the price out of their rows. */
        .photo {
          display: block;
          width: 100%;
          height: 100%;
          min-height: 0;
          object-fit: cover;
          border-radius: 0.25rem;
          background-color: color-mix(
            in oklch,
            var(--card-foreground) 8%,
            transparent
          );
        }
        .has-photo .r-body {
          display: grid;
          grid-template-rows: minmax(0, 1fr) auto;
          gap: 0.25rem;
          margin-top: 0.3125rem;
        }
        .bars {
          display: flex;
          align-items: stretch;
          gap: 0.125rem;
          height: 1.125rem;
          margin-top: 0.375rem;
        }
        .bars span {
          display: block;
          background-color: color-mix(
            in oklch,
            var(--card-foreground) 70%,
            transparent
          );
        }
        .bars span:nth-child(odd) {
          width: 0.125rem;
        }
        .bars span:nth-child(even) {
          width: 0.25rem;
          opacity: 0.55;
        }
        .barcode {
          margin: 0.1875rem 0 0;
          font-family: var(--font-mono);
          font-size: var(--meta-size);
          letter-spacing: 0.18em;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
        }
        .price {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-weight: 700;
          color: var(--card-foreground);
        }
        .cat {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: auto;
          }
          .r-body,
          .r-meta,
          .headline {
            display: none;
          }
        }
        @container fitted-card (50px < height <= 80px) {
          .r-body {
            display: none;
          }
          .headline {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (80px < height <= 130px) {
          .barcode {
            display: none;
          }
          .bars {
            height: 0.75rem;
          }
        }
        @container fitted-card (width <= 140px) {
          .cat {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default FulfilmentProduct;

function percentText(pct: number | undefined) {
  return `${pct}%`;
}
