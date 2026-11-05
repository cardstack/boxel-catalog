import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type { CardDef } from '@cardstack/base/card-api';
import { Avatar } from '../../ui-component/components/avatar';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FormatDate } from '../../ui-component/components/format-date';
import { LoadingState } from '../../ui-component/components/loading-state';
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
              <span class='badge' aria-hidden='true'>
                <FormatDate
                  class='badge-day'
                  @date={{row.start}}
                  @day='numeric'
                />
                <FormatDate
                  class='badge-month'
                  @date={{row.start}}
                  @month='short'
                />
              </span>
              <Avatar
                @name={{row.meeting.candidateName}}
                @src={{row.meeting.candidate.photo.resolvedUrl}}
                @size={{40}}
              />
              <span class='text'>
                <span class='title'>{{row.meeting.title}}</span>
                <span class='sub'>
                  <FormatDate
                    @date={{row.start}}
                    @hour='2-digit'
                    @minute='2-digit'
                    @hourCycle='h23'
                  />{{#if row.end}}
                    –
                    <FormatDate
                      @date={{row.end}}
                      @hour='2-digit'
                      @minute='2-digit'
                      @hourCycle='h23'
                    />{{/if}}
                </span>
              </span>
            </button>
          </li>
        {{/each}}
      </ul>
    {{else if @loading}}
      <LoadingState @label='Loading' />
    {{else}}
      <EmptyState
        @size='s'
        @texture={{false}}
        @title='Nothing scheduled'
        @message='Pick a day on the calendar or use + Add meeting.'
      />
    {{/if}}
    <style scoped>
      .upcoming {
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .upcoming li + li {
        border-top: 1px solid var(--border);
      }
      .row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
        width: 100%;
        min-height: 3rem;
        padding: var(--boxel-sp-sm) 0;
        border: 0;
        background: none;
        color: var(--foreground);
        text-align: left;
      }
      .upcoming li:first-child .row {
        padding-top: 0;
      }
      .upcoming li:last-child .row {
        padding-bottom: 0;
      }
      .row:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .badge {
        display: flex;
        flex: none;
        flex-direction: column;
        width: 2.75rem;
        padding: var(--boxel-sp-4xs) 0;
        border-radius: var(--boxel-border-radius-sm);
        background-color: var(--muted);
        line-height: 1.25;
        text-align: center;
      }
      .badge-day {
        color: var(--primary);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      .badge-month {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
      }
      .text {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }
      .title {
        overflow: hidden;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sub {
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
      }
      @media (hover: hover) {
        .row:hover .title {
          color: var(--primary);
        }
      }
    </style>
  </template>
}
