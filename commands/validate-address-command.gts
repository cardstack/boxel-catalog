import {
  CardDef,
  contains,
  containsMany,
  field,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';

export class ValidateAddressInput extends CardDef {
  @field addressLine1 = contains(StringField);
  @field addressLine2 = contains(StringField);
  @field city = contains(StringField);
  @field region = contains(StringField, {
    description: 'State, province or county — whatever the country calls it.',
  });
  @field postalCode = contains(StringField);
  @field country = contains(StringField, {
    description: 'ISO 3166-1 alpha-2, uppercase. Required.',
  });
}

export class ValidateAddressResult extends CardDef {
  @field ok = contains(BooleanField);
  @field problems = containsMany(StringField);
  /** Information that does not fail the address, such as an ignored value. */
  @field notes = containsMany(StringField);
  @field normalizedPostalCode = contains(StringField);
  @field message = contains(StringField);
}

// Per-country rules for the parts that genuinely differ. Deliberately small:
// every entry here is a rule someone can point at, not a guess. A country
// absent from this table is validated on the universal rules only, and says
// so — which is the honest answer, not a failure.
interface CountryRule {
  postal?: { re: RegExp; hint: string; normalize?: (s: string) => string };
  /** The postal code is checked when given but not required. */
  postalOptional?: boolean;
  regionRequired?: boolean;
  regionLabel?: string;
}

const RULES: Record<string, CountryRule> = {
  GB: {
    postal: {
      // Outward + inward, space optional on input, always present on output.
      re: /^[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}$/i,
      hint: 'UK postcode, e.g. SW1A 1AA',
      normalize: (s) =>
        s
          .toUpperCase()
          .replace(/\s+/g, '')
          .replace(/^(.+)(\d[A-Z]{2})$/, '$1 $2'),
    },
  },
  US: {
    postal: { re: /^\d{5}(-\d{4})?$/, hint: 'ZIP, e.g. 94107 or 94107-1234' },
    regionRequired: true,
    regionLabel: 'state',
  },
  CA: {
    postal: {
      // Canada Post never uses D, F, I, O, Q or U, nor W or Z first.
      re: /^[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z]\s*\d[ABCEGHJ-NPRSTV-Z]\d$/i,
      hint: 'Canadian postal code, e.g. K1A 0B1',
      normalize: (s) =>
        s
          .toUpperCase()
          .replace(/\s+/g, '')
          .replace(/^(.{3})(.{3})$/, '$1 $2'),
    },
    regionRequired: true,
    regionLabel: 'province',
  },
  MY: { postal: { re: /^\d{5}$/, hint: '5 digits, e.g. 50450' } },
  SG: { postal: { re: /^\d{6}$/, hint: '6 digits, e.g. 018956' } },
  AU: {
    postal: { re: /^\d{4}$/, hint: '4 digits, e.g. 3000' },
    regionRequired: true,
    regionLabel: 'state',
  },
  DE: { postal: { re: /^\d{5}$/, hint: '5 digits, e.g. 10115' } },
  FR: { postal: { re: /^\d{5}$/, hint: '5 digits, e.g. 75008' } },
  NL: {
    postal: {
      re: /^\d{4}\s*[A-Z]{2}$/i,
      hint: '4 digits + 2 letters, e.g. 1012 AB',
    },
  },
  JP: { postal: { re: /^\d{3}-?\d{4}$/, hint: '7 digits, e.g. 100-0001' } },
  // Eircode: a routing key and a four-character identifier. Many Irish
  // addresses are still written without one, so it is optional.
  IE: {
    postal: {
      re: /^([AC-FHKNPRTV-Y]\d{2}|D6W)\s*[0-9AC-FHKNPRTV-Y]{4}$/i,
      hint: 'Eircode, e.g. D02 X285',
      normalize: (s) =>
        s
          .toUpperCase()
          .replace(/\s+/g, '')
          .replace(/^(.{3})(.{4})$/, '$1 $2'),
    },
    postalOptional: true,
  },
  // Countries with no postal system at all. Listing them is what stops a
  // "postal code missing" complaint that has no fix.
  AE: {},
  HK: {},
};

const NO_POSTAL_SYSTEM = new Set(['AE', 'HK']);

/**
 * Check that an address is structurally plausible for its country.
 *
 * ### Validation is not verification
 *
 * This says an address **could** exist. It cannot say it **does**. Confirming
 * a real deliverable address needs a postal authority or a geocoding service
 * — a network call, a subscription, and a per-lookup cost.
 *
 * Conflating the two is the trap: a system that reports "address validated"
 * after a format check has told the user something it does not know, and the
 * parcel still goes nowhere. Every message here is phrased as a format
 * finding for that reason.
 *
 * ### Country-specific rules, and honesty about their absence
 *
 * The rules table covers the countries whose formats genuinely differ, and
 * every entry is a rule someone can point at. A country **not** in the table
 * is checked against the universal rules and the result says the postal
 * format was not checked — which is the honest answer, not a pass and not a
 * failure.
 *
 * ### Countries with no postal system
 *
 * The UAE and Hong Kong have addresses with no postal code. Demanding one is
 * a validation error that has no fix, so they are listed explicitly rather
 * than falling through to "missing". Ireland's Eircode is checked when given
 * but not required.
 *
 * ### `region` is required only where it is actually required
 *
 * A US address without a state is ambiguous; a UK address without a county is
 * completely normal. Requiring it everywhere trains users to type filler.
 */
export class ValidateAddressCommand extends Command<
  typeof ValidateAddressInput,
  typeof ValidateAddressResult
> {
  static actionVerb = 'Validate';
  static displayName = 'Validate Address';

  async getInputType() {
    return ValidateAddressInput;
  }

  protected async run(
    input: ValidateAddressInput,
  ): Promise<ValidateAddressResult> {
    let problems: string[] = [];
    let notes: string[] = [];
    let country = (input.country ?? '').trim().toUpperCase();

    if (!country) {
      return new ValidateAddressResult({
        ok: false,
        problems: ['Country is required — every other rule depends on it.'],
        message: 'Cannot validate without a country.',
      });
    }
    if (!/^[A-Z]{2}$/.test(country)) {
      problems.push(
        `Country "${input.country}" is not an ISO 3166-1 alpha-2 code.`,
      );
    }

    if (!input.addressLine1?.trim()) {
      problems.push('Address line 1 is required.');
    }
    if (!input.city?.trim()) {
      problems.push('City is required.');
    }

    let rule = RULES[country];
    let postal = (input.postalCode ?? '').trim();
    let normalized = postal;

    if (rule?.regionRequired && !input.region?.trim()) {
      problems.push(
        `A ${rule.regionLabel ?? 'region'} is required for ${country} addresses.`,
      );
    }

    if (NO_POSTAL_SYSTEM.has(country)) {
      if (postal) {
        notes.push(
          `${country} addresses have no postal code; "${postal}" will not be used.`,
        );
      }
    } else if (!postal) {
      if (!rule?.postalOptional) {
        problems.push('Postal code is required.');
      }
    } else if (rule?.postal) {
      if (!rule.postal.re.test(postal)) {
        problems.push(
          `Postal code "${postal}" does not match the ${country} format (${rule.postal.hint}).`,
        );
      } else if (rule.postal.normalize) {
        normalized = rule.postal.normalize(postal);
      }
    }

    let unknownFormat = !NO_POSTAL_SYSTEM.has(country) && !rule?.postal;
    let ok = problems.length === 0;

    return new ValidateAddressResult({
      ok,
      problems,
      notes,
      normalizedPostalCode: normalized,
      message: ok
        ? unknownFormat
          ? `Structurally plausible. No postal format rule for ${country}, so that part was not checked. This is a format check, not proof the address exists.`
          : 'Structurally plausible. This is a format check, not proof the address exists.'
        : `${problems.length} problem${problems.length === 1 ? '' : 's'} found.`,
    });
  }
}

export default ValidateAddressCommand;
