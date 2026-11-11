import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateTimeField from 'https://cardstack.com/base/datetime';
import MarkdownField from 'https://cardstack.com/base/markdown';
import enumField from 'https://cardstack.com/base/enum';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { DotLabel } from './dot-enum-field';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import type { PretuiTone } from '@cardstack/pretui/pretui-primitives';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from './duration-field';
import {
  InterviewRoundField,
  INTERVIEW_ROUND_LABELS,
} from './interview-round-field';
import { ScorecardField, RECOMMENDATION_LABELS } from './scorecard-field';
import { Employee } from './employee';
import { Candidate } from './candidate';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { liveCount } from './utils';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetEmpty,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';

// ── Shared reads ─────────────────────────────────────────────────────────
// Every format shows the same chips, byline and facts, so they are derived
// once here from the model rather than per format.

type MeetingModel = Partial<Meeting> | undefined;

// A recommendation is a verdict, so it reads the status tones: both votes to
// hire are success, the votes against warning and danger.
const RECOMMENDATION_TONES: Record<string, PretuiTone> = {
  'strong-hire': 'success',
  hire: 'success',
  'no-hire': 'warning',
  'strong-no-hire': 'danger',
};

const outOfFive = (value: number) => `${value} / 5`;

function formatWhen(date: Date, options: Intl.DateTimeFormatOptions) {
  return new Intl.DateTimeFormat('en-US', options).format(date);
}

function scoreStateOf(model: MeetingModel): ScoreState {
  if (typeof model?.interviewScore === 'number') {
    return 'scored';
  }
  let date = parseMeetingDate(model?.date);
  return date && date.getTime() < Date.now() ? 'awaiting' : 'upcoming';
}

// Over and unscored means the ball is in our court; that is the one state a
// scheduling card can surface on its own, from date + interviewScore.
// Only interviews are scored ('' for a standup or 1:1); an untyped meeting
// counts as an interview, as the seed data has one.
function scoreLabelOf(model: MeetingModel): string {
  if (model?.meetingType && model.meetingType !== 'interview') {
    return '';
  }
  let score = model?.interviewScore;
  if (typeof score === 'number') {
    return outOfFive(score);
  }
  return scoreStateOf(model) === 'awaiting'
    ? 'Score overdue'
    : 'Not yet scored';
}

function scoreToneOf(model: MeetingModel): PretuiTone {
  let score = model?.interviewScore;
  if (typeof score === 'number') {
    return score >= 4 ? 'success' : score >= 3 ? 'warning' : 'danger';
  }
  return scoreStateOf(model) === 'awaiting' ? 'danger' : 'neutral';
}

function recommendationToneOf(model: MeetingModel): PretuiTone {
  let value = model?.scorecard?.recommendation;
  return (value && RECOMMENDATION_TONES[value]) || 'neutral';
}

function recommendationOf(model: MeetingModel): string | undefined {
  let value = model?.scorecard?.recommendation;
  return value ? (RECOMMENDATION_LABELS[value] ?? value) : undefined;
}

// An unset duration is still a DurationField whose label is the '—'
// placeholder, so it counts only when it has a value.
function durationOf(model: MeetingModel): string | undefined {
  let duration = model?.duration;
  return duration?.value != null ? duration.label : undefined;
}

function roundOf(model: MeetingModel): string | undefined {
  let round = model?.roundType;
  return round ? (INTERVIEW_ROUND_LABELS[round] ?? round) : undefined;
}

// "Aug 4, 2026 · 10:00 AM · 60 min", only the parts that are set.
function bylineOf(model: MeetingModel): string {
  let date = parseMeetingDate(model?.date);
  return [
    date &&
      formatWhen(date, { month: 'short', day: 'numeric', year: 'numeric' }),
    date &&
      formatWhen(date, {
        hour: 'numeric',
        minute: '2-digit',
        hourCycle: 'h23',
      }),
    durationOf(model),
  ]
    .filter(Boolean)
    .join(' · ');
}

