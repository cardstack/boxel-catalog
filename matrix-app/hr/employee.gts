import {
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import NumberField from 'https://cardstack.com/base/number';
import enumField from 'https://cardstack.com/base/enum';
import BriefcaseIcon from '@cardstack/boxel-icons/briefcase';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';

import { PersonBase } from '../people/person-base';
import { DurationField } from './duration-field';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { normalizedDuration } from './duration-field';
import { daysBetween, formatMoney } from './utils';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { codeRef, realmURL } from '@cardstack/runtime-common';
import type { PtoRequest } from './pto-request';
import type { PerformanceReview } from './performance-review';
import type { Team } from './team';

export const EMPLOYEE_STATUSES = ['onboarding', 'active', 'offboarded'];

// Mirrors Position's EMPLOYMENT_TYPES — kept as a separate local copy rather
// than importing from position.gts, since position.gts imports Employee and
// that would create a circular module dependency.
export const EMPLOYEE_EMPLOYMENT_TYPES = [
  'full-time',
  'part-time',
  'contract',
  'internship',
];

export const ONBOARDING_STATUSES = ['not-started', 'in-progress', 'complete'];

// Colocated with Employee — the hue map colours the status pill, and
// `EMPLOYEE_STATUS_COLORS` below gives the avatar's status ring the same hue.
// Harmonized with the Ledger identity: onboarding = brass (the "just signed"
// seal color), active = forest green (the primary, "permanent record" color),
// offboarded = stone (a deliberate muted color, not a blank fallthrough).
export const EMPLOYEE_STATUS_HUES: Record<string, Hue> = {
  onboarding: 'orange',
  active: 'green',
  offboarded: 'amber',
};

export const EMPLOYEE_STATUS_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(EMPLOYEE_STATUS_HUES).map(([k, hue]) => [
      k,
      stateColor(hue),
    ]),
  );

export const EmployeeStatusField = enumField(StringField, {
  options: EMPLOYEE_STATUSES.map((status) => ({
    value: status,
    label: statusLabel(status),
  })),
  displayName: 'Employee Status',
});

export const EmployeeEmploymentTypeField = enumField(StringField, {
  options: EMPLOYEE_EMPLOYMENT_TYPES.map((type) => ({
    value: type,
    label: type,
  })),
  displayName: 'Employment Type',
});

export const OnboardingStatusField = enumField(StringField, {
  options: ONBOARDING_STATUSES.map((status) => ({
    value: status,
    label: status,
  })),
  displayName: 'Onboarding Status',
});

// The status chip's tone, on the theme's tone axis: active work is success,
// a person still onboarding is warning (the org chart's amber pill), and an
// offboarded record is neutral.
export const EMPLOYEE_STATUS_TONES: Record<string, PretuiToneArg> = {
  onboarding: 'warning',
  active: 'success',
  offboarded: 'neutral',
};

function statusTone(status?: string | null): PretuiToneArg {
  return (status && EMPLOYEE_STATUS_TONES[status]) || 'neutral';
}

function statusLabel(status?: string | null): string {
  return status ? status.charAt(0).toUpperCase() + status.slice(1) : '';
}

function roleText(m?: Partial<Employee>): string {
  return m?.role || 'Role not recorded';
}

function roleLine(m?: Partial<Employee>): string {
  let role = roleText(m);
  return m?.department ? `${role} · ${m.department}` : role;
}

const TENURE_SHORT: Record<string, string> = {
  years: 'yrs',
  months: 'mos',
  weeks: 'wks',
  days: 'days',
};

function tenureShort(m?: Partial<Employee>): string {
  let t = m?.tenure;
  return t?.value != null
    ? `${t.value} ${TENURE_SHORT[t.unit ?? ''] ?? t.unit}`
    : '';
}

// The directory tile's one line: department · employment type · tenure.
function metaLine(m?: Partial<Employee>): string {
  return [m?.department, m?.employmentType, tenureShort(m)]
    .filter(Boolean)
    .join(' · ');
}

function startYear(m?: Partial<Employee>): string | undefined {
  return m?.startDate ? String(new Date(m.startDate).getFullYear()) : undefined;
}

function daysLabel(n?: number | null): string {
  return n == null ? '—' : `${n} days`;
}

function salaryShort(m?: Partial<Employee>): string {
  return formatMoney(m?.salary, { compact: true }) ?? '—';
}

