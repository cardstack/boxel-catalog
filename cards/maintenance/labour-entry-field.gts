import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import ClockIcon from '@cardstack/boxel-icons/clock';

import { hoursBetween, roundHours, formatHours } from './utils/maintenance';
import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';

/**
 * Time one person spent on one job, and what it cost.
 *
 * Either a start/end pair (the Workbench timer writes these) or a typed
 * `hours`. `effectiveHours` prefers the explicit hours, else the interval —
 * open-ended while `endedAt` is empty (the timer is running). `cost` =
 * effectiveHours × rate. Generic: a work order today; a consulting
 * task, a support case or a lesson tomorrow.
 */
export class LabourEntryField extends FieldDef {
  static displayName = 'Labour Entry';
  static icon = ClockIcon;

  @field workerId = contains(StringField, {
    description: 'Card id of the Employee.',
  });
  @field workerName = contains(StringField);
  @field startedAt = contains(DateTimeField);
  @field endedAt = contains(DateTimeField);
  @field hours = contains(NumberField, {
    description: 'Typed hours — overrides the start/end interval when set.',
  });
  @field rate = contains(AmountWithCurrency, {
    description: 'Hourly rate applied to this entry.',
  });
  @field note = contains(StringField);

  @field effectiveHours = contains(NumberField, {
    computeVia: function (this: LabourEntryField) {
      if (this.hours != null) return this.hours;
      return roundHours(
        hoursBetween(this.startedAt, this.endedAt ?? undefined),
      );
    },
  });

  @field cost = contains(NumberField, {
    computeVia: function (this: LabourEntryField) {
      let h = this.effectiveHours;
      let r = this.rate?.amount;
      if (h == null || r == null) return undefined;
      return Math.round(h * r * 100) / 100;
    },
  });

  @field isRunning = contains(StringField, {
    computeVia: function (this: LabourEntryField) {
      return this.startedAt && !this.endedAt && this.hours == null
        ? 'running'
        : '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: LabourEntryField) {
      return `${this.workerName ?? 'Someone'} · ${formatHours(this.effectiveHours)}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hours() {
      return formatHours(this.args.model.effectiveHours);
    }
    get cost() {
      let m = this.args.model;
      return m.cost != null
        ? formatMoneyDisplay(m.cost, m.rate?.currency?.code)
        : undefined;
    }
    <template>
      <div class='le'>
        <ClockIcon class='le-icon' />
        <span class='le-who'>{{if
            @model.workerName
            @model.workerName
            'Unassigned'
          }}</span>
        <span
          class='le-hours {{if @model.isRunning "le-hours--running"}}'
        >{{this.hours}}{{#if @model.isRunning}}
            · running{{/if}}</span>
        {{#if this.cost}}<span class='le-cost'>{{this.cost}}</span>{{/if}}
        {{#if @model.note}}<span class='le-note'>{{@model.note}}</span>{{/if}}
      </div>
      <style scoped>
        .le {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .le-icon {
          width: 0.9rem;
          height: 0.9rem;
          color: var(--muted-foreground);
        }
        .le-who {
          font-weight: 500;
        }
        .le-hours {
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .le-hours--running {
          color: var(--foreground);
          font-weight: 600;
        }
        .le-cost {
          margin-left: auto;
          font-variant-numeric: tabular-nums;
        }
        .le-note {
          flex-basis: 100%;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='le-atom'>{{@model.title}}</span>
      <style scoped>
        .le-atom {
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export default LabourEntryField;
