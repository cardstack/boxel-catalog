import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import CalendarDueIcon from '@cardstack/boxel-icons/calendar-due';
import { FormatDate } from '@cardstack/pretui/components/format-date';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { dueDays } from '@cardstack/catalog/fields/due-date/due-date';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export type DueWindowState =
  | 'not_open'
  | 'open'
  | 'due_soon'
  | 'overdue'
  | 'closed';

export const DUE_WINDOW_HUES: Record<DueWindowState, Hue> = {
  not_open: 'slate',
  open: 'teal',
  due_soon: 'amber',
  overdue: 'red',
  closed: 'slate',
};

const LABELS: Record<DueWindowState, string> = {
  not_open: 'Not open yet',
  open: 'Open',
  due_soon: 'Due soon',
  overdue: 'Overdue',
  closed: 'Closed',
};

/**
 * The three moments of submitted work: when it opens, when it is due, and
 * when the drop box shuts for good. `hardCloseAt` is optional — a consumer
 * that derives the close from a policy leaves it empty, so one policy edit
 * moves every close.
 *
 * The state (`open` / `due soon` / `overdue` / `closed`) is derived from the
 * clock, never stored — reuses `dueDays()` from the shared Due Date block so
 * "due soon" means the same three days everywhere in the catalog.
 */
export class DueWindowField extends FieldDef {
  static displayName = 'Due Window';
  static icon = CalendarDueIcon;

  @field opensAt = contains(DateTimeField);
  @field dueAt = contains(DateTimeField);
  @field hardCloseAt = contains(DateTimeField, {
    description: 'Leave empty when a policy decides the close.',
  });

  @field summary = contains(StringField, {
    computeVia: function (this: DueWindowField) {
      return this.dueAt ? `Due ${fmt(this.dueAt)}` : 'No due date';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model);
    }
    get label() {
      return LABELS[this.state];
    }
    get hue() {
      return DUE_WINDOW_HUES[this.state];
    }
    <template>
      <span class='dw'>
        <span class='dw-due'>{{@model.summary}}</span>
        <StatePill @label={{this.label}} @hue={{this.hue}} @dot={{true}} />
        {{#if @model.hardCloseAt}}
          <span class='dw-close'>closes
            <FormatDate
              @date={{@model.hardCloseAt}}
              @weekday='short'
              @month='short'
              @day='numeric'
              @hour='numeric'
              @minute='2-digit'
            /></span>
        {{/if}}
      </span>
      <style scoped>
        .dw {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        .dw-due {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .dw-close {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get state() {
      return dueWindowState(this.args.model);
    }
    <template>
      <StatePill
        @label={{if @model.dueAt (fmtShort @model.dueAt) '—'}}
        @hue={{lookupHue this.state}}
        @chrome={{eqState this.state 'open'}}
      />
    </template>
  };
}

export function dueWindowState(
  w: Partial<DueWindowField> | null | undefined,
  now: Date = new Date(),
): DueWindowState {
  if (!w?.dueAt) return 'open';
  let t = now.getTime();
  if (w.opensAt && t < new Date(w.opensAt).getTime()) return 'not_open';
  if (w.hardCloseAt && t > new Date(w.hardCloseAt).getTime()) return 'closed';
  let days = dueDays(new Date(w.dueAt));
  if (days == null) return 'open';
  if (days < 0) return 'overdue';
  if (days <= 3) return 'due_soon';
  return 'open';
}

export function dueWindowLabel(state: DueWindowState): string {
  return LABELS[state];
}

function lookupHue(state: DueWindowState): Hue {
  return DUE_WINDOW_HUES[state];
}

function eqState(a: DueWindowState, b: DueWindowState): boolean {
  return a === b;
}

export function fmt(d: Date | string | null | undefined): string {
  if (!d) return '';
  return new Date(d).toLocaleString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function fmtShort(d: Date | string | null | undefined): string {
  if (!d) return '';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}

export default DueWindowField;
