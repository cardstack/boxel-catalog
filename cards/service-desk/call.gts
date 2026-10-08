import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';
import PhoneNumberField from '@cardstack/base/phone-number';
import PhoneIcon from '@cardstack/boxel-icons/phone';
import PhoneIncomingIcon from '@cardstack/boxel-icons/phone-incoming';
import PhoneOutgoingIcon from '@cardstack/boxel-icons/phone-outgoing';
import UsersIcon from '@cardstack/boxel-icons/users';
import NoteIcon from '@cardstack/boxel-icons/note';
import LinkIcon from '@cardstack/boxel-icons/link';
import { eq } from '@cardstack/boxel-ui/helpers';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import enumField from '@cardstack/base/enum';

export const CallDirectionField = enumField(StringField, {
  options: [
    { value: 'inbound', label: 'Inbound' },
    { value: 'outbound', label: 'Outbound' },
  ],
});

/**
 * How the call ended. `connected` is one of six, and that is the point: a
 * call that did not connect is still a call, and a system that only records
 * the connected ones loses the attempt history that tells you someone has
 * been unreachable for two weeks.
 */
export const CallOutcomeField = enumField(StringField, {
  options: [
    { value: 'connected', label: 'Connected' },
    { value: 'no-answer', label: 'No answer' },
    { value: 'voicemail', label: 'Left voicemail' },
    { value: 'busy', label: 'Busy' },
    { value: 'wrong-number', label: 'Wrong number' },
    { value: 'failed', label: 'Failed to connect' },
  ],
});

/**
 * One phone call, connected or not.
 *
 * ### An attempt is a record
 *
 * The most common modelling mistake here is writing a row only when someone
 * picks up. Then "we have called Dana four times and never reached her" is
 * unanswerable, and the next person calls a fifth time without knowing.
 *
 * So `outcome` has six values and only one of them is `connected`. Everything
 * downstream — follow-up rules, unreachable flags, call counts — reads the
 * outcome rather than assuming a row means a conversation.
 *
 * ### Duration only means something when connected
 *
 * `durationSeconds` on a `no-answer` is ring time, which is a different
 * quantity wearing the same name. `effectiveDuration` returns undefined
 * unless the call connected, so an average-call-length figure cannot silently
 * average in fifteen seconds of ringing.
 *
 * ### `phoneNumber` is stored as dialled, not as displayed
 *
 * E.164, from `NormalizePhoneCommand`. A call record whose number was stored
 * as a human typed it cannot be matched against the contact it belongs to
 * later, which is how call histories end up split across three spellings of
 * the same number.
 *
 * ### Notes are markdown and separate from the outcome
 *
 * The outcome is machine-readable; the note is what the human wants to say.
 * Encoding "left message about invoice" into an enum value loses it, and
 * putting the outcome only in prose makes it unqueryable.
 */
