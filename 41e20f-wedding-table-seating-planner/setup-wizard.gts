import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import CalendarHeartIcon from '@cardstack/boxel-icons/calendar-heart';
import CrownIcon from '@cardstack/boxel-icons/crown';
import UsersIcon from '@cardstack/boxel-icons/users';
import LayoutPreview from './components/layout-preview';
import type { Table } from './table';
import type { Fixture } from './fixture';

// First-run setup wizard for the Table Seating Planner. Self-contained and
// composable: owns its own step state + styling, talks to the host planner only
// through args. Two-pane layout — a vertical stepper on the left, the active
// step's content on the right. Steps: event details → hosts (the couple) →
// guests → start from a template (previewed with the LayoutPreview SVG) or blank.
interface TemplateLike {
  name?: string | null;
  tableCount?: number | null;
  seatCount?: number | null;
  tables?: Table[];
  fixtures?: Fixture[];
}

interface Signature {
  Element: HTMLDivElement;
  Args: {
    eventTitle?: string | null;
    venue?: string | null;
    eventDate?: string | null;
    hostCount?: number;
    guestCount?: number;
    templates?: TemplateLike[];
    templatesLoading?: boolean;
    onEventTitle: (e: Event) => void;
    onVenue: (e: Event) => void;
    onEventDate: (e: Event) => void;
    onAddHosts: () => void;
    onAddGuests: () => void;
    onLoadTemplates: () => void;
    onApplyTemplate: (index: number) => void;
    onSkip: () => void;
  };
}

const LAST_STEP = 4;

export default class SetupWizard extends Component<Signature> {
  @tracked step = 1;

  get step1Done(): boolean {
    return !!this.args.eventTitle && this.args.eventTitle.trim().length > 0;
  }
  get step2Done(): boolean {
    return (this.args.hostCount ?? 0) > 0;
  }
  get step3Done(): boolean {
    return (this.args.guestCount ?? 0) > 0;
  }
  get canProceed(): boolean {
    if (this.step === 1) return this.step1Done;
    if (this.step === 2) return this.step2Done;
    if (this.step === 3) return this.step3Done;
    return true;
  }
  get nextDisabled(): boolean {
    return !this.canProceed;
  }
  get isLastStep(): boolean {
    return this.step === LAST_STEP;
  }

  private enter = (step: number) => {
    this.step = step;
    if (step === LAST_STEP) this.args.onLoadTemplates();
  };
  next = () => {
    if (this.step < LAST_STEP) this.enter(this.step + 1);
  };
  back = () => {
    if (this.step > 1) this.step -= 1;
  };
  skipStep = () => {
    if (this.step < LAST_STEP) this.enter(this.step + 1);
    else this.args.onSkip();
  };
  applyTpl = (index: number) => {
    this.args.onApplyTemplate(index);
  };

  <template>
    <div class='wz-scrim' ...attributes>
      <div class='wz-card'>
        <svg
          class='wz-corner wz-corner-tr'
          viewBox='0 0 100 100'
          aria-hidden='true'
        >
          <g fill='none' stroke='currentColor' stroke-width='1'>
            <circle cx='50' cy='50' r='40' /><circle cx='50' cy='50' r='27' />
            <circle cx='50' cy='50' r='14' /><path
              d='M50 4v92M4 50h92M17 17l66 66M83 17l-66 66'
            />
          </g>
        </svg>

        <div class='wz-top'>
          <div class='wz-brand'>
            <span class='wz-kicker'>Getting started</span>
            <span class='wz-brand-name'>Table Seating Planner</span>
          </div>
          <button
            type='button'
            class='wz-close'
            aria-label='Close setup'
            {{on 'click' @onSkip}}
          >&#10005; Close</button>
        </div>

