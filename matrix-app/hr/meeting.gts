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
import { FormatDate } from '../../ui-component/components/format-date';
import { BarList } from '../../ui-component/components/bar-list';
import { Chip } from '../../ui-component/components/chip';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FitTile } from '../../ui-component/components/fit-tile';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { VisuallyHidden } from '../../ui-component/components/visually-hidden';
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
import { UnsetMarker } from '@cardstack/catalog/components/unset-marker';
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
    date && formatWhen(date, { hour: 'numeric', minute: '2-digit' }),
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
    {{#if this.round}}<Chip @label={{this.round}} @tone='info' />{{/if}}
    {{#if this.scoreLabel}}<Chip
        @label={{this.scoreLabel}}
        @tone={{this.scoreTone}}
      />{{/if}}
    {{#if this.recommendation}}<Chip
        @label={{this.recommendation}}
        @tone={{this.recommendationTone}}
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

// The clock time a meeting starts at, as the header and the tile show it
// ("9:30 AM"). en-US like the date tile beside it. Renders nothing when the
// meeting has no date.
class MeetingTime extends GlimmerComponent<{
  Args: { date?: Date };
  Element: HTMLTimeElement;
}> {
  <template>
    {{#if @date}}
      <FormatDate
        @date={{@date}}
        @locale='en-US'
        @hour='numeric'
        @minute='2-digit'
        ...attributes
      />
    {{/if}}
  </template>
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
    get facts() {
      return factsOf(this.args.model);
    }
    get hasAttendees() {
      return Boolean(
        this.args.model?.candidate || this.args.model?.interviewers?.length,
      );
    }

    <template>
      <article class='meeting-isolated'>
        <header class='head'>
          <span class='type-mark' aria-hidden='true'><CalendarIcon /></span>
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
                <Descriptions @items={{this.facts}} @columns={{1}} />
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
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp);
          }
          .type-mark {
            flex: none;
            display: grid;
            place-items: center;
            width: var(--boxel-icon-lg);
            height: var(--boxel-icon-lg);
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--muted);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary);
          }
          .type-mark > svg {
            width: var(--boxel-icon-xs);
            height: var(--boxel-icon-xs);
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
    // The six facts that fit two rows at full width; isolated has the rest.
    get facts() {
      return factsOf(this.args.model).slice(0, 6);
    }

    <template>
      <article class='meeting-embedded'>
        <header class='head'>
          <span class='type-mark' aria-hidden='true'><CalendarIcon /></span>
          <div class='id'>
            <h3>{{@model.title}}</h3>
            {{#if this.byline}}<p class='sub'>{{this.byline}}</p>{{/if}}
          </div>
          <div class='chips'><MeetingChips @model={{@model}} /></div>
        </header>
        {{#if this.recommendation}}
          <p class='fact'>Recommend <strong>{{this.recommendation}}</strong></p>
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
            flex: none;
            display: grid;
            place-items: center;
            width: var(--boxel-icon-lg);
            height: var(--boxel-icon-lg);
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--muted);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary);
          }
          .type-mark > svg {
            width: var(--boxel-icon-xs);
            height: var(--boxel-icon-xs);
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
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
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
        <span class='type-mark' aria-hidden='true'><CalendarIcon /></span>
        <span class='meeting-atom-name'>{{@model.title}}</span>
        {{#if this.scored}}
          <Chip @label={{this.scoreLabel}} @tone={{this.scoreTone}} />
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
            flex: none;
            display: grid;
            place-items: center;
            width: var(--boxel-icon-sm);
            height: var(--boxel-icon-sm);
            border-radius: var(--boxel-sp-4xs);
            background-color: var(--muted);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary);
          }
          .type-mark > svg {
            width: var(--boxel-icon-2xs);
            height: var(--boxel-icon-2xs);
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
    get dateObj(): Date | undefined {
      return parseMeetingDate(this.args.model?.date);
    }

    get recommendation() {
      return recommendationOf(this.args.model);
    }

    get scoreLabel() {
      return scoreLabelOf(this.args.model);
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

    // Type and duration, whichever are set, after the date and time.
    get eyebrow(): string | undefined {
      let parts = [this.args.model?.meetingType, durationOf(this.args.model)];
      let shown = parts.filter(Boolean);
      return shown.length ? shown.join(' · ') : undefined;
    }

    <template>
      {{! FitTile carries who, state and fact at every size. From 170 tall
          the relations leave its one-line row for a list below it, joined
          by the key facts and, on expanded cards, a stat strip. }}
      <div class='meeting-fit'>
        <div class='top'>
          <FitTile>
            <:avatar>
              <span class='type-mark' aria-hidden='true'><CalendarIcon /></span>
            </:avatar>
            {{! The subline's date parts come and go with the tile's width, so
            they are hidden from assistive tech; one visually hidden full
            date and time right after the title stands in for them. }}
            <:title><span class='fit-head'><span
                  class='fit-name'
                  role='heading'
                  aria-level='3'
                >{{@model.title}}</span>{{#if this.dateObj}}<VisuallyHidden
                  ><FormatDate
                      @date={{@model.date}}
                      @locale='en-US'
                      @weekday='long'
                      @month='long'
                      @day='numeric'
                      @year='numeric'
                      @hour='numeric'
                      @minute='2-digit'
                    /></VisuallyHidden>{{/if}}</span></:title>
            <:subtitle><span class='datebox'>{{#if this.dateObj}}<FormatDate
                    class='db-weekday'
                    @date={{@model.date}}
                    @locale='en-US'
                    @weekday='short'
                    aria-hidden='true'
                  />
                  <FormatDate
                    @date={{@model.date}}
                    @locale='en-US'
                    @month='short'
                    aria-hidden='true'
                  />
                  <FormatDate
                    @date={{@model.date}}
                    @locale='en-US'
                    @day='numeric'
                    aria-hidden='true'
                  />{{else}}<UnsetMarker @label='No date' />{{/if}}</span>{{#if
                this.dateObj
              }}
                &middot;
                <MeetingTime
                  class='fit-time'
                  @date={{this.dateObj}}
                  aria-hidden='true'
                />{{/if}}{{#if this.eyebrow}}
                &middot;
                <span class='fit-eb'>{{this.eyebrow}}</span>{{/if}}</:subtitle>
            {{! Score state is the signal that says whether this meeting still
            needs something, so it leads the chips after the round. }}
            <:status><MeetingChips @model={{@model}} /></:status>
            <:fact>{{#if this.recommendation}}Recommend
                <strong>{{this.recommendation}}</strong>{{else if
                @model.candidateName
              }}With {{@model.candidateName}}{{/if}}</:fact>
            <:relations><span class='rel-line'><@fields.candidate
                  @format='atom'
                  @displayContainer={{false}}
                />{{#each @fields.interviewers as |Interviewer|}}<Interviewer
                    @format='atom'
                    @displayContainer={{false}}
                  />{{/each}}</span></:relations>
          </FitTile>
        </div>
        {{! A column that wraps: whatever doesn't fit whole moves to a second
            column out of sight, so no row is ever half-cut. }}
        <div class='more'>
          <div class='stats'>
            {{#if this.scoreLabel}}
              <Stat @label='Score' @value={{this.scoreLabel}} @roll={{false}} />
            {{/if}}
            <Stat
              @label='Duration'
              @value={{this.durationLabel}}
              @roll={{false}}
            />
            <Stat @label='Panel' @value={{this.panelSize}} @roll={{false}} />
          </div>
          {{#if this.facts.length}}
            <dl class='kv'>
              {{#each this.facts as |fact|}}
                <div><dt>{{fact.label}}</dt><dd>{{fact.value}}</dd></div>
              {{/each}}
            </dl>
          {{/if}}
          {{#if @model.candidate}}
            <div class='rel'><span class='k'>Candidate</span><@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></div>
          {{/if}}
          {{#each @fields.interviewers as |Interviewer|}}
            <div class='rel'><span class='k'>Interviewer</span><Interviewer
                @format='atom'
                @displayContainer={{false}}
              /></div>
          {{/each}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent {
          .meeting-fit {
            display: flex;
            flex-direction: column;
            height: 100%;
            overflow: hidden;
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .top {
            height: 100%;
          }
          .rel-line {
            display: contents;
          }
          .more,
          .stats,
          .kv {
            display: none;
          }
          .more {
            flex: 1;
            min-height: 0;
            flex-direction: column;
            flex-wrap: wrap;
            align-content: flex-start;
            gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
            padding: 0 var(--boxel-sp-sm) var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
          }
          .more > * {
            width: 100%;
            min-width: 0;
          }
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
          }
          .kv {
            margin: 0;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          }
          .kv > div {
            display: flex;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            white-space: nowrap;
          }
          .kv dt {
            flex: none;
            color: var(--muted-foreground);
          }
          .kv dd {
            margin: 0;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            height: 1.375rem;
            overflow: hidden;
            white-space: nowrap;
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          /* 170 tall and up: one relation per line below the tile */
          @container fitted-card (height >= 170px) {
            .top {
              height: auto;
            }
            .rel-line {
              display: none;
            }
            .more {
              display: flex;
            }
          }
          @container fitted-card (width < 250px) {
            .k {
              display: none;
            }
          }
          /* 250 x 275 and up: the first key facts lead the list */
          @container fitted-card (height >= 275px) and (width >= 250px) {
            .kv {
              display: grid;
            }
            .kv > div:nth-child(n + 3) {
              display: none;
            }
          }
          @container fitted-card (height >= 275px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .kv > div:nth-child(n + 3) {
              display: flex;
            }
            .kv > div:nth-child(n + 7) {
              display: none;
            }
          }
          /* expanded: a stat strip, then up to eight facts in one column */
          @container fitted-card (height >= 400px) {
            .stats {
              display: grid;
            }
            .kv {
              grid-template-columns: minmax(0, 1fr);
            }
            .kv > div:nth-child(n + 3) {
              display: flex;
            }
            .kv > div:nth-child(n + 9) {
              display: none;
            }
          }
          .type-mark {
            display: grid;
            place-items: center;
            width: var(--boxel-icon-med);
            height: var(--boxel-icon-med);
            border-radius: var(--boxel-border-radius-sm);
            background-color: var(--muted);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary);
          }
          .type-mark > svg {
            width: var(--boxel-icon-xs);
            height: var(--boxel-icon-xs);
          }
          .fit-head {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-name {
            margin: 0;
            font-size: inherit;
            font-weight: inherit;
            line-height: inherit;
          }
          .db-weekday::after {
            content: ',';
          }
          strong {
            font-weight: 600;
            color: var(--foreground);
          }
        }
      </style>
    </template>
  };
}
