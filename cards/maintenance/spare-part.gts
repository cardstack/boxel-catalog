import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import PackageIcon from '@cardstack/boxel-icons/package';

import { Asset } from './asset';
import { AssetCategory } from './asset-category';
import { Vendor } from '../procurement/vendor';
import { InventoryStock } from '../fulfilment/inventory-stock';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';

/**
 * A stocked consumable or component — filters, oil, unions, extinguishers.
 * Compatibility is by category and/or asset; stock level comes from a linked
 * Inventory Stock when present, else the local
 * `quantityOnHand`. `belowReorderPoint` drives the Reorder Spare Parts
 * command (v1.1) which creates a Purchase Requisition per vendor.
 */
export class SparePart extends CardDef {
  static displayName = 'Spare Part';
  static icon = PackageIcon;

  @field partNumber = contains(StringField);
  @field name = contains(StringField);
  @field description = contains(StringField);
  @field compatibleCategories = linksToMany(() => AssetCategory);
  @field compatibleAssets = linksToMany(() => Asset);
  @field preferredVendor = linksTo(() => Vendor);
  @field stock = linksTo(() => InventoryStock);
  @field quantityOnHand = contains(NumberField, {
    description: 'Local stock count when no Inventory Stock card is linked.',
  });
  @field reorderPoint = contains(NumberField);
  @field reorderQuantity = contains(NumberField);
  @field unitCost = contains(AmountWithCurrency);