        <div class='wz-body'>
          <ol class='wz-rail'>
            <li
              class='wz-step
                {{if this.step1Done "is-done"}}
                {{if (eq this.step 1) "is-active"}}'
            >
              <span class='wz-dot'>{{if this.step1Done '✓' '1'}}</span>
              <span class='wz-step-txt'>
                <span class='wz-step-k'>Step 01</span>
                <span class='wz-step-l'>Your event</span>
                <span class='wz-step-s'>{{if
                    this.step1Done
                    'Completed'
                    'Event details'
                  }}</span>
              </span>
            </li>
            <li
              class='wz-step
                {{if this.step2Done "is-done"}}
                {{if (eq this.step 2) "is-active"}}'
            >
              <span class='wz-dot'>{{if this.step2Done '✓' '2'}}</span>
              <span class='wz-step-txt'>
                <span class='wz-step-k'>Step 02</span>
                <span class='wz-step-l'>Hosts</span>
                <span class='wz-step-s'>{{if
                    this.step2Done
                    'Completed'
                    'The couple'
                  }}</span>
              </span>
            </li>
            <li
              class='wz-step
                {{if this.step3Done "is-done"}}
                {{if (eq this.step 3) "is-active"}}'
            >
              <span class='wz-dot'>{{if this.step3Done '✓' '3'}}</span>
              <span class='wz-step-txt'>
                <span class='wz-step-k'>Step 03</span>
                <span class='wz-step-l'>Guests</span>
                <span class='wz-step-s'>{{if
                    this.step3Done
                    'Completed'
                    'Your guest list'
                  }}</span>
              </span>
            </li>
            <li class='wz-step {{if (eq this.step 4) "is-active"}}'>
              <span class='wz-dot'>4</span>
              <span class='wz-step-txt'>
                <span class='wz-step-k'>Step 04</span>
                <span class='wz-step-l'>Template</span>
                <span class='wz-step-s'>Choose a layout</span>
              </span>
            </li>
          </ol>

