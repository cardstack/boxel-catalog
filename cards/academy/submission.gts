import {
  CardDef,
  Component,
  FileDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import {
  SubmissionStatusField,
  SUBMISSION_STATUSES,
} from './submission-status-field';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Enrollment } from './enrollment';
import { Assignment } from './assignment';
import { Grade } from './grade';

/**
 * One hand-in: a version of a learner's answer to one assignment. A
 * resubmission is a NEW Submission (version n+1) so the trail is kept and
 * the grader can see what changed. `isLate` and `daysLate` are derived from
 * the assignment's due moment at render time; the penalty actually applied
 * is a grading decision and lives on the Grade.
 */
export class Submission extends CardDef {
  static displayName = 'Submission';
  static icon = FileTextIcon;

  @field enrollment = linksTo(() => Enrollment);
  @field assignment = linksTo(() => Assignment);
  @field version = contains(NumberField);
  @field submittedAt = contains(DateTimeField);
  @field text = contains(MarkdownField);
  @field files = linksToMany(() => FileDef);
  @field submissionStatus = contains(SubmissionStatusField);
  @field grade = linksTo(() => Grade as any);

  @field isLate = contains(BooleanField, {
    computeVia: function (this: Submission): boolean {
      return daysLateOf(this) > 0;
    },
  });
  @field daysLate = contains(NumberField, {
    computeVia: function (this: Submission): number {
      return daysLateOf(this);
    },
  });
  @field learnerName = contains(StringField, {
    computeVia: function (this: Submission) {
      return this.enrollment?.learnerName ?? '';
    },
  });
  @field assignmentTitle = contains(StringField, {
    computeVia: function (this: Submission) {
      return this.assignment?.cardTitle ?? '';
    },
  });
  @field statusLabel = contains(StringField, {
    computeVia: function (this: Submission) {
      return (
        SUBMISSION_STATUSES.find((s) => s.value === this.submissionStatus)
          ?.label ?? 'Not submitted'
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Submission) {
      let who = this.enrollment?.learnerName ?? 'Learner';
      let what =
        this.assignment?.code ?? this.assignment?.cardTitle ?? 'assignment';
      return `${who} · ${what} v${this.version ?? 1}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return statusHue(
        SubmissionStatusField,
        this.args.model?.submissionStatus,
      );
    }
    <template>
      <article class='submission'>
        <header class='hero'>
          <div class='hero-text'>
            <span class='eyebrow'>Submission v{{if
                @model.version
                @model.version
                1
              }}
              ·
              {{#if @model.assignment}}<@fields.assignment
                  @format='atom'
                />{{/if}}</span>
            <h1>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h1>
            <p class='meta'>
              <StatePill
                @label={{@model.statusLabel}}
                @hue={{this.hue}}
                @dot={{true}}
              />
              {{#if @model.submittedAt}}<span>handed in
                  {{fmtDateTime @model.submittedAt}}</span>{{/if}}
              {{#if @model.isLate}}<StatePill
                  @label='{{@model.daysLate}}d late'
                  @hue='amber'
                />{{/if}}
            </p>
          </div>
          {{#if @model.grade}}
            <div class='grade-box'><@fields.grade @format='embedded' /></div>
          {{/if}}
        </header>
        <section class='panel'>
          <h2>Answer</h2>
          {{#if @model.text}}
            <@fields.text />
          {{else}}
            <p class='empty'>No written answer.</p>
          {{/if}}
        </section>
        {{#if @model.files.length}}
          <section class='panel'>
            <h2>Files</h2>
            <div class='stack'><@fields.files @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .submission {
          max-width: 52rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
        }
        .hero {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp);
          align-items: flex-start;
          flex-wrap: wrap;
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .grade-box {
          min-width: 16rem;
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        .panel {
          padding: var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
          line-height: 1.6;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .stack {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return statusHue(
        SubmissionStatusField,
        this.args.model?.submissionStatus,
      );
    }
    <template>
      <div class='row'>
        <span class='v'>v{{if @model.version @model.version 1}}</span>
        <div class='text'>
          <span class='title'>{{if
              @model.learnerName
              @model.learnerName
              'Learner'
            }}
            ·
            {{@model.assignmentTitle}}</span>
          <span class='sub'>{{#if @model.submittedAt}}{{fmtDateTime
                @model.submittedAt
              }}{{else}}not handed in{{/if}}{{#if @model.isLate}}
              ·
              {{@model.daysLate}}d late{{/if}}</span>
        </div>
        <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .v {
          min-width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--muted, var(--boxel-100));
          font: 700 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'context', label: 'Context' },
      { id: 'answer', label: 'Answer' },
      { id: 'files', label: 'Files' },
      { id: 'grade', label: 'Grade' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Submission sections'
        as |e|
      >
        <e.Section
          @id='context'
          @title='Context'
          @hint='normally written by Submit Assignment'
          @cols={{3}}
        >
          <FieldContainer
            @label='Enrollment'
            @vertical={{true}}
          ><@fields.enrollment /></FieldContainer>
          <FieldContainer
            @label='Assignment'
            @vertical={{true}}
          ><@fields.assignment /></FieldContainer>
          <FieldContainer
            @label='Status'
            @vertical={{true}}
          ><@fields.submissionStatus /></FieldContainer>
          <FieldContainer @label='Version' @vertical={{true}}><@fields.version
            /></FieldContainer>
          <FieldContainer
            @label='Submitted at'
            @vertical={{true}}
          ><@fields.submittedAt /></FieldContainer>
        </e.Section>
        <e.Section @id='answer' @title='Answer' @cols={{1}}>
          <FieldContainer
            @label='Written answer'
            @vertical={{true}}
          ><@fields.text /></FieldContainer>
        </e.Section>
        <e.Section @id='files' @title='Files' @cols={{1}}>
          <FieldContainer
            @label='Attached files'
            @vertical={{true}}
          ><@fields.files /></FieldContainer>
        </e.Section>
        <e.Section @id='grade' @title='Grade' @cols={{1}}>
          <FieldContainer
            @label='Grade record'
            @vertical={{true}}
          ><@fields.grade /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(
        SubmissionStatusField,
        this.args.model?.submissionStatus,
      );
    }
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='v'>v{{if @model.version @model.version 1}}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.learnerName
                @model.learnerName
                'Learner'
              }}</h3>
            <span class='fit-eb'>{{@model.assignmentTitle}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>
        </div>
        <dl class='fit-add'>
          <div><dt>Handed in</dt><dd>{{if
                @model.submittedAt
                (fmtDateTime @model.submittedAt)
                '—'
              }}</dd></div>
          <div><dt>Late</dt><dd>{{if
                @model.isLate
                (concat @model.daysLate 'd')
                'On time'
              }}</dd></div>
          <div><dt>Files</dt><dd>{{@model.files.length}}</dd></div>
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .v {
          flex: none;
          min-width: 2rem;
          height: 2rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--muted, var(--boxel-100));
          font: 700 var(--boxel-font-size-xs)
            var(--font-mono, ui-monospace, monospace);
        }
        .fit-head {
          min-width: 0;
          flex: 1;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-pill {
          flex: none;
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 220px) {
          .fit-pill {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

export function daysLateOf(s: Partial<Submission> | null | undefined): number {
  let due = (s?.assignment as any)?.dueWindow?.dueAt;
  if (!due || !s?.submittedAt) return 0;
  let ms = new Date(s.submittedAt).getTime() - new Date(due).getTime();
  return ms > 0 ? Math.ceil(ms / 86_400_000) : 0;
}

export function fmtDateTime(d?: Date | string | null): string {
  if (!d) return '';
  return new Date(d).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function concat(a: unknown, b: unknown) {
  return `${a ?? ''}${b ?? ''}`;
}

export default Submission;
