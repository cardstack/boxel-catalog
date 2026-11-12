import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
  type BaseDef,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import NumberField from 'https://cardstack.com/base/number';
import enumField from 'https://cardstack.com/base/enum';
import { dotEnumField } from './dot-enum-field';
import BriefcaseIcon from '@cardstack/boxel-icons/briefcase';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  SheetLine,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';
import type { DescriptionsItem } from '@cardstack/pretui/components/descriptions';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

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

export const EmployeeStatusField = markDefinition(
  dotEnumField(
    {
      options: EMPLOYEE_STATUSES.map((status) => ({
        value: status,
        label: statusLabel(status),
      })),
      displayName: 'Employee Status',
    },
    EMPLOYEE_STATUS_HUES,
  ),
);

export const EmployeeEmploymentTypeField = markDefinition(
  enumField(StringField, {
    options: EMPLOYEE_EMPLOYMENT_TYPES.map((type) => ({
      value: type,
      label: type,
    })),
    displayName: 'Employment Type',
  }),
);

export const OnboardingStatusField = markDefinition(
  enumField(StringField, {
    options: ONBOARDING_STATUSES.map((status) => ({
      value: status,
      label: status,
    })),
    displayName: 'Onboarding Status',
  }),
);

// The status chip's tone, on the theme's tone axis: active work is success,
// a person still onboarding is warning (the org chart's amber pill), and an
// offboarded record is neutral.
export const EMPLOYEE_STATUS_TONES: Record<string, PretuiToneArg> = {
  onboarding: 'warning',
  active: 'success',
  offboarded: 'neutral',
};

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

  get summaryFacts(): DescriptionsItem[] {
    let m = this.args.model;
    return [
      {
        label: 'Tenure',
        value: [m?.tenure?.label || '—', this.sinceLabel]
          .filter(Boolean)
          .join(' · '),
      },
      {
        label: 'PTO left',
        value: [this.ptoLeftLabel, this.ptoAllowanceLabel]
          .filter(Boolean)
          .join(' '),
      },
      {
        label: 'Last review',
        value: [this.lastReviewValue, this.lastReviewHint]
          .filter(Boolean)
          .join(' · '),
      },
      { label: 'Salary', value: `${salaryShort(m)} base` },
    ];
  }

  get stripItems(): StripItem[] {
    let m = this.args.model;
    return [
      {
        label: 'Tenure',
        value: tenureShort(m) || null,
        hint: this.sinceLabel,
        tone: 'success',
      },
      {
        label: 'PTO left',
        value: this.ptoLeftLabel,
        hint: this.ptoAllowanceLabel,
        tone: 'info',
      },
      {
        label: 'Last review',
        value: this.lastReviewValue,
        hint: this.lastReviewHint,
        tone: 'success',
      },
      { label: 'Salary', value: salaryShort(m), hint: 'base', tone: 'neutral' },
    ];
  }

  get nextPto(): PtoRequest | undefined {
    return this.ptoItems[0];
  }

  get employmentKv() {
    return this.employmentFacts.map((f) => ({
      key: String(f.label),
      value: f.value as string,
    }));
  }
  get contactKv() {
    return this.contactFacts.map((f) => ({
      key: String(f.label),
      value: f.value as string,
    }));
  }
  get detailKv() {
    return this.detailFacts.map((f) => ({
      key: String(f.label),
      value: f.value as string,
    }));
  }
  linkedKv = [
    { key: 'Manager', value: '' },
    { key: 'Team', value: '' },
    { key: 'Review', value: '' },
  ];

  get team(): Team | undefined {
    return (this.teamQuery?.instances ?? [])[0] as Team | undefined;
  }

  <template>
    <IsoPage>
      <:head>
        <IsoHead @title={{@model.title}} @meta={{roleLine @model}}>
          <:mark><Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{36}}
              aria-hidden='true'
            /></:mark>
          <:aside>
            {{#if @model.status}}<@fields.status
                @format='atom'
                @displayContainer={{false}}
              />{{/if}}
            {{#if this.nextPto.startDate}}<span class='muted'>PTO
                {{formatDay this.nextPto.startDate}}</span>{{/if}}
          </:aside>
          <:stats><StatStrip @items={{this.stripItems}} /></:stats>
        </IsoHead>
      </:head>
      <:main>
        <Panel @title='Employment'><Kv @items={{this.employmentKv}} /></Panel>
        <Panel @title='Time off'>
          {{#each this.ptoItems as |request|}}
            <SheetLine>
              <span class='grow'>{{request.cardTitle}}</span>
              {{#if request.startDate}}<span class='mono'>{{formatDay
                    request.startDate
                  }}{{#if request.endDate}}
                    –
                    {{formatDay request.endDate}}{{/if}}</span>{{/if}}
              {{#if request.status}}<span
                  class='st'
                >{{request.status}}</span>{{/if}}
            </SheetLine>
          {{else}}
            <SheetLine><span class='muted'>No time-off requests.</span></SheetLine>
          {{/each}}
        </Panel>
        <Panel @title='Contact'><Kv @items={{this.contactKv}} /></Panel>
      </:main>
      <:aside>
        <Panel @title='Linked'>
          <Kv @items={{this.linkedKv}}>
            <:value as |item|>
              {{#if (eq item.key 'Manager')}}
                {{#if @model.manager}}
                  <@fields.manager @format='atom' @displayContainer={{false}} />
                {{else}}
                  <span class='muted'>— top of the org</span>
                {{/if}}
              {{else if (eq item.key 'Team')}}
                {{#let (cardComponent this.team) as |TeamAtom|}}
                  {{#if TeamAtom}}<TeamAtom
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}
                {{/let}}
              {{else if (eq item.key 'Review')}}
                {{#let (cardComponent this.latestReview) as |ReviewAtom|}}
                  {{#if ReviewAtom}}<ReviewAtom
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}
                {{/let}}
              {{/if}}
            </:value>
          </Kv>
        </Panel>
        <Panel @title='Details'>
          <Kv @items={{this.detailKv}}>
            <:value as |item|>{{#if (eq item.key 'Status')}}{{#if
                  @model.status
                }}<@fields.status
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else}}{{if
                  item.value
                  item.value
                  '—'
                }}{{/if}}</:value>
          </Kv>
        </Panel>
      </:aside>
    </IsoPage>
    <style scoped>
      .muted {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-2xs);
      }
      .grow {
        flex: 1 1 8rem;
        min-width: 0;
        font-weight: 700;
      }
      .mono {
        font-weight: 500;
        font-size: var(--boxel-font-size-2xs);
        font-family: var(--font-mono);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .st {
        font-weight: 600;
      }
    </style>
  </template>
}

// A linked card's own component, so it renders in its atom format.
function cardComponent(card: BaseDef | undefined) {
  return card
    ? (card.constructor as typeof BaseDef).getComponent(card)
    : undefined;
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

  // Extends the isolated class for its Team / Review / PTO live queries.
  static embedded = class Embedded extends EmployeeIsolated {
    get kv() {
      let m = this.args.model;
      let tenure = [m?.tenure?.label, startYear(m) && `since ${startYear(m)}`]
        .filter(Boolean)
        .join(' · ');
      return [
        {
          key: 'Start date',
          value: m?.startDate ? formatDay(m.startDate) : '—',
        },
        { key: 'Tenure', value: tenure || '—' },
        { key: 'Department', value: m?.department || '—' },
        { key: 'PTO allowance', value: daysLabel(m?.ptoAllowanceDays) },
        { key: 'Salary', value: formatMoney(m?.salary) ?? '—' },
        { key: 'Email', value: m?.email || '—' },
        { key: 'Manager', value: '' },
        { key: 'Team', value: '' },
        { key: 'Review', value: '' },
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{roleLine @model}}>
        <:mark><Avatar
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.kv}}>
            <:value as |item|>{{#if (eq item.key 'Manager')}}{{#if
                  @model.manager
                }}<@fields.manager
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else if (eq item.key 'Team')}}{{#let
                  (cardComponent this.team)
                  as |TeamAtom|
                }}{{#if TeamAtom}}<TeamAtom
                      @format='atom'
                      @displayContainer={{false}}
                    /><span
                      class='mono'
                    >{{this.team.members.length}}</span>{{else}}—{{/if}}{{/let}}{{else if
                (eq item.key 'Review')
              }}{{#let (cardComponent this.latestReview) as |ReviewAtom|}}{{#if
                    ReviewAtom
                  }}<ReviewAtom
                      @format='atom'
                      @displayContainer={{false}}
                    />{{#if this.latestReview.status}}<span
                        class='muted'
                      >{{this.latestReview.status}}</span>{{/if}}{{else}}—{{/if}}{{/let}}{{else}}{{item.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
      <style scoped>
        .mono {
          font: 0.6875rem var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .muted {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
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
            gap: 0.375rem;
            max-width: 100%;
            min-width: 0;
            block-size: 1.375rem;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.375rem;
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

  // Rows in priority order (kit fitted rule): who + state, role, next PTO,
  // tenure, manager, the stat strip, then the remaining facts and links.
  // RichFittedCard shows a row whole or not at all. Extends the isolated class for
  // its Team / Review / PTO live queries.
  static fitted = class Fitted extends EmployeeIsolated {
    get leadStat(): StripItem | undefined {
      return this.strip[0];
    }

    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        { label: 'Tenure', value: tenureShort(m) || null },
        { label: 'PTO left', value: daysLabel(m?.ptoBalance) },
        { label: 'Review', value: this.lastReviewValue },
      ];
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.title @model.title '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{roleLine @model}}</span></:subtitle>
        <:metric>{{#if this.leadStat}}<Metric
              @value={{this.leadStat.value}}
              @label={{this.leadStat.label}}
            />{{/if}}</:metric>
        <:details>

          <Detail @label='PTO'><span class='mono'>{{if
                this.nextPto.startDate
                (formatDay this.nextPto.startDate)
                '—'
              }}</span></Detail>
          <Detail @label='Tenure'><span class='mono'>{{if
                @model.tenure.label
                @model.tenure.label
                '—'
              }}{{#if (startYear @model)}}
                · since
                {{startYear @model}}{{/if}}</span></Detail>
          {{#if @model.manager}}
            <Detail @label='Manager'><@fields.manager
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}

          <Detail @label='Start date'><span class='mono'>{{if
                @model.startDate
                (formatDay @model.startDate)
                '—'
              }}</span></Detail>
          <Detail @label='Department'>{{if
              @model.department
              @model.department
              '—'
            }}</Detail>
          {{#let (cardComponent this.team) as |TeamAtom|}}{{#if TeamAtom}}
              <Detail @label='Team'><TeamAtom
                  @format='atom'
                  @displayContainer={{false}}
                /></Detail>
            {{/if}}{{/let}}
          {{#let (cardComponent this.latestReview) as |ReviewAtom|}}{{#if
              ReviewAtom
            }}
              <Detail @label='Review'><ReviewAtom
                  @format='atom'
                  @displayContainer={{false}}
                /></Detail>
            {{/if}}{{/let}}
          <Detail @label='PTO allowance'><span class='mono'>{{daysLabel
                @model.ptoAllowanceDays
              }}</span></Detail>
          <Detail @label='Salary'><span class='mono'>{{formatMoney
                @model.salary
              }}</span></Detail>
          <Detail @label='Email'><span
              class='mono'
            >{{@model.email}}</span></Detail>
          <Detail @label='Phone'><span
              class='mono'
            >{{@model.phone}}</span></Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font: 500 0.6875rem var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
