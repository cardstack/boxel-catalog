import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import DateTimeField from 'https://cardstack.com/base/datetime';
import {
  actor,
  bxl,
  operation,
  operations,
  OperationsError,
  params,
  type OperationDeclaration,
} from 'https://cardstack.com/base/operations';
import ClockIcon from '@cardstack/boxel-icons/clock';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Textarea } from '@cardstack/pretui/components/textarea';

import { Employee } from '../hr/employee';
import { ReceptionDisplay } from './reception-display';
import {
  VERDICT_LABEL,
  foldDays,
  isCheckedIn,
  localClock,
  minutesLabel,
  openMinutes,
  openShiftStart,
  todayKey,
  zonedToUtc,
  type FoldedDay,
} from './attendance-day';

// The punch shape production records use, minus the gateway-only network
// fields, plus who made it and where a correction stands.
export class PunchEvent extends FieldDef {
  static displayName = 'Punch';
  @field eventId = contains(StringField);
  // 'punch' or 'correction'
  @field kind = contains(StringField);
  @field direction = contains(StringField);
  @field punchedAt = contains(DateTimeField);
  // 'button', 'kiosk' or 'correction'
  @field assurance = contains(StringField);
  @field kioskId = contains(StringField);
  @field kioskCode = contains(StringField);
  @field by = contains(StringField);
  @field reason = contains(StringField);
  // 'recorded' for a punch; 'pending', 'approved' or 'declined' for a correction
  @field state = contains(StringField);
  @field requestedAt = contains(DateTimeField);
  @field decidedBy = contains(StringField);
  @field decidedAt = contains(DateTimeField);
}

export class WorkSchedule extends FieldDef {
  static displayName = 'Work Schedule';
  // An IANA zone such as America/New_York; it decides the day and late or early
  @field timezone = contains(StringField);
  @field scheduledArrival = contains(StringField);
  @field scheduledDeparture = contains(StringField);
  @field graceMinutes = contains(NumberField);
}

export class AttendanceDay extends FieldDef {
  static displayName = 'Attendance Day';
  @field day = contains(StringField);
  @field firstIn = contains(StringField);
  @field lastOut = contains(StringField);
  @field minutes = contains(NumberField);
  @field punchCount = contains(NumberField);
  @field lateBy = contains(NumberField);
  @field earlyBy = contains(NumberField);
  @field verdict = contains(StringField);
}

// Every write stamps the realm's own clock. NOW() is only allowed in `input`,
// and is UTC.
const STAMP_PUNCH = bxl`NOW() as $n | . + { punchedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z") }`;

function refusal(err: unknown): string {
  if (err instanceof OperationsError) {
    return err.detail ?? err.message;
  }
  return err instanceof Error ? err.message : String(err);
}

class RecordView extends Component<typeof AttendanceRecord> {
  @tracked running: string | undefined;
  @tracked message: string | undefined;
  @tracked failed = false;
  @tracked code = '';

  get record(): AttendanceRecord {
    return this.args.model as AttendanceRecord;
  }

  // Every operation here gets the realm's clock (and a correction's id) from
  // its `input` stage, so the caller sends less than the declared params the
  // typed signature lists. This handle takes the payload as sent.
  get ops() {
    return operations(this.record);
  }

  get timezone(): string {
    return this.record.schedule?.timezone || 'UTC';
  }

  get days(): FoldedDay[] {
    return foldDays(this.record.punches, this.record.schedule);
  }

  get today(): FoldedDay | undefined {
    let key = todayKey(this.timezone);
    return this.days.find((d) => d.key === key);
  }

  get isIn(): boolean {
    return isCheckedIn(this.record.punches);
  }

  get todayLine(): string {
    let d = this.today;
    let start = openShiftStart(this.record.punches);
    if (start) {
      let opened = localClock(start, this.timezone);
      let since =
        opened.day === todayKey(this.timezone)
          ? opened.label
          : `${opened.label} yesterday`;
      // Today's closed shifts, plus the open one from when it started.
      let worked = (d?.minutes ?? 0) + openMinutes(this.record.punches);
      return `In since ${since} · ${minutesLabel(worked)}`;
    }
    if (!d) {
      return 'Not checked in today';
    }
    return `${d.firstIn || '—'}–${d.lastOut || '—'} · ${minutesLabel(d.minutes)}`;
  }

