import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import DateTimeField from 'https://cardstack.com/base/datetime';
import enumField from 'https://cardstack.com/base/enum';
import TimerIcon from '@cardstack/boxel-icons/timer';
import { SlaTimerBadge } from './components/sla-timer-badge';
import { timerSnapshot } from './utils/sla';

export const TIMER_KINDS = [
  'First response',
  'Next response',
  'Resolution',
] as const;

export const TimerKindField = enumField(StringField, {
  displayName: 'Timer Kind',
  options: TIMER_KINDS as unknown as string[],
});

/**
 * One SLA commitment on one ticket, and the clock running against it.
 *
 * `deadlineAt` is the load-bearing field. It is a plain wall-clock instant that
 * has ALREADY had business hours, holidays and every pause folded into it, and
 * it is written only by the commands that own the ticket's lifecycle. That is
 * what lets everything downstream — this field's computeds, the live badge, the
 * queue's sort — do nothing but subtract two numbers.
 */
export class SlaTimerField extends FieldDef {
  static displayName = 'SLA Timer';
  static icon = TimerIcon;

  @field kind = contains(TimerKindField);
  @field targetMinutes = contains(NumberField, {
    description: 'The committed target in minutes, copied from the policy.',
  });
  @field startedAt = contains(DateTimeField);
  @field deadlineAt = contains(DateTimeField, {
    description:
      'Business-hours-adjusted expiry. Written by commands, never by hand.',
  });
  @field satisfiedAt = contains(DateTimeField);
  @field pausedSince = contains(DateTimeField);
  @field breachedAt = contains(DateTimeField);

  // The three computeds below are the snapshot that prerendered views read.
  // They are correct as of the last write to the ticket and go stale between
  // writes — which is exactly right for a tile in a grid, and exactly wrong
  // for the ticket you have open, where the live badge recomputes instead.
  @field state = contains(StringField, {
    computeVia: function (this: SlaTimerField) {
      return timerSnapshot(this).state;
    },
  });

  @field percentRemaining = contains(NumberField, {
    computeVia: function (this: SlaTimerField) {
      return timerSnapshot(this).percentRemaining ?? undefined;
    },
  });

  @field label = contains(StringField, {
    computeVia: function (this: SlaTimerField) {
      return timerSnapshot(this).shortLabel;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: SlaTimerField) {
      let snapshot = timerSnapshot(this);
      return `${this.kind ?? 'SLA'} — ${snapshot.shortLabel}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <SlaTimerBadge
        @facts={{@model}}
        @caption={{@model.kind}}
        @live={{true}}
        @showBar={{true}}
        class='sla-embedded'
      />
      <style scoped>
        .sla-embedded {
          width: 100%;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template><SlaTimerBadge @facts={{@model}} @live={{false}} /></template>
  };
}
