import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import TextAreaField from 'https://cardstack.com/base/text-area';
import enumField from 'https://cardstack.com/base/enum';

import {
  stateColor,
  stateColorOf,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { pillStyle } from './utils';

// Background-check lifecycle: not-started → pending → clear | flagged.
// This field TRACKS the status a human (or an external screening vendor's
// portal) reports — it never initiates or polls a check. Integration with a
// screening provider's API is explicitly out of scope per the product spec.
export const BACKGROUND_CHECK_STATUSES = [
  'not-started',
  'pending',
  'clear',
  'flagged',
];

export const BACKGROUND_CHECK_STATUS_LABELS: Record<string, string> = {
  'not-started': 'Not started',
  pending: 'Pending',
  clear: 'Clear',
  flagged: 'Flagged',
};

// Same Ledger palette every other status pill in the tracker draws from:
// gray for a check nobody has ordered yet, amber while the vendor works,
// green when it comes back clean, red when something needs a human look.
export const BACKGROUND_CHECK_STATUS_COLORS: Record<string, StateColor> = {
  'not-started': stateColor('slate'),
  pending: stateColor('amber'),
  clear: stateColor('green'),
  flagged: stateColor('red'),
};

export const BackgroundCheckStatusField = enumField(StringField, {
  options: BACKGROUND_CHECK_STATUSES.map((value) => ({
    value,
    label: BACKGROUND_CHECK_STATUS_LABELS[value],
  })),
  displayName: 'Background Check Status',
});

export class BackgroundCheckField extends FieldDef {
  static displayName = 'Background Check';

  @field status = contains(BackgroundCheckStatusField);
  @field provider = contains(StringField, {
    description: 'Screening vendor running the check, e.g. Checkr, Certn',
  });
  @field requestedDate = contains(DateField);
  @field completedDate = contains(DateField);
  @field notes = contains(TextAreaField, {
    description: 'Free-text detail, e.g. what was flagged and who reviewed it',
  });

  static embedded = class Embedded extends Component<typeof this> {
    get statusColor() {
      return stateColorOf(
        BACKGROUND_CHECK_STATUS_COLORS,
        this.args.model?.status,
      );
    }

    get statusPillStyle() {
      return pillStyle(this.statusColor);
    }

    get statusLabel(): string {
      let status = this.args.model?.status;
      return (
        (status && BACKGROUND_CHECK_STATUS_LABELS[status]) || 'Not started'
      );
    }

    <template>
      <div class='background-check'>
        <div class='bc-head'>
          <span class='pill' style={{this.statusPillStyle}}>
            <span class='pill-dot'></span>{{this.statusLabel}}
          </span>
          {{#if @model.provider}}
            <span class='bc-provider'>via {{@model.provider}}</span>
          {{/if}}
        </div>
        {{#if @model.requestedDate}}
          <dl class='bc-dates'>
            <div>
              <dt>Requested</dt>
              <dd><@fields.requestedDate /></dd>
            </div>
            {{#if @model.completedDate}}
              <div>
                <dt>Completed</dt>
                <dd><@fields.completedDate /></dd>
              </div>
            {{/if}}
          </dl>
        {{/if}}
        {{#if @model.notes}}
          <p class='bc-notes'>{{@model.notes}}</p>
        {{/if}}
      </div>
      <style scoped>
        .background-check {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          color: var(--foreground);
        }
        .bc-head {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .pill {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          padding: 0.18em 0.5em;
          border-radius: 0.1875rem;
          white-space: nowrap;
        }
        .pill-dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: currentColor;
          flex: none;
        }
        .bc-provider {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .bc-dates {
          margin: 0;
          display: flex;
          flex-wrap: wrap;
          gap: 0.15rem var(--boxel-sp);
        }
        .bc-dates > div {
          display: flex;
          gap: 0.3rem;
          min-width: 0;
        }
        .bc-dates dt {
          flex: none;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .bc-dates dd {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .bc-notes {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get statusColor() {
      return stateColorOf(
        BACKGROUND_CHECK_STATUS_COLORS,
        this.args.model?.status,
      );
    }

    get statusPillStyle() {
      return pillStyle(this.statusColor);
    }

    get statusLabel(): string {
      let status = this.args.model?.status;
      return (
        (status && BACKGROUND_CHECK_STATUS_LABELS[status]) || 'Not started'
      );
    }

    <template>
      <span class='bc-atom' style={{this.statusPillStyle}}>
        <span class='bc-atom-dot'></span>{{this.statusLabel}}
      </span>
      <style scoped>
        .bc-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          padding: 0.1em 0.4em;
          border-radius: 0.1875rem;
          white-space: nowrap;
        }
        .bc-atom-dot {
          width: 0.3125rem;
          height: 0.3125rem;
          border-radius: 50%;
          background-color: currentColor;
          flex: none;
        }
      </style>
    </template>
  };
}
