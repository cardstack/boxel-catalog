import { Component, field, contains } from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';

import {
  Clause,
  CLAUSE_EDIT_SECTIONS,
  ClauseEditSections,
} from '@cardstack/catalog/cards/legal/clause';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

// A confidentiality (NDA) clause as a typed library entry. Extends the
// shared Clause additively — the base card owns text, risk, and review
// bookkeeping; this subclass adds the terms a lawyer actually compares NDAs
// by: how long, whether it binds both parties, what falls outside it, and
// whether the duty outlives the contract. Instances should set the base
// `clauseType` to `confidentiality` so type-driven views group them.
export class ConfidentialityClause extends Clause {
  static displayName = 'Confidentiality Clause';

  @field termYears = contains(NumberField, {
    description: 'How many years the duty runs; 0 = perpetual',
  });
  @field isMutual = contains(BooleanField, {
    description: 'Binds both parties, not just the receiving one',
  });
  @field survivesTermination = contains(BooleanField);
  @field carveOuts = contains(MarkdownField, {
    description:
      'What is NOT confidential: public knowledge, independently developed, legally compelled…',
  });

  /**
   * Edit — a Clause plus the typed confidentiality terms.
   * Grouped by task, not schema order; SectionedEdit gives it the
   * section rail.
   */
  static edit = class Edit extends Component<typeof this> {
    sections = [
      ...CLAUSE_EDIT_SECTIONS,
      { id: 'confidentiality', label: 'Confidentiality terms' },
    ];

    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Confidentiality Clause sections'
        as |e|
      >
        <ClauseEditSections @section={{e.Section}} @fields={{@fields}} />
        <e.Section
          @id='confidentiality'
          @title='Confidentiality terms'
          @hint='the typed fields the Navigator and Generate Document read'
        >
          <div class='row cols-3'>
            <FieldContainer @label='Term (years)' @vertical={{true}}>
              <@fields.termYears />
            </FieldContainer>
            <FieldContainer @label='Mutual' @vertical={{true}}>
              <@fields.isMutual />
            </FieldContainer>
            <FieldContainer @label='Survives termination' @vertical={{true}}>
              <@fields.survivesTermination />
            </FieldContainer>
          </div>
          <FieldContainer @label='Carve-outs' @vertical={{true}}>
            <@fields.carveOuts />
          </FieldContainer>
        </e.Section>
      </SectionedEdit>
      <style scoped>
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
    get termLabel() {
      let y = this.args.model?.termYears;
      if (y == null) {
        return 'term unset';
      }
      return y === 0 ? 'perpetual' : `${y}-year term`;
    }
    <template>
      <div class='row'>
        <div class='who'>
          <span class='name'>{{@model.name}}</span>
          <span class='meta'>{{this.termLabel}}
            ·
            {{if @model.isMutual 'mutual' 'one-way'}}
            {{if @model.survivesTermination '· survives termination'}}</span>
        </div>
        <StatePill @label='confidentiality' @hue='blue' @chrome={{true}} />
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
        }
      </style>
    </template>
  };
}
