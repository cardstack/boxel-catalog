import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import {
  identifyCard,
  type getCards,
  type Query,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import { RichFittedCard } from '../shared/rich-fitted-card';

import { Asset } from './asset';
import { AssetCategory } from './asset-category';
import { MaintenanceTriggerField } from './maintenance-trigger-field';
import { ChecklistField } from './checklist-field';
import {
  PlanKindField,
  WorkOrderPriorityField,
} from './maintenance-vocabulary';
import {
  nextOccurrence,
  triggerSummary,
  type MaintenanceTriggerData,
  type NextOccurrence,
} from './utils/recurrence';
import {
  Chip,
  Dot,
  Head,
  Mark,
  Row,
  Kv,
  KvRow,
  Section,
  Stats,
  fmtDay,
} from './card-ui';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * Plain-data view of a plan's trigger, for `nextOccurrence`. Shared with the
 * PM generator and the calendar so every consumer reads the field the same
 * way.
 */
export function planTriggerData(
  plan: MaintenancePlan,
): MaintenanceTriggerData | undefined {
  let t = plan.trigger;
  if (!t) return undefined;
  let c = t.calendar;
  return {
    calendar: c
      ? {
          pattern: c.pattern,
          interval: c.interval,
          daysOfWeek: c.daysOfWeek,
          dayOfMonth: c.dayOfMonth,
          monthOfYear: c.monthOfYear,
          startDate: c.startDate,
          endDate: c.endDate,
          occurrences: c.occurrences,
        }
      : undefined,
    meterThreshold: t.meterThreshold,
    whicheverFirst: t.whicheverFirst ?? true,
    leadDays: t.leadDays,
  };
}

/** The plan's next occurrence as of `today` — the single call every consumer makes. */
// A command passes `meterNow` from the asset it fetched: outside a render the
// plan's asset link may not be loaded.
export function planNext(
  plan: MaintenancePlan,
  today: Date = new Date(),
  meterNow: number | undefined = (plan.asset as any)?.primaryMeterValue,
): NextOccurrence {
  let trigger = planTriggerData(plan);
  let anchor =
    plan.lastCompletedAt ?? plan.trigger?.calendar?.startDate ?? undefined;
  return nextOccurrence(trigger, anchor, {
    today,
    meterNow: meterNow ?? undefined,
    meterAtAnchor: plan.lastCompletedMeter ?? undefined,
  });
}

function dueText(n: NextOccurrence, unit?: string | null): string {
  if (n.decidedBy === 'none') return 'No rhythm set';
  let parts: string[] = [];
  if (n.daysUntil != null) {
    parts.push(
      n.daysUntil < 0
        ? `${Math.abs(n.daysUntil)} d overdue`
        : n.daysUntil === 0
          ? 'due today'
          : `due in ${n.daysUntil} d`,
    );
  }
  if (n.meterRemaining != null) {
    parts.push(
      n.meterRemaining <= 0
        ? `${Math.abs(n.meterRemaining).toLocaleString()} ${unit ?? ''} over`.trim()
        : `${n.meterRemaining.toLocaleString()} ${unit ?? ''} left`.trim(),
    );
  } else if (n.dueMeter != null) {
    parts.push(`at ${n.dueMeter.toLocaleString()} ${unit ?? ''}`.trim());
  }
  return parts.join(' · ');
}

// Work orders raised from this plan: open → next work, closed → history.
class PlanWork extends Component<typeof MaintenancePlan> {
  query: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let model = this.args.model as any;
    let realmHref = model?.[realmURL]?.href;
    // Work Order lives beside this module; resolving it from the plan's own
    // module avoids importing work-order here (it imports this file).
    let planRef = identifyCard(MaintenancePlan) as
      | { module: string }
      | undefined;
    let on = planRef
      ? ({
          module: new URL('./work-order', planRef.module).href,
          name: 'WorkOrder',
        } as ResolvedCodeRef)
      : undefined;
    let query: Query | undefined =
      model?.id && on
        ? { filter: { on, eq: { planId: model.id } } }
        : undefined;
    this.query = this.args.context?.getCards(
      this,
      () => query,
      () => (realmHref ? [realmHref] : undefined),
      { isLive: true },
    );
  }

  get next() {
    return planNext(this.args.model as MaintenancePlan);
  }
  get workOrders(): any[] {
    return ((this.query?.instances ?? []) as any[]).filter(Boolean);
  }
  get history(): any[] {
    return this.workOrders
      .filter((w) => DONE.has(w.status))
      .sort((a, b) => stamp(b.completedAt) - stamp(a.completedAt));
  }
  get lastWork() {
    return this.history[0];
  }
  get nextWork() {
    return this.workOrders
      .filter((w) => !DONE.has(w.status) && w.status !== 'cancelled')
      .sort((a, b) => stamp(a.scheduledFor) - stamp(b.scheduledFor))[0];
  }
}

