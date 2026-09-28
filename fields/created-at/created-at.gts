import { Component } from 'https://cardstack.com/base/card-api';
import DateTimeField from 'https://cardstack.com/base/datetime';
import CalendarPlusIcon from '@cardstack/boxel-icons/calendar-plus';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { RelativeTime } from '@cardstack/pretui/components/relative-time';

import { validDate } from '../../utils/valid-date';

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

/** Within a minute either way reads "just now": clock skew, not an anomaly. */
function isJustNow(value: Date): boolean {
  return Math.abs(Date.now() - value.getTime()) < 60000;
}

/** "3d ago" / "in 2h" / "just now". Anything within a minute either way reads "just now" (clock skew, not an anomaly); beyond that a future stamp renders as "in …" so it stays visible rather than clamped. */
export function relativeStamp(
  value: Date | null | undefined,
): string | undefined {
  let date = validDate(value);
  if (!date) {
    return undefined;
  }
  if (isJustNow(date)) {
    return 'just now';
  }
  let diffSeconds = (Date.now() - date.getTime()) / 1000;
  let past = diffSeconds >= 0;
  let magnitude = Math.abs(diffSeconds);
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
  let date = validDate(value);
  if (!date) {
    return undefined;
  }
  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date);
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
    get stamp() {
      return validDate(this.args.model);
    }
    get justNow() {
      return this.stamp ? isJustNow(this.stamp) : false;
    }
    <template>
      {{#if this.stamp}}
        <span class='stamp'>
          <FormatDate
            @date={{this.stamp}}
            @day='numeric'
            @month='short'
            @year='numeric'
            @hour='2-digit'
            @minute='2-digit'
            @hour12={{false}}
          />
          <span class='relative'>({{#if this.justNow}}just now{{else}}<RelativeTime
                @date={{this.stamp}}
                @format='narrow'
                @numeric='always'
              />{{/if}})</span>
        </span>
      {{else}}
        <span class='unset' aria-label='No creation time'>—</span>
      {{/if}}
      <style scoped>
        .stamp {
          font-size: var(--boxel-font-size-sm);
        }
        .relative,
        .unset {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get stamp() {
      return validDate(this.args.model);
    }
    get justNow() {
      return this.stamp ? isJustNow(this.stamp) : false;
    }
    get absolute() {
      return absoluteStamp(this.args.model);
    }
    <template>
      {{#if this.stamp}}
        {{#if this.justNow}}
          <span class='stamp-atom' title={{this.absolute}}>just now</span>
        {{else}}
          <RelativeTime
            class='stamp-atom'
            title={{this.absolute}}
            @date={{this.stamp}}
            @format='narrow'
            @numeric='always'
          />
        {{/if}}
      {{else}}
        <span class='unset' aria-label='No creation time'>—</span>
      {{/if}}
      <style scoped>
        .stamp-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .unset {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default CreatedAtField;
