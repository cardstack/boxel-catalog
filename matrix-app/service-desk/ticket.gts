import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
  StringField,
  type BaseDefComponent,
} from 'https://cardstack.com/base/card-api';
import DateTimeField from 'https://cardstack.com/base/datetime';
import NumberField from 'https://cardstack.com/base/number';
import MarkdownField from 'https://cardstack.com/base/markdown';
import TicketIcon from '@cardstack/boxel-icons/ticket';
import { formatDateTime } from '@cardstack/boxel-ui/helpers';
import { SupportContact } from './support-contact';
import { SupportAgent } from './support-agent';
import { Queue } from './queue';
import { TicketCategory } from './ticket-category';
import { SlaPolicy } from './sla-policy';
import { KnowledgeArticle } from './knowledge-article';
import { SlaTimerField } from './sla-timer-field';
import { TicketMessageField } from './ticket-message-field';
import {
  TicketStatusField,
  TicketPriorityField,
  TicketChannelField,
  TicketTypeField,
} from './ticket-taxonomy';
import { SlaTimerBadge } from './components/sla-timer-badge';
import { priorityOption } from '@cardstack/catalog/fields/priority/priority';
import { timerSnapshot, urgencyRank, type TimerSnapshot } from './utils/sla';
import { Chip } from '@cardstack/pretui/components/chip';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { Stat } from '@cardstack/pretui/components/stat';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { FitTile } from '../shared/fit-tile';
import { FittedExtras } from '../procurement/vendor';

function daysBetween(
  from?: Date | string | null,
  to?: Date | string | null,
): number | undefined {
  if (!from) {
    return undefined;
  }
  let start = new Date(from);
  let end = to ? new Date(to) : new Date();
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return undefined;
  }
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 86400000));
}

/**
 * One request for help, from arrival to resolution.
 *
 * Incident and ServiceRequest extend this rather than being a `type` string on
 * it, which is what lets `linksTo(Ticket)` accept either and keeps an
 * incident's impact/urgency out of every service request. `ticketType` still
 * exists as a field because a subclass name is not something a prerendered
 * tile can read or a queue can sort by.
 */

/**
 * Editing a ticket IS the agent workspace.
 *
 * The default edit format — every field stacked in a form — is the wrong shape
 * for this card. A ticket is not filled in field by field; it is worked: you
 * read what the customer said, you answer, you route it, you resolve it. The
 * console's detail pane was already that surface, so the edit format mounts
 * the same component rather than a second, lesser one. One editing surface,
 * defined once, reached from two places — pressing Edit on a ticket anywhere
 * in Boxel, and selecting a row in the console.
 */

const STATUS_TONE: Record<string, PretuiToneArg> = {
  Open: 'info',
  Pending: 'warning',
  'On Hold': 'warning',
  Resolved: 'success',
  Closed: 'neutral',
};
function ticketStatusTone(status?: string): PretuiToneArg {
  return (status && STATUS_TONE[status]) || 'neutral';
}
function ticketPriorityTone(priority?: string): PretuiToneArg {
  let hue = priorityOption(TicketPriorityField, priority)?.hue ?? 'slate';
  return (
    (
      {
        red: 'danger',
        orange: 'warning',
        amber: 'warning',
        yellow: 'warning',
        green: 'success',
        blue: 'info',
      } as Record<string, PretuiToneArg>
    )[hue] ?? 'neutral'
  );
}

export class Ticket extends CardDef {
  static displayName = 'Ticket';
  static icon = TicketIcon;
  // Same reason: the workspace wants conversation and context side by side.
  static prefersWideFormat = true;

  @field reference = contains(StringField, { description: 'e.g. #1234' });
  @field subject = contains(StringField);
  @field details = contains(MarkdownField);

  @field status = contains(TicketStatusField);
  @field priority = contains(TicketPriorityField);
  @field channel = contains(TicketChannelField);
  @field ticketType = contains(TicketTypeField);

  @field customer = linksTo(() => SupportContact);
  @field assignee = linksTo(() => SupportAgent);
  @field queue = linksTo(() => Queue);
  @field category = linksTo(() => TicketCategory);
  @field slaPolicy = linksTo(() => SlaPolicy);
  @field linkedArticles = linksToMany(() => KnowledgeArticle);
  @field relatedTickets = linksToMany(() => Ticket);

  @field timers = containsMany(SlaTimerField);
  @field messages = containsMany(TicketMessageField);
  @field tags = containsMany(StringField);

