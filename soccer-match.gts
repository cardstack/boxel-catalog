import { concat, fn, get } from '@ember/helper';
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
// ¹ Core API and components
import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import {
  Button,
  FieldContainer,
  CardContainer,
} from '@cardstack/boxel-ui/components';
import {
  formatNumber,
  formatRelativeTime,
  subtract,
} from '@cardstack/boxel-ui/helpers';
import { add, gt, and, or, not } from '@cardstack/boxel-ui/helpers';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { task, restartableTask, timeout } from 'ember-concurrency';

// ² FieldDef: Team
export class TeamField extends FieldDef {
  static displayName = 'Team';
  @field name = contains(StringField);
  @field color = contains(StringField); // hex or CSS color
  @field rating = contains(NumberField); // 60-95 team strength
  @field formation = contains(StringField); // e.g., 4-3-3

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='team'>
        <div class='swatch' style={{concat 'background:' @model.color}}></div>
        <div class='meta'>
          <div class='name'>{{if @model.name @model.name 'Unnamed'}}</div>
          <div class='sub'>{{if @model.formation @model.formation '—'}}
            •
            {{if @model.rating @model.rating '?'}}</div>
        </div>
      </div>
      <style scoped>
        .team {
          display: flex;
          align-items: center;
          gap: 0.5rem;
        }
        .swatch {
          width: 14px;
          height: 14px;
          border-radius: 3px;
          border: 1px solid rgba(0, 0, 0, 0.1);
        }
        .meta {
          font-size: 0.8125rem;
        }
        .name {
          font-weight: 600;
        }
        .sub {
          font-size: 0.75rem;
          opacity: 0.8;
        }
      </style>
    </template>
  };
}

// ³ FieldDef: Match Event
export class MatchEventField extends FieldDef {
  static displayName = 'Match Event';
  @field minute = contains(NumberField);
  @field team = contains(StringField); // 'home' | 'away' | 'neutral'
  @field eventType = contains(StringField); // goal, shot, foul, yellow, red, save, corner, offside, injury
  @field note = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='event'>
        <span class='min'>{{if @model.minute @model.minute 0}}’</span>
        <span class={{concat 'team ' @model.team}}>{{if
            @model.team
            @model.team
            'neutral'
          }}</span>
        <span class='type'>{{if
            @model.eventType
            @model.eventType
            'event'
          }}</span>
        {{#if @model.note}}<span class='note'>— {{@model.note}}</span>{{/if}}
      </div>
      <style scoped>
        .event {
          font-size: 0.8125rem;
          display: flex;
          gap: 0.375rem;
          align-items: baseline;
        }
        .min {
          color: rgba(0, 0, 0, 0.7);
          width: 2.25rem;
        }
        .team.home {
          color: #2563eb;
        }
        .team.away {
          color: #dc2626;
        }
        .note {
          opacity: 0.8;
        }
      </style>
    </template>
  };
}

// ⁴ FieldDef: Shot Stats
export class ShotStatsField extends FieldDef {
  static displayName = 'Shot Stats';
  @field shots = contains(NumberField);
  @field onTarget = contains(NumberField);

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='shots'>{{@model.shots}} ({{@model.onTarget}})</span>
      <style scoped>
        .shots {
          font-size: 0.8125rem;
          opacity: 0.9;
        }
      </style>
    </template>
  };
}

// ⁵ FieldDef: Score
export class ScoreField extends FieldDef {
  static displayName = 'Score';
  @field home = contains(NumberField);
  @field away = contains(NumberField);

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='score'>{{@model.home}} - {{@model.away}}</span>
      <style scoped>
        .score {
          font-weight: 700;
        }
      </style>
    </template>
  };
}

// ⁶ CardDef: SoccerMatch
export class SoccerMatch extends CardDef {
  // Helpers to manage event log safely
  private ensureLog(self: SoccerMatch) {
    let log = (self as any).matchLog;
    if (!Array.isArray(log)) {
      (self as any).matchLog = [];
    }
  }

