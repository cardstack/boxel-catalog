import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import MarkdownField from '@cardstack/base/markdown';
import enumField from '@cardstack/base/enum';

import { Contract } from './contract';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import FilePlusIcon from '@cardstack/boxel-icons/file-plus';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';

export const MOD_DOC_STATUSES = ['draft', 'executed'];

export const ModDocStatusField = markDefinition(
  enumField(StringField, {
    options: MOD_DOC_STATUSES.map((value) => ({ value, label: value })),
    displayName: 'Modification Document Status',
  }),
);

// An addendum ADDS terms to an executed contract without altering what was
// already agreed — new scope, an extra schedule, an additional service.
// Contrast with Amendment (changes existing terms) and a waiver (excuses one
// obligation without changing the text). Keeping the three as distinct
// cards is the domain distinction itself.
export class Addendum extends CardDef {
  static displayName = 'Addendum';

  @field contract = linksTo(() => Contract);
  @field name = contains(StringField);
  @field effectiveDate = contains(DateField);
  @field addedTerms = contains(MarkdownField);
  @field status = contains(ModDocStatusField);
  @field executedOn = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Addendum) {
      return this.name?.trim()?.length ? this.name : 'Untitled Addendum';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get effectiveLabel() {
      let d = this.args.model?.effectiveDate;
      return d
        ? d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          })
        : '—';
    }
    <template>
      <IsoFrame>
        <article class='doc'>
          <header class='head'>
            <div>
              <p class='kicker'>Addendum</p>
              <h1>{{@model.name}}</h1>
              <p class='sub'>effective {{this.effectiveLabel}}</p>
            </div>
            <StatePill
              @label={{if (eqStr @model.status 'executed') 'EXECUTED' 'DRAFT'}}
              @hue={{if (eqStr @model.status 'executed') 'green' 'slate'}}
              @emphatic={{true}}
            />
          </header>
          {{#if @model.contract}}
            <section class='panel'>
              <h2>Supplements Contract</h2>
              <@fields.contract @format='atom' />
            </section>
          {{/if}}
          <section class='panel'>
            <h2>Added Terms</h2>
            {{#if @model.addedTerms}}
              <@fields.addedTerms />
            {{else}}
              <p class='empty'>No terms drafted yet.</p>
            {{/if}}
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .doc {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
          padding-bottom: var(--boxel-sp);
        }
        .kicker {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: 0.5625rem; /* 9px ladder label: no token */
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-size: var(--boxel-font-size-lg);
        }
        .sub {
          color: var(--muted-foreground);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp);
          background-color: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: 0.5625rem; /* 9px ladder label: no token */
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .empty {
          font-style: italic;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  /**
   * Fitted — attribute-only (prerendered fitted does not resolve links),
   * on RichFittedCard like the rest of the legal family.
   */
  static fitted = class Fitted extends Component<typeof Addendum> {
    get hue() {
      return this.args.model?.status === 'executed'
        ? ('green' as const)
        : ('slate' as const);
    }
    <template>
      <RichFittedCard>
        <:avatar><FilePlusIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status><StatePill
            @label={{if @model.status @model.status 'draft'}}
            @hue={{this.hue}}
          /></:status>
        <:subtitle>{{@model.addedTerms}}</:subtitle>
        <:details>
          {{#if @model.effectiveDate}}<Detail
              @label='Effective'
              @value={{formatDay @model.effectiveDate}}
            />{{/if}}
          {{#if @model.executedOn}}<Detail
              @label='Executed'
              @value={{formatDay @model.executedOn}}
            />{{/if}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='name'>{{@model.name}}</span>
        <StatePill
          @label={{if (eqStr @model.status 'executed') 'executed' 'draft'}}
          @hue={{if (eqStr @model.status 'executed') 'green' 'slate'}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.name}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

function eqStr(a?: string | null, b?: string | null) {
  return a === b;
}
