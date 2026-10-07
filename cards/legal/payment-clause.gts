import {
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';

import { Clause } from '@cardstack/catalog/cards/legal/clause';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

// A payment-terms clause as a typed library entry. Extends the shared
// Clause additively with the numbers a finance reviewer scans for: net
// days, late-fee rate, and any early-payment discount. Instances should set
// the base `clauseType` to `payment` so type-driven views group them.
export class PaymentClause extends Clause {
  static displayName = 'Payment Clause';

  @field netDays = contains(NumberField, {
    description: 'Days to pay after invoice, e.g. 30 for Net-30',
  });
  @field lateFeePercent = contains(NumberField, {
    description: 'Monthly late fee on overdue balance, e.g. 1.5',
  });
  @field earlyPaymentDiscountPercent = contains(NumberField);
  @field earlyPaymentWindowDays = contains(NumberField);
  @field acceptedMethods = contains(StringField, {
    description: 'e.g. ACH, wire, credit card',
  });

  /**
   * Edit — a Clause plus the typed payment terms.
   * Grouped by task, not schema order; SectionedEdit gives it the
   * section rail.
   */
  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'text', label: 'Approved text' },
      { id: 'guidance', label: 'Guidance & review' },
      { id: 'payment', label: 'Payment terms' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Payment Clause sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity'>
          <FieldContainer @label='Clause name' @vertical={{true}}>
            <@fields.name />
          </FieldContainer>
          <div class='row cols-3'>
            <FieldContainer @label='Type' @vertical={{true}}>
              <@fields.clauseType />
            </FieldContainer>
            <FieldContainer
              @label='Risk when used as written'
              @vertical={{true}}
            >
              <@fields.riskLevel />
            </FieldContainer>
            <FieldContainer
              @label='Owner role (who may edit)'
              @vertical={{true}}
            >
              <@fields.ownerRole />
            </FieldContainer>
          </div>
        </e.Section>
        <e.Section
          @id='text'
          @title='Approved text'
          @hint='the wording every ContractClause is measured against'
        >
          <FieldContainer @label='Standard text' @vertical={{true}}>
            <@fields.standardText />
          </FieldContainer>
        </e.Section>
        <e.Section @id='guidance' @title='Guidance & review'>
          <FieldContainer
            @label='When to use it, what must never be conceded without sign-off'
            @vertical={{true}}
          >
            <@fields.guidance />
          </FieldContainer>
          <FieldContainer @label='Last reviewed' @vertical={{true}}>
            <@fields.reviewedAt />
            <p class='hint'>approved language goes stale — Clause References pin
              to this date</p>
          </FieldContainer>
        </e.Section>
        <e.Section @id='payment' @title='Payment terms'>
          <div class='row cols-2'>
            <FieldContainer @label='Net (days)' @vertical={{true}}>
              <@fields.netDays />
            </FieldContainer>
            <FieldContainer @label='Late fee %' @vertical={{true}}>
              <@fields.lateFeePercent />
            </FieldContainer>
          </div>
          <div class='row cols-2'>
            <FieldContainer
              @label='Early-payment discount %'
              @vertical={{true}}
            >
              <@fields.earlyPaymentDiscountPercent />
            </FieldContainer>
            <FieldContainer
              @label='Early-payment window (days)'
              @vertical={{true}}
            >
              <@fields.earlyPaymentWindowDays />
            </FieldContainer>
          </div>
          <FieldContainer @label='Accepted methods' @vertical={{true}}>
            <@fields.acceptedMethods />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
        .hint {
          margin: 0.25rem 0 0;
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .row {
          display: grid;
          gap: var(--boxel-sp-sm);
          align-items: start;
        }
        .row.cols-2 {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .row.cols-3 {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        .row.cols-4 {
          grid-template-columns: repeat(4, minmax(0, 1fr));
        }
        @container edit (width < 640px) {
          .row.cols-2,
          .row.cols-3,
          .row.cols-4 {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get termsLabel() {
      let parts: string[] = [];
      let net = this.args.model?.netDays;
      if (net != null) {
        parts.push(`Net-${net}`);
      }
      let late = this.args.model?.lateFeePercent;
      if (late) {
        parts.push(`${late}%/mo late fee`);
      }
      let disc = this.args.model?.earlyPaymentDiscountPercent;
      let window = this.args.model?.earlyPaymentWindowDays;
      if (disc && window) {
        parts.push(`${disc}/${window} discount`);
      }
      return parts.join(' · ') || 'terms unset';
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.name}}</span>
          <span class='meta'>{{this.termsLabel}}</span>
        </div>
        <StatePill @label='payment' @hue='green' @chrome={{true}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .who {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
        }
        .meta {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
