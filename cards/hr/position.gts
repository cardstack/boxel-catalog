import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import NumberField from 'https://cardstack.com/base/number';
import TextAreaField from 'https://cardstack.com/base/text-area';
import BooleanField from 'https://cardstack.com/base/boolean';
import enumField from 'https://cardstack.com/base/enum';
import BriefcaseBusinessIcon from '@cardstack/boxel-icons/briefcase-business';
import { BoxelButton } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { Token } from '@cardstack/pretui/components/token';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

import { Employee } from './employee';
import { Skill } from './skill';
import { ApprovalChainField } from './approval-chain-field';
import { InterviewPlan } from './interview-plan';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from './utils';
import { FactList, MoneyRange, hueOf } from './hr-ui';
import {
  ALERT_STYLE,
  ID_TOKEN_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';

const MS_PER_DAY = 1000 * 60 * 60 * 24;

// How long this requisition has been open. Derived from postedDate, so the
// isolated and fitted views can never report different ages.
function daysOpen(postedDate?: Date | null): number | undefined {
  if (!postedDate) {
    return undefined;
  }
  let d = new Date(postedDate);
  if (isNaN(d.getTime())) {
    return undefined;
  }
  return Math.max(0, Math.round((Date.now() - d.getTime()) / MS_PER_DAY));
}

export const POSITION_STATUSES = ['open', 'on-hold', 'filled', 'closed'];

export const EMPLOYMENT_TYPES = [
  'full-time',
  'part-time',
  'contract',
  'internship',
];

export const EXPERIENCE_LEVELS = ['entry', 'mid', 'senior', 'lead'];

// Colocated with Position — reuses the Ledger palette so a requisition's
// lifecycle reads as the front half of the same story Candidate/Employee
// tell: open leans on the same green as "screening" (active work), filled
// resolves into the "hired"/"active" forest green, closed lands on the same
// rust as "rejected" (a req that ended without a hire).
export const POSITION_STATUS_HUES: Record<string, Hue> = {
  open: 'green',
  'on-hold': 'amber',
  filled: 'green',
  closed: 'red',
};

function salaryRangeLabel(
  min?: number | null,
  max?: number | null,
  opts?: { compact?: boolean },
): string | undefined {
  if (min == null && max == null) {
    return undefined;
  }
  let fmt = (n: number) => formatMoney(n, opts)!;
  if (min != null && max != null) {
    return `${fmt(min)}–${fmt(max)}`;
  }
  return fmt(min ?? max!);
}

export const PositionStatusField = enumField(StringField, {
  options: POSITION_STATUSES.map((status) => ({
    value: status,
    label: status,
  })),
  displayName: 'Position Status',
});

export const EmploymentTypeField = enumField(StringField, {
  options: EMPLOYMENT_TYPES.map((type) => ({ value: type, label: type })),
  displayName: 'Employment Type',
});

export const ExperienceLevelField = enumField(StringField, {
  options: EXPERIENCE_LEVELS.map((level) => ({ value: level, label: level })),
  displayName: 'Experience Level',
});

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class PositionIsolated extends Component<typeof Position> {
  get statusHue() {
    return hueOf(POSITION_STATUS_HUES, this.args.model?.status);
  }
  get salaryRangeLabel() {
    return salaryRangeLabel(
      this.args.model?.salaryMin,
      this.args.model?.salaryMax,
      { compact: true },
    );
  }
  get remoteLabel(): string {
    let v = this.args.model?.remoteEligible;
    return v == null ? '—' : v ? 'Yes' : 'No';
  }
  get headcountLabel(): string {
    let n = this.args.model?.headcount;
    if (n == null) {
      return '—';
    }
    return n === 0 ? '0 · fully staffed' : `${n} open`;
  }
  get openSeatsLabel(): string {
    let n = this.args.model?.headcount;
    if (n == null) {
      return '— open seats';
    }
    return n === 0 ? 'Fully staffed' : `${n} open seat${n === 1 ? '' : 's'}`;
  }

  get daysOpenLabel(): string | undefined {
    let d = daysOpen(this.args.model?.postedDate);
    return d == null ? undefined : `${d} days open`;
  }

  get ageingLabel(): string | undefined {
    return this.isStale ? `${this.daysOpenLabel} · ageing` : undefined;
  }

  // The Role facts as Pret UI `KeyValue` rows. A row whose value is a field
  // or a money figure carries a key the `<:value>` block renders; every other
  // row prints its text.
  get roleFacts(): KeyValueItem[] {
    let m = this.args.model;
    let hasSalary = m?.salaryMin != null || m?.salaryMax != null;
    return [
      { key: 'Department', value: m?.department || '—' },
      { key: 'Salary range', value: hasSalary ? 'salary' : '—' },
      { key: 'Headcount', value: this.headcountLabel },
      { key: 'Experience', value: m?.experienceLevel || '—' },
      { key: 'Employment', value: m?.employmentType || '—' },
      { key: 'Location', value: m?.workLocation || '—' },
      { key: 'Remote', value: this.remoteLabel },
      { key: 'Posted', value: m?.postedDate ? 'postedDate' : '—' },
      {
        key: 'Target start',
        value: m?.targetStartDate ? 'targetStartDate' : '—',
      },
    ];
  }

  // A requisition that has been open a long time is a fact worth surfacing;
  // none of the four hand-set statuses can tell you this.
  get isStale(): boolean {
    let d = daysOpen(this.args.model?.postedDate);
    return d != null && d >= 45 && this.args.model?.status === 'open';
  }

  // The click-to-decide affordance lives here, not inside
  // ApprovalChainField's own template — see approval-chain-field.gts's
  // class comment for why. This mirrors how every other stage-changing
  // action in this app (ApproveOfferCommand, RejectCandidateCommand) is
  // invoked from the consuming card/tracker rather than from a field.
  @tracked approvalBusy = false;
  @tracked approvalError: string | undefined;

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
    <article class='position-isolated'>
      <header class='hero'>
        <div class='hero-text'>
          <h1>{{@model.title}}</h1>
          <p class='byline'>
            {{if @model.department @model.department 'No department set'}}
            {{#if @model.requisitionCode}}
              <span class='sep-dot'>&middot;</span>
              <Token
                @value={{@model.requisitionCode}}
                style={{ID_TOKEN_STYLE.sm}}
              />
            {{/if}}
          </p>
          <div class='pill-row'>
            <StatePill
              @label={{@model.status}}
              @hue={{this.statusHue}}
              @dot={{true}}
            />
            {{#if this.isStale}}
              <StatePill
                @label={{this.ageingLabel}}
                @hue='attention'
                @dot={{true}}
              />
            {{else}}
              <StatePill @label={{this.daysOpenLabel}} />
            {{/if}}
            <StatePill @label={{@model.experienceLevel}} />
          </div>
        </div>
        <div class='hero-money'>
          <Stat
            class='money'
            @label='Salary range'
            @value={{if this.salaryRangeLabel this.salaryRangeLabel ''}}
            @hint={{this.openSeatsLabel}}
            @roll={{false}}
          />
        </div>
      </header>

      <div class='body'>
        <div class='main'>
          <h2 class='panel-title'>Role</h2>
          <FactList @items={{this.roleFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'salary')}}
                <MoneyRange
                  @min={{@model.salaryMin}}
                  @max={{@model.salaryMax}}
                />
              {{else if (eq row.value 'postedDate')}}
                <span><@fields.postedDate />{{#if this.daysOpenLabel}}<span
                      class='dd-note'
                    >
                      &middot;
                      {{this.daysOpenLabel}}</span>{{/if}}</span>
              {{else if (eq row.value 'targetStartDate')}}
                <@fields.targetStartDate />
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </FactList>

          <h2 class='panel-title spaced'>Required skills</h2>
          {{#if @model.requiredSkills.length}}
            <ul class='chips'>
              {{#each @fields.requiredSkills as |Skill|}}
                <li><Skill @format='atom' @displayContainer={{false}} /></li>
              {{/each}}
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No skills listed yet'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Job description</h2>
          {{#if @model.jobDescription}}
            <p class='prose'>{{@model.jobDescription}}</p>
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No job description added yet'
            />
          {{/if}}

          <h2 class='panel-title spaced'>Interview Plan</h2>
          {{#if @model.interviewPlan}}
            <@fields.interviewPlan @format='embedded' />
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No interview plan yet'
              @message='Running Generate questions from a candidate applying to this position will create one.'
            />
          {{/if}}
        </div>

        <aside class='side'>
          <h2 class='panel-title'>Owner</h2>
          <dl class='stacked'>
            <dt>Hiring manager</dt>
            <dd>{{#if @model.hiringManager}}<@fields.hiringManager
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash;{{/if}}</dd>
          </dl>

          <h2 class='panel-title spaced'>Approval Chain</h2>
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

          <h2 class='panel-title spaced'>Requisition</h2>
          <dl class='stacked'>
            <dt>Status</dt>
            <dd>{{if @model.status @model.status '—'}}</dd>
            <dt>Open for</dt>
            <dd>{{if this.daysOpenLabel this.daysOpenLabel '—'}}</dd>
            <dt>Skills listed</dt>
            <dd>{{if @model.skillTally @model.skillTally '0'}}</dd>
          </dl>
        </aside>
      </div>
    </article>
    <style scoped>
      .position-isolated {
        container-type: inline-size;
        container-name: iso;
        height: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
      }
      .dd-note {
        color: var(--muted-foreground);
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
      /* Stat's hint reads --ink-3, which boxel's theme leaves at a pale
         grey; the page's muted ink keeps it legible. */
      .money {
        --text-stat: 1.5rem;
        --ink-3: var(--muted-foreground);
        justify-items: end;
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
      .prose {
        font-size: var(--boxel-font-size-sm);
        line-height: 1.65;
        max-width: 56ch;
        max-height: 16rem;
        overflow-y: auto;
      }
      .chips {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      }
      .chips > li {
        font-size: var(--boxel-font-size-xs);
        padding: 0.15em 0.5em;
        border-radius: 0.1875rem;
        border: 1px solid var(--border);
        background-color: var(--card);
        color: var(--card-foreground);
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
        font-variant-numeric: tabular-nums;
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

export class Position extends CardDef {
  static displayName = 'Position';
  static icon = BriefcaseBusinessIcon;

  @field jobTitle = contains(StringField);
  @field department = contains(StringField);
  @field requisitionCode = contains(StringField, {
    description: 'Internal requisition ID for ATS/payroll cross-reference',
  });
  @field remoteEligible = contains(BooleanField, {
    description:
      'Filterable flag, independent of the descriptive workLocation text',
  });
  @field approvalChain = contains(ApprovalChainField);
  @field interviewPlan = linksTo(() => InterviewPlan);
  @field hiringManager = linksTo(() => Employee);
  @field status = contains(PositionStatusField);
  @field postedDate = contains(DateField);
  @field targetStartDate = contains(DateField);
  @field headcount = contains(NumberField);
  @field salaryMin = contains(NumberField);
  @field salaryMax = contains(NumberField);
  @field workLocation = contains(StringField, {
    description: 'City/region, or "Remote" / "Hybrid"',
  });
  @field employmentType = contains(EmploymentTypeField);
  @field experienceLevel = contains(ExperienceLevelField);
  @field requiredSkills = linksToMany(() => Skill);
  @field jobDescription = contains(TextAreaField, {
    description: 'Job description / requirements shown to applicants',
  });

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field hiringManagerName = contains(StringField, {
    computeVia: function (this: Position) {
      return this.hiringManager?.name ?? '';
    },
  });

  @field skillTally = contains(StringField, {
    computeVia: function (this: Position) {
      let n = this.requiredSkills?.length ?? 0;
      return n === 0 ? '' : String(n);
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Position) {
      return this.jobTitle?.trim() || 'Untitled Position';
    },
  });

  static isolated = PositionIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get statusHue() {
      return hueOf(POSITION_STATUS_HUES, this.args.model?.status);
    }
    <template>
      <div class='position-embedded'>
        <EntityDisplay
          class='entity'
          @variant='thumbnail'
          @title={{@model.title}}
          @subtitle={{@model.department}}
          @center={{true}}
        >
          <:visual><BriefcaseBusinessIcon class='entity-icon' /></:visual>
        </EntityDisplay>
        <StatePill
          class='pe-status'
          @label={{@model.status}}
          @hue={{this.statusHue}}
        />
      </div>
      <style scoped>
        .position-embedded {
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
        .pe-status {
          flex-shrink: 0;
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='position-atom'>
        <BriefcaseBusinessIcon class='position-atom-icon' />
        <span class='position-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .position-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .position-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .position-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get statusHue() {
      return hueOf(POSITION_STATUS_HUES, this.args.model?.status);
    }
    get salaryRangeLabel() {
      return salaryRangeLabel(
        this.args.model?.salaryMin,
        this.args.model?.salaryMax,
      );
    }
    get headcountLabel(): string | undefined {
      let n = this.args.model?.headcount;
      if (n == null) {
        return undefined;
      }
      return n === 0 ? 'Fully staffed' : `${n} open`;
    }
    get daysOpenLabel(): string | undefined {
      let d = daysOpen(this.args.model?.postedDate);
      return d == null ? undefined : `${d}d open`;
    }

    get isStale(): boolean {
      let d = daysOpen(this.args.model?.postedDate);
      return d != null && d >= 45 && this.args.model?.status === 'open';
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.department}}
              <span class='fit-eb'>{{@model.department}}{{#if
                  @model.experienceLevel
                }}
                  &middot;
                  {{@model.experienceLevel}}{{/if}}</span>
            {{/if}}
          </div>
          {{! Status pill survives every tier. }}
          <StatePill
            class='fit-pill'
            @label={{@model.status}}
            @hue={{this.statusHue}}
            @dot={{true}}
          />
        </div>

        <div class='fit-mid'>
          {{#if this.salaryRangeLabel}}
            <span class='money'>{{this.salaryRangeLabel}}</span>
          {{/if}}
          {{#if this.headcountLabel}}
            <span class='fit-sub'>{{this.headcountLabel}}{{#if
                @model.employmentType
              }}
                &middot;
                {{@model.employmentType}}{{/if}}</span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if this.daysOpenLabel}}
            <div><dt>Open</dt><dd>{{this.daysOpenLabel}}</dd></div>
          {{/if}}
          {{#if @model.workLocation}}
            <div><dt>Where</dt><dd>{{@model.workLocation}}</dd></div>
          {{/if}}
          {{#if @model.skillTally}}
            <div><dt>Skills</dt><dd>{{@model.skillTally}}</dd></div>
          {{/if}}
          {{#if @model.hiringManagerName}}
            <div><dt>Manager</dt><dd>{{@model.hiringManagerName}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING fields. 11px floor. Status never hidden. */
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
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
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
        .money {
          font-size: calc(var(--fit-name) * 1.15);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        .fit-sub {
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
          font-variant-numeric: tabular-nums;
        }

        /* TIER 2 — add the secondary line. Container queries have no `or`,
           so this is reached either by height (tile) or width (strip). */
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
        /* TIER 3 — add the headline figure block. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .fit-mid {
            display: flex;
          }
        }
        /* TIER 4 — width-driven extra facts. Previously absent entirely,
           which is why a 500x400 tile showed the same as a 200x140 one. */
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
        /* Short strip: horizontal, single-line name. */
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
        /* Smallest tier: secondary line goes, the status pill stays. */
        @container fitted-card (height <= 50px) {
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
