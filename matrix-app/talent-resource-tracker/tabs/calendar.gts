import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Meeting } from '../../hr/meeting';
import {
  Calendar,
  type CalendarEvent,
} from '@cardstack/catalog/components/calendar';
import type { StateColor } from '@cardstack/catalog/components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';
import { toLocalDate } from '../dates';
import { UpcomingList } from '../upcoming-list';
import { TrackerPage, TrackerSection, StatusDot } from '../shared';

// Each kind's accent bar on the month grid, from the theme's tone inks.
function kindColor(ink: string): StateColor {
  return { bg: 'transparent', fg: `var(--${ink})`, ring: `var(--${ink})` };
}
const KIND_COLORS: Record<string, StateColor> = {
  interview: kindColor('primary'),
  standup: kindColor('primary'),
  'one-on-one': kindColor('success-ink'),
  'vendor-review': kindColor('warning-ink'),
};

interface Signature {
  Args: {
    tracker: TrackerView;
  };
}

export class CalendarTab extends GlimmerComponent<Signature> {
  openEvent = (event: CalendarEvent) => {
    this.args.tracker.openCard(event);
  };

  rescheduleEvent = async (event: CalendarEvent, newDate: Date) => {
    let meeting = this.args.tracker.meetings.find((m) => m.id === event.id);
    if (!meeting || !meeting.date) {
      return;
    }
    let oldDate = toLocalDate(meeting.date);
    let updated = toLocalDate(newDate);
    updated.setHours(
      oldDate.getHours(),
      oldDate.getMinutes(),
      oldDate.getSeconds(),
      0,
    );
    this.args.tracker.actionError = undefined;
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    let previous = meeting.date;
    meeting.date = updated;
    try {
      await new SaveCardCommand(commandContext).execute({
        card: meeting,
      } as any);
    } catch (error: any) {
      meeting.date = previous;
      this.args.tracker.actionError = error?.message ?? String(error);
    }
  };

  addMeeting = (date: Date) => {
    void this.args.tracker.addMeetingTask.perform(date);
  };

  kindColors = KIND_COLORS;

  timeOf = (event: CalendarEvent): string =>
    event.date
      ? new Date(event.date).toLocaleTimeString('en-GB', {
          hour: '2-digit',
          minute: '2-digit',
        })
      : '';

  loadTone = (
    tone: 'red' | 'amber' | 'green',
  ): 'danger' | 'warning' | 'success' =>
    tone === 'red' ? 'danger' : tone === 'amber' ? 'warning' : 'success';

  <template>
    <TrackerPage
      @group='Planning'
      @title='Calendar'
      @subtitle='Interview activity this cycle'
    >
      <:actions as |bar|>
        {{#if @tracker.canCreate}}
          <bar.Action
            @id='add'
            @label='Add meeting'
            @primary={{true}}
            @loading={{@tracker.addCard.isRunning}}
            @onClick={{fn @tracker.addNew Meeting}}
          />
        {{/if}}
      </:actions>
      <:default>
        <div class='capacity-row'>
          <span class='capacity-label'>Interviewer load this week</span>
          {{#if @tracker.interviewerLoad.length}}
            <ul class='load-row'>
              {{#each @tracker.interviewerLoad as |row|}}
                <li>
                  <StatusDot
                    @tone={{this.loadTone row.tone}}
                    @label='{{row.employee.name}} {{row.hours}}h / {{row.capacityHours}}h'
                  />
                </li>
              {{/each}}
            </ul>
          {{else if @tracker.isLoading}}
            <span class='capacity-empty'>—</span>
          {{else}}
            <span class='capacity-empty'>No interviews this week</span>
          {{/if}}
        </div>
        <TrackerSection @title='Schedule' @meta='this month' @padded={{true}}>
          <Calendar
            @events={{@tracker.calendarEvents}}
            @kindColors={{this.kindColors}}
            @onSelectEvent={{this.openEvent}}
            @onRescheduleEvent={{this.rescheduleEvent}}
            @onAddEvent={{this.addMeeting}}
            @addingDate={{@tracker.addingMeetingOn}}
          >
            <:chip as |event|>
              <span class='ev'><span
                  class='ev-dot'
                  aria-hidden='true'
                ></span><span class='ev-time'>{{this.timeOf event}}</span><span
                  class='ev-title'
                >{{event.title}}</span></span>
            </:chip>
          </Calendar>
        </TrackerSection>
        <TrackerSection @title='Upcoming'>
          <UpcomingList
            @meetings={{@tracker.meetings}}
            @loading={{@tracker.isLoading}}
            @onOpen={{@tracker.openCard}}
          />
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
      /* an event: dot + mono time + title, one 12px line; the Calendar's
         flat appearance makes the whole chip the hover/focus target */
      .ev {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-3xs);
        min-width: 0;
        font-size: var(--boxel-font-size-xs);
      }
      .ev-dot {
        flex: none;
        inline-size: 0.4375rem;
        block-size: 0.4375rem;
        border-radius: 50%;
        background: currentColor;
      }
      .ev-time {
        flex: none;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
      }
      .ev-title {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: var(--foreground);
        font-weight: 600;
      }
      /* one hairline line, like the Dashboard's needs-attention line */
      .capacity-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
        padding: var(--trt-py) 0;
        border-block: 1px solid var(--border);
      }
      .capacity-label {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        line-height: 1.3;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--subtle-foreground);
      }
      .capacity-empty {
        color: var(--muted-foreground);
      }
      .load-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
        margin: 0;
        padding: 0;
        list-style: none;
      }
    </style>
  </template>
}
