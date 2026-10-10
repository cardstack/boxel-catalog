import { getFields, type CardDef } from '@cardstack/base/card-api';

import { linkedId, linkedIds } from './linked-id';

// BXL's own `materializeCardInput` is internal to the package — the card-facing
// entry point is `expression()`, which materializes a card it already holds as
// `this`. A stored expression has no such handle, so it builds its own input.
// The trade-off is depth: this walks contained values only and renders a linked
// card as a bare `{ id }`, where `expression()` would follow it lazily.
const MAX_DEPTH = 4;

function isPlain(value: unknown): boolean {
  return (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  );
}

function materialize(
  value: unknown,
  depth: number,
  seen: Set<object>,
): unknown {
  if (isPlain(value) || value === undefined) {
    return value ?? null;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return depth >= MAX_DEPTH
      ? []
      : value.map((entry) => materialize(entry, depth + 1, seen));
  }
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  if (seen.has(value)) {
    return { id: (value as { id?: string }).id ?? null };
  }
  if (depth >= MAX_DEPTH) {
    return { id: (value as { id?: string }).id ?? null };
  }
  seen.add(value);
  try {
    return fieldsOf(value, depth, seen);
  } finally {
    seen.delete(value);
  }
}

function fieldsOf(
  subject: object,
  depth: number,
  seen: Set<object>,
): Record<string, unknown> {
  let out: Record<string, unknown> = {};
  let fields: Record<string, { fieldType?: string }>;
  try {
    fields = getFields(subject as never) as Record<
      string,
      { fieldType?: string }
    >;
  } catch {
    return out;
  }
  for (let [name, field] of Object.entries(fields)) {
    if (name === 'id') {
      continue;
    }
    // A link outside a render may not have loaded, and its getter then reads
    // undefined; the card's own links are read by their stored id instead.
    if (depth === 0 && field?.fieldType === 'linksTo') {
      let id = linkedId(subject as CardDef, name);
      out[name] = id ? { id } : null;
      continue;
    }
    if (depth === 0 && field?.fieldType === 'linksToMany') {
      out[name] = linkedIds(subject as CardDef, name).map((id) => ({ id }));
      continue;
    }
    let raw: unknown;
    try {
      raw = (subject as Record<string, unknown>)[name];
    } catch {
      continue;
    }
    out[name] = materialize(raw, depth + 1, seen);
  }
  return out;
}

// Field names are the jq keys, so `.dueDate` and `"Due Date"` both address a
// field named dueDate — BXL's readable syntax quotes the prose form.
export function cardToBxlInput(subject: object): Record<string, unknown> {
  if (!subject || typeof subject !== 'object') {
    return {};
  }
  let seen = new Set<object>([subject]);
  let out = fieldsOf(subject, 0, seen);
  let id = (subject as { id?: string }).id;
  if (id) {
    out.id = id;
  }
  return out;
}