const DONE = new Set(['completed', 'closed']);

/**
 * Preventive maintenance as data: WHAT to do (checklist template), on WHAT
 * (an asset — or a category when the plan is a template), and WHEN (a
 * Maintenance Trigger). The system generates work orders from it; manual
 * creation is the corrective exception.
 *
 * `nextDueAt` / `nextDueMeter` are computed through `planNext` → utils/recurrence,
 * never stored, so the plan, the calendar, the generator and the Home runway
 * can never disagree. `lastCompletedAt` / `lastCompletedMeter` are stamped
 * only by Complete Work Order.
 */
export class MaintenancePlan extends CardDef {
  static displayName = 'Maintenance Plan';
  static icon = RepeatIcon;

  @field name = contains(StringField);
  @field asset = linksTo(() => Asset);
  @field category = linksTo(() => AssetCategory, {
    description:
      'For templates (no asset): the category whose assets inherit this plan.',
  });
  @field kind = contains(PlanKindField);
  @field trigger = contains(MaintenanceTriggerField);
  @field checklist = contains(ChecklistField, {
    description: 'The template — copied onto every generated work order.',
  });
  @field estimatedHours = contains(NumberField);
  @field priority = contains(WorkOrderPriorityField);
  @field assignTeamName = contains(StringField, {
    description: 'Team that receives generated work orders.',
  });
  @field lastCompletedAt = contains(DateField, {
    description: 'Stamped by Complete Work Order.',
  });
  @field lastCompletedMeter = contains(NumberField, {
    description: 'Primary meter reading at the last completion.',
  });
  @field active = contains(BooleanField);
  @field complianceWindowDays = contains(NumberField, {
    description: '± days a completion still counts as compliant.',
  });

  @field nextDueAt = contains(DateField, {
    computeVia: function (this: MaintenancePlan) {
      return planNext(this).dueDate;
    },
  });

  @field nextDueMeter = contains(NumberField, {
    computeVia: function (this: MaintenancePlan) {
      return planNext(this).dueMeter;
    },
  });

  @field isOverdue = contains(BooleanField, {
    computeVia: function (this: MaintenancePlan) {
      if (this.active === false) return false;
      let n = planNext(this);
      return n.isDue;
    },
  });

  @field dueLabel = contains(StringField, {
    computeVia: function (this: MaintenancePlan) {
      let n = planNext(this);
      let rhythm = this.trigger?.summary;
      let due = dueText(n, this.trigger?.meterUnit);
      return rhythm && rhythm !== 'No rhythm set' ? `${due} · ${rhythm}` : due;
    },
  });

  @field isTemplate = contains(BooleanField, {
    computeVia: function (this: MaintenancePlan) {
      return !this.asset && !!this.category;
    },
  });

  @field assetId = contains(StringField, {
    computeVia: function (this: MaintenancePlan) {
      return this.asset?.id;
    },
  });
  @field assetTag = contains(StringField, {
    computeVia: function (this: MaintenancePlan) {
      return (this.asset as any)?.identifier?.value as string | undefined;
    },
  });
  @field assetName = contains(StringField, {
    computeVia: function (this: MaintenancePlan) {
      return (this.asset as any)?.name as string | undefined;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: MaintenancePlan) {
      let subject = this.assetTag ?? (this.category as any)?.name;
      return subject
        ? `${this.name ?? 'Plan'} · ${subject}`
        : (this.name ?? 'Untitled plan');
    },
  });

