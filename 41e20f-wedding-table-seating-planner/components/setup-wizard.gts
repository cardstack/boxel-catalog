import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { BoxelInput, Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import CalendarHeartIcon from '@cardstack/boxel-icons/calendar-heart';
import CrownIcon from '@cardstack/boxel-icons/crown';
import UsersIcon from '@cardstack/boxel-icons/users';
import Stepper from '@cardstack/catalog/aef6db-stepper/stepper';
import type { StepperStep } from '@cardstack/catalog/aef6db-stepper/stepper';
import LayoutPreview from './layout-preview';
import type { Table } from '../table';
import type { Fixture } from '../fixture';

// First-run setup wizard for the Table Seating Planner. The shell (modal
// scrim, step rail, nav actions) is the shared <Stepper> catalog component;
// this file owns only the four domain steps — event details → hosts (the
// couple) → guests → start from a template (previewed with the LayoutPreview
// SVG) or blank — plus the gold corner ornament. All colors flow from the
// theme's semantic tokens (the planner pins its Parisian defaults when no
// theme is linked), so no wizard-specific palette remains. Talks to the host
// planner only through args. Every step is mandatory: Next stays disabled
// until the step's fields are filled and there is no Skip. The ✕ close is the
// one escape hatch — dismissal isn't persisted, so the wizard reopens the
// next time an incomplete planner is opened.
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
    /** The planner's `hosts` / `guests` linksToMany field components —
     *  rendered fitted inside the wizard so newly added people show up
     *  as cards, not just a count. */
    hostsField?: any;
    guestsField?: any;
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

export default class SetupWizard extends Component<Signature> {
  get steps(): StepperStep[] {
    return [
      {
        id: 'event',
        label: 'Your event',
        summary: 'Event details',
        title: 'Your event',
        description:
          'Tell us about the celebration — name, date, and venue are all needed.',
        icon: CalendarHeartIcon,
        isComplete:
          !!this.args.eventTitle?.trim() &&
          !!this.args.eventDate &&
          !!this.args.venue?.trim(),
      },
      {
        id: 'hosts',
        label: 'Hosts',
        summary: 'The couple',
        title: 'Hosts',
        description:
          "Who's hosting? Add the couple or hosts of the celebration.",
        icon: CrownIcon,
        isComplete: (this.args.hostCount ?? 0) > 0,
      },
      {
        id: 'guests',
        label: 'Guests',
        summary: 'Your guest list',
        title: 'Guests',
        description: 'Add at least one guest to continue.',
        icon: UsersIcon,
        isComplete: (this.args.guestCount ?? 0) > 0,
      },
      {
        id: 'template',
        label: 'Template',
        summary: 'Choose a layout',
        title: 'Start from a template',
        description:
          'Pick a ready-made layout to get a head start, or start with a blank canvas.',
      },
    ];
  }

  stepEntered = (step: StepperStep) => {
    if (step.id === 'template') this.args.onLoadTemplates();
  };
  applyTpl = (index: number) => {
    this.args.onApplyTemplate(index);
  };

  <template>
    <Stepper
      class='wz'
      @modal={{true}}
      @steps={{this.steps}}
      @kicker='Getting started'
      @title='Table Seating Planner'
      @finishLabel='Start blank'
      @onClose={{@onSkip}}
      @onFinish={{@onSkip}}
      @onStepChange={{this.stepEntered}}
      ...attributes
    >
      <:decoration>
        <svg class='wz-corner' viewBox='0 0 100 100' aria-hidden='true'>
          <g fill='none' stroke='currentColor' stroke-width='1'>
            <circle cx='50' cy='50' r='40' /><circle cx='50' cy='50' r='27' />
            <circle cx='50' cy='50' r='14' /><path
              d='M50 4v92M4 50h92M17 17l66 66M83 17l-66 66'
            />
          </g>
        </svg>
      </:decoration>
      <:step as |step|>
        {{#if (eq step.id 'event')}}
          <div class='wz-form'>
            <label class='wz-field'>Event name
              <BoxelInput
                @value={{@eventTitle}}
                placeholder='e.g. Sunway Hotel Wedding Party'
                {{on 'input' @onEventTitle}}
              />
            </label>
            <label class='wz-field'>Date
              <BoxelInput
                @type='date'
                @value={{@eventDate}}
                {{on 'change' @onEventDate}}
              />
            </label>
            <label class='wz-field'>Venue
              <BoxelInput
                @value={{@venue}}
                placeholder='e.g. Grand Ballroom, Level 3'
                {{on 'input' @onVenue}}
              />
            </label>
          </div>
        {{else if (eq step.id 'hosts')}}
          <div class='wz-panel wz-people-panel'>
            {{#if @hostCount}}
              <div class='wz-cards'>
                <@hostsField @format='fitted' />
              </div>
            {{/if}}
            <div class='wz-people-row'>
              <span class='wz-guest-count'>{{if @hostCount @hostCount 0}}
                host(s) added</span>
              <Button
                @kind='secondary'
                class='wz-secondary'
                {{on 'click' @onAddHosts}}
              >Add hosts</Button>
            </div>
          </div>
        {{else if (eq step.id 'guests')}}
          <div class='wz-panel wz-people-panel'>
            {{#if @guestCount}}
              <div class='wz-cards'>
                <@guestsField @format='fitted' />
              </div>
            {{/if}}
            <div class='wz-people-row'>
              <span class='wz-guest-count'>{{if @guestCount @guestCount 0}}
                guest(s) added</span>
              <Button
                @kind='secondary'
                class='wz-secondary'
                {{on 'click' @onAddGuests}}
              >Add guests</Button>
            </div>
          </div>
        {{else}}
          <div class='wz-panel'>
            {{#if @templatesLoading}}
              <p class='wz-empty'>Loading templates…</p>
            {{else if @templates.length}}
              {{#each @templates as |tpl idx|}}
                <Button
                  @kind='text-only'
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
                </Button>
              {{/each}}
            {{else}}
              <p class='wz-empty'>No templates yet — start blank and build your
                own.</p>
            {{/if}}
          </div>
        {{/if}}
      </:step>
    </Stepper>
    <style scoped>
      /* Wizard-specific Stepper knobs — everything else flows from the
         theme's semantic tokens through the Stepper's own chains. */
      .wz {
        /* Rail highlights in gold — the Stepper's default accent chain
           follows --primary (navy here); the wizard wants the accent
           pair instead, with a cream ✓ on the gold fills. */
        --stepper-accent: var(--tsp-accent, var(--accent, #c5a35c));
        --stepper-accent-fg: var(
          --tsp-primary-foreground,
          var(--primary-foreground, #f3ead6)
        );
        --stepper-heading-font: var(
          --font-serif,
          'Cormorant Garamond',
          Georgia,
          serif
        );
        --stepper-kicker-color: var(--tsp-accent-deep, #a5854a);
        --stepper-scrim-bg: color-mix(
          in srgb,
          var(--tsp-primary, var(--primary, #141b33)) 28%,
          transparent
        );
      }
      .wz-corner {
        position: absolute;
        top: -22px;
        right: -22px;
        width: 170px;
        height: 170px;
        color: var(--tsp-accent, var(--accent, #a5854a));
        opacity: 0.05;
        pointer-events: none;
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
        color: var(--tsp-muted-foreground, var(--muted-foreground, #6b6656));
      }
      .wz-field input {
        min-height: 0;
        padding: 10px 12px;
        border: 1px solid
          var(--tsp-border, var(--border, rgba(34, 40, 63, 0.18)));
        border-radius: 10px;
        font-family: var(
          --tsp-font-sans,
          var(--font-sans, 'Jost', system-ui, sans-serif)
        );
        font-size: 14px;
        color: var(--tsp-foreground, var(--foreground, #22283f));
        background: var(--tsp-input, var(--input, #fffdf8));
      }
      .wz-field input:focus {
        outline: none;
        border-color: var(--tsp-ring, var(--ring, #a5854a));
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
        border: 1.5px dashed
          var(--tsp-border, var(--border, rgba(34, 40, 63, 0.2)));
        border-radius: 16px;
      }
      .wz-guest-panel {
        flex: none;
        flex-direction: row;
        align-items: center;
        justify-content: space-between;
      }
      .wz-people-panel {
        flex: none;
        max-height: 100%;
        gap: 12px;
      }
      .wz-people-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }
      /* Newly added people render as fitted cards. The linksToMany
         plural component stacks items vertically; re-lay its wrapper as
         a responsive grid so the panel width is used. */
      .wz-cards {
        overflow-y: auto;
        min-height: 0;
      }
      .wz-cards :deep(.linksToMany-field.fitted-effectiveFormat) {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
        gap: 8px;
      }
      .wz-cards :deep(.linksToMany-itemContainer + .linksToMany-itemContainer) {
        margin-top: 0;
      }
      .wz-guest-count {
        font-size: 14px;
        color: var(--tsp-muted-foreground, var(--muted-foreground, #6b6656));
      }
      .wz-opt {
        display: flex;
        justify-content: flex-start;
        align-items: center;
        gap: 14px;
        padding: 12px 14px;
        border: 1px solid transparent;
        border-radius: 12px;
        background: color-mix(
          in srgb,
          var(--tsp-accent, var(--accent, #a5854a)) 9%,
          transparent
        );
        cursor: pointer;
        text-align: left;
      }
      .wz-opt:hover {
        border-color: var(--tsp-accent, var(--accent, #a5854a));
      }
      .wz-opt-preview {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 108px;
        height: 62px;
        border-radius: 8px;
        background: var(--tsp-card, var(--card, #ffffff));
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
        font-family: var(
          --tsp-font-serif,
          var(--font-serif, 'Cormorant Garamond', Georgia, serif)
        );
        font-size: 18px;
        font-weight: 600;
      }
      .wz-opt-meta {
        font-size: 11px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--tsp-accent-deep, #a5854a);
      }
      .wz-empty {
        margin: auto;
        text-align: center;
        font-size: 13px;
        opacity: 0.65;
      }
      /* Boxel <Button> re-skin for the panel actions */
      .wz-secondary {
        --boxel-button-secondary-background: transparent;
        --boxel-button-secondary-border: color-mix(
          in srgb,
          var(--tsp-accent, var(--accent, #a5854a)) 55%,
          transparent
        );
        --boxel-button-secondary-foreground: var(--tsp-accent-deep, #a5854a);
        --boxel-button-font: 500 13px
          var(--tsp-font-sans, var(--font-sans, 'Jost', system-ui, sans-serif));
        --boxel-button-letter-spacing: 0.04em;
        --boxel-button-padding: 11px 22px;
        --boxel-button-border-radius: 999px;
      }
    </style>
  </template>
}
