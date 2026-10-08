import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';

export class NormalizePhoneInput extends CardDef {
  @field raw = contains(StringField, {
    description: 'The number as a human typed or an import supplied it.',
  });
  @field defaultCallingCode = contains(StringField, {
    description:
      'Calling code to assume for a national-format number — "44", "1", "65". Without it a national number CANNOT be normalized.',
  });
}

export class NormalizePhoneResult extends CardDef {
  @field e164 = contains(StringField, {
    description:
      'Normalized number, +[calling code][subscriber]. Empty on failure.',
  });
  @field callingCode = contains(StringField);
  @field extension = contains(StringField);
  @field ok = contains(BooleanField);
  @field reason = contains(StringField);
}

// Extension, in the spellings that actually appear in imported data. Kept
// separate from the number because an extension is not dialable as part of
// E.164 — it is dialed after the call connects, and folding it in produces a
// number that looks valid and rings nothing.
const EXT_RE = /(?:\s|^)(?:ext\.?|x|extension|#)\s*(\d{1,6})\s*$/i;

// E.164 caps the whole number at 15 digits including the calling code, and no
// assignment is shorter than 8 in practice. Outside that range the input is
// not a phone number, whatever it looks like.
const MIN_DIGITS = 8;
const MAX_DIGITS = 15;

/**
 * Turn a human-typed phone number into E.164.
 *
 * ### It refuses rather than guesses
 *
 * A national-format number — `020 7946 0958` — **cannot** be normalized
 * without knowing which country it belongs to. There is no globally correct
 * answer, and a system that picks a default silently produces numbers that
 * dial the wrong country.
 *
 * So a number with no `+` and no `defaultCallingCode` returns `ok: false`
 * with a reason naming the missing input. That is the whole value of the
 * command: an honest refusal is more useful than a confident wrong number,
 * because a wrong number fails at send time, to a customer, weeks later.
 *
 * ### Trunk prefixes are stripped only with a calling code in hand
 *
 * Many countries prefix national dialing with a `0` that is dropped when
 * calling internationally. That rule only applies once the country is known,
 * so the strip happens inside the `defaultCallingCode` branch and never to a
 * number that already carries a `+`.
 *
 * ### Extensions are extracted, not folded in
 *
 * An extension is dialed *after* the call connects. Appending it to the
 * subscriber number produces something that passes a length check and rings
 * nothing.
 *
 * ### What it does not do
 *
 * No region-by-region validation: this does not know that a UK mobile starts
 * `7` or how long a Singapore number is. It normalizes shape, and says so.
 * Full validation needs a number-plan library, which is a dependency this is
 * deliberately not taking on — `libphonenumber` is roughly half a megabyte.
 */
export class NormalizePhoneCommand extends Command<
  typeof NormalizePhoneInput,
  typeof NormalizePhoneResult
> {
  static actionVerb = 'Normalize';
  static displayName = 'Normalize Phone';

  async getInputType() {
    return NormalizePhoneInput;
  }

  protected async run(
    input: NormalizePhoneInput,
  ): Promise<NormalizePhoneResult> {
    let raw = (input.raw ?? '').trim();
    if (!raw) {
      return new NormalizePhoneResult({
        ok: false,
        e164: '',
        reason: 'No number supplied.',
      });
    }

    // Pull the extension off first, so its digits never reach the length
    // check or the subscriber number.
    let extension = '';
    let extMatch = raw.match(EXT_RE);
    if (extMatch) {
      extension = extMatch[1];
      raw = raw.slice(0, extMatch.index).trim();
    }

    let hadPlus = raw.trimStart().startsWith('+');
    // `00` is the other international prefix, used across most of Europe.
    let hadZeroZero = /^\s*00\d/.test(raw);
    let digits = raw.replace(/\D/g, '');

    if (hadZeroZero) {
      digits = digits.slice(2);
    }

    let callingCode = '';
    if (hadPlus || hadZeroZero) {
      // The number already declares its country. Nothing is stripped — a
      // leading digit here is part of the calling code, not a trunk prefix.
      callingCode = '';
    } else {
      let cc = (input.defaultCallingCode ?? '').replace(/\D/g, '');
      if (!cc) {
        return new NormalizePhoneResult({
          ok: false,
          e164: '',
          extension,
          reason:
            'National-format number with no defaultCallingCode. There is no globally correct country to assume, so this refuses rather than guessing.',
        });
      }
      // The trunk prefix rule applies only now that the country is known.
      digits = digits.replace(/^0+/, '');
      callingCode = cc;
      digits = cc + digits;
    }

    if (digits.length < MIN_DIGITS || digits.length > MAX_DIGITS) {
      return new NormalizePhoneResult({
        ok: false,
        e164: '',
        extension,
        reason: `${digits.length} digits is outside the E.164 range of ${MIN_DIGITS}–${MAX_DIGITS}. Not a phone number.`,
      });
    }

    return new NormalizePhoneResult({
      ok: true,
      e164: `+${digits}`,
      callingCode,
      extension,
      reason: extension
        ? `Normalized; extension ${extension} kept separate because it is dialed after connection.`
        : 'Normalized.',
    });
  }
}

export default NormalizePhoneCommand;
