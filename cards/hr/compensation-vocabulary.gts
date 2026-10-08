import {
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import BooleanField from '@cardstack/base/boolean';
import CurrencyField from '@cardstack/base/currency';
import enumField from '@cardstack/base/enum';
import { formatAmount } from './utils';
import { daysUntil } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { Component } from '@cardstack/base/card-api';
import { gt } from '@cardstack/boxel-ui/helpers';

// The compensation and eligibility vocabulary. Two fields that answer the two
// questions a hiring or comp decision actually turns on: what may we pay, and
// may this person work here.
//
// Enum values are migrations — never rename or remove one.

// ── Salary Band ─────────────────────────────────────────────────────────────

/**
 * The pay range for a grade, in one currency, for one location.
 *
 * ### Three points, not two
 *
 * A band is min / **mid** / max. The midpoint is not `(min + max) / 2` and
 * must not be computed as one: bands are usually built around the midpoint as
 * the market rate, with the min and max set asymmetrically around it. Deriving
 * it would silently move everyone's compa-ratio.
 *
 * `midpoint` therefore falls back to the average only when it was never set,
 * and `isMidpointDerived` says so, because a comp review needs to know whether
 * it is reading a market rate or an arithmetic guess.
 *
 * ### Compa-ratio is the metric, not the range
 *
 * `compaRatioFor(salary)` — salary ÷ midpoint — is what compensation teams
 * actually work in. 1.0 is at market; below 0.8 usually triggers a review;
 * above 1.2 means the person is near the ceiling and a raise needs a
 * promotion, not a percentage.
 *
 * ### Bands overlap on purpose
 *
 * Adjacent grades are meant to overlap so a strong performer can out-earn a
 * weak one a grade above. Nothing here should treat overlap as an error.
 */
export class SalaryBandField extends FieldDef {
  static displayName = 'Salary Band';

  @field grade = contains(StringField, {
    description: 'The level this band belongs to — L4, Senior, Band 3.',
  });
  @field currency = contains(CurrencyField);
  @field location = contains(StringField, {
    description:
      'Geographic scope. The same grade carries different bands by market, so a band without one is ambiguous.',
  });

  @field minimum = contains(NumberField);
  @field midpoint = contains(NumberField, {
    description:
      'The market rate. Set deliberately — NOT the average of min and max.',
  });
  @field maximum = contains(NumberField);

  @field effectiveFrom = contains(DateField);
  @field effectiveTo = contains(DateField);
  @field source = contains(StringField, {
    description: 'Which survey or benchmark this came from.',
  });

  @field isMidpointDerived = contains(BooleanField, {
    computeVia: function (this: SalaryBandField) {
      return this.midpoint == null;
    },
  });

  @field effectiveMidpoint = contains(NumberField, {
    computeVia: function (this: SalaryBandField) {
      if (this.midpoint != null) {
        return this.midpoint;
      }
      if (this.minimum == null || this.maximum == null) {
        return undefined;
      }
      return (this.minimum + this.maximum) / 2;
    },
  });

  // Width as a percentage of the midpoint — the shape of the band, which is
  // how comp teams compare one band to another across grades.
  @field spreadPercent = contains(NumberField, {
    computeVia: function (this: SalaryBandField) {
      let mid = this.effectiveMidpoint;
      if (!mid || this.minimum == null || this.maximum == null) {
        return undefined;
      }
      return Number((((this.maximum - this.minimum) / mid) * 100).toFixed(1));
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: SalaryBandField) {
      if (this.minimum == null || this.maximum == null) {
        return this.grade ?? '';
      }
      let code = this.currency?.code ?? '';
      return `${code} ${formatAmount(this.minimum)}–${formatAmount(this.maximum)}`.trim();
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='band'>
        <span class='range'>{{@model.label}}</span>
        <span class='meta'>
          {{#if @model.grade}}{{@model.grade}}{{/if}}
          {{#if @model.location}} · {{@model.location}}{{/if}}
          {{#if @model.spreadPercent}} · {{@model.spreadPercent}}% spread{{/if}}
        </span>
        {{#if @model.isMidpointDerived}}
          {{! Load-bearing: a comp review must know whether it is reading a
            market rate or an arithmetic guess. }}
          <span class='derived'>midpoint derived</span>
        {{/if}}
      </div>
      <style scoped>
        .band {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .range {
          font: 600 var(--boxel-font);
          font-variant-numeric: tabular-nums;
        }
        .meta {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
        .derived {
          font: var(--boxel-font-xs);
          color: var(--warning);
        }
      </style>
    </template>
  };
}

// Free function rather than a computed: it takes an argument, and a field
// cannot. Returns undefined — never 1 — when there is no midpoint to compare
// against, because "at market" and "unknown" must not read the same.
export function compaRatio(
  band: Pick<SalaryBandField, 'midpoint' | 'minimum' | 'maximum'>,
  salary?: number | null,
): number | undefined {
  if (salary == null || !Number.isFinite(salary)) {
    return undefined;
  }
  let mid =
    band.midpoint ??
    (band.minimum != null && band.maximum != null
      ? (band.minimum + band.maximum) / 2
      : undefined);
  if (!mid) {
    return undefined;
  }
  return Number((salary / mid).toFixed(3));
}

// ── Work Authorization ──────────────────────────────────────────────────────

export const WorkAuthStatusField = enumField(StringField, {
  options: [
    { value: 'citizen', label: 'Citizen' },
    { value: 'permanent-resident', label: 'Permanent resident' },
    { value: 'visa-holder', label: 'Visa holder' },
    { value: 'requires-sponsorship', label: 'Requires sponsorship' },
    { value: 'not-authorized', label: 'Not authorized' },
  ],
});

/**
 * Whether someone may work in a jurisdiction, and for how long.
 *
 * ### Deliberately stores no document numbers
 *
 * No passport number, no visa number, no national ID. Those are the highest-
 * sensitivity fields a system can hold and they are not needed to answer the
 * question this field exists for. A system that collects them because "it
 * might be useful" has taken on a breach liability for nothing.
 *
 * `verifiedOn` and `verifiedBy` record that a check happened. The evidence
 * itself lives wherever documents live, not here.
 *
 * ### Sponsorship now vs sponsorship later
 *
 * The distinction hiring decisions actually turn on. Someone authorised today
 * on a visa expiring in eight months will need sponsorship **during** the
 * role, which is a different conversation from needing it to start.
 * `willNeedSponsorshipWithin(days)` answers that; a boolean cannot.
 */
export class WorkAuthorizationField extends FieldDef {
  static displayName = 'Work Authorization';

  @field jurisdiction = contains(StringField, {
    description:
      'Where this authorisation applies. Authorisation is per-country; a global boolean is meaningless.',
  });
  @field status = contains(WorkAuthStatusField);
  @field visaType = contains(StringField, {
    description: 'The category, not the number — H-1B, Tier 2, EP.',
  });
  @field validFrom = contains(DateField);
  @field expiresOn = contains(DateField);

  @field restrictions = containsMany(StringField, {
    description:
      'Conditions attached: employer-tied, hours-capped, role-restricted.',
  });

  @field verifiedOn = contains(DateField);
  @field verifiedBy = contains(StringField);

  @field isAuthorized = contains(BooleanField, {
    computeVia: function (this: WorkAuthorizationField) {
      if (this.status === 'not-authorized' || !this.status) {
        return false;
      }
      if (this.status === 'requires-sponsorship') {
        return false;
      }
      if (this.expiresOn && new Date(this.expiresOn) <= new Date()) {
        return false;
      }
      return true;
    },
  });

  @field isVerified = contains(BooleanField, {
    computeVia: function (this: WorkAuthorizationField) {
      return Boolean(this.verifiedOn);
    },
  });

  // Undefined when nothing expires — a citizen has no expiry, and rendering
  // that as a very large number invites a sort that puts them last.
  @field daysUntilExpiry = contains(NumberField, {
    computeVia: function (this: WorkAuthorizationField) {
      return daysUntil(this.expiresOn);
    },
  });

  @field needsSponsorshipNow = contains(BooleanField, {
    computeVia: function (this: WorkAuthorizationField) {
      return this.status === 'requires-sponsorship';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='auth'>
        <span class='status {{if @model.isAuthorized "ok" "no"}}'>
          {{@model.status}}
          {{#if @model.visaType}} · {{@model.visaType}}{{/if}}
        </span>
        <span class='meta'>
          {{#if @model.jurisdiction}}{{@model.jurisdiction}}{{/if}}
          {{#if @model.daysUntilExpiry}}
            · expires in
            {{@model.daysUntilExpiry}}d
          {{/if}}
          {{#unless @model.isVerified}} · unverified{{/unless}}
        </span>
        {{#if (gt @model.restrictions.length 0)}}
          <span class='restr'>{{@model.restrictions.length}}
            restriction(s)</span>
        {{/if}}
      </div>
      <style scoped>
        .auth {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .status {
          font: 600 var(--boxel-font-sm);
        }
        .status.no {
          color: var(--destructive);
        }
        .meta,
        .restr {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// Will this authorisation lapse inside the window? The question a hiring
// manager is really asking, and one a boolean field cannot express because
// the window depends on the role.
export function willNeedSponsorshipWithin(
  auth: Pick<WorkAuthorizationField, 'status' | 'expiresOn'>,
  days: number,
): boolean {
  if (auth.status === 'requires-sponsorship') {
    return true;
  }
  if (auth.status === 'citizen' || auth.status === 'permanent-resident') {
    return false;
  }
  let left = daysUntil(auth.expiresOn);
  return left != null && left <= days;
}
