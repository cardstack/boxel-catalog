import {
  CardDef,
  field,
  contains,
  linksTo,
  Component,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import HistoryIcon from '@cardstack/boxel-icons/history';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { KeyValue } from '@cardstack/pretui/components/key-value';

import { StatePill } from '@cardstack/catalog/components/state-pill';

/**
 * AUDIT ENTRY — the append-only record of what happened to a contract.
 *
 * WHY THIS IS ITS OWN CARD, not a field on Contract.
 * An audit trail's whole value is that it cannot be rewritten by the thing it
 * describes. A `containsMany` on Contract would be edited in the same save as
 * the contract itself, so "who approved this and when" would be as mutable as
 * the contract body — which is exactly the claim an auditor is trying to test.
 * A separate card with its own id gives each event a stable address that
 * survives edits to the contract.
 *
 * WHAT IS CONSUMED. `Employee` for the actor, `StatePill` for the action chip.
 * No new vocabulary is invented for either.
 *
 * WHAT IS NOT MODELLED. Nothing enforces append-only at the platform level —
 * the realm has no immutable-record primitive — so this is a convention the app
 * honours rather than a guarantee the storage makes. Said plainly here because
 * an audit trail that is only conventionally immutable must not be described as
 * if it were tamper-proof.
 */

// The vocabulary itself lives in utils/audit-action-vocabulary so components
// can read labels and hues without importing this card. Re-exported here:
// every existing importer of these names is unaffected.
export {
  AUDIT_ACTIONS,
  auditActionLabel,
  auditActionHue,
} from './utils/audit-action-vocabulary';
import {
  AUDIT_ACTIONS,
  auditActionLabel,
  auditActionHue,
} from './utils/audit-action-vocabulary';

/**
 * A closed vocabulary, not free text.
 *
 * An audit trail whose action column accepts anything cannot be filtered,
 * charted or trusted — one entry saying "approved" and another "Approved!!"
 * are the same event to a person and two different events to a query.
 */
export const AuditActionField = enumField(StringField, {
  options: AUDIT_ACTIONS.map((a) => ({ value: a.value, label: a.label })),
  displayName: 'Audit Action',
  icon: HistoryIcon,
});

export class AuditEntry extends CardDef {
  static displayName = 'Audit Entry';
  static icon = HistoryIcon;

  @field action = contains(AuditActionField);
  /**
   * Who did the thing.
   *
   * Named `doneBy` rather than `actor`: the edit form takes its label straight
   * from the field name, and "Actor" is a system word that made a reader ask
   * what it meant. "Done by" works for every action in the vocabulary —
   * created, approved, signed, amended, terminated.
   */
  @field doneBy = linksTo(() => Employee);
  @field occurredAt = contains(DateTimeField);

  /**
   * What the entry is about — a real link, not a stored id.
   *
   * An id string cannot be navigated to, cannot be queried with
   * `{ eq: { 'subject.id': ... } }`, and gives the reader no way to open the
   * thing being audited. The earlier version stored one to keep the entry
   * readable after the contract is deleted; a broken link renders as a broken
   * link and the snapshot below preserves what it was called, so that argument
   * bought nothing that `subjectTitle` was not already buying.
   *
   * Typed CardDef, not Contract: an audit trail is raised over whatever was
   * audited — a contract, a vendor profile, a site, a Spec — and a link typed
   * to one domain card would leave every other subject unlinkable.
   */
  @field subject = linksTo(CardDef);

  /**
   * The subject's title AS AT the moment of the entry.
   *
   * Deliberately denormalised. Reading through the link would show today's
   * title, and an audit trail is supposed to say what the thing was called
   * when the decision was made.
   */
  @field subjectTitle = contains(StringField);

  /** The reason given at the time. Never back-filled. */
  @field note = contains(TextAreaField);

  /** Set when the action was `approved_with_conditions`. */
  @field conditions = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditEntry) {
      let who = this.doneBy?.cardTitle ?? 'Someone';
      return `${who} — ${auditActionLabel(this.action)}`;
    },
  });

  @field cardDescription = contains(StringField, {
    computeVia: function (this: AuditEntry) {
      return this.subjectTitle ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof AuditEntry> {
    get glance() {
      let m = this.args.model;
      return [
        { key: 'Done by', value: m?.doneBy?.cardTitle ?? '—' },
        { key: 'When', value: 'when' },
        { key: 'Subject', value: m?.subjectTitle || '—' },
      ];
    }
    <template>
      <article class='ae-page'>
        <header class='hero'>
          <p class='kicker'><HistoryIcon role='presentation' />Audit entry</p>
          <h1>{{auditActionLabel @model.action}}</h1>
          <StatePill
            @label={{auditActionLabel @model.action}}
            @hue={{auditActionHue @model.action}}
            @dot={{true}}
          />
        </header>

        <KeyValue
          class='glance'
          @items={{this.glance}}
          @layout='inline'
          @labelStyle='eyebrow'
        >
          <:value as |item|>
            {{#if (eq item.key 'When')}}
              <FormatDate
                @date={{@model.occurredAt}}
                @dateStyle='medium'
                @timeStyle='short'
                @placeholder='Time not recorded'
              />
            {{else}}
              {{item.value}}
            {{/if}}
          </:value>
        </KeyValue>

        {{#if @model.conditions}}
          <section class='panel'>
            <h2>Conditions attached</h2>
            <p>{{@model.conditions}}</p>
          </section>
        {{/if}}

        {{#if @model.note}}
          <section class='panel'>
            <h2>Reason given</h2>
            <p>{{@model.note}}</p>
          </section>
        {{/if}}

        <p class='caveat'>Entries are written once and never edited. Nothing in
          the platform enforces that — it is a convention this app keeps, not a
          guarantee the storage makes.</p>
      </article>

      <style scoped>
        .ae-page {
          container-type: inline-size;
          container-name: ae-page;
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .hero {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
          align-items: flex-start;
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp);
        }
        .kicker {
          margin: 0;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
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
        .hero h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          letter-spacing: -0.015em;
        }
        .glance {
          gap: var(--boxel-sp-xs) var(--boxel-sp-lg);
        }
        .panel {
          padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          border-radius: var(--radius);
          background: var(--panel-bg);
        }
        .panel h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          letter-spacing: 0.04em;
          text-transform: uppercase;
        }
        .panel p {
          margin: 0;
          line-height: 1.55;
        }
        .caveat {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          line-height: 1.5;
          color: var(--muted-foreground);
          max-width: 68ch;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof AuditEntry> {
    <template>
      <article class='fit'>
        <span class='r-head'>
          <StatePill
            @label={{auditActionLabel @model.action}}
            @hue={{auditActionHue @model.action}}
            @dot={{true}}
          />
        </span>
        <span class='r-body'>{{if
            @model.doneBy
            @model.doneBy.cardTitle
            'Not recorded'
          }}</span>
        <span class='r-meta'>{{if
            @model.subjectTitle
            @model.subjectTitle
            ''
          }}</span>
      </article>

      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          gap: 0.125rem;
          padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
          overflow: hidden;
          font-family: var(--font-sans);
          --type-base: clamp(
            10px,
            min(calc(3px + 2.1cqi + 1cqb - 0.6 * var(--ar, 1)), 10cqb),
            15px
          );
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-body {
          font-size: calc(var(--type-base) * 1.15);
          font-weight: 650;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }
        .r-meta {
          font-size: var(--type-base);
          line-height: 1.25;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
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
