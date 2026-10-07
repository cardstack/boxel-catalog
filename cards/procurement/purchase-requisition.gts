import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import { ProcurementBudget } from './procurement-budget';
import { sumLineItems } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';

export const REQUISITION_STATUSES = [
  'draft',
  'submitted',
  'converted-to-rfq',
  'rejected',
];

export const REQUISITION_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft',
  submitted: 'Submitted',
  'converted-to-rfq': 'Converted to RFQ',
  rejected: 'Rejected',
};

export const REQUISITION_STATUS_COLORS: Record<string, StateColor> = {
  draft: stateColor('slate'),
  submitted: stateColor('amber'),
  'converted-to-rfq': stateColor('green'),
  rejected: stateColor('red'),
};

const STATUS_HUES: Record<string, 'slate' | 'amber' | 'green' | 'red'> = {
  draft: 'slate',
  submitted: 'amber',
  'converted-to-rfq': 'green',
  rejected: 'red',
};

export const RequisitionStatusField = enumField(StringField, {
  options: REQUISITION_STATUSES.map((value) => ({
    value,
    label: REQUISITION_STATUS_LABELS[value],
  })),
  displayName: 'Requisition Status',
});

class PurchaseRequisitionEdit extends Component<typeof PurchaseRequisition> {
  @tracked activeSection = 'whats-needed';

  sections = [
    { id: 'whats-needed', label: "What's Needed" },
    { id: 'line-items', label: 'Line Items' },
    { id: 'justification', label: 'Justification & Budget' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.req-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='req-edit'>
      {{! the container element cannot be restyled by its own query — the responsive grid lives on
          this inner wrapper instead }}
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "whats-needed") "focused"}}'
            data-sect='whats-needed'
          >
            <h3>What's Needed</h3>
            <div class='row'>
              <FieldContainer @label='Requester' @vertical={{true}}>
                <@fields.requester />
              </FieldContainer>
              <FieldContainer @label='Department' @vertical={{true}}>
                <@fields.department />
              </FieldContainer>
              <FieldContainer @label='Needed by' @vertical={{true}}>
                <@fields.neededBy />
              </FieldContainer>
              <FieldContainer @label='Status' @vertical={{true}}>
                <@fields.status />
              </FieldContainer>
            </div>
          </section>

          <section
            class='sect items
              {{if (eq this.activeSection "line-items") "focused"}}'
            data-sect='line-items'
          >
            <h3>Line Items
              <span class='sect-hint'>the estimated total is computed from these
                lines</span></h3>
            <FieldContainer
              @label='Items (description, qty, unit price)'
              @vertical={{true}}
            >
              <@fields.lineItems />
            </FieldContainer>
          </section>

          <section
            class='sect
              {{if (eq this.activeSection "justification") "focused"}}'
            data-sect='justification'
          >
            <h3>Justification &amp; Budget</h3>
            <FieldContainer @label='Business justification' @vertical={{true}}>
              <@fields.justification />
            </FieldContainer>
            <FieldContainer @label='Budget to draw against' @vertical={{true}}>
              <@fields.budget />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .req-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background: var(--background);
        color: var(--foreground);
        /* the procurement family's brand ink, declared ONCE — a linked
           Theme overrides via --procurement-ink */
        --pr-ink: var(--procurement-ink, var(--primary-ink));
        --pr-ink-fg: var(--procurement-ink-fg, var(--card));
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect-nav {
        position: sticky;
        top: 0;
        --edit-section-nav-ink: var(--pr-ink);
        --edit-section-nav-ink-fg: var(--pr-ink-fg);
      }
      .sects {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp-sm);
        transition:
          outline-color 160ms ease,
          box-shadow 160ms ease;
        outline: 0.125rem solid transparent;
        outline-offset: 0.125rem;
      }
      .sect.focused {
        outline-color: var(--pr-ink);
        box-shadow: 0 0 0 0.25rem
          color-mix(in oklch, var(--pr-ink) 12%, transparent);
      }
      .sect.items {
        border-left: 0.1875rem solid var(--pr-ink);
      }
      h3 {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: normal;
        font-family: var(--font-sans);
        font-size: 0.75rem;
        font-weight: 400;
        font-style: italic;
      }
      .row {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
        align-items: start;
      }
      @container edit (width < 640px) {
        .row {
          grid-template-columns: 1fr;
        }
        .edit-body {
          grid-template-columns: 1fr;
        }
        .sect-nav {
          position: static;
          flex-direction: row;
          flex-wrap: wrap;
        }
        .sect-nav::before {
          display: none;
        }
      }
    </style>
  </template>
}

// The internal "I need to buy X" request that starts the Procure-to-Pay
// audit trail. No vendor is involved yet: a requisition names what is
// needed, by when, against which budget, and why — the RFQ that follows
// copies its line items. Single-persona: the procurement manager records
// requisitions on behalf of requesters.
export class PurchaseRequisition extends CardDef {
  static displayName = 'Purchase Requisition';
  static headerColor = '#3e4e88';

  @field requester = contains(StringField);
  @field department = contains(StringField);
  @field neededBy = contains(DateField);
  @field lineItems = containsMany(LineItem);
  @field justification = contains(TextAreaField);
  @field status = contains(RequisitionStatusField);
  @field budget = linksTo(() => ProcurementBudget);