// The facts every format draws from, in the mockup's order; isolated shows
// them all, embedded the first six.
function employeeFacts(m?: Partial<Employee>): DescriptionsItem[] {
  return [
    { label: 'Start date', value: m?.startDate ? formatDay(m.startDate) : '—' },
    { label: 'Tenure', value: m?.tenure?.label || '—' },
    { label: 'Department', value: m?.department || '—' },
    { label: 'PTO allowance', value: daysLabel(m?.ptoAllowanceDays) },
    { label: 'Salary', value: formatMoney(m?.salary) ?? '—' },
    { label: 'Email', value: m?.email || '—' },
    { label: 'Phone', value: m?.phone || '—' },
    { label: 'Status', value: statusLabel(m?.status) || '—' },
  ];
}

// Related cards are read by live query rather than stored on Employee, the same
// way the balance math reads PtoRequest. The refs are strings, so this module
// does not import the related classes at runtime (they import Employee back).
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const employeeIsoHere: string = import.meta.url;
const ptoRequestRef = codeRef(employeeIsoHere, './pto-request', 'PtoRequest');
const reviewRef = codeRef(
  employeeIsoHere,
  './performance-review',
  'PerformanceReview',
);
const teamRef = codeRef(employeeIsoHere, './team', 'Team');

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class EmployeeIsolated extends Component<typeof Employee> {
  get contactFacts(): DescriptionsItem[] {
    let m = this.args.model;
    return [
      { label: 'Email', value: m?.email || '—' },
      { label: 'Phone', value: m?.phone || '—' },
    ];
  }

  get employmentFacts(): DescriptionsItem[] {
    let m = this.args.model;
    let rows: DescriptionsItem[] = [
      { label: 'Role', value: m?.role || '—' },
      { label: 'Department', value: m?.department || '—' },
      {
        label: 'Start date',
        value: m?.startDate ? formatDay(m.startDate) : '—',
      },
      { label: 'Tenure', value: m?.tenure?.label || '—' },
      { label: 'Salary', value: formatMoney(m?.salary) ?? '—' },
      { label: 'PTO allowance', value: daysLabel(m?.ptoAllowanceDays) },
    ];
    if (m?.status === 'offboarded') {
      rows.push({
        label: 'Left on',
        value: m?.terminationDate ? formatDay(m.terminationDate) : '—',
      });
    }
    return rows;
  }

  get detailFacts(): DescriptionsItem[] {
    return employeeFacts(this.args.model);
  }

  linkedFacts: DescriptionsItem[] = [
    { label: 'Manager' },
    { label: 'Team' },
    { label: 'Review' },
  ];

  ptoQuery = this.args.context?.getCards(
    this,
    () => ({
      filter: {
        on: ptoRequestRef,
        eq: { 'employee.id': this.args.model?.id ?? '' },
      },
    }),
    () => this.realms,
    { isLive: true },
  );

  reviewQuery = this.args.context?.getCards(
    this,
    () => ({
      filter: {
        on: reviewRef,
        eq: { 'employee.id': this.args.model?.id ?? '' },
      },
    }),
    () => this.realms,
    { isLive: true },
  );

  teamQuery = this.args.context?.getCards(
    this,
    () => ({
      filter: { on: teamRef, eq: { 'members.id': this.args.model?.id ?? '' } },
    }),
    () => this.realms,
    { isLive: true },
  );

  get realms(): string[] {
    let url = this.args.model?.[realmURL]?.href;
    return url ? [url] : [];
  }

  get ptoItems(): PtoRequest[] {
    return (this.ptoQuery?.instances ?? []) as PtoRequest[];
  }

  get latestReview(): PerformanceReview | undefined {
    return (this.reviewQuery?.instances ?? [])[0] as
      | PerformanceReview
      | undefined;
  }

  get lastReviewValue(): string {
    return this.latestReview?.scoreLabel || '—';
  }

  get lastReviewHint(): string | undefined {
    return this.latestReview?.cycleName || undefined;
  }

  get reviewLabel(): string {
    return this.latestReview?.cardTitle || '—';
  }

  get teamName(): string {
    let team = (this.teamQuery?.instances ?? [])[0] as Team | undefined;
    return team?.name || '—';
  }

  get sinceLabel(): string | undefined {
    let d = this.args.model?.startDate;
    return d ? `since ${formatDay(d)}` : undefined;
  }

  get ptoLeftLabel(): string {
    return daysLabel(this.args.model?.ptoBalance);
  }

  get ptoAllowanceLabel(): string | undefined {
    let n = this.args.model?.ptoAllowanceDays;
    return n == null ? undefined : `of ${n} allowance`;
  }

  <template>
    <article class='employee-isolated'>
      <header class='iso-head'>
        <Avatar
          @name={{if @model.title @model.title '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{48}}
          aria-hidden='true'
        />
        <div class='iso-id'>
          <h1>{{@model.title}}</h1>
          <p class='iso-sub'>{{roleLine @model}}</p>
        </div>
        <div class='chips'>
          {{#if @model.status}}
            <Chip
              @tone={{statusTone @model.status}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{statusLabel @model.status}}</Chip>
          {{/if}}
          {{#if @model.employmentType}}
            <Chip
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{@model.employmentType}}</Chip>
          {{/if}}
        </div>
      </header>

      <div class='stat-row'>
        <div class='stat-tile'><Stat
            @label='Tenure'
            @value={{if @model.tenure.label @model.tenure.label '—'}}
            @hint={{this.sinceLabel}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='PTO left'
            @value={{this.ptoLeftLabel}}
            @hint={{this.ptoAllowanceLabel}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Last review'
            @value={{this.lastReviewValue}}
            @hint={{this.lastReviewHint}}
            @roll={{false}}
          /></div>
        <div class='stat-tile'><Stat
            @label='Salary'
            @value={{salaryShort @model}}
            @hint='base'
            @roll={{false}}
          /></div>
      </div>

      <div class='iso-body'>
        <div class='iso-col'>
          <Panel>
            <:header><h2 class='panel-h'>Contact</h2></:header>
            <:default>
              <Descriptions
                @items={{this.contactFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>
          <Panel>
            <:header><h2 class='panel-h'>Employment</h2></:header>
            <:default>
              <Descriptions
                @items={{this.employmentFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>
          <Panel>
            <:header><h2 class='panel-h'>Time off</h2></:header>
            <:default>
              {{#if this.ptoItems.length}}
                <ul class='time-off'>
                  {{#each this.ptoItems as |request|}}
                    <li>
                      <span class='t'>{{request.cardTitle}}</span>
                      {{#if request.status}}
                        <StatusChip @value={{request.status}} @tone='neutral' />
                      {{/if}}
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='note'>No time-off requests.</p>
              {{/if}}
            </:default>
          </Panel>
        </div>

        <div class='iso-col'>
          <Panel>
            <:header><h2 class='panel-h'>Linked</h2></:header>
            <:default>
              <Descriptions
                @items={{this.linkedFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|>
                  {{#if (eq item.label 'Team')}}
                    <span class='v'>{{this.teamName}}</span>
                  {{/if}}
                  {{#if (eq item.label 'Review')}}
                    <span class='v'>{{this.reviewLabel}}</span>
                  {{/if}}
                  {{#if (eq item.label 'Manager')}}
                    {{#if @model.manager}}
                      <@fields.manager
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else}}
                      <span class='v'>— top of the org</span>
                    {{/if}}
                  {{/if}}
                </:value>
              </Descriptions>
            </:default>
          </Panel>
          <Panel>
            <:header><h2 class='panel-h'>Details</h2></:header>
            <:default>
              <Descriptions
                @items={{this.detailFacts}}
                @columns={{1}}
                @size='xl'
              >
                <:value as |item|><span class='v'>{{item.value}}</span></:value>
              </Descriptions>
            </:default>
          </Panel>
        </div>
      </div>
    </article>
    <style scoped>
      @layer PretComponent {
        .employee-isolated {
          container: employee-iso / inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
          background: var(--canvas);
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
        .v {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          overflow-wrap: anywhere;
        }
        .note {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        @container employee-iso (width < 45rem) {
          .iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      }
    </style>
  </template>
}

export class Employee extends PersonBase {
  static displayName = 'Employee';
  static icon = BriefcaseIcon;

  @field role = contains(StringField);
  @field department = contains(StringField);
  @field startDate = contains(DateField);
  @field status = contains(EmployeeStatusField);
  @field employmentType = contains(EmployeeEmploymentTypeField);
  @field terminationDate = contains(DateField);
  @field ptoBalance = contains(NumberField, {
    description: 'Remaining PTO balance, in days',
  });
  @field ptoAllowanceDays = contains(NumberField, {
    description:
      'Annual PTO allowance, in days/year. The balance MATH (allowance minus approved PtoRequest days) happens app-side via a live query over PtoRequest cards — deliberately NOT a linksToMany here, so requests never have to be manually attached.',
  });
  @field onboardingStatus = contains(OnboardingStatusField);
  @field salary = contains(NumberField);
  @field manager = linksTo(() => Employee);
  // Optional free-text credentials/subjects, for consumers that staff teaching
  // or mentoring from the same employee records. Absent means "unspecified",
  // so no instance needs migrating.
  @field teachingQualifications = containsMany(StringField, {
    description: 'Subjects or credentials this person is qualified to teach',
  });
  @field weeklyInterviewCapacityHours = contains(NumberField, {
    description:
      'Hours of interviewing this person can take per week before the Dashboard flags them as overloaded',
  });

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field managerName = contains(StringField, {
    computeVia: function (this: Employee) {
      return this.manager?.name ?? '';
    },
  });

  @field tenure = contains(DurationField, {
    computeVia: function (this: Employee) {
      let days = daysBetween(this.startDate);
      // Normalize the unit by magnitude: a multi-year tenure reads as years,
      // not as a four-digit day count.
      let norm = normalizedDuration(days);
      if (!norm) {
        return undefined;
      }
      return new DurationField({ value: norm.value, unit: norm.unit });
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Employee) {
      return this.name?.trim() || 'Unnamed Employee';
    },
  });

  static isolated = EmployeeIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    get facts(): DescriptionsItem[] {
      return employeeFacts(this.args.model).slice(0, 6);
    }
    <template>
      <div class='employee-embedded'>
        <article class='emb'>
          <header class='emb-head'>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{40}}
              aria-hidden='true'
            />
            <div class='emb-id'>
              <h3 class='emb-title'>{{@model.title}}</h3>
              <p class='emb-sub'>{{roleLine @model}}</p>
            </div>
            {{#if @model.status}}
              <div class='chips'>
                <Chip
                  @tone={{statusTone @model.status}}
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{statusLabel @model.status}}</Chip>
              </div>
            {{/if}}
          </header>
          {{#if @model.tenure.label}}
            <p class='emb-fact'><strong>{{@model.tenure.label}}</strong>{{#if
                (startYear @model)
              }}
                · since
                {{startYear @model}}{{/if}}</p>
          {{/if}}
          <Descriptions
            class='emb-kv'
            @items={{this.facts}}
            @layout='vertical'
            @columns={{3}}
          >
            <:value as |item|><span class='v'>{{item.value}}</span></:value>
          </Descriptions>
          {{#if @model.manager}}
            <p class='emb-rels'>Manager
              <@fields.manager @format='atom' @displayContainer={{false}} /></p>
          {{/if}}
        </article>
      </div>
      <style scoped>
        @layer PretComponent {
          .employee-embedded {
            container-type: inline-size;
          }
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
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
            gap: var(--boxel-sp-xs);
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
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
      <span class='employee-atom'>
        <Avatar
          @name={{if @model.title @model.title '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          aria-hidden='true'
        />
        <span class='name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .employee-atom {
            /* knob: a table can show a larger avatar */
            --pretui-avatar-size: var(--employee-atom-avatar-size, 1.25rem);
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            block-size: 1.5rem;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            white-space: nowrap;
            color: var(--foreground);
          }
          .name {
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };

  // Rows in priority order — who, state, fact, relations, then extra facts
  // where height allows (ui-component/FITTED-RULE.md). Every row is always
  // rendered; container queries pick which ones a size shows.
  static fitted = class Fitted extends Component<typeof this> {
    get facts(): DescriptionsItem[] {
      return employeeFacts(this.args.model);
    }
    <template>
      <article class='fit'>
        <header class='who'>
          <Avatar
            class='av'
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            aria-hidden='true'
          />
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              {{#if @model.status}}
                <span class='chips chips-inline'><Chip
                    @tone={{statusTone @model.status}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{statusLabel @model.status}}</Chip></span>
              {{/if}}
            </div>
            <p class='sub'>{{roleText @model}}{{#if @model.department}}<span
                  class='sub-dept'
                > · {{@model.department}}</span>{{/if}}</p>
          </div>
        </header>
        <p class='meta'>{{metaLine @model}}</p>
        {{#if @model.status}}
          <div class='chips chips-row'><Chip
              @tone={{statusTone @model.status}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{statusLabel @model.status}}</Chip></div>
        {{/if}}
        {{#if @model.tenure.label}}
          <p class='fact'><strong>{{@model.tenure.label}}</strong>{{#if
              (startYear @model)
            }}
              · since
              {{startYear @model}}{{/if}}</p>
        {{/if}}
        <div class='stats'>
          <div><span class='k'>Tenure</span><span class='v'>{{or
                (tenureShort @model)
                '—'
              }}</span></div>
          <div><span class='k'>PTO left</span><span class='v'>{{daysLabel
                @model.ptoBalance
              }}</span></div>
          <div><span class='k'>Salary</span><span class='v'>{{salaryShort
                @model
              }}</span></div>
        </div>
        <dl class='kv'>
          {{#each this.facts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.manager}}
          <ul class='rels'>
            <li><span class='k'>Manager</span><@fields.manager
                @format='atom'
                @displayContainer={{false}}
              /></li>
          </ul>
        {{/if}}
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
          .av {
            --pretui-avatar-size: 2rem;
            display: none;
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
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .title,
          .sub,
          .meta,
          .fact,
          .kv dd {
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .sub {
            font-size: var(--boxel-font-size-xs);
          }
          .sub,
          .meta,
          .fact,
          .k,
          .kv dt {
            color: var(--muted-foreground);
          }
          .meta,
          .fact,
          .kv,
          .rels,
          .stats .k {
            font-size: var(--boxel-font-size-xs);
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
          .meta,
          .stats,
          .kv,
          .rels .k {
            display: none;
          }
          .chips-inline {
            flex: 0 1 auto;
          }
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
          }
          .stats > div {
            display: flex;
            flex-direction: column;
            min-inline-size: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .stats .v {
            font-size: var(--boxel-font-size);
            font-weight: 600;
            color: var(--primary-ink);
            font-variant-numeric: tabular-nums;
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
          .rels {
            display: flex;
            flex-direction: column;
            gap: var(--_fit-gap-tight);
            padding: 0;
            list-style: none;
          }
          .rels li {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            overflow: hidden;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the avatar shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .av {
              display: inline-flex;
            }
          }
          /* relations name their link from 250 wide */
          @container fitted-card (width >= 250px) {
            .rels .k {
              display: inline;
            }
          }
          /* 150 wide: the fact is plain text */
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

          /* under 170 tall: compact type and tight rows */
          @container fitted-card (height < 170px) {
            .fit {
              gap: var(--_fit-gap-tight);
              padding: var(--_fit-gap) var(--boxel-sp-sm);
            }
            .sub {
              font-size: var(--boxel-font-size-xs);
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
              overflow: hidden;
            }
            .rels .k {
              display: none;
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
          @container fitted-card (height < 65px) {
            .sub {
              display: none;
            }
          }

          /* 250 tall: roomier padding and a larger avatar; under 250 wide
             the avatar stacks above the name */
          @container fitted-card (height >= 250px) {
            .fit {
              padding: var(--boxel-sp);
            }
            .av {
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
          /* 275 tall and 250 wide: the remaining facts fill the space left */
          @container fitted-card (height >= 275px) and (width >= 250px) {
            .kv {
              display: grid;
            }
          }
          /* 400 wide under 400 tall: facts in two columns */
          @container fitted-card (height >= 275px) and (height < 400px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
          }
          /* 400 × 400 and up: the three headline numbers */
          @container fitted-card (height >= 400px) and (width >= 400px) {
            .stats {
              display: grid;
            }
          }

          /* The directory tile (151 – 249 wide, 105 – 169 tall): avatar
             beside a name whose role may take two lines, then department ·
             type · tenure, then state. */
          @container fitted-card (150px < width < 250px) and (105px <= height < 170px) {
            .fit {
              gap: var(--_fit-gap-tight);
              padding: var(--boxel-sp);
            }
            .av {
              --pretui-avatar-size: 3rem;
              display: inline-flex;
            }
            .title {
              min-inline-size: 0;
              font-size: var(--boxel-font-size-sm);
            }
            .sub {
              display: -webkit-box;
              -webkit-box-orient: vertical;
              -webkit-line-clamp: 2;
              white-space: normal;
            }
            .sub-dept,
            .fact {
              display: none;
            }
            .meta {
              display: block;
            }
          }
        }
      </style>
    </template>
  };
}
