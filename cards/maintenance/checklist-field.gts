import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import UrlField from '@cardstack/base/url';
import QuantityField from '@cardstack/catalog/fields/quantity/quantity';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { eq } from '@cardstack/boxel-ui/helpers';
import { htmlSafe } from '@ember/template';

import {
  ChecklistItemKindField,
  ChecklistResultField,
  CHECKLIST_RESULT_HUE,
} from './maintenance-vocabulary';
import { checklistStats, measureDelta } from './utils/maintenance';

/**
 * One step of a procedure. `kind` decides what "done" means:
 * check (tick), measure (a number inside expected ± tolerance — out of
 * tolerance auto-fails), photo (an image URL), text, signature (a name).
 */
export class ChecklistItemField extends FieldDef {
  static displayName = 'Checklist Item';

  @field label = contains(StringField);
  @field kind = contains(ChecklistItemKindField);
  @field required = contains(BooleanField);
  @field expectedValue = contains(QuantityField, {
    description: 'measure items: the target value',
    configuration: { options: { min: -Infinity } },
  });
  @field unit = contains(StringField);
  @field tolerance = contains(QuantityField, {
    description: 'measure items: ± allowed around the expected value',
  });
  @field result = contains(ChecklistResultField);
  @field value = contains(StringField, {
    description: 'the measured number, the typed text, or the signer name',
  });
  @field photoUrl = contains(UrlField);
  @field note = contains(StringField);
  @field completedByName = contains(StringField);
  @field completedAt = contains(DateTimeField);

  @field delta = contains(NumberField, {
    computeVia: function (this: ChecklistItemField) {
      return measureDelta(this);
    },
  });

  @field isOutOfTolerance = contains(BooleanField, {
    computeVia: function (this: ChecklistItemField) {
      let d = measureDelta(this);
      return d != null && d !== 0;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: ChecklistItemField) {
      return this.label ?? 'Untitled step';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return (
        CHECKLIST_RESULT_HUE[this.args.model.result ?? 'pending'] ?? 'slate'
      );
    }
    get expectation() {
      let m = this.args.model;
      if (m.kind !== 'measure' || m.expectedValue == null) return undefined;
      let tol = m.tolerance ? ` ± ${m.tolerance}` : '';
      return `${m.expectedValue}${tol} ${m.unit ?? ''}`.trim();
    }
    <template>
      <div class='ci {{if @model.isOutOfTolerance "ci--oot"}}'>
        <StatePill
          @label={{if @model.result @model.result 'pending'}}
          @hue={{this.hue}}
        />
        <span class='ci-label'>{{@model.label}}{{#if @model.required}}<span
              class='ci-req'
              title='required'
            >*</span>{{/if}}</span>
        {{#if (eq @model.kind 'measure')}}
          <span class='ci-measure'>
            {{#if @model.value}}<strong>{{@model.value}}
                {{@model.unit}}</strong>{{/if}}
            {{#if this.expectation}}<span
                class='ci-exp'
              >({{this.expectation}})</span>{{/if}}
            {{#if @model.isOutOfTolerance}}<span class='ci-delta'>{{if
                  (this.positive @model.delta)
                  '+'
                }}{{@model.delta}}</span>{{/if}}
          </span>
        {{else if @model.value}}
          <span class='ci-measure'>{{@model.value}}</span>
        {{/if}}
      </div>
      <style scoped>
        .ci {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .ci-label {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ci-req {
          color: var(--destructive, var(--foreground));
          margin-left: 2px;
        }
        .ci-measure {
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .ci-measure strong {
          color: var(--foreground);
        }
        .ci-delta {
          margin-left: var(--boxel-sp-4xs);
          font-weight: 600;
          color: var(--destructive, var(--foreground));
        }
      </style>
    </template>
    positive = (n?: number | null) => (n ?? 0) > 0;
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ci-atom'>{{@model.label}}</span>
      <style scoped>
        .ci-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

/**
 * The steps that define "done" for a procedure, with their results.
 *
 * Lives twice by design: as a TEMPLATE on a Maintenance Plan (no results)
 * and as a deep COPY on every Work Order generated from it. Results never
 * flow back to the template — `cloneChecklistItems` in utils/maintenance
 * makes the copy. Completion maths (`checklistStats`) is shared with the
 * Checklist Runner and Complete Work Order so they agree on "complete".
 *
 * Generic (l03): onboarding checklists, publish checklists and audit
 * procedures can carry it; the Checklist Runner component executes any of
 * them.
 */
export class ChecklistField extends FieldDef {
  static displayName = 'Checklist';
  static icon = ClipboardCheckIcon;

  @field title = contains(StringField);
  @field items = containsMany(ChecklistItemField);

  @field total = contains(NumberField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).total;
    },
  });
  @field done = contains(NumberField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).done;
    },
  });
  @field failedCount = contains(NumberField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).failedCount;
    },
  });
  @field requiredRemaining = contains(NumberField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).requiredRemaining;
    },
  });
  @field completionPercent = contains(NumberField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).completionPercent;
    },
  });
  @field isComplete = contains(BooleanField, {
    computeVia: function (this: ChecklistField) {
      return checklistStats(this.items).isComplete;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get fillStyle() {
      return htmlSafe(`width: ${this.args.model.completionPercent ?? 0}%`);
    }
    <template>
      <div class='cl'>
        <header class='cl-head'>
          <ClipboardCheckIcon class='cl-icon' />
          <span class='cl-title'>{{if
              @model.title
              @model.title
              'Checklist'
            }}</span>
          <span class='cl-count'>{{@model.done}} / {{@model.total}}</span>
          {{#if @model.requiredRemaining}}
            <span class='cl-req'>{{@model.requiredRemaining}}
              required left</span>
          {{/if}}
          {{#if @model.failedCount}}
            <span class='cl-fail'>{{@model.failedCount}} failed</span>
          {{/if}}
        </header>
        <div
          class='cl-bar'
          role='progressbar'
          aria-valuenow={{@model.completionPercent}}
          aria-valuemin='0'
          aria-valuemax='100'
        >
          <span class='cl-fill' style={{this.fillStyle}}></span>
        </div>
        <ul class='cl-items'>
          {{#each @fields.items as |Item|}}
            <li><Item @format='embedded' /></li>
          {{/each}}
        </ul>
      </div>
      <style scoped>
        .cl {
          display: grid;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .cl-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .cl-icon {
          width: 1rem;
          height: 1rem;
          color: var(--muted-foreground);
        }
        .cl-title {
          font-weight: 600;
          color: var(--foreground);
        }
        .cl-count {
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .cl-req,
        .cl-fail {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .cl-fail {
          color: var(--destructive, var(--foreground));
        }
        .cl-bar {
          height: 4px;
          border-radius: 2px;
          background: var(--muted);
          overflow: hidden;
        }
        .cl-fill {
          display: block;
          height: 100%;
          background: var(--primary);
        }
        .cl-items {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='cl-atom'>{{if @model.title @model.title 'Checklist'}}
        ·
        {{@model.done}}/{{@model.total}}</span>
      <style scoped>
        .cl-atom {
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

export default ChecklistField;
