import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import StringField from '@cardstack/base/string';
import { Command } from '@cardstack/runtime-common';
import { TaxJurisdiction } from '../tax-jurisdiction';
import { inputCard } from '@cardstack/catalog/utils/find-card';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';

export class CalculateTaxInput extends CardDef {
  @field taxableAmount = contains(NumberField);
  @field jurisdiction = linksTo(TaxJurisdiction, { searchable: true });
}

export class CalculateTaxResult extends CardDef {
  @field taxableAmount = contains(NumberField);
  @field taxAmount = contains(NumberField);
  @field rateApplied = contains(NumberField);
  @field message = contains(StringField);
}

/** The tax on `amount` at `ratePercent`, rounded to the cent. */
export function taxOn(amount: number, ratePercent: number): number {
  return Math.round(amount * ratePercent) / 100;
}

/**
 * Computes the tax on an amount at a Tax Jurisdiction's rate. It takes a
 * plain number rather than the thing being taxed, so the caller decides what
 * the taxable amount is and where the result goes. The rate is whatever the
 * jurisdiction record says; there is no live lookup.
 */
export default class CalculateTaxCommand extends Command<
  typeof CalculateTaxInput,
  typeof CalculateTaxResult
> {
  static actionVerb = 'Calculate Tax';

  async getInputType() {
    return CalculateTaxInput;
  }

  protected async run(input: CalculateTaxInput): Promise<CalculateTaxResult> {
    let taxableAmount = input.taxableAmount;
    if (
      typeof taxableAmount !== 'number' ||
      !Number.isFinite(taxableAmount) ||
      taxableAmount < 0
    ) {
      throw new Error('A taxable amount of zero or more is required');
    }

    let jurisdiction = await inputCard<TaxJurisdiction>(
      this.commandContext,
      input,
      'jurisdiction',
    );
    if (!jurisdiction) throw new Error('A tax jurisdiction is required');
    if (!isCardOfType(jurisdiction, TaxJurisdiction)) {
      throw new Error(
        `${(jurisdiction as CardDef).id ?? 'The card'} is not a tax jurisdiction`,
      );
    }
    let rateApplied = jurisdiction.rate;
    if (typeof rateApplied !== 'number' || !Number.isFinite(rateApplied)) {
      throw new Error(`${jurisdiction.cardTitle} has no tax rate`);
    }

    return new CalculateTaxResult({
      taxableAmount,
      taxAmount: taxOn(taxableAmount, rateApplied),
      rateApplied,
      message: `Tax calculated at ${rateApplied}% for ${jurisdiction.cardTitle}.`,
    });
  }
}
