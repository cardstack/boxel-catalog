import { Component } from 'https://cardstack.com/base/card-api';
import DateTimeField from 'https://cardstack.com/base/datetime';
import CalendarPlusIcon from '@cardstack/boxel-icons/calendar-plus';

const UNITS: [limitSeconds: number, divisorSeconds: number, suffix: string][] =
  [
    [60, 1, 's'],
    [3600, 60, 'm'],
    [86400, 3600, 'h'],
    [604800, 86400, 'd'],
    [2629800, 604800, 'w'],
    [31557600, 2629800, 'mo'],
    [Infinity, 31557600, 'y'],
  ];

/** "3d ago" / "in 2h" / "just now". Sign-aware so an anomalous future stamp is visible rather than clamped. */
export function relativeStamp(
  value: Date | null | undefined,
): string | undefined {
  if (!value || Number.isNaN(value.getTime())) {
    return undefined;
  }
  let diffSeconds = (Date.now() - value.getTime()) / 1000;
  let past = diffSeconds >= 0;
  let magnitude = Math.abs(diffSeconds);
  if (magnitude < 60) {
    return 'just now';
  }
  for (let [limit, divisor, suffix] of UNITS) {
    if (magnitude < limit) {
      let n = Math.floor(magnitude / divisor);
      return past ? `${n}${suffix} ago` : `in ${n}${suffix}`;
    }
  }
  return undefined;
}

/** "26 Aug 2026, 14:41", the audit-precision form. */
export function absoluteStamp(
  value: Date | null | undefined,
): string | undefined {
  if (!value || Number.isNaN(value.getTime())) {
    return undefined;
  }
  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(value);
}

/**
 * When the record came into existence. Write-once by convention: stamped at
 * creation by the command or author that made the record, never rewritten. The
 * block renders the fact; a FieldDef cannot see writes, so it does not enforce
 * the discipline. Serializes exactly like DateTimeField, so an existing
 * `createdAt: DateTimeField` upgrades in place with no instance migration.
 */
export class CreatedAtField extends DateTimeField {
  static displayName = 'Created At';
  static icon = CalendarPlusIcon;

  static embedded = class Embedded extends Component<typeof this> {
    get absolute() {
      return absoluteStamp(this.args.model);
    }
    get relative() {
      return relativeStamp(this.args.model);
    }
    <template>
      {{#if this.absolute}}
        <span class='stamp'>{{this.absolute}}
          <span class='relative'>({{this.relative}})</span></span>
      {{else}}
        <span class='unset' aria-label='No creation time'>—</span>
      {{/if}}
      <style scoped>
        .stamp {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground, var(--boxel-dark));
        }
        .relative,
        .unset {
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get absolute() {
      return absoluteStamp(this.args.model);
    }
    get relative() {
      return relativeStamp(this.args.model);
    }
    <template>
      {{#if this.relative}}
        <span
          class='stamp-atom'
          title={{this.absolute}}
        >{{this.relative}}</span>
      {{else}}
        <span class='unset' aria-label='No creation time'>—</span>
      {{/if}}
      <style scoped>
        .stamp-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
        .unset {
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default CreatedAtField;
