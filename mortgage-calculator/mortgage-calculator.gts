import NumberField from 'https://cardstack.com/base/number';
import CurrencyField from 'https://cardstack.com/base/currency';
import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import CalculatorIcon from '@cardstack/boxel-icons/calculator';
import { MortgageCalculatorIsolated } from './components/isolated-template';
import { MortgageCalculatorFitted } from './components/fitted-template';

/* ---------- Card definition ---------- */

export class MortgageCalculator extends CardDef {
  @field currency = contains(CurrencyField);
  @field homePrice = contains(NumberField);
  @field downPaymentPercentage = contains(NumberField);
  @field loanTermYears = contains(NumberField);
  @field interestRatePercentage = contains(NumberField);
  @field taxPerMonth = contains(NumberField);
  @field insurancePerMonth = contains(NumberField);
  @field hoaFeesPerMonth = contains(NumberField);

  @field downPayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.homePrice ?? 0) * ((this.downPaymentPercentage ?? 0) / 100);
    },
  });
  @field loanAmount = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.homePrice ?? 0) - (this.downPayment ?? 0);
    },
  });
  @field numberOfPayments = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.loanTermYears ?? 0) * 12;
    },
  });
  @field monthlyInterestRate = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.interestRatePercentage ?? 0) / 100 / 12;
    },
  });
  @field monthlyMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      const r = this.monthlyInterestRate ?? 0;
      const n = this.numberOfPayments ?? 0;
      const L = this.loanAmount ?? 0;
      if (!L || !n) return 0;
      if (r === 0) return L / n;
      return L * ((r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1));
    },
  });
  @field monthlyTotal = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.monthlyMortgagePayment ?? 0) +
        (this.taxPerMonth ?? 0) +
        (this.insurancePerMonth ?? 0) +
        (this.hoaFeesPerMonth ?? 0)
      );
    },
  });
  @field lifetimeMortgagePayment = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.monthlyMortgagePayment ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeInterest = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.lifetimeMortgagePayment ?? 0) - (this.loanAmount ?? 0);
    },
  });
  @field lifetimeTaxes = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.taxPerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeInsurance = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.insurancePerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeHoaFees = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (this.hoaFeesPerMonth ?? 0) * (this.numberOfPayments ?? 0);
    },
  });
  @field lifetimeTotal = contains(NumberField, {
    computeVia(this: MortgageCalculator) {
      return (
        (this.lifetimeMortgagePayment ?? 0) +
        (this.lifetimeTaxes ?? 0) +
        (this.lifetimeInsurance ?? 0) +
        (this.lifetimeHoaFees ?? 0)
      );
    },
  });

  static displayName = 'Mortgage Calculator';
  static icon = CalculatorIcon;
  static prefersWideFormat = true;
}

MortgageCalculator.fitted = MortgageCalculatorFitted;
MortgageCalculator.isolated = MortgageCalculatorIsolated;
