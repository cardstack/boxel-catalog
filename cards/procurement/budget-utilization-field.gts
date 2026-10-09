import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { htmlSafe } from '@ember/template';

import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Money } from '@cardstack/catalog/cards/crm/money';
import {
  StatePill,
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { nameProgress } from '@cardstack/catalog/components/pretui-helpers';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';

// Commitment-accounting utilization: money splits into `actual` (received)
// and `committed` (approved POs not yet received). Utilization counts BOTH —
// committed money is already spoken for, which is the whole point of
// commitment accounting. The bar renders the two segments distinctly
// (actual solid, committed hatched) so "spent" and "promised" never blur.
//
// Domain-neutral: this field holds three plain numbers. The consumer
// (ProcurementBudget here) decides what counts as committed vs actual and
// keeps the numbers current via its commands.

export type UtilizationBand = 'healthy' | 'warning' | 'critical' | 'over';

export const UTILIZATION_BAND_COLORS: Record<UtilizationBand, StateColor> = {
  healthy: stateColor('green'),
  warning: stateColor('amber'),
  critical: stateColor('red'),
  over: stateColor('red'),
};

/** The StatePill hue for each band; the same table as `UTILIZATION_BAND_COLORS`. */
export const UTILIZATION_BAND_HUES: Record<UtilizationBand, Hue> = {
  healthy: 'green',
  warning: 'amber',
  critical: 'red',
  over: 'red',
};

export function utilizationBandOf(percent: number): UtilizationBand {
  if (percent > 100) {
    return 'over';
  }
  if (percent >= 95) {
    return 'critical';
  }
  if (percent >= 70) {
    return 'warning';
  }
  return 'healthy';
}

export class BudgetUtilizationField extends FieldDef {
  static displayName = 'Budget Utilization';

  @field budget = contains(NumberField);
  @field committed = contains(NumberField);
  @field actual = contains(NumberField);

  @field percent = contains(NumberField, {
    computeVia: function (this: BudgetUtilizationField) {
      let budget = this.budget ?? 0;
      if (budget <= 0) {
        return 0;
      }
      let used = (this.committed ?? 0) + (this.actual ?? 0);
      return Math.round((used / budget) * 100);
    },
  });

  @field band = contains(StringField, {
    computeVia: function (this: BudgetUtilizationField) {
      return utilizationBandOf(this.percent ?? 0);
    },
  });

  @field available = contains(NumberField, {
    computeVia: function (this: BudgetUtilizationField) {
      return (this.budget ?? 0) - (this.committed ?? 0) - (this.actual ?? 0);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get actualPct() {
      let budget = this.args.model?.budget ?? 0;
      if (budget <= 0) {
        return 0;
      }
      return Math.min(100, ((this.args.model?.actual ?? 0) / budget) * 100);
    }
    get committedPct() {
      let budget = this.args.model?.budget ?? 0;
      if (budget <= 0) {
        return 0;
      }
      let pct = ((this.args.model?.committed ?? 0) / budget) * 100;
      return Math.min(100 - this.actualPct, pct);
    }
    get bandHue(): Hue {
      return (
        UTILIZATION_BAND_HUES[this.args.model?.band as UtilizationBand] ??
        'green'
      );
    }
    get bandLabel() {
      switch (this.args.model?.band) {
        case 'over':
          return 'Over budget';
        case 'critical':
          return 'Critical';
        case 'warning':
          return 'Warning';
        default:
          return 'Healthy';
      }
    }
    // Absent figures read as zero, as the ledger does.
    get actualAmount() {
      return this.args.model?.actual ?? 0;
    }
    get committedAmount() {
      return this.args.model?.committed ?? 0;
    }
    get availableAmount() {
      return this.args.model?.available ?? 0;
    }
    get usedPct() {
      return this.actualPct + this.committedPct;
    }
    // The share of the filled length that is actual spend; the rest of the
    // fill is committed and drawn hatched.
    get actualShare() {
      return this.usedPct > 0 ? (this.actualPct / this.usedPct) * 100 : 0;
    }
    get barStyle() {
      return htmlSafe(`--actual-share: ${this.actualShare}%`);
    }
    get valueText() {
      return `${this.args.model?.percent ?? 0}% used: ${formatMoney(this.actualAmount, 'USD')} actual, ${formatMoney(this.committedAmount, 'USD')} committed`;
    }
    <template>
      <div class='util'>
        <div class='meta'>
          <span class='pct band-{{@model.band}}'>{{@model.percent}}%</span>
          <StatePill @label={{this.bandLabel}} @hue={{this.bandHue}} />
        </div>
        <ProgressBar
          class='bar'
          style={{this.barStyle}}
          @value={{this.usedPct}}
          @max={{100}}
          @steps={{false}}
          {{nameProgress 'Budget utilization' this.valueText}}
        />
        <div class='legend'>
          <span><i class='swatch solid'></i>actual
            <Money @amount={{this.actualAmount}} @code='USD' /></span>
          <span><i class='swatch hatch'></i>committed
            <Money @amount={{this.committedAmount}} @code='USD' /></span>
          <span class='avail'>available
            <Money @amount={{this.availableAmount}} @code='USD' /></span>
        </div>
      </div>
      <style scoped>
        .util {
          display: grid;
          gap: var(--boxel-sp-4xs);
          font-size: 0.8125rem;
        }
        .meta {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .pct {
          font-weight: 700;
          font-size: 1rem;
          font-variant-numeric: tabular-nums;
        }
        .band-healthy {
          color: var(--success-ink);
        }
        .band-warning {
          color: var(--warning-ink);
        }
        .band-critical,
        .band-over {
          color: var(--destructive-ink);
        }
        /* Pret UI ProgressBar fills from --primary, which measures 1.20:1
           against the track on a light page, so the bar takes the ink token.
           Its fill is the used share (actual + committed); a second
           background splits it so actual stays solid and committed reads
           hatched. The track is raised from 4px so the hatch stays legible. */
        .bar {
          --primary: var(--primary-ink);
        }
        .bar :deep(.pretui-progress) {
          height: 0.5rem;
          border-radius: 0.25rem;
        }
        .bar :deep(.pretui-progress-fill) {
          border-radius: 0;
          background-color: transparent;
          background-image:
            linear-gradient(
              to right,
              var(--primary) var(--actual-share),
              transparent var(--actual-share)
            ),
            repeating-linear-gradient(
              45deg,
              var(--primary),
              var(--primary) 0.1875rem,
              transparent 0.1875rem,
              transparent 0.375rem
            );
        }
        .legend {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-sm);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .legend .avail {
          margin-left: auto;
          font-weight: 600;
          color: var(--foreground);
        }
        .swatch {
          display: inline-block;
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 0.125rem;
          margin-right: 0.25rem;
          vertical-align: -0.0625rem;
        }
        .swatch.solid {
          background-color: var(--primary-ink);
        }
        .swatch.hatch {
          background-image: repeating-linear-gradient(
            45deg,
            var(--primary-ink),
            var(--primary-ink) 0.125rem,
            transparent 0.125rem,
            transparent 0.25rem
          );
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='util-atom band-{{@model.band}}'>{{@model.percent}}%</span>
      <style scoped>
        .util-atom {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          font-size: 0.8125rem;
        }
        .band-healthy {
          color: var(--success-ink);
        }
        .band-warning {
          color: var(--warning-ink);
        }
        .band-critical,
        .band-over {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };
}