  @field openedAt = contains(DateTimeField);
  @field firstRespondedAt = contains(DateTimeField);
  @field resolvedAt = contains(DateTimeField);
  @field closedAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: Ticket) {
      let ref = this.reference?.trim();
      let subject = this.subject?.trim() || 'Untitled ticket';
      return ref ? `${ref} ${subject}` : subject;
    },
  });

  // ------------------------------------------------------------------
  // Flattened display fields.
  //
  // Prerendered fitted views resolve no links, so every one of these exists
  // because a tile needs to say something a link would otherwise have told it.
  // They are also what the queue and the contact history query on — `eq` on a
  // stored string is something the index can answer, walking a relationship is
  // not.
  //
  // If these are wrong, every tile in the app is wrong and no linter will say
  // so. The sixteen-size walk is the only thing that catches it.
  // ------------------------------------------------------------------

  @field customerName = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.customer?.title ?? '';
    },
  });

  @field customerCompany = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.customer?.company ?? '';
    },
  });

  @field assigneeName = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.assignee?.title ?? '';
    },
  });

  @field queueName = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.queue?.title ?? '';
    },
  });

  @field categoryName = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.category?.title ?? '';
    },
  });

  /** The timer that decides the ticket's colour: the nearest one to breaching. */
  get governingTimer(): SlaTimerField | undefined {
    let live = (this.timers ?? []).filter(Boolean);
    if (!live.length) {
      return undefined;
    }
    return [...live].sort(
      (a, b) => urgencyRank(timerSnapshot(a)) - urgencyRank(timerSnapshot(b)),
    )[0];
  }

  get governingSnapshot(): TimerSnapshot | undefined {
    let timer = this.governingTimer;
    return timer ? timerSnapshot(timer) : undefined;
  }

  @field slaState = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.governingSnapshot?.state ?? '';
    },
  });

  @field slaLabel = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.governingSnapshot?.shortLabel ?? '';
    },
  });

  /**
   * The deadline written as a clock time, for surfaces that cannot tick.
   *
   * `slaLabel` is a COUNTDOWN — "2h 34m" — computed once and stored. In a live
   * view that is fine, because the badge recomputes every second. In
   * prerendered fitted HTML it is baked at index time and never updates, so a
   * tile rendered this morning still claims two hours remain at four in the
   * afternoon. A countdown is the one shape of value that cannot survive being
   * cached; a deadline can. Fitted shows this instead.
   */
  @field slaDueLabel = contains(StringField, {
    computeVia: function (this: Ticket) {
      let due = this.governingTimer?.deadlineAt;
      if (!due) {
        return this.governingSnapshot?.state === 'paused' ? 'Paused' : '';
      }
      let at = due instanceof Date ? due : new Date(due);
      if (isNaN(at.getTime())) {
        return '';
      }
      let when = formatDateTime(at, { preset: 'medium', fallback: '' }) ?? '';
      // No 'overdue' wording: whether it has passed is a fact about NOW, and
      // now is exactly what a cached tile does not know. The colour carries
      // the state; the text carries only the deadline, which never rots.
      return when ? `Due ${when}` : '';
    },
  });

  // Sorted on by every queue. A date sorts correctly in the index where a
  // formatted duration ('2h 34m') does not.
  @field slaDeadline = contains(DateTimeField, {
    computeVia: function (this: Ticket) {
      return this.governingTimer?.deadlineAt;
    },
  });

  // Sorting a queue by deadline alone is wrong in one specific, common way: a
  // PAUSED ticket whose deadline has already passed sorts ahead of a live
  // breach, even though nobody is waiting on it. This is the key the queue
  // actually orders by — breached first, then live clocks by time remaining,
  // then paused, then met.
  @field urgencyOrder = contains(NumberField, {
    computeVia: function (this: Ticket) {
      let snapshot = this.governingSnapshot;
      return snapshot ? urgencyRank(snapshot) : Number.MAX_SAFE_INTEGER;
    },
  });

  @field ageLabel = contains(StringField, {
    computeVia: function (this: Ticket) {
      let days = daysBetween(this.openedAt);
      if (days == null) {
        return '';
      }
      return days === 0 ? 'opened today' : `opened ${days}d ago`;
    },
  });

  @field latestMessage = contains(StringField, {
    computeVia: function (this: Ticket) {
      // Public entries only: the first line of an internal note must never
      // surface on a tile, where nobody can see it is internal.
      let publicOnes = (this.messages ?? []).filter(
        (m) => m?.visibility !== 'Internal' && !m?.isSlaEvent,
      );
      let last = publicOnes[publicOnes.length - 1];
      let text = (last?.body ?? '').replace(/\s+/g, ' ').trim();
      return text.length > 160 ? `${text.slice(0, 157)}…` : text;
    },
  });

  // Joined in the model, not the template: interpolating separators between
  // optional values in a template needs `{{#if}}` around each one, and that
  // whitespace is what the linter (correctly) flags as layout-by-spaces.
  @field customerSuffix = contains(StringField, {
    computeVia: function (this: Ticket) {
      return this.customerCompany ? ` · ${this.customerCompany}` : '';
    },
  });

  @field routeLabel = contains(StringField, {
    computeVia: function (this: Ticket) {
      return [this.categoryName, this.queueName, this.assigneeName]
        .filter(Boolean)
        .join(' · ');
    },
  });

  @field tagSummary = contains(StringField, {
    computeVia: function (this: Ticket) {
      return (this.tags ?? []).filter(Boolean).join(' · ');
    },
  });

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof this
  > {
    timerOf = (kind: string) =>
      (this.args.model?.timers ?? []).find((t) => t?.kind === kind);
    snap = (kind: string) => {
      let t = this.timerOf(kind);
      return t ? timerSnapshot(t as any) : undefined;
    };
    get firstResponse() {
      return this.snap('First response');
    }
    get resolution() {
      return this.snap('Resolution');
    }
    get messages() {
      return (this.args.model?.messages ?? []).filter(Boolean);
    }
    get internalCount() {
      return this.messages.filter((m) => m.isInternal).length;
    }
    get timers() {
      return (this.args.model?.timers ?? []).filter(Boolean);
    }
    stamp = (d?: Date) =>
      d
        ? new Date(d).toLocaleString('en-GB', {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
          })
        : '—';
    visTone = (m: any) =>
      m.isSlaEvent ? 'info' : m.isInternal ? 'warning' : 'success';
    visText = (m: any) =>
      m.isSlaEvent ? 'SLA event' : m.isInternal ? 'internal' : 'public';

    <template>
      <article class='tk'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>#</span>
          <span class='id'>
            <h1>{{@model.subject}}</h1>
            <span class='meta'>{{@model.reference}}
              ·
              {{@model.customerName}}{{@model.customerSuffix}}</span>
          </span>
          <span class='sts'>
            <Chip
              @appearance='plain'
              @tone={{ticketStatusTone @model.status}}
            >{{@model.status}}</Chip>
            <Chip
              @appearance='plain'
              @tone={{ticketPriorityTone @model.priority}}
            >{{@model.priority}}</Chip>
          </span>
        </header>

        <section class='stats' aria-label='Ticket numbers'>
          <div class='cell'><Stat
              @label='First response'
              @tone={{if this.firstResponse 'success' 'neutral'}}
              @value={{if this.firstResponse this.firstResponse.shortLabel '—'}}
              @roll={{false}}
            /></div>
          <div class='cell'><Stat
              @label='Resolution'
              @tone='info'
              @value={{if this.resolution this.resolution.shortLabel '—'}}
              @hint={{@model.slaDueLabel}}
              @roll={{false}}
            /></div>
          <div class='cell'><Stat
              @label='Messages'
              @tone='neutral'
              @value={{this.messages.length}}
              @hint='{{this.internalCount}} internal'
              @roll={{false}}
            /></div>
          <div class='cell'><Stat
              @label='Age'
              @tone='neutral'
              @value={{if @model.ageLabel @model.ageLabel '—'}}
              @roll={{false}}
            /></div>
        </section>

        <div class='body'>
          <div class='main'>
            <section class='blk'>
              <h2 class='sh'>Details</h2>
              <p class='txt'>{{@model.details}}</p>
            </section>
            <section class='blk'>
              <h2 class='sh'>Conversation</h2>
              <ul class='msgs'>
                {{#each this.messages as |m|}}
                  <li class='msg'>
                    <span class='lines'>
                      <span class='who'><b>{{m.author}}</b>
                        ·
                        {{m.authorRole}}
                        <span class='mono dim'>{{this.stamp
                            m.sentAt
                          }}</span></span>
                      <span class='tx'>{{m.body}}</span>
                    </span>
                    <Chip
                      @appearance='plain'
                      @tone={{this.visTone m}}
                    >{{this.visText m}}</Chip>
                  </li>
                {{/each}}
              </ul>
            </section>
            <section class='blk'>
              <h2 class='sh'>SLA timers</h2>
              <dl class='kv'>
                {{#each this.timers as |t|}}
                  <dt>{{t.kind}}</dt>
                  <dd><SlaTimerBadge
                      @facts={{t}}
                      @live={{false}}
                      @plain={{true}}
                    /></dd>
                {{/each}}
                <dt>Category</dt><dd>{{if
                    @model.categoryName
                    @model.categoryName
                    '—'
                  }}</dd>
              </dl>
            </section>
          </div>
          <aside class='side'>
            <section class='blk'>
              <h2 class='sh'>Linked</h2>
              <dl class='kv'>
                <dt>Customer</dt><dd>{{#if @model.customer}}<@fields.customer
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Assignee</dt><dd>{{#if @model.assignee}}<@fields.assignee
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Queue</dt><dd>{{#if @model.queue}}<@fields.queue
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Category</dt><dd>{{#if @model.category}}<@fields.category
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Commitment</dt><dd>{{#if
                    @model.slaPolicy
                  }}<@fields.slaPolicy
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Article</dt><dd>{{#if
                    @model.linkedArticles.length
                  }}<@fields.linkedArticles
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
              </dl>
            </section>
            <section class='blk'>
              <h2 class='sh'>Details</h2>
              <dl class='kv'>
                <dt>Priority</dt><dd>{{@model.priority}}</dd>
                <dt>Status</dt><dd>{{@model.status}}</dd>
                <dt>Channel</dt><dd>{{if
                    @model.channel
                    @model.channel
                    '—'
                  }}</dd>
                <dt>Type</dt><dd>{{if
                    @model.ticketType
                    @model.ticketType
                    '—'
                  }}</dd>
                <dt>Opened</dt><dd class='mono'>{{this.stamp
                    @model.openedAt
                  }}</dd>
                <dt>Resolution due</dt><dd class='mono'>{{if
                    @model.slaDueLabel
                    @model.slaDueLabel
                    '—'
                  }}</dd>
                <dt>Tags</dt><dd>{{if
                    @model.tagSummary
                    @model.tagSummary
                    '—'
                  }}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .tk {
          margin: 0;
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: 0.75rem;
        }
        .head {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem;
          flex-wrap: wrap;
        }
        .mark {
          display: grid;
          place-items: center;
          inline-size: 1.75rem;
          block-size: 1.75rem;
          border: 1px solid var(--border);
          font: 600 0.6875rem/1 var(--font-mono);
          flex: none;
        }
        .id {
          flex: 1 1 12rem;
          min-inline-size: 0;
          display: grid;
          gap: 0.125rem;
        }
        h1 {
          margin: 0;
          font-family: var(--font-sans);
          font-size: 0.75rem;
          font-weight: 700;
          text-transform: none;
          letter-spacing: normal;
        }
        .meta,
        .dim {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
        }
        .sts {
          display: flex;
          gap: 0.75rem;
        }
        .stats {
          --text-stat: 1.375rem;
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          border-block-start: 1px solid var(--border);
        }
        .cell {
          padding: 0.4375rem 0.625rem;
          min-inline-size: 0;
        }
        .cell + .cell {
          border-inline-start: 1px solid var(--border);
        }
        .body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
          border-block-start: 1px solid var(--border);
        }
        .side {
          border-inline-start: 1px solid var(--border);
          min-inline-size: 0;
        }
        .main {
          min-inline-size: 0;
        }
        .blk + .blk {
          border-block-start: 1px solid var(--border);
        }
        .sh {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          font-size: 0.75rem;
          font-weight: 700;
        }
        .txt {
          margin: 0;
          padding: 0 0.625rem 0.4375rem;
        }
        .msgs {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .msg {
          display: grid;
          grid-template-columns: minmax(0, 1fr) auto;
          align-items: center;
          gap: 0.5rem;
          padding: 0.3125rem 0.625rem;
          border-block-start: 1px solid var(--border);
        }
        .lines {
          display: grid;
          gap: 0.125rem;
          min-inline-size: 0;
        }
        .kv {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          margin: 0;
        }
        .kv > * {
          min-block-size: 1.75rem;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: 0.25rem;
          border-block-start: 1px solid var(--border);
          min-inline-size: 0;
          margin: 0;
        }
        dt {
          padding-inline-start: 0.625rem;
          font: 600 0.5625rem/1.3 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          padding-inline-end: 0.625rem;
        }
        @container (width <= 44rem) {
          .body {
            grid-template-columns: minmax(0, 1fr);
          }
          .side {
            border-inline-start: none;
            border-block-start: 1px solid var(--border);
          }
          .stats {
            grid-template-columns: repeat(2, minmax(0, 1fr));
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>#</span>
        <span class='ref'>{{@model.reference}}</span>
        <span class='subject'>{{@model.subject}}</span>
        <Chip
          @appearance='plain'
          @tone={{ticketStatusTone @model.status}}
        >{{@model.status}}</Chip>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.3125rem;
          max-inline-size: 100%;
          min-inline-size: 0;
          font-size: 0.75rem;
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1rem;
          block-size: 1rem;
          border: 1px solid var(--border);
          font: 600 0.5625rem/1 var(--font-mono);
          color: var(--muted-foreground);
        }
        .ref {
          flex: none;
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .subject {
          min-inline-size: 0;
          font-weight: 700;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    <template>
      <article class='emb'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>#</span>
          <span class='titles'>
            <b class='ell'>{{@model.subject}}</b>
            <span class='meta ell'>{{@model.reference}}
              ·
              {{@model.customerName}}{{@model.customerSuffix}}</span>
          </span>
        </header>
        <div class='chips'>
          <Chip
            @appearance='plain'
            @tone={{ticketStatusTone @model.status}}
          >{{@model.status}}</Chip>
          <Chip
            @appearance='plain'
            @tone={{ticketPriorityTone @model.priority}}
          >{{@model.priority}}</Chip>
        </div>
        <dl class='kv'>
          <div><dt>Priority</dt><dd>{{@model.priority}}</dd></div>
          <div><dt>Status</dt><dd>{{@model.status}}</dd></div>
          <div><dt>Channel</dt><dd>{{@model.channel}}</dd></div>
          <div><dt>Resolution due</dt><dd
              class='mono'
            >{{@model.slaDueLabel}}</dd></div>
          <div><dt>Assignee</dt><dd>{{@model.assigneeName}}</dd></div>
          <div><dt>Queue</dt><dd>{{@model.queueName}}</dd></div>
        </dl>
      </article>
      <style scoped>
        .emb {
          display: grid;
          gap: 0.375rem;
          padding: 0.4375rem 0.625rem;
          font-size: 0.75rem;
          color: var(--foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-inline-size: 0;
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1.25rem;
          block-size: 1.25rem;
          border: 1px solid var(--border);
          font: 600 0.625rem/1 var(--font-mono);
        }
        .titles {
          display: grid;
          min-inline-size: 0;
        }
        .ell {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .chips {
          display: flex;
          gap: 0.75rem;
        }
        .kv {
          margin: 0;
        }
        .kv > div {
          display: grid;
          grid-template-columns: 7rem minmax(0, 1fr);
          align-items: center;
          block-size: 1.75rem;
          border-block-start: 1px solid var(--border);
        }
        dt {
          font: 600 0.5625rem/1.3 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Priority', value: m?.priority || '—' },
        { key: 'Status', value: m?.status || '—' },
        { key: 'Assignee', value: m?.assigneeName || '—' },
        { key: 'Queue', value: m?.queueName || '—' },
        { key: 'Channel', value: m?.channel || '—' },
        { key: 'Resolution due', value: m?.slaDueLabel || '—' },
      ];
    }
    get stats() {
      let m = this.args.model;
      let msgs = (m?.messages ?? []).filter(Boolean).length;
      return [
        { key: 'Priority', value: m?.priority || '—' },
        { key: 'Status', value: m?.status || '—' },
        { key: 'Messages', value: String(msgs) },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}} @stats={{this.stats}}>
        <:default>
          <FitTile>
            <:avatar><Avatar
                @name='Ticket'
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.subject}}</:title>
            <:subtitle>{{@model.reference}}
              ·
              {{@model.customerName}}{{@model.customerSuffix}}</:subtitle>
            <:status>
              <Chip
                @appearance='plain'
                @tone={{ticketStatusTone @model.status}}
              >{{@model.status}}</Chip>
              <Chip
                @appearance='plain'
                @tone={{ticketPriorityTone @model.priority}}
              >{{@model.priority}}</Chip>
            </:status>
            <:fact>{{@model.slaDueLabel}}</:fact>
            <:relations>{{@model.assigneeName}}{{#if @model.queueName}}
                ·
                {{@model.queueName}}{{/if}}</:relations>
          </FitTile>
        </:default>
      </FittedExtras>
    </template>
  };
}
