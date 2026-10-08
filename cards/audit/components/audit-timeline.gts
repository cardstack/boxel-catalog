import GlimmerComponent from '@glimmer/component';
import { eq } from '@cardstack/boxel-ui/helpers';
import HistoryIcon from '@cardstack/boxel-icons/history';

import { StatePill } from '@cardstack/catalog/components/state-pill';
// Labels and hues from the vocabulary module, not from the AuditEntry card:
// the timeline renders inside cards the entry module may itself reach, and a
// second copy of the map is how a component comes to show a raw value where a
// person expects a sentence.
import {
  auditActionHue,
  auditActionLabel,
} from '../utils/audit-action-vocabulary';
import type { Hue } from '@cardstack/catalog/components/state-pill';

// Structural rather than importing AuditEntry: the timeline is rendered from
// inside cards that the entry module may itself reach, and a type-only shape
// keeps the module graph acyclic.
interface EntryLike {
  id?: string | null;
  action?: string | null;
  occurredAt?: Date | null;
  doneBy?: { name?: string | null } | null;
  subjectTitle?: string | null;
  note?: string | null;
  conditions?: string | null;
}

interface Signature {
  Args: {
    entries?: readonly (EntryLike | undefined)[] | null;
    /**
     * Anything after this moment is marked as having happened after sign-off.
     * A report signed on the 3rd and edited on the 5th must say so.
     */
    signedOffAt?: Date | null;
    /** Cap the rows; the caller opens the full trail for more. */
    limit?: number;
    emptyMessage?: string;
  };
  Element: HTMLElement;
}

interface Day {
  key: string;
  label: string;
  rows: Row[];
}

interface Row {
  key: string;
  label: string;
  time: string;
  who: string | null;
  subject: string | null;
  note: string | null;
  conditions: string | null;
  afterSignOff: boolean;
  hue: Hue;
}

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function timeOf(d: Date): string {
  return d.toISOString().slice(11, 16);
}

/**
 * The append-only trail, read back: what happened to a record, newest first,
 * grouped by day, with anything after sign-off called out.
 *
 * **It renders `subjectTitle`, not the linked subject's current name.** An
 * entry records what the thing was called when the decision was made, which
 * is the whole point of the snapshot the Audit Entry block keeps — reading
 * through the link would quietly rewrite history every time something is
 * renamed.
 *
 * The changed-since-sign-off marker is the one piece of judgement here. A
 * trail that treats every entry alike makes the reader scan dates to answer
 * the only question an external auditor actually asks.
 */
export class AuditTimeline extends GlimmerComponent<Signature> {
  get rows(): Row[] {
    let entries = (this.args.entries ?? []).filter(Boolean) as EntryLike[];
    let signed = this.args.signedOffAt ?? null;
    let sorted = [...entries].sort((a, b) => {
      let at = a.occurredAt ? a.occurredAt.getTime() : 0;
      let bt = b.occurredAt ? b.occurredAt.getTime() : 0;
      return bt - at;
    });
    let limited =
      typeof this.args.limit === 'number'
        ? sorted.slice(0, this.args.limit)
        : sorted;
    return limited.map((e, i) => {
      let when = e.occurredAt ?? null;
      return {
        key: e.id ?? `entry-${i}`,
        label: auditActionLabel(e.action),
        time: when ? timeOf(when) : '',
        who: e.doneBy?.name ?? null,
        subject: e.subjectTitle ?? null,
        note: e.note ?? null,
        conditions: e.conditions ?? null,
        afterSignOff: Boolean(
          signed && when && when.getTime() > signed.getTime(),
        ),
        hue: auditActionHue(e.action),
      };
    });
  }

