import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import CircleCheckBigIcon from '@cardstack/boxel-icons/circle-check-big';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const EVALUATION_STATUSES = [
  'pass',
  'fail',
  'partial',
  'not-applicable',
  'unproven',
  'pending',
] as const;

export const EVALUATION_LABELS: Record<string, string> = {
  pass: 'Pass',
  fail: 'Fail',
  partial: 'Partial',
  'not-applicable': 'Not applicable',
  unproven: 'Unproven',
  pending: 'Pending',
};

// Only the verdicts are coloured. Unproven, not-applicable and pending are
// deliberately dull: a rule that passed on paper without evidence must not
// read as a pass from across the room.
export const EVALUATION_HUE: Record<string, Hue> = {
  pass: 'green',
  fail: 'red',
  partial: 'amber',
  'not-applicable': 'slate',
  unproven: 'slate',
  pending: 'slate',
};

const CONCLUSIVE = new Set(['pass', 'fail', 'partial', 'not-applicable']);

export const EvaluationStatusValueField = enumField(StringField, {
  displayName: 'Evaluation Status',
  options: EVALUATION_STATUSES.map((value) => ({
    value,
    label: EVALUATION_LABELS[value],
  })),
});

/**
 * The outcome of evaluating one rule against one subject.
 *
 * `unproven` is the honest state of a control that satisfied the rule but
 * attached no evidence — it counts against coverage, never as a pass.
 */
export class EvaluationStatusField extends FieldDef {
  static displayName = 'Evaluation Status';
  static icon = CircleCheckBigIcon;

  @field status = contains(EvaluationStatusValueField);

  @field isConclusive = contains(BooleanField, {
    computeVia: function (this: EvaluationStatusField) {
      return CONCLUSIVE.has(this.status ?? '');
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: EvaluationStatusField) {
      return EVALUATION_LABELS[this.status ?? ''] ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.status ?? ''] ?? 'slate';
    }
    <template>
      <StatePill @label={{@model.label}} @hue={{this.hue}} @dot={{true}} />
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.status ?? ''] ?? 'slate';
    }
    <template><StatePill @label={{@model.label}} @hue={{this.hue}} /></template>
  };
}

export default EvaluationStatusField;