  // Sanitize and push a plain event entry into matchLog
  private addEvent(
    self: SoccerMatch,
    ev:
      | {
          minute?: unknown;
          team?: unknown;
          eventType?: unknown;
          note?: unknown;
        }
      | null
      | undefined,
  ) {
    if (!ev || typeof ev !== 'object') return;

    // Coerce primitives
    const minuteRaw = Number((ev as any).minute);
    let minute = Number.isFinite(minuteRaw)
      ? minuteRaw
      : self.currentMinute ?? 0;
    minute = Math.max(0, Math.floor(minute));

    const teamRaw = (ev as any).team;
    const team =
      teamRaw === 'home' || teamRaw === 'away' || teamRaw === 'neutral'
        ? teamRaw
        : self.possession === 'home' || self.possession === 'away'
        ? self.possession
        : 'neutral';

    const eventTypeRaw = (ev as any).eventType;
    const validTypes = new Set([
      'kickoff',
      'goal',
      'shot',
      'save',
      'foul',
      'yellow',
      'red',
      'corner',
      'offside',
      'event',
    ]);
    const eventType = validTypes.has(eventTypeRaw as string)
      ? (eventTypeRaw as string)
      : 'event';

    const noteVal =
      typeof (ev as any).note === 'string'
        ? ((ev as any).note as string)
        : undefined;

    // Push plain literal
    this.ensureLog(self);
    const entry: any = { minute, team, eventType };
    if (noteVal) entry.note = noteVal;
    ((self as any).matchLog as any[]).push(entry);
  }
  static displayName = 'Soccer Match';

  // Teams and setup
  @field homeTeam = contains(TeamField);
  @field awayTeam = contains(TeamField);

  // Match time
  @field currentMinute = contains(NumberField); // 0..90+
  @field addedTime = contains(NumberField); // 0..7
  @field isSecondHalf = contains(BooleanField);
  @field isPaused = contains(BooleanField);
  @field isFinished = contains(BooleanField);

  // State
  @field possession = contains(StringField); // 'home' | 'away'
  @field homeStamina = contains(NumberField); // 0..100
  @field awayStamina = contains(NumberField); // 0..100
  @field score = contains(ScoreField);
  @field homeShots = contains(ShotStatsField);
  @field awayShots = contains(ShotStatsField);

  // Log
  @field matchLog = containsMany(MatchEventField);

