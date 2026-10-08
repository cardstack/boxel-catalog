import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import BellIcon from '@cardstack/boxel-icons/bell';
import { gt } from '@cardstack/boxel-ui/helpers';
import ClockIcon from '@cardstack/boxel-icons/clock';
import UserIcon from '@cardstack/boxel-icons/user';
import HashIcon from '@cardstack/boxel-icons/hash';
import LinkIcon from '@cardstack/boxel-icons/link';
import ExternalLinkIcon from '@cardstack/boxel-icons/external-link';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';
import enumField from '@cardstack/base/enum';

export const NotificationSeverityField = enumField(StringField, {
  options: [
    { value: 'info', label: 'Info' },
    { value: 'success', label: 'Success' },
    { value: 'warning', label: 'Warning' },
    { value: 'critical', label: 'Critical' },
  ],
});

/**
 * One thing a person needs to be told.
 *
 * ### `dedupeKey` is the field that stops the classic bug
 *
 * Anything that sends notifications gets retried — a job re-runs, a webhook
 * redelivers, a user double-clicks. Without a stable key, the same event
 * produces five copies and the recipient learns to ignore the channel.
 *
 * The key is the **caller's** to choose and should describe the event, not
 * the attempt: `work-order-1841/overdue`, not a timestamp or a UUID. A key
 * that changes per attempt deduplicates nothing.
 *
 * ### Read state belongs to the notification, not the reader
 *
 * One notification, one recipient. Fanning out to five people makes five
 * rows, because otherwise `readAt` has to become a map and every consumer
 * has to understand it. The duplication is cheaper than the shared-state bug.
 *
 * ### Severity is not priority
 *
 * `critical` describes the **event**, not how fast someone should look. A
 * critical alert that is three weeks old is still critical and no longer
 * urgent. Anything sorting a queue should read `severity` and `createdAt`
 * together rather than treating one as the other.
 */
export class Notification extends CardDef {
  static displayName = 'Notification';
  static icon = BellIcon;

  @field recipientRef = contains(StringField, {
    description:
      'Who this is for. One recipient per notification — see the readMe on why this is not a list.',
  });
  @field subject = contains(StringField);
  @field body = contains(StringField);
  @field severity = contains(NotificationSeverityField);

  @field dedupeKey = contains(StringField, {
    description:
      'Stable per EVENT, not per attempt: "work-order-1841/overdue". A key that changes per retry deduplicates nothing.',
  });

  @field createdAt = contains(DateTimeField);
  @field readAt = contains(DateTimeField);
  @field expiresAt = contains(DateTimeField, {
    description:
      'After this, the notification is stale — a reminder about a meeting that already happened helps nobody.',
  });

  @field actionUrl = contains(UrlField, {
    description:
      'Where to go to act on this. Blank means there is nothing to do.',
  });
  @field actionLabel = contains(StringField);

  // What this is about. A link rather than a string so the notification
  // follows a rename, and so opening it lands on the real record.
  @field subjectCard = linksTo(() => CardDef);

  @field isRead = contains(BooleanField, {
    computeVia: function (this: Notification) {
      return Boolean(this.readAt);
    },
  });

  @field isExpired = contains(BooleanField, {
    computeVia: function (this: Notification) {
      return Boolean(this.expiresAt && new Date(this.expiresAt) <= new Date());
    },
  });

  // Unread AND not expired. The only definition a badge count should use —
  // counting expired items trains people to dismiss the badge rather than
  // read it.
  @field isPending = contains(BooleanField, {
    computeVia: function (this: Notification) {
      if (this.readAt) {
        return false;
      }
      return !(this.expiresAt && new Date(this.expiresAt) <= new Date());
    },
  });

  @field isActionable = contains(BooleanField, {
    computeVia: function (this: Notification) {
      return Boolean(this.actionUrl);
    },
  });

  @field ageHours = contains(NumberField, {
    computeVia: function (this: Notification) {
      if (!this.createdAt) {
        return undefined;
      }
      return Math.floor(
        (Date.now() - new Date(this.createdAt).getTime()) / 3600000,
      );
    },
  });

  // One notification, not a layout surface — the ~800px cap is the right
  // measure, so prefersWideFormat stays at its default false.

