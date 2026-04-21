// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
// Try EXTENDING Calendar directly
import { field, linksToMany, Component } from 'https://cardstack.com/base/card-api';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Calendar } from './calendar';
import { CalendarEvent } from './calendar-event';
import { Button } from '@cardstack/boxel-ui/components';

export class CalendarClone extends Calendar {
  static displayName = 'Calendar Clone';

  // Override isolated to simplify
  static isolated = class Isolated extends Component<typeof CalendarClone> {
    @tracked selectedDate: Date | null = null;
    @tracked showForm = false;
    @tracked newEventTitle = '';
    @tracked newEventTime = '09:00';
    @tracked status = '';

    selectToday = () => {
      this.selectedDate = new Date();
      this.showForm = true;
    };

    updateTitle = (event: Event) => {
      this.newEventTitle = (event.target as HTMLInputElement).value;
    };

    updateTime = (event: Event) => {
      this.newEventTime = (event.target as HTMLInputElement).value;
    };

    createEvent = async () => {
      if (!this.selectedDate || !this.newEventTitle.trim()) {
        this.status = 'Select date and enter title';
        return;
      }

      this.status = 'Creating with new CalendarEvent()...';

      const [hours, minutes] = this.newEventTime.split(':').map(Number);
      const eventDateTime = new Date(this.selectedDate);
      eventDateTime.setHours(hours || 9, minutes || 0, 0, 0);

      try {
        // Try AI Agent's suggestion: use new CalendarEvent()
        const newEvent = new CalendarEvent();
        newEvent.eventTitle = this.newEventTitle;
        newEvent.startTime = eventDateTime;
        newEvent.color = '#3b82f6';

        const currentEvents = this.args.model?.events || [];
        (this.args.model as any).events = [...currentEvents, newEvent];

        this.status = 'Success with new CalendarEvent()!';
        this.showForm = false;
        this.newEventTitle = '';
      } catch (e: any) {
        this.status = `Error: ${e?.message || e}`;
      }
    };

    <template>
      <div style="padding: 1rem; font-family: system-ui;">
        <h1>Calendar Clone (extends Calendar)</h1>
        {{#if this.status}}<p style="background: #fef3c7; padding: 0.5rem;">{{this.status}}</p>{{/if}}

        {{#unless this.showForm}}
          <Button @kind="primary" {{on "click" this.selectToday}}>
            Select Today & Add Event
          </Button>
        {{/unless}}

        {{#if this.showForm}}
          <div style="background: #f5f5f5; padding: 1rem; margin: 1rem 0;">
            <p>Selected: {{this.selectedDate}}</p>
            <input
              type="text"
              placeholder="Event title"
              value={{this.newEventTitle}}
              {{on "input" this.updateTitle}}
              style="padding: 0.5rem; margin-right: 0.5rem;"
            />
            <input
              type="time"
              value={{this.newEventTime}}
              {{on "input" this.updateTime}}
              style="padding: 0.5rem; margin-right: 0.5rem;"
            />
            <Button @kind="primary" {{on "click" this.createEvent}}>
              Create Event
            </Button>
          </div>
        {{/if}}

        <hr />
        <h2>Events (inherited from Calendar):</h2>
        {{#if @model.events.length}}
          <@fields.events @format="embedded" />
        {{else}}
          <p>No events yet</p>
        {{/if}}
      </div>
    </template>
  };
}
