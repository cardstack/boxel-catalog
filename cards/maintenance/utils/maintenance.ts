/**
 * Shared, pure helpers for the Facilities & Assets kit. Anything two modules
 * need lives here once (Stage 4b rule). No card imports — plain data in,
 * plain data out — so fields, cards, components and commands can all use it.
 */
import { dayKey, toDay } from './recurrence';

// ----------------------------------------------------------------- time math
const HOUR_MS = 3_600_000;

export function hoursBetween(
  from: Date | string | null | undefined,
  to: Date | string | null | undefined = new Date(),
): number | undefined {
  if (!from) return undefined;
  let a = new Date(from).getTime();
  let b = to ? new Date(to).getTime() : Date.now();
  if (isNaN(a) || isNaN(b)) return undefined;
  return Math.max(0, (b - a) / HOUR_MS);
}

export function roundHours(h: number | undefined, dp = 2): number | undefined {
  return h == null ? undefined : Math.round(h * 10 ** dp) / 10 ** dp;
}

export function formatHours(h: number | null | undefined): string {
  if (h == null) return '—';
  if (h < 1) return `${Math.round(h * 60)} min`;
  let whole = Math.floor(h);
  let mins = Math.round((h - whole) * 60);
  return mins ? `${whole} h ${String(mins).padStart(2, '0')} m` : `${whole} h`;
}

// -------------------------------------------------------------- rollups
export interface CostLine {
  cost?: number | null;
}

export function sumCost(
  lines: readonly (CostLine | null | undefined)[] | null | undefined,
): number {
  if (!lines) return 0;
  return lines.reduce((acc, l) => acc + (l?.cost ?? 0), 0);
}

export interface DowntimeLike {
  startedAt?: Date | string | null;
  endedAt?: Date | string | null;
  planned?: boolean | null;
}

/** Availability over a trailing window: 1 − Σ downtime hours ÷ window hours. */
export function availability(
  downtimes: readonly (DowntimeLike | null | undefined)[],
  windowDays = 90,
  now: Date = new Date(),
): number {
  let windowStart = now.getTime() - windowDays * 24 * HOUR_MS;
  let windowHours = windowDays * 24;
  let down = 0;
  for (let d of downtimes) {
    if (!d?.startedAt) continue;
    let s = Math.max(new Date(d.startedAt).getTime(), windowStart);
    let e = d.endedAt ? new Date(d.endedAt).getTime() : now.getTime();
    if (e > s) down += (e - s) / HOUR_MS;
  }
  return Math.max(0, Math.min(1, 1 - down / windowHours));
}

export interface ComplianceLike {
  kind?: string | null;
  status?: string | null;
  dueBy?: Date | string | null;
  completedAt?: Date | string | null;
}

/** PM compliance: PM work orders completed on/before dueBy ÷ PM work orders due inside the window. */
export function pmCompliance(
  workOrders: readonly (ComplianceLike | null | undefined)[],
  windowDays = 30,
  now: Date = new Date(),
): { compliant: number; due: number; ratio: number | undefined } {
  let from = toDay(new Date(now.getTime() - windowDays * 24 * HOUR_MS))!;
  let today = toDay(now)!;
  let due = 0;
  let compliant = 0;
  for (let wo of workOrders) {
    if (!wo || (wo.kind !== 'preventive' && wo.kind !== 'inspection')) continue;
    let dueDay = toDay(wo.dueBy);
    if (!dueDay || dueDay < from || dueDay > today) continue;
    due++;
    let done = toDay(wo.completedAt);
    if (done && done.getTime() <= dueDay.getTime()) compliant++;
  }
  return { compliant, due, ratio: due ? compliant / due : undefined };
}

// -------------------------------------------------------------- checklist
export interface ChecklistItemData {
  label?: string | null;
  kind?: string | null;
  required?: boolean | null;
  expectedValue?: number | null;
  unit?: string | null;
  tolerance?: number | null;
  result?: string | null;
  value?: string | null;
  photoUrl?: string | null;
  note?: string | null;
  completedByName?: string | null;
  completedAt?: Date | null;
}

