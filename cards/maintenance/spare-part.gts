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
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import PackageIcon from '@cardstack/boxel-icons/package';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { FitTile } from '../shared/fit-tile';

import { Asset } from './asset';
import { AssetCategory } from './asset-category';
import { Vendor } from '../procurement/vendor';
import { InventoryStock } from '../fulfilment/inventory-stock';
import {
  Chip,
  Dot,
  Head,
  Mark,
  Row,
  Kv,
  KvRow,
  Section,
  Stats,
  money,
  type Tone,
} from './card-ui';
import { IsoFrame } from '../shared/compact-sheet';

const STOCK_TONE: Record<string, Tone> = { out: 'bad', low: 'warn', ok: 'ok' };
const ASSET_TONE: Record<string, Tone> = {
  'in-service': 'ok',
  'out-of-service': 'bad',
  'under-maintenance': 'warn',
};

function stockTone(m: Partial<SparePart>): Tone {
  return STOCK_TONE[m.stockState ?? 'ok'] ?? 'muted';
}
function stockLabel(m: Partial<SparePart>): string {
  return m.stockState === 'out' ? 'out' : (m.stockState ?? 'ok');
}
function metaLine(m: Partial<SparePart>): string {
  let d = m.description?.replace(/\.$/, '');
  return [m.partNumber, d].filter(Boolean).join(' · ');
}
function n(v?: number | null): string {
  return v != null ? String(v) : '';
}
function stockValue(m: Partial<SparePart>): string {
  let u = m.unitCost;
  return u?.amount != null
    ? money(u.amount * (m.onHand ?? 0), u.currency?.code)
    : '';
}
function unitCost(m: Partial<SparePart>): string {
  let u = m.unitCost;
  return u?.amount != null ? money(u.amount, u.currency?.code) : '';
}
function onHandFact(m: Partial<SparePart>): string {
  return m.reorderPoint != null ? `reorder at ${m.reorderPoint}` : '';
}
function assetTone(a: any): Tone {
  return ASSET_TONE[a?.status ?? ''] ?? 'muted';
}
function label(s?: string | null): string {
  return (s ?? '').replace(/-/g, ' ');
}
function catCode(c: any): string {
  return (c?.name ?? '').split(/[\s/]+/)[0] ?? '';
}

