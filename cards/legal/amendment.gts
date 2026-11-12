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
import MarkdownField from '@cardstack/base/markdown';

import { Contract } from './contract';
import { ModDocStatusField } from './addendum';
import { ClauseReferenceField } from './clause-reference-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import FileDiffIcon from '@cardstack/boxel-icons/file-diff';

// An amendment CHANGES existing terms of an executed contract — a new
// price, a moved end date, a rewritten section. Numbered per contract so
// "as amended by Amendment No. 2" resolves unambiguously; the sibling
// ContractVersion card snapshots the contract's state at each execution
// (Amend Contract writes both). Contrast with Addendum (adds terms)
// and a waiver (excuses one obligation without changing text).
export class Amendment extends CardDef {
  static displayName = 'Amendment';

  @field contract = linksTo(() => Contract);
  @field amendmentNumber = contains(NumberField);
  @field effectiveDate = contains(DateField);
  @field changesSummary = contains(TextAreaField, {
    description: 'One paragraph a reviewer reads before the redline',
  });
  @field changedTerms = contains(MarkdownField, {
    description: 'The amended text itself',
  });
  @field status = contains(ModDocStatusField);
  /**
   * Which library clauses this amendment touches, each pinned to the revision
   * that was in force when the amendment was drafted.
   * The prose in `changedTerms` says WHAT changed; this says WHERE, in a form
   * the clause library can be queried on.
   */
  @field changedClauses = containsMany(ClauseReferenceField);
  @field executedOn = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Amendment) {
      let n = this.amendmentNumber;
      let base = n != null ? `Amendment No. ${n}` : 'Amendment';
      let contractName = this.contract?.title?.trim();
      return contractName ? `${base} — ${contractName}` : base;
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
    get executed() {
      return this.args.model?.status === 'executed';
    }
    <template>
      <article class='doc'>
        <header class='head'>
          <div>
            <p class='kicker'>Amendment</p>
            <h1>{{@model.cardTitle}}</h1>
            <p class='sub'>effective {{this.effectiveLabel}}</p>
          </div>
          <StatePill
            @label={{if this.executed 'EXECUTED' 'DRAFT'}}
            @hue={{if this.executed 'green' 'slate'}}
            @emphatic={{true}}
          />
        </header>
        {{#if @model.contract}}
          <section class='panel'>
            <h2>Amends Contract</h2>
            <@fields.contract @format='atom' />
          </section>
        {{/if}}
        {{#if @model.changesSummary}}
          <section class='panel'>
            <h2>Summary of Changes</h2>
            <p class='summary'>{{@model.changesSummary}}</p>
          </section>
        {{/if}}
        {{#if @model.changedClauses.length}}
          <section class='panel'>
            <h2>Clauses Affected</h2>
            <ul class='clause-refs'>
              {{#each @fields.changedClauses as |Ref|}}
                <li><Ref @format='embedded' /></li>
              {{/each}}
            </ul>
          </section>
        {{/if}}
        <section class='panel'>
          <h2>Amended Terms</h2>
          {{#if @model.changedTerms}}
            <@fields.changedTerms />
          {{else}}
            <p class='empty'>No amended text drafted yet.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .clause-refs {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-sm);
        }
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
        .summary,
        .empty {
          font-size: var(--boxel-font-size-sm);
          white-space: pre-wrap;
        }
        .empty {
          font-style: italic;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  /**
   * Fitted — attribute-only (prerendered fitted does not resolve links);
   * the Clause fitted's skeleton, so the legal family reads as one set.
   */
  static fitted = class Fitted extends Component<typeof Amendment> {
    get hue() {
      return this.args.model?.status === 'executed'
        ? ('green' as const)
        : ('slate' as const);
    }
    <template>
      <article class='fit'>
        <header class='r-head'>
          <FileDiffIcon role='presentation' />
          <span class='eyebrow'>Amendment{{#if @model.amendmentNumber}}
              No.
              {{@model.amendmentNumber}}{{/if}}</span>
          <span class='head-chip'><StatePill
              @label={{if @model.status @model.status 'draft'}}
              @hue={{this.hue}}
            /></span>
        </header>
        <div class='r-body'>
          <h3 class='anchor'>{{@model.cardTitle}}</h3>
          <p class='sub'>{{@model.changesSummary}}</p>
        </div>
        <footer class='r-meta'><span>{{#if @model.effectiveDate}}effective
              {{formatDay @model.effectiveDate}}{{/if}}</span><span
            class='val tail'
          >{{#if @model.executedOn}}executed
              {{formatDay @model.executedOn}}{{/if}}</span></footer>
      </article>
      <style scoped>
        .fit {
          --_fit-type-ratio: 1.24;
          --_fit-ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          --_fit-type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb - 0.6 * var(--_fit-ar)), 10cqb),
            1.0625rem
          );
          --_fit-meta-size: max(
            0.625rem,
            calc(var(--_fit-type-base) / var(--_fit-type-ratio))
          );
          --_fit-anchor-size: max(
            0.6875rem,
            min(
              calc(
                var(--_fit-type-base) * var(--_fit-type-ratio) *
                  var(--_fit-type-ratio)
              ),
              26cqb
            )
          );
          --_fit-glyph: max(0.6875rem, min(3cqi, 14cqb));
          --_fit-pad: clamp(0.375rem, calc(0.125rem + 1.7cqi), 0.875rem);
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: var(--boxel-sp-6xs);
          padding: var(--_fit-pad);
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
          gap: var(--boxel-sp-2xs);
        }
        .r-head > svg {
          width: var(--_fit-glyph);
          height: var(--_fit-glyph);
          flex: none;
          color: var(--accent);
        }
        .eyebrow {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: max(
            var(--boxel-eyebrow-font-size),
            calc(var(--_fit-meta-size) * 0.85)
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
          gap: var(--boxel-sp-6xs);
        }
        .anchor {
          font-size: var(--_fit-anchor-size);
          font-weight: 700;
          line-height: 1.18;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .sub {
          font-size: var(--_fit-meta-size);
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
          gap: var(--boxel-sp-2xs);
          font-size: var(--_fit-meta-size);
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
    get executed() {
      return this.args.model?.status === 'executed';
    }
    <template>
      <div class='row'>
        <span class='name'>{{@model.cardTitle}}</span>
        <StatePill
          @label={{if this.executed 'executed' 'draft'}}
          @hue={{if this.executed 'green' 'slate'}}
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}
