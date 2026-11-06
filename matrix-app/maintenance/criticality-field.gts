import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';
import { Dot, toneOfHue } from './utils/parts';

import {
  CriticalityLevelField,
  criticalityLevel,
} from './maintenance-vocabulary';

/**
 * How much it hurts when this thing fails — low / medium / high / critical.
 *
 * Criticality is a property of the SUBJECT (an asset, a server, a supplier),
 * distinct from Priority, which is the urgency of one JOB. The two meet in
 * Raise Work Order: a critical asset's corrective work defaults to P1, and
 * the user may override. Each level carries a rank (for sorting), a hue and a
 * response target in hours, so the register badge, the Home ranking and the
 * command never disagree.
 *
 * Generic: a Vehicle, a Meeting Room or a Vendor can carry it unchanged.
 */
export class CriticalityField extends FieldDef {
  static displayName = 'Criticality';
  static icon = AlertTriangleIcon;

  @field level = contains(CriticalityLevelField);

  @field rank = contains(NumberField, {
    computeVia: function (this: CriticalityField) {
      return criticalityLevel(this.level)?.rank ?? 0;
    },
  });

  @field responseTargetHours = contains(NumberField, {
    computeVia: function (this: CriticalityField) {
      return criticalityLevel(this.level)?.responseTargetHours;
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: CriticalityField) {
      return criticalityLevel(this.level)?.label ?? 'Unrated';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get level() {
      return criticalityLevel(this.args.model.level);
    }
    <template>
      <div class='crit'>
        <Dot
          @tone={{toneOfHue (if this.level this.level.hue 'slate')}}
          @label={{if this.level this.level.label 'Unrated'}}
        />
        {{#if this.level}}
          <span class='crit-target'>respond within
            {{this.level.responseTargetHours}}
            h</span>
        {{/if}}
      </div>
      <style scoped>
        .crit {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .crit-target {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
    isTop = (rank: number) => rank >= 4;
  };

  static atom = class Atom extends Component<typeof this> {
    get level() {
      return criticalityLevel(this.args.model.level);
    }
    <template>
      <Dot
        @tone={{toneOfHue (if this.level this.level.hue 'slate')}}
        @label={{if this.level this.level.label 'Unrated'}}
      />
    </template>
  };
}

export default CriticalityField;
