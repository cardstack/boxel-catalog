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
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '../../ui-component/components/alert';
import { Button } from '../../ui-component/components/button';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { EmptyState } from '../../ui-component/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import {
  StepList,
  type StepItem,
  type StepState,
} from '../../ui-component/components/step-list';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';

import { Candidate } from './candidate';
import { Position } from './position';
import { ApprovalChainField } from './approval-chain-field';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { GenerateOfferLetterCommand } from './commands/generate-offer-letter-command';
import type { Hue } from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { daysBetween, formatMoney } from './utils';
import {
  ALERT_STYLE,
  AVATAR_HUE,
} from '@cardstack/catalog/components/pretui-helpers';
import { Avatar } from '../../ui-component/components/avatar';

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

// The status chip's tone: a draft is neutral, an offer out for reply is
// info, an accepted one success and a declined or rescinded one danger.
const OFFER_STATUS_TONES: Record<string, PretuiToneArg> = {
  draft: 'neutral',
  extended: 'warning',
  accepted: 'success',
  declined: 'danger',
  rescinded: 'danger',
};

function statusTone(status?: string | null): PretuiToneArg {
  return (status && OFFER_STATUS_TONES[status]) || 'neutral';
}

// The candidate's name reads first (easy to scan in a list); the stored
// title ("Offer — Theo Bramwell") is the fallback.
function offerHeading(m?: Partial<Offer>): string {
  // prerendered tiles can miss the denormalized candidateName, so fall
  // back to the stored title minus its "Offer — " prefix
  return (
    m?.candidateName || m?.title?.replace(/^Offer — /, '') || 'Untitled Offer'
  );
}