  @field estimatedTotal = contains(NumberField, {
    computeVia: function (this: PurchaseRequisition) {
      return sumLineItems(this.lineItems ?? []).total;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PurchaseRequisition) {
      let first = this.lineItems?.[0]?.description?.trim();
      if (first) {
        let more = (this.lineItems?.length ?? 0) - 1;
        return more > 0 ? `${first} +${more} more` : first;
      }
      return this.requester?.trim()
        ? `Requisition — ${this.requester}`
        : 'Untitled Requisition';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'draft'] ?? 'slate';
    }
    get statusLabel() {
      return (
        REQUISITION_STATUS_LABELS[this.args.model?.status ?? ''] ?? 'Draft'
      );
    }
    get total() {
      return this.args.model?.estimatedTotal ?? 0;
    }
    get timeline(): KeyValueItem[] {
      return [{ key: 'Needed by', value: this.neededByLabel }];
    }
    get neededByLabel() {
      let d = this.args.model?.neededBy;
      return d
        ? d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          })
        : '—';
    }
    <template>
      <article class='pr'>
        <header class='head'>
          <div>
            <p class='kicker'>Purchase Requisition</p>
            <h1>{{@model.title}}</h1>
            <p class='sub'>{{@model.requester}} · {{@model.department}}</p>
          </div>
          <div class='head-right'>
            <StatePill
              @label={{this.statusLabel}}
              @hue={{this.statusHue}}
              @emphatic={{true}}
            />
            <Money class='total' @amount={{this.total}} @code='USD' />
            <span class='total-label'>estimated</span>
          </div>
        </header>

        <div class='grid'>
          <section class='panel span'>
            <h2>Requested Items</h2>
            <div class='lines'>
              {{#each @fields.lineItems as |Line|}}
                <Line />
              {{else}}
                <EmptyState
                  style={{COMPACT_EMPTY_STYLE}}
                  @texture={{false}}
                  @title='No items added yet'
                />
              {{/each}}
            </div>
          </section>

          <section class='panel'>
            <h2>Timeline</h2>
            <KeyValue class='facts' @items={{this.timeline}} />
          </section>

          <section class='panel'>
            <h2>Budget</h2>
            {{#if @model.budget}}
              <@fields.budget @format='atom' />
            {{else}}
              <EmptyState
                style={{COMPACT_EMPTY_STYLE}}
                @texture={{false}}
                @title='No budget linked'
              />
            {{/if}}
          </section>

          {{#if @model.justification}}
            <section class='panel span'>
              <h2>Justification</h2>
              <p class='just'>{{@model.justification}}</p>
            </section>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .pr {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
          margin-bottom: var(--boxel-sp-lg);
        }
        .kicker {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-size: 1.5rem;
          line-height: 1.2;
        }
        .sub {
          margin: 0;
          color: var(--muted-foreground);
        }
        .head-right {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: var(--boxel-sp-5xs);
        }
        .total {
          font-size: 1.25rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .total-label {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background: var(--card);
        }
        .panel.span {
          grid-column: 1 / -1;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI KeyValue at the panel's key and value sizes */
        .facts {
          --text-ui: 0.8125rem;
          --text-ui-md: 0.875rem;
        }
        .lines {
          display: grid;
          gap: var(--boxel-sp-5xs);
        }
        .just {
          margin: 0;
          font-size: 0.875rem;
          white-space: pre-wrap;
        }
        @container (max-width: 560px) {
          .grid {
            grid-template-columns: 1fr;
          }
          .head {
            flex-direction: column;
          }
          .head-right {
            align-items: flex-start;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'draft'] ?? 'slate';
    }
    get statusLabel() {
      return (
        REQUISITION_STATUS_LABELS[this.args.model?.status ?? ''] ?? 'Draft'
      );
    }
    get total() {
      return this.args.model?.estimatedTotal ?? 0;
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.title}}</span>
          <span class='meta'>{{@model.requester}}
            ·
            {{@model.department}}</span>
        </div>
        <Money class='amount' @amount={{this.total}} @code='USD' />
        <StatePill @label={{this.statusLabel}} @hue={{this.statusHue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .who {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .amount {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          min-width: 5.5rem;
          text-align: right;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.title}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'draft'] ?? 'slate';
    }
    get statusLabel() {
      return (
        REQUISITION_STATUS_LABELS[this.args.model?.status ?? ''] ?? 'Draft'
      );
    }
    get total() {
      return this.args.model?.estimatedTotal ?? 0;
    }
    get itemCount() {
      return (this.args.model?.lineItems ?? []).length;
    }
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.title}}</span>
        <span class='fit-sub'>{{@model.requester}}
          ·
          {{this.itemCount}}
          items</span>
        <div class='fit-foot'>
          <Money class='fit-total' @amount={{this.total}} @code='USD' />
          <StatePill
            class='fit-status'
            @label={{this.statusLabel}}
            @hue={{this.statusHue}}
          />
        </div>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-sub {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fit-foot {
          margin-top: auto;
          display: none;
          justify-content: space-between;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.8125rem;
        }
        .fit-total {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .fit-status {
          min-width: 0;
        }
        @container fitted-card (height > 110px) {
          .fit-foot {
            display: flex;
          }
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-sub {
            display: none;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
      </style>
    </template>
  };

  // Grouped by how a requisition is actually captured (who needs what by
  // when → the items themselves → why and against which budget), not by
  // schema order. Three sections — no nav rail needed.
  // estimatedTotal and title are computed (computeVia) and deliberately
  // excluded from the form.
  static edit = PurchaseRequisitionEdit;
}
