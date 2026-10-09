import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { registerDestructor } from '@ember/destroyable';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import ChevronRight from '@cardstack/boxel-icons/chevron-right';

import {
  Dashboard,
  type DashboardTile,
} from '@cardstack/catalog/components/dashboard';
import { slaClock } from '@cardstack/catalog/cards/service-desk/utils/sla-clock';
import { BreachRing } from './breach-ring';
import { LiveClock } from './live-clock';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import {
  timerSnapshot,
  sortByUrgency,
} from '@cardstack/catalog/cards/service-desk/utils/sla';
import { type Hue } from '@cardstack/catalog/components/state-pill';

export interface BreachRiskRow {
  card: any;
  /** Display label; falls back to card.title (some realms use computed cardTitle instead). */
  label?: string;
  timerFacts: any;
  chipLabel?: string;
  chipHue?: Hue;
  queueName?: string;
  ownerName?: string;
  clockKind?: string;
  onAssign?: () => void;
}

export interface QueueLoad {
  name: string;
  open: number;
  agents: number;
  oldestLabel?: string;
  overloaded?: boolean;
  onOpen?: () => void;
}

export interface AckRow {
  levelKey: string;
  label: string;
  ackDueLabel: string;
  overdue?: boolean;
  onOpen?: () => void;
}

interface Signature {
  Args: {
    tiles: DashboardTile[];
    breachRows: BreachRiskRow[];
    queues: QueueLoad[];
    escalations: AckRow[];
    onOpenCard: (card: any) => void;
    /** Context line for the hero: who is at the desk, how many agents, how many open. */
    operatorName?: string;
    agentsOnDuty?: number;
    openCount?: number;
  };
  Element: HTMLElement;
}

// The runway spans "now" to this horizon; anything further sits at the end.
const RUNWAY_MINUTES = 7 * 24 * 60;

/**
 * Command Center — the ops wall.
 *
 * The HERO is the one number that matters: the nearest breach, ticking. Under
 * it a RUNWAY places every running clock on a now→7d axis (Lucas's recorded
 * taste: a hero number and a runway beat a row of stat tiles), so the shape
 * of the day is read in one glance. The Dashboard primitive still renders the
 * secondary counts — quietly, below the hero.
 *
 * The wall's law: EVERY NUMBER IS A DOOR. The empty state is the green state
 * ("Queue clear") — an ops wall with nothing at risk is good news.
 */
