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
import { Alert } from '../../ui-component/components/alert';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FitTile } from '../../ui-component/components/fit-tile';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

import { Employee } from './employee';
import { Skill } from './skill';
import { ApprovalChainField } from './approval-chain-field';
import { InterviewPlan } from './interview-plan';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from './utils';
import { QUIET_AVATAR_HUE } from './hr-ui';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';

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
    return `${fmt(min)} – ${fmt(max)}`;
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

// The status chip's tone. Open and filled read as on-track, on-hold as a
// warning and closed (ended without a hire) as danger, the same story the
// `POSITION_STATUS_HUES` map tells.
const POSITION_STATUS_TONES: Record<string, 'success' | 'warning' | 'danger'> =
  {
    open: 'success',
    'on-hold': 'warning',
    filled: 'success',
    closed: 'danger',
  };

// A date as "Sep 1, 2026", or "Sep 1" without the year. Local time, as the
// DateField's own view reads it.
function shortDate(d?: Date | null, withYear = true): string | undefined {
  if (!d) {
    return undefined;
  }
  let date = new Date(d);
  if (isNaN(date.getTime())) {
    return undefined;
  }
  return date.toLocaleDateString(
    'en-US',
    withYear
      ? { month: 'short', day: 'numeric', year: 'numeric' }
      : { month: 'short', day: 'numeric' },
  );
}

// "full-time" → "Full-time", for enum values printed as a fact.
function sentenceCase(s?: string | null): string {
  return s ? s[0].toUpperCase() + s.slice(1) : '—';
}