// m:ss from whole seconds; empty for a missing or negative duration.
function formatDuration(seconds?: number | null): string {
  if (seconds == null || !Number.isFinite(seconds) || seconds < 0) {
    return '';
  }
  let total = Math.floor(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

export class Call extends CardDef {
  static displayName = 'Call';
  static icon = PhoneIcon;

  @field direction = contains(CallDirectionField);
  @field outcome = contains(CallOutcomeField);

  // base/phone-number, not a StringField: it carries the `phone` serializer
  // and the platform's own edit UI, so a call record and a contact card
  // store and validate a number the same way. The value itself is E.164 as
  // dialled — see NormalizePhoneCommand.
  @field phoneNumber = contains(PhoneNumberField, {
    description:
      'E.164, as dialled — not as displayed. See NormalizePhoneCommand.',
  });
  @field participantNames = containsMany(StringField);

  @field startedAt = contains(DateTimeField);
  @field durationSeconds = contains(NumberField, {
    description:
      'Raw duration. On a call that never connected this is ring time — use effectiveDuration.',
  });

  @field subject = contains(StringField);
  @field notes = contains(MarkdownField);

  // What the call was about. A link, so the call follows a rename and opening
  // it lands on the real record.
  @field regarding = linksTo(() => CardDef);

  @field followUpAt = contains(DateTimeField);

  @field wasConnected = contains(BooleanField, {
    computeVia: function (this: Call) {
      return this.outcome === 'connected';
    },
  });

  // Undefined unless connected, so an average cannot silently include ring
  // time from calls nobody answered.
  @field effectiveDuration = contains(NumberField, {
    computeVia: function (this: Call) {
      return this.outcome === 'connected' ? this.durationSeconds : undefined;
    },
  });

  @field needsFollowUp = contains(BooleanField, {
    computeVia: function (this: Call) {
      return Boolean(this.followUpAt);
    },
  });

  // m:ss, and only for a connected call — a duration label on a no-answer
  // reads as a conversation that did not happen.
  @field durationLabel = contains(StringField, {
    computeVia: function (this: Call) {
      return formatDuration(this.effectiveDuration);
    },
  });

  // A single call record, not a layout surface — the ~800px cap is the right
  // measure for it, so prefersWideFormat stays at its default false.

  static isolated = class Isolated extends Component<typeof this> {
    // The question this card exists to answer: what came of this call, and
    // what do I owe next. Not "how long was it" — that is supporting detail.
    glance = [
      { key: 'When', value: 'startedAt' },
      { key: 'Number', value: 'phoneNumber' },
      { key: 'Follow-up', value: 'followUpAt' },
    ];

    get answer(): string {
      if (this.args.model.wasConnected) {
        return this.args.model.durationLabel || 'Connected';
      }
      let o = this.args.model.outcome;
      return o ? o.replace(/-/g, ' ') : 'No outcome recorded';
    }

    get answerCaption(): string {
      if (this.args.model.wasConnected) {
        return 'connected';
      }
      return 'never connected — nothing was said';
    }

    <template>
      <article class='card {{@model.outcome}}'>
        <header class='hero'>
          <span class='rail' aria-hidden='true'></span>
          <div class='hero-body'>
            <p class='eyebrow'>
              {{#if (eq @model.direction 'inbound')}}
                <PhoneIncomingIcon width='14' height='14' aria-hidden='true' />
                Inbound call
              {{else}}
                <PhoneOutgoingIcon width='14' height='14' aria-hidden='true' />
                Outbound call
              {{/if}}
            </p>
            <h1 class='title'><@fields.cardTitle /></h1>
            {{! The answer, as the one dominant element on the page. }}
            <p class='answer'>{{this.answer}}</p>
            <p class='answer-cap'>{{this.answerCaption}}</p>
          </div>
        </header>

        <KeyValue
          class='glance'
          @items={{this.glance}}
          @layout='inline'
          @labelStyle='eyebrow'
          aria-label='At a glance'
        >
          <:value as |item|>
            {{#if (eq item.key 'When')}}
              <@fields.startedAt />
            {{else if (eq item.key 'Number')}}
              {{! E.164 is read aloud and typed into other systems, so it is
                never ellipsised. }}
              <span class='num'><@fields.phoneNumber /></span>
            {{else if @model.needsFollowUp}}
              <@fields.followUpAt />
            {{else}}
              <span class='none'>none booked</span>
            {{/if}}
          </:value>
        </KeyValue>

        {{! Three different shapes below, on purpose: prose, a list, a linked
          card. Three label/value blocks would be the schema dump. }}
        <section class='sec' aria-label='Notes'>
          <h2><NoteIcon width='16' height='16' aria-hidden='true' /> Notes</h2>
          {{#if @model.notes}}
            <div class='prose'><@fields.notes /></div>
          {{else}}
            <EmptyState
              @title='Nothing was written down for this call.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </section>

        <section class='sec' aria-label='Participants'>
          <h2><UsersIcon width='16' height='16' aria-hidden='true' />
            Participants</h2>
          {{#if @model.participantNames.length}}
            <ul class='people'>
              {{#each @model.participantNames as |n|}}
                <li>{{n}}</li>
              {{/each}}
            </ul>
          {{else}}
            <EmptyState
              @title='No participants recorded.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </section>

        {{#if @model.regarding}}
          <section class='sec' aria-label='Regarding'>
            <h2><LinkIcon width='16' height='16' aria-hidden='true' />
              Regarding</h2>
            <@fields.regarding @displayContainer={{false}} />
          </section>
        {{/if}}
      </article>

      <style scoped>
        /* Rule 1: an isolated card gets no host container, so it declares its
           own. Without this every @container rule below is dead CSS.
           inline-size, not size — the card scrolls vertically. */
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
          background: var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);

          /* One panel primitive. Tint may differ per block; padding and
             radius may not — that is what keeps blocks registered. */
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          --panel-pad: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          --panel-radius: var(--radius);
          /* The family's status hue, set once and diluted at each use. */
          --tone: var(--muted-foreground);
        }
        .card.connected {
          --tone: var(--success);
        }
        .card.wrong-number,
        .card.failed {
          --tone: var(--destructive);
        }
        .card.voicemail {
          --tone: var(--primary);
        }

        /* ── Hero ──────────────────────────────────────────────────────── */
        .hero {
          display: flex;
          gap: var(--boxel-sp);
          padding: var(--panel-pad);
          border-radius: var(--panel-radius);
          background: color-mix(in oklch, var(--tone) 6%, transparent);
        }
        /* The family signature: a status spine that reads before any text. */
        .rail {
          flex: none;
          width: 0.25rem;
          border-radius: 2px;
          background: var(--tone);
        }
        .hero-body {
          min-width: 0;
        }
        .eyebrow {
          display: flex;
          align-items: center;
          gap: 0.3125rem;
          margin: 0;
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: var(--boxel-lsp-lg);
          color: var(--muted-foreground);
        }
        .title {
          margin: var(--boxel-sp-xxs) 0 0;
          font-size: 1.375rem;
          font-weight: 600;
          line-height: 1.25;
          letter-spacing: -0.01em;
        }
        /* The dominant element: 3.25x the body, so the type scale has a real
           top and the reader's eye lands on the answer, not the title. */
        .answer {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: 2.875rem;
          font-weight: 700;
          line-height: 1.05;
          letter-spacing: -0.03em;
          font-variant-numeric: tabular-nums;
          text-transform: capitalize;
          color: var(--tone);
        }
        .answer-cap {
          margin: 2px 0 0;
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }

        /* ── At a glance ───────────────────────────────────────────────── */
        .glance {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-radius: var(--panel-radius);
          background: var(--panel-bg);
          font-variant-numeric: tabular-nums;
        }
        .num {
          font-family: var(--font-mono);
          white-space: nowrap;
        }
        .none {
          color: var(--muted-foreground);
        }

        /* ── Detail sections ───────────────────────────────────────────── */
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
          color: var(--muted-foreground);
        }
        .sec h2 svg {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
        }
        .prose {
          max-width: 68ch;
          font-size: 0.9375rem;
          line-height: 1.55;
        }
        .people {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xxs);
        }
        .people li {
          padding: 0.1875rem 0.625rem;
          border-radius: 999px;
          background: color-mix(in oklch, var(--foreground) 6%, transparent);
          font-size: 0.875rem;
        }

        /* ── Container queries — live because .card declares the container */
        @container card (width < 560px) {
          .answer {
            font-size: 2.25rem;
          }
        }
        @container card (width < 400px) {
          .title {
            font-size: 1.125rem;
          }
          .answer {
            font-size: 1.875rem;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit {{@model.outcome}}'>
        <div class='r-head'>
          <span class='glyph' aria-hidden='true'>{{if
              (eq @model.direction 'inbound')
              '↓'
              '↑'
            }}</span>
          <h3 class='title'>{{if
              @model.subject
              @model.subject
              @model.phoneNumber
            }}</h3>
        </div>
        <div class='r-body'>
          {{#if @model.notes}}
            <p class='note'>{{@model.notes}}</p>
          {{/if}}
        </div>
        <div class='r-meta'>
          {{! Connected calls show their length; the rest show what came of
            them. One slot, one fact — never both, and never a duration on a
            call nobody answered. }}
          {{#if @model.wasConnected}}
            <span class='fact'>{{@model.durationLabel}}</span>
          {{else}}
            <span class='fact out'>{{@model.outcome}}</span>
          {{/if}}
          {{#if @model.needsFollowUp}}
            <span class='flag'>follow up</span>
          {{/if}}
        </div>
      </article>

      <style scoped>
        .fit {
          --type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb), 10cqb),
            1rem
          );
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
          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .r-head {
          grid-area: head;
          display: flex;
          align-items: baseline;
          gap: 0.3125rem;
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
          gap: 0.3125rem;
          min-height: 0;
          overflow: hidden;
          flex-shrink: 0;
        }

        /* The anchor: no image field on a call, so the title carries it —
           decisively bold and 1.56x the body, per the typographic-anchor
           rule. The arrow is a quiet directional mark, never a competitor. */
        .title {
          flex: 1;
          min-width: 0;
          margin: 0;
          font-size: calc(var(--type-base) * pow(var(--type-ratio), 1));
          font-weight: 700;
          line-height: 1.2;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
          overflow-wrap: anywhere;
        }
        .glyph {
          flex: none;
          font-size: var(--type-base);
          line-height: 1.2;
          color: var(--muted-foreground);
        }
        .note {
          margin: 0;
          font-size: var(--type-base);
          line-height: 1.25;
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 3;
          overflow: hidden;
          overflow-wrap: anywhere;
        }
        /* Data is all-or-nothing: the duration and the outcome are never
           ellipsised, they are hidden whole at quanta with no room. */
        .fact {
          flex: none;
          font-size: var(--type-base);
          line-height: 1.25;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .fit.wrong-number .fact.out,
        .fit.failed .fact.out {
          color: var(--destructive-ink);
          font-weight: 600;
        }
        .flag {
          flex: none;
          font-size: var(--type-base);
          line-height: 1.25;
          white-space: nowrap;
          color: color-mix(in oklch, var(--primary) 45%, var(--foreground));
        }

        /* ── height quanta ──────────────────────────────────────────────
           Rows are hidden whole; nothing is ever shrunk into a clip. */

        /* Badge (~2.5rem): the title is the only survivor. */
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
        /* Strip: title + the one fact, no notes. */
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
        /* Tile: notes get one line. */
        @container fitted-card (80px < height <= 130px) {
          .note {
            -webkit-line-clamp: 1;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }

        /* Narrow: the follow-up flag goes before the fact does — the fact is
           data, the flag is a hint. */
        @container fitted-card (width <= 180px) {
          .flag {
            display: none;
          }
        }
        /* Very narrow badge: even the arrow competes for the title's row. */
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
      <article class='call {{@model.outcome}}'>
        <div class='row'>
          <span class='dir'>{{if
              (eq @model.direction 'inbound')
              '↓'
              '↑'
            }}</span>
          <span class='who'>{{if
              @model.subject
              @model.subject
              @model.phoneNumber
            }}</span>
          {{#if @model.durationLabel}}
            <span class='dur'>{{@model.durationLabel}}</span>
          {{else}}
            <span class='out'>{{@model.outcome}}</span>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .call {
          padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
          color: var(--foreground);
        }
        .row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xxs);
          font: var(--boxel-font-sm);
        }
        .dir {
          flex: none;
          color: var(--muted-foreground);
        }
        .who {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .dur {
          flex: none;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        /* An unconnected call shows its outcome where a connected one shows
           its length — the slot means "what came of this", not "how long". */
        .out {
          flex: none;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .call.wrong-number .out,
        .call.failed .out {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };
}

export default Call;
