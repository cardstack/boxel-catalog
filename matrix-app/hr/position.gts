import type { TemplateOnlyComponent } from '@ember/component/template-only';
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
import { dotEnumField } from './dot-enum-field';
import BriefcaseBusinessIcon from '@cardstack/boxel-icons/briefcase-business';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

import { Employee } from './employee';
import { Skill } from './skill';
import { Button } from '@cardstack/pretui/components/button';
import { ApprovalChainField } from './approval-chain-field';
import { InterviewPlan } from './interview-plan';
import { ApproveChainStepCommand } from './commands/approve-chain-step-command';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { formatMoney } from './utils';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from './compact-sheet';

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

export const PositionStatusField = dotEnumField(
  {
    options: POSITION_STATUSES.map((status) => ({
      value: status,
      label: status,
    })),
    displayName: 'Position Status',
  },
  POSITION_STATUS_HUES,
);

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

export function statusTone(
  status?: string | null,
): 'success' | 'warning' | 'danger' | 'neutral' {
  return (status && POSITION_STATUS_TONES[status]) || 'neutral';
}

// "on-hold" → "On-Hold", the label the tab and every format print.
export function statusLabel(status?: string | null): string {
  return (status ?? '').replace(
    /(^|-)([a-z])/g,
    (_m, sep: string, c: string) => sep + c.toUpperCase(),
  );
}

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

// "$150k+": the salary floor, short enough for a fitted stat.
function salaryFloor(min?: number | null): string {
  return min == null ? '—' : '$' + Math.round(min / 1000) + 'k+';
}

// "full-time" → "Full-time", for enum values printed as a fact.
function sentenceCase(s?: string | null): string {
  return s ? s[0].toUpperCase() + s.slice(1) : '—';
}

// The record's type mark: a square, not an Avatar, because a Position is
// not a person. Knobs: `--position-mark-size`, `--position-mark-font-size`.
const PositionMark: TemplateOnlyComponent<{ Element: HTMLSpanElement }> =
  <template>
    <span class='position-mark' aria-hidden='true' ...attributes>Po</span>
    <style scoped>
      @layer PretComponent {
        .position-mark {
          display: inline-grid;
          flex: none;
          place-items: center;
          inline-size: var(--position-mark-size, 2rem);
          block-size: var(--position-mark-size, 2rem);
          border-radius: calc(var(--radius) - 2px);
          background: var(--card);
          box-shadow: inset 0 0 0 1px var(--border);
          color: var(--primary-ink);
          font-size: var(--position-mark-font-size, var(--boxel-font-size-xs));
          font-weight: 600;
          line-height: 1;
        }
      }
    </style>
  </template>;

// The labels every Position format shares, so isolated, embedded, fitted
// and atom can never print the same fact two ways.
class PositionView extends Component<typeof Position> {
  get statusTone(): 'success' | 'warning' | 'danger' | 'neutral' {
    return statusTone(this.args.model?.status);
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

  get strip(): StripItem[] {
    return [
      {
        label: 'Headcount',
        value: this.headcountLabel,
        hint: this.headcountHint,
        tone: 'success',
      },
      { label: 'Salary', value: this.facts.salary, hint: 'base', tone: 'info' },
      {
        label: 'Target start',
        value: this.targetStartShort,
        hint: this.postedHint,
        tone: 'warning',
      },
    ];
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{this.subline}}>
          <:mark><PositionMark /></:mark>
          <:aside>{{#if @model.status}}<@fields.status
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}{{#if this.isStale}}<span
                class='muted'
              >{{this.ageingLabel}}</span>{{/if}}</:aside>
          <:stats><StatStrip @items={{this.strip}} /></:stats>
        </IsoHead>
      </:head>
      <:main>
        <Panel @title='Role'>
          <SheetLine>{{#if @model.jobDescription}}<span
                class='prose'
              >{{@model.jobDescription}}</span>{{else}}<span class='muted'>No
                job description added yet.</span>{{/if}}</SheetLine>
        </Panel>
        <Panel @title='Details'><Kv @items={{this.roleFacts}} /></Panel>
        <Panel @title='Required skills' @meta={{this.skillCount}}>
          {{#each @fields.requiredSkills as |SkillAtom|}}
            <SheetLine><SkillAtom
                @format='atom'
                @displayContainer={{false}}
              /></SheetLine>
          {{else}}
            <SheetLine><span class='muted'>No skills listed yet.</span></SheetLine>
          {{/each}}
        </Panel>
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
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{this.linkedFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'hiringManager')}}
                {{#if @model.hiringManager}}<@fields.hiringManager
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if @model.interviewPlan}}
                <@fields.interviewPlan
                  @format='atom'
                  @displayContainer={{false}}
                />
              {{else}}—{{/if}}
            </:value>
          </Kv>
        </Panel>
        <Panel @title='Details'><Kv @items={{this.detailFacts}} /></Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .muted {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .prose {
        white-space: pre-line;
      }
    </style>
  </template>

  get skillCount(): string {
    return String((this.args.model?.requiredSkills ?? []).length);
  }
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
    get rows() {
      let f = this.facts;
      return [
        { key: 'Start by', value: f.start },
        { key: 'Salary', value: f.salary },
        { key: 'Headcount', value: f.headcount },
        { key: 'Type', value: f.type },
        { key: 'Level', value: f.level },
        { key: 'Location', value: f.location },
        { key: 'Posted', value: f.posted },
        { key: 'Hiring manager', value: '' },
        { key: 'Interview plan', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.subline}}>
        <:mark><PositionMark /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>
              {{#if (eq row.key 'Hiring manager')}}
                {{#if @model.hiringManager}}<@fields.hiringManager
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}
              {{else if (eq row.key 'Interview plan')}}
                {{#if @model.interviewPlan}}<@fields.interviewPlan
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

  static atom = class Atom extends PositionView {
    <template>
      <span class='position-atom'>
        <PositionMark class='atom-mark' />
        <span class='position-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .position-atom {
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
            line-height: 1.375rem;
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-mark {
            --position-mark-size: 1.25rem;
            --position-mark-font-size: var(--boxel-font-size-2xs);
          }
          .position-atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends PositionView {
    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        { label: 'Salary', value: salaryFloor(m?.salaryMin) },
        { label: 'Headcount', value: this.headcountLabel },
        {
          label: 'Level',
          value: m?.experienceLevel ? sentenceCase(m.experienceLevel) : '—',
        },
      ];
    }
    <template>
      <FitCard @title={{@model.title}}>
        <:mark><PositionMark /></:mark>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:default>
          <FitRow @left={{true}}><span
              class='meta'
            >{{this.subline}}</span></FitRow>
          <FitRow @label='Level'>{{this.facts.level}}</FitRow>
          <FitRow @label='Start by'><span
              class='mono'
            >{{this.facts.start}}</span></FitRow>
          {{#if @model.hiringManager}}
            <FitRow @label='Hiring mgr' @left={{true}}><@fields.hiringManager
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <FitRow @label='Salary'><span
              class='mono'
            >{{this.facts.salary}}</span></FitRow>
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#if @model.interviewPlan}}
            <FitRow @label='Plan' @left={{true}}><@fields.interviewPlan
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <FitRow @label='Type'>{{this.facts.type}}</FitRow>
          <FitRow @label='Location'>{{this.facts.location}}</FitRow>
          <FitRow @label='Posted'><span
              class='mono'
            >{{this.facts.posted}}</span></FitRow>
          <FitRow @label='Requisition'><span
              class='mono'
            >{{this.facts.requisition}}</span></FitRow>
        </:default>
      </FitCard>
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
