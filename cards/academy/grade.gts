import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import PercentageField from '@cardstack/base/percentage';
import { RichMarkdownField } from '@cardstack/base/rich-markdown';
import AwardIcon from '@cardstack/boxel-icons/award';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import { Submission } from './submission';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { round1 } from './rubric-criterion-field';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';

/** The grader's pick for one rubric criterion. */
export class CriterionScoreField extends FieldDef {
  static displayName = 'Criterion Score';
  @field criterionName = contains(StringField);
  @field levelLabel = contains(StringField);
  @field points = contains(NumberField);
  @field maxPoints = contains(NumberField);
  @field comment = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='cs'>
        <span class='cs-name'>{{@model.criterionName}}</span>
        <span class='cs-level'>{{@model.levelLabel}}</span>
        <span class='cs-pts'>{{@model.points}}<span
            class='cs-max'
          >/{{@model.maxPoints}}</span></span>
        {{#if @model.comment}}<span
            class='cs-comment'
          >{{@model.comment}}</span>{{/if}}
      </div>
      <style scoped>
        .cs {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: 0 var(--boxel-sp-xs);
          align-items: baseline;
          font-size: var(--boxel-font-size-sm);
        }
        .cs-name {
          font-weight: 600;
        }
        .cs-level {
          color: var(--muted-foreground);
        }
        .cs-pts {
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
        .cs-max {
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .cs-comment {
          grid-column: 1 / -1;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

/**
 * The grader's decision on one submission. Criterion scores, the late
 * deduction actually applied, an optional override, and written feedback.
 *
 * Snapshots by design: `maxPoints` and `letter` are written by Grade
 * Submission at grading time. A grade is a record of what was awarded under
 * the scale in force that day — re-lettering history when a course changes
 * its scale would be wrong, so these two are stored rather than derived.
 * `total` and `pct` ARE derived (from the stored parts) so an override or a
 * waived penalty re-totals instantly.
 */
export class Grade extends CardDef {
  static displayName = 'Grade';
  static icon = AwardIcon;

  @field submission = linksTo(() => Submission);
  @field gradedBy = linksTo(() => Employee);
  @field gradedAt = contains(DateTimeField);
  @field criterionScores = containsMany(CriterionScoreField);
  @field maxPoints = contains(NumberField);
  @field daysLate = contains(NumberField);
  @field penaltyPct = contains(PercentageField, {
    description: 'Deduction applied. Set to 0 to waive.',
  });
  @field overridePoints = contains(NumberField, {
    description: 'When set, replaces the computed total.',
  });
  @field letter = contains(StringField);
  @field feedback = contains(RichMarkdownField);

  @field rawTotal = contains(NumberField, {
    computeVia: function (this: Grade): number {
      return rawTotalOf(this);
    },
  });
  @field total = contains(NumberField, {
    computeVia: function (this: Grade): number {
      return totalOf(this);
    },
  });
  @field pct = contains(PercentageField, {
    computeVia: function (this: Grade): number {
      return pctOf(this);
    },
  });
  @field learnerName = contains(StringField, {
    computeVia: function (this: Grade) {
      return this.submission?.learnerName ?? '';
    },
  });
  @field assignmentTitle = contains(StringField, {
    computeVia: function (this: Grade) {
      return this.submission?.assignmentTitle ?? '';
    },
  });
  @field graderName = contains(StringField, {
    computeVia: function (this: Grade) {
      return this.gradedBy?.name ?? '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Grade): string {
      let who = this.submission?.learnerName ?? 'Learner';
      let what = this.submission?.assignmentTitle ?? 'assignment';
      return `${who} · ${what} · ${this.letter ?? this.total ?? '—'}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='grade'>
        <header class='hero'>
          <div class='letter-box'>
            <span class='letter'>{{if @model.letter @model.letter '—'}}</span>
            <span class='pct'>{{@model.pct}}%</span>
          </div>
          <div class='hero-text'>
            <span class='eyebrow'>Grade ·
              {{#if @model.submission}}<@fields.submission
                  @format='atom'
                />{{/if}}</span>
            <h1>{{@model.total}}
              <span class='of'>/ {{@model.maxPoints}} points</span></h1>
            <p class='meta'>
              {{#if @model.graderName}}<span>by
                  {{@model.graderName}}</span>{{/if}}
              {{#if @model.gradedAt}}<span>{{fmtDate
                    @model.gradedAt
                  }}</span>{{/if}}
              {{#if @model.penaltyPct}}<span class='pen'>−{{@model.penaltyPct}}%
                  late ({{@model.daysLate}}d)</span>{{/if}}
              {{#if @model.overridePoints}}<span class='pen'>override applied</span>{{/if}}
            </p>
          </div>
        </header>
        <section class='panel'>
          <h2>Rubric</h2>
          {{#if @model.criterionScores.length}}
            <div class='stack'>{{#each @fields.criterionScores as |Cs|}}<Cs
                />{{/each}}</div>
            <div class='sum'><span>Raw total</span><span>{{@model.rawTotal}}
                /
                {{@model.maxPoints}}</span></div>
          {{else}}
            <p class='empty'>No criterion scores recorded.</p>
          {{/if}}
        </section>
        <section class='panel'>
          <h2>Feedback</h2>
          {{#if @model.feedback}}<@fields.feedback />{{else}}<p class='empty'>No
              written feedback.</p>{{/if}}
        </section>
      </article>
      <style scoped>
        .grade {
          max-width: 48rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp);
          align-items: center;
        }
        .letter-box {
          width: 5rem;
          height: 5rem;
          display: grid;
          place-content: center;
          justify-items: center;
          border-radius: var(--radius);
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
        }
        .letter {
          font: 800 2.25rem / 1 var(--font-sans);
        }
        .pct {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15 var(--font-sans);
          font-variant-numeric: tabular-nums;
        }
        .of {
          font-size: var(--boxel-font-size);
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .pen {
          color: var(--warning-ink);
          font-weight: 600;
        }
        .panel {
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          line-height: 1.6;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .stack {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .sum {
          margin-top: var(--boxel-sp-xs);
          padding-top: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
          display: flex;
          justify-content: space-between;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground);
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='letter'>{{if @model.letter @model.letter '—'}}</span>
        <div class='text'>
          <span class='title'>{{@model.total}}
            /
            {{@model.maxPoints}}
            <span class='pct'>({{@model.pct}}%)</span></span>
          <span class='sub'>{{#if @model.graderName}}{{@model.graderName}}
              ·
            {{/if}}{{fmtDate @model.gradedAt}}{{#if @model.penaltyPct}}
              · −{{@model.penaltyPct}}% late{{/if}}</span>
        </div>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .letter {
          width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font: 800 var(--boxel-font-size) var(--font-sans);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .pct {
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><b>{{if @model.letter @model.letter '—'}}</b>
        {{@model.total}}/{{@model.maxPoints}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'context', label: 'Context' },
      { id: 'scores', label: 'Scores' },
      { id: 'adjust', label: 'Adjustments' },
      { id: 'feedback', label: 'Feedback' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Grade sections'
        as |e|
      >
        <e.Section
          @id='context'
          @title='Context'
          @hint='normally written by Grade Submission'
          @cols={{2}}
        >
          <FieldContainer
            @label='Submission'
            @vertical={{true}}
          ><@fields.submission /></FieldContainer>
          <FieldContainer
            @label='Graded by'
            @vertical={{true}}
          ><@fields.gradedBy /></FieldContainer>
          <FieldContainer
            @label='Graded at'
            @vertical={{true}}
          ><@fields.gradedAt /></FieldContainer>
          <FieldContainer
            @label='Max points'
            @vertical={{true}}
          ><@fields.maxPoints /></FieldContainer>
        </e.Section>
        <e.Section @id='scores' @title='Scores' @cols={{1}}>
          <FieldContainer
            @label='Criterion scores'
            @vertical={{true}}
          ><@fields.criterionScores /></FieldContainer>
        </e.Section>
        <e.Section
          @id='adjust'
          @title='Adjustments'
          @hint='set penalty to 0 to waive'
          @cols={{4}}
        >
          <FieldContainer
            @label='Days late'
            @vertical={{true}}
          ><@fields.daysLate /></FieldContainer>
          <FieldContainer
            @label='Penalty %'
            @vertical={{true}}
          ><@fields.penaltyPct /></FieldContainer>
          <FieldContainer
            @label='Override points'
            @vertical={{true}}
          ><@fields.overridePoints /></FieldContainer>
          <FieldContainer @label='Letter' @vertical={{true}}><@fields.letter
            /></FieldContainer>
        </e.Section>
        <e.Section @id='feedback' @title='Feedback' @cols={{1}}>
          <FieldContainer
            @label='Feedback to learner'
            @vertical={{true}}
          ><@fields.feedback /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>{{@model.assignmentTitle}}</:eyebrow>
        <:title>{{if @model.learnerName @model.learnerName 'Learner'}}</:title>
        <:subtitle>{{@model.total}}
          /
          {{@model.maxPoints}}
          ·
          {{@model.pct}}%{{#if @model.penaltyPct}}
            · −{{@model.penaltyPct}}% late{{/if}}</:subtitle>
        <:badgeRight><StatePill
            @label={{if @model.letter @model.letter '—'}}
            @hue='slate'
          /></:badgeRight>
        <:footer>{{#if @model.graderName}}{{@model.graderName}}
            ·
          {{/if}}{{fmtDate @model.gradedAt}}</:footer>
      </FittedCard>
    </template>
  };
}

export function rawTotalOf(g: Partial<Grade> | null | undefined): number {
  return round1(
    (g?.criterionScores ?? []).reduce(
      (n: number, c: any) => n + (c?.points ?? 0),
      0,
    ),
  );
}

export function totalOf(g: Partial<Grade> | null | undefined): number {
  if (g?.overridePoints != null) return round1(g.overridePoints);
  let raw = rawTotalOf(g);
  let pen = g?.penaltyPct ?? 0;
  return round1(raw * (1 - Math.min(100, Math.max(0, pen)) / 100));
}

export function pctOf(g: Partial<Grade> | null | undefined): number {
  let max = g?.maxPoints ?? 0;
  if (!max) return 0;
  return Math.round((totalOf(g) / max) * 100);
}

function fmtDate(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}

export default Grade;
