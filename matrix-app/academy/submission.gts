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
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  SubmissionStatusField,
  SUBMISSION_STATUSES,
} from './submission-status-field';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
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
    get lateChip() {
      return lateLabel(this.args.model);
    }
    get subtitle() {
      return subtitleOf(this.args.model);
    }
    get details(): KeyValueItem[] {
      return detailsOf(this.args.model);
    }
    get gradeLine() {
      return gradeLineOf(this.args.model?.grade);
    }
    <template>
      <article class='submission'>
        <header class='iso-head'>
          <Avatar
            @name='S b'
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.cardTitle}}</h1>
            <p class='iso-sub'>{{this.subtitle}}</p>
          </div>
          <div class='iso-chips'>
            <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            <StatePill
              @label={{this.lateChip}}
              @hue={{if @model.isLate 'amber' 'slate'}}
            />
          </div>
        </header>

        <div class='stat-row'>
          <Stat
            @label='Grade'
            @value={{if @model.grade.letter @model.grade.letter '—'}}
            @hint={{this.gradeLine}}
            @roll={{false}}
          />
          <Stat
            @label='Version'
            @value='v{{if @model.version @model.version 1}}'
            @hint={{if
              @model.assignment.allowResubmission
              'resubmission allowed'
              'single attempt'
            }}
            @roll={{false}}
          />
          <Stat
            @label='Late'
            @value='{{@model.daysLate}} d'
            @hint={{@model.assignment.dueLabel}}
            @roll={{false}}
          />
        </div>

        <div class='iso-body'>
          <div class='iso-col'>
            <section class='iso-card'>
              <h2>Answer</h2>
              {{#if @model.text}}
                <@fields.text />
              {{else}}
                <p class='empty'>No written answer.</p>
              {{/if}}
            </section>
            {{#if @model.grade.criterionScores.length}}
              <section class='iso-card'>
                <h2>Rubric score</h2>
                <ul class='scores'>
                  {{#each @model.grade.criterionScores as |c|}}
                    <li>
                      <span class='score-name'>{{c.criterionName}}
                        ·
                        {{c.levelLabel}}</span>
                      <span class='score-pts'>{{c.points}}
                        /
                        {{c.maxPoints}}</span>
                      <ProgressBar
                        class='score-bar'
                        @value={{c.points}}
                        @max={{c.maxPoints}}
                        aria-label='{{c.criterionName}} score'
                      />
                    </li>
                  {{/each}}
                </ul>
              </section>
            {{/if}}
            {{#if @model.files.length}}
              <section class='iso-card'>
                <h2>Files</h2>
                <div class='stack'><@fields.files @format='embedded' /></div>
              </section>
            {{/if}}
          </div>
          <div class='iso-col'>
            <section class='iso-card'>
              <h2>Linked</h2>
              <dl class='rels'>
                <div><dt>Enrollment</dt><dd>{{#if
                      @model.enrollment
                    }}<@fields.enrollment
                        @format='atom'
                      />{{else}}—{{/if}}</dd></div>
                <div><dt>Assignment</dt><dd>{{#if
                      @model.assignment
                    }}<@fields.assignment
                        @format='atom'
                      />{{else}}—{{/if}}</dd></div>
                <div><dt>Grade</dt><dd>{{#if @model.grade}}<@fields.grade
                        @format='atom'
                      />{{else}}—{{/if}}</dd></div>
              </dl>
            </section>
            <section class='iso-card'>
              <h2>Details</h2>
              <KeyValue @items={{this.details}} @rows='ruled' />
            </section>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .submission {
            max-width: 60rem;
            margin: 0 auto;
            container-type: inline-size;
            padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
            display: grid;
            gap: var(--boxel-sp-lg);
            color: var(--foreground);
            background: var(--background);
          }
          .iso-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 14rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-xl);
            font-weight: 600;
            line-height: 1.25;
          }
          .iso-sub {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(16rem, 1fr);
            gap: var(--boxel-sp-lg);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .iso-card {
            padding: var(--boxel-sp-lg);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
            line-height: 1.6;
            min-width: 0;
          }
          h2 {
            margin: 0 0 var(--boxel-sp);
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .stack {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .empty {
            margin: 0;
            color: var(--muted-foreground);
            font-style: italic;
          }
          .scores {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .scores li {
            display: grid;
            grid-template-columns: minmax(0, 1fr) auto;
            gap: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          }
          .score-pts {
            font-variant-numeric: tabular-nums;
            font-weight: 600;
          }
          .score-bar {
            grid-column: 1 / -1;
          }
          .rels {
            margin: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .rels div {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .rels dt {
            min-width: 5.5rem;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .rels dd {
            margin: 0;
            min-width: 0;
          }
          @container (width <= 43.75rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
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
    get lateChip() {
      return lateLabel(this.args.model);
    }
    get subtitle() {
      return subtitleOf(this.args.model);
    }
    get details(): KeyValueItem[] {
      return detailsOf(this.args.model);
    }
    get gradeLine() {
      let g = gradeLineOf(this.args.model?.grade);
      return g ? `Grade ${this.args.model?.grade?.letter ?? ''} · ${g}` : '';
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar
            @name='S b'
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          />
          <div class='emb-id'>
            <h4 class='emb-title'>{{@model.cardTitle}}</h4>
            <p class='emb-sub'>{{this.subtitle}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
            <StatePill
              @label={{this.lateChip}}
              @hue={{if @model.isLate 'amber' 'slate'}}
            />
          </div>
        </header>
        {{#if this.gradeLine}}<p class='emb-fact'>{{this.gradeLine}}</p>{{/if}}
        <dl class='emb-kv'>
          {{#each this.details as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if @model.enrollment}}<span class='emb-rel'>Enrollment
              <@fields.enrollment @format='atom' /></span>{{/if}}
          {{#if @model.assignment}}<span class='emb-rel'>Assignment
              <@fields.assignment @format='atom' /></span>{{/if}}
          {{#if @model.grade}}<span class='emb-rel'>Grade
              <@fields.grade @format='atom' /></span>{{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            color: var(--muted-foreground);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
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
      <span class='submission-atom'>
        <Avatar
          @name='S b'
          @hue='var(--muted-foreground)'
          @size={{20}}
          aria-hidden='true'
        />
        <span class='submission-atom-name'>{{@model.cardTitle}}</span>
        {{#if @model.submissionStatus}}<span
            class='submission-atom-chip'
          ><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .submission-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .submission-atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .submission-atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(
        SubmissionStatusField,
        this.args.model?.submissionStatus,
      );
    }
    get lateChip() {
      return lateLabel(this.args.model);
    }
    get subtitle() {
      return subtitleOf(this.args.model);
    }
    // never empty: FitTile reserves a row for a rendered fact slot
    get fact() {
      let g = gradeLineOf(this.args.model?.grade);
      return g
        ? `Grade ${this.args.model?.grade?.letter ?? ''} · ${g}`
        : 'Not graded yet';
    }
    get facts(): KeyValueItem[] {
      return detailsOf(this.args.model).filter((f) =>
        ['Assignment', 'Submitted', 'Due', 'Late'].includes(f.key),
      );
    }
    get relations() {
      let m = this.args.model;
      return [
        m?.enrollment ? 'Enrollment' : '',
        m?.assignment ? 'Assignment' : '',
        m?.grade ? 'Grade' : '',
      ].filter(Boolean);
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='S b'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.cardTitle}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>
              <StatePill @label={{@model.statusLabel}} @hue={{this.hue}} />
              <StatePill
                @label={{this.lateChip}}
                @hue={{if @model.isLate 'amber' 'slate'}}
              />
            </:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Enrollment')}}
            <@fields.enrollment @format='atom' />
          {{else if (eq label 'Assignment')}}
            <@fields.assignment @format='atom' />
          {{else}}
            <@fields.grade @format='atom' />
          {{/if}}
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };
}

function subtitleOf(s: Partial<Submission> | null | undefined): string {
  let when = s?.submittedAt ? `submitted ${fmtDay(s.submittedAt)}` : '';
  return [s?.assignmentTitle, when || 'not handed in']
    .filter(Boolean)
    .join(' · ');
}

function lateLabel(s: Partial<Submission> | null | undefined): string {
  let d = s?.daysLate ?? 0;
  return d > 0 ? `${d}d late` : 'on time';
}

function gradeLineOf(g: any): string {
  if (!g || g.total == null) return '';
  return `${g.total} / ${g.maxPoints ?? '—'}`;
}

function detailsOf(s: Partial<Submission> | null | undefined): KeyValueItem[] {
  let a = s?.assignment as any;
  let g = s?.grade as any;
  return [
    { key: 'Assignment', value: s?.assignmentTitle || '—' },
    { key: 'Version', value: String(s?.version ?? 1) },
    { key: 'Submitted', value: s?.submittedAt ? fmtDay(s.submittedAt) : '—' },
    {
      key: 'Due',
      value: a?.dueWindow?.dueAt ? fmtDay(a.dueWindow.dueAt) : '—',
    },
    { key: 'Late', value: s?.isLate ? `${s.daysLate} d` : 'no' },
    {
      key: 'Grade',
      value: g?.letter ? `${g.letter} · ${gradeLineOf(g)}` : 'not graded',
    },
  ];
}

export function fmtDay(d?: Date | string | null): string {
  if (!d) return '';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
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