  get days(): Day[] {
    let entries = (this.args.entries ?? []).filter(Boolean) as EntryLike[];
    let byRow = new Map<string, EntryLike>();
    entries.forEach((e, i) => byRow.set(e.id ?? `entry-${i}`, e));
    let out: Day[] = [];
    for (let row of this.rows) {
      let entry = byRow.get(row.key);
      let when = entry?.occurredAt ?? null;
      let key = when ? dayKey(when) : 'undated';
      let day = out.find((d) => d.key === key);
      if (!day) {
        day = {
          key,
          label: when ? key : 'Undated',
          rows: [],
        };
        out.push(day);
      }
      day.rows.push(row);
    }
    return out;
  }

  get isEmpty() {
    return this.rows.length === 0;
  }

  get changedSinceSignOff() {
    return this.rows.filter((r) => r.afterSignOff).length;
  }

  <template>
    <div class='trail' ...attributes>
      {{#if this.isEmpty}}
        <p class='empty'>
          <HistoryIcon class='e-icon' aria-hidden='true' />
          {{if
            @emptyMessage
            @emptyMessage
            'Nothing recorded yet. The trail fills as decisions are made.'
          }}
        </p>
      {{else}}
        {{#if this.changedSinceSignOff}}
          <p class='since'>{{this.changedSinceSignOff}}
            entr{{if (eq this.changedSinceSignOff 1) 'y' 'ies'}}
            recorded after sign-off.</p>
        {{/if}}
        {{#each this.days as |day|}}
          <section class='day'>
            <h3 class='day-label mono'>{{day.label}}</h3>
            {{#each day.rows as |row|}}
              <div class='row {{if row.afterSignOff "after"}}'>
                <span class='time mono'>{{row.time}}</span>
                <div class='body'>
                  <div class='head'>
                    <StatePill
                      @label={{row.label}}
                      @hue={{row.hue}}
                      @dot={{true}}
                    />
                    {{#if row.subject}}
                      <span class='subject'>{{row.subject}}</span>
                    {{/if}}
                    {{#if row.who}}
                      <span class='who'>{{row.who}}</span>
                    {{/if}}
                    {{#if row.afterSignOff}}
                      <StatePill @label='after sign-off' @hue='amber' />
                    {{/if}}
                  </div>
                  {{#if row.note}}
                    <p class='note'>{{row.note}}</p>
                  {{/if}}
                  {{#if row.conditions}}
                    <p class='conditions'>Conditions: {{row.conditions}}</p>
                  {{/if}}
                </div>
              </div>
            {{/each}}
          </section>
        {{/each}}
      {{/if}}
    </div>

    <style scoped>
      .trail {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .empty {
        margin: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        font-size: 0.875rem;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .e-icon {
        width: 16px;
        height: 16px;
        flex: none;
      }
      .since {
        margin: 0;
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--state-next-fg, var(--foreground, var(--boxel-dark)));
      }
      .day {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      .day-label {
        margin: 0 0 var(--boxel-sp-5xs);
        font-size: 0.6875rem;
        font-weight: 700;
        letter-spacing: 0.05em;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .row {
        display: grid;
        grid-template-columns: 3.5rem minmax(0, 1fr);
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-5xs) 0;
        border-bottom: 1px solid var(--border-subtle, var(--border, #f3f4f6));
      }
      .row.after {
        border-left: 2px solid var(--state-next-fg, var(--boxel-warning));
        padding-left: var(--boxel-sp-xs);
      }
      .time {
        font-size: 0.75rem;
        color: var(--muted-foreground, var(--boxel-450));
        font-variant-numeric: tabular-nums;
      }
      .mono {
        font-family: var(--font-mono, ui-monospace, monospace);
      }
      .body {
        min-width: 0;
        display: grid;
        gap: 2px;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .subject {
        font-size: 0.8125rem;
        font-weight: 600;
      }
      .who {
        font-size: 0.75rem;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .note,
      .conditions {
        margin: 0;
        font-size: 0.8125rem;
        line-height: 1.45;
        color: var(--foreground, var(--boxel-dark));
      }
      .conditions {
        color: var(--muted-foreground, var(--boxel-450));
      }
    </style>
  </template>
}

export default AuditTimeline;
