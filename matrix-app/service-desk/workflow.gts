import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import RouteIcon from '@cardstack/boxel-icons/route';
import { WorkflowStateField } from '@cardstack/catalog/fields/workflow-state/workflow-state-field';
import { Token } from '../../ui-component/components/token';
import { tokenStyle } from '@cardstack/catalog/components/pretui-helpers';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { FittedExtras } from '../procurement/vendor';

export const TRANSITION_GUARDS = [
  'none',
  'requires-note',
  'requires-role',
] as const;

export const TransitionGuardField = enumField(StringField, {
  displayName: 'Transition Guard',
  options: TRANSITION_GUARDS as unknown as string[],
});

/** One allowed move between two state keys, with its guard. */
export class TransitionField extends FieldDef {
  static displayName = 'Transition';

  @field from = contains(StringField, { description: 'State key.' });
  @field to = contains(StringField, { description: 'State key.' });
  @field guard = contains(TransitionGuardField);
  @field guardRoleName = contains(StringField, {
    description: 'Role required, when guard is requires-role.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: TransitionField) {
      let g = this.guard && this.guard !== 'none' ? ` (${this.guard})` : '';
      return `${this.from ?? '?'} → ${this.to ?? '?'}${g}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Token
        @value={{@model.title}}
        style={{tokenStyle '--boxel-font-size-xs' 'var(--muted-foreground)'}}
      />
    </template>
  };
}

const KIND_TONES: Record<string, PretuiToneArg> = {
  initial: 'neutral',
  working: 'primary',
  waiting: 'warning',
  terminal: 'success',
};

function sentence(value?: string | null) {
  return value ? value[0]!.toUpperCase() + value.slice(1) : '';
}
function plural(n: number, word: string) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}
function guardText(g?: string | null, role?: string | null) {
  if (!g || g === 'none') return 'none';
  let text = g.replace('-', ' ');
  return g === 'requires-role' && role ? `${text} · ${role}` : text;
}

/** The strings every SupportWorkflow format shows, read once from the model. */
function wfView(m?: Partial<Workflow>) {
  let states = m?.states ?? [];
  let transitions = m?.transitions ?? [];
  let label = (key?: string | null) =>
    states.find((s) => s.key === key)?.label ?? key ?? '';
  let guarded = transitions.filter((t) => t.guard && t.guard !== 'none');
  let paused = states.filter((s) => s.pausesSlaClock);
  let roleGuard = transitions.find((t) => t.guard === 'requires-role');
  let noteGuard = transitions.find((t) => t.guard === 'requires-note');
  let initial = states.find((s) => s.kind === 'initial');
  let terminal = states.find((s) => s.kind === 'terminal');
  let version = m?.version ?? '';
  let applies = m?.appliesTo ?? '';
  let dash = (v?: string | null) => v || '—';
  let guardedText = guarded.length ? plural(guarded.length, 'transition') : '—';
  let pausesText = paused.length ? paused.map((s) => s.label).join(', ') : '—';
  let facts: KeyValueItem[] = [
    { key: 'Applies to', value: dash(applies) },
    { key: 'Version', value: dash(version) },
    { key: 'States', value: String(states.length) },
    { key: 'Transitions', value: String(transitions.length) },
    { key: 'Pauses clock', value: pausesText },
    { key: 'Guarded', value: guardedText },
    { key: 'Initial', value: dash(initial?.label) },
    { key: 'Terminal', value: dash(terminal?.label) },
    { key: 'Role guard', value: dash(roleGuard?.guardRoleName) },
    {
      key: 'Note guard',
      value: noteGuard
        ? `${label(noteGuard.from)} → ${label(noteGuard.to)}`
        : '—',
    },
  ];
  let flow = states.map((s) => s.label);
  return {
    name: m?.name ?? 'Workflow',
    version,
    versionLabel: version.toUpperCase(),
    statesChip: plural(states.length, 'State'),
    subline: [applies ? `Applies to ${applies}` : undefined, version]
      .filter(Boolean)
      .join(' · '),
    flowHead: flow.slice(0, -1).join(' → '),
    flowLast: flow.length > 1 ? flow[flow.length - 1] : undefined,
    flowOnly: flow.length === 1 ? flow[0] : undefined,
    facts,
    statesCount: states.length,
    transitionsCount: transitions.length,
    guardedCount: guarded.length,
    pausedCount: paused.length,
    // guarded share of all transitions, 0-100
    guardedPercent: transitions.length
      ? Math.round((guarded.length / transitions.length) * 100)
      : 0,
    guardedOf: `${guarded.length} of ${transitions.length}`,
    stateRows: states.map((s) => ({
      label: s.label,
      kind: sentence(s.kind),
      tone: KIND_TONES[s.kind ?? ''] ?? 'neutral',
      detail: [s.kind, s.pausesSlaClock ? 'pauses the SLA clock' : undefined]
        .filter(Boolean)
        .join(' · '),
    })),
    transitionRows: transitions.map((t) => ({
      route: `${t.from} → ${t.to}`,
      guard: guardText(t.guard, t.guardRoleName),
    })),
  };
}

/**
 * A team's PROCESS as an editable card: ordered states, guarded
 * transitions. An ops lead adds a "waiting-on-legal" state without an
 * engineer; the Run Workflow command is the single writer that enforces it.
 *
 * VERSIONING RULE: changing `states` or `transitions` after instances run on
 * them is a migration — bump `version` and leave the old keys valid. Keys are
 * never renamed once in use (see WorkflowStateField).
 */
export class Workflow extends CardDef {
  static displayName = 'Workflow';
  static icon = RouteIcon;

  @field name = contains(StringField);
  @field appliesTo = contains(StringField, {
    description: 'Informational card-type name this flow is meant for.',
  });
  @field states = containsMany(WorkflowStateField);
  @field transitions = containsMany(TransitionField);
  @field version = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: Workflow) {
      return this.version
        ? `${this.name ?? 'Workflow'} ${this.version}`
        : (this.name ?? 'Workflow');
    },
  });

  /** Is `from → to` allowed, and behind which guard? */
  findTransition(from?: string | null, to?: string | null) {
    return (this.transitions ?? []).find((t) => t.from === from && t.to === to);
  }

  stateByKey(key?: string | null) {
    return (this.states ?? []).find((s) => s.key === key);
  }

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return wfView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>Wf</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.name}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'>
            {{#if this.v.version}}<Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.versionLabel}}</Chip>{{/if}}
            <Chip
              @tone='primary'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statesChip}}</Chip>
          </span>
        </header>
        <p class='emb-flow'>{{this.v.flowHead}}{{#if this.v.flowLast}}
            →
            <b>{{this.v.flowLast}}</b>{{else}}<b
            >{{this.v.flowOnly}}</b>{{/if}}</p>
        <KeyValue class='emb-facts' @items={{this.v.facts}} @layout='stacked' />
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            container-type: inline-size;
            display: grid;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .emb-sub,
          .emb-flow {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .emb-flow b {
            font-weight: 600;
            color: var(--foreground);
          }
          .emb-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-facts {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          }
          @container (max-width: 25rem) {
            .emb-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .emb-chips {
              grid-column: 1 / -1;
            }
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get v() {
      return wfView(this.args.model);
    }
    <template>
      <span class='atom'>
        <span class='atom-mark' aria-hidden='true'>Wf</span>
        <span class='atom-name'>{{this.v.name}}</span>
        {{#if this.v.version}}<Chip
            @tone='neutral'
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{this.v.versionLabel}}</Chip>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            font-size: var(--boxel-font-size-sm);
          }
          .atom-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .atom-name {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return wfView(this.args.model);
    }
    get pausesHint() {
      return `${this.v.pausedCount} pauses the clock`;
    }
    get guardedHint() {
      return `${this.v.guardedCount} guarded`;
    }
    <template>
      <article class='iso'>
        <header class='iso-head'>
          <span class='iso-mark' aria-hidden='true'>Wf</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{this.v.name}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'>
            {{#if this.v.version}}<Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.versionLabel}}</Chip>{{/if}}
            <Chip
              @tone='primary'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statesChip}}</Chip>
          </span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='States'
              @value={{this.v.statesCount}}
              @hint={{this.pausesHint}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Transitions'
              @value={{this.v.transitionsCount}}
              @hint={{this.guardedHint}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Version'
              @value={{if this.v.version this.v.version '—'}}
              @hint={{@model.appliesTo}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            <Panel @title='States'>
              <ul class='iso-rows'>
                {{#each this.v.stateRows as |s|}}
                  <li class='iso-row'>
                    <span class='iso-row-id'>
                      <span class='iso-row-name'>{{s.label}}</span>
                      <span class='iso-row-sub'>{{s.detail}}</span>
                    </span>
                    <Chip
                      @tone={{s.tone}}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    >{{s.kind}}</Chip>
                  </li>
                {{/each}}
              </ul>
            </Panel>
            <Panel @title='Transitions'>
              <ul class='iso-rows'>
                {{#each this.v.transitionRows as |t|}}
                  <li class='iso-row iso-row-line'>
                    <span class='iso-row-sub'>{{t.route}}</span>
                    <span class='iso-row-name'>{{t.guard}}</span>
                  </li>
                {{/each}}
              </ul>
            </Panel>
          </div>
          <div class='iso-col'>
            <Panel @title='Details'>
              <KeyValue @items={{this.v.facts}} @rows='ruled' />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            min-block-size: 100%;
            background: var(--canvas);
            display: grid;
            gap: var(--boxel-sp);
            padding: var(--boxel-sp-lg);
          }
          .iso-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-title {
            margin: 0;
            font-size: 1.5rem;
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
          }
          .iso-sub {
            margin: 0;
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp);
            min-width: 0;
          }
          .iso-rows {
            margin: 0;
            padding: 0;
            list-style: none;
            display: grid;
          }
          .iso-row {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding-block: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-row:last-child {
            border-bottom: 0;
          }
          .iso-row-id {
            display: grid;
            min-width: 0;
          }
          .iso-row-name {
            font-weight: 600;
          }
          .iso-row-sub {
            color: var(--muted-foreground);
          }
          .iso-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container (max-width: 40rem) {
            .iso-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-chips {
              grid-column: 1 / -1;
            }
            .iso-grid {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return wfView(this.args.model);
    }
    get progress() {
      return this.v.guardedCount
        ? {
            label: 'Guarded transitions',
            value: this.v.guardedPercent,
            valueText: this.v.guardedOf,
          }
        : undefined;
    }

    <template>
      <FittedExtras @facts={{this.v.facts}} @progress={{this.progress}}>
        <FitTile>
          <:avatar>
            {{! the record's type mark, not a person: a square, not an Avatar }}
            <span class='fit-mark' aria-hidden='true'>Wf</span>
          </:avatar>
          <:title><span
              class='fit-title'
              role='heading'
              aria-level='3'
            >{{this.v.name}}</span></:title>
          <:subtitle>{{this.v.subline}}</:subtitle>
          <:status>
            {{#if this.v.version}}<Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.versionLabel}}</Chip>{{/if}}
            <Chip
              @tone='primary'
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.statesChip}}</Chip>
          </:status>
          <:fact>{{this.v.flowHead}}{{#if this.v.flowLast}}
              →
              <b class='fit-last'>{{this.v.flowLast}}</b>{{/if}}</:fact>
        </FitTile>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .fit-last {
            font-weight: 600;
            color: var(--foreground);
          }
        }
      </style>
    </template>
  };
}

export default Workflow;
