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
import { Token } from '@cardstack/pretui/components/token';
import { tokenStyle } from '@cardstack/catalog/components/pretui-helpers';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { Stat } from '@cardstack/pretui/components/stat';
import { Chip } from '@cardstack/pretui/components/chip';
import { FitTile } from '../shared/fit-tile';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

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
  initial: 'primary',
  working: 'primary',
  waiting: 'warning',
  terminal: 'success',
};

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
    statesLabel: plural(states.length, 'state'),
    subline: [applies ? `Applies to ${applies}` : undefined, version]
      .filter(Boolean)
      .join(' · '),
    flowHead: flow.slice(0, -1).join(' → '),
    flowLast: flow.length > 1 ? flow[flow.length - 1] : undefined,
    flowOnly: flow.length === 1 ? flow[0] : undefined,
    facts,
    embFacts: facts.slice(0, 6),
    statesCount: states.length,
    transitionsCount: transitions.length,
    guardedCount: guarded.length,
    pausedCount: paused.length,
    stateRows: states.map((s) => ({
      label: s.label,
      kind: s.kind ?? '—',
      tone: KIND_TONES[s.kind ?? ''] ?? 'neutral',
      detail: [s.kind, s.pausesSlaClock ? 'pauses the SLA clock' : undefined]
        .filter(Boolean)
        .join(' · '),
    })),
    transitionRows: transitions.map((t) => ({
      route: `${t.from} → ${t.to}`,
      guard: guardText(t.guard, t.guardRoleName),
      tone: (t.guard && t.guard !== 'none'
        ? 'warning'
        : 'neutral') as PretuiToneArg,
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
        <header class='eh'>
          <span class='mark' aria-hidden='true'>Wf</span>
          <div class='t'>
            <h3 class='name'>{{this.v.name}}</h3>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.statesCount}}<p class='fact'>{{this.v.flowHead}}{{#if
              this.v.flowLast
            }}
              →
              <b>{{this.v.flowLast}}</b>{{else}}<b
              >{{this.v.flowOnly}}</b>{{/if}}</p>{{/if}}
        <dl class='kv'>
          {{#each this.v.embFacts as |f|}}
            <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
              >{{f.value}}</dd></div>
          {{/each}}
        </dl>
      </article>
      <style scoped>
        .emb {
          container-type: inline-size;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .t {
          display: grid;
          flex: 1;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .name,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta,
        .fact {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .fact b {
          font-weight: 700;
        }
        .kv {
          margin: 0;
          padding: 0 var(--boxel-sp-xs);
        }
        .kv-r {
          display: grid;
          grid-template-columns: 6.25rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Wf</span>
        <span class='name'>{{if @model.name @model.name 'Workflow'}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
          max-width: 100%;
          vertical-align: middle;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          color: var(--card-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          inline-size: 1.125rem;
          block-size: 1.125rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
    edit = () => {
      this.args.editCard?.(this.args.model as Workflow);
    };
    <template>
      <article class='iso'>
        <header class='ih'>
          <span class='mark' aria-hidden='true'>Wf</span>
          <div class='t'>
            <h1 class='name'>{{this.v.name}}</h1>
            <p class='meta'>{{this.v.subline}}</p>
          </div>
          <span class='sts'>
            {{#if this.v.version}}<Chip
                @label={{this.v.version}}
                @tone='neutral'
                @appearance='plain'
              />{{/if}}
            <Chip
              @label={{this.v.statesLabel}}
              @tone='neutral'
              @appearance='plain'
            />
          </span>
          {{#if @editCard}}
            <Button
              @tone='neutral' @appearance='outlined'
              @size='s'
              @icon={{PencilIcon}}
              {{on 'click' this.edit}}
            >Edit</Button>
          {{/if}}
        </header>
        <div class='stats'>
          <Stat
            @label='States'
            @tone='neutral'
            @value={{this.v.statesCount}}
            @hint={{this.pausesHint}}
            @roll={{false}}
          />
          <Stat
            @label='Transitions'
            @tone='primary'
            @value={{this.v.transitionsCount}}
            @hint={{this.guardedHint}}
            @roll={{false}}
          />
          <Stat
            @label='Version'
            @tone='neutral'
            @value={{if this.v.version this.v.version '—'}}
            @hint={{if @model.appliesTo @model.appliesTo '—'}}
            @roll={{false}}
          />
        </div>
        <div class='cols'>
          <div class='main'>
            <section>
              <h2>States</h2>
              {{#each this.v.stateRows as |s|}}
                <div class='row'>
                  <span class='row-id'>
                    <span class='row-name'>{{s.label}}</span>
                    <span class='meta'>{{s.detail}}</span>
                  </span>
                  <Chip
                    @label={{s.kind}}
                    @tone={{s.tone}}
                    @appearance='plain'
                  />
                </div>
              {{else}}
                <p class='row meta'>No states yet</p>
              {{/each}}
            </section>
            <section>
              <h2>Transitions</h2>
              {{#each this.v.transitionRows as |t|}}
                <div class='row'>
                  <span class='row-name'>{{t.route}}</span>
                  <Chip
                    @label={{t.guard}}
                    @tone={{t.tone}}
                    @appearance='plain'
                  />
                </div>
              {{else}}
                <p class='row meta'>No transitions yet</p>
              {{/each}}
            </section>
          </div>
          <aside class='side'>
            <section>
              <h2>Details</h2>
              <dl class='kv'>
                {{#each this.v.facts as |f|}}
                  <div class='kv-r'><dt class='cap'>{{f.key}}</dt><dd
                    >{{f.value}}</dd></div>
                {{/each}}
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          --text-stat: 1.375rem;
        }
        .ih {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          border-bottom: 1px solid var(--border);
        }
        .ih > .mark {
          inline-size: 1.75rem;
          block-size: 1.75rem;
        }
        .t {
          display: grid;
          flex: 1 1 12rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .sts {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-weight: 600;
        }
        .stats {
          display: grid;
          grid-auto-flow: column;
          grid-auto-columns: minmax(0, 1fr);
          border-bottom: 1px solid var(--border);
        }
        .stats > * {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        }
        .main,
        .side {
          min-width: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        section + section {
          border-top: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          min-block-size: 1.75rem;
          margin: 0;
          padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .row-id {
          display: grid;
          min-width: 0;
        }
        .row-name {
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv {
          margin: 0;
        }
        .kv-r {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-xs);
          align-items: center;
          min-block-size: 1.75rem;
          padding-inline: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .kv-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex: none;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        @container (max-width: 40rem) {
          .stats {
            grid-auto-flow: row;
          }
          .stats > * + * {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return wfView(this.args.model);
    }
    <template>
      <FitTile>
        <:avatar>
          {{! the record's type mark, not a person: a square, not an Avatar }}
          <span class='mark' aria-hidden='true'>Wf</span>
        </:avatar>
        <:title><span
            class='ell'
            role='heading'
            aria-level='3'
          >{{this.v.name}}</span></:title>
        <:subtitle>{{this.v.subline}}</:subtitle>
        <:status>{{#if this.v.version}}<Chip
              @label={{this.v.version}}
              @tone='neutral'
              @appearance='plain'
            />{{else}}<Chip
              @label={{this.v.statesLabel}}
              @tone='neutral'
              @appearance='plain'
            />{{/if}}</:status>
        <:fact>
          {{! rows ranked by priority; container queries drop whole rows }}
          <dl class='fr'>
            {{#each this.v.facts as |f|}}
              <div class='fr-r'><dt class='cap'>{{f.key}}</dt><dd
                >{{f.value}}</dd></div>
            {{/each}}
          </dl>
        </:fact>
      </FitTile>
      <style scoped>
        .ell {
          display: block;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 1.375rem;
          block-size: 1.375rem;
          border-radius: calc(var(--radius) / 2);
          background: var(--muted);
          color: var(--card-foreground);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          line-height: 1.2;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          white-space: normal;
          color: var(--muted-foreground);
        }
        .fr {
          display: grid;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .fr-r {
          display: grid;
          grid-template-columns: 5rem minmax(0, 1fr);
          column-gap: var(--boxel-sp-2xs);
          align-items: center;
          block-size: 1.75rem;
          border-top: 1px solid var(--border);
          overflow: hidden;
        }
        .fr-r dd {
          margin: 0;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fr-r:nth-child(n + 13) {
          display: none;
        }
        @container fitted-card (width < 250px) {
          .fr-r {
            grid-template-columns: minmax(0, 1fr);
          }
          .fr-r dt {
            display: none;
          }
        }
        @container fitted-card (width >= 400px) {
          .fr-r {
            grid-template-columns: 6.75rem minmax(0, 1fr);
          }
        }
        @container fitted-card (height < 445px) and (width < 400px) {
          .fr-r:nth-child(n + 7) {
            display: none;
          }
        }
        @container fitted-card (height < 445px) and (width >= 400px) {
          .fr-r:nth-child(n + 8) {
            display: none;
          }
        }
        @container fitted-card (height < 275px) {
          .fr-r:nth-child(n + 6) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width < 400px) {
          .fr-r:nth-child(n + 3) {
            display: none;
          }
        }
        @container fitted-card (height < 250px) and (width >= 400px) {
          .fr-r:nth-child(n + 4) {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width < 400px) {
          .fr {
            display: none;
          }
        }
        @container fitted-card (height < 170px) and (width >= 400px) {
          .fr-r:nth-child(n + 2) {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Workflow;