// The labels every Position format shares, so isolated, embedded, fitted
// and atom can never print the same fact two ways.
class PositionView extends Component<typeof Position> {
  get statusTone(): 'success' | 'warning' | 'danger' | 'neutral' {
    let status = this.args.model?.status;
    return (status && POSITION_STATUS_TONES[status]) || 'neutral';
  }
  /** "Engineering · Remote (US) · REQ-2026-014" */
  get avatarName(): string {
    return this.args.model?.title ?? '';
  }
  get subline(): string {
    let m = this.args.model;
    return [m?.department, m?.workLocation, m?.requisitionCode]
      .filter(Boolean)
      .join(' · ');
  }
  get salaryLabel(): string | undefined {
    return salaryRangeLabel(
      this.args.model?.salaryMin,
      this.args.model?.salaryMax,
      { compact: true },
    );
  }
  get targetStartLabel() {
    return shortDate(this.args.model?.targetStartDate);
  }
  get postedLabel() {
    return shortDate(this.args.model?.postedDate);
  }
  get postedShort() {
    return shortDate(this.args.model?.postedDate, false);
  }
  get headcountLabel(): string {
    let n = this.args.model?.headcount;
    return n == null ? '—' : String(n);
  }
  get facts(): Record<string, string> {
    let m = this.args.model;
    return {
      salary: this.salaryLabel ?? '—',
      headcount: this.headcountLabel,
      type: sentenceCase(m?.employmentType),
      level: sentenceCase(m?.experienceLevel),
      location: m?.workLocation || '—',
      remote: m?.remoteEligible == null ? '—' : m.remoteEligible ? 'Yes' : 'No',
      posted: this.postedLabel ?? '—',
      start: this.targetStartLabel ?? '—',
      requisition: m?.requisitionCode || '—',
    };
  }
}

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class PositionIsolated extends PositionView {
  get daysOpenLabel(): string | undefined {
    let d = daysOpen(this.args.model?.postedDate);
    return d == null ? undefined : `${d} days open`;
  }

  // A requisition that has been open a long time is a fact worth surfacing;
  // none of the four hand-set statuses can tell you this.
  get isStale(): boolean {
    let d = daysOpen(this.args.model?.postedDate);
    return d != null && d >= 45 && this.args.model?.status === 'open';
  }

  get ageingLabel(): string {
    return `${this.daysOpenLabel} · ageing`;
  }

  get targetStartShort(): string {
    return shortDate(this.args.model?.targetStartDate, false) ?? '—';
  }

  get headcountHint(): string {
    return this.args.model?.headcount === 0 ? 'fully staffed' : 'open';
  }

  get postedHint(): string | undefined {
    return this.postedLabel ? `posted ${this.postedLabel}` : undefined;
  }

  get roleFacts(): KeyValueItem[] {
    let f = this.facts;
    return [
      { key: 'Employment type', value: f.type },
      { key: 'Experience level', value: f.level },
      { key: 'Work location', value: f.location },
      { key: 'Remote eligible', value: f.remote },
      { key: 'Requisition', value: f.requisition },
    ];
  }

  get detailFacts(): KeyValueItem[] {
    let f = this.facts;
    return [
      { key: 'Salary', value: f.salary },
      { key: 'Headcount', value: f.headcount },
      { key: 'Type', value: f.type },
      { key: 'Level', value: f.level },
      { key: 'Location', value: f.location },
      { key: 'Posted', value: f.posted },
      { key: 'Target start', value: f.start },
      { key: 'Requisition', value: f.requisition },
    ];
  }

  // Rows whose value is a linked card; the `<:value>` block renders its atom.
  get linkedFacts(): KeyValueItem[] {
    return [
      { key: 'Hiring manager', value: 'hiringManager' },
      { key: 'Interview plan', value: 'interviewPlan' },
    ];
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
      <header class='iso-head'>
        <Avatar
          @name={{this.avatarName}}
          @hue={{QUIET_AVATAR_HUE}}
          @size={{48}}
          aria-hidden='true'
        />
        <div class='iso-id'>
          <h1>{{@model.title}}</h1>
          {{#if this.subline}}
            <p class='iso-sub'>{{this.subline}}</p>
          {{/if}}
        </div>
        <div class='chips'>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
          {{/if}}
          {{#if @model.experienceLevel}}
            <StatusChip @value={{@model.experienceLevel}} @tone='neutral' />
          {{/if}}
          {{#if @model.remoteEligible}}
            <StatusChip @value='remote' @tone='info' />
          {{/if}}
          {{#if this.isStale}}
            <StatusChip @value={{this.ageingLabel}} @tone='warning' />
          {{/if}}
        </div>
      </header>

      <div class='stat-row'>
        <Stat
          @label='Headcount'
          @value={{this.headcountLabel}}
          @hint={{this.headcountHint}}
          @roll={{false}}
        />
        <Stat
          @label='Salary'
          @value={{this.facts.salary}}
          @hint='base'
          @roll={{false}}
        />
        <Stat
          @label='Target start'
          @value={{this.targetStartShort}}
          @hint={{this.postedHint}}
          @roll={{false}}
        />
      </div>

      <div class='iso-body'>
        <div class='iso-col'>
          <Panel @title='Role'>
            {{#if @model.jobDescription}}
              <p class='prose'>{{@model.jobDescription}}</p>
            {{else}}
              <EmptyState
                @texture={{false}}
                @title='No job description added yet'
              />
            {{/if}}
          </Panel>

          <Panel @title='Details'>
            <KeyValue class='kv' @items={{this.roleFacts}}>
              <:value as |row|><span class='v'>{{row.value}}</span></:value>
            </KeyValue>
          </Panel>

          <Panel @title='Required skills'>
            {{#if @model.requiredSkills.length}}
              <ul class='tag-row'>
                {{#each @fields.requiredSkills as |SkillAtom|}}
                  <li><SkillAtom
                      @format='atom'
                      @displayContainer={{false}}
                    /></li>
                {{/each}}
              </ul>
            {{else}}
              <EmptyState @texture={{false}} @title='No skills listed yet' />
            {{/if}}
          </Panel>

          <Panel @title='Approval chain'>
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
          </Panel>
        </div>

        <div class='iso-col'>
          <Panel @title='Linked'>
            <KeyValue class='kv' @items={{this.linkedFacts}}>
              <:value as |row|>
                {{#if (eq row.value 'hiringManager')}}
                  {{#if @model.hiringManager}}<@fields.hiringManager
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}&mdash;{{/if}}
                {{else if @model.interviewPlan}}
                  <@fields.interviewPlan
                    @format='atom'
                    @displayContainer={{false}}
                  />
                {{else}}
                  &mdash;
                {{/if}}
              </:value>
            </KeyValue>
          </Panel>

          <Panel @title='Details'>
            <KeyValue class='kv' @items={{this.detailFacts}}>
              <:value as |row|><span class='v'>{{row.value}}</span></:value>
            </KeyValue>
          </Panel>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .position-isolated {
          container-type: inline-size;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          box-sizing: border-box;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .iso-id {
          flex: 1 1 0;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--primary);
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
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp);
          margin-top: var(--boxel-sp-lg);
        }
        .iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
          gap: var(--boxel-sp-lg);
          margin-top: var(--boxel-sp-lg);
        }
        .iso-col {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          min-width: 0;
        }
        .prose {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          white-space: pre-line;
        }
        /* KeyValue's knobs: keys as muted body text, the mockup's list. */
        .kv {
          --pretui-kv-label-font-size: var(--boxel-font-size-sm);
          --pretui-kv-label-font-weight: 400;
          font-size: var(--boxel-font-size-sm);
        }
        .v {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .tag-row {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .approval-actions {
          display: flex;
          gap: var(--boxel-sp-xs);
          margin-top: var(--boxel-sp-xs);
        }
        .notice {
          margin-top: var(--boxel-sp-xs);
        }
        @container (max-width: 44rem) {
          .iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
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

  static embedded = class Embedded extends PositionView {
    get gridFacts(): DescriptionsItem[] {
      let f = this.facts;
      return [
        { label: 'Salary', value: f.salary },
        { label: 'Headcount', value: f.headcount },
        { label: 'Type', value: f.type },
        { label: 'Level', value: f.level },
        { label: 'Location', value: f.location },
        { label: 'Posted', value: f.posted },
      ];
    }
    get hasRelations(): boolean {
      return Boolean(
        this.args.model?.hiringManager || this.args.model?.interviewPlan,
      );
    }
    <template>
      <article class='position-embedded'>
        <header class='emb-head'>
          <Avatar
            @name={{this.avatarName}}
            @hue={{QUIET_AVATAR_HUE}}
            @size={{40}}
            aria-hidden='true'
          />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.title}}</h3>
            {{#if this.subline}}
              <p class='emb-sub'>{{this.subline}}</p>
            {{/if}}
          </div>
          <div class='emb-chips'>
            {{#if @model.status}}
              <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
            {{/if}}
            {{#if @model.experienceLevel}}
              <StatusChip @value={{@model.experienceLevel}} @tone='neutral' />
            {{/if}}
            {{#if @model.remoteEligible}}
              <StatusChip @value='remote' @tone='info' />
            {{/if}}
          </div>
        </header>
        {{#if this.targetStartLabel}}
          <p class='emb-fact'>Start by
            <strong>{{this.targetStartLabel}}</strong>{{#if this.postedShort}}
              &middot; posted
              {{this.postedShort}}{{/if}}</p>
        {{/if}}
        <Descriptions
          class='emb-kv'
          @items={{this.gridFacts}}
          @layout='vertical'
          @columns={{3}}
        >
          <:value as |row|><span class='v'>{{row.value}}</span></:value>
        </Descriptions>
        {{#if this.hasRelations}}
          <div class='emb-rels'>
            {{#if @model.hiringManager}}
              <span class='rel'>Hiring manager
                <@fields.hiringManager
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
            {{#if @model.interviewPlan}}
              <span class='rel'>Interview plan
                <@fields.interviewPlan
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/if}}
          </div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .position-embedded {
            container-type: inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
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
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            max-width: 100%;
          }
          @container (max-width: 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .emb-chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends PositionView {
    <template>
      <span class='position-atom'>
        <Avatar
          @name={{this.avatarName}}
          @hue={{QUIET_AVATAR_HUE}}
          @size={{20}}
          aria-hidden='true'
        />
        <span class='position-atom-name'>{{@model.title}}</span>
        {{#if @model.status}}
          <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .position-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .position-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  // Under 170 tall the four FitTile rows are the whole budget. From 170 up
  // the mockup adds rows FitTile has no slot for (one relation per line, a
  // fact list, a stat strip), so that layout is drawn here and the two
  // swap on the fitted-card container's height.
  static fitted = class Fitted extends PositionView {
    get statFacts() {
      return [
        { key: 'Headcount', value: this.headcountLabel },
        {
          key: 'Target start',
          value: shortDate(this.args.model?.targetStartDate, false) ?? '—',
        },
      ];
    }
    get kvFacts() {
      let f = this.facts;
      return [
        { key: 'Salary', value: f.salary },
        { key: 'Headcount', value: f.headcount },
        { key: 'Type', value: f.type },
        { key: 'Level', value: f.level },
        { key: 'Location', value: f.location },
        { key: 'Posted', value: f.posted },
        { key: 'Target start', value: f.start },
        { key: 'Requisition', value: f.requisition },
      ];
    }

    <template>
      <div class='fit-short'>
        <FitTile>
          <:avatar>
            <Avatar
              @name={{this.avatarName}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              class='fit-title'
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{this.subline}}</:subtitle>
          <:status>
            {{#if @model.status}}
              <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
            {{/if}}
            {{#if @model.experienceLevel}}
              <StatusChip @value={{@model.experienceLevel}} @tone='neutral' />
            {{/if}}
            {{#if @model.remoteEligible}}
              <StatusChip @value='remote' @tone='info' />
            {{/if}}
          </:status>
          <:fact>{{#if this.targetStartLabel}}Start by
              <strong class='fit-strong'>{{this.targetStartLabel}}</strong>{{#if
                this.postedShort
              }}
                &middot; posted
                {{this.postedShort}}{{/if}}{{else}}{{this.salaryLabel}}{{/if}}</:fact>
          <:relations><@fields.hiringManager
              @format='atom'
            /><@fields.interviewPlan @format='atom' /></:relations>
        </FitTile>
      </div>

      <article class='fit-tall'>
        <header class='ft-who'>
          <span class='ft-av'><Avatar
              @name={{this.avatarName}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            /></span>
          <div class='ft-id'>
            <div class='ft-line1'>
              <span
                class='ft-title'
                role='heading'
                aria-level='3'
              >{{@model.title}}</span>
              <span class='ft-chips ft-chips-inline'>
                {{#if @model.status}}
                  <StatusChip
                    @value={{@model.status}}
                    @tone={{this.statusTone}}
                  />
                {{/if}}
                {{#if @model.experienceLevel}}
                  <StatusChip
                    @value={{@model.experienceLevel}}
                    @tone='neutral'
                  />
                {{/if}}
                {{#if @model.remoteEligible}}
                  <StatusChip @value='remote' @tone='info' />
                {{/if}}
              </span>
            </div>
            {{#if this.subline}}
              <p class='ft-sub'>{{this.subline}}</p>
            {{/if}}
          </div>
        </header>
        <div class='ft-chips ft-chips-row'>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
          {{/if}}
          {{#if @model.experienceLevel}}
            <StatusChip @value={{@model.experienceLevel}} @tone='neutral' />
          {{/if}}
          {{#if @model.remoteEligible}}
            <StatusChip @value='remote' @tone='info' />
          {{/if}}
        </div>
        <p class='ft-fact'>{{#if this.targetStartLabel}}Start by
            <strong class='fit-strong'>{{this.targetStartLabel}}</strong>{{#if
              this.postedShort
            }}
              &middot; posted
              {{this.postedShort}}{{/if}}{{else}}{{this.salaryLabel}}{{/if}}</p>
        <dl class='ft-stats'>
          {{#each this.statFacts as |s|}}
            <div><dt>{{s.key}}</dt><dd>{{s.value}}</dd></div>
          {{/each}}
        </dl>
        <dl class='ft-kv'>
          {{#each this.kvFacts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <ul class='ft-rels'>
          {{#if @model.hiringManager}}
            <li class='ft-rel'><span class='ft-k'>Hiring manager</span><@fields.hiringManager
                @format='atom'
              /></li>
          {{/if}}
          {{#if @model.interviewPlan}}
            <li class='ft-rel ft-rel-plan'><span
                class='ft-k ft-k-wide'
              >Interview plan</span><@fields.interviewPlan
                @format='atom'
              /></li>
          {{/if}}
        </ul>
      </article>
      <style scoped>
        @layer PretComponent {
          .fit-short {
            block-size: 100%;
          }
          .fit-title {
            display: block;
            margin: 0;
            font-size: inherit;
            font-weight: inherit;
            line-height: inherit;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-strong {
            font-weight: 600;
            color: var(--foreground);
          }

          /* ── 170 tall and up ── */
          .fit-tall {
            display: none;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            block-size: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
            color: var(--foreground);
          }
          .fit-tall > * {
            flex: none;
            min-width: 0;
            margin: 0;
          }
          .ft-who {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
            min-width: 0;
          }
          .ft-av {
            display: none;
            flex: none;
          }
          .ft-id {
            flex: 1 1 auto;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-6xs);
          }
          .ft-line1 {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .ft-title {
            flex: 1 1 auto;
            min-width: 7rem;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .ft-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          /* Chips past the line's end wrap out of sight whole. */
          .ft-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            max-height: var(--boxel-sp-lg);
            overflow: hidden;
          }
          .ft-chips-inline {
            display: none;
            flex: 0 1 auto;
            justify-content: flex-end;
          }
          .ft-fact {
            color: var(--muted-foreground);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .ft-stats,
          .ft-kv {
            display: none;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          }
          .ft-stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
          }
          .ft-stats div {
            display: flex;
            flex-direction: column;
            min-width: 0;
            overflow: hidden;
          }
          .ft-stats dt {
            color: var(--muted-foreground);
            white-space: nowrap;
          }
          .ft-stats dd {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            color: var(--primary);
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
          }
          .ft-kv div {
            display: flex;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            overflow: hidden;
          }
          .ft-kv dt {
            flex: none;
            color: var(--muted-foreground);
          }
          .ft-kv dd {
            margin: 0;
            min-width: 0;
            font-weight: 600;
            text-align: right;
            font-variant-numeric: tabular-nums;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .ft-rels {
            list-style: none;
            padding: 0;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-4xs);
          }
          .ft-rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-width: 0;
            height: var(--boxel-sp-lg);
            overflow: hidden;
            white-space: nowrap;
          }
          .ft-k,
          .ft-rel-plan {
            display: none;
          }
          .ft-k {
            flex: none;
            color: var(--muted-foreground);
          }

          @container fitted-card (height >= 170px) {
            .fit-short {
              display: none;
            }
            .fit-tall {
              display: flex;
            }
          }
          /* The avatar shows from 250 wide, and on tall narrow tiles above
             the title. */
          @container fitted-card (width >= 250px) {
            .ft-av {
              display: inline-flex;
            }
            .ft-k {
              display: inline;
            }
            .ft-k-wide {
              display: none;
            }
          }
          @container fitted-card (width < 250px) and (height >= 250px) {
            .ft-who {
              flex-direction: column;
              align-items: flex-start;
              gap: var(--boxel-sp-xs);
            }
            .ft-id {
              width: 100%;
            }
            .ft-av {
              display: inline-flex;
            }
          }
          @container fitted-card (height >= 250px) {
            .fit-tall {
              padding: var(--boxel-sp);
            }
            .ft-rel-plan {
              display: flex;
            }
          }
          /* From 400 wide the chips share the title line. */
          @container fitted-card (width >= 400px) {
            .ft-chips-inline {
              display: flex;
            }
            .ft-chips-row {
              display: none;
            }
            .ft-rel-plan {
              display: flex;
            }
            .ft-k-wide {
              display: inline;
            }
          }
          @container fitted-card (width >= 250px) and (height >= 275px) {
            .ft-kv {
              display: grid;
            }
          }
          /* 250 wide: salary and headcount only. */
          @container fitted-card (width < 400px) and (height >= 275px) {
            .ft-kv div:nth-child(n + 3) {
              display: none;
            }
          }
          /* 400 × 275: six facts in two columns. */
          @container fitted-card (width >= 400px) and (height >= 275px) and (height < 445px) {
            .ft-kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .ft-kv div:nth-child(n + 7) {
              display: none;
            }
          }
          @container fitted-card (height >= 445px) {
            .ft-stats {
              display: grid;
            }
          }
        }
      </style>
    </template>
  };
}
