import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import ShieldIcon from '@cardstack/boxel-icons/shield';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const TRUST_LEVELS = [
  'self-asserted',
  'attested',
  'system-generated',
  'independently-verified',
] as const;

export const TRUST_LABELS: Record<string, string> = {
  'self-asserted': 'Self-asserted',
  attested: 'Attested',
  'system-generated': 'System-generated',
  'independently-verified': 'Independently verified',
};

/**
 * How far the evidence can be relied on, ordered. An auditor weights evidence
 * by this, so the order is the useful part — a self-asserted statement and a
 * system export are both "evidence" and are not worth the same.
 */
export const TRUST_WEIGHT: Record<string, number> = {
  'self-asserted': 1,
  attested: 2,
  'system-generated': 3,
  'independently-verified': 4,
};

// Trust is not a verdict, so it stays cool: only the top level earns a
// colour, and self-asserted is deliberately dull rather than alarming — it is
// a normal, acceptable kind of evidence for a low-risk control.
export const TRUST_HUE: Record<string, Hue> = {
  'self-asserted': 'slate',
  attested: 'teal',
  'system-generated': 'blue',
  'independently-verified': 'green',
};

export const TrustLevelField = enumField(StringField, {
  displayName: 'Trust Level',
  options: TRUST_LEVELS.map((value) => ({
    value,
    label: TRUST_LABELS[value],
  })),
});

/**
 * How far to believe an artefact, and on what basis.
 *
 * `isComplete` is the honest gate: an `attested` level with nobody named and
 * no date is a claim about a claim. The field reports the gap rather than
 * refusing the value, because half-recorded evidence is a real state during
 * fieldwork — what must never happen is it reading as fully attested.
 */
export class TrustMetadataField extends FieldDef {
  static displayName = 'Trust Metadata';
  static icon = ShieldIcon;

  @field level = contains(TrustLevelField);
  @field attestedBy = linksTo(() => PersonBase);
  @field attestedAt = contains(DateTimeField);
  /** The outside party, for independently-verified evidence. */
  @field verifiedBy = contains(StringField);
  /** One line: "exported from the IdP", "photo taken on site". */
  @field basis = contains(StringField);

  @field weight = contains(NumberField, {
    computeVia: function (this: TrustMetadataField) {
      return TRUST_WEIGHT[this.level ?? ''] ?? 0;
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: TrustMetadataField) {
      return TRUST_LABELS[this.level ?? ''] ?? '';
    },
  });

  @field isComplete = contains(BooleanField, {
    computeVia: function (this: TrustMetadataField) {
      if (this.level === 'attested') {
        return Boolean(this.attestedBy && this.attestedAt);
      }
      if (this.level === 'independently-verified') {
        return Boolean((this.verifiedBy ?? '').trim());
      }
      return Boolean(this.level);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return TRUST_HUE[this.args.model?.level ?? ''] ?? 'slate';
    }
    <template>
      <div class='trust'>
        <StatePill @label={{@model.label}} @hue={{this.hue}} @dot={{true}} />
        {{#if @model.basis}}
          <span class='basis'>{{@model.basis}}</span>
        {{/if}}
        {{#if @model.attestedBy}}
          <span class='who'><@fields.attestedBy @format='atom' /></span>
        {{/if}}
        {{#if @model.verifiedBy}}
          <span class='who'>{{@model.verifiedBy}}</span>
        {{/if}}
        {{#unless @model.isComplete}}
          <span class='gap'>incomplete attestation</span>
        {{/unless}}
      </div>
      <style scoped>
        .trust {
          display: inline-flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.8125rem;
        }
        .basis,
        .who {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .gap {
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--state-next-fg, var(--foreground, var(--boxel-dark)));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return TRUST_HUE[this.args.model?.level ?? ''] ?? 'slate';
    }
    <template><StatePill @label={{@model.label}} @hue={{this.hue}} /></template>
  };
}

export default TrustMetadataField;
