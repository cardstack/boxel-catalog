import { Component } from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import HourglassIcon from '@cardstack/boxel-icons/hourglass';

/**
 * Academic credit a course is worth — a number with a unit and a convention,
 * not a plain count. Half credits are common (1.5), negatives are not, and a
 * transcript prints it with one decimal so "3" and "3.0" never look like two
 * different things across a list.
 */
export class CreditHoursField extends NumberField {
  static displayName = 'Credit Hours';
  static icon = HourglassIcon;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='credit'>{{formatCreditHours @model}}</span>
      <style scoped>
        .credit {
          font-variant-numeric: tabular-nums;
          color: var(--foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='credit-atom'>{{formatCreditHours @model short=true}}</span>
      <style scoped>
        .credit-atom {
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export function formatCreditHours(
  n: number | null | undefined,
  opts?: { short?: boolean },
): string {
  if (n == null || Number.isNaN(n)) return '—';
  let v = Math.max(0, Math.round(n * 2) / 2).toFixed(1);
  if (opts?.short) return `${v} cr`;
  return `${v} credit ${n === 1 ? 'hour' : 'hours'}`;
}

export default CreditHoursField;
