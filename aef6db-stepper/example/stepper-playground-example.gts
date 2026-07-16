import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { tracked } from '@glimmer/tracking';

import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { BoxelSelect } from '@cardstack/boxel-ui/components';
import UserIcon from '@cardstack/boxel-icons/user';
import SettingsIcon from '@cardstack/boxel-icons/settings';
import UsersIcon from '@cardstack/boxel-icons/users';
import RocketIcon from '@cardstack/boxel-icons/rocket';

import Stepper from '../stepper';
import type { StepperStep } from '../stepper';
import CodeSnippet from '../../components/code-snippet';

/**
 * A config explorer for `<Stepper>` — the multi-step "guideline book"
 * shell that walks a user through a journey (a first-run wizard, an
 * onboarding flow) before they start using an app. The playground runs a
 * live 4-step demo whose completion gating is REAL: step 1 completes
 * when you type a name, step 2 when you pick a workspace — exactly how a
 * product wires `isComplete` to its own state. Knobs toggle modal mode
 * and rail jumping; colors, fonts, and radius come from the linked theme
 * (cardInfo.theme) via the semantic tokens — link a different Theme card
 * and the whole stepper restyles.
 */
class StepperPlaygroundIsolated extends Component<typeof StepperPlayground> {
  // ── knobs ──
  modalOptions = ['inline', 'modal'];
  jumpOptions = ['off', 'on'];

  @tracked modalOn = false;
  @tracked jumpOn = false;

  setModal = (value: string): void => {
    this.modalOn = value === 'modal';
    // Re-open the demo when switching into modal so there is something
    // to see behind the knob.
    if (this.modalOn) this.dismissed = false;
  };
  setJump = (value: string): void => {
    this.jumpOn = value === 'on';
  };

  get modalChoice(): string {
    return this.modalOn ? 'modal' : 'inline';
  }
  get jumpChoice(): string {
    return this.jumpOn ? 'on' : 'off';
  }

  // ── demo state the steps gate on (host-owned, like a real product) ──
  @tracked name = '';
  @tracked workspace: string | undefined = undefined;
  @tracked invited = 0;
  @tracked dismissed = false;
  @tracked lastEvent = '—';

  workspaceOptions = ['Personal', 'Team', 'Enterprise'];

  setName = (event: Event): void => {
    this.name = (event.target as HTMLInputElement).value;
  };
  setWorkspace = (value: string): void => {
    this.workspace = value;
  };
  invite = (): void => {
    this.invited += 1;
  };

  /** The playground's step definitions — `isComplete` is wired to live
   *  demo state, so Next unlocks the moment the step's input is filled. */
  get steps(): StepperStep[] {
    return [
      {
        id: 'details',
        label: 'Your details',
        summary: 'Name yourself',
        title: 'Your details',
        description: 'Type a name below — Next unlocks when it is non-empty.',
        icon: UserIcon,
        isComplete: this.name.trim().length > 0,
      },
      {
        id: 'workspace',
        label: 'Workspace',
        summary: 'Pick a plan',
        title: 'Workspace',
        description: 'Pick a workspace type to complete this step.',
        icon: SettingsIcon,
        isComplete: this.workspace !== undefined,
      },
      {
        id: 'team',
        label: 'Invite team',
        summary: 'Optional',
        title: 'Invite team',
        description:
          'This step sets optional: true, so a Skip button appears (MUI-style optional step). The two steps before it are linear — no Skip. It also has no isComplete, so Next never gates.',
        icon: UsersIcon,
        optional: true,
      },
      {
        id: 'launch',
        label: 'Launch',
        summary: 'Ready to go',
        title: 'Ready to launch',
        description:
          'The last step swaps Skip/Next for a single finish button (@finishLabel / @onFinish).',
        icon: RocketIcon,
      },
    ];
  }

