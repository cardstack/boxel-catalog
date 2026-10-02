import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import MarkdownField from 'https://cardstack.com/base/markdown';
import NumberField from 'https://cardstack.com/base/number';
import enumField from 'https://cardstack.com/base/enum';
import { FileDef } from 'https://cardstack.com/base/file-api';
import HandshakeIcon from '@cardstack/boxel-icons/handshake';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { BoxelButton } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat } from '@cardstack/pretui/components/stat';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';

import { Candidate } from './candidate';
import { Position } from './position';
import { ApprovalChainField } from './approval-chain-field';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { GenerateOfferLetterCommand } from './commands/generate-offer-letter-command';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { daysBetween, formatMoney } from './utils';
import { FactList, Money, hueOf } from './hr-ui';
import {
  ALERT_STYLE,
  AVATAR_HUE,
  nameProgress,
} from '@cardstack/catalog/components/pretui-helpers';

export const OFFER_STATUSES = [
  'draft',
  'extended',
  'accepted',
  'declined',
  'rescinded',
];

// Colocated with Offer — the closing chapter of the Candidate story. Draft
// is stone (not yet real), extended reuses Candidate's "offer" stage brass
// exactly (the same seal going out the door), accepted resolves into the
// hired/active forest green, declined and rescinded both land on rust —
// the offer ended without a hire either way.
export const OFFER_STATUS_HUES: Record<string, Hue> = {
  draft: 'amber',
  extended: 'orange',
  accepted: 'green',
  declined: 'red',
  rescinded: 'red',
};

// The happy path an offer walks. Declined and rescinded are terminal branches
// off 'extended': an offer can only end that way after it went out.
const OFFER_PATH = ['draft', 'extended', 'accepted'];

