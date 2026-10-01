import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import UrlField from '@cardstack/base/url';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import ScrollTextIcon from '@cardstack/boxel-icons/scroll-text';
import HistoryIcon from '@cardstack/boxel-icons/history';
import FileTextIcon from '@cardstack/boxel-icons/file-text';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Contract } from './contract';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { tracked } from '@glimmer/tracking';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { EditSectionNav } from '../../components/edit-section-nav';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { COMPACT_EMPTY_STYLE, LegalFacts } from './legal-ui';

class ContractVersionEdit extends Component<typeof ContractVersion> {
  @tracked activeSection = 'snapshot';

  sections = [
    { id: 'snapshot', label: 'Snapshot' },
    { id: 'terms', label: 'Terms at this version' },
    { id: 'record', label: 'Record' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.cversion-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='cversion-edit'>
      {{! root is the container + only scroller; the responsive grid lives
          on this inner wrapper }}
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "snapshot") "focused"}}'
            data-sect='snapshot'
          >
            <h3>Snapshot
              <span class='sect-hint'>written by Execute Contract / Amend
                Contract — edit only to correct</span></h3>
            <FieldContainer @label='Contract' @vertical={{true}}>
              <@fields.contract />
            </FieldContainer>
            <div class='row cols-3'>
              <FieldContainer @label='Version' @vertical={{true}}>
                <@fields.versionNumber />
              </FieldContainer>
              <FieldContainer @label='Effective' @vertical={{true}}>
                <@fields.effectiveDate />
              </FieldContainer>
              <FieldContainer @label='Executed by' @vertical={{true}}>
                <@fields.executedBy />
              </FieldContainer>
            </div>
          </section>
          <section
            class='sect {{if (eq this.activeSection "terms") "focused"}}'
            data-sect='terms'
          >
            <h3>Terms at this version</h3>
            <div class='row cols-2'>
              <FieldContainer @label='Value' @vertical={{true}}>
                <@fields.valueAtVersion />
              </FieldContainer>
              <FieldContainer @label='End date' @vertical={{true}}>
                <@fields.endDateAtVersion />
              </FieldContainer>
            </div>
          </section>
          <section
            class='sect {{if (eq this.activeSection "record") "focused"}}'
            data-sect='record'
          >
            <h3>Record</h3>
            <FieldContainer
              @label='What changed in this version'
              @vertical={{true}}
            >
              <@fields.summary />
            </FieldContainer>
            <div class='row cols-2'>
              <FieldContainer @label='Executed copy URL' @vertical={{true}}>
                <@fields.documentUrl />
              </FieldContainer>
              <FieldContainer @label='Title as executed' @vertical={{true}}>
                <@fields.contractTitle />
                <p class='hint'>kept so the history reads even if the contract
                  is renamed</p>
              </FieldContainer>
            </div>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .cversion-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background-color: var(--background);
        color: var(--foreground);
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp);
      }
      /* root is the scroller, so sticky pins the rail; the legal family
         asserts no brand ink, so the rail keeps its default fg/bg pair */
      .sect-nav {
        position: sticky;
        top: 0;
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
        outline-color: var(--foreground);
        box-shadow: 0 0 0 0.25rem
          color-mix(in oklch, var(--foreground) 12%, transparent);
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
        font-size: 0.75rem;
        font-weight: 400;
        font-style: italic;
      }
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

/**
 * CONTRACT VERSION — an amendment record, so "version history" is a history
 * rather than a lineage.
 *
 * WHAT WAS THERE BEFORE. `Contract.parentContract` gives the chain from an
 * amendment back to its master, which answers "what is this an amendment TO".
 * It does not answer "what CHANGED, when, and who signed it" — and that second
 * question is the one an auditor and a renewal reviewer both actually ask.
 *
 * WHY THE CHANGED VALUES ARE STORED, not derived. Reading the current contract
 * tells you where things ended up; it cannot tell you what the value was before
 * amendment 2, because the contract has since been edited. A version record
 * that recomputed from the live card would show today's numbers on every row
 * and quietly claim nothing ever changed.
 */
export class ContractVersion extends CardDef {
  static displayName = 'Contract Version';
  static icon = ScrollTextIcon;

  /** A real link, so a reader can open the contract this version belongs to. */
  @field contract = linksTo(() => Contract);

  /** The title as at this version — a snapshot, not a read-through. */
  @field contractTitle = contains(StringField);

  @field versionNumber = contains(NumberField);
  @field effectiveDate = contains(DateField);
  @field executedBy = linksTo(() => Employee);
  @field documentUrl = contains(UrlField);

  /** What this version changed, in the drafter's words. */
  @field summary = contains(TextAreaField);

