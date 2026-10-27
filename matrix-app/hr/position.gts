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
import BriefcaseBusinessIcon from '@cardstack/boxel-icons/briefcase-business';
import { BoxelButton } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Alert } from '../../ui-component/components/alert';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { EmptyState } from '../../ui-component/components/empty-state';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
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

// Status, level and remote as soft pills, the one chip set every
// non-fitted format prints.
const PositionChips: TemplateOnlyComponent<{
  Args: { model?: Partial<Position> };
  Blocks: { default: [] };
  Element: HTMLDivElement;
}> = <template>
  <div class='position-chips' ...attributes>
    {{#if @model.status}}<Chip
        @tone={{statusTone @model.status}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >{{statusLabel @model.status}}</Chip>{{/if}}
    {{#if @model.experienceLevel}}<Chip
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >{{sentenceCase @model.experienceLevel}}</Chip>{{/if}}
    {{#if @model.remoteEligible}}<Chip
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >Remote</Chip>{{/if}}
    {{yield}}
  </div>
  <style scoped>
    @layer PretComponent {
      .position-chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
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

  <template>
    <article class='position-isolated'>
      <header class='iso-head'>
        <PositionMark class='iso-mark' />
        <div class='iso-id'>
          <h1>{{@model.title}}</h1>
          {{#if this.subline}}
            <p class='iso-sub'>{{this.subline}}</p>
          {{/if}}
        </div>
        <PositionChips @model={{@model}}>
          {{#if this.isStale}}<Chip
              @tone='warning'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.ageingLabel}}</Chip>{{/if}}
        </PositionChips>
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
            <KeyValue class='kv' @items={{this.roleFacts}} @rows='ruled'>
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
            <KeyValue class='kv' @items={{this.detailFacts}} @rows='ruled'>
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
        /* the name keeps its line; the chips wrap below it before it does */
        .iso-id {
          flex: 1 1 16rem;
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
        .iso-mark {
          --position-mark-size: 2.75rem;
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
        this.args.model?.hiringManager ||
        this.args.model?.interviewPlan ||
        this.args.model?.approvalChain?.steps?.length,
      );
    }
    <template>
      <article class='position-embedded'>
        <header class='emb-head'>
          <PositionMark />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.title}}</h3>
            {{#if this.subline}}
              <p class='emb-sub'>{{this.subline}}</p>
            {{/if}}
          </div>
          <PositionChips class='emb-chips' @model={{@model}} />
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
            {{#each @fields.approvalChain.steps as |Step|}}
              <span class='rel'>Approver
                <Step.approver
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{/each}}
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
            justify-content: flex-end;
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
            flex-direction: column;
            align-items: flex-start;
            gap: var(--boxel-sp-xs);
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
        <PositionMark class='atom-mark' />
        <span class='position-atom-name'>{{@model.title}}</span>
        {{#if @model.status}}<Chip
            class='position-atom-chip'
            @tone={{this.statusTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{statusLabel @model.status}}</Chip>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .position-atom {
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
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-mark {
            --position-mark-size: 1.25rem;
            --position-mark-font-size: var(--boxel-font-size-2xs);
          }
          .position-atom-chip {
            flex: none;
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
    get kvFacts(): DescriptionsItem[] {
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

    <template>
      <article class='fit'>
        <header class='who'>
          {{! the record's type mark, not a person: a square, not an Avatar }}
          <span class='mark' aria-hidden='true'>Po</span>
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              <span class='chips chips-inline'>
                {{#if @model.status}}<Chip
                    @tone={{this.statusTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{statusLabel @model.status}}</Chip>{{/if}}
                {{#if @model.experienceLevel}}<Chip
                    class='chip-level'
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{sentenceCase @model.experienceLevel}}</Chip>{{/if}}
                {{#if @model.remoteEligible}}<Chip
                    class='chip-extra'
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >Remote</Chip>{{/if}}
              </span>
            </div>
            <p class='sub'>{{this.subline}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          {{#if @model.status}}<Chip
              @tone={{this.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{statusLabel @model.status}}</Chip>{{/if}}
          {{#if @model.experienceLevel}}<Chip
              class='chip-level'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{sentenceCase @model.experienceLevel}}</Chip>{{/if}}
          {{#if @model.remoteEligible}}<Chip
              class='chip-extra'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >Remote</Chip>{{/if}}
        </span>
        {{#if this.targetStartLabel}}
          <p class='fact'>Start by
            <strong>{{this.targetStartLabel}}</strong>{{#if this.postedShort}}
              · posted
              {{this.postedShort}}{{/if}}</p>
        {{/if}}
        <dl class='kv'>
          {{#each this.kvFacts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <ul class='rels'>
          {{#if @model.hiringManager}}
            <li><span class='k'>Hiring manager</span><@fields.hiringManager
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#if @model.interviewPlan}}
            <li><span class='k'>Interview plan</span><@fields.interviewPlan
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#each @fields.approvalChain.steps as |Step|}}
            <li><span class='k'>Approver</span><Step.approver
                @format='atom'
                @displayContainer={{false}}
              /></li>
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
            display: none;
            flex: none;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary-ink);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
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
          .kv,
          .rels .k {
            display: none;
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
            overflow: hidden;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the type mark shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: grid;
            }
          }
          /* the level and remote chips join the status from 250 wide */
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
              inline-size: 2.5rem;
              block-size: 2.5rem;
              font-size: var(--boxel-font-size-sm);
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
