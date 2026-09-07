import { Component, StringField } from 'https://cardstack.com/base/card-api';
import enumField from 'https://cardstack.com/base/enum';
import CircleDotIcon from '@cardstack/boxel-icons/circle-dot';

import { StatePill, type Hue } from '../../components/state-pill';

/**
 * A lifecycle status: the option set, the colour of each option, and the legal
 * moves between them are all supplied by the consumer.
 *
 * The transition graph is the part worth having. Without it every status field
 * is a free-text dropdown and every lifecycle is one careless click away from a
 * record that skipped the middle of its own process. Storing the graph next to
 * the options lets the field answer "may I?" instead of only "what are the
 * choices?".
 */
export interface StatusOption {
  value: string;
  label?: string;
  hue?: Hue;
  /**
   * Nothing follows a terminal status except a deliberate re-open. Consumers
   * read it to grey out actions rather than to block them.
   */
  terminal?: boolean;
  /**
   * Free-form marker for consumers with a clock: a service desk reads it to
   * stop the SLA timer, a billing app to stop dunning. The block itself never
   * interprets it.
   */
  holds?: boolean;
  /**
   * One line explaining what the status MEANS, in the reader's words: the
   * consequence, not the name restated. Consumers render it where the choice
   * is made, as a menu subtitle or hover hint.
   */
  meaning?: string;
}

export interface StatusFieldConfig {
  options: StatusOption[];
  /** value → the values that may follow it. Absent = anything goes. */
  transitions?: Record<string, string[]>;
  displayName?: string;
  icon?: unknown;
}

export interface StatusFieldClass {
  statusOptions: StatusOption[];
  statusTransitions?: Record<string, string[]>;
}

function optionOf(
  options: StatusOption[],
  value?: string | null,
): StatusOption | undefined {
  return options.find((o) => o.value === value);
}

/**
 * Build a status field bound to one lifecycle.
 *
 * Returns a real FieldDef subclass, so the edit template is the constrained
 * dropdown that comes with `enumField`: no hand-rolled select, and no way to
 * store a value that is not in the list.
 */
export function statusField(config: StatusFieldConfig) {
  let { options, transitions } = config;

  let Base = enumField(StringField, {
    displayName: config.displayName ?? 'Status',
    icon: config.icon ?? CircleDotIcon,
    options: options.map((o) => ({
      value: o.value,
      label: o.label ?? o.value,
    })),
  });

  class Status extends Base {
    static displayName = config.displayName ?? 'Status';
    static statusOptions = options;
    static statusTransitions = transitions;

    static embedded = class Embedded extends Component<typeof this> {
      get option() {
        return optionOf(options, this.args.model as unknown as string);
      }
      <template>
        <StatePill
          @label={{if this.option.label this.option.label @model}}
          @hue={{this.option.hue}}
          @dot={{true}}
        />
      </template>
    };

    static atom = class Atom extends Component<typeof this> {
      get option() {
        return optionOf(options, this.args.model as unknown as string);
      }
      <template>
        <StatePill @label={{@model}} @hue={{this.option.hue}} />
      </template>
    };
  }

  return Status;
}

/** Whether `to` may follow `from` under this field's graph. */
export function canTransition(
  fieldClass: StatusFieldClass,
  from?: string | null,
  to?: string | null,
): boolean {
  if (!from || !to || from === to) {
    return false;
  }
  let graph = fieldClass.statusTransitions;
  if (!graph) {
    return true;
  }
  return (graph[from] ?? []).includes(to);
}

/** The statuses reachable from here, which is what an action menu should offer. */
export function nextStatuses(
  fieldClass: StatusFieldClass,
  from?: string | null,
): StatusOption[] {
  let graph = fieldClass.statusTransitions;
  let allowed = from && graph ? (graph[from] ?? []) : undefined;
  return fieldClass.statusOptions.filter((o) =>
    allowed ? allowed.includes(o.value) : o.value !== from,
  );
}

export function statusOption(
  fieldClass: StatusFieldClass,
  value?: string | null,
): StatusOption | undefined {
  return optionOf(fieldClass.statusOptions, value);
}

export function statusHue(
  fieldClass: StatusFieldClass,
  value?: string | null,
): Hue {
  return optionOf(fieldClass.statusOptions, value)?.hue ?? 'slate';
}

/**
 * A neutral four-state lifecycle for consumers that just want a status and do
 * not have opinions yet. Anything with a real process should call
 * `statusField` with its own options instead of adopting this.
 */
export const StatusField = statusField({
  displayName: 'Status',
  options: [
    { value: 'Draft', hue: 'slate' },
    { value: 'Active', hue: 'teal' },
    { value: 'Done', hue: 'green', terminal: true, holds: true },
    { value: 'Cancelled', hue: 'slate', terminal: true, holds: true },
  ],
  transitions: {
    Draft: ['Active', 'Cancelled'],
    Active: ['Done', 'Cancelled'],
    Done: ['Active'],
    Cancelled: ['Active'],
  },
});

export default StatusField;
