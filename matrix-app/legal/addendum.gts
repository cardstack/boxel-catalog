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
  static headerColor = '#41337a';

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
      <style scoped>
        .doc {
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
        }
        .sub {
          margin: 0;
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
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .empty {
          margin: 0;
          font-style: italic;
          color: var(--muted-foreground);
          font-size: 0.875rem;
        }
      </style>
    </template>
  };

  /**
   * Fitted — attribute-only (prerendered fitted does not resolve links);
   * the Clause fitted's skeleton, so the legal family reads as one set.
   */
  static fitted = class Fitted extends Component<typeof Addendum> {
    get hue() {
      return this.args.model?.status === 'executed'
        ? ('green' as const)
        : ('slate' as const);
    }
    <template>
      <article class='fit'>
        <header class='r-head'>
          <FilePlusIcon role='presentation' />
          <span class='eyebrow'>Addendum</span>
          <span class='head-chip'><StatePill
              @label={{if @model.status @model.status 'draft'}}
              @hue={{this.hue}}
            /></span>
        </header>
        <div class='r-body'>
          <h3 class='anchor'>{{@model.cardTitle}}</h3>
          <p class='sub'>{{@model.addedTerms}}</p>
        </div>
        <footer class='r-meta'><span>{{#if @model.effectiveDate}}effective
              {{formatDay @model.effectiveDate}}{{/if}}</span><span
            class='val tail'
          >{{#if @model.executedOn}}executed
              {{formatDay @model.executedOn}}{{/if}}</span></footer>
      </article>
      <style scoped>
        .fit {
          --type-ratio: 1.24;
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb - 0.6 * var(--ar)), 10cqb),
            1.0625rem
          );
          --meta-size: max(
            0.625rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --anchor-size: max(
            0.6875rem,
            min(
              calc(var(--type-base) * var(--type-ratio) * var(--type-ratio)),
              26cqb
            )
          );
          --glyph: max(0.6875rem, min(3cqi, 14cqb));
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
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          display: flex;
          align-items: center;
          gap: 0.375rem;
        }
        .r-head > svg {
          width: var(--glyph);
          height: var(--glyph);
          flex: none;
          color: var(--accent);
        }
        .eyebrow {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: max(
            var(--boxel-eyebrow-font-size),
            calc(var(--meta-size) * 0.85)
          );
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .head-chip {
          margin-left: auto;
          flex: none;
        }
        .r-body {
          display: grid;
          align-content: start;
          gap: 0.125rem;
        }
        .anchor {
          margin: 0;
          font-size: var(--anchor-size);
          font-weight: 700;
          line-height: 1.18;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .sub {
          margin: 0;
          font-size: var(--meta-size);
          line-height: 1.3;
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .r-meta {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-size: var(--meta-size);
          line-height: 1.3;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .val {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-weight: 600;
          color: var(--card-foreground);
        }
        .tail {
          margin-left: auto;
        }
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: auto;
          }
          .r-body,
          .r-meta {
            display: none;
          }
        }
        @container fitted-card (50px < height <= 80px) {
          .fit {
            grid-template-rows: auto minmax(0, 1fr);
          }
          .sub,
          .r-meta {
            display: none;
          }
        }
        @container fitted-card (80px < height <= 130px) {
          .sub,
          .tail {
            display: none;
          }
        }
        @container fitted-card (width <= 150px) {
          .head-chip,
          .tail {
            display: none;
          }
        }
        @container fitted-card (width <= 110px) {
          .eyebrow {
            display: none;
          }
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
          font-size: 0.9375rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.name}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };
}

function eqStr(a?: string | null, b?: string | null) {
  return a === b;
}
