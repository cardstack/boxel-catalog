import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { realmURL } from '@cardstack/runtime-common';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { Switch } from '@cardstack/pretui/components/switch';
import { Textarea } from '@cardstack/pretui/components/textarea';

import GradeSubmissionCommand, {
  GradePickField,
} from '../commands/grade-submission-command';
import { latePenalty } from '../late-policy-field';
import { letterFor } from '../grade-scale-field';
import { round1 } from '../rubric-criterion-field';

interface Signature {
  Args: {
    submission: any;
    context?: any;
    gradedBy?: any;
    onGraded?: (message: string) => void;
  };
  Element: HTMLElement;
}

interface Pick {
  levelLabel?: string;
  comment?: string;
}

/**
 * Grading as a grid, not a form: every criterion is a row, every level a
 * button in that row, and the running total re-prices as you click. Late
 * deduction is shown up front with a waive switch; the letter updates live
 * against the course scale. Writes through Grade Submission and surfaces its
 * refusal text verbatim (an unpicked criterion, a missing rubric).
 */
export class RubricGrader extends GlimmerComponent<Signature> {
  @tracked picks: Record<string, Pick> = {};
  @tracked feedback = '';
  @tracked waive = false;
  @tracked overrideText = '';
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked done: string | undefined;

  get assignment() {
    return this.args.submission?.assignment;
  }
  get rubric() {
    return this.assignment?.rubric;
  }
  get criteria(): any[] {
    return (this.rubric?.criteria ?? []).filter(Boolean);
  }
  get course() {
    return this.args.submission?.enrollment?.cohort?.course;
  }
  get late() {
    return latePenalty(
      this.course?.latePolicy,
      this.assignment?.dueWindow?.dueAt,
      this.args.submission?.submittedAt,
    );
  }
  get maxPoints(): number {
    return this.assignment?.effectiveMaxPoints ?? this.rubric?.totalPoints ?? 0;
  }
  get pickedCount() {
    return this.criteria.filter((c) => this.picks[c.name]?.levelLabel).length;
  }
  get allPicked() {
    return (
      this.criteria.length > 0 && this.pickedCount === this.criteria.length
    );
  }
  get raw(): number {
    return round1(
      this.criteria.reduce((n, c) => {
        let lvl = (c.levels ?? []).find(
          (l: any) => l?.label === this.picks[c.name]?.levelLabel,
        );
        return n + (lvl ? (lvl.points ?? 0) * (c.weight ?? 1) : 0);
      }, 0),
    );
  }
  get penaltyPct() {
    return this.waive ? 0 : this.late.penaltyPct;
  }
  get override(): number | undefined {
    let n = parseFloat(this.overrideText);
    return Number.isFinite(n) ? n : undefined;
  }
  get total(): number {
    if (this.override != null) return round1(this.override);
    return round1(this.raw * (1 - this.penaltyPct / 100));
  }
  get pct() {
    return this.maxPoints ? Math.round((this.total / this.maxPoints) * 100) : 0;
  }
  get letter() {
    return letterFor(this.pct, this.course?.gradeScale);
  }
  get canGrade() {
    return this.args.submission?.submissionStatus === 'submitted';
  }
  get statusNote() {
    let s = this.args.submission?.submissionStatus;
    if (s === 'graded') return 'This version is already graded.';
    if (s === 'returned')
      return 'This version was returned; wait for the next submission.';
    if (s === 'not_submitted') return 'Nothing has been handed in yet.';
    return undefined;
  }

  isPicked = (c: any, lvl: any) => this.picks[c.name]?.levelLabel === lvl.label;
  pick = (c: any, lvl: any) => {
    this.picks = {
      ...this.picks,
      [c.name]: { ...this.picks[c.name], levelLabel: lvl.label },
    };
  };
  setComment = (c: any, value: string) => {
    this.picks = {
      ...this.picks,
      [c.name]: { ...this.picks[c.name], comment: value },
    };
  };
  setFeedback = (v: string) => (this.feedback = v);
  setOverride = (v: string) => (this.overrideText = v);
  toggleWaive = (checked: boolean) => (this.waive = checked);
  levelPoints = (c: any, lvl: any) =>
    round1((lvl.points ?? 0) * (c.weight ?? 1));