  stepEntered = (step: StepperStep, index: number): void => {
    this.lastEvent = `onStepChange → '${step.id}' (index ${index})`;
  };
  handleClose = (): void => {
    this.lastEvent = 'onClose fired';
    this.dismissed = true;
  };
  handleFinish = (): void => {
    this.lastEvent = 'onFinish fired';
    this.dismissed = true;
  };
  reopen = (): void => {
    this.dismissed = false;
  };

  /** Generated invocation reflecting every current selection. */
  get previewCode(): string {
    const lines = [`<Stepper`];
    if (this.modalOn) lines.push(`  @modal={{true}}`);
    lines.push(
      `  @steps={{this.steps}}`,
      `  @kicker='Getting started'`,
      `  @title='Stepper Playground'`,
      `  @finishLabel='Launch app'`,
      `  @onClose={{this.handleClose}}`,
      `  @onFinish={{this.handleFinish}}`,
      `  @onStepChange={{this.stepEntered}}`,
    );
    if (this.jumpOn) lines.push(`  @allowStepJump={{true}}`);
    lines.push(
      `>`,
      `  <:step as |step api|>`,
      `    {{#if (eq step.id 'details')}} …details form… {{/if}}`,
      `  </:step>`,
      `</Stepper>`,
    );
    return lines.join('\n');
  }

