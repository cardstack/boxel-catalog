import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import ArrowRightLeftIcon from '@cardstack/boxel-icons/arrow-right-left';
import { StatePill } from '@cardstack/catalog/components/state-pill';

import { CustodyKindField } from './maintenance-vocabulary';
import { absoluteStamp } from './utils/relative-time';
import type { Hue } from '@cardstack/catalog/components/state-pill';

const KIND_HUE: Record<string, Hue> = {
  'check-out': 'teal',
  'check-in': 'green',
  transfer: 'blue',
  loan: 'amber',
  return: 'green',
};

/**
 * One custody event — who handed what to whom, when, in what condition.
 *
 * Custody is append-only: the Transfer Custody command writes an entry here
 * AND rewrites the record's current owner (Record Owner, via Assign Owner).
 * Names are stamped strings (a FieldDef cannot `linksTo`); ids are kept for
 * joins. Generic: an asset, a library book, a company car, a key.
 */
export class CustodyTransferField extends FieldDef {
  static displayName = 'Custody Transfer';
  static icon = ArrowRightLeftIcon;

  @field kind = contains(CustodyKindField);
  @field fromName = contains(StringField);
  @field fromTeamName = contains(StringField);
  @field toId = contains(StringField, {
    description: 'Card id of the receiving Employee (empty for a team).',
  });
  @field toName = contains(StringField);
  @field toTeamName = contains(StringField);
  @field at = contains(DateTimeField);
  @field dueBack = contains(DateField, {
    description: 'Loans only — when it must come back.',
  });
  @field conditionCode = contains(StringField, {
    description: 'Condition grade code at hand-over, e.g. A / B / C.',
  });
  @field note = contains(StringField);

  @field label = contains(StringField, {
    computeVia: function (this: CustodyTransferField) {
      let to = this.toName ?? this.toTeamName ?? '—';
      let from = this.fromName ?? this.fromTeamName;
      switch (this.kind) {
        case 'check-out':
          return `Checked out to ${to}`;
        case 'check-in':
          return `Checked in${from ? ` from ${from}` : ''}`;
        case 'loan':
          return `On loan to ${to}`;
        case 'return':
          return `Returned${from ? ` by ${from}` : ''}`;
        case 'transfer':
          return `${from ?? '—'} → ${to}`;
        default:
          return 'Custody event';
      }
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return KIND_HUE[this.args.model.kind ?? ''] ?? 'slate';
    }
    get when() {
      return absoluteStamp(this.args.model.at ?? undefined);
    }
    <template>
      <div class='ct'>
        <StatePill
          @label={{if @model.kind @model.kind 'event'}}
          @hue={{this.hue}}
        />
        <span class='ct-label'>{{@model.label}}</span>
        <span class='ct-meta'>
          {{#if this.when}}{{this.when}}{{/if}}
          {{#if @model.dueBack}}· due back
            <@fields.dueBack @format='atom' />{{/if}}
          {{#if @model.conditionCode}}· condition
            {{@model.conditionCode}}{{/if}}
        </span>
      </div>
      <style scoped>
        .ct {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
        }
        .ct-label {
          color: var(--foreground);
          font-weight: 500;
        }
        .ct-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ct-atom'>{{@model.label}}</span>
      <style scoped>
        .ct-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    <template>
      {{! Custody is written by the Transfer Custody command so the trail stays
          truthful; edit shows the facts, not inputs. }}
      <div class='ct-edit'>
        <span class='ct-current'>{{@model.label}}</span>
        <p class='ct-note'>Change custody with the Transfer Custody action so
          the owner, the status and the trail all move together.</p>
      </div>
      <style scoped>
        .ct-edit {
          display: grid;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
        }
        .ct-current {
          font-weight: 500;
        }
        .ct-note {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default CustodyTransferField;
