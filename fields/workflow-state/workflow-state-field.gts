import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import RouteIcon from '@cardstack/boxel-icons/route';

import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

export const WORKFLOW_STATE_KINDS = [
  'initial',
  'working',
  'waiting',
  'terminal',
] as const;

export const WorkflowStateKindField = enumField(StringField, {
  displayName: 'Workflow State Kind',
  options: WORKFLOW_STATE_KINDS as unknown as string[],
});

/** One hue per KIND, not per state — states are data, kinds are the enum. */
export const WORKFLOW_KIND_HUES: Record<string, Hue> = {
  initial: 'blue',
  working: 'teal',
  waiting: 'slate',
  terminal: 'green',
};

export function workflowKindColor(kind?: string | null): StateColor {
  return stateColor(WORKFLOW_KIND_HUES[kind ?? 'working'] ?? 'slate');
}

/**
 * One state in a data-driven workflow. Unlike a fixed status enum (the
 * catalog's `statusField` factory, which owns the STATIC case), these are rows in a
 * Workflow card that an ops lead edits without an engineer.
 *
 * `kind` is the load-bearing part: `waiting` states pause SLA clocks (the
 * Run Workflow command reads `pausesSlaClock` at transition time), `terminal`
 * states are the ones a consumer offers Archive on, `initial` is where minting
 * happens.
 */
export class WorkflowStateField extends FieldDef {
  static displayName = 'Workflow State';
  static icon = RouteIcon;

  @field key = contains(StringField, {
    description: 'Stable slug, e.g. "qa-review". Never renamed once in use.',
  });
  @field label = contains(StringField);
  @field kind = contains(WorkflowStateKindField);
  @field pausesSlaClock = contains(BooleanField, {
    description: 'True for waiting-on-customer style states.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: WorkflowStateField) {
      return this.label ?? this.key ?? 'State';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get chipStyle() {
      let c = workflowKindColor(this.args.model.kind);
      return `--wfs-fg: ${c.fg}; --wfs-bg: ${c.bg};`;
    }
    <template>
      <span class='wfs' style={{this.chipStyle}}>
        {{if @model.label @model.label @model.key}}
        {{#if @model.pausesSlaClock}}<span
            class='wfs-pause'
            title='Pauses SLA clocks'
          >⏸</span>{{/if}}
      </span>
      <style scoped>
        .wfs {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          border-radius: 999px;
          padding: 0.125rem 0.625rem;
          background: var(--wfs-bg);
          color: var(--wfs-fg);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          white-space: nowrap;
        }
        .wfs-pause {
          font-size: 0.625rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='wfs-atom'>{{if @model.label @model.label @model.key}}</span>
      <style scoped>
        .wfs-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

export default WorkflowStateField;
