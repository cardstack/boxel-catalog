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
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { htmlSafe } from '@ember/template';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { Stat } from '@cardstack/pretui/components/stat';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from './duration-field';
import { InterviewRoundField } from './interview-round-field';
import { ScorecardField } from './scorecard-field';
import { Employee } from './employee';
import { Candidate } from './candidate';
import {
  StatePill,
  stateColor,
  stateColorOf,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { UnsetMarker } from '@cardstack/catalog/components/unset-marker';
import { liveCount } from './utils';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { hueOf } from './hr-ui';

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

// Score state carries status meaning, kept apart from the type hue so "whose
// court is the ball in" never competes with "what kind of meeting is this".
const SCORE_STATE_HUES: Record<ScoreState, Hue> = {
  scored: 'green',
  awaiting: 'red',
  upcoming: 'slate',
};

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
    get typeHue() {
      return hueOf(MEETING_TYPE_HUES, this.args.model?.meetingType);
    }

    get scoreHue(): Hue {
      return SCORE_STATE_HUES[this.scoreState];
    }

    get dateObj(): Date | undefined {
      return parseMeetingDate(this.args.model?.date);
    }

    // The byline shows only the parts that are set, with the dot only
    // between two shown parts.
    get hasByline(): boolean {
      return Boolean(this.dateObj || this.args.model?.duration?.label);
    }

    get durationNeedsSeparator(): boolean {
      return this.dateObj !== undefined;
    }

    // Derived: the meeting is over and nobody recorded a score. This is the
    // one state a scheduling card can genuinely surface — "the ball is in our
    // court" — and it comes free from date + interviewScore.
    get scoreState(): ScoreState {
      let d = this.dateObj;
      let scored = typeof this.args.model?.interviewScore === 'number';
      if (scored) {
        return 'scored';
      }
      if (d && d.getTime() < Date.now()) {
        return 'awaiting';
      }
      return 'upcoming';
    }

    get scoreLabel(): string {
      let v = this.args.model?.interviewScore;
      if (typeof v === 'number') {
        return `${v} / 5`;
      }
      return this.scoreState === 'awaiting'
        ? 'Score overdue'
        : 'Not yet scored';
    }

    get attendees(): Array<{
      role: string;
      title: string;
      photoUrl?: string | null;
    }> {
      let list = [];
      let candidate = this.args.model?.candidate;
      if (candidate) {
        list.push({
          role: 'Candidate',
          title: candidate.title ?? '',
          photoUrl: candidate.photo?.resolvedUrl,
        });
      }
      for (let interviewer of this.args.model?.interviewers ?? []) {
        if (interviewer) {
          list.push({
            role: 'Interviewer',
            title: interviewer.title ?? '',
            photoUrl: interviewer.photo?.resolvedUrl,
          });
        }
      }
      return list;
    }

    <template>
      <article class='meeting-isolated'>
        <header class='hero'>
          {{! A meeting's first question is always "when", so the date gets a
              block of its own rather than a line in the subtitle. }}
          <div class='datebox'>
            {{#if this.dateObj}}
              <FormatDate
                class='db-month'
                @date={{@model.date}}
                @locale='en-US'
                @month='short'
              />
              <FormatDate
                class='db-day'
                @date={{@model.date}}
                @locale='en-US'
                @day='numeric'
              />
              <FormatDate
                class='db-weekday'
                @date={{@model.date}}
                @locale='en-US'
                @weekday='short'
              />
            {{else}}
              <UnsetMarker class='db-day' @label='No date' />
            {{/if}}
          </div>
          <div class='hero-text'>
            <h1>{{@model.title}}</h1>
            {{#if this.hasByline}}
              <p class='byline'>
                <MeetingTime @date={{this.dateObj}} />
                {{#if @model.duration.label}}
                  {{#if this.durationNeedsSeparator}}
                    <span class='sep-dot'>&middot;</span>
                  {{/if}}
                  {{@model.duration.label}}
                {{/if}}
              </p>
            {{/if}}
            <div class='pill-row'>
              <StatePill
                @label={{@model.meetingType}}
                @hue={{this.typeHue}}
                @dot={{true}}
              />
              <StatePill
                @label={{this.scoreLabel}}
                @hue={{this.scoreHue}}
                @dot={{true}}
              />
            </div>
          </div>
        </header>

        <div class='body'>
          <div class='main'>
            <h2 class='panel-title'>Attendees</h2>
            {{#if this.attendees.length}}
              <ul class='attendees'>
                {{#each this.attendees as |a|}}
                  <li>
                    <EntityDisplay
                      class='attendee'
                      @title={{a.title}}
                      @subtitle={{a.role}}
                      @center={{true}}
                    >
                      <:visual>
                        <Avatar
                          @name={{if a.title a.title '?'}}
                          @src={{a.photoUrl}}
                          @hue={{AVATAR_HUE}}
                          @size={{28}}
                          aria-hidden='true'
                        />
                      </:visual>
                    </EntityDisplay>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No attendees linked yet'
              />
            {{/if}}

            <h2 class='panel-title spaced'>Notes</h2>
            {{#if @model.notes}}
              <div class='notes'><@fields.notes /></div>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No notes recorded for this meeting'
              />
            {{/if}}

            {{#if @model.scorecard.criteria.length}}
              <h2 class='panel-title spaced'>Scorecard</h2>
              <div class='scorecard-wrap'><@fields.scorecard /></div>
            {{/if}}

            {{#if @model.interviewPlanRound}}
              <h2 class='panel-title spaced'>Interview questions (this round)</h2>
              <div class='markdown'><@fields.interviewPlanRound /></div>
            {{/if}}
          </div>

          <aside class='side'>
            <h2 class='panel-title'>Score</h2>
            <div class='score-block'>
              <Stat
                class='score-num'
                @label='Interview score'
                @value={{this.scoreLabel}}
                @roll={{false}}
              />
              {{#if @model.interviewScore}}
                <span class='score-sub'><@fields.interviewScore /></span>
              {{/if}}
            </div>

            <h2 class='panel-title spaced'>Details</h2>
            <dl class='stacked'>
              <dt>Type</dt>
              <dd>{{if @model.meetingType @model.meetingType '—'}}</dd>
              <dt>Round</dt>
              <dd>{{#if @model.roundType}}<@fields.roundType
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}&mdash;{{/if}}</dd>
              <dt>Duration</dt>
              <dd>{{#if
                  @model.duration.label
                }}{{@model.duration.label}}{{else}}&mdash;{{/if}}</dd>
              <dt>Candidate</dt>
              <dd>{{#if @model.candidate}}<@fields.candidate
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}&mdash;{{/if}}</dd>
              <dt>Interviewers</dt>
              <dd>{{if
                  @model.interviewerTally
                  @model.interviewerTally
                  '0'
                }}</dd>
            </dl>
          </aside>
        </div>
      </article>
      <style scoped>
        .meeting-isolated {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          --meet-strong: color-mix(
            in oklch,
            var(--primary) 45%,
            var(--foreground)
          );
        }
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .datebox {
          flex: none;
          min-width: 4rem;
          text-align: center;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          padding: 0.4rem 0.7rem;
          background-color: var(--muted);
          color: var(--foreground);
        }
        .db-month {
          display: block;
          text-transform: uppercase;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          font-weight: 700;
          color: var(--meet-strong);
        }
        .db-day {
          display: block;
          font-size: 1.7rem;
          font-weight: 800;
          line-height: 1;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        .db-weekday {
          display: block;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .hero-text {
          flex: 1;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: anywhere;
        }
        .byline {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sep-dot {
          margin: 0 0.25rem;
        }
        .pill-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
          margin-top: var(--boxel-sp-xs);
        }
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
          /* Fill whatever height is left so the aside's surface reaches the
             bottom edge. Without this the grid is only as tall as its content
             and the panel stops mid-card, reading as a cut-off seam. */
          flex: 1;
          min-height: 0;
          align-content: start;
        }
        .main {
          padding: var(--boxel-sp-lg);
          min-width: 0;
        }
        .side {
          padding: var(--boxel-sp-lg);
          border-left: 1px solid var(--border);
          background-color: var(--muted);
          color: var(--foreground);
        }
        .panel-title {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .panel-title.spaced {
          margin-top: var(--boxel-sp-lg);
        }
        .attendees {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        /* EntityDisplay's name at the small body size and its role at the extra-small size, with a 1.75rem avatar, so each attendee reads as a compact row. */
        .attendee {
          --pretui-entity-visual-size: 1.75rem;
          --text-ui-md: var(--boxel-font-size-sm);
          --text-ui-sm: var(--boxel-font-size-xs);
          --space-3: var(--boxel-sp-xs);
        }
        .notes {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.65;
          max-height: 18rem;
          overflow-y: auto;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          padding: var(--boxel-sp-xs);
        }
        .markdown {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.65;
          max-height: 20rem;
          overflow-y: auto;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          padding: var(--boxel-sp-xs);
        }
        .empty {
          --space-9: var(--boxel-sp);
          --space-6: var(--boxel-sp);
          --text-heading: var(--boxel-font-size);
        }
        .scorecard-wrap {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          padding: var(--boxel-sp-xs);
        }
        .score-block {
          padding: var(--boxel-sp-xs) 0;
        }
        .score-num {
          --text-stat: 1.5rem;
        }
        .score-sub {
          display: block;
          margin-top: 0.15rem;
        }
        .stacked {
          margin: 0;
          display: grid;
        }
        .stacked dt {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding-top: 0.4rem;
        }
        .stacked dd {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          overflow-wrap: anywhere;
        }
        @container iso (max-width: 40rem) {
          .body {
            grid-template-columns: 1fr;
          }
          .side {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get typeHue() {
      return hueOf(MEETING_TYPE_HUES, this.args.model?.meetingType);
    }

    get accentBorderStyle() {
      let c = stateColorOf(MEETING_TYPE_COLORS, this.args.model?.meetingType);
      return htmlSafe(`border-left-color: ${c.ring};`);
    }

    <template>
      <div class='meeting-embedded' style={{this.accentBorderStyle}}>
        <header>
          <h3>{{@model.title}}</h3>
          <StatePill
            class='type'
            @label={{@model.meetingType}}
            @hue={{this.typeHue}}
          />
        </header>
        <dl class='meta-list'>
          <div><dt>When</dt><dd><@fields.date /></dd></div>
          <div><dt>Duration</dt><dd><@fields.duration
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          </div>
          {{#if @model.candidate}}
            <div>
              <dt>Candidate</dt>
              <dd><@fields.candidate
                  @format='atom'
                  @displayContainer={{false}}
                /></dd>
            </div>
          {{/if}}
          {{#if @model.interviewScore}}
            <div><dt>Score</dt><dd><@fields.interviewScore /></dd></div>
          {{/if}}
        </dl>
      </div>
      <style scoped>
        .meeting-embedded {
          padding: var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          border-left: 0.1875rem solid;
          transition: box-shadow 0.15s ease-out;
        }
        header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size);
        }
        .type {
          text-transform: capitalize;
        }
        .meta-list {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp);
        }
        .meta-list > div {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-2xs);
        }
        .meta-list dt {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .meta-list dd {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='meeting-atom'>
        <CalendarIcon class='meeting-atom-icon' />
        <span class='meeting-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .meeting-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .meeting-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .meeting-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get scoreHue(): Hue {
      return SCORE_STATE_HUES[this.scoreState];
    }

    get dateObj(): Date | undefined {
      return parseMeetingDate(this.args.model?.date);
    }

    // Same derivation as isolated: over and unscored means we owe an action.
    get scoreState(): ScoreState {
      let d = this.dateObj;
      if (typeof this.args.model?.interviewScore === 'number') {
        return 'scored';
      }
      return d && d.getTime() < Date.now() ? 'awaiting' : 'upcoming';
    }

    get scoreShort(): string {
      let v = this.args.model?.interviewScore;
      if (typeof v === 'number') {
        return `★ ${v}/5`;
      }
      return this.scoreState === 'awaiting' ? 'Unscored' : 'Upcoming';
    }

    // The tier-2 line: type and duration, whichever are set. An unset
    // duration is still a DurationField whose label is the '—' placeholder,
    // so the duration counts only when it has a value.
    get eyebrow(): string | undefined {
      let duration = this.args.model?.duration;
      let parts = [
        this.args.model?.meetingType,
        duration?.value != null ? duration.label : undefined,
      ].filter(Boolean);
      return parts.length ? parts.join(' · ') : undefined;
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          {{! The weekday and the time line come and go with the card's size,
              so the tile's parts and the time line are all hidden from
              assistive tech. One visually hidden date and time after the
              title stands in for them at every tier. }}
          <div class='datebox'>
            {{#if this.dateObj}}
              <FormatDate
                class='db-month'
                @date={{@model.date}}
                @locale='en-US'
                @month='short'
                aria-hidden='true'
              />
              <FormatDate
                class='db-day'
                @date={{@model.date}}
                @locale='en-US'
                @day='numeric'
                aria-hidden='true'
              />
              <FormatDate
                class='db-weekday'
                @date={{@model.date}}
                @locale='en-US'
                @weekday='short'
                aria-hidden='true'
              />
            {{else}}
              <UnsetMarker class='db-day' @label='No date' />
            {{/if}}
          </div>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if this.dateObj}}
              <VisuallyHidden><FormatDate
                  @date={{@model.date}}
                  @locale='en-US'
                  @weekday='long'
                  @month='long'
                  @day='numeric'
                  @year='numeric'
                  @hour='numeric'
                  @minute='2-digit'
                /></VisuallyHidden>
            {{/if}}
            {{#if this.eyebrow}}
              <span class='fit-eb'>{{this.eyebrow}}</span>
            {{/if}}
          </div>
          {{! Score state survives to the smallest tier — it is the only
              signal that says whether this meeting still needs something. }}
          <StatePill
            class='fit-pill'
            @label={{this.scoreShort}}
            @hue={{this.scoreHue}}
            @dot={{true}}
          />
        </div>

        <div class='fit-mid'>
          <MeetingTime
            class='fit-time'
            @date={{this.dateObj}}
            aria-hidden='true'
          />
          {{#if @model.candidateName}}
            <span class='fit-who'>{{@model.candidateName}}</span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if @model.interviewerTally}}
            <div><dt>Panel</dt><dd>{{@model.interviewerTally}}</dd></div>
          {{/if}}
          {{#if @model.duration.label}}
            <div><dt>Length</dt><dd>{{@model.duration.label}}</dd></div>
          {{/if}}
          {{#if @model.meetingType}}
            <div><dt>Type</dt><dd>{{@model.meetingType}}</dd></div>
          {{/if}}
          <div><dt>Score</dt><dd>{{this.scoreShort}}</dd></div>
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING fields. 11px floor. Pill never hidden. */
        .fit {
          height: 100%;
          /* Flex, not a three-row grid: with `minmax(0, 1fr)` in the middle
             a taller bottom block squeezed the middle row and clipped its
             text. Here the middle keeps its natural height and the extras
             block is pushed to the bottom by `margin-top: auto`. */
          display: flex;
          flex-direction: column;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --meet-strong: color-mix(
            in oklch,
            var(--primary) 45%,
            var(--foreground)
          );
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .datebox {
          flex: none;
          min-width: 2.3rem;
          text-align: center;
        }
        .db-month {
          display: block;
          text-transform: uppercase;
          font-size: var(--fit-small);
          font-weight: 700;
          color: var(--meet-strong);
        }
        .db-day {
          display: block;
          font-size: calc(var(--fit-name) * 1.2);
          font-weight: 800;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .db-weekday {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        .fit-mid {
          flex: none;
          display: none;
          flex-direction: column;
          gap: 0.0625rem;
        }
        .fit-time {
          font-size: var(--fit-small);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .fit-who {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-add {
          display: none;
          margin: 0;
          margin-top: auto;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          grid-template-columns: 1fr 1fr;
          gap: 0.125rem 0.5rem;
        }
        .fit-add > div {
          display: flex;
          gap: 0.25rem;
          min-width: 0;
        }
        .fit-add dt {
          flex: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-add dd {
          margin: 0;
          font-size: var(--fit-small);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* TIER 2 — add meeting type + duration. No `or` in CQ, so two rules. */
        @container fitted-card (height > 80px) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 240px) {
          .fit-eb {
            display: block;
          }
        }
        /* TIER 3 — add weekday, time and who it is with. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .db-weekday {
            display: block;
          }
          .fit-mid {
            display: flex;
          }
        }
        /* TIER 4 — width-driven facts. Previously absent entirely. */
        @container fitted-card (height > 150px) and (width > 180px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 340px) and (height > 130px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }
        @container fitted-card (height <= 90px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height <= 50px) {
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