/** A fresh, unanswered copy of a template's items — results never flow back. */
export function cloneChecklistItems<T extends ChecklistItemData>(
  items: readonly (T | null | undefined)[] | null | undefined,
): ChecklistItemData[] {
  if (!items) return [];
  return items
    .filter((i): i is T => !!i)
    .map((i) => ({
      label: i.label ?? undefined,
      kind: i.kind ?? 'check',
      required: i.required ?? false,
      expectedValue: i.expectedValue ?? undefined,
      unit: i.unit ?? undefined,
      tolerance: i.tolerance ?? undefined,
      result: 'pending',
      value: undefined,
      photoUrl: undefined,
      note: undefined,
      completedByName: undefined,
      completedAt: undefined,
    }));
}

export function measureDelta(item: ChecklistItemData): number | undefined {
  if (item.kind !== 'measure' || item.expectedValue == null) return undefined;
  let v = item.value == null || item.value === '' ? NaN : Number(item.value);
  if (isNaN(v)) return undefined;
  let tol = item.tolerance ?? 0;
  if (v > item.expectedValue + tol)
    return roundHours(v - (item.expectedValue + tol), 3);
  if (v < item.expectedValue - tol)
    return roundHours(v - (item.expectedValue - tol), 3);
  return 0;
}

export function checklistStats(
  items: readonly (ChecklistItemData | null | undefined)[] | null | undefined,
) {
  let all = (items ?? []).filter((i): i is ChecklistItemData => !!i);
  let done = all.filter((i) => i.result && i.result !== 'pending');
  let failed = all.filter((i) => i.result === 'fail');
  let requiredRemaining = all.filter(
    (i) => i.required && (!i.result || i.result === 'pending'),
  );
  return {
    total: all.length,
    done: done.length,
    failedCount: failed.length,
    requiredRemaining: requiredRemaining.length,
    completionPercent: all.length
      ? Math.round((done.length / all.length) * 100)
      : 0,
    isComplete: all.length > 0 && requiredRemaining.length === 0,
  };
}

// -------------------------------------------------------------- identifiers
/** Idempotency key for a generated PM work order: one per (plan, due day). */
export function planDueKey(planId: string, dueDate: Date): string {
  return `${planId}@${dayKey(dueDate)}`;
}

/**
 * A plan id as it appears in a `planDueKey`. Stored keys were written with the
 * plan's short slug ("ast-0041-quarterly"), while a live `plan.id` is the full
 * realm URL — so both sides are reduced to the last path segment before they
 * are compared.
 */
function planSlug(planId?: string | null): string {
  return (planId ?? '').split('/').pop() ?? '';
}

interface RaisedSource {
  planId?: string | null;
  planDueKey?: string | null;
  scheduledFor?: Date | null;
  dueBy?: Date | null;
}

/**
 * The (plan, due day) pairs that already exist as real work orders.
 *
 * A plan's `nextDueAt` is a FORECAST; once the generator has raised the work
 * order for that occurrence, the forecast and the record are the same job.
 * Drawing both — which every surface did until now — inflates apparent
 * workload on exactly the screens used to judge capacity.
 *
 * `planDueKey` is the generator's own immutable key and is trusted first: it
 * survives a reschedule, where matching on the work order's current date would
 * not. Work orders predating the key fall back to plan id plus scheduled day.
 */
export function raisedPlanOccurrences(
  workOrders: readonly (RaisedSource | null | undefined)[] | null | undefined,
): Set<string> {
  let out = new Set<string>();
  for (let wo of workOrders ?? []) {
    if (!wo) continue;
    if (wo.planDueKey) {
      let [id, day] = wo.planDueKey.split('@');
      if (id && day) out.add(`${planSlug(id)}@${day}`);
      continue;
    }
    let when = wo.scheduledFor ?? wo.dueBy;
    if (wo.planId && when) {
      out.add(planDueKey(planSlug(wo.planId), new Date(when)));
    }
  }
  return out;
}

/** True when this plan's occurrence on `due` is already a real work order. */
export function isPlanOccurrenceRaised(
  raised: Set<string>,
  planId?: string | null,
  due?: Date | null,
): boolean {
  if (!planId || !due) return false;
  return raised.has(planDueKey(planSlug(planId), new Date(due)));
}

/** Percent 0–100 rounded to one decimal, or undefined. */
export function percent(ratio: number | undefined, dp = 1): number | undefined {
  if (ratio == null || isNaN(ratio)) return undefined;
  return Math.round(ratio * 100 * 10 ** dp) / 10 ** dp;
}
