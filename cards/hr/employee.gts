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
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { tracked } from '@glimmer/tracking';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EntityDisplay } from '@cardstack/pretui/components/entity-display';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { DurationField } from './duration-field';
import {
  StatePill,
  stateColor,
  stateColorOf,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { normalizedDuration } from './duration-field';
import { daysBetween } from './utils';
import { AVATAR_HUE, FactList, QUIET_AVATAR_HUE, hueOf } from './hr-ui';

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

// Hoisted out of `static isolated = class {…}`: decorators are not valid in a
// class expression under the catalog type-check.
class EmployeeIsolated extends Component<typeof Employee> {
  @tracked selectedTab: 'overview' | 'team' = 'overview';

  setTab = (tab: 'overview' | 'team') => {
    this.selectedTab = tab;
  };

  get statusHue() {
    return hueOf(EMPLOYEE_STATUS_HUES, this.args.model?.status);
  }

  get tenureInRoleLabel(): string | undefined {
    let label = this.args.model?.tenure?.label;
    return label ? `${label} in role` : undefined;
  }

  // The Employment facts as Pret UI `KeyValue` rows; the two date rows render
  // their fields through the `<:value>` block.
  get employmentFacts(): KeyValueItem[] {
    let m = this.args.model;
    let rows: KeyValueItem[] = [
      { key: 'Role', value: m?.role || '—' },
      { key: 'Department', value: m?.department || '—' },
      { key: 'Started', value: m?.startDate ? 'startDate' : '—' },
      { key: 'Tenure', value: m?.tenure?.label || '—' },
      { key: 'Employment', value: m?.employmentType || '—' },
      { key: 'PTO balance', value: this.ptoBalanceLabel },
      { key: 'Onboarding', value: m?.onboardingStatus || '—' },
    ];
    if (m?.status === 'offboarded') {
      rows.push({
        key: 'Left on',
        value: m?.terminationDate ? 'terminationDate' : '—',
      });
    }
    return rows;
  }

  get ptoBalanceLabel(): string {
    let n = this.args.model?.ptoBalance;
    if (n == null) {
      return '—';
    }
    return n === 0 ? '0 days · exhausted' : `${n} days`;
  }

  get capacityLabel(): string | undefined {
    let h = this.args.model?.weeklyInterviewCapacityHours;
    return typeof h === 'number' ? `${h} h/week interview capacity` : undefined;
  }

  <template>
    <article class='employee-isolated'>
      <header class='hero'>
        <Avatar
          @name={{if @model.title @model.title '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{52}}
          aria-hidden='true'
        />
        <div class='hero-text'>
          <h1>{{@model.title}}</h1>
          <p class='byline'>
            {{if @model.role @model.role 'Role not recorded'}}
            {{#if @model.department}}
              <span class='sep-dot'>&middot;</span>
              {{@model.department}}
            {{/if}}
          </p>
          <div class='pill-row'>
            <StatePill
              @label={{@model.status}}
              @hue={{this.statusHue}}
              @dot={{true}}
            />
            <StatePill @label={{@model.employmentType}} />
            <StatePill @label={{this.tenureInRoleLabel}} />
          </div>
        </div>
        {{#if @model.tenure.label}}
          <div class='hero-money'>
            <Stat
              class='money'
              @label='Tenure'
              @value={{@model.tenure.label}}
              @roll={{false}}
            />
          </div>
        {{/if}}
      </header>

      <div class='body'>
        <div class='main'>
          <h2 class='panel-title'>Employment</h2>
          <FactList @items={{this.employmentFacts}}>
            <:value as |row|>
              {{#if (eq row.value 'startDate')}}
                <@fields.startDate />
              {{else if (eq row.value 'terminationDate')}}
                <@fields.terminationDate />
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </FactList>
        </div>

        <aside class='side'>
          <h2 class='panel-title'>Org position</h2>
          <dl class='stacked'>
            <dt>Reports to</dt>
            <dd>{{#if @model.manager}}<@fields.manager
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}&mdash; top of the org{{/if}}</dd>
            <dt>Status</dt>
            <dd>{{if @model.status @model.status '—'}}</dd>
          </dl>

          {{#if this.capacityLabel}}
            <h2 class='panel-title spaced'>Interviewing</h2>
            <p class='side-note'>{{this.capacityLabel}}. The Dashboard flags
              this person once booked hours pass that ceiling.</p>
          {{/if}}
        </aside>
      </div>
    </article>
    <style scoped>
      .employee-isolated {
        container-type: inline-size;
        container-name: iso;
        height: 100%;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
      }
      .side-note {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.6;
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
        --text-stat: 1.5rem;
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
    get statusHue() {
      return hueOf(EMPLOYEE_STATUS_HUES, this.args.model?.status);
    }
    get roleLine() {
      let m = this.args.model;
      let role = m?.role || '—';
      return m?.department ? `${role} · ${m.department}` : role;
    }
    <template>
      <div class='employee-embedded'>
        <EntityDisplay
          class='entity'
          @title={{if @model.name @model.name 'Unnamed'}}
          @subtitle={{this.roleLine}}
          @center={{true}}
        >
          <:visual>
            <Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{QUIET_AVATAR_HUE}}
              @size={{30}}
              aria-hidden='true'
            />
          </:visual>
        </EntityDisplay>
        <StatePill
          class='ee-status'
          @label={{@model.status}}
          @hue={{this.statusHue}}
        />
      </div>
      <style scoped>
        .employee-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        /* EntityDisplay's name and secondary line keep the row's sizes. */
        .entity {
          flex: 1;
          --pretui-entity-visual-size: 1.875rem;
          --text-ui-md: 0.8125rem;
          --text-ui-sm: 0.6875rem;
          --space-3: 0.625rem;
        }
        .ee-status {
          flex-shrink: 0;
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='employee-atom'>
        <BriefcaseIcon class='employee-atom-icon' />
        <span class='employee-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .employee-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .employee-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .employee-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get statusHue() {
      return hueOf(EMPLOYEE_STATUS_HUES, this.args.model?.status);
    }

    // The status ring sits on a wrapper: Avatar writes its own inline style,
    // and a caller's `style` would replace it.
    get avatarRingStyle() {
      let ring = stateColorOf(EMPLOYEE_STATUS_COLORS, this.args.model?.status);
      return htmlSafe(`--status-ring: ${ring.ring}`);
    }

    get startYear(): string | undefined {
      let date = this.args.model?.startDate;
      if (!date) {
        return undefined;
      }
      return new Date(date).getFullYear().toString();
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='avatar-ring' style={{this.avatarRingStyle}}>
            <Avatar
              @name={{if @model.title @model.title '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{26}}
              aria-hidden='true'
            />
          </span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.role}}
              <span class='fit-eb'>{{@model.role}}{{#if @model.department}}
                  &middot;
                  {{@model.department}}{{/if}}</span>
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
          {{#if @model.tenure.label}}
            <span class='money'>{{@model.tenure.label}}</span>
          {{/if}}
          {{#if this.startYear}}
            <span class='fit-sub'>since
              {{this.startYear}}{{#if @model.employmentType}}
                &middot;
                {{@model.employmentType}}{{/if}}</span>
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if @model.managerName}}
            <div><dt>Reports to</dt><dd>{{@model.managerName}}</dd></div>
          {{/if}}
          {{#if @model.department}}
            <div><dt>Dept</dt><dd>{{@model.department}}</dd></div>
          {{/if}}
          {{#if @model.onboardingStatus}}
            <div><dt>Onboard</dt><dd>{{@model.onboardingStatus}}</dd></div>
          {{/if}}
          {{#if @model.employmentType}}
            <div><dt>Type</dt><dd>{{@model.employmentType}}</dd></div>
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
        .avatar-ring {
          flex: none;
          display: inline-flex;
          border-radius: 50%;
          box-shadow:
            0 0 0 0.125rem var(--background),
            0 0 0 0.1875rem var(--status-ring);
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
          /* The photo avatar's ring (box-shadow, painted outside its own
             box) was being clipped along its top edge by the inherited
             `.fit > * { overflow: hidden }` rule — the ring bled above
             this row's flex-start-aligned top edge with no padding to
             absorb it, reading as a cropped circle. */
          overflow: visible;
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