  // Computed title from fixture
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SoccerMatch) {
      const h = this.homeTeam?.name ?? 'Home';
      const a = this.awayTeam?.name ?? 'Away';
      return `${h} vs ${a}`;
    },
  });

  // Utility: bounded random
  private rand(min: number, max: number) {
    return Math.random() * (max - min) + min;
  }

  // Simple minute simulation
  // Normalize log entries to plain safe objects
  private normalizeLog(self: SoccerMatch) {
    const log = (self as any).matchLog;
    if (!Array.isArray(log)) return;
    for (let i = 0; i < log.length; i++) {
      const e = log[i];
      if (!e || typeof e !== 'object') {
        log.splice(i, 1);
        i--;
        continue;
      }
      const minuteNum = Number(e.minute);
      const minute = Number.isFinite(minuteNum)
        ? Math.max(0, Math.floor(minuteNum))
        : self.currentMinute ?? 0;
      const team =
        e.team === 'home' || e.team === 'away' || e.team === 'neutral'
          ? e.team
          : 'neutral';
      const eventType = typeof e.eventType === 'string' ? e.eventType : 'event';
      const note = typeof e.note === 'string' ? e.note : undefined;
      log[i] = note
        ? { minute, team, eventType, note }
        : { minute, team, eventType };
    }
  }

  // Normalize momentum series to numbers-only array (filtering invalids)
  private normalizeMomentum(self: SoccerMatch) {
    let series = (self as any).momentumSeries;
    if (!Array.isArray(series)) return;
    for (let i = 0; i < series.length; i++) {
      const n = Number(series[i]);
      if (!Number.isFinite(n)) {
        series.splice(i, 1);
        i--;
        continue;
      }
      // clamp to safe range [-12, 12] to preserve sparkline scale
      const clamped = Math.max(-12, Math.min(12, Math.round(n)));
      series[i] = clamped;
    }
  }

  // store last 12-minute momentum for sparkline
  @field momentumSeries = containsMany(NumberField);

  private simulateMinute = (self: SoccerMatch) => {
    // Inputs
    const hr = self.homeTeam?.rating ?? 75;
    const ar = self.awayTeam?.rating ?? 75;
    const hs = Math.max(10, Math.min(100, self.homeStamina ?? 100));
    const as = Math.max(10, Math.min(100, self.awayStamina ?? 100));
    const minute = (self.currentMinute ?? 0) + 1;

    // Ensure containers exist before mutation
    if (!self.score) self.score = { home: 0, away: 0 } as any;
    if (!self.homeShots) self.homeShots = { shots: 0, onTarget: 0 } as any;
    if (!self.awayShots) self.awayShots = { shots: 0, onTarget: 0 } as any;
    this.ensureLog(self);

    // Possession tilt
    const ratingTilt = (hr - ar) * 0.6;
    const staminaTilt = ((hs - as) / 5) * 0.4;
    const baseTilt = ratingTilt + staminaTilt; // positive → home advantage
    const possessionRoll = this.rand(-10, 10) + baseTilt;
    const attackingSide = possessionRoll >= 0 ? 'home' : 'away';
    self.possession = attackingSide;

    // Track momentum series for sparkline (bounded to last 12 points)
    const momentumPoint = Math.max(-12, Math.min(12, Math.round(baseTilt / 5)));
    let series = (self as any).momentumSeries as number[] | undefined;
    if (!Array.isArray(series)) {
      (self as any).momentumSeries = [momentumPoint] as any;
    } else {
      series.push(momentumPoint);
      if (series.length > 12) series.splice(0, series.length - 12);
    }
    // Sanitize momentum after update
    this.normalizeMomentum(self);

    // Chance of creating an attack in this minute
    const attackChance = 0.35 + Math.abs(baseTilt) / 200; // 0.35—0.6

    const happens = Math.random() < attackChance;
    if (happens) {
      // Shot probability
      const shotChance = 0.65;
      if (Math.random() < shotChance) {
        const onTargetChance = 0.55;
        const isOnTarget = Math.random() < onTargetChance;

        const scoringBias = 0.08 + Math.abs(baseTilt) / 300; // 8%—11% baseline
        const goalChance = isOnTarget ? scoringBias : 0.02;

        const teamKey = attackingSide;
        const teamName =
          teamKey === 'home'
            ? self.homeTeam?.name ?? 'Home'
            : self.awayTeam?.name ?? 'Away';

        // Update shots
        if (teamKey === 'home') {
          self.homeShots.shots = (self.homeShots.shots ?? 0) + 1;
          if (isOnTarget) {
            self.homeShots.onTarget = (self.homeShots.onTarget ?? 0) + 1;
          }
        } else {
          self.awayShots.shots = (self.awayShots.shots ?? 0) + 1;
          if (isOnTarget) {
            self.awayShots.onTarget = (self.awayShots.onTarget ?? 0) + 1;
          }
        }

        // Determine goal/save
        if (Math.random() < goalChance) {
          // Goal
          if (teamKey === 'home') {
            self.score.home = (self.score.home ?? 0) + 1;
          } else {
            self.score.away = (self.score.away ?? 0) + 1;
          }
          this.addEvent(self, {
            minute,
            team: teamKey,
            eventType: 'goal',
            note: `${teamName} score!`,
          });
        } else if (isOnTarget) {
          // Save
          this.addEvent(self, {
            minute,
            team: teamKey,
            eventType: 'save',
            note: `${teamName} denied by the keeper`,
          });
        } else {
          // Shot off target
          this.addEvent(self, {
            minute,
            team: teamKey,
            eventType: 'shot',
            note: `${teamName} shot off target`,
          });
        }
      } else {
        // Non-shot event: foul or offside or corner
        const r = Math.random();
        if (r < 0.5) {
          this.addEvent(self, {
            minute,
            team: attackingSide,
            eventType: 'foul',
            note: 'Foul given',
          });
          if (Math.random() < 0.15) {
            this.addEvent(self, {
              minute,
              team: attackingSide,
              eventType: 'yellow',
              note: 'Booked',
            });
          }
        } else if (r < 0.75) {
          this.addEvent(self, {
            minute,
            team: attackingSide,
            eventType: 'offside',
            note: 'Flag is up',
          });
        } else {
          this.addEvent(self, {
            minute,
            team: attackingSide,
            eventType: 'corner',
            note: 'Corner kick',
          });
        }
      }
    }

    // Apply stamina decay each minute
    self.homeStamina = Math.max(
      0,
      (self.homeStamina ?? 100) - (happens ? 1.2 : 0.6),
    );
    self.awayStamina = Math.max(
      0,
      (self.awayStamina ?? 100) - (happens ? 1.2 : 0.6),
    );

    // Time updates
    self.currentMinute = minute;
    if (!self.isSecondHalf && minute >= 45) {
      self.isSecondHalf = true;
      // Small halftime recovery
      self.homeStamina = Math.min(100, (self.homeStamina ?? 100) + 5);
      self.awayStamina = Math.min(100, (self.awayStamina ?? 100) + 5);
    }

    // Finish at 90 + addedTime
    const nominalEnd = 90 + (self.addedTime ?? 0);
    if (minute >= nominalEnd) {
      self.isFinished = true;
    }

    // Final safety: normalize log after this minute’s updates
    this.ensureLog(self);
    this.normalizeLog(self);

    // Nothing to append here anymore; events are pushed as they occur via addEvent
  };

  static isolated = class Isolated extends Component<typeof SoccerMatch> {
    @tracked fastPlayRunning = false;

    // Build sparkline points for momentumSeries as a space-separated "x,y" list
    get pointsAttr() {
      try {
        const series = (this.args.model as any)?.momentumSeries as
          | number[]
          | undefined;
        if (!Array.isArray(series) || series.length < 2) return '';
        const len = series.length;
        const pts: string[] = [];
        for (let idx = 0; idx < len; idx++) {
          const p = series[idx] ?? 0;
          const x = (idx / (len - 1)) * 120;
          const y = 24 - p * 0.9; // maps [-12..12] roughly into [~34..~13], then clamped by viewBox
          pts.push(`${Math.round(x)},${Math.round(y)}`);
        }
        return pts.join(' ');
      } catch (e) {
        // Fallback in case of unexpected data
        return '';
      }
    }

    get minuteDisplay() {
      const m = this.args.model?.currentMinute ?? 0;
      const add = this.args.model?.addedTime ?? 0;
      const half = this.args.model?.isSecondHalf ? '2H' : '1H';
      return `${m}’ ${half}${add ? ' +' + add : ''}`;
    }

    get scoreline() {
      const h = this.args.model?.score?.home ?? 0;
      const a = this.args.model?.score?.away ?? 0;
      return `${h} - ${a}`;
    }

    private step = () => {
      if (
        !this.args.model ||
        this.args.model.isPaused ||
        this.args.model.isFinished
      )
        return;
      (this.args.model as SoccerMatch as any).simulateMinute(this.args.model);
    };

    private play = restartableTask(async (minutes: number) => {
      this.fastPlayRunning = true;
      for (let i = 0; i < minutes; i++) {
        if (this.args.model?.isPaused || this.args.model?.isFinished) break;
        this.step();
        await timeout(300);
      }
      this.fastPlayRunning = false;
    });

    // Replace perform helper usage with bound methods
    playOne = () => {
      if (!this.args.model?.isPaused && !this.args.model?.isFinished) {
        this.play.perform(1);
      }
    };

    playFive = () => {
      if (!this.args.model?.isPaused && !this.args.model?.isFinished) {
        this.play.perform(5);
      }
    };

    start = () => {
      if (!this.args.model) return;
      this.args.model.isPaused = false;
      if ((this.args.model.currentMinute ?? 0) === 0) {
        // Kickoff event
        this.addEvent(this.args.model as SoccerMatch, {
          minute: 0,
          team: 'neutral',
          eventType: 'kickoff',
          note: 'Kickoff!',
        });
      }
      // Normalize right after possible kickoff insertion
      this.ensureLog(this.args.model as SoccerMatch);
      this.normalizeLog(this.args.model as SoccerMatch);
    };

    pause = () => {
      if (!this.args.model) return;
      this.args.model.isPaused = true;
    };

    reset = () => {
      const m = this.args.model as SoccerMatch;
      if (!m) return;
      m.currentMinute = 0;
      m.addedTime = 2;
      m.isSecondHalf = false;
      m.isPaused = true;
      m.isFinished = false;
      m.possession = 'home';
      m.homeStamina = 100;
      m.awayStamina = 100;

      // Ensure score and stats containers exist before mutation
      if (!m.score) m.score = { home: 0, away: 0 } as any;
      m.score.home = 0;
      m.score.away = 0;

      if (!m.homeShots) m.homeShots = { shots: 0, onTarget: 0 } as any;
      m.homeShots.shots = 0;
      m.homeShots.onTarget = 0;

      if (!m.awayShots) m.awayShots = { shots: 0, onTarget: 0 } as any;
      m.awayShots.shots = 0;
      m.awayShots.onTarget = 0;

      // Clear log in-place without reassigning the array identity
      this.ensureLog(m);
      ((m as any).matchLog as any[]).length = 0;

      // Reset momentum series too
      (m as any).momentumSeries = [] as any;

      // Normalize for safety
      this.normalizeLog(m);
      this.normalizeMomentum(m);
    };

    <template>
      <div class='match'>
        <header class='header'>
          <!-- Live commentary ribbon -->
          <div class='commentary'>
            {{#if (gt @model.matchLog.length 0)}}
              {{#let
                (get @model.matchLog (subtract @model.matchLog.length 1))
                as |last|
              }}
                <span class='tick'>•</span>
                <span class='text'>{{last.minute}}’ —
                  {{last.team}}
                  {{last.eventType}}{{#if last.note}}:
                    {{last.note}}{{/if}}</span>
              {{/let}}
            {{else}}
              <span class='text'>Kickoff when you’re ready.</span>
            {{/if}}
            <!-- Momentum sparkline -->
            <svg
              class='spark'
              viewBox='0 0 120 24'
              preserveAspectRatio='none'
              aria-hidden='true'
            >
              {{! baseline }}
              <line
                x1='0'
                y1='12'
                x2='120'
                y2='12'
                stroke='rgba(0,0,0,0.2)'
                stroke-width='1'
              />
              {{! path constructed from momentumSeries (-12..12 mapped to y) }}
              {{#if (gt @model.momentumSeries.length 1)}}
                {{! Build polyline by sampling series across width (computed in JS to avoid block-in-attribute) }}
                <polyline
                  fill='none'
                  stroke='#2563eb'
                  stroke-width='2'
                  points={{this.pointsAttr}}
                />
              {{/if}}
            </svg>
          </div>

          <div class='teams'>
            <div class='team home'>
              <@fields.homeTeam @format='embedded' />
            </div>
            <div class='score'>
              <@fields.score @format='atom' />
              <div class='time'>{{this.minuteDisplay}}</div>
            </div>
            <div class='team away'>
              <@fields.awayTeam @format='embedded' />
            </div>
          </div>
          <div class='stats'>
            <span>Shots:
              <strong>{{@model.homeShots.shots}}</strong>
              ({{@model.homeShots.onTarget}}) •
              <strong>{{@model.awayShots.shots}}</strong>
              ({{@model.awayShots.onTarget}})</span>
            <span>Stamina: H
              {{formatNumber @model.homeStamina size='short'}}
              • A
              {{formatNumber @model.awayStamina size='short'}}</span>
          </div>
        </header>

        <section class='pitch'>
          <div class='bar'>
            <div class={{concat 'pos ' @model.possession}}></div>
          </div>
          <div class='controls'>
            <Button class='btn' {{on 'click' this.start}}>Start</Button>
            <Button class='btn' {{on 'click' this.pause}}>Pause</Button>
            <Button
              class='btn'
              {{on 'click' this.playOne}}
              disabled={{or @model.isPaused @model.isFinished}}
            >Play +1’</Button>
            <Button
              class='btn'
              {{on 'click' this.playFive}}
              disabled={{or @model.isPaused @model.isFinished}}
            >Play +5’</Button>
            <Button class='btn danger' {{on 'click' this.reset}}>Reset</Button>
          </div>
        </section>

        <section class='log'>
          {{#if (gt @model.matchLog.length 0)}}
            <div class='events'>
              <@fields.matchLog @format='embedded' />
            </div>
          {{else}}
            <div class='empty'>No events yet.</div>
          {{/if}}
        </section>
      </div>

      <style scoped>
        .match {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          padding: 1rem;
          max-height: 100%;
          overflow: auto;
        }
        .commentary {
          display: grid;
          grid-template-columns: auto 1fr auto;
          align-items: center;
          gap: 0.5rem;
          padding: 0.25rem 0.5rem;
          background: #f9fafb;
          border: 1px solid #e5e7eb;
          border-radius: 6px;
          font-size: 0.8125rem;
        }
        .commentary .tick {
          color: #16a34a;
          font-weight: 700;
          margin-right: 0.25rem;
        }
        .commentary .text {
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .commentary .spark {
          width: 120px;
          height: 24px;
        }

        .header .teams {
          display: grid;
          grid-template-columns: 1fr auto 1fr;
          align-items: center;
          gap: 1rem;
        }
        .score {
          display: flex;
          flex-direction: column;
          align-items: center;
        }
        .score .time {
          font-size: 0.8125rem;
          opacity: 0.9;
        }
        .stats {
          display: flex;
          justify-content: center;
          gap: 1rem;
          font-size: 0.8125rem;
          opacity: 0.9;
        }

        .pitch .bar {
          height: 10px;
          background: #e5e7eb;
          border-radius: 6px;
          overflow: hidden;
        }
        .pitch .pos {
          height: 100%;
          width: 50%;
        }
        .pitch .pos.home {
          background: #2563eb;
        }
        .pitch .pos.away {
          background: #dc2626;
          margin-left: 50%;
        }

        .controls {
          display: flex;
          gap: 0.5rem;
          justify-content: center;
        }
        .btn {
          padding: 0.375rem 0.75rem;
          font-size: 0.8125rem;
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
        }
        .btn.danger {
          background: #fee2e2;
        }

        .log .events > .containsMany-field {
          display: flex;
          flex-direction: column;
          gap: 0.375rem;
        }
        .empty {
          text-align: center;
          opacity: 0.7;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof SoccerMatch> {
    <template>
      <div class='line'>
        <span class='fixture'>{{@model.homeTeam.name}}
          vs
          {{@model.awayTeam.name}}</span>
        <span class='score'>{{@model.score.home}}-{{@model.score.away}}</span>
        <span class='minute'>{{@model.currentMinute}}’</span>
      </div>
      <style scoped>
        .line {
          display: flex;
          align-items: baseline;
          gap: 0.5rem;
          font-size: 0.875rem;
        }
        .score {
          font-weight: 700;
        }
        .minute {
          opacity: 0.7;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SoccerMatch> {
    <template>
      <div class='fitted-container'>
        <div class='badge-format'>
          <div class='row'>
            <span class='fixture'>{{@model.homeTeam.name}}
              vs
              {{@model.awayTeam.name}}</span>
            <span
              class='score'
            >{{@model.score.home}}-{{@model.score.away}}</span>
          </div>
          <div class='row sub'><span>{{@model.currentMinute}}’</span></div>
        </div>

        <div class='strip-format'>
          <div class='row'>
            <span class='fixture'>{{@model.homeTeam.name}}
              vs
              {{@model.awayTeam.name}}</span>
            <span
              class='score'
            >{{@model.score.home}}-{{@model.score.away}}</span>
            <span class='minute'>{{@model.currentMinute}}’</span>
          </div>
        </div>

        <div class='tile-format'>
          <div class='top'>
            <div class='fixture'>{{@model.homeTeam.name}}
              vs
              {{@model.awayTeam.name}}</div>
            <div class='score'>{{@model.score.home}}-{{@model.score.away}}</div>
          </div>
          <div class='bottom'>
            <div class='meta'>Shots
              {{@model.homeShots.shots}}/{{@model.homeShots.onTarget}}
              •
              {{@model.awayShots.shots}}/{{@model.awayShots.onTarget}}</div>
            <div class='minute'>{{@model.currentMinute}}’</div>
          </div>
        </div>

        <div class='card-format'>
          <div class='header'>
            <div class='fixture'>{{@model.homeTeam.name}}
              vs
              {{@model.awayTeam.name}}</div>
            <div class='score'>{{@model.score.home}}-{{@model.score.away}}</div>
          </div>
          <div class='footer'>
            <div class='meta'>Stamina H
              {{@model.homeStamina}}
              • A
              {{@model.awayStamina}}</div>
            <div class='minute'>{{@model.currentMinute}}’</div>
          </div>
        </div>
      </div>

      <style scoped>
        .fitted-container {
          width: 100%;
          height: 100%;
          container-type: size;
        }
        .badge-format,
        .strip-format,
        .tile-format,
        .card-format {
          display: none;
          width: 100%;
          height: 100%;
          padding: clamp(0.1875rem, 2%, 0.625rem);
          box-sizing: border-box;
        }
        @container (max-width: 150px) and (max-height: 169px) {
          .badge-format {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }
        }
        @container (min-width: 151px) and (max-height: 169px) {
          .strip-format {
            display: flex;
            align-items: center;
          }
        }
        @container (max-width: 399px) and (min-height: 170px) {
          .tile-format {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }
        }
        @container (min-width: 400px) and (min-height: 170px) {
          .card-format {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }
        }

        .row {
          display: flex;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .fixture {
          font-weight: 600;
          font-size: 0.875rem;
        }
        .score {
          font-weight: 700;
        }
        .meta {
          font-size: 0.75rem;
          opacity: 0.85;
        }
        .minute {
          font-size: 0.75rem;
          opacity: 0.8;
        }
        .top,
        .bottom,
        .header,
        .footer {
          display: flex;
          justify-content: space-between;
          gap: 0.5rem;
        }
      </style>
    </template>
  };
}