function isTerminal(status?: string | null): boolean {
  return status === 'declined' || status === 'rescinded';
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

// Display labels for the offer lifecycle. The stored values stay as they are
// — they are the industry vocabulary and they feed reports and filters — but
// a raw enum value is not a UI label. Each label answers "whose turn is it",
// which is the only thing a reader of a board needs from a status chip.
export const OFFER_STATUS_LABELS: Record<string, string> = {
  draft: 'Draft · not sent',
  extended: 'Awaiting reply',
  accepted: 'Accepted',
  declined: 'Declined',
  rescinded: 'Rescinded',
};

export function offerStatusLabel(status?: string | null): string | undefined {
  if (!status) {
    return undefined;
  }
  return OFFER_STATUS_LABELS[status] ?? status;
}

export const OfferStatusField = enumField(StringField, {
  options: OFFER_STATUSES.map((status) => ({ value: status, label: status })),
  displayName: 'Offer Status',
});

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class OfferIsolated extends Component<typeof Offer> {
  get salaryLabel(): string | undefined {
    return formatMoney(this.args.model?.salary);
  }
  get statusHue() {
    return hueOf(OFFER_STATUS_HUES, this.args.model?.status);
  }
  get statusLabel(): string | undefined {
    let status = this.args.model?.status;
    if (!status) {
      return undefined;
    }
    let label = status.charAt(0).toUpperCase() + status.slice(1);
    if (status === 'extended') {
      let expires = this.args.model?.expirationDate;
      let days = expires ? daysBetween(new Date(), expires) : undefined;
      if (days != null) {
        return days <= 0
          ? `${label} · expired`
          : `${label} · expires in ${days}d`;
      }
    }
    return label;
  }
  // The lifecycle as Pret UI `StepList` steps. Stages before the reached one
  // are complete and the reached one is current; reaching 'accepted'
  // completes the run. A declined or rescinded offer keeps 'draft' and
  // 'extended' complete and ends on its own terminal stage as an error step,
  // rather than blanking the whole rail.
  get lifecycleSteps(): StepItem[] {
    let status = this.args.model?.status;
    let terminal = isTerminal(status);
    let reached = terminal
      ? OFFER_PATH.indexOf('extended')
      : OFFER_PATH.indexOf(status ?? '');
    let last = OFFER_PATH.length - 1;
    let steps: StepItem[] = OFFER_PATH.map((step, i) => {
      let state: StepState =
        reached < 0 || i > reached
          ? 'upcoming'
          : i < reached || reached === last || terminal
            ? 'complete'
            : 'current';
      return { label: capitalize(step), state };
    });
    if (terminal && status) {
      steps.push({ label: capitalize(status), state: 'error' });
    }
    return steps;
  }
  get avatarName() {
    return this.args.model?.candidateName || this.args.model?.title || '?';
  }

  // Compensation and key dates as Pret UI `KeyValue` rows. A row whose value
  // is a field component carries that field's name; the `<:value>` block
  // renders it, and every other row prints its text.
  get compensationFacts(): KeyValueItem[] {
    let m = this.args.model;
    return [
      { key: 'Base salary', value: m?.salary != null ? 'salary' : '—' },
      { key: 'Equity', value: m?.equity != null ? 'equity' : '—' },
      { key: 'Signing bonus', value: m?.bonus != null ? 'bonus' : '—' },
    ];
  }
  get dateFacts(): KeyValueItem[] {
    let m = this.args.model;
    return [
      { key: 'Extended', value: m?.extendedDate ? 'extendedDate' : '—' },
      { key: 'Expires', value: m?.expirationDate ? 'expirationDate' : '—' },
      { key: 'Start date', value: m?.startDate ? 'startDate' : '—' },
      {
        key: 'Decision',
        value: m?.decisionDate ? 'decisionDate' : '— awaiting response',
      },
    ];
  }

  get expiresNote(): string | undefined {
    let expires = this.args.model?.expirationDate;
    if (!expires) {
      return undefined;
    }
    let days = daysBetween(new Date(), expires);
    if (days == null) {
      return undefined;
    }
    return days <= 0 ? 'Expired' : `${days} days to respond`;
  }

  // The click-to-decide affordance lives here, not inside
  // ApprovalChainField's own template — see approval-chain-field.gts's
  // class comment for why. This mirrors how every other stage-changing
  // action in this app (ApproveOfferCommand, RejectCandidateCommand) is
  // invoked from the consuming card/tracker rather than from a field.
  @tracked approvalBusy = false;
  @tracked approvalError: string | undefined;

  // Generate-letter action. The command resolves the template itself (the
  // linked one, else the first OfferLetterTemplate in the realm), so the
  // button needs no picker UI — one template is the common case here.
  @tracked letterBusy = false;
  @tracked letterError: string | undefined;
  @tracked letterMessage: string | undefined;

  generateLetter = () => {
    void this.generateLetterTask();
  };

  private generateLetterTask = async () => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.letterError = 'Commands are unavailable in this mode';
      return;
    }
    this.letterError = undefined;
    this.letterMessage = undefined;
    this.letterBusy = true;
    try {
      let result = await new GenerateOfferLetterCommand(commandContext).execute(
        {
          offer: model,
        } as any,
      );
      this.letterMessage = (result as any)?.message;
    } catch (error: any) {
      this.letterError = error?.message ?? String(error);
    } finally {
      this.letterBusy = false;
    }
  };

  get canDecideApproval(): boolean {
    return this.args.model?.approvalChain?.status === 'in-progress';
  }

  decideApprovalStep = (decision: 'approved' | 'rejected') => {
    void this.decideApprovalStepTask(decision);
  };

  private decideApprovalStepTask = async (
    decision: 'approved' | 'rejected',
  ) => {
    let model = this.args.model;
    let chain = model?.approvalChain;
    if (!model || !chain) {
      return;
    }
    let commandContext = this.args.context?.commandContext;
    if (!commandContext) {
      this.approvalError = 'Commands are unavailable in this mode';
      return;
    }
    this.approvalError = undefined;
    this.approvalBusy = true;
    try {
      await new ApproveChainStepCommand(commandContext).execute({
        target: model,
        stepIndex: chain.currentStepIndex,
        decision,
      } as any);
    } catch (error: any) {
      this.approvalError = error?.message ?? String(error);
    } finally {
      this.approvalBusy = false;
    }
  };

  <template>
    <article class='offer-isolated'>
      <header class='hero'>
        <Avatar
          class='avatar'
          @name={{this.avatarName}}
          @hue={{AVATAR_HUE}}
          @size={{52}}
          aria-hidden='true'
        />
        <div class='hero-text'>
          <h1>{{@model.title}}</h1>
          <p class='byline'>
            {{#if @model.offeredTitle}}{{@model.offeredTitle}}{{/if}}
            {{#if @model.positionTitle}}
              <span class='sep-dot'>&middot;</span>
              {{@model.positionTitle}}
            {{/if}}
          </p>
          <div class='pill-row'>
            <StatePill
              @label={{this.statusLabel}}
              @hue={{this.statusHue}}
              @dot={{true}}
            />
            <StatePill @label={{this.expiresNote}} />
          </div>
        </div>
        <div class='hero-money'>
          {{#if this.salaryLabel}}
            <Stat
              class='money'
              @label='Base salary'
              @value={{this.salaryLabel}}
              @roll={{false}}
            />
          {{/if}}
          {{#if @model.startDate}}
            <span class='money-label'>starts <@fields.startDate /></span>
          {{/if}}
        </div>
      </header>

      <div class='body'>
        <div class='main'>
          <h2 class='panel-title'>Progress</h2>
          <StepList
            class='timeline'
            @steps={{this.lifecycleSteps}}
            @variant='track'
            @label='Offer progress'
          />

          <h2 class='panel-title spaced'>Compensation</h2>
          <FactList @items={{this.compensationFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'salary')}}
                <Money @amount={{@model.salary}} />
              {{else if (eq row.value 'equity')}}
                <span><FormatNumber @value={{@model.equity}} /> shares</span>
              {{else if (eq row.value 'bonus')}}
                <span><Money @amount={{@model.bonus}} />{{#if
                    (eq @model.bonus 0)
                  }}
                    &middot; confirmed none{{/if}}</span>
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </FactList>

          <h2 class='panel-title spaced'>Key dates</h2>
          <FactList @items={{this.dateFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'extendedDate')}}
                <@fields.extendedDate />
              {{else if (eq row.value 'expirationDate')}}
                <span><@fields.expirationDate />{{#if this.expiresNote}}<span
                      class='dd-note'
                    >
                      &middot;
                      {{this.expiresNote}}</span>{{/if}}</span>
              {{else if (eq row.value 'startDate')}}
                <@fields.startDate />
              {{else if (eq row.value 'decisionDate')}}
                <@fields.decisionDate />
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </FactList>

          <section class='letter-panel'>
            <h2 class='panel-title spaced letter-ui'>Offer letter</h2>
            {{#if @model.letter}}
              <div class='letter-doc'>
                <@fields.letter />
              </div>
            {{else}}
              <EmptyState
                class='empty letter-ui'
                @texture={{false}}
                @title='No letter generated yet'
                @message="Generate letter merges this offer's values into an Offer Letter Template. Print this page to save the result as a PDF."
              />
            {{/if}}
            <div class='letter-actions letter-ui'>
              <BoxelButton
                @kind='secondary'
                @size='small'
                class='letter-btn'
                @loading={{this.letterBusy}}
                @disabled={{this.letterBusy}}
                {{on 'click' this.generateLetter}}
              >{{if @model.letter 'Regenerate letter' 'Generate letter'}}
              </BoxelButton>
            </div>
            {{#if this.letterMessage}}
              <Alert
                class='notice letter-ui'
                @tone='success'
                style={{ALERT_STYLE.success}}
              >{{this.letterMessage}}</Alert>
            {{/if}}
            {{#if this.letterError}}
              <Alert
                class='notice letter-ui'
                @tone='danger'
                style={{ALERT_STYLE.danger}}
              >{{this.letterError}}</Alert>
            {{/if}}
          </section>
        </div>

        <aside class='side'>
          <h2 class='panel-title'>Candidate</h2>
          {{#if @model.candidate}}
            <div class='linked'><@fields.candidate
                @format='embedded'
                @displayContainer={{false}}
              /></div>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No candidate linked'
              @message='An offer should always point at one.'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Approval</h2>
          <dl class='stacked'>
            <dt>Offer letter</dt>
            <dd>{{#if @model.offerLetterFile}}<@fields.offerLetterFile
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash; not attached{{/if}}</dd>
          </dl>
          <@fields.approvalChain />
          {{#if this.canDecideApproval}}
            <div class='approval-actions'>
              <BoxelButton
                @kind='primary'
                @size='small'
                @loading={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'approved')}}
              >Approve</BoxelButton>
              <BoxelButton
                @kind='danger'
                @size='small'
                @loading={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'rejected')}}
              >Reject</BoxelButton>
            </div>
          {{/if}}
          {{#if this.approvalError}}
            <Alert
              class='notice'
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.approvalError}}</Alert>
          {{/if}}
        </aside>
      </div>
    </article>
    <style scoped>
      .offer-isolated {
        container-type: inline-size;
        container-name: iso;
        height: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        --offer-id: var(--primary);
        --offer-strong: color-mix(
          in oklch,
          var(--offer-id) 45%,
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
      .hero-money {
        flex: none;
        text-align: right;
      }
      .money {
        --text-stat: 1.6rem;
        justify-items: end;
      }
      .money-label {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
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
      /* Every mark on a guaranteed pair: the default current bar (--primary)
         and error tone (--destructive) are fills that fall under 3:1 on the
         page, so each takes its ink token. */
      .timeline {
        --pretui-step-current-marker-fg: var(--foreground);
        --pretui-step-current-bar: var(--primary-ink);
        --pretui-step-complete-marker-fg: var(--success-ink);
        --pretui-step-error-tone: var(--destructive-ink);
        --pretui-step-error-marker-fg: var(--destructive-ink);
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
        padding-top: 0.45rem;
      }
      .stacked dd {
        margin: 0;
        padding: 0.1rem 0 0.45rem;
        font-size: var(--boxel-font-size-sm);
        border-bottom: 1px solid var(--border);
        overflow-wrap: anywhere;
      }
      .dd-note {
        color: var(--muted-foreground);
      }
      .linked {
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        overflow: hidden;
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .empty {
        --space-9: var(--boxel-sp);
        --space-6: var(--boxel-sp);
        --text-heading: var(--boxel-font-size);
      }
      .approval-actions {
        display: flex;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-xs);
      }
      .notice {
        margin-top: var(--boxel-sp-xs);
      }
      .letter-doc {
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        padding: var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.65;
        max-width: 62ch;
      }
      .letter-actions {
        display: flex;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-xs);
      }
      .letter-btn {
        --boxel-button-secondary-background: transparent;
        --boxel-button-secondary-foreground: var(--offer-strong);
        --boxel-button-secondary-border: var(--offer-strong);
        --boxel-button-border-radius: var(--boxel-border-radius-sm);
      }
      /* Print = the letter's export path. The browser's print-to-PDF is
         the spec's "PDF" pragmatically: everything that is app chrome
         (hero, aside, facts, actions) disappears, and the letter reforms
         as a serif document with document margins. */
      @media print {
        .hero,
        .side,
        .letter-ui,
        .main > *:not(.letter-panel) {
          display: none;
        }
        .offer-isolated {
          overflow: visible;
          background-color: transparent;
        }
        .body {
          display: block;
        }
        .main {
          padding: 0;
        }
        .letter-doc {
          border: 0;
          padding: 2.5cm 2cm;
          max-width: none;
          background-color: transparent;
          font-family: Georgia, 'Times New Roman', serif;
          font-size: 12pt;
          line-height: 1.6;
        }
      }
      @container iso (max-width: 40rem) {
        .body {
          grid-template-columns: 1fr;
        }
        .side {
          border-left: 0;
          border-top: 1px solid var(--border);
        }
        .hero {
          flex-wrap: wrap;
        }
        .hero-money {
          text-align: left;
        }
        .money {
          justify-items: start;
        }
      }
    </style>
  </template>
}

export class Offer extends CardDef {
  static displayName = 'Offer';
  static icon = HandshakeIcon;

  @field candidate = linksTo(() => Candidate);
  @field position = linksTo(() => Position);
  @field offeredTitle = contains(StringField, {
    description: 'Job title extended in this offer',
  });
  @field salary = contains(NumberField);
  @field equity = contains(NumberField, {
    description: 'Equity grant, e.g. number of shares/units',
  });
  @field bonus = contains(NumberField, {
    description: 'Signing or annual bonus amount',
  });
  @field startDate = contains(DateField);
  @field extendedDate = contains(DateField);
  @field expirationDate = contains(DateField, {
    description: 'Date this offer lapses if not accepted',
  });
  @field decisionDate = contains(DateField);
  @field approvalChain = contains(ApprovalChainField);
  @field offerLetterFile = linksTo(FileDef, { searchable: true });
  // The generated letter itself — written by GenerateOfferLetterCommand from
  // an OfferLetterTemplate's merge fields. The print stylesheet in the
  // isolated view is the export path (browser print-to-PDF); distinct from
  // offerLetterFile, which holds an externally-produced signed document.
  @field letter = contains(MarkdownField);
  @field status = contains(OfferStatusField);

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field candidateName = contains(StringField, {
    computeVia: function (this: Offer) {
      return this.candidate?.name ?? '';
    },
  });

  // Denormalized id, same rationale as Meeting.candidateId: the tracker's
  // board resolves a candidate's Offer from the live offers query by this
  // own-attribute match — dereferencing `candidate.offer` at click time
  // races the async linksTo load and silently opens nothing.
  @field candidateId = contains(StringField, {
    computeVia: function (this: Offer) {
      return this.candidate?.id ?? '';
    },
  });

  @field positionTitle = contains(StringField, {
    computeVia: function (this: Offer) {
      return this.position?.jobTitle ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Offer) {
      let who = this.candidate?.name?.trim();
      return who ? `Offer — ${who}` : 'Untitled Offer';
    },
  });

  static isolated = OfferIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return hueOf(OFFER_STATUS_HUES, this.args.model?.status);
    }
    <template>
      <div class='offer-embedded'>
        <EntityDisplay
          class='entity'
          @variant='thumbnail'
          @title={{@model.title}}
          @subtitle={{@model.offeredTitle}}
          @center={{true}}
        >
          <:visual><HandshakeIcon class='entity-icon' /></:visual>
        </EntityDisplay>
        <StatePill
          class='oe-status'
          @label={{@model.status}}
          @hue={{this.statusHue}}
        />
      </div>
      <style scoped>
        .offer-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        /* EntityDisplay's thumbnail dress holds the type icon; the name and
           secondary line keep the row's sizes. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.75rem;
          --text-ui-md: 0.8125rem;
          --text-ui-sm: 0.6875rem;
          --space-3: 0.625rem;
        }
        .entity-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
        }
        .oe-status {
          flex-shrink: 0;
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='offer-atom'>
        <HandshakeIcon class='offer-atom-icon' />
        <span class='offer-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .offer-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .offer-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .offer-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get statusLabel(): string | undefined {
      return offerStatusLabel(this.args.model?.status);
    }

    get statusHue() {
      return hueOf(OFFER_STATUS_HUES, this.args.model?.status);
    }
    // Mirrors the isolated view's rule: declined/rescinded can only happen
    // after 'extended', so those two statuses keep the earlier stages done and
    // add a terminal stage, instead of blanking the whole bar.
    get isTerminal(): boolean {
      return isTerminal(this.args.model?.status);
    }
    get stageTotal(): number {
      return OFFER_PATH.length + (this.isTerminal ? 1 : 0);
    }
    get stagesDone(): number {
      if (this.isTerminal) {
        return this.stageTotal;
      }
      return OFFER_PATH.indexOf(this.args.model?.status ?? '') + 1;
    }
    // What a screen reader hears for the bar. A terminal offer fills every
    // segment, so the count alone would announce it as complete; the text
    // names how it ended and the stage it ended after.
    get progressText(): string {
      let status = this.args.model?.status;
      if (isTerminal(status)) {
        return `${capitalize(status!)} after extended`;
      }
      if (!status || this.stagesDone === 0) {
        return 'Not started';
      }
      return `${capitalize(status)}, stage ${this.stagesDone} of ${this.stageTotal}`;
    }
    get avatarName() {
      return this.args.model?.candidateName || this.args.model?.title || '?';
    }
    get hasSalary(): boolean {
      return this.args.model?.salary != null;
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          {{! Avatar sizes itself from @size, so the smallest tier mounts its
              own 20px disc and the container queries show one of the two. }}
          <Avatar
            class='avatar-lg'
            @name={{this.avatarName}}
            @hue={{AVATAR_HUE}}
            @size={{26}}
            aria-hidden='true'
          />
          <Avatar
            class='avatar-sm'
            @name={{this.avatarName}}
            @hue={{AVATAR_HUE}}
            @size={{20}}
            aria-hidden='true'
          />
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.offeredTitle}}
              <span class='fit-eb'>{{@model.offeredTitle}}</span>
            {{/if}}
          </div>
          {{! Status survives to the smallest tier. Terminal offers must never
              look like a fresh draft, so this is never the first thing cut. }}
          <StatePill
            class='fit-pill'
            @label={{this.statusLabel}}
            @hue={{this.statusHue}}
            @dot={{true}}
          />
        </div>

        <div class='fit-track'>
          {{#if this.hasSalary}}
            <Money class='money' @amount={{@model.salary}} />
          {{/if}}
          <div class='steps {{if this.isTerminal "term"}}'>
            <ProgressBar
              @value={{this.stagesDone}}
              @max={{this.stageTotal}}
              @steps={{true}}
              {{nameProgress 'Offer stages reached' this.progressText}}
            />
          </div>
          {{#if @model.expirationDate}}
            <span class='track-label'>Expires
              <FormatDate
                @date={{@model.expirationDate}}
                @locale='en-US'
                @month='short'
                @day='numeric'
              /></span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if @model.positionTitle}}
            <div><dt>Role</dt><dd>{{@model.positionTitle}}</dd></div>
          {{/if}}
          {{#if @model.startDate}}
            <div><dt>Starts</dt><dd><@fields.startDate /></dd></div>
          {{/if}}
          {{#if @model.equity}}
            <div><dt>Equity</dt><dd>{{@model.equity}}</dd></div>
          {{/if}}
          {{#if @model.candidateName}}
            <div><dt>For</dt><dd>{{@model.candidateName}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING fields; 11px floor; status pill always on. */
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
        .fit-top .avatar-sm {
          display: none;
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
        .fit-track {
          flex: none;
          display: none;
        }
        .money {
          display: block;
          font-size: calc(var(--fit-name) * 1.25);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        /* ProgressBar's segments read --primary; the ink token keeps them
           3:1 against the track, and a declined or rescinded offer's run is
           destructive. */
        .steps {
          margin-top: 0.2rem;
          --primary: var(--primary-ink);
        }
        .steps.term {
          --primary: var(--destructive-ink);
        }
        .track-label {
          display: block;
          margin-top: 0.15rem;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
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
          font-variant-numeric: tabular-nums;
        }

        /* TIER 2 — add the offered title. Two rules: no `or` in CQ. */
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
        /* TIER 3 — add salary, lifecycle track and expiry. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .fit-track {
            display: block;
          }
        }
        /* TIER 4 — width-driven facts; previously missing entirely. */
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
          .fit-top .avatar-lg {
            display: none;
          }
          .fit-top .avatar-sm {
            display: inline-flex;
          }
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
