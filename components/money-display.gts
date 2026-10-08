import GlimmerComponent from '@glimmer/component';
import { FormatNumber } from '@cardstack/pretui/components/format-number';

// Money Display — the money-rendering primitive: tabular numerals, the
// currency's own precision, negatives as red parentheses, an optional
// base-currency subline for foreign amounts. A display wrapper over plain
// values — explicitly NOT a money data type (base AmountWithCurrency owns
// storage). Formatting is Intl's currency style, the same output as the
// catalog's formatMoney helpers, so a total reads identically in a Money
// Display and in a card that formats it inline.

function currencyFormat(code: string): Intl.NumberFormat | undefined {
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code.toUpperCase(),
    });
  } catch {
    return undefined;
  }
}

/** The currency's minor-unit digits as Intl reports them: 0 for JPY, 3 for KWD. */
export function decimalsFor(code?: string | null): number {
  if (!code) {
    return 2;
  }
  return currencyFormat(code)?.resolvedOptions().maximumFractionDigits ?? 2;
}

export function formatMoneyDisplay(
  amount?: number | null,
  code?: string | null,
): string {
  if (amount == null || !Number.isFinite(amount)) {
    return '—';
  }
  let format = code ? currencyFormat(code) : undefined;
  let abs = format
    ? format.format(Math.abs(amount))
    : Math.abs(amount).toLocaleString('en-US', {
        maximumFractionDigits: 2,
      });
  return amount < 0 ? `(${abs})` : abs;
}

interface Signature {
  Args: {
    amount?: number | null;
    currency?: string | null;
    /** shown as a muted subline, e.g. the base-currency equivalent */
    baseAmount?: number | null;
    baseCurrency?: string | null;
    /** larger emphatic rendering for totals */
    emphatic?: boolean;
  };
  Element: HTMLElement;
}

export class MoneyDisplay extends GlimmerComponent<Signature> {
  get finite() {
    let amount = this.args.amount;
    return amount != null && Number.isFinite(amount) ? amount : undefined;
  }
  get magnitude() {
    let amount = this.finite;
    return amount === undefined ? undefined : Math.abs(amount);
  }
  get negative() {
    return (this.finite ?? 0) < 0;
  }
  // An unknown code formats as a plain number, as formatMoneyDisplay does.
  get code() {
    let code = this.args.currency;
    return code && currencyFormat(code) ? code.toUpperCase() : undefined;
  }
  get baseDisplay() {
    if (this.args.baseAmount == null) {
      return undefined;
    }
    return formatMoneyDisplay(this.args.baseAmount, this.args.baseCurrency);
  }
  <template>
    <span
      class='money {{if this.negative "negative"}} {{if @emphatic "emphatic"}}'
      ...attributes
    >
      <span class='money-main'>{{if this.negative '('}}<FormatNumber
          @value={{this.magnitude}}
          @style='currency'
          @currency={{this.code}}
          @locale='en-US'
          @maximumFractionDigits={{unless this.code 2}}
        />{{if this.negative ')'}}</span>
      {{#if this.baseDisplay}}
        <span class='money-base'>≈ {{this.baseDisplay}}</span>
      {{/if}}
    </span>
    <style scoped>
      .money {
        display: inline-flex;
        flex-direction: column;
        align-items: flex-end;
        font-variant-numeric: tabular-nums;
        line-height: 1.25;
      }
      .money-main {
        font-weight: 600;
      }
      .money.emphatic .money-main {
        font-weight: 700;
        font-size: 1.125em;
      }
      .money.negative .money-main {
        color: var(--destructive-ink);
      }
      .money-base {
        font-size: 0.75em;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