function factsOf(model: MeetingModel): DescriptionsItem[] {
  let date = parseMeetingDate(model?.date);
  let score = model?.interviewScore;
  let items: DescriptionsItem[] = [];
  let add = (label: string, value: string | undefined) => {
    if (value) {
      items.push({ label, value });
    }
  };
  add(
    'Date',
    date &&
      formatWhen(date, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hourCycle: 'h23',
      }),
  );
  add('Duration', durationOf(model));
  add('Round', roundOf(model));
  add('Score', typeof score === 'number' ? outOfFive(score) : undefined);
  for (let criterion of model?.scorecard?.criteria ?? []) {
    add(
      criterion?.name ?? '',
      typeof criterion?.score === 'number'
        ? outOfFive(criterion.score)
        : undefined,
    );
  }
  add('Interviewers', model?.interviewerTally || undefined);
  add('Type', model?.meetingType ?? undefined);
  return items;
}

// The record's type mark (a square, not a person): same one in every format.
const MeetingMark: TemplateOnlyComponent<{ Element: HTMLSpanElement }> =
  <template>
    <span class='meeting-mark' aria-hidden='true' ...attributes>Mt</span>
    <style scoped>
      @layer PretComponent {
        .meeting-mark {
          display: inline-grid;
          flex: none;
          place-items: center;
          inline-size: var(--meeting-mark-size, 2rem);
          block-size: var(--meeting-mark-size, 2rem);
          border-radius: calc(var(--radius) - 2px);
          background: var(--card);
          box-shadow: inset 0 0 0 1px var(--border);
          color: var(--primary-ink);
          font-size: var(--meeting-mark-font-size, var(--boxel-font-size-xs));
          font-weight: 600;
          line-height: 1;
        }
      }
    </style>
  </template>;

export const MEETING_TYPES = [
  'interview',
  'one-on-one',
  'standup',
  'vendor-review',
];

// Colocated with Meeting — the hue map colours the type badge, and
// `MEETING_TYPE_COLORS` below gives the embedded view's left border the same
// hue; it is also the shape components/calendar.gts takes as `@kindColors`.
// Harmonized with the Ledger
// identity: interview shares candidate.gts's "interviewing" plum, vendor
// review shares the brass seal color.
// Category hues only; the status hues follow the theme's status tokens.
export const MEETING_TYPE_HUES: Record<string, Hue> = {
  interview: 'purple',
  'one-on-one': 'teal',
  standup: 'blue',
  'vendor-review': 'pink',
};

export const MEETING_TYPE_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(MEETING_TYPE_HUES).map(([k, hue]) => [k, stateColor(hue)]),
  );

type ScoreState = 'scored' | 'awaiting' | 'upcoming';

export const MeetingTypeField = markDefinition(
  enumField(StringField, {
    options: MEETING_TYPES.map((type) => ({ value: type, label: type })),
    displayName: 'Meeting Type',
  }),
);

// A meeting's date as a Date, or undefined when it is unset or unparseable,
// so every render site gates on the same check.
function parseMeetingDate(
  value: Date | string | null | undefined,
): Date | undefined {
  if (!value) {
    return undefined;
  }
  let date = new Date(value);
  return isNaN(date.getTime()) ? undefined : date;
}

export class Meeting extends CardDef {
  static displayName = 'Meeting';
  static icon = CalendarIcon;

  @field name = contains(StringField);
  @field meetingType = contains(MeetingTypeField);
  @field date = contains(DateTimeField);
  @field duration = contains(DurationField);
  @field candidate = linksTo(() => Candidate);
  @field interviewers = linksToMany(() => Employee);
  // Kept as a plain field, not a computed mirror of scorecard.averageScore:
  // seed data and the tracker's overdue/rollup logic (whoseTurn,
  // avgInterviewScore) set and read this directly on meetings that have no
  // scorecard at all, and computing it away would silently blank those out.
  // The two live side by side — interviewScore is the quick one-number
  // verdict, scorecard is the optional structured breakdown.
  @field interviewScore = contains(ScoreField);
  @field roundType = contains(InterviewRoundField);
  @field scorecard = contains(ScorecardField);
  @field notes = contains(MarkdownField);

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field candidateName = contains(StringField, {
    computeVia: function (this: Meeting) {
      return this.candidate?.name ?? '';
    },
  });

