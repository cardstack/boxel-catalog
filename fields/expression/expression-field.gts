import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { evaluateBxlSafe, prepareBxlSafe } from '@cardstack/bxl';
import FunctionIcon from '@cardstack/boxel-icons/function';
import { cardToBxlInput } from '../../utils/bxl-input';

/**
 * A BXL expression stored as data.
 *
 * `expression()` from `@cardstack/bxl` already covers the code-time case — a
 * module author writing `computeVia: expression('Amount * 12')`. This covers
 * the other one: an expression an author types into an instance and the card
 * evaluates at runtime. Compilation errors surface as a field rather than a
 * render failure, so a half-typed formula never breaks the card it sits on.
 */
export class ExpressionField extends FieldDef {
  static displayName = 'Expression';
  static icon = FunctionIcon;

  @field source = contains(StringField, {
    description:
      'BXL readable syntax, e.g. IF(Recurring, Amount * 12, Amount). Field ' +
      'references are capitalised — `Amount` reads the field `amount`. A ' +
      'lowercase bare word parses as a zero-argument function and fails at ' +
      'evaluation, having compiled clean. `.amount` is the exact jq form.',
  });

  @field plainJq = contains(BooleanField, {
    description:
      'Skip readable-syntax compilation and hand the source straight to jq.',
  });

  // Compile-time only — see `evaluate`.
  @field error = contains(StringField, {
    computeVia: function (this: ExpressionField) {
      let src = this.source?.trim();
      if (!src) {
        return '';
      }
      try {
        let result = prepareBxlSafe(src, { readableSyntax: !this.plainJq });
        return result.ok ? '' : (result.error?.message ?? 'Invalid expression');
      } catch (e) {
        return e instanceof Error ? e.message : 'Invalid expression';
      }
    },
  });

  @field isValid = contains(BooleanField, {
    computeVia: function (this: ExpressionField) {
      return Boolean(this.source?.trim()) && !this.error;
    },
  });

  // `error` only proves the expression compiles. An unresolved name is a
  // runtime fault, so anything that reports success to a reader has to
  // evaluate rather than trust the compile.
  evaluate(subject: object): {
    ok: boolean;
    value: unknown;
    error: string;
  } {
    let src = this.source?.trim();
    if (!src) {
      return { ok: false, value: undefined, error: 'No expression.' };
    }
    try {
      let result = evaluateBxlSafe(src, cardToBxlInput(subject), {
        readableSyntax: !this.plainJq,
      });
      return result.ok
        ? { ok: true, value: result.value?.value, error: '' }
        : {
            ok: false,
            value: undefined,
            error: result.error?.message ?? 'Evaluation failed.',
          };
    } catch (e) {
      return {
        ok: false,
        value: undefined,
        error: e instanceof Error ? e.message : 'Evaluation failed.',
      };
    }
  }

  // Total, for a computeVia that must not tear down the card mid-render.
  evaluateAgainst(subject: object): unknown {
    return this.evaluate(subject).value;
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      {{#if @model.source}}
        <div class='expr'>
          <code class='src'>{{@model.source}}</code>
          {{#if @model.error}}
            <p class='err'>{{@model.error}}</p>
          {{/if}}
        </div>
      {{else}}
        <span class='empty'>No expression</span>
      {{/if}}
      <style scoped>
        .expr {
          display: grid;
          gap: var(--boxel-sp-xxs, 0.25rem);
        }
        .src {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: 0.8125rem;
          padding: var(--boxel-sp-xxxs, 0.125rem) var(--boxel-sp-xxs, 0.25rem);
          border: 1px solid var(--boxel-border-color, #d8dee5);
          border-radius: var(--boxel-border-radius-sm, 4px);
          overflow-wrap: anywhere;
        }
        .err {
          margin: 0;
          font-size: 0.75rem;
          color: var(--boxel-danger, #a83f3f);
        }
        .empty {
          font-style: italic;
          color: var(--boxel-450, #6b7683);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='edit'>
        <@fields.source />
        {{#if @model.error}}
          <p class='err'>{{@model.error}}</p>
        {{else if @model.isValid}}
          <p class='ok'>Compiles.</p>
        {{/if}}
      </div>
      <style scoped>
        .edit {
          display: grid;
          gap: var(--boxel-sp-xxs, 0.25rem);
        }
        .err,
        .ok {
          margin: 0;
          font-size: 0.75rem;
        }
        .err {
          color: var(--boxel-danger, #a83f3f);
        }
        .ok {
          color: var(--boxel-success, #3f7a5e);
        }
      </style>
    </template>
  };
}