function subLine(m?: Partial<Offer>): string {
  let parts = [
    m?.offeredTitle || m?.positionTitle,
    m?.startDate ? `start ${formatDay(m.startDate)}` : undefined,
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : 'No role set';
}

function chainSteps(m?: Partial<Offer>) {
  return (m?.approvalChain?.steps ?? []).filter(Boolean);
}

// '' when there is no chain: a template `#if` reads it as false
function approvalChip(m?: Partial<Offer>): string {
  let steps = chainSteps(m);
  if (!steps.length) {
    return '';
  }
  if (steps.some((s) => s.decision === 'rejected')) {
    return 'Approval rejected';
  }
  let approved = steps.filter((s) => s.decision === 'approved').length;
  return `Approval ${approved} / ${steps.length}`;
}

function approvalTone(m?: Partial<Offer>): PretuiToneArg {
  let steps = chainSteps(m);
  if (steps.some((s) => s.decision === 'rejected')) {
    return 'danger';
  }
  return steps.every((s) => s.decision === 'approved') ? 'success' : 'warning';
}

function approvalLabel(m?: Partial<Offer>): string {
  let steps = chainSteps(m);
  let approved = steps.filter((s) => s.decision === 'approved').length;
  return steps.length
    ? `${approved} of ${steps.length} approved`
    : 'no approvers';
}

/** The index of the step waiting on a decision, or -1 when none is. */
function pendingIndex(m?: Partial<Offer>): number {
  return chainSteps(m).findIndex((s) => s.decision === 'pending');
}

// The one fact that explains the state: whose sign-off it waits on, else
// when an offer out for reply lapses.
function waitingOn(m?: Partial<Offer>): string | undefined {
  let i = pendingIndex(m);
  if (i < 0) {
    return undefined;
  }
  return chainSteps(m)[i]?.approver?.name || 'approval';
}

function stepOf(m?: Partial<Offer>): string | undefined {
  let i = pendingIndex(m);
  return i < 0 ? undefined : `step ${i + 1} of ${chainSteps(m).length}`;
}

function expiresLabel(m?: Partial<Offer>): string | undefined {
  return m?.status === 'extended' && m?.expirationDate
    ? `Expires ${formatDay(m.expirationDate)}`
    : undefined;
}

function unitsLabel(n?: number | null): string {
  return n == null ? '—' : `${n.toLocaleString('en-US')} units`;
}

// The status and approval chips, the same soft pills in every format.
const OfferChips: TemplateOnlyComponent<{
  Args: { model?: Partial<Offer> };
  Element: HTMLSpanElement;
}> = <template>
  <span class='offer-chips' ...attributes>
    {{#if @model.status}}<StatusChip
        @value={{capitalize @model.status}}
        @tone={{statusTone @model.status}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      />{{/if}}
    {{#if (approvalChip @model)}}<StatusChip
        class='offer-chip-extra'
        @value={{approvalChip @model}}
        @tone={{approvalTone @model}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      />{{/if}}
  </span>
  <style scoped>
    .offer-chips {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-4xs);
      min-inline-size: 0;
    }
  </style>
</template>;

// The facts every format draws from, in the mockup's order; isolated shows
// them all, embedded the first six.
function offerFacts(m?: Partial<Offer>): DescriptionsItem[] {
  let cash =
    m?.salary != null || m?.bonus != null
      ? (m?.salary ?? 0) + (m?.bonus ?? 0)
      : undefined;
  return [
    { label: 'Base salary', value: formatMoney(m?.salary) ?? '—' },
    { label: 'Bonus', value: formatMoney(m?.bonus) ?? '—' },
    { label: 'Equity', value: unitsLabel(m?.equity) },
    {
      label: 'Start date',
      value: m?.startDate ? formatDay(m.startDate) : '—',
    },
    { label: 'Total cash', value: formatMoney(cash) ?? '—' },
    { label: 'Approval', value: approvalLabel(m) },
    {
      label: 'Extended',
      value: m?.extendedDate ? formatDay(m.extendedDate) : 'not yet',
    },
  ];
}

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class OfferIsolated extends Component<typeof Offer> {
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

  get details(): KeyValueItem[] {
    return offerFacts(this.args.model).map((f) => ({
      key: f.label,
      value: String(f.value ?? '—'),
    }));
  }

  // The position's band under the base salary, so the number reads against
  // the range it was set in.
  get bandHint(): string {
    let p = this.args.model?.position;
    let min = formatMoney(p?.salaryMin, { compact: true });
    let max = formatMoney(p?.salaryMax, { compact: true });
    return min && max ? `band ${min} – ${max}` : 'base';
  }

  get salaryValue(): string {
    return formatMoney(this.args.model?.salary) ?? '—';
  }

  get bonusValue(): string {
    return formatMoney(this.args.model?.bonus) ?? '—';
  }

  get equityValue(): string {
    let n = this.args.model?.equity;
    return n == null ? '—' : n.toLocaleString('en-US');
  }

  get startValue(): string {
    let d = this.args.model?.startDate;
    return d ? formatDay(d) : '—';
  }

  <template>
    <article class='offer-isolated'>
      <header class='iso-head'>
        <Avatar
          class='iso-mark'
          @name={{offerHeading @model}}
          @src={{@model.candidate.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          aria-hidden='true'
        />
        <div class='iso-id'>
          <h1>{{offerHeading @model}}</h1>
          <p class='iso-sub'>{{subLine @model}}</p>
        </div>
        <div class='chips'>
          <OfferChips @model={{@model}} />
          {{#if this.expiresNote}}
            <StatusChip
              @value={{this.expiresNote}}
              @tone='warning'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />
          {{/if}}
        </div>
      </header>

      <div class='stat-row'>
        <div class='stat-tile'><Stat
            @label='Base salary'
            @value={{this.salaryValue}}
            @hint={{this.bandHint}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Bonus'
            @value={{this.bonusValue}}
            @hint='annual target'
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Equity'
            @value={{this.equityValue}}
            @hint='units'
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Start date'
            @value={{this.startValue}}
            @roll={{false}}
          /></div>
      </div>

      <div class='iso-body'>
        <div class='iso-col'>
          <Panel class='screen-only'>
            <:header><h2 class='panel-h'>Approval chain</h2></:header>
            <:default>
              <@fields.approvalChain />
              {{#if this.canDecideApproval}}
                <div class='actions'>
                  <Button
                    @tone='primary'
                    @busy={{this.approvalBusy}}
                    @disabled={{this.approvalBusy}}
                    {{on 'click' (fn this.decideApprovalStep 'approved')}}
                  >Approve</Button>
                  <Button
                    @tone='danger'
                    @appearance='outlined'
                    @busy={{this.approvalBusy}}
                    @disabled={{this.approvalBusy}}
                    {{on 'click' (fn this.decideApprovalStep 'rejected')}}
                  >Reject</Button>
                </div>
              {{/if}}
              {{#if this.approvalError}}
                <Alert
                  class='notice'
                  @tone='danger'
                  style={{ALERT_STYLE.danger}}
                >{{this.approvalError}}</Alert>
              {{/if}}
            </:default>
          </Panel>
          <Panel class='screen-only'>
            <:header><h2 class='panel-h'>Offer path</h2></:header>
            <:default>
              <StepList
                @steps={{this.lifecycleSteps}}
                @variant='track'
                @label='Offer progress'
              />
            </:default>
          </Panel>
          <Panel class='letter-panel'>
            <:header><h2 class='panel-h letter-ui'>Offer letter</h2></:header>
            <:default>
              {{#if @model.letter}}
                <div class='letter-doc'>
                  <@fields.letter />
                </div>
              {{else}}
                <EmptyState
                  class='letter-ui'
                  @texture={{false}}
                  @title='No letter generated yet'
                  @message="Generate letter merges this offer's values into an Offer Letter Template. Print this page to save the result as a PDF."
                />
              {{/if}}
              <div class='actions letter-ui'>
                <Button
                  @tone='primary'
                  @appearance='outlined'
                  @busy={{this.letterBusy}}
                  @disabled={{this.letterBusy}}
                  {{on 'click' this.generateLetter}}
                >{{if @model.letter 'Regenerate letter' 'Generate letter'}}
                </Button>
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
            </:default>
          </Panel>
        </div>

        <div class='iso-col screen-only'>
          <Panel>
            <:header><h2 class='panel-h'>Linked</h2></:header>
            <:default>
              <ul class='linked'>
                <li class='rel'><span class='k'>Candidate</span>{{#if
                    @model.candidate
                  }}<@fields.candidate
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}<span class='v'>none linked</span>{{/if}}</li>
                <li class='rel'><span class='k'>Position</span>{{#if
                    @model.position
                  }}<@fields.position
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}<span class='v'>none linked</span>{{/if}}</li>
                <li class='rel'><span class='k'>Signed letter</span>{{#if
                    @model.offerLetterFile
                  }}<@fields.offerLetterFile
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}<span class='v'>not attached</span>{{/if}}</li>
              </ul>
            </:default>
          </Panel>
          <Panel>
            <:header><h2 class='panel-h'>Details</h2></:header>
            <:default>
              <KeyValue @items={{this.details}} @rows='ruled'>
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </KeyValue>
            </:default>
          </Panel>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .offer-isolated {
          container: offer-iso / inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          background: var(--canvas);
        }
        .iso-mark {
          --pretui-avatar-size: 3rem;
        }
        .iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .iso-id {
          flex: 1 1 12rem;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--primary-ink);
          overflow-wrap: anywhere;
        }
        .iso-sub {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .stat-row {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        .stat-tile {
          padding: var(--boxel-sp);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--primary-ink);
          box-shadow: var(--shadow-md);
        }
        .iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
          align-items: start;
          gap: var(--boxel-sp-lg);
        }
        .iso-col {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        .panel-h {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
          line-height: 1.25;
        }
        .actions {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          margin-top: var(--boxel-sp-sm);
        }
        .notice {
          margin-top: var(--boxel-sp-xs);
        }
        .letter-doc {
          max-width: 62ch;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
        }
        .linked {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .rel {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-width: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .k {
          flex: none;
          color: var(--muted-foreground);
        }
        .v {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          overflow-wrap: anywhere;
        }
        @container offer-iso (width < 45rem) {
          .iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
        /* Print is the letter's export path (browser print-to-PDF): the app
           chrome disappears and only the letter remains. */
        @media print {
          .iso-head,
          .stat-row,
          .screen-only,
          .letter-ui {
            display: none;
          }
          .offer-isolated {
            overflow: visible;
            padding: 0;
          }
          .iso-body {
            display: block;
          }
          .letter-doc {
            max-width: none;
          }
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
    get facts(): DescriptionsItem[] {
      return offerFacts(this.args.model).slice(0, 6);
    }
    <template>
      <div class='offer-embedded'>
        <article class='emb'>
          <header class='emb-head'>
            <Avatar
              class='emb-mark'
              @name={{offerHeading @model}}
              @src={{@model.candidate.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{offerHeading @model}}</h3>
              <p class='emb-sub'>{{subLine @model}}</p>
            </div>
            <div class='chips'><OfferChips @model={{@model}} /></div>
          </header>
          {{#if (waitingOn @model)}}
            <p class='emb-fact'>Waiting on
              <strong>{{waitingOn @model}}</strong>
              ·
              {{stepOf @model}}</p>
          {{else if (expiresLabel @model)}}
            <p class='emb-fact'>{{expiresLabel @model}}</p>
          {{/if}}
          <Descriptions
            class='emb-kv'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          >
            <:value as |item|><span class='v'>{{item.value}}</span></:value>
          </Descriptions>
          <p class='emb-rels'>
            {{#if @model.candidate}}
              <span class='rel'>Candidate
                <@fields.candidate
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
            {{#if @model.position}}
              <span class='rel'>Position
                <@fields.position
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
            {{#each @fields.approvalChain.steps as |Step i|}}
              {{#if (eq i (pendingIndex @model))}}
                <span class='rel'>Approver
                  <Step.approver
                    @format='atom'
                    @displayContainer={{false}}
                  /></span>
              {{/if}}
            {{/each}}
          </p>
        </article>
      </div>
      <style scoped>
        @layer PretComponent {
          .offer-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-mark {
            --pretui-avatar-size: 2.5rem;
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 auto;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .emb-sub {
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
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-fact strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          .v {
            font-weight: 600;
            font-variant-numeric: tabular-nums;
            overflow-wrap: anywhere;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          /* under 400 the chips move under the name */
          @container (width < 25rem) {
            .emb-head {
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
    <template>
      <span class='offer-atom'>
        <Avatar
          @name={{offerHeading @model}}
          @src={{@model.candidate.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          aria-hidden='true'
        />
        <span class='name'>{{offerHeading @model}}</span>
        {{#if @model.status}}
          <StatusChip
            @value={{capitalize @model.status}}
            @tone={{statusTone @model.status}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .offer-atom {
            --pretui-avatar-size: 1.25rem;
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            white-space: nowrap;
            color: var(--foreground);
          }
          .name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get kvFacts(): DescriptionsItem[] {
      return offerFacts(this.args.model);
    }
    // The three headline numbers of the expanded card; equity drops its unit
    get headlineFacts(): { label: string; value: string }[] {
      let m = this.args.model;
      let [salary, bonus] = offerFacts(m);
      return [
        { label: salary.label, value: String(salary.value) },
        { label: bonus.label, value: String(bonus.value) },
        {
          label: 'Equity',
          value: m?.equity == null ? '—' : m.equity.toLocaleString('en-US'),
        },
      ];
    }
    get approvalTotal(): number {
      return chainSteps(this.args.model).length;
    }
    get approvedCount(): number {
      return chainSteps(this.args.model).filter(
        (s) => s.decision === 'approved',
      ).length;
    }

    <template>
      <article class='fit'>
        <header class='who'>
          <Avatar
            class='mark'
            @name={{offerHeading @model}}
            @src={{@model.candidate.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            aria-hidden='true'
          />
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{offerHeading @model}}</h3>
              <span class='chips chips-inline'>
                {{#if @model.status}}<StatusChip
                    @value={{capitalize @model.status}}
                    @tone={{statusTone @model.status}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  />{{/if}}
                {{#if (approvalChip @model)}}<StatusChip
                    class='chip-extra'
                    @value={{approvalChip @model}}
                    @tone={{approvalTone @model}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  />{{/if}}
              </span>
            </div>
            <p class='sub'>{{subLine @model}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          {{#if @model.status}}<StatusChip
              @value={{capitalize @model.status}}
              @tone={{statusTone @model.status}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />{{/if}}
          {{#if (approvalChip @model)}}<StatusChip
              class='chip-extra'
              @value={{approvalChip @model}}
              @tone={{approvalTone @model}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />{{/if}}
        </span>
        {{#if (waitingOn @model)}}
          <p class='fact'>Waiting on
            <strong>{{waitingOn @model}}</strong>
            ·
            {{stepOf @model}}</p>
        {{else if (expiresLabel @model)}}
          <p class='fact'>{{expiresLabel @model}}</p>
        {{/if}}
        <div class='stats'>
          {{#each this.headlineFacts as |f|}}
            <div class='stat'><span class='stat-k'>{{f.label}}</span><span
                class='stat-v'
              >{{f.value}}</span></div>
          {{/each}}
        </div>
        {{#if this.approvalTotal}}
          {{! The wrapper carries the hide/show rule: ProgressBar's own root
            rule (display: grid, same layer and specificity) overrides a
            class passed to it, so the bar showed at every size. }}
          <div class='bar'><ProgressBar
              @label='Approval'
              @value={{this.approvedCount}}
              @max={{this.approvalTotal}}
              @count='{{this.approvedCount}} / {{this.approvalTotal}}'
              @steps={{false}}
            /></div>
        {{/if}}
        <dl class='kv'>
          {{#each this.kvFacts as |f|}}
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
          {{#if @model.position}}
            <li><span class='k'>Position</span><@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#each @fields.approvalChain.steps as |Step i|}}
            {{#if (eq i (pendingIndex @model))}}
              <li><span class='k'>Approver</span><Step.approver
                  @format='atom'
                  @displayContainer={{false}}
                /></li>
            {{/if}}
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
            --pretui-avatar-size: 2rem;
            display: none;
            flex: none;
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
          .chips-inline,
          .chip-extra,
          .stats,
          .bar,
          .kv,
          .rels .k {
            display: none;
          }
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
          }
          .stat {
            display: flex;
            flex-direction: column;
            min-inline-size: 0;
            overflow: hidden;
          }
          .stat-k {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stat-v {
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.5;
            color: var(--primary-ink);
            font-variant-numeric: tabular-nums;
          }
          .stat-k,
          .stat-v {
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .chips-inline {
            flex: 0 1 auto;
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
            padding-block: 1px;
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
            /* clip sideways only: an outlined chip's 1px border sits on the
               row edge and was cut off by overflow: hidden */
            overflow-x: clip;
            overflow-y: visible;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the type mark shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: inline-flex;
            }
          }
          /* the approval chip joins the status from 250 wide */
          @container fitted-card (width >= 250px) {
            .chip-extra {
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
          /* 400 wide: state moves beside the title */
          @container fitted-card (width >= 400px) {
            .chips-inline {
              display: flex;
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
          /* under 105 tall: who only, state beside the title from 250 wide */
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
          /* 250 wide under 65 tall: status only beside the title */
          @container fitted-card (height < 65px) {
            .sub,
            .chip-extra {
              display: none;
            }
          }
          /* a pill strip under 400 wide keeps the status only; in the
             chip's dot + text form (under 65 tall or 150 wide) the level
             rides along, the remote flag does not */
          @container fitted-card (65px <= height < 105px) and (150px < width < 400px) {
            .chip-level {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width < 400px) {
            .chip-extra {
              display: none;
            }
          }
          .chips > * {
            flex: none;
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
              --pretui-avatar-size: 2.5rem;
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
          /* 400 tall: the headline numbers and the approval bar lead the facts */
          @container fitted-card (height >= 400px) {
            .stats {
              display: grid;
            }
            .bar {
              display: grid;
            }
            /* the links keep their own height so every fact row gets the rest */
            .rels {
              flex: none;
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
