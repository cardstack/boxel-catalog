import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import { on } from '@ember/modifier';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import { Asset } from './asset';
import { AssetCategory } from './asset-category';
import { MaintenanceTriggerField } from './maintenance-trigger-field';
import { ChecklistField } from './checklist-field';
import {
  PlanKindField,
  WorkOrderPriorityField,
} from './maintenance-vocabulary';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import {
  nextOccurrence,
  toDay,
  type MaintenanceTriggerData,
  type NextOccurrence,
} from './utils/recurrence';
import type { Hue } from '@cardstack/catalog/components/state-pill';

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
export function planNext(
  plan: MaintenancePlan,
  today: Date = new Date(),
): NextOccurrence {
  let trigger = planTriggerData(plan);
  let anchor =
    plan.lastCompletedAt ?? plan.trigger?.calendar?.startDate ?? undefined;
  let meterNow = (plan.asset as any)?.primaryMeterValue as number | undefined;
  return nextOccurrence(trigger, anchor, {
    today,
    meterNow: meterNow ?? undefined,
    meterAtAnchor: plan.lastCompletedMeter ?? undefined,
  });
}

export function dueHue(n: NextOccurrence): Hue {
  if (n.isDue) return 'orange';
  if (n.daysUntil != null && n.daysUntil <= 14) return 'amber';
  if (n.decidedBy === 'none') return 'slate';
  return 'green';
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

  static isolated = class Isolated extends Component<typeof MaintenancePlan> {
    get next() {
      return planNext(this.args.model as MaintenancePlan);
    }
    get hue() {
      return dueHue(this.next);
    }
    get due() {
      return dueText(this.next, this.args.model.trigger?.meterUnit);
    }
    get lastLabel() {
      let d = toDay(this.args.model.lastCompletedAt);
      if (!d) return 'never';
      let s = d.toLocaleDateString(undefined, {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
      });
      let m = this.args.model.lastCompletedMeter;
      return m != null
        ? `${s} at ${m.toLocaleString()} ${this.args.model.trigger?.meterUnit ?? ''}`.trim()
        : s;
    }
    get nextLabel() {
      let d = this.next.dueDate;
      return d
        ? d.toLocaleDateString(undefined, {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
          })
        : '—';
    }
    // `viewCard` is a top-level component arg on every card (never
    // `context.actions`) — same convention used throughout this desk.
    openAsset = () => {
      let asset = this.args.model.asset;
      if (asset) this.args.viewCard?.(asset);
    };
    <template>
      <article class='plan'>
        <header class='hero'>
          <div class='hero-main'>
            <span class='kind'>{{if @model.kind @model.kind 'plan'}}{{#if
                @model.isTemplate
              }} · template{{/if}}</span>
            <h1 class='name'>{{@model.name}}</h1>
            <p class='rhythm'><RepeatIcon class='ic' />
              {{@model.trigger.summary}}</p>
            <div class='subject'>
              {{#if @model.asset}}
                <button
                  type='button'
                  class='subject-link'
                  {{on 'click' this.openAsset}}
                >
                  <@fields.asset @format='atom' />
                </button>
              {{else if @model.category}}
                <@fields.category @format='atom' />
              {{else}}
                <span class='muted'>No subject yet</span>
              {{/if}}
              {{#if @model.assignTeamName}}<span class='muted'>·
                  {{@model.assignTeamName}}</span>{{/if}}
              {{#if @model.priority}}<@fields.priority @format='atom' />{{/if}}
            </div>
          </div>
          <aside class='due-card'>
            <StatePill
              @label={{if @model.isOverdue 'Overdue' 'Next due'}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            <div class='due-date'>{{this.nextLabel}}</div>
            <div class='due-text'>{{this.due}}</div>
            <dl class='due-facts'>
              <dt>Last done</dt><dd>{{this.lastLabel}}</dd>
              <dt>Estimate</dt><dd>{{if
                  @model.estimatedHours
                  (concat @model.estimatedHours ' h')
                  '—'
                }}</dd>
              <dt>Window</dt><dd>±
                {{if @model.complianceWindowDays @model.complianceWindowDays 0}}
                d</dd>
              <dt>Active</dt><dd>{{if @model.active 'yes' 'no'}}</dd>
            </dl>
          </aside>
        </header>
        <section class='sec'>
          <h2><ClipboardCheckIcon class='ic' /> Procedure template</h2>
          {{#if @model.checklist.items.length}}
            <@fields.checklist />
          {{else}}
            <p class='muted'>No steps yet — add the checklist that defines
              “done”.</p>
          {{/if}}
        </section>
      </article>
      <style scoped>
        .plan {
          container-type: inline-size;
          display: grid;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 16rem;
          gap: var(--boxel-sp-lg);
          align-items: start;
        }
        .hero-main {
          display: grid;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .kind {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .name {
          margin: 0;
          font-size: 2rem;
          line-height: 1.1;
          font-weight: 700;
          text-wrap: balance;
        }
        .rhythm {
          margin: 0;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size);
          color: var(--foreground);
        }
        .subject {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
        }
        .subject-link {
          border: none;
          background: none;
          padding: 0;
          margin: 0;
          font: inherit;
          color: inherit;
          cursor: pointer;
          border-radius: var(--boxel-border-radius-sm);
        }
        .subject-link:hover,
        .subject-link:focus-visible {
          text-decoration: underline;
          outline: 2px solid var(--primary, var(--boxel-highlight));
          outline-offset: 2px;
        }
        .muted {
          color: var(--muted-foreground);
        }
        .due-card {
          display: grid;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card);
        }
        .due-date {
          font-size: 1.5rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .due-text {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .due-facts {
          margin: var(--boxel-sp-xs) 0 0;
          display: grid;
          grid-template-columns: auto 1fr;
          gap: 2px var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
        }
        .due-facts dt {
          color: var(--muted-foreground);
        }
        .due-facts dd {
          margin: 0;
          font-variant-numeric: tabular-nums;
        }
        .sec {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .sec h2 {
          margin: 0;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .ic {
          width: 1rem;
          height: 1rem;
          flex: none;
        }
        @container (width < 640px) {
          .hero {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof MaintenancePlan> {
    get next() {
      return planNext(this.args.model as MaintenancePlan);
    }
    get hue() {
      return dueHue(this.next);
    }
    <template>
      <div class='plan-emb'>
        <RepeatIcon class='ic' />
        <div class='body'>
          <div class='row'>
            <span class='name'>{{@model.name}}</span>
            {{#if @model.assetTag}}<code
                class='tag'
              >{{@model.assetTag}}</code>{{/if}}
          </div>
          <div class='meta'>{{@model.dueLabel}}</div>
        </div>
        <StatePill
          @label={{if
            @model.isOverdue
            'overdue'
            (if @model.kind @model.kind 'plan')
          }}
          @hue={{this.hue}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .plan-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .ic {
          width: 1rem;
          height: 1rem;
          color: var(--muted-foreground);
          flex: none;
        }
        .body {
          flex: 1;
          min-width: 0;
          display: grid;
          gap: 2px;
        }
        .row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .tag {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof MaintenancePlan> {
    get next() {
      return planNext(this.args.model as MaintenancePlan);
    }
    get hue() {
      return dueHue(this.next);
    }
    get due() {
      return dueText(this.next, this.args.model.trigger?.meterUnit);
    }
    <template>
      <div class='fit'>
        <StatePill
          @label={{if
            @model.isOverdue
            'overdue'
            (if @model.kind @model.kind 'plan')
          }}
          @hue={{this.hue}}
          @dot={{true}}
        />
        <div class='info'>
          <span class='name'>{{@model.name}}</span>
          <span class='line line-due'>{{this.due}}</span>
          <span class='line line-subject'>{{if
              @model.assetTag
              @model.assetTag
              ''
            }}
            {{@model.assetName}}</span>
          <span class='line line-rhythm'>{{@model.trigger.summary}}</span>
        </div>
      </div>
      <style scoped>
        .fit {
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          box-sizing: border-box;
          overflow: hidden;
          color: var(--foreground);
        }
        .info {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .line {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          display: none;
        }
        @container fitted-card (max-height: 80px) {
          .fit {
            align-items: center;
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-due {
            display: block;
          }
        }
        @container fitted-card (min-height: 120px) {
          .line-subject {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .fit {
            flex-direction: column;
            align-items: stretch;
            padding: var(--boxel-sp-sm);
          }
          .info {
            width: 100%;
            min-width: 0;
          }
          .line-rhythm {
            display: block;
            white-space: normal;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof MaintenancePlan> {
    <template>
      <span class='plan-atom'><RepeatIcon class='ic' /> {{@model.name}}</span>
      <style scoped>
        .plan-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
        }
        .ic {
          width: 0.85rem;
          height: 0.85rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof MaintenancePlan> {
    sections = [
      { id: 'plan', label: 'Plan' },
      { id: 'subject', label: 'Subject & team' },
      { id: 'rhythm', label: 'Rhythm' },
      { id: 'procedure', label: 'Procedure' },
      { id: 'history', label: 'History' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Maintenance plan sections'
        as |e|
      >
        <e.Section @id='plan' @title='Plan' @cols={{2}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer @label='Kind' @vertical={{true}}><@fields.kind
            /></FieldContainer>
          <FieldContainer
            @label='Priority of generated work'
            @vertical={{true}}
          ><@fields.priority /></FieldContainer>
          <FieldContainer
            @label='Estimated hours'
            @vertical={{true}}
          ><@fields.estimatedHours /></FieldContainer>
          <FieldContainer @label='Active' @vertical={{true}}><@fields.active
            /></FieldContainer>
          <FieldContainer
            @label='Compliance window (± days)'
            @vertical={{true}}
          ><@fields.complianceWindowDays /></FieldContainer>
        </e.Section>
        <e.Section
          @id='subject'
          @title='Subject & team'
          @hint='An asset, or a category for a template'
          @cols={{2}}
        >
          <FieldContainer @label='Asset' @vertical={{true}}><@fields.asset
            /></FieldContainer>
          <FieldContainer
            @label='Category (template)'
            @vertical={{true}}
          ><@fields.category /></FieldContainer>
          <FieldContainer
            @label='Assign to team'
            @vertical={{true}}
          ><@fields.assignTeamName /></FieldContainer>
        </e.Section>
        <e.Section @id='rhythm' @title='Rhythm'>
          <@fields.trigger />
        </e.Section>
        <e.Section
          @id='procedure'
          @title='Procedure'
          @hint='Template — copied onto each work order'
        >
          <@fields.checklist />
        </e.Section>
        <e.Section
          @id='history'
          @title='History'
          @hint='Stamped by Complete Work Order'
          @cols={{2}}
        >
          <FieldContainer
            @label='Last completed'
            @vertical={{true}}
          ><@fields.lastCompletedAt /></FieldContainer>
          <FieldContainer
            @label='Meter at last completion'
            @vertical={{true}}
          ><@fields.lastCompletedMeter /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

function concat(a: unknown, b: unknown) {
  return `${a ?? ''}${b ?? ''}`;
}

export default MaintenancePlan;
