import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import DatetimeField from 'https://cardstack.com/base/datetime';
import BoxesIcon from '@cardstack/boxel-icons/boxes';
import { FulfilmentProduct } from './fulfilment-product';
import { Warehouse } from './warehouse';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { FitTile } from '../shared/fit-tile';
import { DotLabel } from '../hr/dot-enum-field';
import { on } from '@ember/modifier';
import { IsoFrame } from '../shared/compact-sheet';
// Inventory Stock — one product, in one warehouse, at one bin.
//
// Three quantities are stored and one is computed, and which is which is the
// whole design. On-hand is what a count would find. Reserved is what is already
// promised to orders. AVAILABLE IS NEVER STORED — it is on-hand minus reserved,
// and a stored copy would drift the moment either half moved.
//
// Low stock is likewise derived from the reorder point rather than stored as a
// flag: a stored flag has to be recomputed by whoever last touched the row, and
// eventually someone forgets.
export class InventoryStock extends CardDef {
  static displayName = 'Inventory Item';
  static icon = BoxesIcon;

  @field product = linksTo(() => FulfilmentProduct);
  @field warehouse = linksTo(() => Warehouse);
  @field binLocation = contains(StringField);

  @field quantityOnHand = contains(NumberField);
  @field quantityReserved = contains(NumberField);
  @field quantityIncoming = contains(NumberField);
  @field reorderPoint = contains(NumberField);
  @field reorderQuantity = contains(NumberField);

  @field lastCountedAt = contains(DatetimeField);
  @field lastMovementAt = contains(DatetimeField);

  @field quantityAvailable = contains(NumberField, {
    computeVia: function (this: InventoryStock) {
      return (this.quantityOnHand ?? 0) - (this.quantityReserved ?? 0);
    },
  });

