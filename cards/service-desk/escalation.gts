import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import TrendingUpIcon from '@cardstack/boxel-icons/trending-up';

import { eq } from '@cardstack/boxel-ui/helpers';

import { EscalationLevelField, levelColor } from '@cardstack/catalog/fields/escalation-level/escalation-level-field';
import {
  stateColor,
  stateColorOf,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { tracked } from '@glimmer/tracking';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';

export const ESCALATION_REASONS = [
  'sla-risk',
  'customer-request',
  'agent-request',
  'breach',
  'policy',
] as const;

export const EscalationReasonField = enumField(StringField, {
  displayName: 'Escalation Reason',
  options: ESCALATION_REASONS as unknown as string[],
});

export const ESCALATION_STATUSES = [
  'open',
  'acknowledged',
  'resolved',
  'cancelled',
] as const;

export const EscalationStatusField = enumField(StringField, {
  displayName: 'Escalation Status',
  options: ESCALATION_STATUSES as unknown as string[],
});

/** Exported beside the enum so every consumer colors the ladder alike. */
export const ESCALATION_STATUS_HUES: Record<string, Hue> = {
  open: 'amber',
  acknowledged: 'blue',
  resolved: 'green',
  cancelled: 'slate',
};

export const ESCALATION_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(ESCALATION_STATUS_HUES).map(([k, h]) => [k, stateColor(h)]),
  );

export function escalationStatusHue(status?: string | null): Hue {
  return ESCALATION_STATUS_HUES[status ?? 'open'] ?? 'slate';
}

/**
 * One rung-climb on the ladder, as a RECORD — "escalated twice last quarter"
 * must be a query, not an anecdote.
 *
 * The receiving level's acknowledgement has its own clock
 * (`toLevel.ackTargetMinutes` vs `raisedAt`→`acknowledgedAt`): an
 * unacknowledged escalation is invisible risk and renders breach-amber wherever it is
 * listed. Cancellation is a coded act with a required reason (the
 * Cancel command enforces it); nothing here is ever deleted.
 *
 * `subject` is `linksTo(CardDef)` — the ladder works for any record type.
 */
export class Escalation extends CardDef {
  static displayName = 'Escalation';
  static icon = TrendingUpIcon;

  @field subject = linksTo(CardDef);
  /** Denormalised link facts: consumers join on these instead of touching
      `subject` (a lazy linksTo that would load mid-render). */
  @field subjectId = contains(StringField, {
    computeVia: function (this: Escalation) {
      return this.subject?.id;
    },
  });
  @field subjectTitle = contains(StringField, {
    computeVia: function (this: Escalation) {
      return (this.subject as any)?.cardTitle ?? this.subject?.title;
    },
  });
  @field fromLevel = contains(EscalationLevelField);
  @field toLevel = contains(EscalationLevelField);
  @field reason = contains(EscalationReasonField);
  @field note = contains(TextAreaField);
  @field raisedByName = contains(StringField, {
    description: 'Person or "policy <name>" — automation is always attributed.',
  });
  @field raisedAt = contains(DateTimeField);
  @field acknowledgedByName = contains(StringField);
  @field acknowledgedAt = contains(DateTimeField);
  @field status = contains(EscalationStatusField);
  @field cancelledReason = contains(StringField);

