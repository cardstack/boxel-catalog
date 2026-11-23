import GlimmerComponent from '@glimmer/component';
import type { ComponentLike } from '@glint/template';
import {
  CardDef,
  Component,
  contains,
  field,
  type BaseDef,
  type CardContext,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { operations } from 'https://cardstack.com/base/operations';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { AttendanceRecord } from '../attendance/attendance-record';
import { localClock } from '../attendance/attendance-day';

interface LiveRecordsSignature {
  Args: {
    entries: { id: string }[] | undefined;
    isLoading: boolean;
    context: CardContext | undefined;
    // Show only the first N rows; `mine` sorts the current year first.
    limit?: number;
  };
  Blocks: { empty: [] };
}

// The saved search says which records are mine; each is then loaded as a live
// card, so its check-in button works without the hover a prerendered row needs.
class LiveRecords extends GlimmerComponent<LiveRecordsSignature> {
  collection = this.args.context?.getCardCollection(this, () =>
    this.args.entries?.slice(0, this.args.limit ?? undefined).map((e) => e.id),
  );

  get items(): { id: string; component: ComponentLike }[] {
    return (this.collection?.cards ?? []).map((card) => ({
      id: card.id,
      component: (card.constructor as typeof BaseDef).getComponent(
        card,
      ) as unknown as ComponentLike,
    }));
  }

  get isEmpty(): boolean {
    return !this.args.isLoading && !this.args.entries?.length;
  }

  <template>
    {{#if this.isEmpty}}
      {{yield to='empty'}}
    {{else}}
      <div class='records'>
        {{#each this.items key='id' as |item|}}
          <item.component @format='embedded' />
        {{/each}}
      </div>
    {{/if}}
    <style scoped>
      .records {
        display: grid;
        gap: var(--boxel-sp);
      }
    </style>
  </template>
}

class AppView extends Component<typeof AttendanceApp> {
  // Each saved search answers only for the person signed in: their own record,
  // and the records of the people they manage.
  mine = operations<typeof AttendanceRecord>(AttendanceRecord).mine.query({});
  myTeam = operations<typeof AttendanceRecord>(AttendanceRecord).myTeam.query(
    {},
  );

  get timezone(): string {
    return this.args.model.timezone || 'UTC';
  }

  get todayLabel(): string {
    let { day, label } = localClock(new Date(), this.timezone);
    return `${day} · ${label} (${this.timezone})`;
  }

  <template>
    <article class='app'>
      <header>
        <h1>{{if @model.name @model.name 'Time Card'}}</h1>
        <p class='sub'>{{this.todayLabel}}</p>
      </header>

      <section aria-labelledby='mine-heading'>
        <h2 id='mine-heading'>My attendance</h2>
        {{#if @context.searchResultsComponent}}
          <@context.searchResultsComponent
            @query={{this.mine}}
            @overlays={{false}}
            as |results|
          >
            <LiveRecords
              @entries={{results.entries}}
              @isLoading={{results.isLoading}}
              @context={{@context}}
              @limit={{1}}
            >
              <:empty>
                <EmptyState
                  @title='No attendance record for you yet'
                  @message='Ask an admin to make sure your Boxel account is on your employee record.'
                />
              </:empty>
            </LiveRecords>
          </@context.searchResultsComponent>
        {{/if}}
      </section>

      <section aria-labelledby='team-heading'>
        <h2 id='team-heading'>My team</h2>
        {{#if @context.searchResultsComponent}}
          <@context.searchResultsComponent
            @query={{this.myTeam}}
            @overlays={{false}}
            as |results|
          >
            <LiveRecords
              @entries={{results.entries}}
              @isLoading={{results.isLoading}}
              @context={{@context}}
            >
              <:empty>
                <p class='sub'>Nobody reports to you here.</p>
              </:empty>
            </LiveRecords>
          </@context.searchResultsComponent>
        {{/if}}
      </section>
    </article>
    <style scoped>
      .app {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        max-width: 48rem;
      }
      h1 {
        margin: 0;
        font-size: var(--boxel-font-size-xl);
      }
      h2 {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size);
      }
      .sub {
        margin: 0;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// The attendance realm's home: check in and out, my attendance, and the
// records of the people I manage. `timezone` is the organization's clock.
export class AttendanceApp extends CardDef {
  static displayName = 'Attendance App';
  static icon = CalendarClockIcon;
  static prefersWideFormat = true;

  @field name = contains(StringField);
  @field timezone = contains(StringField, {
    description:
      "The organization's IANA time zone, such as America/New_York. It decides today, late and early",
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AttendanceApp) {
      return this.name || 'Time Card';
    },
  });

  static isolated = AppView;
}
