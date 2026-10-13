import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import { WarrantyKindField } from './maintenance-vocabulary';
import { toDay, daysBetweenDays } from './utils/recurrence';

/**
 * A coverage period from a provider, with terms and how to claim.
 *
 * The field's whole job is to say "still covered until 2027-03-14 — claim,
 * don't pay" BEFORE a technician orders the part. `isActive` and
 * `daysRemaining` are computed on calendar days (never `toISOString`) so the
 * boundary days are right in every timezone.
 *
 * A FieldDef cannot `linksTo`, so the provider is stored as id + name
 * (Record Owner pattern); the consuming card may also link the Vendor.
 * Generic: an asset, a laptop, a vehicle, a building system.
 */
export class WarrantyField extends FieldDef {
  static displayName = 'Warranty';
  static icon = ShieldCheckIcon;

  @field providerId = contains(StringField, {
    description: 'Card id of the Vendor providing the coverage.',
  });
  @field providerName = contains(StringField);
  @field kind = contains(WarrantyKindField);
  @field startsOn = contains(DateField);
  @field endsOn = contains(DateField);
  @field terms = contains(TextAreaField);
  @field claimReference = contains(StringField, {
    description: 'Policy / contract number quoted when claiming.',
  });

  @field isActive = contains(BooleanField, {
    computeVia: function (this: WarrantyField) {
      if (this.kind === 'none') return false;
      let end = toDay(this.endsOn);
      if (!end) return false;
      let start = toDay(this.startsOn);
      let today = toDay(new Date())!;
      if (start && start.getTime() > today.getTime()) return false;
      return end.getTime() >= today.getTime();
    },
  });

  @field daysRemaining = contains(NumberField, {
    computeVia: function (this: WarrantyField) {
      let end = toDay(this.endsOn);
      if (!end) return undefined;
      return daysBetweenDays(toDay(new Date())!, end);
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: WarrantyField) {
      if (!this.endsOn || this.kind === 'none') return 'No warranty';
      let end = toDay(this.endsOn);
      let day = end
        ? end.toLocaleDateString(undefined, {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
          })
        : '';
      if (this.isActive) {
        return `Covered until ${day}${this.providerName ? ` · ${this.providerName}` : ''}`;
      }
      return `Expired ${day}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      let m = this.args.model;
      if (!m.endsOn || m.kind === 'none') return 'slate';
      if (!m.isActive) return 'slate';
      return (m.daysRemaining ?? 999) <= 60 ? 'amber' : 'green';
    }
    get pillLabel() {
      let m = this.args.model;
      if (!m.endsOn || m.kind === 'none') return 'No warranty';
      return m.isActive ? 'Covered' : 'Expired';
    }
    <template>
      <div class='warranty'>
        <div class='warranty-row'>
          <StatePill
            @label={{this.pillLabel}}
            @hue={{this.hue}}
            @dot={{true}}
          />
          <span class='warranty-label'>{{@model.label}}</span>
        </div>
        {{#if @model.isActive}}
          <div class='warranty-claim'>
            Claim, don't pay
            {{#if @model.claimReference}}· ref
              <code>{{@model.claimReference}}</code>{{/if}}
            {{#if @model.daysRemaining}}·
              {{@model.daysRemaining}}
              days left{{/if}}
          </div>
        {{/if}}
        {{#if @model.terms}}
          <p class='warranty-terms'>{{@model.terms}}</p>
        {{/if}}
      </div>
      <style scoped>
        .warranty {
          display: grid;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
        }
        .warranty-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .warranty-label {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .warranty-claim {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .warranty-claim code {
          font-family: var(--font-mono);
          color: var(--foreground);
        }
        .warranty-terms {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: pre-wrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      let m = this.args.model;
      if (!m.endsOn || m.kind === 'none' || !m.isActive) return 'slate';
      return (m.daysRemaining ?? 999) <= 60 ? 'amber' : 'green';
    }
    get text() {
      let m = this.args.model;
      if (!m.endsOn || m.kind === 'none') return 'No warranty';
      return m.isActive ? 'Covered' : 'Expired';
    }
    <template><StatePill @label={{this.text}} @hue={{this.hue}} /></template>
  };
}

export default WarrantyField;
