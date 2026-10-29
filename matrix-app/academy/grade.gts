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
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  AcademyRel,
  AcademyRels,
  type FormatFact,
} from './components/card-formats';
import { Submission } from './submission';
import { Employee } from '../hr/employee';
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
    get subtitle() {
      let m = this.args.model;
      return [m?.assignmentTitle, m?.graderName && `by ${m.graderName}`]
        .filter(Boolean)
        .join(' · ');
    }
    get lateHint() {
      let p = this.args.model?.penaltyPct;
      return p ? `−${p}% applied` : 'no deduction';
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Graded', value: fmtDate(m?.gradedAt) || '—' },
        {
          key: 'Raw total',
          value: `${m?.rawTotal ?? 0} / ${m?.maxPoints ?? 0}`,
        },
        {
          key: 'Late penalty',
          value: m?.penaltyPct ? `−${m.penaltyPct}% (${m.daysLate}d)` : 'None',
        },
        {
          key: 'Override',
          value: m?.overridePoints ? String(m.overridePoints) : 'None',
        },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='Gr'
        @title={{@model.cardTitle}}
        @subtitle={{this.subtitle}}
      >
        <:chips>
          <StatePill
            @label={{if @model.letter @model.letter '—'}}
            @hue='slate'
          />
          <StatePill
            @label={{if @model.penaltyPct 'late penalty' 'on time'}}
            @hue={{if @model.penaltyPct 'amber' 'slate'}}
          />
        </:chips>
        <:stats>
          <Stat
            @label='Points'
            @value='{{@model.total}} / {{@model.maxPoints}}'
            @hint='after penalty and override'
            @roll={{false}}
          />
          <Stat
            @label='Percent'
            @value='{{@model.pct}}%'
            @hint={{if @model.letter @model.letter 'no letter'}}
            @roll={{false}}
          />
          <Stat
            @label='Late'
            @value='{{@model.daysLate}} d'
            @hint={{this.lateHint}}
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Rubric score'>
            {{#if @model.criterionScores.length}}
              <div class='stack'>{{#each @fields.criterionScores as |Cs|}}<Cs
                  />{{/each}}</div>
              <div class='sum'><span>Raw total</span><span>{{@model.rawTotal}}
                  /
                  {{@model.maxPoints}}</span></div>
            {{else}}
              <p class='empty'>No criterion scores recorded.</p>
            {{/if}}
          </AcademyPanel>
          <AcademyPanel @title='Feedback'>
            {{#if @model.feedback.content}}<@fields.feedback />{{else}}<p
                class='empty'
              >No written feedback.</p>{{/if}}
          </AcademyPanel>
        </:main>
        <:side>
          <AcademyPanel @title='Linked'>
            <AcademyRels>
              <AcademyRel @label='Submission'>{{#if
                  @model.submission
                }}<@fields.submission
                    @format='atom'
                  />{{else}}—{{/if}}</AcademyRel>
              <AcademyRel @label='Graded by'>{{#if
                  @model.gradedBy
                }}<@fields.gradedBy
                    @format='atom'
                  />{{else}}—{{/if}}</AcademyRel>
            </AcademyRels>
          </AcademyPanel>
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
      <style scoped>
        @layer PretComponent {
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
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Score', value: `${m?.total ?? 0} / ${m?.maxPoints ?? 0}` },
        { key: 'Percent', value: `${m?.pct ?? 0}%` },
        { key: 'Graded by', value: m?.graderName || '—' },
        { key: 'Graded', value: fmtDate(m?.gradedAt) || '—' },
        {
          key: 'Late penalty',
          value: m?.penaltyPct ? `−${m.penaltyPct}%` : 'None',
        },
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='Gr'
        @title={{if @model.learnerName @model.learnerName 'Learner'}}
        @subtitle={{@model.assignmentTitle}}
        @facts={{this.facts}}
      >
        <:chips><StatePill
            @label={{if @model.letter @model.letter '—'}}
            @hue='slate'
          /></:chips>
        <:relations>
          {{#if @model.submission}}<span>Submission
              <@fields.submission @format='atom' /></span>{{/if}}
        </:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AcademyAtom
        @mark='Gr'
        @name={{if @model.learnerName @model.learnerName @model.cardTitle}}
      >
        <StatePill @label={{if @model.letter @model.letter '—'}} @hue='slate' />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get fact() {
      let m = this.args.model;
      return `${m?.total ?? 0} / ${m?.maxPoints ?? 0} · ${m?.pct ?? 0}%`;
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Graded by', value: m?.graderName || '—' },
        { key: 'Graded', value: fmtDate(m?.gradedAt) || '—' },
        {
          key: 'Late penalty',
          value: m?.penaltyPct ? `−${m.penaltyPct}%` : 'None',
        },
      ];
    }
    get relations() {
      return this.args.model?.submission ? ['Submission'] : [];
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Gr'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span class='fit-title' role='heading' aria-level='3'>{{if
                  @model.learnerName
                  @model.learnerName
                  'Learner'
                }}</span></:title>
            <:subtitle>{{@model.assignmentTitle}}</:subtitle>
            <:status><StatePill
                @label={{if @model.letter @model.letter '—'}}
                @hue='slate'
              /></:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation><@fields.submission @format='atom' /></:relation>
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
