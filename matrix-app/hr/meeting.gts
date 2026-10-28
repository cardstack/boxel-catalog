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
import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { BarList } from '../../ui-component/components/bar-list';
import { Chip } from '../../ui-component/components/chip';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import type { PretuiTone } from '../../ui-component/pretui-primitives';

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

// The chips every format leads its state with: round, score, verdict.
class MeetingChips extends GlimmerComponent<{ Args: { model: MeetingModel } }> {
  get round() {
    return roundOf(this.args.model);
  }
  get scoreLabel() {
    return scoreLabelOf(this.args.model);
  }
  get scoreTone() {
    return scoreToneOf(this.args.model);
  }
  get recommendation() {
    return recommendationOf(this.args.model);
  }
  get recommendationTone() {
    let value = this.args.model?.scorecard?.recommendation;
    return (value && RECOMMENDATION_TONES[value]) || 'neutral';
  }
  <template>
    {{#if this.round}}<Chip
        @label={{this.round}}
        @tone='info'
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      />{{/if}}
    {{#if this.scoreLabel}}<Chip
        @label={{this.scoreLabel}}
        @tone={{this.scoreTone}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      />{{/if}}
    {{#if this.recommendation}}<Chip
        @label={{this.recommendation}}
        @tone={{this.recommendationTone}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      />{{/if}}
  </template>
}

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

export const MeetingTypeField = enumField(StringField, {
  options: MEETING_TYPES.map((type) => ({ value: type, label: type })),
  displayName: 'Meeting Type',
});

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

    <template>
      <article class='meeting-isolated'>
        <header class='head'>
          <MeetingMark class='type-mark' />
          <div class='id'>
            <h1>{{@model.title}}</h1>
            {{#if this.byline}}<p class='sub'>{{this.byline}}</p>{{/if}}
          </div>
          <div class='chips'><MeetingChips @model={{@model}} /></div>
        </header>

        <div class='stats'>
          {{#if this.scoreLabel}}
            <Panel class='stat-tile'><Stat
                @label='Score'
                @value={{this.scoreLabel}}
                @hint={{this.recommendationHint}}
                @roll={{false}}
              /></Panel>
          {{/if}}
          <Panel class='stat-tile'><Stat
              @label='Duration'
              @value={{this.durationLabel}}
              @hint={{this.dateHint}}
              @roll={{false}}
            /></Panel>
          <Panel class='stat-tile'><Stat
              @label='Panel'
              @value={{this.panelSize}}
              @hint='interviewers'
              @roll={{false}}
            /></Panel>
        </div>

        <div class='body'>
          <div class='col'>
            {{#if this.criteriaRows.length}}
              <Panel>
                <:header><h2>Scorecard</h2></:header>
                <:default>
                  <BarList
                    @rows={{this.criteriaRows}}
                    @max={{5}}
                    @format={{outOfFive}}
                    @label='Scorecard'
                  />
                </:default>
              </Panel>
            {{/if}}
            {{#if @model.scorecard.overallNotes}}
              <Panel>
                <:header><h2>Overall notes</h2></:header>
                <:default>
                  <p class='text'>{{@model.scorecard.overallNotes}}</p>
                </:default>
              </Panel>
            {{/if}}
            <Panel>
              <:header><h2>Notes</h2></:header>
              <:default>
                {{#if @model.notes}}
                  <div class='text'><@fields.notes /></div>
                {{else}}
                  <EmptyState
                    class='empty'
                    @texture={{false}}
                    @title='No notes recorded for this meeting'
                  />
                {{/if}}
              </:default>
            </Panel>
            {{#if @model.interviewPlanRound}}
              <Panel>
                <:header><h2>Interview questions (this round)</h2></:header>
                <:default>
                  <div class='text'><@fields.interviewPlanRound /></div>
                </:default>
              </Panel>
            {{/if}}
          </div>

          <div class='col'>
            <Panel>
              <:header><h2>Linked</h2></:header>
              <:default>
                {{#if this.hasAttendees}}
                  <dl class='linked'>
                    {{#if @model.candidate}}
                      <div>
                        <dt>Candidate</dt>
                        <dd><@fields.candidate
                            @format='atom'
                            @displayContainer={{false}}
                          /></dd>
                      </div>
                    {{/if}}
                    {{#each @fields.interviewers as |Interviewer|}}
                      <div>
                        <dt>Interviewer</dt>
                        <dd><Interviewer
                            @format='atom'
                            @displayContainer={{false}}
                          /></dd>
                      </div>
                    {{/each}}
                  </dl>
                {{else}}
                  <EmptyState
                    class='empty'
                    @texture={{false}}
                    @title='No attendees linked yet'
                  />
                {{/if}}
              </:default>
            </Panel>
            <Panel>
              <:header><h2>Details</h2></:header>
              <:default>
                <KeyValue @items={{this.keyValues}} @rows='ruled' />
              </:default>
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .meeting-isolated {
            container: meeting-iso / inline-size;
            height: 100%;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            padding: var(--boxel-sp-lg);
            background-color: var(--canvas);
            color: var(--card-foreground);
          }
          .head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp);
          }
          .type-mark {
            --meeting-mark-size: var(--boxel-icon-lg);
            --meeting-mark-font-size: var(--boxel-font-size-xs);
          }
          .id {
            flex: 1 1 0;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary);
            overflow-wrap: anywhere;
          }
          .sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stat-tile {
            --pretui-shadow-card: var(--shadow-md);
          }
          .body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            gap: var(--boxel-sp-lg);
            align-items: start;
          }
          .col {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          h2 {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            line-height: 1.25;
          }
          .text {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            white-space: pre-line;
            overflow-wrap: anywhere;
          }
          .linked {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
          }
          .linked > div {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-xs) 0;
            border-top: 1px solid var(--border);
          }
          .linked > div:first-child {
            border-top: 0;
            padding-top: 0;
          }
          .linked dt {
            color: var(--muted-foreground);
          }
          .linked dd {
            margin: 0;
            min-width: 0;
          }
          .empty {
            --space-9: var(--boxel-sp);
            --space-6: var(--boxel-sp);
            --text-heading: var(--boxel-font-size);
          }
          @container meeting-iso (width < 45rem) {
            .body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
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

    <template>
      <article class='meeting-embedded'>
        <header class='head'>
          <MeetingMark class='type-mark' />
          <div class='id'>
            <h3>{{@model.title}}</h3>
            {{#if this.byline}}<p class='sub'>{{this.byline}}</p>{{/if}}
          </div>
          <div class='chips'><MeetingChips @model={{@model}} /></div>
        </header>
        {{#if this.recommendation}}
          <p class='fact'>Recommend
            <strong>{{this.recommendationLower}}</strong>{{#if this.overall}}
              &middot;
              {{this.overall}}{{/if}}</p>
        {{/if}}
        {{#if this.facts.length}}
          <Descriptions
            class='facts'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          />
        {{/if}}
        {{#if @model.candidate}}
          <div class='rels'>
            <span>Candidate
              <@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></span>
            {{#each @fields.interviewers as |Interviewer|}}
              <span>Interviewer
                <Interviewer
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/each}}
          </div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .meeting-embedded {
            container: meeting-emb / inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .type-mark {
            --meeting-mark-size: var(--boxel-icon-lg);
            --meeting-mark-font-size: var(--boxel-font-size-xs);
          }
          .id {
            flex: 1 1 0;
            min-width: 0;
          }
          h3 {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            overflow-wrap: anywhere;
          }
          .sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .fact {
            margin: 0;
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .facts {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .rels > span {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            max-width: 100%;
          }
          /* under 400 wide the chips move under the name */
          @container meeting-emb (width < 25rem) {
            .head {
              flex-wrap: wrap;
            }
            .chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
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
        {{#if this.scored}}
          <Chip
            @label={{this.scoreLabel}}
            @tone={{this.scoreTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          />
        {{/if}}
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

    <template>
      <article class='fit'>
        <header class='who'>
          <MeetingMark class='mark' />
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              <span class='chips chips-inline'>
                {{#if this.lead}}<Chip
                    @tone='info'
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{this.lead}}</Chip>{{/if}}
                {{#if this.scoreLabel}}<Chip
                    class='c-score'
                    @tone={{this.scoreTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{this.scoreLabel}}</Chip>{{/if}}
                {{#if this.recommendation}}<Chip
                    class='c-rec'
                    @tone={{this.recommendationTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{this.recommendation}}</Chip>{{/if}}
              </span>
            </div>
            <p class='sub'>{{if this.byline this.byline 'No date'}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          {{#if this.lead}}<Chip
              @tone='info'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.lead}}</Chip>{{/if}}
          {{#if this.scoreLabel}}<Chip
              @tone={{this.scoreTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.scoreLabel}}</Chip>{{/if}}
          {{#if this.recommendation}}<Chip
              class='c-rec'
              @tone={{this.recommendationTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.recommendation}}</Chip>{{/if}}
        </span>
        {{#if this.recommendation}}
          <p class='fact'>Recommend
            <strong>{{this.recommendationLower}}</strong>{{#if this.overall}}
              &middot;
              {{this.overall}}{{/if}}</p>
        {{else if @model.candidateName}}
          <p class='fact'>With {{@model.candidateName}}</p>
        {{/if}}
        <dl class='stats'>
          {{#if this.scoreLabel}}<div><dt>Score</dt><dd
              >{{this.scoreLabel}}</dd></div>{{/if}}
          <div><dt>Duration</dt><dd>{{this.durationLabel}}</dd></div>
          <div><dt>Panel</dt><dd>{{this.panelSize}}</dd></div>
        </dl>
        <dl class='kv'>
          {{#each this.facts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <ul class='rels'>
          {{#if @model.candidate}}
            <li><span class='k'>Candidate</span><@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#each @fields.interviewers as |Interviewer|}}
            <li><span class='k'>Interviewer</span><Interviewer
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/each}}
        </ul>
      </article>
      <style scoped>
        @layer PretComponent {
          /* off-ladder gaps from the IMS rule (8 / 4 / 2); type reads the
             ladder, set here so a host's font-size never leaks in */
          .fit {
            --_fit-gap: 0.5rem;
            --_fit-gap-tight: 0.25rem;
            --_fit-hair: 0.125rem;

            display: flex;
            flex-direction: column;
            gap: var(--_fit-gap);
            block-size: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
          }
          .fit > * {
            flex: none;
            min-inline-size: 0;
            margin: 0;
          }
          .who {
            display: flex;
            align-items: flex-start;
            gap: var(--boxel-sp-sm);
            min-inline-size: 0;
          }
          .mark {
            display: none;
          }
          .id {
            display: flex;
            flex: 1 1 auto;
            flex-direction: column;
            gap: var(--_fit-hair);
            min-inline-size: 0;
          }
          .line1 {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
          }
          .title {
            flex: 1 1 auto;
            min-inline-size: 7rem;
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .title,
          .sub,
          .fact,
          .kv dd {
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .sub {
            margin: 0;
          }
          .sub,
          .fact,
          .kv,
          .rels {
            font-size: var(--boxel-font-size-xs);
          }
          .sub,
          .fact,
          .k,
          .kv dt {
            color: var(--muted-foreground);
          }
          .fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .chips {
            display: flex;
            gap: var(--_fit-gap-tight);
            min-inline-size: 0;
            overflow: hidden;
          }
          .chips > * {
            flex: none;
          }
          .chips-inline,
          .chips-inline .c-score,
          .chips-inline .c-rec,
          .c-rec,
          .kv,
          .rels .k,
          .stats {
            display: none;
          }
          .chips-inline {
            flex: none;
          }
          /* as many rows as fit the space left; rows past the bottom get
             zero height, so none shows half */
          .kv {
            flex: 1 1 0;
            grid-template-columns: minmax(0, 1fr);
            grid-template-rows: repeat(auto-fill, 1.125rem);
            grid-auto-rows: 0;
            gap: var(--_fit-gap-tight) var(--boxel-sp-sm);
            min-block-size: 0;
            overflow: hidden;
          }
          .kv-i {
            display: flex;
            justify-content: space-between;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            overflow: hidden;
          }
          .kv dt {
            flex: none;
          }
          .kv dd {
            margin: 0;
            font-weight: 600;
            text-align: end;
            font-variant-numeric: tabular-nums;
          }
          /* a link that doesn't fit wraps into a second column, which the
             overflow clips, so no row ever shows half */
          .rels {
            display: flex;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            min-block-size: 0;
            gap: var(--_fit-gap-tight);
            margin: 0;
            padding: 0;
            list-style: none;
            overflow: hidden;
          }
          .rels li {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            flex: none;
            inline-size: 100%;
            block-size: 1.375rem;
            overflow: hidden;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--_fit-gap);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stats dd {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            color: var(--foreground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .stats dt {
            margin: 0;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the type mark shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: grid;
            }
          }
          /* the recommendation joins the chips from 250 wide */
          @container fitted-card (width >= 250px) {
            .chips-row .c-rec {
              display: inline-flex;
            }
          }
          /* relations name their link from 250 wide and 170 tall */
          @container fitted-card (width >= 250px) and (height >= 170px) {
            .rels .k {
              display: inline;
            }
          }
          @container fitted-card (width <= 150px) {
            .fact strong {
              font-weight: inherit;
              color: inherit;
            }
          }
          /* 400 wide: state moves beside the title, all three chips */
          @container fitted-card (width >= 400px) {
            .chips-inline,
            .chips-inline .c-score,
            .chips-inline .c-rec {
              display: inline-flex;
            }
            .chips-row {
              display: none;
            }
          }
          /* under 170 tall: tight rows */
          @container fitted-card (height < 170px) {
            .fit {
              gap: var(--_fit-gap-tight);
              padding: var(--_fit-gap) var(--boxel-sp-sm);
            }
          }
          /* 105 – 169 tall, under 400 wide: no relations line */
          @container fitted-card (height < 170px) and (width < 400px) {
            .rels {
              display: none;
            }
          }
          /* 105 – 169 tall, 400 wide: the relations are one line of atoms */
          @container fitted-card (height < 170px) and (width >= 400px) {
            .rels {
              flex-flow: row wrap;
              max-block-size: 1.375rem;
            }
          }
          /* under 105 tall: who only, the round beside the title from 250 wide */
          @container fitted-card (height < 105px) {
            .chips-row,
            .fact,
            .rels {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width >= 250px) {
            .chips-inline {
              display: flex;
            }
          }
          /* under 65 tall: the date line goes too */
          @container fitted-card (height < 65px) {
            .sub {
              display: none;
            }
          }
          @container fitted-card (height < 65px) and (width < 250px) {
            .chips-inline {
              display: none;
            }
          }
          /* 250 tall: roomier padding and a larger mark; under 250 wide the
             mark stacks above the name */
          @container fitted-card (height >= 250px) {
            .fit {
              padding: var(--boxel-sp);
            }
            .mark {
              --meeting-mark-size: 2.5rem;
              --meeting-mark-font-size: var(--boxel-font-size-sm);
            }
          }
          @container fitted-card (height >= 250px) and (width < 250px) {
            .who {
              flex-direction: column;
              gap: var(--_fit-gap);
            }
            .id {
              align-self: stretch;
            }
          }
          /* 275 tall: the remaining facts fill the space left */
          @container fitted-card (height >= 275px) {
            .kv {
              display: grid;
            }
          }
          /* 400 tall: the headline numbers lead */
          @container fitted-card (height >= 400px) {
            .stats {
              display: grid;
            }
          }
          @container fitted-card (height >= 275px) and (height < 400px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
          }
        }
      </style>
    </template>
  };
}
