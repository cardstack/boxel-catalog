import {
  FieldDef,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';

// The shared vocabulary for the Placement family — the zone, the placement,
// and the pure functions that decide occupancy and ordering.
//
// It lives in its own module because every part of a placement surface needs
// it: a board persists these fields, a drop zone reads occupancy, the palette
// reads which items are already placed, and a commit command re-runs the
// capacity check. A copy in each is how a board ends up disagreeing with its
// own commit gate about whether a zone is full.

// ── Zone ────────────────────────────────────────────────────────────────────

/**
 * One place a thing can be put: a seat, a shelf slot, a room, a shift.
 *
 * `key` is the stable identifier every placement points at — it must not
 * change once placements reference it, because a placement is data and a
 * rename would orphan it. `label` is what the eye reads and may change
 * freely.
 *
 * `capacity` is a soft ceiling: the UI warns and the commit command refuses,
 * but nothing prevents an over-capacity draft from existing. That is
 * deliberate — a user dragging a fifth chair to a four-chair table wants to
 * see the conflict, not have the drag silently swallowed.
 */
export class PlacementZoneField extends FieldDef {
  static displayName = 'Placement Zone';

  @field key = contains(StringField, {
    description:
      'Stable identifier placements point at. Never rename once in use.',
  });
  @field label = contains(StringField);
  @field capacity = contains(NumberField, {
    description: 'Soft ceiling. Blank means unlimited.',
  });
  // A hue name the host's palette understands (slate, blue, green, amber,
  // red…). Kept as a string rather than an enum so the zone does not have an
  // opinion about which design system is rendering it.
  @field hue = contains(StringField);
  @field note = contains(StringField);

  @field displayLabel = contains(StringField, {
    computeVia: function (this: PlacementZoneField) {
      return this.label || this.key || 'Untitled zone';
    },
  });
}

// ── Placement ───────────────────────────────────────────────────────────────

/**
 * One item, in one zone, at one position.
 *
 * `itemId` is the item's id as the host knows it — usually a card URL, but
 * deliberately a plain string so the family works for things that are not
 * cards (a seat number, an SKU, a row from an import).
 *
 * `seq` is the explicit order within the zone. Items without one sort after
 * those that have one, keeping their incoming order, so a board whose host
 * has no ordering concept behaves identically to one that does — the same
 * rule the Calendar block uses for its day chips.
 */
export class PlacementField extends FieldDef {
  static displayName = 'Placement';

  @field itemId = contains(StringField);
  @field zoneKey = contains(StringField);
  @field seq = contains(NumberField);
  @field placedAt = contains(DateTimeField);
  @field note = contains(StringField);
}

// ── Pure logic ──────────────────────────────────────────────────────────────

export interface ZoneOccupancy {
  key: string;
  count: number;
  capacity?: number;
  // `capacity` unset means unlimited, which is never over and never full.
  isFull: boolean;
  isOver: boolean;
  // Remaining slots, or undefined when unlimited — distinct from 0, which
  // means full.
  remaining?: number;
}

export function occupancyOf(
  zone: Pick<PlacementZoneField, 'key' | 'capacity'>,
  placements: PlacementField[],
): ZoneOccupancy {
  let key = zone.key ?? '';
  let count = placements.filter((p) => p?.zoneKey === key).length;
  let capacity =
    typeof zone.capacity === 'number' && zone.capacity > 0
      ? zone.capacity
      : undefined;
  return {
    key,
    count,
    capacity,
    isFull: capacity != null && count >= capacity,
    isOver: capacity != null && count > capacity,
    remaining: capacity != null ? Math.max(0, capacity - count) : undefined,
  };
}

// Every zone that a draft has pushed past its ceiling. The commit gate reads
// this; the board's header reads it too, so the warning and the refusal can
// never disagree.
export function overCapacityZones(
  zones: PlacementZoneField[],
  placements: PlacementField[],
): ZoneOccupancy[] {
  return (zones ?? [])
    .map((z) => occupancyOf(z, placements ?? []))
    .filter((o) => o.isOver);
}

// Placements in one zone, in run order: explicit `seq` first, then incoming
// order. `sort` is stable, so items tying on `seq` never shuffle between
// renders.
export function placementsIn(
  zoneKey: string,
  placements: PlacementField[],
): PlacementField[] {
  return (placements ?? [])
    .filter((p) => p?.zoneKey === zoneKey)
    .sort(
      (a, b) =>
        (a.seq ?? Number.POSITIVE_INFINITY) -
        (b.seq ?? Number.POSITIVE_INFINITY),
    );
}

// The next free position at the end of a zone.
export function nextSeq(
  zoneKey: string,
  placements: PlacementField[],
): number {
  let seqs = placementsIn(zoneKey, placements)
    .map((p) => p.seq)
    .filter((s): s is number => typeof s === 'number');
  return seqs.length ? Math.max(...seqs) + 1 : 0;
}

/**
 * Normalise an item reference so a stored placement and a live card id
 * compare equal.
 *
 * A placement stores `itemId` as a plain string — it has to, because the
 * family works for things that are not cards. But a card's runtime `id` is
 * realm-absolute (`http://…/experiments/Author/jane-doe`) while an authored
 * instance writes the relative form (`../Author/jane-doe`). Comparing those
 * raw means a hand-authored board never matches its own pool, and every item
 * shows as unplaced.
 *
 * The normal form is the last two path segments — `Author/jane-doe` — which
 * is stable across realms and survives the board being copied to staging.
 * Boxel's `Type/name` instance convention is what makes two segments enough.
 *
 * The cost: two instances with the same name under the same type name in
 * different realms collide. That is acceptable here because a board's pool
 * is a curated set the author chose, not an open query.
 */
export function itemKey(id?: string | null): string {
  if (!id) {
    return '';
  }
  let clean = id.trim().replace(/\.json$/i, '').replace(/\/+$/, '');
  let segments = clean.split('/').filter((s) => s && s !== '..' && s !== '.');
  return segments.slice(-2).join('/');
}

export function sameItem(a?: string | null, b?: string | null): boolean {
  let ka = itemKey(a);
  return ka !== '' && ka === itemKey(b);
}

// Normalised keys, so callers can compare against a live card id directly.
export function placedItemIds(placements: PlacementField[]): Set<string> {
  return new Set(
    (placements ?? [])
      .map((p) => itemKey(p?.itemId))
      .filter(Boolean) as string[],
  );
}

// Is the draft materially different from what is committed? Compared as
// itemId→(zone, seq) so a reordered array with identical content is not a
// false positive — otherwise every render would mark the board dirty.
export function isDirty(
  committed: PlacementField[],
  draft: PlacementField[],
): boolean {
  let key = (list: PlacementField[]) =>
    (list ?? [])
      .filter((p) => p?.itemId)
      .map((p) => `${itemKey(p.itemId)}@${p.zoneKey ?? ''}#${p.seq ?? ''}`)
      .sort()
      .join('|');
  return key(committed) !== key(draft);
}
