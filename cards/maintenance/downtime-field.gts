import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import PowerOffIcon from '@cardstack/boxel-icons/power-off';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import { hoursBetween, roundHours, formatHours } from './utils/maintenance';
import { absoluteStamp } from './utils/relative-time';

/**
 * An interval something was unavailable — planned (a PM window) or unplanned
 * (a failure). Open-ended while `endedAt` is empty; `hours` keeps counting.
 * Availability = 1 − Σ downtime ÷ period, computed in utils/maintenance so
 * the asset, the Home hero and the reliability report agree.
 *
 * Generic: a compressor, a server, a meeting room, a vehicle.
 */
export class DowntimeField extends FieldDef {
  static displayName = 'Downtime';
  static icon = PowerOffIcon;

  @field startedAt = contains(DateTimeField);
  @field endedAt = contains(DateTimeField);
  @field planned = contains(BooleanField, {
    description: 'true for maintenance windows; false for failures.',
  });
  @field reason = contains(StringField);

  @field hours = contains(NumberField, {
    computeVia: function (this: DowntimeField) {
      return roundHours(
        hoursBetween(this.startedAt, this.endedAt ?? undefined),
      );
    },
  });

  @field isOpen = contains(BooleanField, {
    computeVia: function (this: DowntimeField) {
      return !!this.startedAt && !this.endedAt;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: DowntimeField) {
      if (!this.startedAt) return 'No downtime';
      return `${this.planned ? 'Planned' : 'Unplanned'} · ${formatHours(this.hours)}${this.isOpen ? ' · ongoing' : ''}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      let m = this.args.model;
      if (!m.startedAt) return 'slate';
      return m.planned ? 'slate' : m.isOpen ? 'red' : 'orange';
    }
    get from() {
      return absoluteStamp(this.args.model.startedAt ?? undefined);
    }
    get to() {
      return absoluteStamp(this.args.model.endedAt ?? undefined);
    }
    <template>
      <div class='dt'>
        <StatePill
          @label={{if
            @model.startedAt
            (if @model.planned 'planned' 'unplanned')
            'none'
          }}
          @hue={{this.hue}}
          @dot={{@model.isOpen}}
        />
        {{#if @model.startedAt}}
          <span class='dt-hours'>{{@model.title}}</span>
          <span class='dt-meta'>{{this.from}}{{#if this.to}}
              →
              {{this.to}}{{/if}}</span>
          {{#if @model.reason}}<span class='dt-meta'>·
              {{@model.reason}}</span>{{/if}}
        {{/if}}
      </div>
      <style scoped>
        .dt {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .dt-hours {
          font-variant-numeric: tabular-nums;
          font-weight: 500;
        }
        .dt-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='dt-atom'>{{@model.title}}</span>
      <style scoped>
        .dt-atom {
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export default DowntimeField;
