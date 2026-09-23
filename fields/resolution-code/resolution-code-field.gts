import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import FileCheckIcon from '@cardstack/boxel-icons/file-check';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const RESOLUTION_CODES = [
  'remediated',
  'risk-accepted',
  'false-positive',
  'duplicate',
  'superseded',
  'out-of-scope',
] as const;

export const RESOLUTION_LABELS: Record<string, string> = {
  remediated: 'Remediated',
  'risk-accepted': 'Risk accepted',
  'false-positive': 'False positive',
  duplicate: 'Duplicate',
  superseded: 'Superseded',
  'out-of-scope': 'Out of scope',
};

export const RESOLUTION_HUE: Record<string, Hue> = {
  remediated: 'green',
  'risk-accepted': 'amber',
  'false-positive': 'slate',
  duplicate: 'slate',
  superseded: 'slate',
  'out-of-scope': 'slate',
};

export const ResolutionCodeValueField = enumField(StringField, {
  displayName: 'Resolution Code',
  options: RESOLUTION_CODES.map((value) => ({
    value,
    label: RESOLUTION_LABELS[value],
  })),
});

/**
 * How a finding was closed. "Closed" alone hides whether anything was fixed;
 * the code says so, and two of them carry obligations: remediated needs the
 * corrective action done, risk-accepted needs someone senior to have said so.
 */
export class ResolutionCodeField extends FieldDef {
  static displayName = 'Resolution Code';
  static icon = FileCheckIcon;

  @field code = contains(ResolutionCodeValueField);

  @field requiresAction = contains(BooleanField, {
    computeVia: function (this: ResolutionCodeField) {
      return this.code === 'remediated';
    },
  });

  @field requiresApproval = contains(BooleanField, {
    computeVia: function (this: ResolutionCodeField) {
      return this.code === 'risk-accepted';
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: ResolutionCodeField) {
      return RESOLUTION_LABELS[this.code ?? ''] ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return RESOLUTION_HUE[this.args.model?.code ?? ''] ?? 'slate';
    }
    <template>
      <div class='resolution'>
        <StatePill @label={{@model.label}} @hue={{this.hue}} @dot={{true}} />
        {{#if @model.requiresAction}}
          <span class='note'>needs corrective action done</span>
        {{else if @model.requiresApproval}}
          <span class='note'>needs approval</span>
        {{/if}}
      </div>
      <style scoped>
        .resolution {
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
    get hue() {
      return RESOLUTION_HUE[this.args.model?.code ?? ''] ?? 'slate';
    }
    <template><StatePill @label={{@model.label}} @hue={{this.hue}} /></template>
  };
}

export default ResolutionCodeField;
