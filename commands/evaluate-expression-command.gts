import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import { evaluateBxlSafe } from '@cardstack/bxl';
import { cardToBxlInput } from '../utils/bxl-input';
import { inputCard } from '../utils/find-card';

export class EvaluateExpressionInput extends CardDef {
  @field expression = contains(StringField, {
    description: 'BXL readable syntax unless plainJq is set.',
  });
  @field subject = linksTo(() => CardDef, {
    description: 'The card the expression reads. Its field names are the keys.',
  });
  @field plainJq = contains(BooleanField);
}

export class EvaluateExpressionResult extends CardDef {
  @field ok = contains(BooleanField);
  @field value = contains(StringField, {
    description: 'JSON encoding of the result. Scalars encode as themselves.',
  });
  @field error = contains(StringField);
}

/**
 * Evaluates a stored expression against a card and returns the result as JSON.
 *
 * A total function: a bad expression comes back as `ok: false` with the
 * compiler's own message, never as a throw, so a caller can show the author
 * what is wrong instead of failing the run.
 */
export class EvaluateExpressionCommand extends Command<
  typeof EvaluateExpressionInput,
  typeof EvaluateExpressionResult
> {
  static actionVerb = 'Evaluate';
  static displayName = 'Evaluate Expression';

  async getInputType() {
    return EvaluateExpressionInput;
  }

  protected async run(
    input: EvaluateExpressionInput,
  ): Promise<EvaluateExpressionResult> {
    let src = input.expression?.trim();
    if (!src) {
      return new EvaluateExpressionResult({
        ok: false,
        error: 'No expression supplied.',
      });
    }
    let subject = await inputCard(this.commandContext, input, 'subject');
    if (!subject) {
      return new EvaluateExpressionResult({
        ok: false,
        error:
          'No subject card supplied — an expression needs something to read.',
      });
    }

    let result = evaluateBxlSafe(src, cardToBxlInput(subject), {
      readableSyntax: !input.plainJq,
    });

    if (!result.ok) {
      return new EvaluateExpressionResult({
        ok: false,
        error: result.error?.message ?? 'Evaluation failed.',
      });
    }

    let raw = result.value?.value;
    return new EvaluateExpressionResult({
      ok: true,
      value: raw === undefined ? '' : JSON.stringify(raw),
    });
  }
}