export class CommandCenter extends GlimmerComponent<Signature> {
  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    // The wall reads the shared clock, so its counts and order move as
    // deadlines pass rather than freezing at first render.
    slaClock.subscribe();
    registerDestructor(this, () => slaClock.unsubscribe());
  }

  get breachRows() {
    return sortByUrgency(
      this.args.breachRows ?? [],
      (r) => r.timerFacts,
      slaClock.now,
    );
  }

  get hero(): BreachRiskRow | undefined {
    return this.breachRows.find(
      (r) => timerSnapshot(r.timerFacts ?? {}, slaClock.now).state !== 'paused',
    );
  }

  get heroState() {
    return this.hero
      ? timerSnapshot(this.hero.timerFacts, slaClock.now).state
      : 'clear';
  }

  /** The masthead date — a wall says what day it is watching. */
  get today() {
    return new Intl.DateTimeFormat(undefined, {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
    }).format(slaClock.now);
  }

  get breachedCount() {
    return this.breachRows.filter(
      (r) =>
        timerSnapshot(r.timerFacts ?? {}, slaClock.now).state === 'breached',
    ).length;
  }

  /** Runway position 0–100 for a row: breached pins left, ≥7d pins right. */
  runwayLeft = (row: BreachRiskRow) => {
    let snap = timerSnapshot(row.timerFacts ?? {}, slaClock.now);
    let m = snap.remainingMinutes ?? RUNWAY_MINUTES;
    let pct = Math.max(0, Math.min(1, m / RUNWAY_MINUTES));
    // sqrt spreads the near end where the eye needs resolution
    return `${(Math.sqrt(pct) * 100).toFixed(1)}%`;
  };

  runwayStyle = (row: BreachRiskRow, i: number) =>
    `left: ${this.runwayLeft(row)}; --i: ${i};`;

  rowStyle = (i: number) => `--i: ${i};`;

  countdownState = (row: BreachRiskRow) =>
    timerSnapshot(row.timerFacts ?? {}, slaClock.now).state;

  open = (row: { card?: any; onOpen?: () => void }) => {
    if (row.onOpen) row.onOpen();
    else if (row.card) this.args.onOpenCard(row.card);
  };

  assign = (row: BreachRiskRow) => {
    row.onAssign?.();
  };

  loadPercent = (q: QueueLoad) => {
    let per = q.agents > 0 ? q.open / (q.agents * 8) : 1;
    return Math.max(4, Math.min(100, Math.round(per * 100)));
  };

  <template>
    <div class='wall wall-{{this.heroState}}' ...attributes>
      {{! ── HERO WALL: an inverted panel — the room's one big screen ── }}
      <section class='hero hero-{{this.heroState}}' aria-label='Nearest breach'>
        <div class='hero-grid'>
          <div class='hero-main'>
            <span class='hero-eyebrow'>{{this.today}}
              ·
              {{#if this.hero}}Nearest breach{{else}}Breach risk{{/if}}</span>
            {{#if this.hero}}
              <LiveClock @facts={{this.hero.timerFacts}} class='hero-clock' />
              <button
                type='button'
                class='hero-case hit-ext'
                {{on 'click' (fn this.open this.hero)}}
              >
                <span class='hero-case-title'>{{if
                    this.hero.label
                    this.hero.label
                    this.hero.card.cardTitle
                  }}</span>
                <ChevronRight
                  class='hero-cue'
                  role='presentation'
                  width='18'
                  height='18'
                />
              </button>
              <div class='hero-facts'>
                {{#if this.hero.chipLabel}}<StatePill
                    @label={{this.hero.chipLabel}}
                    @hue={{this.hero.chipHue}}
                  />{{/if}}
                <span class='hero-fact'>{{this.hero.clockKind}} clock</span>
                <span
                  class='hero-fact
                    {{unless this.hero.ownerName "hero-fact-warn"}}'
                >{{if
                    this.hero.ownerName
                    this.hero.ownerName
                    'unassigned'
                  }}</span>
                {{#if this.hero.onAssign}}
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @size='xs'
                    class='hit-ext hero-assign'
                    {{on 'click' (fn this.assign this.hero)}}
                  >Assign to me</Button>
                {{/if}}
              </div>
            {{else}}
              <span class='hero-clear'>All clear</span>
              <span class='hero-fact'>No running clock is near its deadline.
                Good watch.</span>
            {{/if}}
          </div>
          <div class='hero-side'>
            {{#if this.hero}}
              <BreachRing
                @facts={{this.hero.timerFacts}}
                @size={{168}}
                @labelled={{true}}
                class='hero-ring'
              />
            {{/if}}
            <dl class='hero-duty'>
              {{#if @operatorName}}<div><dt>at the desk</dt><dd
                  >{{@operatorName}}</dd></div>{{/if}}
              {{#if @agentsOnDuty}}<div><dt>agents on duty</dt><dd
                  >{{@agentsOnDuty}}</dd></div>{{/if}}
              <div><dt>breached</dt><dd
                  class='{{if this.breachedCount "hero-duty-hot"}}'
                >{{this.breachedCount}}</dd></div>
            </dl>
          </div>
        </div>

        {{! ── RUNWAY: the horizon line of the wall — every running clock, now→7d ── }}
        {{#if this.breachRows.length}}
          <div class='runway' aria-label='Time to breach, all open clocks'>
            <div class='runway-track'>
              {{#each this.breachRows as |row idx|}}
                <button
                  type='button'
                  class='runway-dot runway-dot-{{this.countdownState row}}'
                  style={{this.runwayStyle row idx}}
                  title='{{if row.label row.label row.card.cardTitle}}'
                  aria-label='{{if row.label row.label row.card.cardTitle}}'
                  {{on 'click' (fn this.open row)}}
                >
                  <BreachRing @facts={{row.timerFacts}} @size={{18}} />
                </button>
              {{/each}}
            </div>
            <div class='runway-axis'>
              <span class='runway-tick runway-tick-now'>now</span>
              <span class='runway-tick runway-tick-mid'>1d</span>
              <span class='runway-tick runway-tick-end'>7d</span>
            </div>
          </div>
        {{/if}}
      </section>

      {{! ── PULSE RAIL: five doors in one bar, not five tiles ── }}
      <Dashboard @tiles={{@tiles}} class='wall-tiles' />

      <div class='wall-main'>
        <section class='panel panel-primary' aria-label='Breach risk'>
          <div class='panel-head'>
            <h3 class='panel-title'>Breach risk</h3>
            <span class='panel-sub'>nearest first ·
              {{this.breachRows.length}}</span>
          </div>
          <div class='panel-rows'>
            {{#each this.breachRows as |row idx|}}
              <div class='risk-line' style={{this.rowStyle idx}}>
                <button
                  type='button'
                  class='risk-row'
                  {{on 'click' (fn this.open row)}}
                >
                  <BreachRing @facts={{row.timerFacts}} @size={{26}} />
                  <span class='risk-title'>{{if
                      row.label
                      row.label
                      row.card.cardTitle
                    }}</span>
                  {{#if row.chipLabel}}<StatePill
                      @label={{row.chipLabel}}
                      @hue={{row.chipHue}}
                    />{{/if}}
                  <span
                    class='risk-owner {{unless row.ownerName "risk-unowned"}}'
                  >
                    {{if row.ownerName row.ownerName 'unassigned'}}
                  </span>
                  <span class='risk-kind'>{{row.clockKind}}</span>
                  <LiveClock @facts={{row.timerFacts}} class='risk-clock' />
                  <ChevronRight
                    class='risk-cue'
                    role='presentation'
                    width='14'
                    height='14'
                  />
                </button>
                {{#if row.onAssign}}
                  {{#unless row.ownerName}}
                    <Button
                      @tone='primary'
                      @appearance='accent'
                      @size='xs'
                      class='hit-ext'
                      {{on 'click' (fn this.assign row)}}
                    >Assign</Button>
                  {{/unless}}
                {{/if}}
              </div>
            {{else}}
              <p class='wall-clear'>✓ Queue clear — no breach risk.</p>
            {{/each}}
          </div>
        </section>

        <div class='wall-side'>
          <section class='panel' aria-label='Queue load'>
            <div class='panel-head'>
              <h3 class='panel-title'>Queues</h3>
              <span class='panel-sub'>load vs agents on duty</span>
            </div>
            <div class='panel-rows'>
              {{#each @queues as |q idx|}}
                <button
                  type='button'
                  class='queue-row'
                  style={{this.rowStyle idx}}
                  {{on 'click' (fn this.open q)}}
                >
                  <span class='queue-name'>{{q.name}}</span>
                  <ProgressBar
                    class='queue-bar'
                    @value={{this.loadPercent q}}
                    @max={{100}}
                    @hue={{if
                      q.overloaded
                      'var(--warning-ink)'
                      'var(--primary)'
                    }}
                    aria-label='{{q.name}} load'
                  />
                  <span class='queue-nums'>{{q.open}}/{{q.agents}}</span>
                  <span
                    class='queue-oldest {{if q.overloaded "queue-oldest-hot"}}'
                  >{{if q.oldestLabel q.oldestLabel 'ok'}}</span>
                </button>
              {{else}}
                <p class='strip-empty'>No queues yet.</p>
              {{/each}}
            </div>
          </section>
          <section
            class='panel'
            aria-label='Escalations awaiting acknowledgement'
          >
            <div class='panel-head'>
              <h3 class='panel-title'>Awaiting acknowledgement</h3>
              <span class='panel-sub'>{{@escalations.length}}</span>
            </div>
            <div class='panel-rows'>
              {{#each @escalations as |e idx|}}
                <button
                  type='button'
                  class='ack-row'
                  style={{this.rowStyle idx}}
                  {{on 'click' (fn this.open e)}}
                >
                  <span class='ack-level'>{{e.levelKey}}</span>
                  <span class='ack-label'>{{e.label}}</span>
                  <span
                    class='ack-due {{if e.overdue "ack-overdue"}}'
                  >{{e.ackDueLabel}}</span>
                  <ChevronRight
                    class='risk-cue'
                    role='presentation'
                    width='13'
                    height='13'
                  />
                </button>
              {{else}}
                <p class='wall-clear'>✓ Every escalation acknowledged.</p>
              {{/each}}
            </div>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .wall {
        --ease: cubic-bezier(0.22, 1, 0.36, 1);
        /* resolved HERE, before the hero remaps --foreground for its children */
        --hero-base: var(--foreground);
        --hero-ink: var(--background);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        container-type: inline-size;
        /* ambient: the wall breathes the hero's state, faintly, from the top */
        background: radial-gradient(
          60% 18rem at 50% -4rem,
          color-mix(in oklab, var(--hero-hue, var(--primary)) 9%, transparent),
          transparent 70%
        );
      }
      .wall-urgent,
      .wall-breached,
      .hero-urgent,
      .hero-breached {
        --hero-hue: var(--destructive);
      }
      .wall-warning,
      .hero-warning {
        --hero-hue: var(--warning);
      }
      .wall-healthy,
      .wall-clear,
      .hero-healthy,
      .hero-clear {
        --hero-hue: var(--success);
      }

      /* ── hero: the inverted wall panel. Semantic tokens are REMAPPED inside
         it, so every child (clock, ring, pills) reads on the dark ground. ── */
      .hero {
        --hero-ground: color-mix(
          in oklab,
          var(--hero-base) 90%,
          var(--hero-hue)
        );
        --foreground: var(--hero-ink);
        --card-foreground: var(--hero-ink);
        --muted-foreground: color-mix(
          in oklab,
          var(--hero-ink) 62%,
          transparent
        );
        --border: color-mix(in oklab, var(--hero-ink) 18%, transparent);
        /* The -ink tokens resolve against the page's own ground; on the dark
           hero they lift toward the hero's light ink instead. */
        --destructive-ink: color-mix(
          in oklab,
          var(--destructive) 55%,
          var(--hero-ink)
        );
        --warning-ink: color-mix(in oklab, var(--warning) 55%, var(--hero-ink));
        --success-ink: color-mix(in oklab, var(--success) 55%, var(--hero-ink));
        position: relative;
        overflow: hidden;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-lg) var(--boxel-sp-xl) var(--boxel-sp-sm);
        border-radius: calc(var(--boxel-border-radius) * 2);
        color: var(--hero-ink);
        background:
          radial-gradient(
            70% 120% at 88% 0%,
            color-mix(in oklab, var(--hero-hue) 46%, transparent),
            transparent 58%
          ),
          radial-gradient(
            50% 80% at 0% 100%,
            color-mix(in oklab, var(--hero-hue) 22%, transparent),
            transparent 62%
          ),
          var(--hero-ground);
        box-shadow: 0 24px 48px -28px
          color-mix(in oklab, var(--hero-hue) 55%, transparent);
        animation: hero-in 600ms var(--ease) both;
      }
      /* the grain: a dotted field so the dark ground is a surface, not a void */
      .hero::before {
        content: '';
        position: absolute;
        inset: 0;
        pointer-events: none;
        background-image: radial-gradient(
          color-mix(in oklab, var(--hero-ink) 9%, transparent) 1px,
          transparent 1.2px
        );
        background-size: 1.25rem 1.25rem;
        mask-image: linear-gradient(
          180deg,
          transparent,
          black 30%,
          black 70%,
          transparent
        );
      }
      .hero-grid {
        position: relative;
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: var(--boxel-sp-xl);
        align-items: center;
      }
      .hero-main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .hero-eyebrow {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .hero-clock {
        font-size: clamp(3rem, 9cqi, 5.5rem);
        line-height: 0.95;
        font-weight: 650;
        letter-spacing: -0.035em;
        font-variant-numeric: tabular-nums;
      }
      .hero-clear {
        font-size: clamp(3rem, 9cqi, 5.5rem);
        line-height: 0.95;
        font-weight: 650;
        letter-spacing: -0.035em;
        color: var(--success-ink);
      }
      .hero-case {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        padding: 0;
        border: none;
        background: none;
        font: inherit;
        color: inherit;
        cursor: pointer;
        text-align: left;
        min-width: 0;
        max-width: 100%;
      }
      .hero-case-title {
        font-size: var(--boxel-font-size-lg);
        font-weight: 500;
        line-height: 1.3;
        overflow: hidden;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
      }
      .hero-case:hover .hero-cue,
      .hero-case:focus-visible .hero-cue {
        transform: translateX(0.25rem);
      }
      .hero-case:focus-visible {
        outline: 2px solid var(--hero-ink);
        outline-offset: 4px;
        border-radius: var(--boxel-border-radius-sm);
      }
      .hero-cue {
        flex: none;
        color: var(--muted-foreground);
        transition: transform 180ms var(--ease);
      }
      .hero-facts {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-4xs);
      }
      .hero-fact {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .hero-fact-warn {
        color: var(--warning-ink);
        font-style: italic;
      }
      .hero-assign {
        margin-left: var(--boxel-sp-4xs);
      }
      .hero-side {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-sm);
      }
      .hero-ring {
        flex: none;
        filter: drop-shadow(
          0 10px 28px color-mix(in oklab, var(--hero-hue) 55%, transparent)
        );
      }
      .hero-breached .hero-ring,
      .hero-urgent .hero-ring {
        animation: ring-breathe 2.8s ease-in-out infinite;
      }
      .hero-duty {
        display: flex;
        gap: var(--boxel-sp);
        margin: 0;
      }
      .hero-duty div {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.125rem;
      }
      .hero-duty dt {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .hero-duty dd {
        margin: 0;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      .hero-duty-hot {
        color: var(--destructive-ink);
      }
      @container (width < 48rem) {
        .hero-grid {
          grid-template-columns: 1fr;
        }
        .hero-side {
          flex-direction: row;
          justify-content: space-between;
          width: 100%;
        }
      }

      /* ── runway: the hero's horizon line ── */
      .runway {
        position: relative;
        padding: 0 var(--boxel-sp-xs);
      }
      .runway-track {
        position: relative;
        height: 2.25rem;
        border-top: 1px solid var(--border);
        background: linear-gradient(
          90deg,
          color-mix(in oklab, var(--destructive) 28%, transparent),
          color-mix(in oklab, var(--warning) 14%, transparent) 30%,
          transparent 60%
        );
      }
      .runway-axis {
        position: relative;
        height: 1rem;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .runway-tick {
        position: absolute;
        top: 0;
        transform: translateX(-50%);
      }
      .runway-tick-now {
        left: 0;
        transform: none;
      }
      .runway-tick-mid {
        left: 37.8%;
      }
      .runway-tick-end {
        right: 0;
        transform: none;
      }
      .runway-dot {
        position: absolute;
        top: 0.5rem;
        transform: translateX(-50%);
        padding: 0.125rem;
        border: none;
        border-radius: 50%;
        background: var(--hero-ground);
        cursor: pointer;
        line-height: 0;
        box-shadow:
          0 0 0 1px var(--border),
          0 0 14px color-mix(in oklab, var(--hero-ink) 18%, transparent);
        animation: dot-in 500ms var(--ease) both;
        animation-delay: calc(var(--i) * 60ms);
        transition:
          transform 160ms var(--ease),
          left 800ms ease-out;
      }
      .runway-dot:hover,
      .runway-dot:focus-visible {
        transform: translateX(-50%) scale(1.3);
        z-index: 2;
      }
      .runway-dot:focus-visible {
        outline: 2px solid var(--hero-ink);
        outline-offset: 2px;
      }

      /* ── pulse rail: the Dashboard primitive, drawn as ONE bar ── */
      .wall-tiles :deep(.dash) {
        gap: 0;
        border-radius: calc(var(--boxel-border-radius) * 1.5);
        background: var(--card);
        box-shadow: 0 1px 0
          color-mix(in oklab, var(--foreground) 7%, transparent);
        overflow: hidden;
      }
      .wall-tiles :deep(.tile) {
        border-radius: 0;
        border-color: transparent;
        border-left: 1px solid
          color-mix(in oklab, var(--foreground) 8%, transparent);
      }
      .wall-tiles :deep(.tile:first-child) {
        border-left-color: transparent;
      }
      .wall-tiles :deep(.tile-door:hover),
      .wall-tiles :deep(.tile-door:focus-visible) {
        transform: none;
        box-shadow: inset 0 -3px 0 var(--tile-accent, var(--primary));
        background: color-mix(
          in oklab,
          var(--tile-accent, var(--primary)) 6%,
          var(--card)
        );
      }

      /* ── panels: one primitive for every grounded block below the hero ── */
      .wall-main {
        display: grid;
        grid-template-columns: minmax(0, 1.6fr) minmax(18rem, 1fr);
        gap: var(--boxel-sp);
        align-items: start;
      }
      .wall-side {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      @container (width < 68rem) {
        .wall-main {
          grid-template-columns: 1fr;
        }
      }
      .panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        padding: var(--boxel-sp-sm) var(--boxel-sp) var(--boxel-sp-xs);
        border-radius: calc(var(--boxel-border-radius) * 1.5);
        background: var(--card);
        color: var(--card-foreground);
        box-shadow: 0 1px 0
          color-mix(in oklab, var(--foreground) 7%, transparent);
      }
      .panel-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .panel-title {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        letter-spacing: 0.01em;
      }
      .panel-sub {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .panel-rows {
        display: flex;
        flex-direction: column;
      }
      /* WCAG 2.5.8: the drawn control stays compact, the hit area is ~2.75rem tall. */
      .hit-ext {
        position: relative;
      }
      .hit-ext::after {
        content: '';
        position: absolute;
        inset: -0.625rem 0;
      }
      .risk-line {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
      }
      .risk-line > .risk-row {
        flex: 1;
        min-width: 0;
      }
      .risk-row,
      .queue-row,
      .ack-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-width: 0;
        width: 100%;
        min-height: 2.75rem;
        text-align: left;
        border: none;
        border-bottom: 1px solid
          color-mix(in oklab, var(--foreground) 7%, transparent);
        border-radius: 0;
        background: transparent;
        color: inherit;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        margin: 0 calc(-1 * var(--boxel-sp-xs));
        width: calc(100% + 2 * var(--boxel-sp-xs));
        cursor: pointer;
        font: inherit;
        transition: background-color 140ms ease-out;
        animation: row-in 420ms var(--ease) both;
        animation-delay: calc(var(--i, 0) * 45ms);
      }
      .panel-rows > :last-child {
        border-bottom-color: transparent;
      }
      .risk-row:hover,
      .queue-row:hover,
      .ack-row:hover,
      .risk-row:focus-visible,
      .queue-row:focus-visible,
      .ack-row:focus-visible {
        background: color-mix(in oklab, var(--primary) 7%, transparent);
        border-radius: var(--boxel-border-radius-sm);
      }
      .risk-row:focus-visible,
      .queue-row:focus-visible,
      .ack-row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -2px;
      }
      .risk-title {
        font-weight: 500;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        flex: 1;
        min-width: 0;
      }
      .risk-owner,
      .risk-kind {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .risk-unowned {
        color: var(--warning-ink);
        font-style: italic;
      }
      .risk-clock {
        font-size: var(--boxel-font-size-sm);
        min-width: 4.5rem;
        text-align: right;
      }
      .risk-cue {
        flex: none;
        color: var(--muted-foreground);
        transition: transform 160ms var(--ease);
      }
      .risk-row:hover .risk-cue,
      .ack-row:hover .risk-cue {
        transform: translateX(0.1875rem);
      }
      .wall-clear {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-radius: var(--boxel-border-radius);
        color: var(--success-ink);
        background: color-mix(in oklab, var(--success) 9%, var(--card));
        font-size: var(--boxel-font-size-sm);
      }
      .strip-empty {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-style: italic;
      }
      .queue-name {
        width: 6.5rem;
        flex: none;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: var(--boxel-font-size-sm);
      }
      .queue-bar {
        flex: 1;
      }
      .queue-nums {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .queue-oldest {
        font-size: var(--boxel-font-size-xs);
        color: var(--success-ink);
        white-space: nowrap;
      }
      .queue-oldest-hot {
        color: var(--warning-ink);
      }
      .ack-level {
        flex: none;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-xs);
        border: 1px solid var(--primary);
        color: color-mix(in oklab, var(--primary) 38%, var(--card-foreground));
        border-radius: var(--boxel-border-radius-sm);
        padding: 0.0625rem 0.4375rem;
      }
      .ack-label {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: var(--boxel-font-size-sm);
        font-weight: 500;
      }
      .ack-due {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        white-space: nowrap;
      }
      .ack-overdue {
        color: var(--destructive-ink);
        font-weight: 600;
        animation: breathe 2.4s ease-in-out infinite;
      }

      @keyframes hero-in {
        from {
          opacity: 0;
          transform: translateY(0.875rem) scale(0.985);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @keyframes ring-breathe {
        0%,
        100% {
          transform: scale(1);
        }
        50% {
          transform: scale(1.035);
        }
      }
      @keyframes row-in {
        from {
          opacity: 0;
          transform: translateY(0.5rem);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @keyframes dot-in {
        from {
          opacity: 0;
          transform: translateX(-50%) scale(0.6);
        }
        to {
          opacity: 1;
          transform: translateX(-50%) scale(1);
        }
      }
      @keyframes breathe {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .hero,
        .hero-ring,
        .risk-row,
        .queue-row,
        .ack-row,
        .runway-dot,
        .ack-overdue {
          animation: none;
        }
        .risk-row,
        .queue-row,
        .ack-row,
        .runway-dot,
        .risk-cue,
        .hero-cue {
          transition: none;
        }
      }
    </style>
  </template>
}

export default CommandCenter;