const StockDots: TemplateOnlyComponent<{
  Args: { model: Partial<SparePart> };
}> = <template>
  <Dot @tone={{stockTone @model}} @label={{stockLabel @model}} />
  {{#if @model.belowReorderPoint}}{{#if @model.reorderQuantity}}<Dot
        @label={{concat 'reorder ' @model.reorderQuantity}}
      />{{/if}}{{/if}}
</template>;

function concat(a: unknown, b: unknown) {
  return `${a ?? ''}${b ?? ''}`;
}

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
      return u?.amount != null ? money(u.amount, u.currency?.code) : '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SparePart) {
      let pn = this.partNumber?.trim();
      let n = this.name?.trim();
      return pn && n ? `${pn} · ${n}` : n || pn || 'Untitled part';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get stats() {
      let m = this.args.model;
      return [
        { label: 'On hand', value: n(m.onHand) || '0', meta: onHandFact(m) },
        {
          label: 'Unit cost',
          value: unitCost(m) || '—',
          meta: m.unitCost?.currency?.code ?? '',
        },
        {
          label: 'Reorder qty',
          value: n(m.reorderQuantity) || '—',
          meta: m.vendorName ? `from ${m.vendorName}` : '',
        },
      ];
    }
    <template>
      <IsoFrame>
        <article class='sp'>
          <Head @mark='Pt' @title={{@model.name}} @meta={{metaLine @model}}>
            <StockDots @model={{@model}} />
          </Head>
          <Stats @items={{this.stats}} />
          <div class='cols'>
            <div class='col'>
              <Section @title='Stock'>
                <Kv>
                  <KvRow @label='On hand' @value={{n @model.onHand}} />
                  <KvRow
                    @label='Reorder point'
                    @value={{n @model.reorderPoint}}
                  />
                  <KvRow
                    @label='Reorder quantity'
                    @value={{n @model.reorderQuantity}}
                  />
                  <KvRow @label='State'><Dot
                      @tone={{stockTone @model}}
                      @label={{stockLabel @model}}
                    /></KvRow>
                </Kv>
              </Section>
              <Section @title='Cost'>
                <Kv>
                  <KvRow @label='Unit cost' @value={{unitCost @model}} />
                  <KvRow @label='Stock value' @value={{stockValue @model}} />
                  <KvRow
                    @label='Preferred vendor'
                    @value={{@model.vendorName}}
                  />
                </Kv>
              </Section>
              <Section @title='Compatible with'>
                {{#each @model.compatibleCategories as |c|}}
                  <Row
                    @title={{c.name}}
                    @meta='category'
                    @state={{catCode c}}
                  />
                {{/each}}
                {{#each @model.compatibleAssets as |a|}}
                  <Row
                    @title={{a.name}}
                    @meta={{a.tag}}
                    @tone={{assetTone a}}
                    @state={{label a.status}}
                  />
                {{/each}}
                {{#unless (fits @model)}}<p class='empty'>No compatibility
                    recorded</p>{{/unless}}
              </Section>
            </div>
            <aside class='col side'>
              <Section @title='Linked'>
                <Kv>
                  <KvRow @label='Vendor'>{{#if
                      @model.preferredVendor
                    }}<@fields.preferredVendor
                        @format='atom'
                      />{{else}}—{{/if}}</KvRow>
                  <KvRow @label='Fits'>{{#if
                      @model.compatibleAssets.length
                    }}<@fields.compatibleAssets
                        @format='atom'
                      />{{else}}—{{/if}}</KvRow>
                  <KvRow @label='Category'>{{#if
                      @model.compatibleCategories.length
                    }}<@fields.compatibleCategories
                        @format='atom'
                      />{{else}}—{{/if}}</KvRow>
                  {{#if @model.stock}}
                    <KvRow @label='Stock'><@fields.stock
                        @format='atom'
                      /></KvRow>
                  {{/if}}
                </Kv>
              </Section>
              <Section @title='Details'>
                <PartDetails @model={{@model}} />
              </Section>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .sp {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .col {
          min-inline-size: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        .empty {
          padding-block: var(--boxel-sp-5xs);
          color: var(--muted-foreground);
        }
        @container (width < 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='emb'>
        <Head @mark='Pt' @title={{@model.name}} @meta={{metaLine @model}} />
        <div class='body'>
          <div class='dots'><StockDots @model={{@model}} /></div>
          <p class='fact'><strong>{{if @model.onHand @model.onHand 0}}
              on hand</strong>
            {{#if @model.reorderPoint}}· {{onHandFact @model}}{{/if}}</p>
          <PartDetails @model={{@model}} @short={{true}} />
          <Kv>
            <KvRow @label='Vendor'>{{#if
                @model.preferredVendor
              }}<@fields.preferredVendor
                  @format='atom'
                />{{else}}—{{/if}}</KvRow>
            <KvRow @label='Fits'>{{#if
                @model.compatibleAssets.length
              }}<@fields.compatibleAssets
                  @format='atom'
                />{{else}}—{{/if}}</KvRow>
            <KvRow @label='Category'>{{#if
                @model.compatibleCategories.length
              }}<@fields.compatibleCategories
                  @format='atom'
                />{{else}}—{{/if}}</KvRow>
          </Kv>
        </div>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .body {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        }
        .dots {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get ratio() {
      let m = this.args.model;
      let max = Math.max(m.reorderPoint ?? 0, m.onHand ?? 0, 1);
      return Math.min(100, Math.round(((m.onHand ?? 0) / max) * 100));
    }
    <template>
      <FitTile class='fit'>
        <:avatar><Mark @text='Pt' @size='lg' /></:avatar>
        <:title>{{@model.name}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='dots'><StockDots
              @model={{@model}}
            /></span></:status>
        <:fact><span class='fact'><span><strong>{{if
                  @model.onHand
                  @model.onHand
                  0
                }}
                on hand</strong>
              {{#if @model.reorderPoint}}· {{onHandFact @model}}{{/if}}</span>
            {{#if @model.reorderPoint}}<ProgressBar
                @value={{this.ratio}}
                @label='On hand vs reorder point'
              />{{/if}}</span></:fact>
        <:relations>{{#if @model.preferredVendor}}<@fields.preferredVendor
              @format='atom'
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .fit {
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .dots {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .fact {
          display: grid;
          gap: var(--boxel-sp-5xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <Chip
        @bare={{true}}
        @mark='Pt'
        @name={{@model.name}}
        @tone={{stockTone @model}}
        @meta={{stockLabel @model}}
      />
    </template>
  };
}

const PartDetails: TemplateOnlyComponent<{
  Args: { model: Partial<SparePart>; short?: boolean };
}> = <template>
  <Kv>
    <KvRow @label='On hand' @value={{n @model.onHand}} />
    <KvRow @label='Reorder point' @value={{n @model.reorderPoint}} />
    <KvRow @label='Reorder qty' @value={{n @model.reorderQuantity}} />
    <KvRow @label='Unit cost' @value={{unitCost @model}} />
    <KvRow @label='Stock value' @value={{stockValue @model}} />
    <KvRow @label='Vendor' @value={{@model.vendorName}} />
    {{#unless @short}}
      <KvRow @label='Part number' @value={{@model.partNumber}} />
    {{/unless}}
  </Kv>
</template>;

function fits(m: Partial<SparePart>): boolean {
  return (
    (m.compatibleCategories?.length ?? 0) + (m.compatibleAssets?.length ?? 0) >
    0
  );
}

export default SparePart;
