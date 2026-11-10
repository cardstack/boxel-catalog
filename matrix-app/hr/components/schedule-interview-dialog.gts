import GlimmerComponent from '@glimmer/component';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { not } from '@cardstack/boxel-ui/helpers';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Dialog } from '@cardstack/pretui/components/dialog';
import { Input } from '@cardstack/pretui/components/input';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import {
  ToggleGroup,
  type ToggleOption,
} from '@cardstack/pretui/components/toggle-group';

import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import type { Candidate } from '../candidate';
import type { Employee } from '../employee';
import type { Meeting } from '../meeting';
import { INTERVIEW_ROUND_OPTIONS } from '../interview-round-field';
import {
  DEFAULT_INTERVIEW_MINUTES,
  durationMs,
} from '../commands/schedule-interview-command';

// Working window and slot size for the picker. One hour per slot matches the
// command's DEFAULT_INTERVIEW_MINUTES, so a slot shown as free here is
// exactly the interval the command will re-check server-side.
const WORK_START_HOUR = 9;
const WORK_END_HOUR = 17;
const SLOT_MINUTES = DEFAULT_INTERVIEW_MINUTES;

function toDateStr(d: Date): string {
  let y = d.getFullYear();
  let m = String(d.getMonth() + 1).padStart(2, '0');
  let day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

interface SlotState {
  hour: number;
  label: string;
  free: boolean;
  reason?: string;
}

interface ScheduleInterviewDialogSignature {
  Args: {
    candidate: Candidate;
    employees: Employee[];
    meetings: Meeting[];
    isRunning?: boolean;
    error?: string;
    onConfirm: (opts: {
      date: Date;
      interviewers: Employee[];
      roundType: string;
      ignoreConflicts: boolean;
    }) => void;
    onCancel: () => void;
  };
  Element: HTMLElement;
}

// A plain Glimmer component the caller renders inside {{#if}}, so open →
// close → reopen always starts from a fresh instance; no reset bookkeeping.
//
// The slot row is availability-aware: for the chosen interviewer(s) and day
// it computes which hourly slots (9:00–17:00) are still free from the
// meetings the caller passes in, so the recruiter picks a conflict-free time
// instead of typing one blind. ScheduleInterviewCommand re-checks and throws
// on a clash; that error shows here with a deliberate "book anyway" override.
export class ScheduleInterviewDialog extends GlimmerComponent<ScheduleInterviewDialogSignature> {
  roundTypeOptions = INTERVIEW_ROUND_OPTIONS;

  @tracked dateStr = toDateStr(new Date());
  @tracked selectedInterviewerIds: string[] = [];
  @tracked roundType = 'technical';
  @tracked selectedHour: number | undefined;

  get availableEmployees(): Employee[] {
    return (this.args.employees ?? []).filter(
      (e) => e && e.status !== 'offboarded',
    );
  }

  @cached
  get selectedInterviewers(): Employee[] {
    return this.availableEmployees.filter(
      (e) => e.id && this.selectedInterviewerIds.includes(e.id),
    );
  }

  get interviewerOptions(): ToggleOption[] {
    return this.availableEmployees
      .filter((e) => e.id)
      .map((e) => ({ value: e.id!, label: e.name ?? '' }));
  }

  setInterviewers = (ids: string[]) => {
    this.selectedInterviewerIds = ids;
  };

  // A booked slot stays pickable for the override; its label says it is booked.
  get slotOptions(): ToggleOption[] {
    return this.slots.map((slot) => ({
      value: String(slot.hour),
      label: slot.free ? slot.label : `${slot.label} · ${slot.reason}`,
      disabled: slot.reason === 'In the past',
    }));
  }

  get selectedHourValue(): string | null {
    return this.selectedHour == null ? null : String(this.selectedHour);
  }

  setSlotValue = (value: string | undefined) => {
    this.selectedHour = value == null ? undefined : Number(value);
  };

  setRoundType = (value: string) => {
    this.roundType = value;
  };

  setDate = (value: string) => {
    this.dateStr = value;
  };

  private slotStart(hour: number): Date | undefined {
    let match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(this.dateStr ?? '');
    if (!match) {
      return undefined;
    }
    return new Date(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      hour,
      0,
      0,
      0,
    );
  }

  // The selected interviewers' existing meetings on any day — the overlap
  // test below confines them to the chosen slot's interval, so no separate
  // same-day filter is needed.
  private get relevantMeetings(): Meeting[] {
    let ids = this.selectedInterviewerIds;
    if (!ids.length) {
      return [];
    }
    return (this.args.meetings ?? []).filter(
      (m) =>
        m.date &&
        (m.interviewers ?? []).some((i) => i?.id && ids.includes(i.id)),
    );
  }

  @cached
  get slots(): SlotState[] {
    let now = Date.now();
    let meetings = this.relevantMeetings;
    let result: SlotState[] = [];
    for (let hour = WORK_START_HOUR; hour < WORK_END_HOUR; hour++) {
      let start = this.slotStart(hour);
      let label = `${((hour + 11) % 12) + 1}:00 ${hour < 12 ? 'AM' : 'PM'}`;
      if (!start) {
        result.push({ hour, label, free: false, reason: 'Pick a date first' });
        continue;
      }
      let startMs = start.getTime();
      let endMs = startMs + SLOT_MINUTES * 60000;
      if (endMs <= now) {
        result.push({ hour, label, free: false, reason: 'In the past' });
        continue;
      }
      let clash = meetings.find((m) => {
        let mStart = new Date(m.date!).getTime();
        if (isNaN(mStart)) {
          return false;
        }
        let mEnd = mStart + durationMs(m.duration);
        return startMs < mEnd && mStart < endMs;
      });
      if (clash) {
        result.push({
          hour,
          label,
          free: false,
          reason: `Booked: ${clash.title ?? 'Meeting'}`,
        });
      } else {
        result.push({ hour, label, free: true });
      }
    }
    return result;
  }

  get freeSlotCount(): number {
    return this.slots.filter((s) => s.free).length;
  }

  get selectedSlotState(): SlotState | undefined {
    return this.slots.find((s) => s.hour === this.selectedHour);
  }

  // Busy slots stay selectable — the picker STEERS toward free slots but the
  // COMMAND is the enforcement point (it throws a named conflict, surfaced
  // below with the override). Only past slots are hard-disabled: there is no
  // legitimate "book it anyway" for a time that has already gone by.
  get canConfirm(): boolean {
    let slot = this.selectedSlotState;
    return Boolean(
      !this.args.isRunning &&
      this.selectedInterviewers.length &&
      slot &&
      slot.reason !== 'In the past',
    );
  }

  private buildConfirm(ignoreConflicts: boolean) {
    if (this.selectedHour == null) {
      return;
    }
    let date = this.slotStart(this.selectedHour);
    if (!date) {
      return;
    }
    this.args.onConfirm({
      date,
      interviewers: this.selectedInterviewers,
      roundType: this.roundType,
      ignoreConflicts,
    });
  }

  confirm = () => {
    if (!this.canConfirm) {
      return;
    }
    this.buildConfirm(false);
  };

  // Deliberate human override after the command reported a conflict — the
  // same escape hatch as the command's own `ignoreConflicts` input.
  confirmOverride = () => {
    if (!this.canConfirm) {
      return;
    }
    this.buildConfirm(true);
  };

  // The override answers a booking conflict only, the error Schedule
  // Interview raises for an overlap; any other failure has nothing to
  // override.
  get showOverride(): boolean {
    return Boolean(this.args.error?.includes('is already booked'));
  }

  get title(): string {
    return this.args.candidate?.name
      ? `Schedule interview — ${this.args.candidate.name}`
      : 'Schedule interview';
  }

  <template>
    <Dialog @open={{true}} @onClose={{@onCancel}} @size='m'>
      <:title>{{this.title}}</:title>
      <:default>
        <div class='schedule-dialog'>
          <p class='sd-sub'>Pick interviewers, a day, and a free slot. A slot
            already booked for the chosen interviewers says so; it can still be
            booked with an override.</p>

          <div class='sd-field'>
            <span
              class='sd-label'
              id='sd-interviewers-label'
            >Interviewers</span>
            <ToggleGroup
              @multiple={{true}}
              @label='Interviewers'
              @options={{this.interviewerOptions}}
              @values={{this.selectedInterviewerIds}}
              @onValuesChange={{this.setInterviewers}}
            />
          </div>

          <div class='sd-field'>
            <span class='sd-label' id='sd-round-label'>Round</span>
            <SegmentedControl
              @label='Round'
              @options={{this.roundTypeOptions}}
              @value={{this.roundType}}
              @onValueChange={{this.setRoundType}}
            />
          </div>

          <div class='sd-field'>
            <label class='sd-label' for='sd-date'>Date</label>
            <Input
              class='sd-date'
              @controlId='sd-date'
              @type='date'
              @value={{this.dateStr}}
              @onInput={{this.setDate}}
            />
          </div>

          <div class='sd-field'>
            <span class='sd-label' id='sd-slots-label'>
              Time
              {{#if this.selectedInterviewers.length}}
                ·
                {{this.freeSlotCount}}
                of
                {{this.slots.length}}
                slots free
              {{else}}
                · pick interviewers to see availability
              {{/if}}
            </span>
            <ToggleGroup
              @label='Time'
              @options={{this.slotOptions}}
              @value={{this.selectedHourValue}}
              @onValueChange={{this.setSlotValue}}
            />
          </div>

          {{#if @error}}
            <Alert
              @tone='danger'
              @title='Could not schedule'
              style={{ALERT_STYLE.danger}}
            >{{@error}}</Alert>
          {{/if}}
        </div>
      </:default>
      <:footer>
        <Button
          @tone='neutral'
          @appearance='outlined'
          @disabled={{@isRunning}}
          {{on 'click' @onCancel}}
        >Cancel</Button>
        {{#if this.showOverride}}
          <Button
            @tone='neutral'
            @appearance='outlined'
            @disabled={{not this.canConfirm}}
            {{on 'click' this.confirmOverride}}
          >Book anyway (override)</Button>
        {{/if}}
        <Button
          @tone='primary'
          @appearance='accent'
          @disabled={{not this.canConfirm}}
          @busy={{@isRunning}}
          {{on 'click' this.confirm}}
        >Schedule</Button>
      </:footer>
    </Dialog>
    <style scoped>
      .schedule-dialog {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .sd-sub {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .sd-field {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
      }
      .sd-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .sd-date {
        max-width: 14rem;
      }
    </style>
  </template>
}
