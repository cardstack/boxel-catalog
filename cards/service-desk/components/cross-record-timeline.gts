import GlimmerComponent from '@glimmer/component';

import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';

// Shared by the timestamp field blocks (created-at-field, updated-at-field).

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
function relativeStamp(value: Date | null | undefined): string | undefined {
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

/** "26 Aug 2026, 14:41" — the audit-precision form. */
function absoluteStamp(value: Date | null | undefined): string | undefined {
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

export interface TimelineEvent {
  at: Date | string | undefined;
  label: string;
  /** Who did it — a person, or "policy <name>" (automation is attributed). */
  by?: string;
  /** Semantic hue for the marker dot. */
  intent?: Hue;
}

interface Signature {
  Args: {
    /**
     * Events from ACROSS the linked graph — the case plus its replies,
     * escalations, SLA pauses, tasks — merged by the CALLER (only the caller
     * knows which cards relate). This component owns the drawing: one
     * chronological stream, newest first, day-grouped feel via relative
     * stamps.
     */
    events: TimelineEvent[];
    emptyLabel?: string;
  };
  Element: HTMLElement;
}

/**
 * Cross-Record Timeline — merges the EVENTS OF LINKED RECORDS
 * into one stream. Deliberately distinct from the Audit desk's Audit
 * Timeline, which renders ONE subject's append-only Audit Entry trail; this
 * one reads the linked graph's own records. Both readMes cross-reference
 * this split.
 */
export class CrossRecordTimeline extends GlimmerComponent<Signature> {
  get sorted() {
    return [...(this.args.events ?? [])]
      .filter((e) => e && e.at)
      .sort(
        (a, b) =>
          new Date(b.at as any).getTime() - new Date(a.at as any).getTime(),
      );
  }

  when = (e: TimelineEvent) => relativeStamp(new Date(e.at as any));
  whenFull = (e: TimelineEvent) => absoluteStamp(new Date(e.at as any));
  dotStyle = (e: TimelineEvent) => {
    let c = stateColor(e.intent ?? 'slate');
    return `--dot: ${c.ring};`;
  };

  <template>
    {{#if this.sorted.length}}
      <ol class='crt' ...attributes>
        {{#each this.sorted as |e|}}
          <li class='crt-row' style={{this.dotStyle e}}>
            <span class='crt-dot' aria-hidden='true'></span>
            <span class='crt-when' title='{{this.whenFull e}}'>{{this.when
                e
              }}</span>
            <span class='crt-body'>
              {{e.label}}
              {{#if e.by}}<span class='crt-by'>· {{e.by}}</span>{{/if}}
            </span>
          </li>
        {{/each}}
      </ol>
    {{else}}
      <p class='crt-empty'>{{if
          @emptyLabel
          @emptyLabel
          'Nothing has happened yet.'
        }}</p>
    {{/if}}
    <style scoped>
      .crt {
        margin: 0;
        padding: 0;
        list-style: none;
        display: flex;
        flex-direction: column;
      }
      .crt-row {
        position: relative;
        display: grid;
        grid-template-columns: 0.75rem 5.5rem 1fr;
        gap: var(--boxel-sp-xs);
        align-items: baseline;
        padding: var(--boxel-sp-4xs) 0;
      }
      /* the rail */
      .crt-row::before {
        content: '';
        position: absolute;
        left: 0.3125rem;
        top: 0;
        bottom: 0;
        width: 1px;
        background: var(--border, var(--boxel-border-color));
      }
      .crt-row:first-child::before {
        top: 50%;
      }
      .crt-row:last-child::before {
        bottom: 50%;
      }
      .crt-dot {
        position: relative;
        z-index: 1;
        width: 0.5rem;
        height: 0.5rem;
        margin-top: 0.125rem;
        border-radius: 50%;
        background: var(--dot);
        align-self: center;
      }
      .crt-when {
        font-family: var(--font-mono, var(--boxel-monospace-font-family));
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
        white-space: nowrap;
      }
      .crt-body {
        font-size: var(--boxel-font-size-sm);
        min-width: 0;
      }
      .crt-by {
        color: var(--muted-foreground, var(--boxel-450));
        font-size: var(--boxel-font-size-xs);
      }
      .crt-empty {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
        font-style: italic;
      }
    </style>
  </template>
}

export default CrossRecordTimeline;
