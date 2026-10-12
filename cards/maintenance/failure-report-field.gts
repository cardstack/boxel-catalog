import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import ZapOffIcon from '@cardstack/boxel-icons/zap-off';

/**
 * Why a thing failed and what fixed it — symptom, cause, remedy, a failure
 * code, and whether the asset was down. Raise Work Order reads `assetDown`
 * to take the asset out of service and open an unplanned Downtime; Complete
 * Work Order requires `remedy` on corrective work. `codeText` is the v1
 * taxonomy (a Failure Code card is v1.1); `recurrenceOfId` points at the
 * previous work order with the same code on the same asset when the
 * technician confirms it is the same fault again.
 */
export class FailureReportField extends FieldDef {
  static displayName = 'Failure Report';
  static icon = ZapOffIcon;

  @field symptom = contains(TextAreaField);
  @field cause = contains(TextAreaField);
  @field remedy = contains(TextAreaField);
  @field codeText = contains(StringField, {
    description:
      'Failure code — mechanical / electrical / control / operator / external / wear / unknown.',
  });
  @field detectedAt = contains(DateTimeField);
  @field operatorError = contains(BooleanField);
  @field assetDown = contains(BooleanField, {
    description: 'The asset cannot operate until fixed.',
  });
  @field recurrenceOfId = contains(StringField, {
    description: 'Card id of the earlier Work Order this repeats.',
  });

  @field label = contains(StringField, {
    computeVia: function (this: FailureReportField) {
      let head = this.symptom?.split('\n')[0]?.trim();
      if (!head)
        return this.codeText
          ? `Failure · ${this.codeText}`
          : 'No failure recorded';
      return this.codeText ? `${head} · ${this.codeText}` : head;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='fr'>
        <header class='fr-head'>
          <ZapOffIcon class='fr-icon' />
          <span class='fr-label'>{{@model.label}}</span>
          {{#if @model.assetDown}}<span class='fr-down'>asset down</span>{{/if}}
          {{#if @model.recurrenceOfId}}<span class='fr-rec'>repeat fault</span>{{/if}}
        </header>
        <dl class='fr-body'>
          {{#if @model.symptom}}<dt>Symptom</dt><dd
            >{{@model.symptom}}</dd>{{/if}}
          {{#if @model.cause}}<dt>Cause</dt><dd>{{@model.cause}}</dd>{{/if}}
          {{#if @model.remedy}}<dt>Remedy</dt><dd>{{@model.remedy}}</dd>{{/if}}
        </dl>
      </div>
      <style scoped>
        .fr {
          display: grid;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .fr-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .fr-icon {
          width: 1rem;
          height: 1rem;
          color: var(--muted-foreground);
        }
        .fr-label {
          font-weight: 600;
          color: var(--foreground);
        }
        .fr-down {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--destructive, var(--foreground));
        }
        .fr-rec {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .fr-body {
          margin: 0;
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .fr-body dt {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding-top: 2px;
        }
        .fr-body dd {
          margin: 0;
          color: var(--foreground);
          white-space: pre-wrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='fr-atom'>{{@model.label}}</span>
      <style scoped>
        .fr-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

export default FailureReportField;
