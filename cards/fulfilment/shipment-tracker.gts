import GlimmerComponent from '@glimmer/component';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { StepList } from '@cardstack/pretui/components/step-list';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { lifecycleSteps } from './fulfilment-ui';
import {
  SHIPMENT_PIPELINE,
  shipmentStatusStyle,
  shipmentStageIndex,
  isShipmentException,
} from './shipment-status';

// Shipment Tracker (ST), Tracking Status View (TV) and Feed (Fe) — three
// densities of the same journey, shipped from one module because they read the
// same event log and must never disagree about it.
//
// All three are domain-neutral in the way that matters: they are handed a
// status, a list of events and an optional promise, and have no idea what a
// warehouse is. Anything with scans can mount them.

type TrackingEventLike = {
  occurredAt?: Date | null;
  statusCode?: string | null;
  statusDescription?: string | null;
  location?: string | null;
  isDelivered?: boolean | null;
};

type DeliveryWindowLike = {
  label?: string | null;
  relativeLabel?: string | null;
  isOverdue?: boolean;
};

function sortEvents(events: TrackingEventLike[] | undefined) {
  return [...(events ?? [])]
    .filter(Boolean)
    .sort(
      (a, b) => (a.occurredAt?.getTime() ?? 0) - (b.occurredAt?.getTime() ?? 0),
    );
}

// ── Tracking Status View (TV) ───────────────────────────────────────────────
// The compact rail. Four fixed stages, because a package's progress is only
// legible as a fraction of a known route. A package in exception shows the rail
// stalled where it stopped rather than pretending to advance — a progress bar
// that keeps moving while nothing happens is a lying affordance.
interface RailSignature {
  Args: {
    status?: string | null;
    deliveryWindow?: DeliveryWindowLike | null;
  };
  Element: HTMLDivElement;
}

export class TrackingStatusView extends GlimmerComponent<RailSignature> {
  get steps() {
    return lifecycleSteps(
      SHIPMENT_PIPELINE,
      (value) => shipmentStatusStyle(value).label,
      shipmentStageIndex(this.args.status),
    );
  }

  get isException() {
    return isShipmentException(this.args.status);
  }

  get exceptionLabel() {
    return shipmentStatusStyle(this.args.status).label;
  }

  <template>
    <div class='rail' ...attributes>
      {{! Pret UI StepList: an ordered list with a state per stage, the current
          stage marked aria-current, and state text for assistive tech. }}
      <StepList
        class='stages'
        @steps={{this.steps}}
        @label='Shipment progress'
      />

