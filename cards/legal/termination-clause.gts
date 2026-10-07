import {
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';

import { Clause } from '@cardstack/catalog/cards/legal/clause';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

// A termination clause as a typed library entry. Extends the shared Clause
// additively with the exit mechanics a reviewer compares: notice period,
// whether either party can leave without cause ("for convenience"), how
// long a breaching party has to cure, and any early-exit fee. Instances
// should set the base `clauseType` to `termination`.
export class TerminationClause extends Clause {
  static displayName = 'Termination Clause';

  @field noticeDays = contains(NumberField, {
    description: 'Days of written notice required',
  });
  @field forConvenience = contains(BooleanField, {
    description: 'Either party may terminate without cause',
  });
  @field curePeriodDays = contains(NumberField, {
    description: 'Days a breaching party has to fix the breach',
  });
  @field earlyExitFeeText = contains(StringField, {
    description: 'e.g. "3 months of remaining fees", "none"',
  });

  /**
   * Edit — a Clause plus the typed termination terms.
   * Grouped by task, not schema order; SectionedEdit gives it the
   * section rail.
   */
  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'text', label: 'Approved text' },
      { id: 'guidance', label: 'Guidance & review' },
      { id: 'termination', label: 'Termination terms' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Termination Clause sections'
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
        <e.Section @id='termination' @title='Termination terms'>
          <div class='row cols-3'>
            <FieldContainer @label='Notice (days)' @vertical={{true}}>
              <@fields.noticeDays />
            </FieldContainer>
            <FieldContainer @label='For convenience' @vertical={{true}}>
              <@fields.forConvenience />
            </FieldContainer>
            <FieldContainer @label='Cure period (days)' @vertical={{true}}>
              <@fields.curePeriodDays />
            </FieldContainer>
          </div>
          <FieldContainer @label='Early exit fee' @vertical={{true}}>
            <@fields.earlyExitFeeText />
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
      let notice = this.args.model?.noticeDays;
      if (notice != null) {
        parts.push(`${notice}-day notice`);
      }
      if (this.args.model?.forConvenience) {
        parts.push('for convenience');
      }
      let cure = this.args.model?.curePeriodDays;
      if (cure != null) {
        parts.push(`${cure}-day cure`);
      }
      return parts.join(' · ') || 'terms unset';
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.name}}</span>
          <span class='meta'>{{this.termsLabel}}</span>
        </div>
        <StatePill @label='termination' @hue='red' @chrome={{true}} />
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
