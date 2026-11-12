import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
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
import { dotEnumField } from './dot-enum-field';
import { FileDef } from 'https://cardstack.com/base/file-api';
import HandshakeIcon from '@cardstack/boxel-icons/handshake';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { type DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

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
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';

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

// The status dot's hue, from the same tones the chips used.
function offerStatusHue(status?: string | null) {
  let tone = statusTone(status);
  return (
    tone === 'success'
      ? 'green'
      : tone === 'danger'
        ? 'red'
        : tone === 'warning'
          ? 'amber'
          : tone === 'info'
            ? 'blue'
            : 'slate'
  ) as 'green' | 'red' | 'amber' | 'blue' | 'slate';
}

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

export const OfferStatusField = markDefinition(
  dotEnumField(
    {
      options: OFFER_STATUSES.map((status) => ({
        value: status,
        label: status,
      })),
      displayName: 'Offer Status',
    },
    OFFER_STATUS_HUES,
  ),
);

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

// The kit's head line: "<role> offer", then "<candidate> · start <date>".
function offerTitle(m?: Partial<Offer>): string {
  let role = m?.offeredTitle || m?.positionTitle;
  return role ? role + ' offer' : offerHeading(m);
}
function offerMeta(m?: Partial<Offer>): string {
  return [
    offerHeading(m),
    m?.startDate ? 'start ' + formatDay(m.startDate) : undefined,
  ]
    .filter(Boolean)
    .join(' · ');
}

function chainSteps(m?: Partial<Offer>) {
  return (m?.approvalChain?.steps ?? []).filter(Boolean);
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

function unitsLabel(n?: number | null): string {
  return n == null ? '—' : `${n.toLocaleString('en-US')} units`;
}

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
  // The mock's header action: a draft whose chain is fully approved goes
  // out as extended, dated today.
  @tracked extendBusy = false;
  @tracked extendError: string | undefined;

  get isDraft(): boolean {
    return this.args.model?.status === 'draft';
  }
  get chainApproved(): boolean {
    return this.args.model?.approvalChain?.status === 'approved';
  }
  get cannotExtend(): boolean {
    return !this.chainApproved || this.extendBusy;
  }

  extendOffer = async () => {
    let ctx = this.args.context?.commandContext;
    let model = this.args.model as Offer | undefined;
    if (!ctx || !model) {
      this.extendError = 'Commands are unavailable in this mode';
      return;
    }
    this.extendBusy = true;
    this.extendError = undefined;
    try {
      model.status = 'extended';
      model.extendedDate = new Date();
      await new SaveCardCommand(ctx).execute({ card: model });
    } catch (e: any) {
      this.extendError = e?.message ?? String(e);
    } finally {
      this.extendBusy = false;
    }
  };

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

  get strip(): StripItem[] {
    return [
      {
        label: 'Base salary',
        value: this.salaryValue,
        hint: this.bandHint,
        tone: 'success',
      },
      { label: 'Bonus', value: this.bonusValue, hint: 'annual target' },
      { label: 'Equity', value: this.equityValue, hint: 'units', tone: 'info' },
      { label: 'Start date', value: this.startValue },
    ];
  }
  linkedRows = [
    { key: 'Candidate', value: '' },
    { key: 'Position', value: '' },
    { key: 'Signed letter', value: '' },
  ];

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{offerTitle @model}} @meta={{offerMeta @model}}>
          <:mark><Avatar
              @name='Of'
              @hue='var(--muted)'
              @shape='rounded'
              @size={{36}}
              aria-hidden='true'
            /></:mark>
          <:aside>{{#if @model.status}}<@fields.status
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}{{#if this.expiresNote}}<span
                class='muted'
              >{{this.expiresNote}}</span>{{/if}}</:aside>
          <:actions as |bar|>{{#if this.isDraft}}<bar.Action
                @id='extend'
                @label='Extend offer'
                @primary={{true}}
                @loading={{this.extendBusy}}
                @disabled={{this.cannotExtend}}
                @onClick={{this.extendOffer}}
              />{{/if}}<bar.Action
              @id='letter'
              @label={{if @model.letter 'Regenerate letter' 'Generate letter'}}
              @loading={{this.letterBusy}}
              @onClick={{this.generateLetter}}
            /></:actions>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
        {{#if this.extendError}}<Alert
            @tone='danger'
            style={{ALERT_STYLE.danger}}
          >{{this.extendError}}</Alert>{{/if}}
        {{#if this.letterMessage}}<Alert
            @tone='success'
            style={{ALERT_STYLE.success}}
          >{{this.letterMessage}}</Alert>{{/if}}
        {{#if this.letterError}}<Alert
            @tone='danger'
            style={{ALERT_STYLE.danger}}
          >{{this.letterError}}</Alert>{{/if}}
      </:head>
      <:main>
        <Panel @title='Approval chain'>
          <@fields.approvalChain />
          {{#if this.canDecideApproval}}
            <SheetLine>
              <Button
                @tone='primary'
                @appearance='accent'
                @size='xs'
                @busy={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'approved')}}
              >Approve</Button>
              <Button
                @tone='danger'
                @appearance='link'
                @size='xs'
                @busy={{this.approvalBusy}}
                @disabled={{this.approvalBusy}}
                {{on 'click' (fn this.decideApprovalStep 'rejected')}}
              >Reject</Button>
            </SheetLine>
          {{/if}}
          {{#if this.approvalError}}
            <Alert
              @tone='danger'
              style={{ALERT_STYLE.danger}}
            >{{this.approvalError}}</Alert>
          {{/if}}
        </Panel>
        <Panel @title='Offer path'>
          <SheetLine><StepList
              @steps={{this.lifecycleSteps}}
              @variant='track'
              @label='Offer progress'
            /></SheetLine>
        </Panel>
        {{! the letter itself opens from the header action, not inline: the mock's left column is approval chain + offer path }}
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{this.linkedRows}}>
            <:value as |row|>
              {{#if (eq row.key 'Candidate')}}
                {{#if @model.candidate}}<@fields.candidate
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}none linked{{/if}}
              {{else if (eq row.key 'Position')}}
                {{#if @model.position}}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}none linked{{/if}}
              {{else}}
                {{#if @model.offerLetterFile}}<@fields.offerLetterFile
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}not attached{{/if}}
              {{/if}}
            </:value>
          </Kv>
        </Panel>
        <Panel @title='Details'><Kv @items={{this.details}} /></Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>

  get statusHue() {
    return offerStatusHue(this.args.model?.status);
  }
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
    get rows() {
      let m = this.args.model;
      return [
        { key: 'Waiting on', value: waitingOn(m) ?? '—' },
        ...kv(offerFacts(m).slice(0, 6)),
        { key: 'Candidate', value: '' },
        { key: 'Position', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{offerTitle @model}} @meta={{offerMeta @model}}>
        <:mark><Avatar
            @name='Of'
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>
              {{#if (eq row.key 'Candidate')}}
                {{#if @model.candidate}}<@fields.candidate
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if (eq row.key 'Position')}}
                {{#if @model.position}}<@fields.position
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else}}{{row.value}}{{/if}}
            </:value>
          </Kv>
        </:default>
      </EmbCard>
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
      </span>
      <style scoped>
        @layer PretComponent {
          .offer-atom {
            --pretui-avatar-size: 1.25rem;
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-2xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.375rem;
            row-gap: var(--boxel-sp-lg);
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1;
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

    get strip(): StripItem[] {
      let m = this.args.model;
      let k = (n?: number | null) =>
        n == null ? '—' : (formatMoney(n, { compact: true }) ?? '—');
      return [
        { label: 'Base', value: k(m?.salary) },
        { label: 'Bonus', value: k(m?.bonus) },
        {
          label: 'Equity',
          value: m?.equity == null ? '—' : m.equity.toLocaleString('en-US'),
        },
      ];
    }

    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name='Of'
            @hue='var(--muted)'
            @shape='rounded'
            aria-hidden='true'
          /></:avatar>
        <:title>{{offerTitle @model}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{offerMeta @model}}</span></:subtitle>
        <:metric>{{#let (get this.strip 0) as |s|}}{{#if s}}<Metric
                @value={{s.value}}
                @label={{s.label}}
              />{{/if}}{{/let}}</:metric>
        <:details>

          <Detail @label='Approval'>{{this.approvedCount}}
            of
            {{this.approvalTotal}}
            approved</Detail>
          <Detail @label='Base salary'><span class='mono'>{{formatMoney
                @model.salary
              }}</span></Detail>
          {{#if @model.candidate}}
            <Detail @label='Candidate'><@fields.candidate
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}

          <Detail @label='Start date'><span class='mono'>{{if
                @model.startDate
                (formatDay @model.startDate)
                '—'
              }}</span></Detail>
          {{#if @model.position}}
            <Detail @label='Position'><@fields.position
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}
          <Detail @label='Bonus'><span class='mono'>{{formatMoney
                @model.bonus
              }}</span></Detail>
          <Detail @label='Equity'><span class='mono'>{{unitsLabel
                @model.equity
              }}</span></Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 500;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