  // Hide on a definite no only; undefined is "not answered yet".
  denied(name: string): boolean {
    return this.args.context?.canInvoke?.(name, this.record) === false;
  }

  get hideCheckIn(): boolean {
    return (
      this.isIn || Boolean(this.record.requiresCode) || this.denied('checkIn')
    );
  }

  get hideCheckOut(): boolean {
    return !this.isIn || this.denied('checkOut');
  }

  get showCodeCheckIn(): boolean {
    return (
      !this.isIn &&
      Boolean(this.record.requiresCode) &&
      !this.denied('checkInWithCode')
    );
  }

  isBusy = (name: string): boolean => this.running === name;

  // The clicked button shows its busy state; the others are disabled, since
  // a native disabled would cancel the busy state and drop focus.
  otherBusy = (name: string): boolean =>
    this.running !== undefined && this.running !== name;

  run = async (name: string, invoke: () => Promise<unknown>, done: string) => {
    if (this.running) {
      return;
    }
    this.running = name;
    this.message = undefined;
    this.failed = false;
    try {
      await invoke();
      this.message = done;
    } catch (err) {
      this.message = refusal(err);
      this.failed = true;
    } finally {
      this.running = undefined;
    }
  };

  checkIn = () =>
    this.run('checkIn', () => this.ops.checkIn({}), 'Checked in.');

  checkOut = () =>
    this.run('checkOut', () => this.ops.checkOut({}), 'Checked out.');

  setCode = (value: string) => (this.code = value.trim().toUpperCase());

  checkInWithCode = (event?: Event) => {
    event?.preventDefault();
    return this.run(
      'checkInWithCode',
      async () => {
        if (!this.code) {
          throw new Error('Enter the code shown on the reception screen.');
        }
        await this.ops.checkInWithCode({ code: this.code });
        this.code = '';
      },
      'Checked in at reception.',
    );
  };
}