      {{#if this.isException}}
        <p class='exception'>Stalled: {{this.exceptionLabel}}</p>
      {{else if @deliveryWindow.label}}
        <p class='promise'>
          Due
          <strong>{{@deliveryWindow.label}}</strong>
          {{#if @deliveryWindow.relativeLabel}}
            <span
              class='{{if @deliveryWindow.isOverdue "overdue"}}'
            >({{@deliveryWindow.relativeLabel}})</span>
          {{/if}}
        </p>
      {{/if}}
    </div>

    <style scoped>
      .rail {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      /* StepList knobs: a completed stage's check reads the success ink rather
         than the fill, and the labels sit at the rail's old caption size. */
      .stages {
        --text-ui: 0.75rem;
        --pretui-step-complete-marker-fg: var(--success-ink);
      }
      .promise,
      .exception {
        margin: 0;
        font-size: 0.8rem;
        color: var(--muted-foreground);
      }
      .promise strong {
        color: var(--foreground);
      }
      .overdue,
      .exception {
        font-weight: 700;
        color: var(--destructive-ink);
      }
    </style>
  </template>
}

// ── Feed (Fe) ───────────────────────────────────────────────────────────────
// The scan log, newest last, the way a carrier prints it. Empty is a designed
// state: a package with no scans yet is normal for the first few hours, and
// saying so is more useful than an empty box.
interface FeedSignature {
  Args: {
    events?: TrackingEventLike[];
    emptyMessage?: string;
  };
  Element: HTMLDivElement;
}

export class TrackingEventFeed extends GlimmerComponent<FeedSignature> {
  get ordered() {
    // Read each property explicitly rather than spreading: these are field
    // instances, whose values live on prototype accessors that a spread would
    // silently drop.
    return sortEvents(this.args.events).map((e, i, all) => ({
      occurredAt: e.occurredAt ?? undefined,
      statusDescription: e.statusDescription,
      location: e.location,
      isLatest: i === all.length - 1,
    }));
  }

  <template>
    <div class='feed' ...attributes>
      {{#if this.ordered.length}}
        <ol class='events'>
          {{#each this.ordered as |event|}}
            <li class='event {{if event.isLatest "latest"}}'>
              <span class='marker' aria-hidden='true'></span>
              <div class='body'>
                <span class='when'><FormatDate
                    @date={{event.occurredAt}}
                    @weekday='short'
                    @day='numeric'
                    @month='short'
                    @hour='2-digit'
                    @minute='2-digit'
                    @placeholder=''
                  /></span>
                <span class='what'>{{event.statusDescription}}</span>
                {{#if event.location}}
                  <span class='where'>{{event.location}}</span>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ol>
      {{else}}
        <EmptyState
          style={{COMPACT_EMPTY_STYLE}}
          @texture={{false}}
          @title={{if @emptyMessage @emptyMessage 'No carrier scans yet'}}
          @message={{unless
            @emptyMessage
            'The first one usually appears within a few hours of handover.'
          }}
        />
      {{/if}}
    </div>

    <style scoped>
      .feed {
        min-width: 0;
      }
      .events {
        margin: 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: 0;
      }
      .event {
        position: relative;
        display: grid;
        grid-template-columns: 1.125rem minmax(0, 1fr);
        gap: var(--boxel-sp-xs);
        padding-bottom: var(--boxel-sp-sm);
      }
      /* The spine runs through the markers rather than beside them, so the
         column stays aligned however long a description wraps. */
      .event::before {
        content: '';
        position: absolute;
        left: 0.3125rem;
        top: 0.75rem;
        bottom: 0;
        width: 0.125rem;
        background-color: color-mix(
          in oklch,
          var(--foreground) 10%,
          transparent
        );
      }
      .event:last-child::before {
        display: none;
      }
      .marker {
        margin-top: 0.25rem;
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: color-mix(
          in oklch,
          var(--foreground) 25%,
          transparent
        );
      }
      .event.latest .marker {
        width: 0.75rem;
        height: 0.75rem;
        margin-top: 0.125rem;
        margin-left: -0.125rem;
        background-color: color-mix(
          in oklch,
          var(--foreground) 60%,
          transparent
        );
      }
      .body {
        display: grid;
        gap: 0.0625rem;
        min-width: 0;
      }
      .when {
        font-family: var(--font-mono);
        font-size: 0.72rem;
        color: var(--muted-foreground);
      }
      .what {
        font-size: 0.88rem;
        font-weight: 600;
        color: var(--foreground);
      }
      .event.latest .what {
        font-weight: 800;
      }
      .where {
        font-size: 0.78rem;
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// ── Shipment Tracker (ST) ───────────────────────────────────────────────────
// The composed surface: rail on top, log beneath, and the carrier's own page
// one click away. Composition rather than a third implementation, so a fix to
// either half lands in all three consumers at once.
interface TrackerSignature {
  Args: {
    status?: string | null;
    events?: TrackingEventLike[];
    deliveryWindow?: DeliveryWindowLike | null;
    trackingUrl?: string | null;
    compact?: boolean;
  };
  Element: HTMLDivElement;
}

export class ShipmentTracker extends GlimmerComponent<TrackerSignature> {
  <template>
    <div class='tracker' ...attributes>
      <TrackingStatusView
        @status={{@status}}
        @deliveryWindow={{@deliveryWindow}}
      />

      {{#unless @compact}}
        <TrackingEventFeed @events={{@events}} class='log' />
      {{/unless}}

      {{#if @trackingUrl}}
        <a
          class='out'
          href={{@trackingUrl}}
          target='_blank'
          rel='noopener noreferrer'
        >Open on the carrier's site</a>
      {{/if}}
    </div>

    <style scoped>
      .tracker {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .log {
        padding-top: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .out {
        justify-self: start;
        font-size: 0.8rem;
        color: var(--foreground);
        text-decoration: underline;
        text-underline-offset: 0.1875rem;
        text-decoration-color: color-mix(
          in oklch,
          var(--foreground) 35%,
          transparent
        );
      }
    </style>
  </template>
}

export default ShipmentTracker;
