import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Meeting, MEETING_TYPE_COLORS } from '../../hr/meeting';
import { Calendar, type CalendarEvent } from '../../../components/calendar';
import { Button } from '@cardstack/pretui/components/button';
import type { TrackerView } from '../talent-resource-tracker';

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
    let oldDate = new Date(meeting.date);
    let updated = new Date(newDate);
    updated.setHours(
      oldDate.getHours(),
      oldDate.getMinutes(),
      oldDate.getSeconds(),
      0,
    );
    meeting.date = updated;
    this.args.tracker.actionError = undefined;
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    await new SaveCardCommand(commandContext).execute({
      card: meeting,
    } as any);
  };

  addMeeting = (date: Date) => {
    void this.args.tracker.addMeetingTask.perform(date);
  };

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Calendar</h2>
          <p class='byline'>Interview activity this cycle</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Meeting)}}
          >+ Add meeting</Button>
        {{/if}}
      </div>
      {{#if @tracker.interviewerLoad.length}}
        <div class='capacity-row'>
          <span class='capacity-label'>Interviewer load this week</span>
          {{#each @tracker.interviewerLoad as |row|}}
            <span class='turn-chip turn-{{row.tone}}'>
              {{row.employee.name}}
              {{row.hours}}h /
              {{row.capacityHours}}h
            </span>
          {{/each}}
        </div>
      {{/if}}
      <Calendar
        @events={{@tracker.calendarEvents}}
        @kindColors={{MEETING_TYPE_COLORS}}
        @onSelectEvent={{this.openEvent}}
        @onRescheduleEvent={{this.rescheduleEvent}}
        @onAddEvent={{this.addMeeting}}
        @addingDate={{@tracker.addingMeetingOn}}
      />
    </section>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 2px solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 20px;
        margin: 0 0 3px;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 11.5px;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .turn-chip {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.02em;
        padding: 0.125rem 0.4375rem;
        border-radius: 999px;
      }
      .capacity-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        margin-bottom: var(--boxel-sp);
      }
      .capacity-label {
        font-family: var(--font-mono);
        font-size: 11px;
        color: var(--muted-foreground);
      }
      .btn-review {
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
      }
      .review-queue-item.on {
        background: var(--muted);
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .btn-review {
        font-size: 10px;
        margin-bottom: var(--boxel-sp-5xs);
      }
      .tab-section > .directory.grid-view {
        --item-width: auto;
        --item-height: 14rem;
        grid-template-columns: repeat(auto-fill, minmax(13rem, 1fr));
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