  static isolated = class Isolated extends Component<typeof this> {
    // The question: what happened, and do I need to do something. The
    // answer is the subject plus whether an action is still open — which is
    // why isPending, not severity, drives the headline state.
    get standing(): string {
      if (this.args.model.isExpired) {
        return 'Expired — no longer actionable';
      }
      if (this.args.model.isRead) {
        return 'Read';
      }
      return this.args.model.isActionable ? 'Needs action' : 'Unread';
    }

    get ageLabel(): string {
      let h = this.args.model.ageHours;
      if (h == null) {
        return '';
      }
      if (h < 24) {
        return `${h}h ago`;
      }
      return `${Math.floor(h / 24)}d ago`;
    }

    <template>
      <article
        class='card {{@model.severity}} {{if @model.isRead "read" "unread"}}'
      >
        <header class='hero'>
          <span class='rail' aria-hidden='true'></span>
          <div class='hero-body'>
            <p class='eyebrow'>
              <BellIcon width='14' height='14' aria-hidden='true' />
              {{@model.severity}}
              notification
            </p>
            {{! The subject IS the answer here — so it is the dominant
              element, not a caption above one. }}
            <h1 class='subject'>{{@model.subject}}</h1>
            {{#if @model.body}}<p class='body'>{{@model.body}}</p>{{/if}}
            <p class='standing'>
              {{#if @model.isRead}}
                <CircleCheckIcon width='14' height='14' aria-hidden='true' />
              {{/if}}
              {{this.standing}}
              {{#if this.ageLabel}} · {{this.ageLabel}}{{/if}}
            </p>
          </div>
        </header>

        {{#if @model.isActionable}}
          {{! Actions sit directly under the hero, not stranded at the foot
            of the scroll — this is the one thing the reader came to do. }}
          <nav class='actions' aria-label='Actions'>
            <a class='cta' href={{@model.actionUrl}}>
              {{if @model.actionLabel @model.actionLabel 'Open'}}
              <ExternalLinkIcon width='15' height='15' aria-hidden='true' />
            </a>
          </nav>
        {{/if}}

        <section class='glance' aria-label='At a glance'>
          <div class='stat'>
            <UserIcon width='15' height='15' aria-hidden='true' />
            <span class='k'>Recipient</span>
            <span class='v'>{{@model.recipientRef}}</span>
          </div>
          <div class='stat'>
            <ClockIcon width='15' height='15' aria-hidden='true' />
            <span class='k'>Raised</span>
            <span class='v'><@fields.createdAt /></span>
          </div>
          <div class='stat'>
            <ClockIcon width='15' height='15' aria-hidden='true' />
            <span class='k'>Expires</span>
            {{#if @model.expiresAt}}
              <span class='v'><@fields.expiresAt /></span>
            {{else}}
              <span class='v none'>does not expire</span>
            {{/if}}
          </div>
        </section>

        {{#if @model.subjectCard}}
          <section class='sec' aria-label='About'>
            <h2><LinkIcon width='16' height='16' aria-hidden='true' />
              About</h2>
            <@fields.subjectCard @displayContainer={{false}} />
          </section>
        {{/if}}

        <section class='sec' aria-label='Delivery'>
          <h2><HashIcon width='16' height='16' aria-hidden='true' />
            Delivery</h2>
          {{! Surfaced deliberately: the dedupe key is the field that decides
            whether a retry writes a second copy, and a support question
            about a duplicated alert is answered by reading it. }}
          <dl class='kv'>
            <dt>Dedupe key</dt>
            <dd class='mono'>{{@model.dedupeKey}}</dd>
            <dt>Counts toward badge</dt>
            <dd>{{if @model.isPending 'yes' 'no'}}</dd>
          </dl>
        </section>
      </article>

      <style scoped>
        /* Rule 1: isolated has no host container — declare our own or every
           @container rule below is inert. */
        .card {
          container-type: inline-size;
          container-name: card;
          width: 100%;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          box-sizing: border-box;
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          font-family: var(--font-sans, var(--boxel-font-family));

          --panel-bg: color-mix(
            in oklch,
            var(--foreground, #000) 3%,
            transparent
          );
          --panel-pad: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          --panel-radius: var(--radius, 8px);
          --tone: var(--muted-foreground, var(--boxel-450));
        }
        .card.success {
          --tone: var(--success, #2f855a);
        }
        .card.warning {
          --tone: var(--warning, #b7791f);
        }
        .card.critical {
          --tone: var(--destructive, var(--boxel-danger));
        }

        .hero {
          display: flex;
          gap: var(--boxel-sp);
          padding: var(--panel-pad);
          border-radius: var(--panel-radius);
          background: color-mix(in oklch, var(--tone) 6%, transparent);
        }
        /* Same signature spine as Call — one family, one mark. */
        .rail {
          flex: none;
          width: 4px;
          border-radius: 2px;
          background: var(--tone);
        }
        .hero-body {
          min-width: 0;
        }
        .eyebrow {
          display: flex;
          align-items: center;
          gap: 5px;
          margin: 0;
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground, var(--boxel-450));
        }
        /* Dominant element: 2.2x the body. Unread adds weight on top —
           colour is already carrying severity. */
        .subject {
          margin: var(--boxel-sp-xxs) 0 0;
          font-size: 2.0625rem;
          font-weight: 600;
          line-height: 1.15;
          letter-spacing: -0.02em;
          max-width: 24ch;
        }
        .card.unread .subject {
          font-weight: 800;
        }
        .body {
          margin: var(--boxel-sp-xs) 0 0;
          max-width: 62ch;
          font-size: 0.9375rem;
          line-height: 1.55;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .standing {
          display: flex;
          align-items: center;
          gap: 5px;
          margin: var(--boxel-sp-xs) 0 0;
          font-size: 0.8125rem;
          font-weight: 600;
          color: var(--tone);
        }

        .actions {
          display: flex;
          gap: var(--boxel-sp-xs);
        }
        .cta {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xxs);
          padding: var(--boxel-sp-xs) var(--boxel-sp);
          border-radius: var(--panel-radius);
          background: var(--tone);
          color: var(--background, var(--boxel-light));
          font-size: 0.9375rem;
          font-weight: 600;
          text-decoration: none;
        }
        .cta:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 2px;
        }

        .glance {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
          gap: var(--boxel-sp-xs);
        }
        .stat {
          display: grid;
          grid-template-columns: auto 1fr;
          grid-template-areas: 'i k' 'v v';
          align-items: center;
          gap: 2px var(--boxel-sp-xxs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-radius: var(--panel-radius);
          background: var(--panel-bg);
        }
        .stat svg {
          grid-area: i;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .k {
          grid-area: k;
          font-size: 0.6875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .v {
          grid-area: v;
          font-size: 0.9375rem;
          font-variant-numeric: tabular-nums;
        }
        .v.none {
          color: var(--muted-foreground, var(--boxel-450));
        }

        .sec {
          padding: var(--panel-pad);
          border-radius: var(--panel-radius);
          background: var(--panel-bg);
        }
        .sec h2 {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xxs);
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.8125rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .sec h2 svg {
          width: max(14px, 1em);
          height: max(14px, 1em);
        }
        .kv {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp-xxs) var(--boxel-sp);
          margin: 0;
          font-size: 0.875rem;
        }
        .kv dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .kv dd {
          margin: 0;
        }
        /* A dedupe key is read and typed into other systems — never
           ellipsised. */
        .mono {
          font-family: var(--font-mono, monospace);
          font-size: 0.8125rem;
          overflow-wrap: anywhere;
        }

        @container card (width < 560px) {
          .glance {
            grid-template-columns: 1fr;
          }
          .subject {
            font-size: 1.625rem;
          }
        }
        @container card (width < 400px) {
          .subject {
            font-size: 1.375rem;
          }
          .kv {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article
        class='fit {{@model.severity}} {{unless @model.isRead "unread"}}'
      >
        <div class='r-head'>
          <BellIcon class='glyph' width='14' height='14' aria-hidden='true' />
          <h3 class='title'>{{@model.subject}}</h3>
        </div>
        <div class='r-body'>
          {{#if @model.body}}<p class='body'>{{@model.body}}</p>{{/if}}
        </div>
        <div class='r-meta'>
          {{#if @model.isActionable}}
            <span class='cta'>{{if
                @model.actionLabel
                @model.actionLabel
                'Open'
              }}</span>
          {{/if}}
          {{! Age reads as a whole number of hours or days, never a
            truncated timestamp — data is all-or-nothing. }}
          {{#if (gt @model.ageHours 0)}}
            <span class='age'>{{@model.ageHours}}h</span>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .fit {
          --type-base: clamp(10px, min(calc(3px + 2.1cqi + 1cqb), 10cqb), 16px);
          --type-ratio: 1.25;
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 2px;
          padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
          box-sizing: border-box;
          overflow: hidden;
          background: var(--card, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          font-family: var(--font-sans, var(--boxel-font-family));
          /* Severity is a data hue consumed as a rail, so it marks the cell
             without competing with the title for attention. */
          border-left: 3px solid var(--sev, var(--border, var(--boxel-300)));
        }
        .fit.success {
          --sev: var(--success, #2f855a);
        }
        .fit.warning {
          --sev: var(--warning, #b7791f);
        }
        .fit.critical {
          --sev: var(--destructive, var(--boxel-danger));
        }
        .r-head {
          grid-area: head;
          display: flex;
          align-items: baseline;
          gap: 5px;
          min-height: 0;
          overflow: hidden;
          flex-shrink: 0;
        }
        .r-body {
          grid-area: body;
          min-height: 0;
          overflow: hidden;
        }
        .r-meta {
          grid-area: meta;
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 5px;
          min-height: 0;
          overflow: hidden;
          flex-shrink: 0;
        }

        /* The anchor: the bell is the card's identity glyph (same icon the
           card declares), and the subject is the loudest thing at every
           quantum. Unread adds weight on top — colour is already carrying
           severity and one channel cannot hold two variables. */
        .glyph {
          flex: none;
          align-self: center;
          color: var(--sev, var(--muted-foreground, var(--boxel-450)));
        }
        .title {
          flex: 1;
          min-width: 0;
          margin: 0;
          font-size: calc(var(--type-base) * pow(var(--type-ratio), 1));
          font-weight: 600;
          line-height: 1.2;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
          overflow-wrap: anywhere;
        }
        .fit.unread .title {
          font-weight: 800;
        }
        .body {
          margin: 0;
          font-size: var(--type-base);
          line-height: 1.25;
          color: var(--muted-foreground, var(--boxel-450));
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 3;
          overflow: hidden;
          overflow-wrap: anywhere;
        }
        .cta {
          flex: none;
          font-size: var(--type-base);
          line-height: 1.25;
          white-space: nowrap;
          font-weight: 600;
          color: color-mix(
            in oklch,
            var(--primary, var(--boxel-highlight)) 45%,
            var(--foreground, var(--boxel-dark))
          );
        }
        .age {
          flex: none;
          font-size: var(--type-base);
          line-height: 1.25;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
          color: var(--muted-foreground, var(--boxel-450));
        }

        /* ── height quanta: rows drop whole, never shrink ─────────────── */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            grid-template-areas: 'head';
            padding: 0 var(--boxel-sp-xxs);
            align-items: center;
          }
          .r-body,
          .r-meta {
            display: none;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (50px < height <= 80px) {
          .fit {
            grid-template-rows: auto auto;
            grid-template-areas: 'head' 'meta';
          }
          .r-body {
            display: none;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (80px < height <= 130px) {
          .body {
            -webkit-line-clamp: 1;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }

        /* Narrow: the age goes before the action does — one is context, the
           other is the thing the reader came to do. */
        @container fitted-card (width <= 180px) {
          .age {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .glyph {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article
        class='note {{@model.severity}} {{unless @model.isRead "unread"}}'
      >
        <h4 class='subj'>{{@model.subject}}</h4>
        {{#if @model.body}}<p class='body'>{{@model.body}}</p>{{/if}}
      </article>
      <style scoped>
        .note {
          padding: var(--boxel-sp-xs);
          border-left: 3px solid var(--border, var(--boxel-300));
          color: var(--foreground, var(--boxel-dark));
        }
        /* Severity is a data hue, consumed diluted so it marks the row
           without shouting over the text it is marking. */
        .note.warning {
          border-left-color: var(--warning, #b7791f);
        }
        .note.critical {
          border-left-color: var(--destructive, var(--boxel-danger));
        }
        .note.success {
          border-left-color: var(--success, #2f855a);
        }
        /* Unread is weight, not colour — colour is already carrying
           severity, and one channel cannot hold two variables. */
        .note.unread .subj {
          font-weight: 700;
        }
        .subj {
          margin: 0;
          font: 500 var(--boxel-font-sm);
        }
        .body {
          margin: 2px 0 0;
          font: var(--boxel-font-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default Notification;
