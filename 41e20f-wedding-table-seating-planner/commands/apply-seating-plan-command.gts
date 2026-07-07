import {
  CardDef,
  FieldDef,
  field,
  contains,
  containsMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { GUEST_CATEGORIES } from '../utils/index';
import type { TableSeatingPlanner } from '../table-seating-planner';
import type { Guest } from '../guest';
import type { Table } from '../table';

export class TableAssignmentField extends FieldDef {
  static displayName = 'Table Assignment';
  @field tableIndex = contains(NumberField, {
    description:
      'Zero-based index of the table in the payload the user sent (and in the planner card’s "tables" field).',
  });
  @field partyIds = containsMany(StringField, {
    description:
      'Guest card IDs of the party HEADS seated at this table, ordered from the front (first chair / first row, nearest the couple) to the back. Each head brings their whole party (companions) with them.',
  });
}

export class ApplySeatingPlanInput extends CardDef {
  @field plannerCardId = contains(StringField, {
    description: 'ID of the Table Seating Planner card to update.',
  });
  @field assignments = containsMany(TableAssignmentField, {
    description:
      'The COMPLETE seating plan — one entry per table that should have guests. Any table omitted here is emptied.',
  });
  @field summary = contains(StringField, {
    description: 'One friendly sentence about the overall plan.',
  });
}

export class ApplySeatingPlanResult extends CardDef {
  @field seatedCount = contains(NumberField);
  @field message = contains(StringField);
}

function chairCountOf(t: Table): number {
  let shape = t.shape || 'round';
  if (shape === 'seat') return 1;
  if (shape === 'section')
    return (
      Math.max(0, Math.floor(t.rows || 0)) *
      Math.max(0, Math.floor(t.cols || 0))
    );
  return t.seatCount ?? 8;
}

function gridForCount(
  curRows: number,
  curCols: number,
  n: number,
): { rows: number; cols: number } {
  if (n <= 0) return { rows: Math.max(1, curRows), cols: Math.max(1, curCols) };
  let r0 = Math.max(1, curRows);
  let c0 = Math.max(1, curCols);
  let ratio = c0 / r0; // columns per row
  let cols = Math.max(1, Math.round(Math.sqrt(n * ratio)));
  let rows = Math.max(1, Math.ceil(n / cols));
  while (cols > 1 && (cols - 1) * rows >= n) cols--;
  while (rows > 1 && cols * (rows - 1) >= n) rows--;
  return { rows, cols };
}

export class ApplySeatingPlanCommand extends Command<
  typeof ApplySeatingPlanInput,
  typeof ApplySeatingPlanResult
> {
  static actionVerb = 'Apply';
  static displayName = 'Apply Seating Plan';
  description =
    'Apply a complete seating arrangement to a Table Seating Planner card. Every table gets exactly the parties assigned to it; tables without an assignment entry are emptied.';

  async getInputType() {
    return ApplySeatingPlanInput;
  }

  protected async run(
    input: ApplySeatingPlanInput,
  ): Promise<ApplySeatingPlanResult> {
    if (!input.plannerCardId) {
      throw new Error('plannerCardId is required');
    }
    let planner = (await new GetCardCommand(this.commandContext).execute({
      cardId: input.plannerCardId,
    })) as TableSeatingPlanner;
    let tables = planner.tables ?? [];
    if (!tables.length) {
      throw new Error('The planner has no tables to seat guests at.');
    }

    let roster = (planner.guests ?? []).filter(Boolean) as Guest[];
    let inRoster = new Set(roster);
    let rootOf = (g: Guest): Guest => {
      let cur = g;
      let seen = new Set<Guest>([cur]);
      let p = cur.parentGuest as Guest | undefined;
      while (p && inRoster.has(p) && !seen.has(p)) {
        seen.add(p);
        cur = p;
        p = cur.parentGuest as Guest | undefined;
      }
      return cur;
    };
    let childrenOf = new Map<Guest, Guest[]>();
    for (let g of roster) {
      let root = rootOf(g);
      if (root === g) continue;
      let kids = childrenOf.get(root);
      if (kids) kids.push(g);
      else childrenOf.set(root, [g]);
    }
    let companions = new Set([...childrenOf.values()].flatMap((kids) => kids));
    let partyOf = new Map<string, Guest[]>();
    for (let g of roster) {
      if (!g.id || companions.has(g)) continue;
      partyOf.set(g.id, [g, ...(childrenOf.get(g) ?? [])]);
    }

    let seatLists = new Map<number, Guest[]>();
    let unknownIds: string[] = [];
    let assignedIds = new Set<string>();
    for (let a of input.assignments ?? []) {
      let idx = a.tableIndex ?? -1;
      if (idx < 0 || idx >= tables.length) continue;
      let seated = seatLists.get(idx) ?? [];
      for (let pid of a.partyIds ?? []) {
        let members = partyOf.get(pid);
        if (!members) {
          unknownIds.push(pid);
          continue;
        }
        assignedIds.add(pid);
        seated.push(...members);
      }
      seatLists.set(idx, seated);
    }

    let catPriority = (cat: string | null | undefined) => {
      let i = GUEST_CATEGORIES.findIndex((c) => c.value === cat);
      return i === -1 ? GUEST_CATEGORIES.length : i;
    };
    let leftovers = [...partyOf.entries()]
      .filter(([pid]) => !assignedIds.has(pid))
      .map(([, members]) => members)
      .sort((a, b) => {
        let av = a.some((m) => !!m.vip);
        let bv = b.some((m) => !!m.vip);
        if (av !== bv) return av ? -1 : 1;
        let p = catPriority(a[0].category) - catPriority(b[0].category);
        if (p) return p;
        return b.length - a.length;
      });
    let autoSeated = 0;
    let reservedOk = (t: Table, cat: string | null | undefined) => {
      let r = t.reservedCategories ?? [];
      if (!r.length) return true;
      return !!cat && r.includes(cat);
    };
    for (let members of leftovers) {
      let cat = members[0].category;
      let idx = tables.findIndex((t, i) => {
        let seated = seatLists.get(i) ?? [];
        return (
          reservedOk(t, cat) &&
          seated.length + members.length <= chairCountOf(t)
        );
      });
      if (idx === -1) continue;
      let seated = seatLists.get(idx) ?? [];
      seated.push(...members);
      seatLists.set(idx, seated);
      autoSeated += members.length;
    }

    let seatedCount = 0;
    tables.forEach((t, idx) => {
      let seated = seatLists.get(idx) ?? [];
      let curCap = Math.max(0, t.rows || 0) * Math.max(0, t.cols || 0);
      if (t.shape === 'section' && seated.length > curCap) {
        let { rows, cols } = gridForCount(
          t.rows || 0,
          t.cols || 0,
          seated.length,
        );
        if (rows * cols > curCap) {
          t.rows = rows;
          t.cols = cols;
          t.seatCount = rows * cols;
        }
      }
      let cap = chairCountOf(t);
      if (seated.length > cap) seated = seated.slice(0, cap);
      t.seatedGuests = seated;
      t.seatSlots = [];
      seatedCount += seated.length;
    });

    let message = `Seated ${seatedCount} guests across ${tables.length} tables.`;
    if (autoSeated) {
      message += ` Auto-seated ${autoSeated} guest(s) the plan left out.`;
    }
    if (unknownIds.length) {
      message += ` Ignored ${unknownIds.length} unknown party id(s): ${unknownIds
        .slice(0, 5)
        .join(', ')}.`;
    }
    if (input.summary) {
      message += ` ${input.summary}`;
    }
    return new ApplySeatingPlanResult({ seatedCount, message });
  }
}