  // Denormalized for the same reason as candidateName, but for an id-based
  // match: the Tracker shell filters meetings by candidate in a hot getter
  // (whoseTurn, called once per candidate per render) — reading `candidate`
  // there directly races the async linksTo load the same way candidateName
  // avoids for fitted.
  @field candidateId = contains(StringField, {
    computeVia: function (this: Meeting) {
      return this.candidate?.id ?? '';
    },
  });

  @field interviewerTally = contains(StringField, {
    computeVia: function (this: Meeting) {
      let n = liveCount(this.interviewers);
      return n === 0 ? '' : String(n);
    },
  });

  // Looks up this meeting's own round in the candidate's position's
  // interview plan, so an interviewer opening a scheduled Meeting sees
  // exactly the questions written for the round they're running — without
  // having to separately open the Position's InterviewPlan. Typed as
  // MarkdownField (like `notes`) so it renders formatted, not as raw text —
  // computeVia works the same for a MarkdownField as for any other contains
  // field, it just needs to return the plain string the field stores.
  //
  // Every hop is optional-chained and read defensively (candidate?. and
  // position?. can each be an unloaded linksTo, and interviewPlan?.rounds
  // resolves only once that link itself is loaded) — same defensive style as
  // candidateName/skillMatchPct in candidate.gts, so an unloaded link
  // upstream yields '' rather than tripping an "used before loaded"
  // assertion.
  @field interviewPlanRound = contains(MarkdownField, {
    computeVia: function (this: Meeting) {
      let rounds = this.candidate?.position?.interviewPlan?.rounds ?? [];
      let match = rounds.find(
        (round) => round && round.roundType === this.roundType,
      );
      return match?.questions ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Meeting) {
      return this.name?.trim() || 'Untitled Meeting';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get byline() {
      return bylineOf(this.args.model);
    }
    get scoreLabel() {
      return scoreLabelOf(this.args.model);
    }
    get recommendationHint() {
      let recommendation = recommendationOf(this.args.model);
      return recommendation ? `recommend ${recommendation.toLowerCase()}` : '';
    }
    get durationLabel() {
      return durationOf(this.args.model) ?? '—';
    }
    get dateHint() {
      let date = parseMeetingDate(this.args.model?.date);
      return date
        ? formatWhen(date, {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hourCycle: 'h23',
          })
        : 'no date set';
    }
    get panelSize() {
      return this.args.model?.interviewerTally || '0';
    }
    get criteriaRows() {
      return (this.args.model?.scorecard?.criteria ?? [])
        .filter((c) => c?.name)
        .map((c) => ({ name: c.name ?? '', value: c.score ?? 0 }));
    }
    get recommendation() {
      return recommendationOf(this.args.model)?.toLowerCase() ?? '';
    }
    get keyValues(): KeyValueItem[] {
      return factsOf(this.args.model).map(({ label, value }) => ({
        key: label,
        value: String(value),
      }));
    }
    get hasAttendees() {
      return Boolean(
        this.args.model?.candidate || this.args.model?.interviewers?.length,
      );
    }

    get strip(): StripItem[] {
      let items: StripItem[] = [];
      if (this.scoreLabel) {
        items.push({
          label: 'Score',
          value: this.scoreLabel,
          hint: this.recommendationHint,
          tone: 'success',
        });
      }
      items.push(
        { label: 'Duration', value: this.durationLabel, hint: this.dateHint },
        {
          label: 'Panel',
          value: this.panelSize,
          hint: 'interviewers',
          tone: 'info',
        },
      );
      return items;
    }
    get linkedRows() {
      let rows: { key: string; value: string }[] = [];
      if (this.args.model?.candidate) {
        rows.push({ key: 'Candidate', value: '' });
      }
      return rows;
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{this.byline}}>
            <:mark><MeetingMark /></:mark>
            <:aside><span class='status'>{{#if (roundOf @model)}}<DotLabel
                    @label={{roundOf @model}}
                    @hue='blue'
                  />{{/if}}{{#if this.recommendation}}<DotLabel
                    @label={{this.recommendation}}
                    @hue='green'
                  />{{/if}}{{#if this.scoreLabel}}<span
                    class='num'
                  >{{this.scoreLabel}}</span>{{/if}}</span></:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          {{#if this.criteriaRows.length}}
            <Panel @title='Scorecard'>
              {{#each this.criteriaRows as |row|}}
                <SheetLine class='crit'><span
                    class='crit-name'
                  >{{row.name}}</span><ProgressBar
                    class='crit-bar'
                    @value={{row.value}}
                    @max={{5}}
                    @steps={{false}}
                    @hue='var(--foreground)'
                    aria-label={{row.name}}
                  /><span class='num'>{{row.value}} / 5</span></SheetLine>
              {{/each}}
            </Panel>
          {{/if}}
          {{#if @model.scorecard.overallNotes}}
            <Panel @title='Overall notes'><SheetLine
              >{{@model.scorecard.overallNotes}}</SheetLine></Panel>
          {{/if}}
          <Panel @title='Notes'>
            {{#if @model.notes}}
              <SheetLine><div class='text'><@fields.notes /></div></SheetLine>
            {{else}}
              <SheetEmpty @title='No notes recorded for this meeting' />
            {{/if}}
          </Panel>

        </:main>
        <:aside>
          <Panel @title='Linked'>
            {{#if @model.candidate}}
              <SheetLine class='lk'><span
                  class='k'
                >Candidate</span><@fields.candidate
                  @format='atom'
                  @displayContainer={{false}}
                /></SheetLine>
            {{/if}}
            {{#each @fields.interviewers as |Interviewer|}}
              <SheetLine class='lk'><span
                  class='k'
                >Interviewer</span><Interviewer
                  @format='atom'
                  @displayContainer={{false}}
                /></SheetLine>
            {{/each}}
            {{#unless this.hasAttendees}}
              <SheetEmpty @title='No attendees linked yet' />
            {{/unless}}
          </Panel>
          <Panel @title='Details'><Kv @items={{this.keyValues}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .status {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          font-weight: 600;
        }
        .num {
          font-weight: 400;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .crit {
          flex-wrap: nowrap;
        }
        .crit-name {
          inline-size: 7.5rem;
          flex: none;
        }
        .crit-bar {
          flex: 1;
          min-width: 0;
        }
        .text {
          min-width: 0;
          overflow-wrap: break-word;
        }
        .lk {
          flex-wrap: nowrap;
          min-width: 0;
        }
        .k {
          flex: none;
          inline-size: 5.5rem;
          font-weight: 600;
          font-size: 0.5625rem; /* 9px ladder label: no token */
          line-height: 1.3;
          font-family: var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--subtle-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get byline() {
      return bylineOf(this.args.model);
    }
    get recommendation() {
      return recommendationOf(this.args.model);
    }
    get recommendationLower() {
      return this.recommendation?.toLowerCase();
    }
    get overall(): string | undefined {
      return this.args.model?.scorecard?.overallNotes || undefined;
    }
    // The six facts that fit two rows at full width; isolated has the rest.
    get facts() {
      return factsOf(this.args.model).slice(0, 6);
    }

    get rows() {
      return kv(factsOf(this.args.model).slice(0, 6));
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.byline}}>
        <:mark><MeetingMark /></:mark>
        <:aside>{{#if (roundOf @model)}}<DotLabel
              @label={{roundOf @model}}
              @hue='blue'
            />{{/if}}</:aside>
        <:default>
          {{#if this.recommendation}}
            <SheetLine class='lk'><span class='k'>Summary</span><span>Recommend
                <strong>{{this.recommendationLower}}</strong>{{#if
                  this.overall
                }} · {{this.overall}}{{/if}}</span></SheetLine>
          {{/if}}
          <Kv @items={{this.rows}} />
          {{#if @model.candidate}}
            <SheetLine class='lk'><span
                class='k'
              >Candidate</span><@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></SheetLine>
          {{/if}}
          {{#each @fields.interviewers as |Interviewer|}}
            <SheetLine class='lk'><span class='k'>Interviewer</span><Interviewer
                @format='atom'
                @displayContainer={{false}}
              /></SheetLine>
          {{/each}}
        </:default>
      </EmbCard>
      <style scoped>
        .k {
          inline-size: 7.5rem;
          font-weight: 600;
          font-size: 0.5625rem; /* 9px ladder label: no token */
          line-height: 1.3;
          font-family: var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--subtle-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get scored() {
      return typeof this.args.model?.interviewScore === 'number';
    }
    get scoreLabel() {
      return scoreLabelOf(this.args.model);
    }
    get scoreTone() {
      return scoreToneOf(this.args.model);
    }

    <template>
      <span class='meeting-atom'>
        <MeetingMark class='type-mark' />
        <span class='meeting-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .meeting-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .type-mark {
            --meeting-mark-size: 1.25rem;
            --meeting-mark-font-size: var(--boxel-font-size-2xs);
          }
          .meeting-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get recommendation() {
      return recommendationOf(this.args.model);
    }
    get scoreLabel() {
      return scoreLabelOf(this.args.model);
    }
    get scoreTone() {
      return scoreToneOf(this.args.model);
    }
    get recommendationTone() {
      return recommendationToneOf(this.args.model);
    }
    // The first chip: the interview round, or the meeting type when it has none.
    get lead(): string | undefined {
      return (
        roundOf(this.args.model) ?? this.args.model?.meetingType ?? undefined
      );
    }
    get byline() {
      return bylineOf(this.args.model);
    }
    get recommendationLower() {
      return this.recommendation?.toLowerCase();
    }
    get overall(): string | undefined {
      return this.args.model?.scorecard?.overallNotes || undefined;
    }
    get durationLabel() {
      return durationOf(this.args.model) ?? '—';
    }
    get panelSize() {
      return this.args.model?.interviewerTally || '0';
    }
    get facts() {
      return factsOf(this.args.model);
    }

    get strip(): StripItem[] {
      return [
        { label: 'Score', value: this.scoreLabel || '—' },
        { label: 'Duration', value: this.durationLabel },
        { label: 'Panel', value: this.panelSize },
      ];
    }
    <template>
      <FitCard @title={{@model.title}}>
        <:mark><MeetingMark /></:mark>
        <:status>{{#if (roundOf @model)}}<DotLabel
              @label={{roundOf @model}}
              @hue='blue'
            />{{/if}}</:status>
        <:default>
          <FitRow @left={{true}}><span
              class='meta'
            >{{this.byline}}</span></FitRow>
          {{#if this.scoreLabel}}
            <FitRow @label='Score'>{{this.scoreLabel}}{{#if
                this.recommendationLower
              }}
                ·
                {{this.recommendationLower}}{{/if}}</FitRow>
          {{/if}}
          {{#if @model.candidate}}
            <FitRow @label='Candidate' @left={{true}}><@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#each @fields.interviewers as |Interviewer|}}
            <FitRow @label='Interviewer' @left={{true}}><Interviewer
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/each}}
          {{#each this.facts as |f|}}
            <FitRow @label={{f.label}}><span
                class='mono'
              >{{f.value}}</span></FitRow>
          {{/each}}
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 400;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
