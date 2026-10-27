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
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '../../ui-component/components/avatar';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
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
    label: status,
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
// a person still onboarding is info, and an offboarded record is neutral.
export const EMPLOYEE_STATUS_TONES: Record<string, PretuiToneArg> = {
  onboarding: 'info',
  active: 'success',
  offboarded: 'neutral',
};

function statusTone(status?: string | null): PretuiToneArg {
  return (status && EMPLOYEE_STATUS_TONES[status]) || 'neutral';
}

function roleLine(m?: Partial<Employee>): string {
  let role = m?.role || 'Role not recorded';
  return m?.department ? `${role} · ${m.department}` : role;
}

function startYear(m?: Partial<Employee>): string | undefined {
  return m?.startDate ? String(new Date(m.startDate).getFullYear()) : undefined;
}

function daysLabel(n?: number | null): string {
  return n == null ? '—' : `${n} days`;
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
    { label: 'Status', value: m?.status || '—' },
  ];
}

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
      { label: 'Employment', value: m?.employmentType || '—' },
      { label: 'Onboarding', value: m?.onboardingStatus || '—' },
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

  linkedFacts: DescriptionsItem[] = [{ label: 'Manager' }];

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

  get salaryShort(): string {
    return formatMoney(this.args.model?.salary, { compact: true }) ?? '—';
  }

  get capacityLabel(): string | undefined {
    let h = this.args.model?.weeklyInterviewCapacityHours;
    return typeof h === 'number' ? `${h} h/week interview capacity` : undefined;
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
            <StatusChip
              @value={{@model.status}}
              @tone={{statusTone @model.status}}
            />
          {{/if}}
          {{#if @model.employmentType}}
            <StatusChip @value={{@model.employmentType}} @tone='neutral' />
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
            @label='Salary'
            @value={{this.salaryShort}}
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
          {{#if this.capacityLabel}}
            <Panel>
              <:header><h2 class='panel-h'>Interviewing</h2></:header>
              <:default>
                <p class='note'>{{this.capacityLabel}}. The Dashboard flags this
                  person once booked hours pass that ceiling.</p>
              </:default>
            </Panel>
          {{/if}}
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
                <StatusChip
                  @value={{@model.status}}
                  @tone={{statusTone @model.status}}
                />
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
          @size={{20}}
          aria-hidden='true'
        />
        <span class='name'>{{@model.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .employee-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
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

  static fitted = class Fitted extends Component<typeof this> {
    // Each fact is its own KeyValue row, so a row that doesn't fit wraps
    // out of sight whole instead of showing half.
    get factRows(): KeyValueItem[][] {
      return employeeFacts(this.args.model).map((f) => [
        { key: f.label, value: f.value ?? '—' },
      ]);
    }
    <template>
      <div class='fit'>
        <FitTile class='tile'>
          <:avatar>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{roleLine @model}}</:subtitle>
          <:status>
            {{#if @model.status}}
              <StatusChip
                @value={{@model.status}}
                @tone={{statusTone @model.status}}
              />
            {{/if}}
          </:status>
          <:fact>{{#if @model.tenure.label}}<strong
                class='strong'
              >{{@model.tenure.label}}</strong>{{#if (startYear @model)}}
                · since
                {{startYear @model}}{{/if}}{{/if}}</:fact>
        </FitTile>
        {{! Relations, then the key facts: shown from 170 tall, and the
            relation line on a 400-wide strip. }}
        <div class='more'>
          <p class='rel'><span class='k'>Manager</span><@fields.manager
              @format='atom'
            /></p>
          {{#each this.factRows as |row|}}
            <KeyValue class='kv' @items={{row}} />
          {{/each}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent, PretComposite;
        @layer PretComposite {
          .tile {
            flex: none;
            block-size: auto;
          }
        }
        @layer PretComponent {
          .fit {
            display: flex;
            flex-direction: column;
            block-size: 100%;
            overflow: hidden;
          }
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          /* a column that wraps: rows past the bottom move to a second
             column outside the card, whole */
          .more {
            display: none;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            row-gap: var(--boxel-sp-4xs);
            column-gap: var(--boxel-sp-sm);
            min-block-size: 0;
            padding: 0 var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
          }
          .rel,
          .kv {
            inline-size: 100%;
          }
          .rel {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            margin: 0;
            overflow: hidden;
            white-space: nowrap;
          }
          .k {
            flex: none;
            color: var(--muted-foreground);
          }
          @container fitted-card (height >= 170px) {
            .more {
              display: flex;
            }
          }
          @container fitted-card (105px <= height < 170px) and (width >= 400px) {
            .more {
              display: flex;
            }
          }
        }
      </style>
    </template>
  };
}
