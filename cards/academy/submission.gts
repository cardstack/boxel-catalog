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
import { Button } from '@cardstack/pretui/components/button';
import { concat } from '@ember/helper';
import { on } from '@ember/modifier';

import {
  SubmissionStatusField,
  SUBMISSION_STATUSES,
} from './submission-status-field';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Enrollment } from './enrollment';
import { Assignment } from './assignment';
import { Grade } from './grade';
import { RichFittedCard } from '../shared/rich-fitted-card';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { IsoFrame } from '../shared/compact-sheet';

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
    get scores() {
      return ((this.args.model?.grade as any)?.criterionScores ?? []) as any[];
    }
    get comments() {
      return this.scores.filter((c) => c?.comment);
    }
    openGrade = () => {
      let g = this.args.model?.grade;
      if (g) this.args.viewCard?.(g as any, 'isolated');
    };
    <template>
      <IsoFrame>
        <Sheet @mark='Sb' @title={{headline @model}} @meta={{metaLine @model}}>
          <:status>
            <Dot @hue={{this.hue}}>{{lower @model.statusLabel}}</Dot>
            {{#if @model.submittedAt}}
              <Dot @hue={{if @model.isLate 'red' 'green'}}>{{lateLabel
                  @model
                }}</Dot>
            {{/if}}
          </:status>
          <:actions>
            {{#if @model.grade}}
              <Button
                @size='s'
                @tone='primary'
                @appearance='accent'
                {{on 'click' this.openGrade}}
              >Open grade</Button>
            {{/if}}
          </:actions>
          <:stats>
            <Stat
              @label='Grade'
              @value={{gradeLetter @model}}
              @sub={{gradeLine @model}}
            />
            <Stat
              @label='Version'
              @value={{concat 'v' (if @model.version @model.version 1)}}
              @sub={{if
                @model.assignment.allowResubmission
                'resubmission allowed'
                'single submission'
              }}
            />
            <Stat
              @label='Late'
              @value={{concat (if @model.daysLate @model.daysLate 0) ' days'}}
              @sub={{dueLine @model}}
            />
          </:stats>
          <:main>
            <Section @title='Answer'>
              <div class='answer'>{{#if @model.text}}<@fields.text
                  />{{else}}<span class='muted'>No text answer.</span>{{/if}}</div>
            </Section>
            {{#if this.scores.length}}
              <Section @title='Rubric score'>
                {{#each this.scores as |c|}}
                  <div class='row'>
                    <span class='lead'>{{c.criterionName}}{{#if c.levelLabel}}
                        <span class='muted'>·
                          {{c.levelLabel}}</span>{{/if}}</span>
                    <span class='mono'>{{c.points}} / {{c.maxPoints}}</span>
                  </div>
                {{/each}}
              </Section>
            {{/if}}
            {{#if this.comments.length}}
              <Section @title='Grader comment'>
                {{#each this.comments as |c|}}
                  <div class='row'>
                    <span class='lead'>{{c.criterionName}}
                      <span class='muted'>{{c.comment}}</span></span>
                    <span class='mono'>{{c.points}} / {{c.maxPoints}}</span>
                  </div>
                {{/each}}
              </Section>
            {{/if}}
            {{#if @model.files.length}}
              <Section @title='Files'>
                <div class='files'><@fields.files
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
              </Section>
            {{/if}}
          </:main>
          <:side>
            <Section @title='Linked'>
              <Kv @label='Enrollment'>{{#if
                  @model.enrollment
                }}<@fields.enrollment
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
              <Kv @label='Assignment'>{{#if
                  @model.assignment
                }}<@fields.assignment
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
              <Kv @label='Grade'>{{#if @model.grade}}<@fields.grade
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
            </Section>
            <Section @title='Details'>
              <Kv @label='Assignment'>{{dash @model.assignmentTitle}}</Kv>
              <Kv @label='Version' @mono={{true}}>{{if
                  @model.version
                  @model.version
                  1
                }}</Kv>
              <Kv @label='Submitted' @mono={{true}}>{{fmtDay
                  @model.submittedAt
                }}</Kv>
              <Kv @label='Due' @mono={{true}}>{{fmtDay
                  @model.assignment.dueWindow.dueAt
                }}</Kv>
              <Kv @label='Late'>{{if
                  @model.isLate
                  (concat @model.daysLate ' days')
                  'no'
                }}</Kv>
              <Kv @label='Grade'>{{gradeShort @model}}</Kv>
              <Kv @label='Graded' @mono={{true}}>{{fmtDay
                  @model.grade.gradedAt
                }}</Kv>
              <Kv @label='Files' @mono={{true}}>{{if
                  @model.files.length
                  @model.files.length
                  'none'
                }}</Kv>
            </Section>
          </:side>
        </Sheet>
      </IsoFrame>
      <style scoped>
        .answer {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-block-size: 1.75rem;
          padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
        }
        .lead {
          min-inline-size: 0;
          font-weight: 600;
        }
        .muted {
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .mono {
          flex: none;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-variant-numeric: tabular-nums;
        }
        .files {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
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
      <Embed @mark='Sb' @title={{headline @model}} @meta={{metaLine @model}}>
        <:status>
          <Dot @hue={{this.hue}}>{{lower @model.statusLabel}}</Dot>
          {{#if @model.submittedAt}}
            <Dot @hue={{if @model.isLate 'red' 'green'}}>{{lateLabel
                @model
              }}</Dot>
          {{/if}}
        </:status>
        <:fact>Grade
          <strong>{{gradeLetter @model}}</strong>
          ·
          {{gradeFact @model}}</:fact>
        <:default>
          <Kv @label='Assignment'>{{dash @model.assignmentTitle}}</Kv>
          <Kv @label='Version' @mono={{true}}>{{if
              @model.version
              @model.version
              1
            }}</Kv>
          <Kv @label='Submitted' @mono={{true}}>{{fmtDay
              @model.submittedAt
            }}</Kv>
          <Kv @label='Due' @mono={{true}}>{{fmtDay
              @model.assignment.dueWindow.dueAt
            }}</Kv>
          <Kv @label='Late'>{{if
              @model.isLate
              (concat @model.daysLate ' days')
              'no'
            }}</Kv>
          <Kv @label='Grade'>{{gradeShort @model}}</Kv>
          <Kv @label='Enrollment'>{{#if @model.enrollment}}<@fields.enrollment
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Assignment'>{{#if @model.assignment}}<@fields.assignment
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return statusHue(
        SubmissionStatusField,
        this.args.model?.submissionStatus,
      );
    }
    <template>
      <AtomChip @mark='Sb' @title={{headline @model}}><Dot
          @hue={{this.hue}}
        >{{lower @model.statusLabel}}</Dot></AtomChip>
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
      <RichFittedCard>
        <:avatar><Mark @text='Sb' /></:avatar>
        <:title>{{headline @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Dot @hue={{this.hue}}>{{lower
              @model.statusLabel
            }}</Dot></:status>
        <:fact>Grade {{gradeLetter @model}} · {{gradeFact @model}}</:fact>
        <:relations>{{#if @model.enrollment}}<@fields.enrollment
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.assignment}}<@fields.assignment
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
    </template>
  };
}

function headline(m?: Partial<Submission> | null): string {
  return m?.cardTitle ?? 'Submission';
}
function metaLine(m?: Partial<Submission> | null): string {
  let what = (m?.assignment as any)?.title ?? m?.assignmentTitle ?? '';
  let when = m?.submittedAt
    ? `submitted ${fmtShort(m.submittedAt)}`
    : 'not handed in';
  return [what, when].filter(Boolean).join(' · ');
}
function lateLabel(m?: Partial<Submission> | null): string {
  return m?.isLate ? `${m.daysLate} days late` : 'on time';
}
function dueLine(m?: Partial<Submission> | null): string {
  let due = (m?.assignment as any)?.dueWindow?.dueAt;
  return due ? `due ${fmtShort(due)}` : 'no due date';
}
function gradeLetter(m?: Partial<Submission> | null): string {
  return (m?.grade as any)?.letter || '—';
}
function gradeShort(m?: Partial<Submission> | null): string {
  let g = m?.grade as any;
  if (!g) return '—';
  return [g.letter, g.total != null ? `${g.total} / ${g.maxPoints ?? '—'}` : '']
    .filter(Boolean)
    .join(' · ');
}
function gradeLine(m?: Partial<Submission> | null): string {
  let g = m?.grade as any;
  if (!g || g.total == null) return 'not graded';
  return `${g.total} / ${g.maxPoints ?? '—'}${g.pct != null ? ` · ${g.pct}%` : ''}`;
}
function gradeFact(m?: Partial<Submission> | null): string {
  let g = m?.grade as any;
  if (!g || g.total == null) return 'not graded';
  return [`${g.total} / ${g.maxPoints ?? '—'}`, g.graderName]
    .filter(Boolean)
    .join(' · ');
}
function fmtShort(d: Date | string): string {
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}
function fmtDay(d?: Date | string | null): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}
function dash(v: unknown): string {
  return v == null || v === '' ? '—' : String(v);
}
function lower(v?: string | null) {
  return (v ?? '').toLowerCase();
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

export default Submission;
