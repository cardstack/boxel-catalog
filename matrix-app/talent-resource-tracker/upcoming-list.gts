import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type { CardDef } from '@cardstack/base/card-api';
import { getComponent, TrackerEmpty } from './shared';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import type { Meeting } from '../hr/meeting';
import { toLocalDate } from './dates';

interface Signature {
  Args: {
    meetings: Meeting[];
    loading?: boolean;
    onOpen: (card: CardDef) => void;
  };
}

interface UpcomingRow {
  meeting: Meeting;
  start: Date;
  end?: Date;
}

const UNIT_MINUTES: Record<string, number> = { minutes: 1, hours: 60 };

// The next five meetings as ruled rows: a date badge, who it is with and the
// time span. The dashboard and the calendar tab both show this panel body.
export class UpcomingList extends GlimmerComponent<Signature> {
  get upcoming(): UpcomingRow[] {
    let now = Date.now();
    return this.args.meetings
      .filter((m) => m.date && toLocalDate(m.date).getTime() >= now)
      .sort(
        (a, b) =>
          toLocalDate(a.date!).getTime() - toLocalDate(b.date!).getTime(),
      )
      .slice(0, 5)
      .map((meeting) => {
        let start = toLocalDate(meeting.date!);
        let { value, unit } = meeting.duration ?? {};
        let perUnit = UNIT_MINUTES[unit ?? 'minutes'];
        let end =
          value && perUnit
            ? new Date(start.getTime() + value * perUnit * 60000)
            : undefined;
        return { meeting, start, end };
      });
  }

  <template>
    {{#if this.upcoming.length}}
      <ul class='upcoming'>
        {{#each this.upcoming key='meeting.id' as |row|}}
          <li>
            <button
              type='button'
              class='row'
              {{on 'click' (fn @onOpen row.meeting)}}
            >
              <span class='when'><FormatDate
                  @date={{row.start}}
                  @weekday='short'
                />
                <FormatDate
                  @date={{row.start}}
                  @hour='2-digit'
                  @minute='2-digit'
                  @hourCycle='h23'
                /></span>
              <span class='what'>{{row.meeting.title}}</span>
              {{#if row.meeting.candidate}}
                <span class='who'>{{#let
                    (getComponent row.meeting.candidate)
                    as |Atom|
                  }}{{#if Atom}}<Atom
                        @format='atom'
                        @displayContainer={{false}}
                      />{{/if}}{{/let}}</span>
              {{/if}}
            </button>
          </li>
        {{/each}}
      </ul>
    {{else if @loading}}
      <LoadingState @label='Loading' />
    {{else}}
      <TrackerEmpty>Nothing scheduled. Pick a day on the calendar or use + Add
        meeting.</TrackerEmpty>
    {{/if}}
    <style scoped>
      .upcoming {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      /* the mock's Upcoming rows: mono time, bold title, the person's atom */
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: 100%;
        min-height: 2.125rem;
        padding: 0 var(--trt-px);
        border: 0;
        border-top: 1px solid var(--border);
        background: none;
        color: var(--foreground);
        font: inherit;
        text-align: start;
        cursor: pointer;
      }
      .row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: -0.125rem;
      }
      .when {
        flex: none;
        inline-size: 4.625rem;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      .what {
        min-width: 0;
        overflow: hidden;
        font-weight: 700;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .who {
        margin-inline-start: auto;
        min-width: 0;
      }
      @media (hover: hover) {
        .row:hover .what {
          color: var(--primary-ink);
        }
      }
    </style>
  </template>
}
