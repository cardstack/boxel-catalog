import { Guest } from '../guest';
import { Table } from '../table';
import { Fixture } from '../fixture';

export function clampNum(
  v: unknown,
  min: number,
  max: number,
  def: number,
): number {
  let n = Number(v);
  if (!isFinite(n)) return def;
  return Math.max(min, Math.min(max, Math.round(n)));
}

export function cloneTableGeometry(t: Table): Table {
  return new Table({
    name: t.name,
    shape: t.shape,
    seatCount: t.seatCount,
    seatingStyle: t.seatingStyle,
    rows: t.rows,
    cols: t.cols,
    x: t.x,
    y: t.y,
    width: t.width,
    height: t.height,
    rotation: t.rotation,
    z: t.z,
    themeColor: t.themeColor,
    vip: t.vip,
    note: t.note,
  });
}

export function cloneTableWithSeating(t: Table): Table {
  let copy = cloneTableGeometry(t);
  copy.seatOrder = t.seatOrder;
  copy.reservedCategories = [...(t.reservedCategories ?? [])];
  copy.seatedGuests = [...((t.seatedGuests ?? []) as Guest[])];
  copy.seatSlots = [...(t.seatSlots ?? [])];
  copy.rank = t.rank;
  copy.locked = t.locked;
  return copy;
}

export function cloneFixture(f: Fixture): Fixture {
  return new Fixture({
    label: f.label,
    kind: f.kind,
    pattern: f.pattern,
    x: f.x,
    y: f.y,
    width: f.width,
    height: f.height,
    rotation: f.rotation,
    z: f.z,
    color: f.color,
  });
}
