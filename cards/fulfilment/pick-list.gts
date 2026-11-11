import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DatetimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import RouteIcon from '@cardstack/boxel-icons/route';
import { Warehouse } from './warehouse';
import { FulfilmentOrder } from './fulfilment-order';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { FitTile } from '../shared/fit-tile';
import { IsoFrame } from '../shared/compact-sheet';

export const PICK_LIST_STATUSES = [
  { value: 'pending', label: 'Not started' },
  { value: 'in_progress', label: 'In progress' },
  { value: 'complete', label: 'Complete' },
];

export const PickListStatusField = markDefinition(
  enumField(StringField, {
    options: PICK_LIST_STATUSES,
    displayName: 'Pick List Status',
  }),
);

// One stop on the walk. `orderNumbers` is plural because batching is the whole
// point of a pick list: the same SKU picked once can serve three orders, and
// the picker needs to know how many to grab in total.
export class PickItemField extends FieldDef {
  static displayName = 'Pick Item';

  @field sku = contains(StringField);
  @field productName = contains(StringField);
  @field barcode = contains(StringField);
  @field binLocation = contains(StringField);
  @field quantity = contains(NumberField);
  @field pickedQuantity = contains(NumberField);
  @field isShort = contains(BooleanField);
  @field orderNumbers = containsMany(StringField);

  get isDone() {
    return (
      this.isShort === true ||
      (this.pickedQuantity ?? 0) >= (this.quantity ?? 0)
    );
  }