  run = async (returnForRevision: boolean) => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    let realm = this.args.submission?.[realmURL]?.href;
    if (!realm) {
      this.error = 'Could not determine the realm';
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      let res = (await new GradeSubmissionCommand(ctx).execute({
        submission: this.args.submission,
        gradedBy: this.args.gradedBy,
        picks: this.criteria.map(
          (c) =>
            new GradePickField({
              criterionName: c.name,
              levelLabel: this.picks[c.name]?.levelLabel ?? '',
              comment: this.picks[c.name]?.comment ?? '',
            }),
        ),
        feedback: this.feedback || undefined,
        waiveLatePenalty: this.waive,
        overridePoints: this.override,
        returnForRevision,
        realm,
      } as any)) as any;
      this.done = res?.message ?? 'Done';
      this.args.onGraded?.(this.done!);
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  grade = () => this.run(false);
  sendBack = () => this.run(true);

  <template>
    <section class='grader' ...attributes>
      <header class='head'>
        <div>
          <span class='eyebrow'>{{@submission.assignmentTitle}}
            · v{{if @submission.version @submission.version 1}}</span>
          <h2>{{if
              @submission.learnerName
              @submission.learnerName
              'Learner'
            }}</h2>
          <p class='sub'>
            {{#if @submission.submittedAt}}Handed in
              {{fmt @submission.submittedAt}}{{/if}}
            {{#if this.late.daysLate}}<span class='late'>
                ·
                {{this.late.daysLate}}d late, −{{this.late.penaltyPct}}%</span>{{/if}}
          </p>
        </div>
        <div class='total'>
          <span class='total-n'>{{this.total}}<span
              class='of'
            >/{{this.maxPoints}}</span></span>
          <span class='total-l'>{{if this.letter this.letter '—'}}
            ·
            {{this.pct}}%</span>
        </div>
      </header>

      {{#if this.done}}
        <Alert @tone='success'>{{this.done}}</Alert>
      {{else if this.statusNote}}
        <p class='note'>{{this.statusNote}}</p>
      {{else if (not this.rubric)}}
        <Alert @tone='warning' @title='No rubric'>Link a rubric to this
          assignment before grading it.</Alert>
      {{else}}
        <ol class='crits'>
          {{#each this.criteria as |c|}}
            <li class='crit'>
              <div class='crit-head'>
                <span class='crit-name'>{{c.name}}</span>
                <span class='crit-max'>{{c.maxPoints}}
                  pts{{#if (weighted c.weight)}} · ×{{c.weight}}{{/if}}</span>
              </div>
              <div
                class='levels'
                role='radiogroup'
                aria-label='{{c.name}} level'
              >
                {{#each (sortedLevels c) as |lvl|}}
                  <button
                    type='button'
                    class='lvl {{if (this.isPicked c lvl) "picked"}}'
                    role='radio'
                    aria-checked={{if (this.isPicked c lvl) 'true' 'false'}}
                    title={{lvl.descriptor}}
                    {{on 'click' (fn this.pick c lvl)}}
                  >
                    <span class='lvl-label'>{{lvl.label}}</span>
                    <span class='lvl-pts'>{{this.levelPoints c lvl}}</span>
                    {{#if lvl.descriptor}}<span
                        class='lvl-desc'
                      >{{lvl.descriptor}}</span>{{/if}}
                  </button>
                {{/each}}
              </div>
              <Input
                class='comment'
                @value={{get this.picks c.name 'comment'}}
                @onInput={{fn this.setComment c}}
                @placeholder='Comment on {{c.name}} (optional)'
                aria-label='Comment on {{c.name}}'
              />
            </li>
          {{/each}}
        </ol>

        <div class='controls'>
          <label class='ctl'>
            <span class='ctl-l'>Feedback to learner</span>
            <Textarea
              @value={{this.feedback}}
              @onInput={{this.setFeedback}}
              @placeholder='What was strong, what to fix next time'
            />
          </label>
          <div class='ctl-row'>
            {{#if this.late.penaltyPct}}
              <label class='switch'>
                <Switch
                  @checked={{this.waive}}
                  @onCheckedChange={{this.toggleWaive}}
                  aria-label='Waive late penalty'
                />
                <span>Waive −{{this.late.penaltyPct}}% late penalty</span>
              </label>
            {{/if}}
            <label class='ctl small'>
              <span class='ctl-l'>Override total (optional)</span>
              <Input
                @type='number'
                @value={{this.overrideText}}
                @onInput={{this.setOverride}}
                @placeholder='e.g. 72'
              />
            </label>
          </div>
          {{#if this.error}}<Alert @tone='danger'>{{this.error}}</Alert>{{/if}}
          <div class='actions'>
            <span class='count'>{{this.pickedCount}}
              of
              {{this.criteria.length}}
              criteria scored</span>
            <Button
              class='cta'
              @tone='neutral'
              @appearance='outlined'
              @disabled={{this.busy}}
              {{on 'click' this.sendBack}}
            >Return for revision</Button>
            <Button
              class='cta'
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              @disabled={{or this.busy (not this.allPicked)}}
              {{on 'click' this.grade}}
            >Save grade</Button>
          </div>
        </div>
      {{/if}}
    </section>
    <style scoped>
      .cta {
        min-height: 2.75rem;
      }
      .grader {
        display: grid;
        gap: var(--boxel-sp);
        color: var(--foreground);
      }
      .head {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: var(--boxel-sp);
      }
      .eyebrow {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      h2 {
        margin: var(--boxel-sp-4xs) 0 0;
        font: 700 var(--boxel-font-size-lg) var(--font-sans);
      }
      .sub {
        margin: var(--boxel-sp-4xs) 0 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .late {
        color: var(--warning-ink);
        font-weight: 600;
      }
      .total {
        flex: none;
        display: grid;
        justify-items: end;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-radius: var(--radius);
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
      }
      .total-n {
        font-size: var(--boxel-font-size-xl);
        font-weight: 800;
        font-variant-numeric: tabular-nums;
        line-height: 1;
      }
      .of {
        font-size: var(--boxel-font-size-sm);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .total-l {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .crits {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .crit {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .crit-head {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
      }
      .crit-name {
        font-weight: 700;
      }
      .crit-max {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .levels {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: var(--boxel-sp-4xs);
      }
      .lvl {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 0 var(--boxel-sp-xs);
        text-align: start;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: inherit;
        font: inherit;
        cursor: pointer;
        transition:
          border-color 120ms ease,
          background 120ms ease;
      }
      .lvl:hover {
        border-color: var(--primary);
      }
      .lvl:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .lvl.picked {
        border-color: var(--primary);
        background: color-mix(in oklab, var(--primary) 12%, var(--card));
      }
      .lvl-label {
        font-weight: 600;
        font-size: var(--boxel-font-size-sm);
      }
      .lvl-pts {
        font-variant-numeric: tabular-nums;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .lvl-desc {
        grid-column: 1 / -1;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .controls {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .ctl {
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .ctl.small {
        max-width: 12rem;
      }
      .ctl-l {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .ctl-row {
        display: flex;
        gap: var(--boxel-sp);
        align-items: flex-end;
        flex-wrap: wrap;
      }
      .switch {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
        align-items: center;
        font-size: var(--boxel-font-size-sm);
      }
      .actions {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
        justify-content: flex-end;
      }
      .count {
        margin-right: auto;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .note {
        margin: 0;
        color: var(--muted-foreground);
        font-style: italic;
      }
    </style>
  </template>
}

function sortedLevels(c: any) {
  return ((c?.levels ?? []) as any[])
    .filter((l) => l?.label)
    .slice()
    .sort((a, b) => (b.points ?? 0) - (a.points ?? 0));
}
function weighted(w?: number) {
  return w != null && w !== 1;
}
function get(map: Record<string, Pick>, key: string, prop: keyof Pick) {
  return map[key]?.[prop] ?? '';
}
function fmt(d?: Date | string | null) {
  if (!d) return '';
  return new Date(d).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}
function not(v: unknown) {
  return !v;
}
function or(...v: unknown[]) {
  return v.some(Boolean);
}

export default RubricGrader;