  <template>
    <div class='sp'>
      <div class='sp-section'>Live preview
        <span class='sp-event'>last event: {{this.lastEvent}}</span></div>
      <div class='sp-stage'>
        {{#if this.dismissed}}
          <button
            type='button'
            class='sp-reopen'
            {{on 'click' this.reopen}}
          >Wizard closed — click to reopen</button>
        {{else}}
          <Stepper
            @modal={{this.modalOn}}
            @steps={{this.steps}}
            @kicker='Getting started'
            @title='Stepper Playground'
            @finishLabel='Launch app'
            @onClose={{this.handleClose}}
            @onFinish={{this.handleFinish}}
            @onStepChange={{this.stepEntered}}
            @allowStepJump={{this.jumpOn}}
          >
            <:step as |step|>
              {{#if (eq step.id 'details')}}
                <label class='sp-field'>Name
                  <input
                    type='text'
                    value={{this.name}}
                    placeholder='e.g. Ada Lovelace'
                    {{on 'input' this.setName}}
                  />
                </label>
              {{else if (eq step.id 'workspace')}}
                <div class='sp-pick'>
                  <BoxelSelect
                    @options={{this.workspaceOptions}}
                    @selected={{this.workspace}}
                    @onChange={{this.setWorkspace}}
                    @placeholder='Pick a workspace…'
                    as |item|
                  >
                    {{item}}
                  </BoxelSelect>
                </div>
              {{else if (eq step.id 'team')}}
                <div class='sp-invite'>
                  <span>{{this.invited}} teammate(s) invited</span>
                  <button
                    type='button'
                    class='sp-invite-btn'
                    {{on 'click' this.invite}}
                  >+ Invite</button>
                </div>
              {{else}}
                <p class='sp-done'>Everything's set{{if this.name ', '}}
                  {{this.name}}. Hit
                  <strong>Launch app</strong>
                  to fire
                  <code>@onFinish</code>.</p>
              {{/if}}
            </:step>
          </Stepper>
        {{/if}}
      </div>

      <div class='sp-section'>Configuration</div>
      <div class='sp-axes'>
        <div class='sp-axis'>
          <span class='sp-label'>@modal</span>
          <BoxelSelect
            @options={{this.modalOptions}}
            @selected={{this.modalChoice}}
            @onChange={{this.setModal}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <span class='sp-desc'><code>inline</code>
            renders the shell as a plain bordered card;
            <code>modal</code>
            wraps it in a scrim + centered card — the first-run-wizard mode.</span>
        </div>
        <div class='sp-axis'>
          <span class='sp-label'>@allowStepJump</span>
          <BoxelSelect
            @options={{this.jumpOptions}}
            @selected={{this.jumpChoice}}
            @onChange={{this.setJump}}
            @placeholder='Choose…'
            as |item|
          >
            {{item}}
          </BoxelSelect>
          <span class='sp-desc'>When
            <code>on</code>, clicking a rail item jumps straight to that step.
            Off by default so a wizard stays linear.</span>
        </div>
      </div>

      <div class='sp-section'>Generated code</div>
      <CodeSnippet @code={{this.previewCode}} />

      <div class='sp-section'>Reference — the full API</div>
      <div class='sp-args'>
        <div class='sp-arg'>
          <code>@steps</code>
          <span>Array of
            <code>StepperStep</code>:
            <code>id</code>,
            <code>label</code>
            (rail),
            <code>summary</code>
            (rail sub-line, swaps to “Completed” when done),
            <code>title</code>/<code>description</code>
            (content-pane heading),
            <code>icon</code>
            (lead circle), and
            <code>isComplete</code>
            — wire it to your own state; while false it disables Next and once
            true it paints the rail ✓. Omit it for steps that never gate. Add
            <code>optional: true</code>
            to show a Skip button on that step (like MUI's optional steps) —
            linear steps get no Skip.</span>
        </div>
        <div class='sp-arg'>
          <code>&lt;:step as |step api|&gt;</code>
          <span>The content pane for the active step — dispatch on
            <code>step.id</code>. The
            <code>api</code>
            bundle exposes
            <code>next</code>/<code>back</code>/<code>skip</code>/<code
            >goTo</code>
            plus
            <code>index</code>/<code>isFirst</code>/<code>isLast</code>/<code
            >canProceed</code>
            for hosts that want custom controls inside the content.</span>
        </div>
        <div class='sp-arg'>
          <code>&lt;:actions&gt;</code>
          /
          <code>&lt;:decoration&gt;</code>
          <span><code>:actions</code>
            replaces the default Back/Skip/Next bar entirely (receives the same
            api);
            <code>:decoration</code>
            renders inside the card for brand art — the seating planner puts its
            gold corner mandala there.</span>
        </div>
        <div class='sp-arg'>
          <code>@modal</code>
          <span>Wraps the shell in a scrim + centered card. The scrim is
            <code>position: absolute; inset: 0</code>
            so it fills the nearest positioned ancestor — your card's isolated
            view.</span>
        </div>
        <div class='sp-arg'>
          <code>@kicker</code>
          /
          <code>@title</code>
          <span>Header chrome. The header only renders when one of these (or
            <code>@onClose</code>) is present, so a bare stepper stays
            chrome-free. The close button is an outlined circle ✕ — same
            treatment as the seating planner's popover close.</span>
        </div>
        <div class='sp-arg'>
          <code>@onClose</code>
          /
          <code>@onFinish</code>
          /
          <code>@finishLabel</code>
          <span><code>onClose</code>
            backs the header ✕ (hide it by passing false to
            <code>@showClose</code>) and the
            <code>api.skip</code>
            fallback on the last step;
            <code>onFinish</code>
            backs the last-step primary button labeled
            <code>finishLabel</code>
            (default “Done”). The component never closes itself — the host owns
            visibility, exactly like Popover's
            <code>@open</code>.</span>
        </div>
        <div class='sp-arg'>
          <code>@onStepChange</code>
          <span>Fires on every step entry (Next / Skip / goTo) with
            <code>(step, index)</code>. Use it for enter hooks — the seating
            planner lazy-loads its templates when the user reaches the template
            step.</span>
        </div>
        <div class='sp-arg'>
          <code>@initialStep</code>
          /
          <code>@allowStepJump</code>
          <span>Start on a later step (resume), and let users click rail items
            to jump.</span>
        </div>
        <div class='sp-arg'>
          <code>Theming</code>
          <span>The stepper follows the linked theme automatically: every visual
            value resolves
            <code>--stepper-*</code>
            knob → theme semantic token → neutral default. The accent fills and
            their on-fill content pair come from
            <code>--primary</code>
            /
            <code>--primary-foreground</code>; text, surfaces, borders, radius,
            and fonts come from
            <code>--foreground</code>,
            <code>--muted</code>,
            <code>--muted-foreground</code>,
            <code>--card</code>,
            <code>--border</code>,
            <code>--radius</code>, and
            <code>--font-sans</code>. Link a Theme card (cardInfo.theme) or
            Brand Guide and the whole stepper restyles with no stepper-specific
            work. For a one-off brand color there is also
            <code>@accent</code>
            (hex) — the on-fill content color is auto-computed black/white via
            <code>getContrastColor</code>, the same pattern as boxel-ui's
            Avatar.</span>
        </div>
      </div>
    </div>

    <style scoped>
      .sp {
        display: grid;
        gap: 16px;
        padding: 24px;
        max-width: 900px;
        font:
          14px/1.4 system-ui,
          sans-serif;
      }
      .sp-section {
        display: flex;
        align-items: baseline;
        gap: 12px;
        font-size: 11px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b7280;
      }
      .sp-event {
        font-weight: 500;
        text-transform: none;
        letter-spacing: normal;
        font-family: ui-monospace, monospace;
        font-size: 11px;
        color: #4338ca;
      }
      .sp-axes {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 12px;
      }
      .sp-axis {
        display: grid;
        gap: 6px;
        align-content: start;
      }
      .sp-label {
        font-size: 11px;
        font-weight: 600;
        color: #4338ca;
      }
      .sp-desc {
        font-size: 11px;
        line-height: 1.5;
        color: #6b7280;
      }
      .sp-desc code,
      .sp-arg code {
        font-family: ui-monospace, monospace;
        font-size: 10px;
        color: #4338ca;
        background: #eef2ff;
        padding: 1px 4px;
        border-radius: 3px;
      }
      .sp-stage {
        position: relative;
        height: 480px;
        width: 100%;
        background: #e5e7eb;
        border-radius: 10px;
        overflow: hidden;
        contain: layout size;
        display: grid;
        place-items: center;
        padding: 16px;
      }
      .sp-reopen {
        padding: 10px 20px;
        border: 1.5px dashed #9ca3af;
        border-radius: 8px;
        background: #fff;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
        color: #374151;
      }
      /* demo step content */
      .sp-field {
        display: flex;
        flex-direction: column;
        gap: 4px;
        margin-top: 20px;
        max-width: 380px;
        font-size: 12px;
        color: rgba(0, 0, 0, 0.65);
      }
      .sp-field input {
        padding: 10px 12px;
        border: 1px solid rgba(0, 0, 0, 0.18);
        border-radius: 10px;
        font: inherit;
        font-size: 14px;
      }
      .sp-pick {
        margin-top: 20px;
        max-width: 380px;
      }
      .sp-invite {
        margin-top: 20px;
        padding: 16px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        max-width: 380px;
        border: 1.5px dashed rgba(0, 0, 0, 0.2);
        border-radius: 16px;
        font-size: 14px;
        color: rgba(0, 0, 0, 0.7);
      }
      .sp-invite-btn {
        padding: 8px 16px;
        border: 1px solid rgba(0, 0, 0, 0.25);
        border-radius: 999px;
        background: transparent;
        cursor: pointer;
        font: inherit;
        font-size: 13px;
      }
      .sp-done {
        margin: 20px 0 0;
        font-size: 14px;
        color: rgba(0, 0, 0, 0.7);
        max-width: 48ch;
      }
      .sp-args {
        margin: 0;
        display: grid;
        gap: 8px;
      }
      .sp-arg {
        display: grid;
        grid-template-columns: 220px 1fr;
        gap: 12px;
        align-items: baseline;
        font-size: 12px;
      }
      .sp-arg span {
        color: #4b5563;
      }
      @media (max-width: 520px) {
        .sp-arg {
          grid-template-columns: 1fr;
          gap: 2px;
        }
      }
    </style>
  </template>
}

export class StepperPlayground extends CardDef {
  static displayName = 'Stepper Playground';

  @field title = contains(StringField);

  static isolated = StepperPlaygroundIsolated;
}
