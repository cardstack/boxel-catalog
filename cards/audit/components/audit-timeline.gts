import GlimmerComponent from '@glimmer/component';
import { cached } from '@glimmer/tracking';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import {
  Timeline,
  type TimelineEvent,
} from '@cardstack/pretui/components/timeline';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

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

interface Row extends TimelineEvent {
  when: Date | null;
  actionLabel: string;
  note: string | null;
  conditions: string | null;
  afterSignOff: boolean;
  hue: Hue;
}

interface Day {
  key: string;
  date: Date | null;
  rows: Row[];
}

// Grouped by the local calendar day, as the reader's clock shows it.
function dayKey(d: Date): string {
  let m = `${d.getMonth() + 1}`.padStart(2, '0');
  let day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
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
  @cached
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
      let actionLabel = auditActionLabel(e.action);
      return {
        id: e.id ?? `entry-${i}`,
        title: e.subjectTitle || actionLabel,
        person: e.doneBy?.name ?? undefined,
        when,
        actionLabel,
        note: e.note ?? null,
        conditions: e.conditions ?? null,
        afterSignOff: Boolean(
          signed && when && when.getTime() > signed.getTime(),
        ),
        hue: auditActionHue(e.action),
      };
    });
  }

  @cached
  get days(): Day[] {
    let out: Day[] = [];
    for (let row of this.rows) {
      let key = row.when ? dayKey(row.when) : 'undated';
      let day = out.find((d) => d.key === key);
      if (!day) {
        day = { key, date: row.when, rows: [] };
        out.push(day);
      }
      day.rows.push(row);
    }
    return out;
  }

  get changedSinceSignOff() {
    return this.rows.filter((r) => r.afterSignOff).length;
  }

  get sinceLabel(): string {
    let n = this.changedSinceSignOff;
    return `${n} ${n === 1 ? 'entry' : 'entries'} recorded after sign-off.`;
  }

  // Timeline yields its own event type; every event here is a Row.
  rowOf = (event: TimelineEvent): Row => event as Row;

  <template>
    <div class='trail' ...attributes>
      {{#if this.rows.length}}
        {{#if this.changedSinceSignOff}}
          <p class='since'>{{this.sinceLabel}}</p>
        {{/if}}
        {{#each this.days as |day|}}
          <section class='day'>
            <h3 class='day-label'>
              {{#if day.date}}
                <FormatDate @date={{day.date}} @dateStyle='medium' />
              {{else}}
                Undated
              {{/if}}
            </h3>
            <Timeline
              @events={{day.rows}}
              @density='compact'
              @label='Audit entries'
            >
              <:default as |event|>
                {{#let (this.rowOf event) as |row|}}
                  <div class='head'>
                    <StatePill
                      @label={{row.actionLabel}}
                      @hue={{row.hue}}
                      @dot={{true}}
                    />
                    {{#if row.when}}
                      <FormatDate
                        class='time'
                        @date={{row.when}}
                        @timeStyle='short'
                      />
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
                {{/let}}
              </:default>
            </Timeline>
          </section>
        {{/each}}
      {{else}}
        <EmptyState
          @title={{if
            @emptyMessage
            @emptyMessage
            'Nothing recorded yet. The trail fills as decisions are made.'
          }}
          @texture={{false}}
          style={{COMPACT_EMPTY_STYLE}}
        />
      {{/if}}
    </div>

    <style scoped>
      .trail {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .since {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        color: var(--attention-ink);
      }
      .day {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .day-label {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .time {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .note,
      .conditions {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.45;
      }
      .conditions {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

export default AuditTimeline;
