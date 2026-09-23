import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import TimerIcon from '@cardstack/boxel-icons/timer';

import { SlaPolicy } from '@cardstack/catalog/cards/service-desk/sla-policy';
import { SlaTimerField } from '@cardstack/catalog/cards/service-desk/sla-timer-field';
import { SlaWindowField } from '@cardstack/catalog/fields/sla-window/sla-window-field';
import { SlaTimerBadge } from '@cardstack/catalog/cards/service-desk/components/sla-timer-badge';
import {
  timerSnapshot,
  sortByUrgency,
} from '@cardstack/catalog/cards/service-desk/utils/sla';
import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';

/**
 * A pause on the clock, as an EVENT — never a boolean. While the ball is with
 * the customer, elapsed time stops; the interval is stored so "paused 17h"
 * is answerable, and fairness of the metric is auditable.
 */
export class PauseIntervalField extends FieldDef {
  static displayName = 'Pause Interval';

  @field pausedAt = contains(DateTimeField);
  @field resumedAt = contains(DateTimeField);
  @field reason = contains(StringField, {
    description: 'e.g. waiting-on-customer.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: PauseIntervalField) {
      let from = relativeStamp(this.pausedAt ?? undefined);
      return this.resumedAt
        ? `Paused ${from ?? ''} → resumed`
        : `Paused ${from ?? ''}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='pause'>⏸
        {{@model.title}}{{#if @model.reason}} · {{@model.reason}}{{/if}}</span>
      <style scoped>
        .pause {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

class SlaEdit extends Component<typeof Sla> {
  @tracked activeSection = 'promise';

  sections = [
    { id: 'promise', label: 'Promise' },
    { id: 'clocks', label: 'Clocks' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.sla-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='sla-edit'>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "promise") "focused"}}'
            data-sect='promise'
          >
            <h3>Promise
              <span class='sect-hint'>the policy and the frozen window</span></h3>
            <FieldContainer @label='Window' @vertical={{true}}>
              <@fields.window />
            </FieldContainer>
          </section>
          <section
            class='sect {{if (eq this.activeSection "clocks") "focused"}}'
            data-sect='clocks'
          >
            <h3>Clocks
              <span class='sect-hint'>deadlines are written by commands, never
                by hand</span></h3>
            <FieldContainer @label='Timers' @vertical={{true}}>
              <@fields.timers />
            </FieldContainer>
            <FieldContainer @label='Pauses' @vertical={{true}}>
              <@fields.pauses />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .sla-edit {
        container-type: inline-size;
      }
      .edit-body {
        display: grid;
        grid-template-columns: 10rem 1fr;
        gap: var(--boxel-sp);
        align-items: start;
      }
      @container (width < 34rem) {
        .edit-body {
          grid-template-columns: 1fr;
        }
      }
      .sects {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        padding: var(--boxel-sp-sm);
        scroll-margin-top: var(--boxel-sp);
      }
      .sect.focused {
        border-color: var(--primary, var(--boxel-highlight));
      }
      .sect h3 {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--muted-foreground, var(--boxel-450));
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: 0;
        font-weight: 400;
        font-style: italic;
      }
    </style>
  </template>
}

/**
 * The APPLIED SLA: one promise (a reused SLA Policy) attached to one subject,
 * with the clocks running against it.
 *
 * Composition, not reinvention: the clocks are the ServiceDesk's own
 * `SlaTimerField` (deadlineAt already business-hours-adjusted, written only
 * by commands); the window is frozen onto this record at apply time
 * (`SlaWindowField`) so a later edit to the shared Schedule cannot rewrite
 * history; the countdown/urgency maths is `utils/sla.ts` — one source, so the
 * card, the queue sort and any dashboard can never disagree.
 *
 * `subject` is `linksTo(CardDef)` — NEVER a domain type, so an SLA
 * applies to any card and the clock still renders.
 */
export class Sla extends CardDef {
  static displayName = 'SLA';
  static icon = TimerIcon;

  @field subject = linksTo(CardDef, {
    description: 'The record under this promise. Any card type.',
  });
  @field policy = linksTo(() => SlaPolicy);
  /** Denormalised link facts: consumers join on these instead of touching
      `subject` (a lazy linksTo that would load mid-render). */
  @field subjectId = contains(StringField, {
    computeVia: function (this: Sla) {
      return this.subject?.id;
    },
  });
  @field subjectTitle = contains(StringField, {
    computeVia: function (this: Sla) {
      return (this.subject as any)?.cardTitle ?? (this.subject as any)?.title;
    },
  });
  @field window = contains(SlaWindowField);
  @field timers = containsMany(SlaTimerField);
  @field pauses = containsMany(PauseIntervalField);
  @field startedAt = contains(DateTimeField);

  /**
   * Snapshot state across all timers: the WORST clock speaks for the record.
   * Stale between writes by design (see SlaTimerField) — live surfaces use
   * the badge, which recomputes.
   */
  @field state = contains(StringField, {
    computeVia: function (this: Sla) {
      let timers = this.timers ?? [];
      if (!timers.length) return 'pending';
      let worst = sortByUrgency(timers)[0];
      return timerSnapshot(worst!).state;
    },
  });

  @field nearestLabel = contains(StringField, {
    computeVia: function (this: Sla) {
      let timers = this.timers ?? [];
      if (!timers.length) return 'No clocks';
      let worst = sortByUrgency(timers)[0];
      let snap = timerSnapshot(worst!);
      return `${worst!.kind ?? 'SLA'}: ${snap.shortLabel}`;
    },
  });

  @field pausedMinutesTotal = contains(NumberField, {
    computeVia: function (this: Sla) {
      let total = 0;
      for (let p of this.pauses ?? []) {
        let from = p.pausedAt
          ? new Date(p.pausedAt as unknown as string)
          : null;
        let to = p.resumedAt
          ? new Date(p.resumedAt as unknown as string)
          : null;
        if (from && to)
          total += Math.round((to.getTime() - from.getTime()) / 60000);
      }
      return total;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Sla) {
      let policy = this.policy?.name;
      return policy ? `SLA · ${policy}` : 'SLA';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='sla-page'>
        <header class='sla-head'>
          <h1><@fields.title /></h1>
          <span class='sla-subject'>on <@fields.subject @format='atom' /></span>
        </header>
        <section class='sla-clocks'>
          <h2>Clocks</h2>
          {{#each @model.timers as |timer|}}
            <SlaTimerBadge
              @facts={{timer}}
              @caption={{timer.kind}}
              @live={{true}}
              @showBar={{true}}
            />
          {{else}}
            <p class='sla-none'>No clocks running — apply a policy to start
              them.</p>
          {{/each}}
        </section>
        <section class='sla-meta'>
          <div class='sla-cell'>
            <h3>Window</h3>
            <@fields.window @format='embedded' />
          </div>
          <div class='sla-cell'>
            <h3>Policy</h3>
            <@fields.policy @format='atom' />
          </div>
          <div class='sla-cell'>
            <h3>Pauses</h3>
            {{#if @model.pauses.length}}
              <@fields.pauses @format='embedded' />
              <p class='sla-paused-total'>{{@model.pausedMinutesTotal}}
                min paused in total — excluded from every consumed figure.</p>
            {{else}}
              <p class='sla-none'>Never paused.</p>
            {{/if}}
          </div>
        </section>
      </article>
      <style scoped>
        .sla-page {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .sla-head {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
        .sla-subject {
          color: var(--muted-foreground, var(--boxel-450));
          font-size: var(--boxel-font-size-sm);
        }
        h2,
        h3 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.1em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .sla-clocks {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .sla-meta {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
          gap: var(--boxel-sp);
        }
        .sla-cell {
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp-sm);
          background: var(--card, var(--boxel-light));
        }
        .sla-none {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
        .sla-paused-total {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='sla-embedded'>
        {{#each @model.timers as |timer|}}
          <SlaTimerBadge
            @facts={{timer}}
            @caption={{timer.kind}}
            @live={{true}}
            @showBar={{true}}
          />
        {{else}}
          <span class='sla-none'>No clocks</span>
        {{/each}}
      </div>
      <style scoped>
        .sla-embedded {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          width: 100%;
        }
        .sla-none {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='sla-atom'>{{@model.nearestLabel}}</span>
      <style scoped>
        .sla-atom {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get worstTimer() {
      let timers = this.args.model.timers ?? [];
      if (!timers.length) return undefined;
      return sortByUrgency(timers)[0];
    }
    <template>
      <div class='sla-fitted'>
        <TimerIcon class='sla-icon' aria-hidden='true' />
        <div class='sla-fitted-body'>
          <span class='sla-fitted-title'>{{@model.title}}</span>
          {{#if this.worstTimer}}
            <SlaTimerBadge @facts={{this.worstTimer}} @live={{false}} />
          {{/if}}
          <div class='sla-fitted-more'>
            {{#each @model.timers as |timer|}}
              <SlaTimerBadge
                @facts={{timer}}
                @caption={{timer.kind}}
                @live={{false}}
                @showBar={{true}}
              />
            {{/each}}
            {{#if @model.pauses.length}}
              <span class='sla-fitted-note'>{{@model.pauses.length}}
                pause(s) ·
                {{@model.pausedMinutesTotal}}m excluded</span>
            {{/if}}
            <span class='sla-fitted-note'>{{@model.window.title}}</span>
          </div>
        </div>
      </div>
      <style scoped>
        .sla-fitted {
          height: 100%;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .sla-icon {
          flex: none;
          width: 1.25rem;
          height: 1.25rem;
          color: var(--primary, var(--boxel-highlight));
        }
        .sla-fitted-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
        }
        .sla-fitted-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        /* progressive data: taller tiles ADD the full clock set */
        .sla-fitted-more {
          display: none;
        }
        @container fitted-card (height > 170px) {
          .sla-fitted-more {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-4xs);
            margin-top: var(--boxel-sp-4xs);
          }
          .sla-fitted-note {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground, var(--boxel-450));
          }
        }
        @container fitted-card (height <= 80px) {
          .sla-fitted {
            align-items: center;
          }
        }
      </style>
    </template>
  };
  static edit = SlaEdit;
}

export default Sla;
