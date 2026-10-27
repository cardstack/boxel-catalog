import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Meeting } from '../../hr/meeting';
import { Calendar, type CalendarEvent } from '../../../components/calendar';
import type { StateColor } from '@cardstack/catalog/components/state-pill';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { StatusChip } from '../../../ui-component/components/status-chip';
import { Button } from '../../../ui-component/components/button';
import type { TrackerView } from '../talent-resource-tracker';
import { toLocalDate } from '../dates';
import { UpcomingList } from '../upcoming-list';

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

  loadTone = (
    tone: 'red' | 'amber' | 'green',
  ): 'danger' | 'warning' | 'success' =>
    tone === 'red' ? 'danger' : tone === 'amber' ? 'warning' : 'success';

  <template>
    <PageScaffold @title='Calendar' @subtitle='Interview activity this cycle'>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Meeting)}}
          >+ Add meeting</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='capacity-row'>
          <span class='capacity-label'>Interviewer load this week</span>
          {{#if @tracker.interviewerLoad.length}}
            <ul class='load-row'>
              {{#each @tracker.interviewerLoad as |row|}}
                <li>
                  <StatusChip
                    @value='{{row.employee.name}} {{row.hours}}h / {{row.capacityHours}}h'
                    @tone={{this.loadTone row.tone}}
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
        <Panel>
          <Calendar
            @events={{@tracker.calendarEvents}}
            @kindColors={{this.kindColors}}
            @appearance='flat'
            @weekStart='mon'
            @onSelectEvent={{this.openEvent}}
            @onRescheduleEvent={{this.rescheduleEvent}}
            @onAddEvent={{this.addMeeting}}
            @addingDate={{@tracker.addingMeetingOn}}
          />
        </Panel>
        <Panel @title='Upcoming'>
          <UpcomingList
            @meetings={{@tracker.meetings}}
            @loading={{@tracker.isLoading}}
            @onOpen={{@tracker.openCard}}
          />
        </Panel>
      </:default>
    </PageScaffold>
    <style scoped>
      .capacity-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .capacity-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .capacity-empty {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .load-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
    </style>
  </template>
}
