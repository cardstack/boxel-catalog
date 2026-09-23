import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import MarkdownField from '@cardstack/base/markdown';
import enumField from '@cardstack/base/enum';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { Ticket } from '@cardstack/catalog/cards/service-desk/ticket';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';
import {
  stateColor,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { RecordIdentifierField } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { RecordOwnerField } from '@cardstack/catalog/fields/record-owner/record-owner-field';
import { RelationshipSetField } from '@cardstack/catalog/fields/relationship-set/relationship-set-field';
import { ExternalReferenceField } from '@cardstack/catalog/fields/external-reference/external-reference-field';
import { WorkflowStateField } from '@cardstack/catalog/fields/workflow-state/workflow-state-field';

export const CASE_STATUSES = [
  'open',
  'investigating',
  'waiting-on-customer',
  'resolved',
  'closed',
];

export const CASE_STATUS_LABELS: Record<string, string> = {
  open: 'Open',
  investigating: 'Investigating',
  'waiting-on-customer': 'Waiting on Customer',
  resolved: 'Resolved',
  closed: 'Closed',
};

export const CASE_STATUS_COLORS: Record<string, StateColor> = {
  open: stateColor('blue'),
  investigating: stateColor('amber'),
  'waiting-on-customer': stateColor('slate'),
  resolved: stateColor('green'),
  closed: stateColor('slate'),
};

export const STATUS_HUES: Record<string, 'blue' | 'amber' | 'slate' | 'green'> =
  {
    open: 'blue',
    investigating: 'amber',
    'waiting-on-customer': 'slate',
    resolved: 'green',
    closed: 'slate',
  };

export const CaseStatusField = enumField(StringField, {
  options: CASE_STATUSES.map((value) => ({
    value,
    label: CASE_STATUS_LABELS[value],
  })),
  displayName: 'Case Status',
});

export const CASE_SEVERITIES = ['low', 'medium', 'high', 'critical'];

export const CaseSeverityField = enumField(StringField, {
  options: CASE_SEVERITIES.map((value) => ({ value, label: value })),
  displayName: 'Case Severity',
});

export const SEVERITY_HUES: Record<string, 'slate' | 'amber' | 'red'> = {
  low: 'slate',
  medium: 'slate',
  high: 'amber',
  critical: 'red',
};

// A Case is the longer-running investigation a Ticket is not: one customer
// problem that may span several tickets, days, and owners, with its own
// severity, findings, and resolution record. Tickets stay the unit of
// conversation; the Case is the unit of accountability — it LINKS the
// related tickets rather than replacing them.
export class Case extends CardDef {
  static displayName = 'Case';
  static headerColor = '#8b3a3a';

  @field subject = contains(StringField);
  @field account = linksTo(() => Account);
  @field owner = linksTo(() => Employee);
  @field status = contains(CaseStatusField);
  @field severity = contains(CaseSeverityField);
  @field openedOn = contains(DateField);
  @field resolvedOn = contains(DateField);
  @field relatedTickets = linksToMany(() => Ticket);
  // ── Support Ops additive extend (2026-09-07): the record-operations layer.
  // Nothing below renames or removes an existing field; instances predating
  // it simply leave these empty.
  @field caseId = contains(RecordIdentifierField);
  @field ownership = contains(RecordOwnerField);
  @field relationships = contains(RelationshipSetField);
  @field externalRefs = containsMany(ExternalReferenceField);
  @field workflowState = contains(WorkflowStateField);
  @field problemStatement = contains(TextAreaField);
  @field findings = contains(MarkdownField);
  @field resolution = contains(TextAreaField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Case) {
      return this.subject?.trim()?.length ? this.subject : 'Untitled Case';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'open'] ?? 'blue';
    }
    get statusLabel() {
      return CASE_STATUS_LABELS[this.args.model?.status ?? ''] ?? 'Open';
    }
    get severityHue() {
      return SEVERITY_HUES[this.args.model?.severity ?? 'low'] ?? 'slate';
    }
    get openedLabel() {
      let d = this.args.model?.openedOn;
      return d
        ? d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          })
        : '—';
    }
    get ticketCount() {
      try {
        return (this.args.model?.relatedTickets ?? []).filter(Boolean).length;
      } catch {
        return 0;
      }
    }
    <template>
      <article class='case'>
        <header class='head'>
          <div>
            <p class='kicker'>Support Case{{#if @model.caseId.value}}
                <code class='case-ref'>{{@model.caseId.value}}</code>{{/if}}</p>
            <h1>{{@model.subject}}</h1>
            <p class='sub'>opened
              {{this.openedLabel}}
              {{#if @model.account}}· <@fields.account @format='atom' />{{/if}}
              {{#if @model.owner}}· owned by
                <@fields.owner @format='atom' />{{/if}}</p>
          </div>
          <div class='head-right'>
            <StatePill
              @label={{this.statusLabel}}
              @hue={{this.statusHue}}
              @emphatic={{true}}
            />
            <StatePill
              @label='{{@model.severity}} severity'
              @hue={{this.severityHue}}
              @dot={{true}}
            />
          </div>
        </header>

        <section class='panel'>
          <h2>Problem</h2>
          <p class='body-text'>{{@model.problemStatement}}</p>
        </section>

        <section class='panel'>
          <h2>Related Tickets ({{this.ticketCount}})</h2>
          <div class='tickets'>
            {{#each @fields.relatedTickets as |T|}}
              <T @format='embedded' />
            {{else}}
              <p class='empty'>No tickets linked yet — a case usually starts
                from at least one.</p>
            {{/each}}
          </div>
        </section>

        {{#if @model.findings}}
          <section class='panel'>
            <h2>Findings</h2>
            <@fields.findings />
          </section>
        {{/if}}

        {{#if @model.resolution}}
          <section class='panel resolved-panel'>
            <h2>Resolution</h2>
            <p class='body-text'>{{@model.resolution}}</p>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .case {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          font-family: var(--font-sans, inherit);
          display: grid;
          gap: var(--boxel-sp);
        }
        .head {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: var(--boxel-sp);
          border-bottom: 1px solid var(--border, var(--boxel-200));
          padding-bottom: var(--boxel-sp);
        }
        .kicker {
          margin: 0;
          font-size: 0.6875rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .case-ref {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.02em;
          margin-left: var(--boxel-sp-4xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-5xs) 0;
          font-family: var(--font-heading, inherit);
          font-size: 1.5rem;
          line-height: 1.25;
        }
        .sub {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .head-right {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: var(--boxel-sp-xxs);
        }
        .panel {
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          padding: var(--boxel-sp);
          background: var(--card, transparent);
        }
        .resolved-panel {
          border-color: var(--state-green-fg, #15803d);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.8125rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .body-text {
          margin: 0;
          white-space: pre-wrap;
          font-size: 0.875rem;
        }
        .tickets {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
          font-size: 0.875rem;
        }
        @container (max-width: 560px) {
          .head {
            flex-direction: column;
          }
          .head-right {
            flex-direction: row;
            align-items: flex-start;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'open'] ?? 'blue';
    }
    get statusLabel() {
      return CASE_STATUS_LABELS[this.args.model?.status ?? ''] ?? 'Open';
    }
    get severityHue() {
      return SEVERITY_HUES[this.args.model?.severity ?? 'low'] ?? 'slate';
    }
    <template>
      <div class='row'>
        <span class='name'>{{@model.subject}}</span>
        <StatePill
          @label={{@model.severity}}
          @hue={{this.severityHue}}
          @dot={{true}}
        />
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
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.subject}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    /** Fitted has ~250px; the long status label ellipsised its own pill. */
    get statusLabel() {
      let status = this.args.model?.status ?? '';
      if (status === 'waiting-on-customer') return 'Waiting';
      return CASE_STATUS_LABELS[status] ?? 'Open';
    }
    get severityColor(): StateColor {
      return stateColor(
        SEVERITY_HUES[this.args.model?.severity ?? 'low'] ?? 'slate',
      );
    }
    get statusHue() {
      return STATUS_HUES[this.args.model?.status ?? 'open'] ?? 'blue';
    }
    get accentStyle() {
      return `--fit-accent: ${this.severityColor.ring};`;
    }
    <template>
      {{! The visual anchor is the severity STRIPE — the one thing every size
          keeps — so a grid of cases reads as a heat map before a word is read. }}
      <div class='fit' style={{this.accentStyle}}>
        <span class='fit-head'>
          {{#if @model.caseId.value}}<code
              class='fit-ref'
            >{{@model.caseId.value}}</code>{{/if}}
          <span class='fit-sev'>{{@model.severity}}</span>
          <StatePill
            @label={{this.statusLabel}}
            @hue={{this.statusHue}}
            class='fit-status'
          />
        </span>
        <span class='fit-name'>{{@model.subject}}</span>
        <span class='fit-foot'>
          <span
            class='fit-owner
              {{unless @model.ownership.ownerName "fit-unowned"}}'
          >{{if
              @model.ownership.ownerName
              @model.ownership.ownerName
              'unassigned'
            }}</span>
          {{#if @model.ownership.teamName}}<span
              class='fit-team'
            >{{@model.ownership.teamName}}</span>{{/if}}
        </span>
      </div>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-xs)
            calc(var(--boxel-sp-xs) + 0.25rem);
          overflow: hidden;
          border-left: 0.25rem solid
            var(--fit-accent, var(--muted, var(--boxel-200)));
          background: var(--card, var(--boxel-light));
          color: var(--card-foreground, var(--boxel-dark));
        }
        .fit-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-ref {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-weight: 600;
          white-space: nowrap;
        }
        .fit-sev {
          color: var(--fit-accent, var(--muted-foreground, var(--boxel-450)));
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          font-size: 0.6875rem;
        }
        .fit-status {
          margin-left: auto;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.25;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 3;
          -webkit-box-orient: vertical;
        }
        .fit-foot {
          margin-top: auto;
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          min-width: 0;
        }
        .fit-owner,
        .fit-team {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fit-unowned {
          color: var(--boxel-warning);
          font-style: italic;
        }
        /* strips: one row, the subject carries the width */
        @container fitted-card (height <= 105px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-head {
            flex: none;
          }
          .fit-status {
            margin-left: 0;
          }
          .fit-name {
            flex: 1;
            -webkit-line-clamp: 2;
            font-size: var(--boxel-font-size-sm);
          }
          .fit-foot {
            margin-top: 0;
            flex: none;
            max-width: 9rem;
          }
        }
        @container fitted-card (height <= 65px) {
          .fit-name {
            -webkit-line-clamp: 1;
          }
          .fit-foot {
            display: none;
          }
        }
        /* badges: ref + severity only — the stripe still says how bad */
        @container fitted-card (width <= 150px) {
          .fit {
            flex-direction: column;
            gap: 0;
          }
          .fit-status,
          .fit-foot,
          .fit-sev {
            display: none;
          }
          .fit-name {
            -webkit-line-clamp: 2;
            font-size: var(--boxel-font-size-xs);
          }
        }
        @container fitted-card (width <= 150px) and (height <= 40px) {
          .fit-name {
            display: none;
          }
        }
      </style>
    </template>
  };

  // The form for working a case, grouped by how an investigation actually
  // runs: what is it and how bad (identity) → who reported it and who owns
  // it → what we know → how it ended. cardTitle is computed and never
  // appears here. Four sections → the EditSectionNav rail. This family asserts no brand
  // token in its other formats, so the accent is the theme's own foreground.
  static edit = class Edit extends Component<typeof this> {
    // Left section nav: clicking anchors that section to the top of the
    // form's own scroller (the root — never a nested
    // scroller). Scoped through the event's own root so several open edit
    // panels never cross-scroll each other.
    @tracked activeSection = 'identity';

    sections = [
      { id: 'identity', label: 'Case' },
      { id: 'people', label: 'Reporter & Owner' },
      { id: 'description', label: 'Description' },
      { id: 'resolution', label: 'Resolution' },
      { id: 'operations', label: 'Operations' },
    ];

    goTo = (id: string, event: Event) => {
      this.activeSection = id;
      let root = (event.currentTarget as HTMLElement).closest('.case-edit');
      root
        ?.querySelector(`[data-sect='${id}']`)
        ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
    };

    <template>
      <div class='case-edit'>
        {{! the container element cannot be restyled by its own query
            — the responsive grid lives on
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
              class='sect {{if (eq this.activeSection "identity") "focused"}}'
              data-sect='identity'
            >
              <h3>Case</h3>
              <FieldContainer @label='Subject' @vertical={{true}}>
                <@fields.subject />
              </FieldContainer>
              <div class='row'>
                <FieldContainer @label='Severity' @vertical={{true}}>
                  <@fields.severity />
                </FieldContainer>
                <FieldContainer @label='Status' @vertical={{true}}>
                  <@fields.status />
                </FieldContainer>
                <FieldContainer @label='Opened on' @vertical={{true}}>
                  <@fields.openedOn />
                </FieldContainer>
              </div>
            </section>

            <section
              class='sect {{if (eq this.activeSection "people") "focused"}}'
              data-sect='people'
            >
              <h3>Reporter &amp; Owner</h3>
              <div class='row two'>
                <FieldContainer @label='Account' @vertical={{true}}>
                  <@fields.account />
                </FieldContainer>
                <FieldContainer @label='Owner' @vertical={{true}}>
                  <@fields.owner />
                </FieldContainer>
              </div>
              <FieldContainer @label='Related tickets' @vertical={{true}}>
                <@fields.relatedTickets />
              </FieldContainer>
            </section>

            <section
              class='sect
                {{if (eq this.activeSection "description") "focused"}}'
              data-sect='description'
            >
              <h3>Description
                <span class='sect-hint'>findings grow as the investigation does
                  — append, don't rewrite</span></h3>
              <FieldContainer @label='Problem statement' @vertical={{true}}>
                <@fields.problemStatement />
              </FieldContainer>
              <FieldContainer @label='Findings' @vertical={{true}}>
                <@fields.findings />
              </FieldContainer>
            </section>

            <section
              class='sect {{if (eq this.activeSection "resolution") "focused"}}'
              data-sect='resolution'
            >
              <h3>Resolution
                <span class='sect-hint'>fill in when closing the case</span></h3>
              <FieldContainer @label='Resolution' @vertical={{true}}>
                <@fields.resolution />
              </FieldContainer>
              <div class='row two'>
                <FieldContainer @label='Resolved on' @vertical={{true}}>
                  <@fields.resolvedOn />
                </FieldContainer>
              </div>
            </section>
            <section
              class='sect {{if (eq this.activeSection "operations") "focused"}}'
              data-sect='operations'
            >
              <h3>Operations
                <span class='sect-hint'>ids and ownership are written by
                  commands; relationships and external references are edited
                  here</span></h3>
              <FieldContainer @label='Case ID' @vertical={{true}}>
                <@fields.caseId />
              </FieldContainer>
              <FieldContainer @label='Owner' @vertical={{true}}>
                <@fields.ownership />
              </FieldContainer>
              <FieldContainer @label='Workflow state' @vertical={{true}}>
                <@fields.workflowState />
              </FieldContainer>
              <FieldContainer @label='Linked records' @vertical={{true}}>
                <@fields.relationships />
              </FieldContainer>
              <FieldContainer @label='External references' @vertical={{true}}>
                <@fields.externalRefs />
              </FieldContainer>
            </section>
          </div>
        </div>
      </div>
      <style scoped>
        .case-edit {
          container-type: inline-size;
          container-name: edit;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          /* the case family asserts no brand hue of its own — the accent is
             the theme's foreground */
          --case-ink: var(--foreground, var(--boxel-dark));
        }
        .edit-body {
          display: grid;
          grid-template-columns: 9.5rem minmax(0, 1fr);
          align-items: start;
          gap: var(--boxel-sp);
        }
        /* the root is the scroller, so sticky pins the nav to its top;
           no ink knobs handed over — the rail's default is already the
           inverted foreground/background pair */
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
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          padding: var(--boxel-sp);
          display: grid;
          gap: var(--boxel-sp-sm);
          transition:
            outline-color 160ms ease,
            box-shadow 160ms ease;
          outline: 2px solid transparent;
          outline-offset: 2px;
        }
        /* the section the rail points at mirrors the rail's active state */
        .sect.focused {
          outline-color: var(--case-ink);
          box-shadow: 0 0 0 4px
            color-mix(in oklch, var(--case-ink) 12%, transparent);
        }
        h3 {
          margin: 0;
          font-size: 0.8125rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
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
        .row {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: var(--boxel-sp-sm);
          align-items: start;
        }
        .row.two {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        @container edit (width < 640px) {
          .row,
          .row.two {
            grid-template-columns: 1fr;
          }
          /* narrow panel: nav becomes a horizontal chip row above the form */
          .edit-body {
            grid-template-columns: 1fr;
          }
          /* narrow: the rail flips horizontal (consumer's scope attribute
             rides ...attributes onto the component root, so these apply) */
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
  };
}
