import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { cached, tracked } from '@glimmer/tracking';
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
import {
  operations,
  OperationsError,
} from 'https://cardstack.com/base/operations';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Input } from '@cardstack/pretui/components/input';
import { Select } from '@cardstack/pretui/components/select';
import { StatusChip } from '@cardstack/pretui/components/status-chip';

import { AttendanceRecord } from '../attendance/attendance-record';
import { LeaveRequest } from '../attendance/leave-request';
import { currentRecords } from '../attendance/board-fold';
import { TodayBoard } from '../attendance/today-board';
import { localClock } from '../attendance/attendance-day';
import {
  DECLARED_TYPES,
  LEAVE_STATE_LABEL,
  LEAVE_TYPES,
  dayKeyOf,
  leaveBalances,
  leaveDays,
} from '../attendance/leave-days';

interface LiveRecordsSignature {
  Args: {
    entries: { id: string }[] | undefined;
    isLoading: boolean;
    context: CardContext | undefined;
    // Show only the first N rows; `mine` sorts the latest year first, so an
    // admin creates next year's record when the year turns over.
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

function refusal(err: unknown): string {
  if (err instanceof OperationsError) {
    // The realm refuses a request whose type or dates fail its checks with
    // this wording.
    if (err.detail?.includes('this program produced 0')) {
      return 'Check the kind of leave and the dates. The last day can’t be before the first.';
    }
    return err.detail ?? err.message;
  }
  return err instanceof Error ? err.message : String(err);
}

interface LeaveRow {
  id: string;
  card: LeaveRequest;
  who: string;
  type: string;
  range: string;
  daysLabel: string;
  state: string;
  stateLabel: string;
  note: string;
}

function leaveRow(card: LeaveRequest, names: Record<string, string>): LeaveRow {
  let type =
    LEAVE_TYPES.find((t) => t.value === card.ptoType)?.label ??
    card.ptoType ??
    'Leave';
  let start = dayKeyOf(card.startDate);
  let end = dayKeyOf(card.endDate);
  let state = card.state ?? '';
  return {
    id: card.id,
    card,
    who: names[card.userId ?? ''] ?? card.userId ?? '',
    type,
    range: start === end || !end ? start : `${start} to ${end}`,
    daysLabel: leaveDays(card) === 1 ? '1 day' : `${leaveDays(card)} days`,
    state,
    stateLabel: LEAVE_STATE_LABEL[state] ?? 'Draft',
    note: card.declared
      ? 'Declared'
      : state === 'pending'
        ? 'Waiting on your manager'
        : '',
  };
}

interface LiveCardsSignature {
  Args: {
    entries: { id: string }[] | undefined;
    context: CardContext | undefined;
  };
  Blocks: { default: [record: AttendanceRecord | undefined] };
}

// A saved search lists ids; this loads the first as a live record. `mine`
// sorts the latest year first, so that is the current one.
class FirstRecord extends GlimmerComponent<LiveCardsSignature> {
  collection = this.args.context?.getCardCollection(this, () =>
    this.args.entries?.slice(0, 1).map((e) => e.id),
  );

  get record(): AttendanceRecord | undefined {
    return this.collection?.cards?.[0] as AttendanceRecord | undefined;
  }

  <template>{{yield this.record}}</template>
}

interface LeaveListSignature {
  Args: {
    rows: LeaveRow[];
    context: CardContext | undefined;
    // Approve and decline buttons on pending rows
    decide?: boolean;
    deciding?: string;
    onDecide?: (row: LeaveRow, decision: string) => void;
  };
  Blocks: { empty: [] };
}

class LeaveList extends GlimmerComponent<LeaveListSignature> {
  hide = (row: LeaveRow): boolean =>
    this.args.context?.canInvoke?.('decideLeave', row.card) === false;

  isDeciding = (row: LeaveRow, decision: string): boolean =>
    this.args.deciding === `${row.id}:${decision}`;

  otherDeciding = (row: LeaveRow, decision: string): boolean =>
    this.args.deciding !== undefined && !this.isDeciding(row, decision);

  <template>
    {{#if @rows.length}}
      <ul class='leave'>
        {{#each @rows key='id' as |row|}}
          <li>
            <div class='info'>
              {{#if @decide}}<strong>{{row.who}}</strong> · {{/if}}<strong
              >{{row.type}}</strong>
              {{row.range}}
              ·
              {{row.daysLabel}}
              {{#if row.note}}<span class='note'>{{row.note}}</span>{{/if}}
            </div>
            <StatusChip @value={{row.stateLabel}} />
            {{#if @onDecide}}
              {{#unless (this.hide row)}}
                <Button
                  @tone='success'
                  @appearance='outlined'
                  @size='s'
                  @busy={{this.isDeciding row 'approved'}}
                  @disabled={{this.otherDeciding row 'approved'}}
                  {{on 'click' (fn @onDecide row 'approved')}}
                >Approve</Button>
                <Button
                  @tone='danger'
                  @appearance='outlined'
                  @size='s'
                  @busy={{this.isDeciding row 'declined'}}
                  @disabled={{this.otherDeciding row 'declined'}}
                  {{on 'click' (fn @onDecide row 'declined')}}
                >Decline</Button>
              {{/unless}}
            {{/if}}
          </li>
        {{/each}}
      </ul>
    {{else}}
      {{yield to='empty'}}
    {{/if}}
    <style scoped>
      .leave {
        display: grid;
        margin: 0;
        padding: 0;
        list-style: none;
      }
      li {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .info {
        flex: 1;
        min-width: 12rem;
      }
      .note {
        margin-inline-start: var(--boxel-sp-xs);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

interface LeaveSectionSignature {
  Args: {
    record: AttendanceRecord;
    myLeave: { id: string }[] | undefined;
    context: CardContext | undefined;
  };
}

// My balances, my requests and the form to ask for time off. Balances come
// from my approved requests, read live.
class LeaveSection extends GlimmerComponent<LeaveSectionSignature> {
  @tracked ptoType = 'vacation';
  @tracked startDate = '';
  @tracked endDate = '';
  @tracked reason = '';
  @tracked running = false;
  @tracked message: string | undefined;
  @tracked failed = false;

  leave = this.args.context?.getCardCollection(this, () =>
    this.args.myLeave?.map((e) => e.id),
  );

  get requests(): LeaveRequest[] {
    return (this.leave?.cards ?? []) as LeaveRequest[];
  }

  get balances() {
    let r = this.args.record;
    return leaveBalances(r.allowances, this.requests, r.yearStart, r.yearEnd);
  }

  get rows(): LeaveRow[] {
    return this.requests.map((c) => leaveRow(c, {}));
  }

  get hideRequest(): boolean {
    return (
      this.args.context?.canInvoke?.('requestLeave', this.args.record) === false
    );
  }

  get isDeclared(): boolean {
    return DECLARED_TYPES.includes(this.ptoType);
  }

  get submitLabel(): string {
    return this.isDeclared ? 'File leave' : 'Send to my manager';
  }

  typeOptions = LEAVE_TYPES;
  setType = (value: string) => (this.ptoType = value);
  setStart = (value: string) => {
    this.startDate = value;
    if (!this.endDate || this.endDate < value) {
      this.endDate = value;
    }
  };
  setEnd = (value: string) => (this.endDate = value);
  setReason = (value: string) => (this.reason = value);

  request = async (event?: Event) => {
    event?.preventDefault();
    if (this.running) {
      return;
    }
    this.message = undefined;
    this.failed = false;
    if (!this.startDate || !this.endDate) {
      this.message = 'Choose the first and last day of leave.';
      this.failed = true;
      return;
    }
    if (this.endDate < this.startDate) {
      this.message = 'The last day can’t be before the first day.';
      this.failed = true;
      return;
    }
    this.running = true;
    try {
      // The realm sets state and declared; the call sends only what the
      // person chose.
      await operations(this.args.record).requestLeave({
        ptoType: this.ptoType,
        startDate: this.startDate,
        endDate: this.endDate,
        reason: this.reason,
      });
      this.message = this.isDeclared
        ? 'Filed. Sick and personal days are approved as filed.'
        : 'Sent to your manager.';
      this.startDate = '';
      this.endDate = '';
      this.reason = '';
    } catch (err) {
      this.message = refusal(err);
      this.failed = true;
    } finally {
      this.running = false;
    }
  };

  <template>
    <div class='balances'>
      {{#each this.balances key='type' as |b|}}
        <div class='balance'>
          <span class='label'>{{b.label}}</span>
          <strong>{{b.remaining}}</strong>
          <span class='of'>of {{b.allowed}} days left · {{b.used}} used</span>
        </div>
      {{/each}}
    </div>

    <LeaveList @rows={{this.rows}} @context={{@context}}>
      <:empty><p class='none'>No leave requested yet.</p></:empty>
    </LeaveList>

    {{#unless this.hideRequest}}
      <form
        class='request'
        aria-label='Request leave'
        {{on 'submit' this.request}}
      >
        <label class='field'>
          Kind of leave
          <Select
            @options={{this.typeOptions}}
            @value={{this.ptoType}}
            @onValueChange={{this.setType}}
            aria-label='Kind of leave'
          />
        </label>
        <label class='field'>
          First day
          <Input
            @type='date'
            @value={{this.startDate}}
            @onInput={{this.setStart}}
          />
        </label>
        <label class='field'>
          Last day
          <Input
            @type='date'
            @value={{this.endDate}}
            @onInput={{this.setEnd}}
          />
        </label>
        <label class='field wide'>
          Note (optional)
          <Input @value={{this.reason}} @onInput={{this.setReason}} />
        </label>
        {{#if this.isDeclared}}
          <p class='hint'>Sick and personal days are approved when you file
            them.</p>
        {{/if}}
        <div>
          <Button
            type='submit'
            @busy={{this.running}}
            @busyLabel='Sending…'
          >{{this.submitLabel}}</Button>
        </div>
        <p class='message {{if this.failed "is-error"}}' role='status'>
          {{this.message}}
        </p>
      </form>
    {{/unless}}
    <style scoped>
      .balances {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: var(--boxel-sp-xs);
        margin-bottom: var(--boxel-sp);
      }
      .balance {
        display: grid;
        padding: var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .balance strong {
        font-size: var(--boxel-font-size-xl);
      }
      .label {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .of,
      .none,
      .hint {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .request {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp);
      }
      .field {
        display: grid;
        gap: var(--boxel-sp-5xs);
        font-size: var(--boxel-font-size-sm);
      }
      .wide,
      .hint,
      .message {
        grid-column: 1 / -1;
      }
      .message {
        margin: 0;
        min-height: 1lh;
        color: var(--muted-foreground);
      }
      .message.is-error {
        color: var(--destructive-ink);
      }
    </style>
  </template>
}

interface ManagerPanelSignature {
  Args: {
    team: { id: string }[] | undefined;
    queue: { id: string }[] | undefined;
    away: { id: string }[] | undefined;
    isLoading: boolean;
    context: CardContext | undefined;
    timezone: string;
  };
}

// The manager's view: the Today board, the leave waiting for a decision, and
// the team's attendance records.
class ManagerPanel extends GlimmerComponent<ManagerPanelSignature> {
  @tracked deciding: string | undefined;
  @tracked message: string | undefined;
  @tracked failed = false;

  teamCards = this.args.context?.getCardCollection(this, () =>
    this.args.team?.map((e) => e.id),
  );
  queueCards = this.args.context?.getCardCollection(this, () =>
    this.args.queue?.map((e) => e.id),
  );

  get currentTeam(): { id: string }[] | undefined {
    let cards = (this.teamCards?.cards ?? []) as AttendanceRecord[];
    return cards.length ? currentRecords(cards) : this.args.team;
  }

  get names(): Record<string, string> {
    let names: Record<string, string> = {};
    for (let r of (this.teamCards?.cards ?? []) as AttendanceRecord[]) {
      names[r.userId ?? ''] = r.employeeName ?? '';
    }
    return names;
  }

  get rows(): LeaveRow[] {
    let names = this.names;
    return ((this.queueCards?.cards ?? []) as LeaveRequest[]).map((c) =>
      leaveRow(c, names),
    );
  }

  decide = async (row: LeaveRow, decision: string) => {
    if (this.deciding) {
      return;
    }
    this.deciding = `${row.id}:${decision}`;
    this.message = undefined;
    this.failed = false;
    try {
      await operations(row.card).decideLeave({ decision });
      this.message =
        decision === 'approved' ? 'Leave approved.' : 'Leave declined.';
    } catch (err) {
      this.message = refusal(err);
      this.failed = true;
    } finally {
      this.deciding = undefined;
    }
  };

  get isManager(): boolean {
    return Boolean(this.args.team?.length);
  }

  <template>
    {{#if this.isManager}}
      <section aria-labelledby='today-heading'>
        <h2 id='today-heading'>Today</h2>
        <TodayBoard
          @teamEntries={{@team}}
          @leaveEntries={{@away}}
          @isLoading={{@isLoading}}
          @context={{@context}}
          @timezone={{@timezone}}
        />
      </section>

      <section aria-labelledby='approve-heading'>
        <h2 id='approve-heading'>Leave to approve</h2>
        <LeaveList
          @rows={{this.rows}}
          @context={{@context}}
          @decide={{true}}
          @deciding={{this.deciding}}
          @onDecide={{this.decide}}
        >
          <:empty><p class='sub'>Nothing is waiting for you.</p></:empty>
        </LeaveList>
        <p class='message {{if this.failed "is-error"}}' role='status'>
          {{this.message}}
        </p>
      </section>

      <section aria-labelledby='team-heading'>
        <h2 id='team-heading'>My team</h2>
        <LiveRecords
          @entries={{this.currentTeam}}
          @isLoading={{@isLoading}}
          @context={{@context}}
        >
          <:empty>
            <p class='sub'>Nobody reports to you here.</p>
          </:empty>
        </LiveRecords>
      </section>
    {{/if}}
    <style scoped>
      h2 {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size);
      }
      .sub {
        margin: 0;
        color: var(--muted-foreground);
      }
      .message {
        margin: 0;
        min-height: 1lh;
        color: var(--muted-foreground);
      }
      .message.is-error {
        color: var(--destructive-ink);
      }
    </style>
  </template>
}

class AppView extends Component<typeof AttendanceApp> {
  // Each saved search answers only for the person signed in: their own record
  // and leave, the records and leave of the people they manage.
  mine = operations<typeof AttendanceRecord>(AttendanceRecord).mine.query({});
  myTeam = operations<typeof AttendanceRecord>(AttendanceRecord).myTeam.query(
    {},
  );
  myLeave = operations<typeof LeaveRequest>(LeaveRequest).myLeave.query({});
  leaveToApprove = operations<typeof LeaveRequest>(
    LeaveRequest,
  ).leaveToApprove.query({});
  // Leave that ended before yesterday is no use to the board. A day of slack
  // keeps a leave that ends today listed in any zone.
  @cached
  get teamLeave() {
    let yesterday = localClock(
      new Date(Date.now() - 86_400_000),
      this.timezone,
    ).day;
    return operations<typeof LeaveRequest>(LeaveRequest).teamLeave.query({
      since: yesterday,
    });
  }

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
            <FirstRecord
              @entries={{results.entries}}
              @context={{@context}}
              as |record|
            >
              {{#if record}}
                <section aria-labelledby='leave-heading' class='leave-section'>
                  <h2 id='leave-heading'>My leave</h2>
                  <@context.searchResultsComponent
                    @query={{this.myLeave}}
                    @overlays={{false}}
                    as |leave|
                  >
                    <LeaveSection
                      @record={{record}}
                      @myLeave={{leave.entries}}
                      @context={{@context}}
                    />
                  </@context.searchResultsComponent>
                </section>
              {{/if}}
            </FirstRecord>
          </@context.searchResultsComponent>
        {{/if}}
      </section>

      {{#if @context.searchResultsComponent}}
        <@context.searchResultsComponent
          @query={{this.myTeam}}
          @overlays={{false}}
          as |team|
        >
          <@context.searchResultsComponent
            @query={{this.leaveToApprove}}
            @overlays={{false}}
            as |queue|
          >
            <@context.searchResultsComponent
              @query={{this.teamLeave}}
              @overlays={{false}}
              as |away|
            >
              <ManagerPanel
                @team={{team.entries}}
                @queue={{queue.entries}}
                @away={{away.entries}}
                @isLoading={{team.isLoading}}
                @context={{@context}}
                @timezone={{this.timezone}}
              />
            </@context.searchResultsComponent>
          </@context.searchResultsComponent>
        </@context.searchResultsComponent>
      {{/if}}
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
      .leave-section {
        margin-top: var(--boxel-sp-lg);
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