  /** Values AS AT this version — snapshots, never recomputed. */
  @field valueAtVersion = contains(AmountWithCurrency);
  @field endDateAtVersion = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ContractVersion) {
      let n = this.versionNumber;
      let label = n === 1 ? 'Original' : `Amendment ${(n ?? 1) - 1}`;
      return this.contractTitle ? `${this.contractTitle} — ${label}` : label;
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: ContractVersion) {
      return this.summary ?? '';
    },
  });

  /**
   * The domain question: "what did this version change, and what were the
   * numbers at the time?"
   *
   * The value AS AT this version is the hero, because it is the figure a reader
   * came for and the one they cannot get from the live contract — the contract
   * has since been edited and only shows today.
   */
  /**
   * Edit — an append-only snapshot of a contract at execution.
   * Grouped by task, not schema order; EditSectionNav is the table of
   * contents.
   */
  static edit = ContractVersionEdit;

  static isolated = class Isolated extends Component<typeof ContractVersion> {
    get money(): string {
      return (
        formatMoney(
          this.args.model?.valueAtVersion?.amount,
          this.args.model?.valueAtVersion?.currency?.code,
        ) || '—'
      );
    }
    get isOriginal() {
      return (this.args.model?.versionNumber ?? 1) === 1;
    }
    get glanceFacts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Effective', value: formatDay(m?.effectiveDate) },
        { key: 'Term ends', value: formatDay(m?.endDateAtVersion) },
        { key: 'Executed by', value: m?.executedBy?.cardTitle ?? '—' },
      ];
    }
    <template>
      <article class='cv-page'>
        <header class='hero'>
          <div class='hero-id'>
            <p class='kicker'><ScrollTextIcon role='presentation' />Contract
              version</p>
            <h1>{{@model.cardTitle}}</h1>
            <div class='hero-pills'>
              <StatePill
                @label='v{{if @model.versionNumber @model.versionNumber 1}}'
                @hue='blue'
              />
              {{#if this.isOriginal}}
                <StatePill @label='Original' @hue='slate' />
              {{else}}
                <StatePill @label='Amendment' @hue='purple' />
              {{/if}}
            </div>
          </div>
          <Stat
            class='hero-figure'
            @label='Value at this version'
            @value={{this.money}}
            @roll={{false}}
          />
        </header>

        <LegalFacts @items={{this.glanceFacts}} />

        <section class='panel'>
          <h2><HistoryIcon role='presentation' />What changed</h2>
          {{#if @model.summary}}
            <p class='prose'>{{@model.summary}}</p>
          {{else}}
            <EmptyState
              @title='No summary recorded'
              @message='A version with no stated change is a date and a number — the next reader has to diff it by eye.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </section>

        {{#if @model.documentUrl}}
          <section class='panel'>
            <h2><FileTextIcon role='presentation' />Executed copy</h2>
            <a
              class='doc'
              href={{@model.documentUrl}}
              target='_blank'
              rel='noopener noreferrer'
            >Open the signed document</a>
          </section>
        {{/if}}

        <p class='caveat'>These values are snapshots taken when the version was
          recorded, not readings from the live contract. That is the point: the
          contract shows today, and this shows what was agreed then.</p>
      </article>

      <style scoped>
        .cv-page {
          container-type: inline-size;
          container-name: cv-page;
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .hero {
          display: flex;
          align-items: flex-start;
          justify-content: space-between;
          gap: var(--boxel-sp-lg);
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: var(--boxel-sp);
        }
        .hero-id {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          min-width: 0;
        }
        .hero-pills {
          display: flex;
          flex-wrap: wrap;
          gap: 0.375rem;
        }
        .kicker {
          margin: 0;
          display: flex;
          align-items: center;
          gap: 0.375rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kicker :deep(svg) {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
        }
        /* The heading is the one shout. The figure on the right supports it
           and is deliberately smaller — a card is opened for the thing it IS,
           and the number qualifies that rather than replacing it. */
        .hero h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
          letter-spacing: -0.015em;
        }
        /* Money keeps its minor units and never wraps — a truncated amount on a
           version record is unusable evidence. */
        .hero-figure {
          flex: 0 1 auto;
          min-width: 0;
          white-space: nowrap;
        }
        .panel {
          padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          border-radius: var(--radius);
          background-color: var(--panel-bg);
        }
        .panel h2 {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
        }
        .panel h2 :deep(svg) {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
          color: var(--muted-foreground);
        }
        .prose {
          margin: 0;
          font-family: var(--font-serif);
          font-size: var(--boxel-font-size);
          line-height: 1.6;
          max-width: 68ch;
        }
        .caveat {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
          color: var(--muted-foreground);
          max-width: 68ch;
        }
        .caveat {
          font-size: var(--boxel-font-size-xs);
        }
        .doc {
          font-size: var(--boxel-font-size-sm);
        }
        @container cv-page (width < 560px) {
          .hero {
            flex-direction: column;
            align-items: flex-start;
            gap: var(--boxel-sp);
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ContractVersion> {
    get money(): string {
      return formatMoney(
        this.args.model?.valueAtVersion?.amount,
        this.args.model?.valueAtVersion?.currency?.code,
      );
    }
    <template>
      <article class='fit'>
        <span class='r-head'>
          <StatePill
            @label='v{{if @model.versionNumber @model.versionNumber 1}}'
            @hue='blue'
          />
        </span>
        <span class='r-body'>{{if
            @model.summary
            @model.summary
            'No summary recorded'
          }}</span>
        {{#if this.money}}<span class='r-meta'>{{this.money}}</span>{{/if}}
      </article>

      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: 0.125rem;
          padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
          overflow: hidden;
          --type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb), 10cqb),
            0.9375rem
          );
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-body {
          font-size: calc(var(--type-base) * 1.1);
          font-weight: 600;
          line-height: 1.25;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }
        /* Money never ellipsises — a truncated amount is not an amount. */
        .r-meta {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-size: var(--type-base);
          white-space: nowrap;
          color: var(--muted-foreground);
        }
        @container fitted-card (height <= 65px) {
          .r-meta {
            display: none;
          }
        }
        @container fitted-card (height <= 45px) {
          .r-head {
            display: none;
          }
        }
      </style>
    </template>
  };
}