  static embedded = class Embedded extends Component<typeof PickItemField> {
    <template>
      <div class='pi {{if @model.isDone "done"}}'>
        <span class='pi-bin'>{{if
            @model.binLocation
            @model.binLocation
            '—'
          }}</span>
        <div class='pi-id'>
          <span class='pi-sku'>{{@model.sku}}</span>
          <span class='pi-name'>{{@model.productName}}</span>
        </div>
        <span class='pi-qty'>{{if
            @model.pickedQuantity
            @model.pickedQuantity
            0
          }}
          /
          {{if @model.quantity @model.quantity 0}}</span>
        <span class='pi-flag'>{{if @model.isShort 'short' ''}}</span>
      </div>

      <style scoped>
        .pi {
          display: grid;
          grid-template-columns: 6.5rem minmax(0, 1fr) 4rem 3.5rem;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-2xs) 0;
          font-size: var(--boxel-font-size-sm);
        }
        .done {
          opacity: 0.55;
        }
        .pi-bin {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          letter-spacing: 0.06em;
          color: var(--foreground);
        }
        .pi-id {
          display: flex;
          flex-direction: column;
          min-width: 0;
        }
        .pi-sku {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          color: var(--foreground);
        }
        .pi-name {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .pi-qty {
          text-align: right;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-weight: 700;
        }
        .pi-flag {
          text-align: right;
          font-size: var(--boxel-eyebrow-font-size);
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: color-mix(in oklch, var(--destructive) 60%, var(--foreground));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof PickItemField> {
    <template>
      <span class='pi-atom'>{{@model.binLocation}} · {{@model.sku}}</span>
      <style scoped>
        .pi-atom {
          font-family: var(--font-mono);
          font-size: 0.85em;
        }
      </style>
    </template>
  };
}

// Bins are named so that sorting them lexically walks the aisles in order —
// "A3-B-14" before "A3-C-02" before "B1-A-01". That is a property of how bins
// are labelled, not an optimisation this card invents, so the route is a plain
// sort rather than a solver pretending to be one.
export function routeOrder(items: PickItemField[] | undefined) {
  return [...(items ?? [])].filter(Boolean).sort((a, b) =>
    (a.binLocation ?? '~').localeCompare(b.binLocation ?? '~', undefined, {
      numeric: true,
    }),
  );
}

class PickListIsolated extends Component<typeof PickList> {
  @tracked scanValue = '';
  @tracked scanFeedback: string | undefined = undefined;
  @tracked busy = false;

  get model() {
    return this.args.model as PickList;
  }

  get canAct() {
    // No store means no persistence — in prerender or a read-only surface the
    // walk renders as a plan rather than offering buttons that would silently
    // do nothing.
    return Boolean((this.args as any).context?.store && this.model?.id);
  }

  // A scanner can send a second Enter before the first save finishes, so
  // picks run one at a time: each waits for the one before it, then reads the
  // next item afresh.
  #queue: Promise<unknown> = Promise.resolve();

  private enqueue(work: () => Promise<void>): Promise<void> {
    let next = this.#queue.then(work, work);
    this.#queue = next.catch(() => undefined);
    return next;
  }

  // Writes the whole item array back. `store.patch` replaces arrays wholesale,
  // so the current values have to be re-serialized, not just the changed one.
  // Returns whether the write saved; a failure is reported in the feedback.
  private async writeItems(
    mutate: (item: any, index: number) => any,
  ): Promise<boolean> {
    let store = (this.args as any).context?.store;
    let id = this.model?.id;
    if (!store || !id) {
      return false;
    }
    this.busy = true;
    try {
      let serialized = (this.model.items ?? []).map((item, index) => {
        let next = mutate(item, index);
        return {
          sku: next.sku ?? null,
          productName: next.productName ?? null,
          barcode: next.barcode ?? null,
          binLocation: next.binLocation ?? null,
          quantity: next.quantity ?? null,
          pickedQuantity: next.pickedQuantity ?? null,
          isShort: next.isShort ?? null,
          orderNumbers: next.orderNumbers ?? [],
        };
      });
      let allDone = serialized.every(
        (i) => i.isShort || (i.pickedQuantity ?? 0) >= (i.quantity ?? 0),
      );
      await store.patch(id, {
        attributes: {
          items: serialized,
          status: allDone ? 'complete' : 'in_progress',
          ...(allDone ? { completedAt: new Date().toISOString() } : {}),
        },
      });
      return true;
    } catch (e) {
      this.scanFeedback = `Couldn't save the pick: ${
        e instanceof Error ? e.message : String(e)
      }`;
      return false;
    } finally {
      this.busy = false;
    }
  }

  private matches(item: any, value: string) {
    let v = value.trim().toLowerCase();
    if (!v) {
      return false;
    }
    return (
      (item.barcode ?? '').toLowerCase() === v ||
      (item.sku ?? '').toLowerCase() === v
    );
  }

  @action
  pickCurrent() {
    return this.enqueue(() => this.pick());
  }

  private async pick() {
    let current = this.model.nextItem;
    if (!current) {
      return;
    }
    let saved = await this.writeItems((item) =>
      item === current
        ? {
            sku: item.sku,
            productName: item.productName,
            barcode: item.barcode,
            binLocation: item.binLocation,
            quantity: item.quantity,
            pickedQuantity: item.quantity,
            isShort: false,
            orderNumbers: item.orderNumbers,
          }
        : item,
    );
    if (saved) {
      this.scanFeedback = undefined;
    }
  }

  @action
  markShort() {
    return this.enqueue(async () => {
      let current = this.model.nextItem;
      if (!current) {
        return;
      }
      let saved = await this.writeItems((item) =>
        item === current
          ? {
              sku: item.sku,
              productName: item.productName,
              barcode: item.barcode,
              binLocation: item.binLocation,
              quantity: item.quantity,
              pickedQuantity: item.pickedQuantity ?? 0,
              isShort: true,
              orderNumbers: item.orderNumbers,
            }
          : item,
      );
      if (saved) {
        this.scanFeedback =
          'Marked short — the order will need a partial ship.';
      }
    });
  }

  @action
  setScan(value: string) {
    this.scanValue = value;
  }

  // A USB barcode scanner is a keyboard that types fast and presses Enter.
  // Handling Enter on a plain text input therefore supports real hardware
  // without any device integration at all.
  @action
  async handleScanKey(event: Event) {
    if (!(event instanceof KeyboardEvent)) return;
    if (event.key !== 'Enter') {
      return;
    }
    event.preventDefault();
    let value = this.scanValue;
    this.scanValue = '';
    await this.enqueue(async () => {
      let current = this.model.nextItem;
      if (!current) {
        this.scanFeedback = 'Everything on this list is already picked.';
        return;
      }
      if (this.matches(current, value)) {
        await this.pick();
      } else {
        this.scanFeedback = `That is not ${current.sku}. Check the bin before picking.`;
      }
    });
  }

  get stats() {
    return pickStats(this.model);
  }

  <template>
    <IsoFrame>
      <article class='pl'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>Pk</span>
            <div class='id'>
              <h1 class='name'>{{@model.cardTitle}}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            <span class='st' data-tone={{statusTone @model.status}}><span
                class='dot'
              ></span>{{statusText @model.status}}</span>
            <span class='st'><span class='dot'></span>{{unitsText @model}}
              picked</span>
          </div>
        </header>

        <div class='stats'>
          {{#each this.stats as |s|}}
            <div class='stat'>
              <span class='st cap' data-tone={{s.tone}}><span
                  class='dot'
                ></span>{{s.label}}</span>
              <span class='num'>{{s.value}}</span>
              <span class='meta'>{{s.meta}}</span>
            </div>
          {{/each}}
        </div>

        <section class='blk'>
          <h2>Next pick</h2>
          {{#if @model.nextItem}}
            <div class='row'>
              <span class='lead'>
                <span class='strong'>{{@model.nextItem.productName}}
                  ×
                  {{@model.nextItem.quantity}}</span>
                <span class='meta'>{{itemMeta @model.nextItem}}</span>
              </span>
              <span class='mono'>{{dash @model.nextItem.binLocation}}</span>
            </div>
            {{#if this.canAct}}
              <div class='scan'>
                <Input
                  class='scan-input'
                  @value={{this.scanValue}}
                  @onInput={{this.setScan}}
                  @placeholder='Scan barcode or type SKU'
                  aria-label='Scan barcode or SKU'
                  {{on 'keydown' this.handleScanKey}}
                />
                <Button
                  @tone='primary'
                  @appearance='accent'
                  @size='sm'
                  @disabled={{this.busy}}
                  {{on 'click' this.pickCurrent}}
                >Picked {{@model.nextItem.quantity}}</Button>
                <Button
                  @tone='neutral'
                  @appearance='outlined'
                  @size='sm'
                  @disabled={{this.busy}}
                  {{on 'click' this.markShort}}
                >Item missing</Button>
              </div>
              {{#if this.scanFeedback}}
                <p class='row meta' role='status'>{{this.scanFeedback}}</p>
              {{/if}}
            {{else}}
              <p class='row meta'>Open this pick list in the app to scan and
                record picks.</p>
            {{/if}}
          {{else}}
            <p class='row meta'>Every line is accounted for. Take the tote to
              the packing station.</p>
          {{/if}}
        </section>

        <section class='blk'>
          <h2>Pick path</h2>
          {{#each @model.route as |item|}}
            <div class='row'>
              <span class='lead'>
                <span class='strong'>{{item.productName}}
                  ×
                  {{item.quantity}}</span>
                <span class='meta'>{{routeMeta item}}</span>
              </span>
              <span class='st' data-tone={{itemTone item}}><span
                  class='dot'
                ></span>{{if item.isShort 'short · '}}{{if
                  item.pickedQuantity
                  item.pickedQuantity
                  0
                }}
                /
                {{if item.quantity item.quantity 0}}</span>
            </div>
          {{else}}
            <p class='row meta'>No items on this list.</p>
          {{/each}}
        </section>

        <section class='blk'>
          <h2>Progress</h2>
          <dl class='kv'>
            <dt class='cap'>Units picked</dt>
            <dd>{{unitsText @model}}</dd>
          </dl>
          <div class='prog'>
            <ProgressBar
              @value={{if @model.pickedUnits @model.pickedUnits 0}}
              @max={{if @model.totalUnits @model.totalUnits 1}}
              @label='Units picked'
              @hue='var(--foreground)'
            />
          </div>
        </section>

        <section class='blk'>
          <h2>Linked</h2>
          <dl class='kv'>
            <dt class='cap'>Warehouse</dt>
            <dd>{{#if @model.warehouse}}<@fields.warehouse
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
            {{#each @fields.orders as |Order|}}
              <dt class='cap'>Order</dt>
              <dd><Order @format='atom' @displayContainer={{false}} /></dd>
            {{else}}
              <dt class='cap'>Order</dt>
              <dd>—</dd>
            {{/each}}
          </dl>
        </section>
      </article>
    </IsoFrame>
    <style scoped>
      .pl {
        container-type: inline-size;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        color: var(--card-foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
        --pretui-button-h: 1.625rem;
        --control-height: 1.625rem;
      }
      .ihead {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        padding: var(--boxel-sp-xs);
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
      }
      .id {
        min-width: 0;
      }
      .name {
        margin: 0;
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
        gap: var(--boxel-sp-2xs);
        font-weight: 600;
        white-space: nowrap;
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
        overflow: hidden;
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        padding: var(--boxel-sp-xs);
        border-right: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
        margin-bottom: -1px;
      }
      .num {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        line-height: 1.15;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .blk {
        border-top: 1px solid var(--border);
      }
      .blk h2 {
        margin: 0;
        padding: var(--boxel-sp-sm) var(--boxel-sp-xs) var(--boxel-sp-2xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
        min-height: 1.75rem;
        margin: 0;
        padding: 0 var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .lead {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        column-gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .strong {
        font-weight: 600;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .scan {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .scan-input {
        flex: 1 1 12rem;
        min-width: 0;
      }
      .kv {
        display: grid;
        grid-template-columns: minmax(7rem, 9.5rem) minmax(0, 1fr);
        margin: 0;
      }
      .kv dt,
      .kv dd {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        min-height: 1.75rem;
        margin: 0;
        border-top: 1px solid var(--border);
      }
      .kv dt {
        padding-left: var(--boxel-sp-xs);
      }
      .kv dd {
        padding: 0 var(--boxel-sp-xs);
        min-width: 0;
      }
      .prog {
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      @container (width < 480px) {
        .stats {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    </style>
  </template>
}

export class PickList extends CardDef {
  static displayName = 'Pick List';
  static icon = RouteIcon;

  @field pickListNumber = contains(StringField);
  @field warehouse = linksTo(() => Warehouse);
  @field orders = linksToMany(() => FulfilmentOrder);
  @field items = containsMany(PickItemField);
  @field assignedTo = contains(StringField);
  @field status = contains(PickListStatusField);
  @field createdAt = contains(DatetimeField);
  @field completedAt = contains(DatetimeField);

  @field totalUnits = contains(NumberField, {
    computeVia: function (this: PickList) {
      return (this.items ?? []).reduce((s, i) => s + (i?.quantity ?? 0), 0);
    },
  });

  @field pickedUnits = contains(NumberField, {
    computeVia: function (this: PickList) {
      return (this.items ?? []).reduce(
        (s, i) => s + (i?.pickedQuantity ?? 0),
        0,
      );
    },
  });

  @field warehouseCode = contains(StringField, {
    computeVia: function (this: PickList) {
      return this.warehouse?.code;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: PickList) {
      return this.pickListNumber?.length
        ? this.pickListNumber
        : 'Untitled Pick List';
    },
  });

  get route() {
    return routeOrder(this.items);
  }

  get remaining() {
    return this.route.filter((i) => !i.isDone);
  }

  get nextItem() {
    return this.remaining[0];
  }

  get doneCount() {
    return this.route.length - this.remaining.length;
  }

  get progressPercent() {
    let total = this.route.length;
    if (!total) {
      return 0;
    }
    return Math.round((this.doneCount / total) * 100);
  }

  // The mobile pick walk. One item at a time, because a picker holding a phone
  // in one hand and a box in the other cannot parse a table.
  static isolated = PickListIsolated;

  static embedded = class Embedded extends Component<typeof PickList> {
    get rows() {
      return embRows(this.args.model as PickList);
    }
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>Pk</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          <span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span>{{statusText @model.status}}</span>
        </header>
        <dl class='kv'>
          {{#each this.rows as |r|}}
            <dt>{{r.k}}</dt>
            <dd>{{r.v}}</dd>
          {{/each}}
          <dt>Warehouse</dt>
          <dd>{{#if @model.warehouse}}<@fields.warehouse
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
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
          padding: var(--boxel-sp-xs);
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
          gap: var(--boxel-sp-2xs);
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
          padding-left: var(--boxel-sp-xs);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-xs);
          min-width: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof PickList> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Pk</span>
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          color: var(--card-foreground);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1rem;
          height: 1rem;
          border-radius: calc(var(--radius) * 0.5);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof PickList> {
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>Pk</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span><span class='st-text'>{{statusText
                @model.status
              }}</span></span></:status>
        <:fact>{{unitsText @model}} picked · next {{nextBin @model}}</:fact>
        <:relations>{{#if @model.warehouse}}<@fields.warehouse
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
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
          color: var(--card-foreground);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          font-weight: 600;
          white-space: nowrap;
          --tone: var(--muted-foreground);
        }
        .st-text {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          flex-shrink: 0;
          border-radius: 50%;
          background-color: var(--tone);
        }
      </style>
    </template>
  };
}

export default PickList;

// ── format helpers (tokens for tone, plain strings for text) ─────────────
type Tone = 'ok' | 'warn' | 'bad' | '';

function statusTone(status: string | undefined | null): Tone {
  return status === 'complete' ? 'ok' : '';
}

function statusText(status: string | undefined | null) {
  let label = PICK_LIST_STATUSES.find((s) => s.value === status)?.label;
  return (label ?? status ?? 'no status').toLowerCase();
}

function itemTone(item: PickItemField): Tone {
  if (item.isShort) return 'bad';
  return item.isDone ? 'ok' : 'warn';
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function dayTime(d: Date | undefined | null) {
  if (!d) return '—';
  return d.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
    timeZone: 'UTC',
  });
}

function metaLine(m: Partial<PickList>) {
  let n = (m.orders ?? []).length;
  return (
    [
      m.assignedTo,
      m.warehouseCode,
      n ? `${n} ${n === 1 ? 'order' : 'orders'}` : undefined,
    ]
      .filter(Boolean)
      .join(' · ') || '—'
  );
}

function unitsText(m: Partial<PickList>) {
  return `${m.pickedUnits ?? 0} / ${m.totalUnits ?? 0}`;
}

function nextBin(m: Partial<PickList>) {
  return m.nextItem?.binLocation ?? '—';
}

function itemMeta(item: PickItemField) {
  return [item.sku, ...(item.orderNumbers ?? [])].filter(Boolean).join(' · ');
}

function routeMeta(item: PickItemField) {
  return [item.binLocation, item.sku, ...(item.orderNumbers ?? [])]
    .filter(Boolean)
    .join(' · ');
}

function pickStats(m: PickList) {
  let total = m.totalUnits ?? 0;
  let pct = total ? Math.round(((m.pickedUnits ?? 0) / total) * 100) : 0;
  let started = m.createdAt;
  return [
    {
      label: 'Picked',
      tone: statusTone(m.status),
      value: unitsText(m),
      meta: `${pct}% of units`,
    },
    {
      label: 'Lines',
      tone: '',
      value: String(m.route.length),
      meta: `${m.doneCount} done`,
    },
    {
      label: 'Started',
      tone: '',
      value: started
        ? started.toLocaleTimeString('en-GB', {
            hour: '2-digit',
            minute: '2-digit',
            timeZone: 'UTC',
          })
        : '—',
      meta: started
        ? started.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            timeZone: 'UTC',
          })
        : '—',
    },
  ];
}

function embRows(m: PickList) {
  let short = m.route.filter((i) => i.isShort).length;
  return [
    { k: 'Picked', v: `${m.pickedUnits ?? 0} of ${m.totalUnits ?? 0} units` },
    { k: 'Lines', v: String(m.route.length) },
    { k: 'Next bin', v: nextBin(m) },
    { k: 'Assigned to', v: dash(m.assignedTo) },
    { k: 'Created', v: dayTime(m.createdAt) },
    { k: 'Short', v: short ? String(short) : 'none' },
    { k: 'Orders', v: String((m.orders ?? []).length) },
  ];
}