  // Snapshots of the linked cards, as computed fields rather than template
  // traversals. Prerendered fitted does not resolve links, so a fitted template
  // reading `@model.product.sku` renders blank; reading `@model.sku` — an
  // attribute the indexer filled in — renders everywhere.
  @field sku = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      return this.product?.sku;
    },
  });

  @field productName = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      return this.product?.productName;
    },
  });

  @field warehouseCode = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      return this.warehouse?.code;
    },
  });

  // Denormalized for the same reason as `sku` and `productName`: a prerendered
  // fitted cannot resolve a linksTo, so a stock tile that wants the product
  // photo has to be handed the resolved URL rather than the linked card.
  @field productImageUrl = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      return this.product?.image?.resolvedUrl;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      let sku = this.product?.sku;
      let wh = this.warehouse?.code;
      if (!sku) {
        return 'Untitled stock row';
      }
      return wh ? `${sku} @ ${wh}` : sku;
    },
  });

  // A row that has not been filled in yet is not a stock signal. Without this
  // guard a freshly created blank row counted as out-of-stock the moment it was
  // saved, so "Add Stock Row" incremented the OUT OF STOCK KPI that purchasing
  // acts on — a number pointing at a shortage that does not exist.
  // Deliberately NOT `product == null || warehouse == null`: those are linksTo,
  // and a linked card reads as null in prerender and index contexts, so that
  // test marked every saved row a draft and emptied the out-of-stock count.
  // `binLocation` and the quantities are local, so they mean the same thing
  // wherever the row is evaluated.
  get isDraft() {
    return (
      !this.binLocation &&
      this.quantityOnHand == null &&
      this.quantityReserved == null &&
      this.quantityIncoming == null &&
      this.reorderPoint == null
    );
  }

  get isOutOfStock() {
    if (this.isDraft) {
      return false;
    }
    return (this.quantityAvailable ?? 0) <= 0;
  }

  get isLowStock() {
    let point = this.reorderPoint;
    if (point == null) {
      return false;
    }
    return !this.isOutOfStock && (this.quantityAvailable ?? 0) <= point;
  }

  // What the row is telling you to do, in one word. Used for the stock hue and
  // for filtering the inventory tab — one definition, several readers.
  //
  // It is a FIELD rather than a getter because a consumer needs to filter on it
  // through the index: a getter is invisible to a realm query, so a grid backed
  // by a wire query could not honour a "low stock" filter that a table computed
  // in JS, and the two views would silently disagree about which rows exist.
  @field stockState = contains(StringField, {
    computeVia: function (this: InventoryStock) {
      if (this.isDraft) {
        return 'draft';
      }
      if (this.isOutOfStock) {
        return 'out';
      }
      return this.isLowStock ? 'low' : 'ok';
    },
  });

  // `stockState` is the indexed value a query filters on (`ok` / `low` / `out` /
  // `draft`); this is what a reader should see. Kept beside the hue so the two
  // cannot drift apart.
  get stockStateLabel() {
    if (this.isDraft) {
      return 'Draft';
    }
    if (this.isOutOfStock) {
      return 'Out of stock';
    }
    return this.isLowStock ? 'Low stock' : 'In stock';
  }

  // The pill hue for `stockStateLabel`. Low stock is `attention`, the token
  // the low quantity text is inked in.
  get stockStateHue(): Hue {
    if (this.isDraft) {
      return 'slate';
    }
    if (this.isOutOfStock) {
      return 'red';
    }
    return this.isLowStock ? 'attention' : 'green';
  }

  static isolated = class Isolated extends Component<typeof InventoryStock> {
    // Reorder and Count are the next steps of the task; until there are
    // commands for them they open the card the step happens on.
    openProduct = () => {
      let p = this.args.model?.product;
      if (p) this.args.viewCard?.(p, 'isolated');
    };
    openWarehouse = () => {
      let w = this.args.model?.warehouse;
      if (w) this.args.viewCard?.(w, 'isolated');
    };
    get m() {
      return this.args.model as InventoryStock;
    }
    get quantities() {
      let m = this.m;
      return [
        { key: 'On hand', value: num(m?.quantityOnHand) },
        { key: 'Reserved', value: num(m?.quantityReserved) },
        { key: 'Available', value: num(m?.quantityAvailable) },
        { key: 'Reorder point', value: num(m?.reorderPoint) },
      ];
    }
    get location() {
      let m = this.m;
      let wh = m?.warehouse;
      let whLabel = wh?.warehouseName
        ? wh.code
          ? `${wh.warehouseName} (${wh.code})`
          : wh.warehouseName
        : (m?.warehouseCode ?? '—');
      return [
        { key: 'Warehouse', value: whLabel },
        { key: 'Bin', value: m?.binLocation || '—' },
        { key: 'Last counted', value: dateTime(m?.lastCountedAt) },
        { key: 'Last movement', value: dateTime(m?.lastMovementAt) },
      ];
    }
    <template>
      <IsoFrame>
        <article class='page'>
          <header>
            <Avatar
              @name={{if @model.productName @model.productName 'Stock'}}
              @src={{@model.productImageUrl}}
              @shape='square'
              @size={{32}}
            />
            <div class='id'>
              <h1>{{@model.cardTitle}}</h1>
              <p>{{subLine @model}}</p>
            </div>
            <div class='acts'>
              <DotLabel
                @label={{stateWord @model}}
                @hue={{@model.stockStateHue}}
              />
              <DotLabel @label='{{num @model.quantityAvailable}} available' />
              <Button
                @variant='primary'
                @size='sm'
                {{on 'click' this.openProduct}}
              >Reorder {{num @model.reorderQuantity}}</Button>
              <Button
                @variant='outline'
                @size='sm'
                {{on 'click' this.openWarehouse}}
              >Count</Button>
            </div>
          </header>
          <div class='stats'>
            <Stat
              @label='Available'
              @tone={{stateTone @model}}
              @value={{num @model.quantityAvailable}}
              @hint='{{num @model.quantityOnHand}} on hand, {{num
                @model.quantityReserved
              }} reserved'
              @roll={{false}}
            />
            <Stat
              @label='Reorder point'
              @tone='neutral'
              @value={{num @model.reorderPoint}}
              @hint='reorder {{num @model.reorderQuantity}} when hit'
              @roll={{false}}
            />
            <Stat
              @label='Incoming'
              @tone='neutral'
              @value={{num @model.quantityIncoming}}
              @hint={{if @model.quantityIncoming 'on order' 'nothing on order'}}
              @roll={{false}}
            />
            <Stat
              @label='Last movement'
              @tone='neutral'
              @value={{shortDate @model.lastMovementAt}}
              @hint={{shortTime @model.lastMovementAt}}
              @roll={{false}}
            />
          </div>
          <section>
            <h2>Quantities</h2>
            <dl class='kv'>
              {{#each this.quantities as |r|}}
                <dt class='cap'>{{r.key}}</dt>
                <dd>{{r.value}}</dd>
              {{/each}}
            </dl>
          </section>
          <section>
            <h2>Location</h2>
            <dl class='kv'>
              {{#each this.location as |r|}}
                <dt class='cap'>{{r.key}}</dt>
                <dd>{{r.value}}</dd>
              {{/each}}
            </dl>
          </section>
          <section>
            <h2>Linked</h2>
            <dl class='kv'>
              <dt class='cap'>Product</dt>
              <dd><@fields.product
                  @format='atom'
                  @displayContainer={{false}}
                /></dd>
              <dt class='cap'>Warehouse</dt>
              <dd><@fields.warehouse
                  @format='atom'
                  @displayContainer={{false}}
                /></dd>
            </dl>
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .page {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          background: var(--card);
          color: var(--foreground);
          container-type: inline-size;
        }
        header {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.625rem;
          padding: 0.75rem;
        }
        .id {
          flex: 1 1 12rem;
          min-width: 0;
        }
        h1 {
          font-family: var(--font-sans);
          margin: 0;
          font-size: 0.8125rem;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .acts {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.625rem;
          --control-height: 1.625rem;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          border-block: 1px solid var(--border);
        }
        .stats > * {
          padding: 0.4375rem 0.625rem;
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        @container (max-width: 32rem) {
          .stats {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }
          .stats > :nth-child(3) {
            border-inline-start: 0;
          }
          .stats > :nth-child(n + 3) {
            border-block-start: 1px solid var(--border);
          }
        }
        section + section {
          border-block-start: 1px solid var(--border);
        }
        section h2 {
          margin: 0;
          padding: 0.75rem 0.75rem 0.375rem;
          font-size: 0.75rem;
          font-weight: 700;
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
          flex-wrap: wrap;
          min-height: 1.75rem;
          margin: 0;
          border-top: 1px solid var(--border);
        }
        .kv dt {
          padding-left: 0.625rem;
        }
        .kv dd {
          padding: 0 0.625rem;
          min-width: 0;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof InventoryStock> {
    get rows() {
      let m = this.args.model as InventoryStock;
      return [
        { key: 'On hand', value: num(m?.quantityOnHand) },
        { key: 'Reserved', value: num(m?.quantityReserved) },
        { key: 'Available', value: num(m?.quantityAvailable) },
        { key: 'Incoming', value: num(m?.quantityIncoming) },
        { key: 'Reorder point', value: num(m?.reorderPoint) },
        { key: 'Reorder qty', value: num(m?.reorderQuantity) },
        { key: 'Bin', value: m?.binLocation || '—' },
        { key: 'Last counted', value: longDate(m?.lastCountedAt) },
      ];
    }
    <template>
      <article class='emb'>
        <header>
          <Avatar
            @name={{if @model.productName @model.productName 'Stock'}}
            @src={{@model.productImageUrl}}
            @shape='square'
            @size={{28}}
          />
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p>{{subLine @model}}</p>
          </div>
          <DotLabel @label={{stateWord @model}} @hue={{@model.stockStateHue}} />
        </header>
        <KeyValue
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
          class='kv'
        />
        <div class='linked'><span class='cap'>Product</span>
          <@fields.product @format='atom' @displayContainer={{false}} /></div>
        <div class='linked'><span class='cap'>Warehouse</span>
          <@fields.warehouse @format='atom' @displayContainer={{false}} /></div>
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          line-height: 1.4;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          display: flex;
          flex-direction: column;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
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
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv {
          padding-inline: 0.625rem;
          border-block-start: 1px solid var(--border);
        }
        .linked {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.75rem;
          min-height: 1.75rem;
          padding: 0.25rem 0.625rem;
          border-block-start: 1px solid var(--border);
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 6rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof InventoryStock> {
    <template>
      <span class='atom'>
        <Avatar
          @name={{if @model.productName @model.productName 'Stock'}}
          @src={{@model.productImageUrl}}
          @shape='square'
          @size={{16}}
        />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          color: var(--foreground);
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof InventoryStock> {
    <template>
      <FitTile>
        <:avatar><Avatar
            @name={{if @model.productName @model.productName 'Stock'}}
            @src={{@model.productImageUrl}}
            @shape='square'
            @size={{32}}
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{subLine @model}}</:subtitle>
        <:status><DotLabel
            @label={{stateWord @model}}
            @hue={{@model.stockStateHue}}
          /></:status>
        <:fact>{{num @model.quantityAvailable}}
          available ·
          {{num @model.quantityOnHand}}
          on hand ·
          {{num @model.quantityReserved}}
          reserved</:fact>
        <:relations>{{#if @model.warehouse}}<@fields.warehouse
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };
}

function num(n: number | null | undefined) {
  return n == null ? '—' : n.toLocaleString('en-US');
}

function subLine(m: Partial<InventoryStock> | undefined) {
  let parts = [];
  if (m?.productName) parts.push(m.productName);
  if (m?.binLocation) parts.push(`bin ${m.binLocation}`);
  return parts.join(' · ') || '—';
}

// The mock reads the state as one lower-case word: low, out, ok, draft.
function stateWord(m: Partial<InventoryStock> | undefined) {
  let s = m?.stockState;
  return s === 'out' ? 'out of stock' : s === 'ok' ? 'in stock' : (s ?? '—');
}

function stateTone(m: Partial<InventoryStock> | undefined) {
  let s = m?.stockState;
  return s === 'out'
    ? 'danger'
    : s === 'low'
      ? 'warning'
      : s === 'draft'
        ? 'neutral'
        : 'success';
}

function asDate(d: Date | string | null | undefined) {
  if (!d) return undefined;
  let date = d instanceof Date ? d : new Date(d);
  return isNaN(date.getTime()) ? undefined : date;
}

function shortDate(d: Date | string | null | undefined) {
  return (
    asDate(d)?.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    }) ?? '—'
  );
}

function shortTime(d: Date | string | null | undefined) {
  return (
    asDate(d)?.toLocaleTimeString('en-GB', {
      hour: '2-digit',
      minute: '2-digit',
    }) ?? ''
  );
}

function longDate(d: Date | string | null | undefined) {
  return (
    asDate(d)?.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }) ?? '—'
  );
}

function dateTime(d: Date | string | null | undefined) {
  let date = asDate(d);
  return date ? `${longDate(date)}, ${shortTime(date)}` : '—';
}

export default InventoryStock;