          <div class='wz-main'>
            {{#if (eq this.step 1)}}
              <div class='wz-lead'><CalendarHeartIcon
                  width='26'
                  height='26'
                /></div>
              <h1 class='wz-title'>Your event</h1>
              <p class='wz-sub'>Tell us about the celebration.</p>
              <div class='wz-form'>
                <label class='wz-field'>Event name
                  <input
                    type='text'
                    value={{@eventTitle}}
                    placeholder='e.g. Lucas & Amy'
                    {{on 'input' @onEventTitle}}
                  />
                </label>
                <label class='wz-field'>Date
                  <input
                    type='date'
                    value={{@eventDate}}
                    {{on 'change' @onEventDate}}
                  />
                </label>
                <label class='wz-field'>Venue
                  <input
                    type='text'
                    value={{@venue}}
                    placeholder='e.g. Sunway Hotel'
                    {{on 'input' @onVenue}}
                  />
                </label>
              </div>
            {{else if (eq this.step 2)}}
              <div class='wz-lead'><CrownIcon width='26' height='26' /></div>
              <h1 class='wz-title'>Hosts</h1>
              <p class='wz-sub'>Who's hosting? Add the couple or hosts of the
                celebration.</p>
              <div class='wz-panel wz-guest-panel'>
                <span class='wz-guest-count'>{{if @hostCount @hostCount 0}}
                  host(s) added</span>
                <button
                  type='button'
                  class='wz-btn wz-secondary'
                  {{on 'click' @onAddHosts}}
                >Add hosts</button>
              </div>
            {{else if (eq this.step 3)}}
              <div class='wz-lead'><UsersIcon width='26' height='26' /></div>
              <h1 class='wz-title'>Guests</h1>
              <p class='wz-sub'>Add your guest list now, or skip and add them
                later.</p>
              <div class='wz-panel wz-guest-panel'>
                <span class='wz-guest-count'>{{if @guestCount @guestCount 0}}
                  guest(s) added</span>
                <button
                  type='button'
                  class='wz-btn wz-secondary'
                  {{on 'click' @onAddGuests}}
                >Add guests</button>
              </div>
            {{else}}
              <h1 class='wz-title'>Start from a template</h1>
              <p class='wz-sub'>Pick a ready-made layout to get a head start, or
                start with a blank canvas.</p>
              <div class='wz-panel'>
                {{#if @templatesLoading}}
                  <p class='wz-empty'>Loading templates…</p>
                {{else if @templates.length}}
                  {{#each @templates as |tpl idx|}}
                    <button
                      type='button'
                      class='wz-opt'
                      {{on 'click' (fn this.applyTpl idx)}}
                    >
                      <span class='wz-opt-preview'>
                        <LayoutPreview
                          @tables={{tpl.tables}}
                          @fixtures={{tpl.fixtures}}
                        />
                      </span>
                      <span class='wz-opt-text'>
                        <span class='wz-opt-name'>{{if
                            tpl.name
                            tpl.name
                            'Untitled template'
                          }}</span>
                        <span class='wz-opt-meta'>{{if
                            tpl.tableCount
                            tpl.tableCount
                            0
                          }}
                          tables ·
                          {{if tpl.seatCount tpl.seatCount 0}}
                          seats</span>
                      </span>
                    </button>
                  {{/each}}
                {{else}}
                  <p class='wz-empty'>No templates yet — start blank and build
                    your own.</p>
                {{/if}}
              </div>
            {{/if}}

            <div class='wz-actions'>
              {{#unless (eq this.step 1)}}
                <button
                  type='button'
                  class='wz-ghost'
                  {{on 'click' this.back}}
                >Back</button>
              {{/unless}}
              {{#if this.isLastStep}}
                <button
                  type='button'
                  class='wz-btn wz-primary'
                  {{on 'click' @onSkip}}
                >Start blank</button>
              {{else}}
                <button
                  type='button'
                  class='wz-ghost'
                  {{on 'click' this.skipStep}}
                >Skip</button>
                <button
                  type='button'
                  class='wz-btn wz-primary'
                  disabled={{this.nextDisabled}}
                  {{on 'click' this.next}}
                >Next</button>
              {{/if}}
            </div>
          </div>
        </div>
      </div>
    </div>
    <style scoped>
      .wz-scrim {
        position: absolute;
        inset: 0;
        z-index: 200;
        display: grid;
        place-items: center;
        padding: 16px;
        background: rgba(20, 27, 51, 0.28);
        backdrop-filter: blur(2px);
      }
      .wz-card {
        --wz-ink: #22283f;
        --wz-gold: #a5854a;
        --wz-navy: #141b33;
        --wz-serif: 'Cormorant Garamond', Georgia, serif;
        --wz-sans: 'Jost', system-ui, sans-serif;
        box-sizing: border-box;
        position: relative;
        display: flex;
        flex-direction: column;
        width: 100%;
        height: 100%;
        padding: 26px 30px;
        overflow: hidden;
        background: #ffffff;
        border-radius: 18px;
        box-shadow: 0 20px 60px rgba(20, 27, 51, 0.28);
        font-family: var(--wz-sans);
        color: var(--wz-ink);
      }
      .wz-corner {
        position: absolute;
        width: 170px;
        height: 170px;
        color: var(--wz-gold);
        opacity: 0.05;
        pointer-events: none;
      }
      .wz-corner-tr {
        top: -22px;
        right: -22px;
      }
      .wz-top {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
      }
      .wz-brand {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      .wz-kicker {
        font-size: 10px;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(--wz-gold);
      }
      .wz-brand-name {
        font-family: var(--wz-serif);
        font-size: 21px;
        font-weight: 600;
      }
      .wz-close {
        border: none;
        background: none;
        cursor: pointer;
        font-family: var(--wz-sans);
        font-size: 13px;
        color: var(--wz-ink);
        opacity: 0.6;
      }
      .wz-close:hover {
        opacity: 1;
      }
      .wz-body {
        flex: 1;
        min-height: 0;
        display: flex;
        gap: 32px;
        margin-top: 18px;
      }
      .wz-rail {
        flex: none;
        width: 232px;
        margin: 0;
        padding: 22px 18px;
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 24px;
        border: 1px solid rgba(34, 40, 63, 0.1);
        border-radius: 16px;
        background: #fdfaf2;
      }
      .wz-step {
        position: relative;
        display: flex;
        gap: 14px;
      }
      .wz-step:not(:last-child)::before {
        content: '';
        position: absolute;
        left: 15px;
        top: 34px;
        bottom: -24px;
        width: 2px;
        background: rgba(34, 40, 63, 0.12);
      }
      .wz-step.is-done:not(:last-child)::before {
        background: var(--wz-gold);
      }
      .wz-dot {
        flex: none;
        width: 32px;
        height: 32px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 2px solid rgba(34, 40, 63, 0.18);
        background: #ffffff;
        color: rgba(34, 40, 63, 0.5);
        font-size: 12px;
        font-weight: 600;
        z-index: 1;
      }
      .wz-step.is-done .wz-dot {
        background: var(--wz-gold);
        border-color: var(--wz-gold);
        color: #ffffff;
      }
      .wz-step.is-active .wz-dot {
        border-color: var(--wz-gold);
        color: var(--wz-gold);
        box-shadow: 0 0 0 4px
          color-mix(in srgb, var(--wz-gold) 16%, transparent);
      }
      .wz-step-txt {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-top: 2px;
      }
      .wz-step-k {
        font-size: 10px;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: rgba(34, 40, 63, 0.45);
      }
      .wz-step-l {
        font-family: var(--wz-serif);
        font-size: 18px;
        font-weight: 600;
      }
      .wz-step.is-active .wz-step-l {
        color: var(--wz-gold);
      }
      .wz-step-s {
        font-size: 11px;
        color: rgba(34, 40, 63, 0.45);
      }
      .wz-step.is-done .wz-step-s {
        color: var(--wz-gold);
      }
      .wz-main {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
      }
      .wz-lead {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: color-mix(in srgb, var(--wz-gold) 14%, transparent);
        color: var(--wz-gold);
      }
      .wz-title {
        margin: 12px 0 0;
        font-family: var(--wz-serif);
        font-size: 32px;
        font-weight: 600;
      }
      .wz-sub {
        margin: 6px 0 0;
        font-size: 14px;
        color: rgba(34, 40, 63, 0.65);
        max-width: 54ch;
      }
      .wz-form {
        display: flex;
        flex-direction: column;
        gap: 14px;
        margin-top: 20px;
        max-width: 460px;
      }
      .wz-field {
        display: flex;
        flex-direction: column;
        gap: 4px;
        font-size: 12px;
        letter-spacing: 0.04em;
        color: rgba(34, 40, 63, 0.7);
      }
      .wz-field input {
        padding: 10px 12px;
        border: 1px solid rgba(34, 40, 63, 0.18);
        border-radius: 10px;
        font-family: var(--wz-sans);
        font-size: 14px;
        color: var(--wz-ink);
      }
      .wz-field input:focus {
        outline: none;
        border-color: var(--wz-gold);
      }
      .wz-panel {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        margin-top: 20px;
        padding: 16px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        border: 1.5px dashed rgba(34, 40, 63, 0.2);
        border-radius: 16px;
      }
      .wz-guest-panel {
        flex: none;
        flex-direction: row;
        align-items: center;
        justify-content: space-between;
      }
      .wz-guest-count {
        font-size: 14px;
        color: rgba(34, 40, 63, 0.7);
      }
      .wz-opt {
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 12px 14px;
        border: 1px solid transparent;
        border-radius: 12px;
        background: color-mix(in srgb, var(--wz-gold) 9%, transparent);
        cursor: pointer;
        text-align: left;
      }
      .wz-opt:hover {
        border-color: var(--wz-gold);
      }
      .wz-opt-preview {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 108px;
        height: 62px;
        border-radius: 8px;
        background: #ffffff;
        overflow: hidden;
      }
      .wz-opt-preview :deep(svg) {
        width: 100%;
        height: 100%;
      }
      .wz-opt-text {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
      }
      .wz-opt-name {
        font-family: var(--wz-serif);
        font-size: 18px;
        font-weight: 600;
      }
      .wz-opt-meta {
        font-size: 11px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--wz-gold);
      }
      .wz-empty {
        margin: auto;
        text-align: center;
        font-size: 13px;
        opacity: 0.65;
      }
      .wz-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 10px;
        margin-top: 18px;
      }
      .wz-ghost {
        border: none;
        background: none;
        cursor: pointer;
        font-family: var(--wz-sans);
        font-size: 13px;
        color: var(--wz-ink);
        opacity: 0.65;
      }
      .wz-btn {
        border: 1px solid transparent;
        border-radius: 999px;
        cursor: pointer;
        font-family: var(--wz-sans);
        font-size: 13px;
        letter-spacing: 0.04em;
        padding: 11px 22px;
      }
      .wz-btn:disabled {
        opacity: 0.45;
        cursor: not-allowed;
      }
      .wz-primary {
        background: var(--wz-navy);
        color: #ffffff;
      }
      .wz-secondary {
        background: transparent;
        border-color: rgba(197, 163, 92, 0.55);
        color: var(--wz-gold);
      }
    </style>
  </template>
}