  @field ackOverdue = contains(StringField, {
    computeVia: function (this: Escalation) {
      if (this.acknowledgedAt || this.status !== 'open') return 'no';
      let target = this.toLevel?.ackTargetMinutes;
      let raised = this.raisedAt
        ? new Date(this.raisedAt as unknown as string)
        : null;
      if (!target || !raised) return 'no';
      return Date.now() - raised.getTime() > target * 60000 ? 'yes' : 'no';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Escalation) {
      let from = this.fromLevel?.key ?? '?';
      let to = this.toLevel?.key ?? '?';
      return `Escalation ${from} → ${to}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get statusHue() {
      return escalationStatusHue(this.args.model.status);
    }
    get statusColor() {
      let c = stateColorOf(ESCALATION_STATUS_COLORS, this.args.model.status);
      return `--esc-fg: ${c.fg}; --esc-bg: ${c.bg};`;
    }
    get raisedLabel() {
      return relativeStamp(this.args.model.raisedAt ?? undefined);
    }
    get ackLabel() {
      return relativeStamp(this.args.model.acknowledgedAt ?? undefined);
    }
    <template>
      <article class='esc-page' style={{this.statusColor}}>
        <header class='esc-head'>
          <h1><@fields.title /></h1>
          <StatePill @label={{@model.status}} @hue={{this.statusHue}} />
        </header>
        <p class='esc-subject'>on <@fields.subject @format='atom' /></p>
        <section class='esc-ladder'>
          <div class='esc-rung'>
            <span class='esc-k'>From</span><@fields.fromLevel
              @format='embedded'
            />
          </div>
          <div class='esc-rung'>
            <span class='esc-k'>To</span><@fields.toLevel @format='embedded' />
            {{#if @model.toLevel.ackTargetMinutes}}
              <span class='esc-ack-target'>ack target
                {{@model.toLevel.ackTargetMinutes}}m</span>
            {{/if}}
          </div>
        </section>
        <section class='esc-facts'>
          <div><span class='esc-k'>Reason</span> {{@model.reason}}</div>
          <div><span class='esc-k'>Raised</span>
            {{this.raisedLabel}}
            by
            {{@model.raisedByName}}</div>
          {{#if @model.acknowledgedAt}}
            <div><span class='esc-k'>Acknowledged</span>
              {{this.ackLabel}}
              by
              {{@model.acknowledgedByName}}</div>
          {{else if @model.toLevel.ackTargetMinutes}}
            <div class='esc-await'>Awaiting acknowledgement{{#if
                (eq @model.ackOverdue 'yes')
              }} — OVERDUE{{/if}}</div>
          {{/if}}
          {{#if @model.note}}<p class='esc-note'>{{@model.note}}</p>{{/if}}
          {{#if @model.cancelledReason}}
            <div><span class='esc-k'>Cancelled</span>
              {{@model.cancelledReason}}</div>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .esc-page {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .esc-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
        .esc-subject {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-size: var(--boxel-font-size-sm);
        }
        .esc-ladder {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp-sm);
          background: var(--card, var(--boxel-light));
        }
        .esc-rung {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .esc-k {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
          min-width: 6rem;
        }
        .esc-ack-target {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .esc-facts {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
        }
        .esc-await {
          color: var(--esc-fg);
          font-weight: 500;
        }
        .esc-note {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-left: 0.1875rem solid var(--border, var(--boxel-border-color));
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return escalationStatusHue(this.args.model.status);
    }
    get toColor() {
      let c = levelColor(this.args.model.toLevel?.key);
      return `--esc-fg: ${c.fg}; --esc-bg: ${c.bg};`;
    }
    get raisedLabel() {
      return relativeStamp(this.args.model.raisedAt ?? undefined);
    }
    <template>
      <div class='esc-row' style={{this.toColor}}>
        <span class='esc-level'>{{if
            @model.toLevel.key
            @model.toLevel.key
            '?'
          }}</span>
        <span class='esc-body'>
          <span class='esc-title'>{{@model.title}} · {{@model.reason}}</span>
          <span class='esc-meta'>{{this.raisedLabel}}
            by
            {{@model.raisedByName}}
            {{#if (eq @model.ackOverdue 'yes')}}<b class='esc-overdue'>ack
                overdue</b>{{/if}}
          </span>
        </span>
        <StatePill @label={{@model.status}} @hue={{this.statusHue}} />
      </div>
      <style scoped>
        .esc-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          width: 100%;
        }
        .esc-level {
          flex: none;
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          padding: 0.125rem 0.5rem;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--esc-bg);
          color: var(--esc-fg);
        }
        .esc-body {
          display: flex;
          flex-direction: column;
          min-width: 0;
          flex: 1;
        }
        .esc-title {
          font-weight: 500;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .esc-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .esc-overdue {
          color: var(--boxel-danger);
          margin-left: var(--boxel-sp-4xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='esc-atom'>{{@model.title}} · {{@model.status}}</span>
      <style scoped>
        .esc-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get toColor() {
      let c = levelColor(this.args.model.toLevel?.key);
      return `--esc-fg: ${c.fg}; --esc-bg: ${c.bg};`;
    }
    <template>
      <div class='esc-fitted' style={{this.toColor}}>
        <span class='esc-badge'>{{if
            @model.toLevel.key
            @model.toLevel.key
            '?'
          }}</span>
        <div class='esc-fitted-body'>
          <span class='esc-fitted-title'>{{@model.title}}</span>
          <span class='esc-fitted-meta'>{{@model.reason}}
            ·
            {{@model.status}}</span>
          <div class='esc-fitted-more'>
            <span>raised by {{@model.raisedByName}}</span>
            {{#if @model.toLevel.ackTargetMinutes}}
              <span>ack target
                {{@model.toLevel.ackTargetMinutes}}m{{#if
                  @model.acknowledgedByName
                }} · ack by {{@model.acknowledgedByName}}{{/if}}</span>
            {{/if}}
            {{#if @model.note}}<span
                class='esc-fitted-note'
              >{{@model.note}}</span>{{/if}}
          </div>
        </div>
      </div>
      <style scoped>
        .esc-fitted {
          height: 100%;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .esc-badge {
          flex: none;
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-weight: 700;
          font-size: var(--boxel-font-size);
          padding: 0.25rem 0.5rem;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--esc-bg);
          color: var(--esc-fg);
        }
        .esc-fitted-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
        }
        .esc-fitted-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .esc-fitted-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .esc-fitted-more {
          display: none;
        }
        @container fitted-card (height > 170px) {
          .esc-fitted-more {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-5xs);
            margin-top: var(--boxel-sp-4xs);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground, var(--boxel-450));
          }
          .esc-fitted-note {
            font-style: italic;
            overflow: hidden;
            display: -webkit-box;
            -webkit-line-clamp: 3;
            -webkit-box-orient: vertical;
          }
        }
        @container fitted-card (height <= 80px) {
          .esc-fitted {
            align-items: center;
          }
          .esc-fitted-meta {
            display: none;
          }
        }
      </style>
    </template>
  };
  static edit = class Edit extends Component<typeof this> {
    @tracked activeSection = 'ladder';

    sections = [
      { id: 'ladder', label: 'Ladder' },
      { id: 'facts', label: 'Facts' },
      { id: 'lifecycle', label: 'Lifecycle' },
    ];

    goTo = (id: string, event: Event) => {
      this.activeSection = id;
      let root = (event.currentTarget as HTMLElement).closest('.esc-edit');
      root
        ?.querySelector(`[data-sect='${id}']`)
        ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    };

    <template>
      <div class='esc-edit'>
        <div class='edit-body'>
          <EditSectionNav
            @sections={{this.sections}}
            @activeId={{this.activeSection}}
            @onSelect={{this.goTo}}
            class='sect-nav'
          />
          <div class='sects'>
            <section
              class='sect {{if (eq this.activeSection "ladder") "focused"}}'
              data-sect='ladder'
            >
              <h3>Ladder
                <span class='sect-hint'>levels are set when the escalation is
                  raised</span></h3>
              <FieldContainer @label='From level' @vertical={{true}}>
                <@fields.fromLevel />
              </FieldContainer>
              <FieldContainer @label='To level' @vertical={{true}}>
                <@fields.toLevel />
              </FieldContainer>
            </section>
            <section
              class='sect {{if (eq this.activeSection "facts") "focused"}}'
              data-sect='facts'
            >
              <h3>Facts</h3>
              <FieldContainer @label='Reason' @vertical={{true}}>
                <@fields.reason />
              </FieldContainer>
              <FieldContainer @label='Note' @vertical={{true}}>
                <@fields.note />
              </FieldContainer>
              <FieldContainer @label='Raised by' @vertical={{true}}>
                <@fields.raisedByName />
              </FieldContainer>
            </section>
            <section
              class='sect {{if (eq this.activeSection "lifecycle") "focused"}}'
              data-sect='lifecycle'
            >
              <h3>Lifecycle
                <span class='sect-hint'>acknowledge from My Desk; cancel via the
                  Cancel action so the reason is recorded</span></h3>
              <FieldContainer @label='Status' @vertical={{true}}>
                <@fields.status />
              </FieldContainer>
              <FieldContainer @label='Acknowledged by' @vertical={{true}}>
                <@fields.acknowledgedByName />
              </FieldContainer>
              <FieldContainer @label='Cancelled reason' @vertical={{true}}>
                <@fields.cancelledReason />
              </FieldContainer>
            </section>
          </div>
        </div>
      </div>
      <style scoped>
        .esc-edit {
          container-type: inline-size;
        }
        .edit-body {
          display: grid;
          grid-template-columns: 10rem 1fr;
          gap: var(--boxel-sp);
          align-items: start;
        }
        @container (width < 34rem) {
          .edit-body {
            grid-template-columns: 1fr;
          }
        }
        .sects {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          min-width: 0;
        }
        .sect {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          background: var(--card, var(--boxel-light));
          padding: var(--boxel-sp-sm);
          scroll-margin-top: var(--boxel-sp);
        }
        .sect.focused {
          border-color: var(--primary, var(--boxel-highlight));
        }
        .sect h3 {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .sect-hint {
          text-transform: none;
          letter-spacing: 0;
          font-weight: 400;
          font-style: italic;
        }
      </style>
    </template>
  };
}

export default Escalation;