  static isolated = class Isolated extends PlanWork {
    get stats() {
      let m = this.args.model;
      let n = this.next;
      let items = m.checklist?.items ?? [];
      let meter = n.dueMeter != null ? meterText(m, n.dueMeter) : '';
      return [
        {
          label: 'Next due',
          value: n.dueDate ? fmtDay(n.dueDate) : meter || '—',
          meta:
            n.dueDate && meter
              ? `or ${meter}${m.trigger?.whicheverFirst === false ? '' : ', whichever first'}`
              : m.isOverdue
                ? 'overdue'
                : '',
        },
        {
          label: 'Estimate',
          value: m.estimatedHours != null ? `${m.estimatedHours} h` : '—',
          meta: [m.priority, m.assignTeamName].filter(Boolean).join(' · '),
        },
        {
          label: 'Checklist',
          value: String(items.length),
          meta: `${items.filter((i) => i?.required).length} required`,
        },
      ];
    }
    <template>
      <IsoFrame>
        <article class='mp'>
          <Head @mark='Pl' @title={{@model.name}} @meta={{subjectLine @model}}>
            <PlanDots @model={{@model}} />
          </Head>
          <Stats @items={{this.stats}} />
          <div class='cols'>
            <div class='col'>
              <Section @title='Trigger'>
                <Kv>
                  <KvRow @label='Calendar' @value={{calendarLine @model}} />
                  <KvRow @label='Meter' @value={{meterLine @model}} />
                  <KvRow @label='Rule' @value={{ruleLine @model}} />
                  <KvRow
                    @label='Raise ahead'
                    @value={{days @model.trigger.leadDays}}
                  />
                  <KvRow
                    @label='Compliance window'
                    @value={{days @model.complianceWindowDays}}
                  />
                </Kv>
              </Section>
              <Section @title='Checklist'>
                {{#each @model.checklist.items as |i|}}
                  <Row
                    @title={{i.label}}
                    @meta={{itemSub i}}
                    @tone={{if i.required 'info' 'muted'}}
                    @state={{if i.required 'required' 'optional'}}
                  />
                {{else}}
                  <p class='empty'>No steps yet</p>
                {{/each}}
              </Section>
              <Section @title='History'>
                {{#each this.history as |w|}}
                  <Row
                    @title={{w.cardTitle}}
                    @meta={{historySub w}}
                    @tone={{woTone w.status}}
                    @state={{woLabel w.status}}
                  />
                {{else}}
                  <p class='empty'>Not done yet</p>
                {{/each}}
              </Section>
            </div>
            <aside class='col side'>
              <Section @title='Linked'>
                <Kv>
                  {{#if @model.asset}}
                    <KvRow @label='Asset'><@fields.asset
                        @format='atom'
                      /></KvRow>
                  {{else}}
                    <KvRow @label='Category'>{{#if
                        @model.category
                      }}<@fields.category
                          @format='atom'
                        />{{else}}—{{/if}}</KvRow>
                  {{/if}}
                  <KvRow @label='Next work'>{{#if this.nextWork}}<WoChip
                        @wo={{this.nextWork}}
                      />{{else}}—{{/if}}</KvRow>
                </Kv>
              </Section>
              <Section @title='Details'>
                <PlanDetails @model={{@model}} />
              </Section>
            </aside>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .mp {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .col {
          min-inline-size: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        .empty {
          padding-block: var(--boxel-sp-5xs);
          color: var(--muted-foreground);
        }
        @container (width < 40rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends PlanWork {
    <template>
      <article class='emb'>
        <Head @mark='Pl' @title={{@model.name}} @meta={{subjectLine @model}} />
        <div class='body'>
          <div class='dots'><PlanDots @model={{@model}} /></div>
          <p class='fact'>{{dueFact @model}}</p>
          <Kv>
            <KvRow @label='Trigger' @value={{@model.trigger.summary}} />
            <KvRow @label='Lead time' @value={{days @model.trigger.leadDays}} />
            <KvRow @label='Estimate' @value={{hours @model.estimatedHours}} />
            <KvRow @label='Priority' @value={{@model.priority}} />
            <KvRow @label='Team' @value={{@model.assignTeamName}} />
            <KvRow
              @label='Window'
              @value={{days @model.complianceWindowDays}}
            />
            {{#if @model.asset}}
              <KvRow @label='Asset'><@fields.asset @format='atom' /></KvRow>
            {{/if}}
            <KvRow @label='Next work'>{{#if this.nextWork}}<WoChip
                  @wo={{this.nextWork}}
                />{{else}}—{{/if}}</KvRow>
            <KvRow @label='Last work'>{{#if this.lastWork}}<WoChip
                  @wo={{this.lastWork}}
                />{{else}}—{{/if}}</KvRow>
          </Kv>
        </div>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .body {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        }
        .dots {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof MaintenancePlan> {
    <template>
      <RichFittedCard class='fit'>
        <:avatar><Mark @text='Pl' @size='lg' /></:avatar>
        <:title>{{@model.name}}</:title>
        <:subtitle>{{subjectLine @model}}</:subtitle>
        <:status><span class='dots'><PlanDots
              @model={{@model}}
            /></span></:status>
        <:fact>{{dueFact @model}}</:fact>
        <:relations>{{#if @model.asset}}<@fields.asset
              @format='atom'
            />{{/if}}</:relations>
      </RichFittedCard>
      <style scoped>
        .fit {
          color: var(--card-foreground);
          background-color: var(--card);
        }
        .dots {
          display: inline-flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof MaintenancePlan> {
    <template>
      <Chip
        @bare={{true}}
        @mark='Pl'
        @name={{@model.name}}
        @tone={{if @model.active 'ok' 'muted'}}
        @meta={{if @model.active 'active' 'paused'}}
      />
    </template>
  };
}

function stamp(d?: Date | string | null): number {
  return d ? new Date(d).getTime() || 0 : 0;
}
function woTone(status?: string) {
  return DONE.has(status ?? '') ? 'ok' : 'muted';
}
function woLabel(status?: string) {
  return (status ?? '').replace(/-/g, ' ');
}
function historySub(w: any): string {
  let when = fmtDay(w.completedAt ?? w.closedAt, true);
  return [when ? `Closed ${when}` : '', w.ownership?.ownerName]
    .filter(Boolean)
    .join(' · ');
}

function subjectLine(m: Partial<MaintenancePlan>): string {
  if (m.asset) return [m.assetName, m.assetTag].filter(Boolean).join(' · ');
  let c = (m.category as any)?.name;
  return c ? `${c} · template` : 'No subject yet';
}
function meterText(m: Partial<MaintenancePlan>, v: number): string {
  return `${v.toLocaleString('en-US')} ${m.trigger?.meterUnit ?? ''}`.trim();
}
function dueFact(m: Partial<MaintenancePlan>): string {
  let n = planNext(m as MaintenancePlan);
  let parts: string[] = [];
  if (n.dueDate) parts.push(`Next due ${fmtDay(n.dueDate, true)}`);
  if (n.dueMeter != null) {
    parts.push(
      `${n.dueDate ? 'or ' : 'Next due '}at ${meterText(m, n.dueMeter)}`,
    );
  }
  return parts.join(' · ') || 'No rhythm set';
}
function calendarLine(m: Partial<MaintenancePlan>): string {
  let c = m.trigger?.calendar;
  if (!c?.pattern || c.pattern === 'none') return '';
  let data = planTriggerData(m as MaintenancePlan);
  let s = triggerSummary(
    data ? { ...data, meterThreshold: undefined, leadDays: undefined } : data,
  );
  return c.startDate ? `${s} from ${fmtDay(c.startDate, true)}` : s;
}
function meterLine(m: Partial<MaintenancePlan>): string {
  let t = m.trigger;
  return t?.meterThreshold
    ? `Every ${t.meterThreshold.toLocaleString('en-US')} ${t.meterUnit ?? ''}`.trim()
    : '';
}
function ruleLine(m: Partial<MaintenancePlan>): string {
  let t = m.trigger;
  if (!t?.meterThreshold || !t?.calendar?.pattern) return '';
  return t.whicheverFirst === false
    ? 'Both must be due'
    : 'Whichever comes first';
}
function days(n?: number | null): string {
  return n != null ? `${n} day${n === 1 ? '' : 's'}` : '';
}
function hours(n?: number | null): string {
  return n != null ? `${n} h` : '';
}
function itemSub(i: any): string {
  if (i?.kind === 'measure' && i?.expectedValue != null) {
    let tol = i.tolerance != null ? ` ± ${i.tolerance}` : '';
    return `measure · ${i.expectedValue} ${i.unit ?? ''}${tol}`.trim();
  }
  return i?.kind ?? 'check';
}

const PlanDots: TemplateOnlyComponent<{
  Args: { model: Partial<MaintenancePlan> };
}> = <template>
  <Dot
    @tone={{if @model.isOverdue 'bad' (if @model.active 'ok' 'muted')}}
    @label={{if
      @model.isOverdue
      'overdue'
      (if @model.active 'active' 'paused')
    }}
  />
  {{#if @model.kind}}<Dot @tone='info' @label={{@model.kind}} />{{/if}}
  {{#if @model.priority}}<Dot @label={{@model.priority}} />{{/if}}
</template>;

const PlanDetails: TemplateOnlyComponent<{
  Args: { model: Partial<MaintenancePlan> };
}> = <template>
  <Kv>
    <KvRow @label='Trigger' @value={{@model.trigger.summary}} />
    <KvRow @label='Lead time' @value={{days @model.trigger.leadDays}} />
    <KvRow @label='Estimate' @value={{hours @model.estimatedHours}} />
    <KvRow @label='Priority' @value={{@model.priority}} />
    <KvRow @label='Team' @value={{@model.assignTeamName}} />
    <KvRow @label='Window' @value={{days @model.complianceWindowDays}} />
    <KvRow @label='Last done' @value={{fmtDay @model.lastCompletedAt true}} />
    <KvRow
      @label='Checklist'
      @value={{concat @model.checklist.items.length ' items'}}
    />
  </Kv>
</template>;

const WoChip: TemplateOnlyComponent<{ Args: { wo: any } }> = <template>
  <Chip
    @mark='WO'
    @name={{@wo.cardTitle}}
    @tone={{woTone @wo.status}}
    @meta={{woLabel @wo.status}}
  />
</template>;

function concat(a: unknown, b: unknown) {
  return `${a ?? 0}${b ?? ''}`;
}

export default MaintenancePlan;