class Embedded extends RecordView {
  <template>
    <article class='record'>
      <div class='who'>
        <span class='name'>{{this.record.employeeName}}</span>
        <span class='status {{if this.isIn "is-in"}}'>{{if
            this.isIn
            'In'
            'Out'
          }}</span>
      </div>
      <p class='today'>{{this.todayLine}}</p>
      <div class='actions'>
        {{#unless this.hideCheckIn}}
          <Button
            @tone='primary'
            @appearance='accent'
            @busy={{this.isBusy 'checkIn'}}
            @busyLabel='Checking in…'
            @disabled={{this.otherBusy 'checkIn'}}
            {{on 'click' this.checkIn}}
          >Check in</Button>
        {{/unless}}
        {{#unless this.hideCheckOut}}
          <Button
            @appearance='outlined'
            @busy={{this.isBusy 'checkOut'}}
            @busyLabel='Checking out…'
            @disabled={{this.otherBusy 'checkOut'}}
            {{on 'click' this.checkOut}}
          >Check out</Button>
        {{/unless}}
      </div>
      {{#if this.showCodeCheckIn}}
        <form
          class='code'
          aria-label='Check in with the reception code'
          {{on 'submit' this.checkInWithCode}}
        >
          <Input
            @value={{this.code}}
            @onInput={{this.setCode}}
            @placeholder='Code on the reception screen'
            aria-label='Reception code'
          />
          <Button
            type='submit'
            @busy={{this.isBusy 'checkInWithCode'}}
            @busyLabel='Checking in…'
            @disabled={{this.otherBusy 'checkInWithCode'}}
          >Check in with code</Button>
        </form>
      {{/if}}
      <p class='message {{if this.failed "is-error"}}' role='status'>
        {{this.message}}
      </p>
    </article>
    <style scoped>
      .record {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
      }
      .who {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .name {
        font-weight: 600;
      }
      .status {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .status.is-in {
        color: var(--success);
        font-weight: 600;
      }
      .today {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .actions,
      .code {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .message {
        margin: 0;
        min-height: 1lh;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .message.is-error {
        color: var(--destructive);
      }
    </style>
  </template>
}

function nonce(): string {
  let bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

class Isolated extends RecordView {
  @tracked correctionDirection = 'in';
  @tracked correctionAt = '';
  @tracked correctionReason = '';
  @tracked deciding: string | undefined;

  directionOptions = [
    { value: 'in', label: 'Check in' },
    { value: 'out', label: 'Check out' },
  ];

  get recentDays(): (FoldedDay & { label: string; hours: string })[] {
    return this.days
      .slice(-14)
      .reverse()
      .map((d) => ({
        ...d,
        label: VERDICT_LABEL[d.verdict],
        hours: minutesLabel(d.minutes),
      }));
  }

  localTime(at: Date | string): string {
    let { day, label } = localClock(new Date(at), this.timezone);
    return `${day} ${label}`;
  }

  get corrections() {
    return (this.record.punches ?? [])
      .filter((p) => p.kind === 'correction')
      .map((p) => ({
        eventId: p.eventId ?? '',
        direction: p.direction === 'out' ? 'Check out' : 'Check in',
        at: p.punchedAt ? this.localTime(p.punchedAt) : '—',
        reason: p.reason ?? '',
        state: p.state ?? 'pending',
        isPending: p.state === 'pending',
      }))
      .reverse();
  }

  get hideRequest(): boolean {
    return this.denied('requestCorrection');
  }

  get hideDecide(): boolean {
    return this.denied('decideCorrection');
  }

  setDirection = (value: string) => (this.correctionDirection = value);
  setAt = (value: string) => (this.correctionAt = value);
  setReason = (value: string) => (this.correctionReason = value);

  isDeciding = (eventId: string, decision: string): boolean =>
    this.deciding === `${eventId}:${decision}`;

  otherDeciding = (eventId: string, decision: string): boolean =>
    this.running !== undefined && !this.isDeciding(eventId, decision);

  requestCorrection = (event?: Event) => {
    event?.preventDefault();
    return this.run(
      'requestCorrection',
      async () => {
        // The time is typed on the organization's clock, not the device's.
        let at = this.correctionAt
          ? zonedToUtc(this.correctionAt, this.timezone)
          : null;
        if (!at) {
          throw new Error('Enter the date and time of the missing punch.');
        }
        await this.ops.requestCorrection({
          direction: this.correctionDirection,
          punchedAt: at.toISOString().replace('.000Z', 'Z'),
          reason: this.correctionReason,
          nonce: nonce(),
        });
        this.correctionAt = '';
        this.correctionReason = '';
      },
      'Correction sent to your manager.',
    );
  };

  decide = async (eventId: string, decision: 'approved' | 'declined') => {
    this.deciding = `${eventId}:${decision}`;
    try {
      await this.run(
        'decideCorrection',
        () => this.ops.decideCorrection({ eventId, decision }),
        decision === 'approved'
          ? 'Correction approved.'
          : 'Correction declined.',
      );
    } finally {
      this.deciding = undefined;
    }
  };

  <template>
    <article class='sheet'>
      <header class='head'>
        <div>
          <h1>{{this.record.employeeName}}</h1>
          <p class='sub'>{{this.record.year}} · {{this.todayLine}}</p>
        </div>
        <div class='actions'>
          {{#unless this.hideCheckIn}}
            <Button
              @tone='primary'
              @appearance='accent'
              @size='l'
              @busy={{this.isBusy 'checkIn'}}
              @busyLabel='Checking in…'
              @disabled={{this.otherBusy 'checkIn'}}
              {{on 'click' this.checkIn}}
            >Check in</Button>
          {{/unless}}
          {{#unless this.hideCheckOut}}
            <Button
              @appearance='outlined'
              @size='l'
              @busy={{this.isBusy 'checkOut'}}
              @busyLabel='Checking out…'
              @disabled={{this.otherBusy 'checkOut'}}
              {{on 'click' this.checkOut}}
            >Check out</Button>
          {{/unless}}
        </div>
      </header>

      {{#if this.showCodeCheckIn}}
        <form
          class='code'
          aria-label='Check in with the reception code'
          {{on 'submit' this.checkInWithCode}}
        >
          <Input
            @value={{this.code}}
            @onInput={{this.setCode}}
            @placeholder='Code on the reception screen'
            aria-label='Reception code'
          />
          <Button
            type='submit'
            @busy={{this.isBusy 'checkInWithCode'}}
            @busyLabel='Checking in…'
            @disabled={{this.otherBusy 'checkInWithCode'}}
          >Check in with code</Button>
        </form>
      {{/if}}

      <p class='message {{if this.failed "is-error"}}' role='status'>
        {{this.message}}
      </p>

      <section>
        <h2>Recent days</h2>
        {{#if this.recentDays.length}}
          <table class='days'>
            <thead>
              <tr><th>Day</th><th>In</th><th>Out</th><th>Time</th><th
                >Status</th></tr>
            </thead>
            <tbody>
              {{#each this.recentDays as |d|}}
                <tr>
                  <td>{{d.key}}</td>
                  <td>{{if d.firstIn d.firstIn '—'}}</td>
                  <td>{{if d.lastOut d.lastOut '—'}}</td>
                  <td>{{d.hours}}</td>
                  <td class='verdict {{d.verdict}}'>{{d.label}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        {{else}}
          <EmptyState
            @title='No punches yet'
            @message='Check in to start this year’s record.'
          />
        {{/if}}
      </section>

      <section>
        <h2>Corrections</h2>
        {{#each this.corrections as |c|}}
          <div class='correction'>
            <div>
              <strong>{{c.direction}}</strong>
              at
              {{c.at}}
              <span class='state {{c.state}}'>{{c.state}}</span>
              <p class='reason'>{{c.reason}}</p>
            </div>
            {{#if c.isPending}}
              {{#unless this.hideDecide}}
                <div class='decide'>
                  <Button
                    @tone='success'
                    @appearance='outlined'
                    @size='s'
                    @busy={{this.isDeciding c.eventId 'approved'}}
                    @disabled={{this.otherDeciding c.eventId 'approved'}}
                    {{on 'click' (fn this.decide c.eventId 'approved')}}
                  >Approve</Button>
                  <Button
                    @tone='danger'
                    @appearance='outlined'
                    @size='s'
                    @busy={{this.isDeciding c.eventId 'declined'}}
                    @disabled={{this.otherDeciding c.eventId 'declined'}}
                    {{on 'click' (fn this.decide c.eventId 'declined')}}
                  >Decline</Button>
                </div>
              {{/unless}}
            {{/if}}
          </div>
        {{else}}
          <p class='none'>No corrections requested.</p>
        {{/each}}

        {{#unless this.hideRequest}}
          <form
            class='request'
            aria-label='Request a correction'
            {{on 'submit' this.requestCorrection}}
          >
            <h3>Missing or wrong punch?</h3>
            <fieldset class='direction'>
              <legend>Which punch is missing</legend>
              <SegmentedControl
                @options={{this.directionOptions}}
                @value={{this.correctionDirection}}
                @onValueChange={{this.setDirection}}
              />
            </fieldset>
            <label class='label'>
              When ({{this.timezone}})
              <Input
                @type='datetime-local'
                @value={{this.correctionAt}}
                @onInput={{this.setAt}}
              />
            </label>
            <label class='label'>
              What happened
              <Textarea
                @value={{this.correctionReason}}
                @onInput={{this.setReason}}
                @placeholder='For example: forgot to check out'
              />
            </label>
            <div>
              <Button
                type='submit'
                @busy={{this.isBusy 'requestCorrection'}}
                @busyLabel='Sending…'
                @disabled={{this.otherBusy 'requestCorrection'}}
              >Send to my manager</Button>
            </div>
          </form>
        {{/unless}}
      </section>
    </article>
    <style scoped>
      .sheet {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        max-width: 48rem;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        align-items: flex-end;
        gap: var(--boxel-sp);
      }
      h1 {
        margin: 0;
        font-size: var(--boxel-font-size-xl);
      }
      h2 {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size);
      }
      h3 {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
      }
      .sub,
      .none,
      .reason {
        margin: 0;
        color: var(--muted-foreground);
      }
      .actions,
      .decide,
      .code {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .message {
        margin: 0;
        min-height: 1lh;
        color: var(--muted-foreground);
      }
      .message.is-error {
        color: var(--destructive);
      }
      .days {
        width: 100%;
        border-collapse: collapse;
        font-variant-numeric: tabular-nums;
      }
      .days th,
      .days td {
        text-align: start;
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border-bottom: 1px solid var(--border);
      }
      .days th {
        color: var(--muted-foreground);
        font-weight: 500;
      }
      .verdict.late,
      .verdict.early,
      .verdict.late-early,
      .verdict.no-checkout {
        color: var(--destructive);
      }
      .correction {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .state {
        margin-inline-start: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
      .state.approved {
        color: var(--success);
      }
      .state.declined {
        color: var(--destructive);
      }
      .request {
        display: grid;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp);
      }
      .direction {
        display: grid;
        gap: var(--boxel-sp-5xs);
        margin: 0;
        padding: 0;
        border: 0;
      }
      .direction legend,
      .label {
        font-size: var(--boxel-font-size-sm);
      }
      .label {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
    </style>
  </template>
}

// One person's attendance for one year. The employee lives in the ERP realm;
// `userId` and `managerUserId` are copied here because a realm policy grant
// reads the record's own fields, never a linked card's.
export class AttendanceRecord extends CardDef {
  static displayName = 'Attendance Record';
  static icon = ClockIcon;

  @field employee = linksTo(Employee);
  @field userId = contains(StringField);
  @field managerUserId = contains(StringField);
  @field year = contains(StringField);
  @field schedule = contains(WorkSchedule);
  @field punches = containsMany(PunchEvent);
  // The reception display whose code a check-in with code is matched against.
  // Staff can't read it, so the screen reads `requiresCode` instead.
  @field display = linksTo(ReceptionDisplay, { searchable: true });
  @field requiresCode = contains(BooleanField, {
    description:
      'Check in only with the code on the linked reception display. Set it together with display',
  });

  @field employeeName = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return this.employee?.name || this.userId || 'Unknown employee';
    },
  });

  // As of the last index; templates read isCheckedIn live.
  @field status = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return isCheckedIn(this.punches) ? 'in' : 'out';
    },
  });

  @field days = containsMany(AttendanceDay, {
    computeVia: function (this: AttendanceRecord) {
      return foldDays(this.punches, this.schedule).map(
        (d) =>
          new AttendanceDay({
            day: d.key,
            firstIn: d.firstIn,
            lastOut: d.lastOut,
            minutes: d.minutes,
            punchCount: d.punchCount,
            lateBy: d.lateBy,
            earlyBy: d.earlyBy,
            verdict: d.verdict,
          }),
      );
    },
  });

  @field pendingCorrections = contains(NumberField, {
    computeVia: function (this: AttendanceRecord) {
      return (this.punches ?? []).filter(
        (p) => p.kind === 'correction' && p.state === 'pending',
      ).length;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return `${this.employeeName} · ${this.year ?? ''}`.trim();
    },
  });

  @operation static read = {
    base: 'read',
    links: 'ids',
  } satisfies OperationDeclaration;

  @operation static checkIn = {
    base: 'transform',
    params: { punchedAt: StringField },
    input: STAMP_PUNCH,
    transformations: bxl`
      assert(.requiresCode != true; "Check in with the code on the reception display"; { snapshot: true });
      .punches += [{ kind: "punch", direction: "in", punchedAt: params("punchedAt"), assurance: "button", by: actor(), state: "recorded" }];
    `,
  } satisfies OperationDeclaration;

  @operation static checkOut = {
    base: 'appendContainsMany',
    field: 'punches',
    params: { punchedAt: StringField },
    input: STAMP_PUNCH,
    item: {
      kind: 'punch',
      direction: 'out',
      punchedAt: params('punchedAt'),
      assurance: 'button',
      by: actor(),
      state: 'recorded',
    },
  } satisfies OperationDeclaration;

  // A check-in that proves presence: the code must be the one the linked
  // reception display shows now or showed just before, issued within the last
  // 165 seconds.
  @operation static checkInWithCode = {
    base: 'transform',
    params: {
      code: StringField,
      punchedAt: StringField,
      cutoff: NumberField,
    },
    input: bxl`NOW() as $n | . + { punchedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z"), cutoff: ($n - 165 / 86400) }`,
    transformations: bxl`
      assert((params("code") | length) > 0; "Enter the code shown on the reception screen");
      assert(OR(.display.code == params("code"); .display.previousCode == params("code")); "That code is not the one on the reception display"; { snapshot: true });
      assert(OR((.display.code == params("code") and .display.issuedAtSerial > params("cutoff")); (.display.previousCode == params("code") and .display.previousIssuedAtSerial > params("cutoff"))); "That code has expired. Scan the display again"; { snapshot: true });
      .punches += [{ kind: "punch", direction: "in", punchedAt: params("punchedAt"), assurance: "kiosk", kioskCode: params("code"), by: actor(), state: "recorded" }];
    `,
  } satisfies OperationDeclaration;

  @operation static requestCorrection = {
    base: 'transform',
    params: {
      direction: StringField,
      punchedAt: StringField,
      reason: StringField,
      eventId: StringField,
      requestedAt: StringField,
      nonce: StringField,
    },
    input: bxl`NOW() as $n | . + { eventId: ("c-" + TEXT($n; "yyyymmddhhmmss") + "-" + params("nonce")), requestedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z") }`,
    // punchedAt is the caller's, so its shape is checked here: a UTC time to
    // the second, no later than now. Same-shape ISO strings compare in order.
    transformations: bxl`
      assert(OR(params("direction") == "in"; params("direction") == "out"); "Say whether the missing punch was a check in or a check out");
      assert((params("reason") | length) > 0; "Add a note saying what happened");
      assert((params("nonce") | length) > 0; "The request is missing its id");
      assert(params("punchedAt") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"); "Enter the date and time of the missing punch");
      assert(params("punchedAt") <= params("requestedAt"); "A missing punch can't be in the future");
      assert(any(.punches[]; .eventId == params("eventId")) == false; "That correction was already sent. Send it again to get a new id");
      .punches += [{ eventId: params("eventId"), kind: "correction", direction: params("direction"), punchedAt: params("punchedAt"), assurance: "correction", reason: params("reason"), by: actor(), state: "pending", requestedAt: params("requestedAt") }];
    `,
  } satisfies OperationDeclaration;

  @operation static decideCorrection = {
    base: 'transform',
    params: {
      eventId: StringField,
      decision: StringField,
      decidedAt: StringField,
    },
    input: bxl`NOW() as $n | . + { decidedAt: (TEXT($n; "yyyy-mm-dd") + "T" + TEXT($n; "hh:mm:ss") + "Z") }`,
    transformations: bxl`
      assert(OR(params("decision") == "approved"; params("decision") == "declined"); "A correction is either approved or declined");
      assert(any(.punches[]; .eventId == params("eventId") and .state == "pending"); "That correction is not waiting for a decision");
      (.punches[] | select(.eventId == params("eventId")) | .state) = params("decision");
      (.punches[] | select(.eventId == params("eventId")) | .decidedBy) = actor();
      (.punches[] | select(.eventId == params("eventId")) | .decidedAt) = params("decidedAt");
    `,
  } satisfies OperationDeclaration;

  @operation static mine = {
    base: 'query',
    links: 'ids',
    query: {
      filter: {
        on: () => AttendanceRecord,
        eq: { userId: actor() },
      },
      sort: [{ on: () => AttendanceRecord, by: 'year', direction: 'desc' }],
    },
  } satisfies OperationDeclaration;

  @operation static myTeam = {
    base: 'query',
    links: 'ids',
    query: {
      filter: {
        on: () => AttendanceRecord,
        eq: { managerUserId: actor() },
      },
      sort: [
        { on: () => AttendanceRecord, by: 'employeeName', direction: 'asc' },
      ],
    },
  } satisfies OperationDeclaration;

  static embedded = Embedded;
  static fitted = Embedded;
  static isolated = Isolated;
}