  @field onHand = contains(NumberField, {
    computeVia: function (this: SparePart) {
      let s = this.stock?.quantityOnHand;
      return s != null ? s : this.quantityOnHand;
    },
  });
  @field belowReorderPoint = contains(BooleanField, {
    computeVia: function (this: SparePart) {
      if (this.reorderPoint == null) return false;
      return (this.onHand ?? 0) < this.reorderPoint;
    },
  });
  @field stockState = contains(StringField, {
    computeVia: function (this: SparePart) {
      let q = this.onHand ?? 0;
      if (q <= 0) return 'out';
      if (this.belowReorderPoint) return 'low';
      return 'ok';
    },
  });
  @field vendorName = contains(StringField, {
    computeVia: function (this: SparePart) {
      return this.preferredVendor?.name;
    },
  });
  @field vendorId = contains(StringField, {
    computeVia: function (this: SparePart) {
      return this.preferredVendor?.id;
    },
  });
  @field unitCostLabel = contains(StringField, {
    computeVia: function (this: SparePart) {
      let u = this.unitCost;
      return u?.amount != null
        ? formatMoneyDisplay(u.amount, u.currency?.code)
        : '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SparePart) {
      let pn = this.partNumber?.trim();
      let n = this.name?.trim();
      return pn && n ? `${pn} · ${n}` : n || pn || 'Untitled part';
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='sp-atom'><code>{{@model.partNumber}}</code>
        {{@model.name}}</span>
      <style scoped>
        .sp-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--foreground);
        }
        code {
          font-family: var(--font-mono);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      let s = this.args.model.stockState;
      return s === 'out' ? 'red' : s === 'low' ? 'amber' : 'green';
    }
    get stockLabel() {
      let m = this.args.model;
      let s = m.stockState;
      return s === 'out'
        ? 'out of stock'
        : s === 'low'
          ? `low · ${m.onHand}`
          : `in stock ${m.onHand}`;
    }
    <template>
      <div class='sp'>
        <span class='sp-disc'><PackageIcon class='sp-ico' /></span>
        <div class='sp-body'>
          <div class='sp-row'><code
              class='sp-pn'
            >{{@model.partNumber}}</code><span
              class='sp-name'
            >{{@model.name}}</span></div>
          <div class='sp-meta'>{{#if
              @model.vendorName
            }}{{@model.vendorName}}{{/if}}{{#if @model.unitCostLabel}}
              ·
              {{@model.unitCostLabel}}
              each{{/if}}</div>
        </div>
        <StatePill @label={{this.stockLabel}} @hue={{this.hue}} @dot={{true}} />
      </div>
      <style scoped>
        .sp {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
          color: var(--foreground);
        }
        .sp-disc {
          flex: none;
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .sp-ico {
          width: 1rem;
          height: 1rem;
        }
        .sp-body {
          flex: 1;
          min-width: 0;
        }
        .sp-row {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
          min-width: 0;
        }
        .sp-pn {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          flex: none;
        }
        .sp-name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sp-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      let s = this.args.model.stockState;
      return s === 'out' ? 'red' : s === 'low' ? 'amber' : 'green';
    }
    get stockLabel() {
      let m = this.args.model;
      let s = m.stockState;
      return s === 'out'
        ? 'out'
        : s === 'low'
          ? `low · ${m.onHand}`
          : `${m.onHand} in stock`;
    }
    <template>
      <FittedCard class='fit' @titleTag='h3'>
        <:eyebrow><span class='mono'>{{if
              @model.partNumber
              @model.partNumber
              'no P/N'
            }}</span></:eyebrow>
        <:title>{{@model.name}}</:title>
        <:subtitle>{{@model.vendorName}}{{#if @model.unitCostLabel}}
            ·
            {{@model.unitCostLabel}}{{/if}}</:subtitle>
        <:meta>reorder at
          {{@model.reorderPoint}}
          · qty
          {{@model.reorderQuantity}}</:meta>
        <:badge><StatePill
            @label={{this.stockLabel}}
            @hue={{this.hue}}
          /></:badge>
      </FittedCard>
      <style scoped>
        .fit {
          --fc-title-font-size: var(--boxel-font-size-sm);
          --fc-subtitle-font-size: var(--boxel-font-size-xs);
        }
        .mono {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      let s = this.args.model.stockState;
      return s === 'out' ? 'red' : s === 'low' ? 'amber' : 'green';
    }
    <template>
      <article class='iso'>
        <header class='hero'>
          <div>
            <p class='eyebrow'>Spare part ·
              <code>{{@model.partNumber}}</code></p>
            <h1 class='title'>{{@model.name}}</h1>
            {{#if @model.description}}<p
                class='desc'
              >{{@model.description}}</p>{{/if}}
          </div>
          <div class='stock'>
            <span class='stock-v'>{{if @model.onHand @model.onHand 0}}</span>
            <StatePill
              @label={{@model.stockState}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            <span class='stock-l'>on hand · reorder at
              {{@model.reorderPoint}}
              ({{@model.reorderQuantity}}
              per order)</span>
          </div>
        </header>
        <div class='grid'>
          <section class='panel'>
            <h2>Supply</h2>
            <dl class='facts'>
              <div><dt>Preferred vendor</dt><dd>{{#if
                    @model.preferredVendor
                  }}<@fields.preferredVendor
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
              <div><dt>Unit cost</dt><dd>{{if
                    @model.unitCostLabel
                    @model.unitCostLabel
                    '—'
                  }}</dd></div>
              <div><dt>Inventory stock</dt><dd>{{#if
                    @model.stock
                  }}<@fields.stock @format='atom' />{{else}}local count{{/if}}</dd></div>
            </dl>
          </section>
          <section class='panel'>
            <h2>Fits</h2>
            {{#if @model.compatibleCategories.length}}
              <div class='chips'><@fields.compatibleCategories
                  @format='atom'
                /></div>
            {{/if}}
            {{#if @model.compatibleAssets.length}}
              <div class='chips'><@fields.compatibleAssets
                  @format='atom'
                /></div>
            {{/if}}
            {{#unless @model.compatibleCategories.length}}{{#unless
                @model.compatibleAssets.length
              }}<p class='empty'>No compatibility recorded.</p>{{/unless}}{{/unless}}
          </section>
        </div>
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
          color: var(--foreground);
          background: var(--card);
        }
        .hero {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp);
          flex-wrap: wrap;
          align-items: flex-start;
        }
        .eyebrow {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        .eyebrow code {
          font-family: var(--font-mono);
          text-transform: none;
          color: var(--foreground);
        }
        .title {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
        }
        .desc {
          margin: var(--boxel-sp-4xs) 0 0;
          color: var(--muted-foreground);
          max-width: 60ch;
        }
        .stock {
          display: grid;
          justify-items: end;
          gap: var(--boxel-sp-4xs);
          text-align: right;
        }
        .stock-v {
          font-size: 2.5rem;
          font-weight: 700;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .stock-l {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(16.25rem, 1fr));
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-lg);
          background: var(--card);
          box-shadow: var(--shadow-2xs);
          padding: var(--boxel-sp);
          display: grid;
          gap: var(--boxel-sp-sm);
          align-content: start;
        }
        .panel h2 {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .facts {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .facts dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .facts dd {
          margin: 0;
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .empty {
          margin: 0;
          font-style: italic;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'fits', label: 'Compatibility' },
      { id: 'stock', label: 'Stock & supply' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Spare part sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer
            @label='Part number'
            @vertical={{true}}
          ><@fields.partNumber /></FieldContainer>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer
            @label='Description'
            @vertical={{true}}
          ><@fields.description /></FieldContainer>
        </e.Section>
        <e.Section @id='fits' @title='Compatibility' @cols={{2}}>
          <FieldContainer
            @label='Categories'
            @vertical={{true}}
          ><@fields.compatibleCategories /></FieldContainer>
          <FieldContainer
            @label='Assets'
            @vertical={{true}}
          ><@fields.compatibleAssets /></FieldContainer>
        </e.Section>
        <e.Section
          @id='stock'
          @title='Stock & supply'
          @hint='link an Inventory Stock card or keep a local count'
          @cols={{2}}
        >
          <FieldContainer
            @label='Inventory stock'
            @vertical={{true}}
          ><@fields.stock /></FieldContainer>
          <FieldContainer
            @label='Quantity on hand (local)'
            @vertical={{true}}
          ><@fields.quantityOnHand /></FieldContainer>
          <FieldContainer
            @label='Reorder point'
            @vertical={{true}}
          ><@fields.reorderPoint /></FieldContainer>
          <FieldContainer
            @label='Reorder quantity'
            @vertical={{true}}
          ><@fields.reorderQuantity /></FieldContainer>
          <FieldContainer
            @label='Preferred vendor'
            @vertical={{true}}
          ><@fields.preferredVendor /></FieldContainer>
          <FieldContainer
            @label='Unit cost'
            @vertical={{true}}
          ><@fields.unitCost /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

export default SparePart;
