import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';

import { SeverityBadge } from '../../components/severity-badge';
import {
  SEVERITY_LEVELS,
  SEVERITY_LABELS,
  SEVERITY_RANK,
  certificateAtRisk,
} from './severity-vocabulary';

export {
  SEVERITY_LEVELS,
  SEVERITY_LABELS,
  SEVERITY_RANK,
  SEVERITY_HUE,
  certificateAtRisk,
} from './severity-vocabulary';

export const SeverityLevelField = enumField(StringField, {
  displayName: 'Severity Level',
  options: SEVERITY_LEVELS.map((value) => ({
    value,
    label: SEVERITY_LABELS[value],
  })),
});

/**
 * How bad a finding is — one definition so the badge, the report roll-up
 * and any follow-up SLA never disagree about what "major" means.
 *
 * A compound field rather than a bare enum so it can carry the derived facts
 * (rank, certificate-at-risk) and so a Spec can hold an example of it.
 */
export class SeverityField extends FieldDef {
  static displayName = 'Severity';
  static icon = AlertTriangleIcon;

  @field level = contains(SeverityLevelField);

  @field rank = contains(NumberField, {
    computeVia: function (this: SeverityField) {
      return SEVERITY_RANK[this.level ?? ''] ?? 0;
    },
  });

  @field certificateAtRisk = contains(BooleanField, {
    computeVia: function (this: SeverityField) {
      return certificateAtRisk(this.level);
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: SeverityField) {
      return SEVERITY_LABELS[this.level ?? ''] ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='severity'>
        <SeverityBadge @level={{@model.level}} />
        {{#if @model.certificateAtRisk}}
          <span class='note'>certificate at risk</span>
        {{/if}}
      </div>
      <style scoped>
        .severity {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .note {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <SeverityBadge @level={{@model.level}} @compact={{true}} />
    </template>
  };
}

export default SeverityField;
