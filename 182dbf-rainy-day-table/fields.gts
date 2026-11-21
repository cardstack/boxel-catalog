// Field definitions for the Game, Match and Opponent cards, plus the
// converters between Boxel field instances and the engine's plain objects.

import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { JsonField } from '@cardstack/base/json-field';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import type { CompDef, Copy, Look, LogEntry, Seat } from './engine';

// ─── JSON blocks (layout, ruleset, faces…) with a forgiving editor ────────
class JsonEdit extends Component<typeof GameJsonField> {
  @tracked error = '';
  get text() {
    return JSON.stringify(this.args.model ?? null, null, 2);
  }
  commit = (e: Event) => {
    let v = (e.target as HTMLTextAreaElement).value;
    try {
      this.args.set?.(JSON.parse(v));
      this.error = '';
    } catch (err: any) {
      this.error = `Not saved: ${err.message}`;
    }
  };
  <template>
    <div class='json-edit'>
      <textarea
        aria-label='JSON value'
        spellcheck='false'
        rows='10'
        {{on 'change' this.commit}}
      >{{this.text}}</textarea>
      {{#if this.error}}<p class='err' role='alert'>{{this.error}}</p>{{/if}}
    </div>
    <style scoped>
      .json-edit textarea {
        width: 100%;
        min-height: 9rem;
        font:
          12px/1.45 ui-monospace,
          'SF Mono',
          Menlo,
          monospace;
        padding: 0.6rem 0.7rem;
        border: 1px solid var(--boxel-border-color, #ccc);
        border-radius: 6px;
        resize: vertical;
        background: #fffdf9;
      }
      .err {
        color: #9b2f25;
        font-size: 0.8rem;
        margin: 0.3rem 0 0;
      }
    </style>
  </template>
}

export class GameJsonField extends JsonField {
  static displayName = 'JSON';
  static embedded = class Embedded extends Component<typeof this> {
    get summary() {
      let v = this.args.model as any;
      if (v === null || v === undefined) return '—';
      if (Array.isArray(v))
        return `${v.length} item${v.length === 1 ? '' : 's'}`;
      if (typeof v === 'object') return Object.keys(v).join(', ') || '{}';
      return String(v);
    }
    <template>
      <code class='json-sum'>{{this.summary}}</code>
      <style scoped>
        .json-sum {
          font-size: 0.8em;
          color: var(--boxel-450, #777);
        }
      </style>
    </template>
  };
  static edit = JsonEdit;
}

// ─── Look and Component Definition ────────────────────────────────────────
export class LookField extends FieldDef {
  static displayName = 'Look';
  @field shape = contains(StringField);
  @field path = contains(StringField);
  @field fill = contains(StringField);
  @field edge = contains(StringField);
  @field ink = contains(StringField);
  @field imageUrl = contains(StringField);
  @field backPattern = contains(StringField);
  @field backColour = contains(StringField);
  @field depth = contains(NumberField);
  @field size = contains(NumberField);
}

export class ComponentDefinitionField extends FieldDef {
  static displayName = 'Component Definition';
  @field defId = contains(StringField);
  @field kind = contains(StringField);
  @field name = contains(StringField);
  @field faces = contains(GameJsonField);
  @field value = contains(NumberField);
  @field alt = contains(NumberField);
  @field rank = contains(StringField);
  @field suit = contains(StringField);
  @field tags = containsMany(StringField);
  @field look = contains(LookField);
  @field quantity = contains(NumberField);
  @field startZone = contains(StringField);
  @field owner = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span>{{@model.name}}
        <small>({{@model.kind}}
          ×{{if @model.quantity @model.quantity 1}})</small></span>
    </template>
  };
}

// ─── Match parts ──────────────────────────────────────────────────────────
export class CopyStateField extends FieldDef {
  static displayName = 'Copy State';
  @field copyId = contains(StringField);
  @field defId = contains(StringField);
  @field zone = contains(StringField);
  @field position = contains(NumberField);
  @field facing = contains(StringField);
  @field orientation = contains(NumberField);
  @field visibleTo = contains(StringField);
  @field counters = contains(GameJsonField);
  @field owner = contains(StringField);
  @field history = containsMany(NumberField);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <code>{{@model.copyId}}
        ·
        {{@model.zone}}
        #{{@model.position}}
        ·
        {{@model.facing}}</code>
    </template>
  };
}

export class TurnField extends FieldDef {
  static displayName = 'Turn';
  @field seat = contains(StringField);
  @field phase = contains(StringField);
  @field step = contains(StringField);
  @field number = contains(NumberField);
}

export class ActionLogEntryField extends FieldDef {
  static displayName = 'Action Log Entry';
  @field index = contains(NumberField);
  @field turn = contains(NumberField);
  @field seat = contains(StringField);
  @field action = contains(StringField);
  @field args = contains(GameJsonField);
  @field rngCalls = contains(NumberField);
  @field resultSummary = contains(StringField);
  @field undone = contains(BooleanField);
  @field at = contains(StringField);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class={{if @model.undone 'undone'}}>#{{@model.index}}
        {{@model.seat}}
        {{@model.action}}
        —
        {{@model.resultSummary}}</span>
      <style scoped>
        .undone {
          text-decoration: line-through;
          opacity: 0.6;
        }
      </style>
    </template>
  };
}

export class PolicyRuleField extends FieldDef {
  static displayName = 'Policy Rule';
  @field when = contains(StringField);
  @field do = contains(StringField);
  @field weight = contains(NumberField);
}

// ─── Converters: field instances ↔ plain engine objects ───────────────────
const clean = <T extends Record<string, any>>(o: T): T => {
  let out: any = {};
  for (let [k, v] of Object.entries(o)) {
    if (v === null || v === undefined || v === '') continue;
    if (Array.isArray(v) && !v.length) continue;
    out[k] = v;
  }
  return out;
};

export function lookToPlain(l: any): Look | undefined {
  if (!l) return undefined;
  let o = clean({
    shape: l.shape,
    path: l.path,
    fill: l.fill,
    edge: l.edge,
    ink: l.ink,
    imageUrl: l.imageUrl,
    backPattern: l.backPattern,
    backColour: l.backColour,
    depth: l.depth,
    size: l.size,
  });
  return Object.keys(o).length ? o : undefined;
}

export function defToPlain(d: any): CompDef {
  return clean({
    id: d.defId,
    kind: d.kind,
    name: d.name,
    faces: d.faces,
    value: d.value,
    alt: d.alt,
    rank: d.rank,
    suit: d.suit,
    tags: d.tags ? [...d.tags] : undefined,
    look: lookToPlain(d.look),
    quantity: d.quantity,
    startZone: d.startZone,
    owner: d.owner,
  }) as CompDef;
}

export function seatToPlain(s: any): Seat {
  return {
    id: s.seatId,
    label: s.label ?? s.seatId,
    occupant: (s.occupant ?? 'human') as Seat['occupant'],
    ...(s.colour ? { colour: s.colour } : {}),
    resources: { ...(s.resources ?? {}) },
  };
}

export function copyToPlain(c: any): Copy {
  return {
    copyId: c.copyId,
    defId: c.defId,
    zone: c.zone,
    position: c.position ?? 0,
    facing: c.facing === 'down' ? 'down' : 'up',
    orientation: c.orientation ?? 0,
    visibleTo: c.visibleTo ?? 'all',
    counters: { ...(c.counters ?? {}) },
    ...(c.owner ? { owner: c.owner } : {}),
    history: [...(c.history ?? [])],
  };
}

export function logToPlain(e: any): LogEntry {
  return {
    index: e.index,
    turn: e.turn ?? 0,
    seat: e.seat ?? '',
    action: e.action,
    args: e.args ?? {},
    rngCalls: e.rngCalls ?? 0,
    resultSummary: e.resultSummary ?? '',
    ...(e.undone ? { undone: true } : {}),
    ...(e.at ? { at: e.at } : {}),
  };
}

const same = (a: any, b: any) =>
  JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

// Write a copy list into existing field instances, touching only what changed.
export function writeCopies(
  existing: CopyStateField[],
  next: Copy[],
): CopyStateField[] | null {
  let byId = new Map(existing.map((c) => [c.copyId, c]));
  if (
    existing.length !== next.length ||
    next.some((c) => !byId.has(c.copyId))
  ) {
    return next.map(
      (c) => new CopyStateField({ ...c, history: [...c.history] }),
    );
  }
  for (let c of next) {
    let f = byId.get(c.copyId)! as any;
    for (let k of [
      'defId',
      'zone',
      'position',
      'facing',
      'orientation',
      'visibleTo',
      'owner',
    ] as const) {
      if ((f[k] ?? undefined) !== ((c as any)[k] ?? undefined))
        f[k] = (c as any)[k];
    }
    if (!same(f.counters ?? {}, c.counters)) f.counters = { ...c.counters };
    if (!same([...(f.history ?? [])], c.history)) f.history = [...c.history];
  }
  return null; // updated in place
}

export function writeLog(
  existing: ActionLogEntryField[],
  next: LogEntry[],
): ActionLogEntryField[] | null {
  if (existing.length > next.length)
    return next.map((e) => new ActionLogEntryField({ ...e }));
  existing.forEach((f, i) => {
    let e = next[i];
    if (!!f.undone !== !!e.undone) f.undone = !!e.undone;
  });
  if (existing.length === next.length) return null;
  return [
    ...existing,
    ...next
      .slice(existing.length)
      .map((e) => new ActionLogEntryField({ ...e })),
  ];
}
