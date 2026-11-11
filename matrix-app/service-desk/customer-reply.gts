import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import MarkdownField from '@cardstack/base/markdown';
import enumField from '@cardstack/base/enum';
import MessageCircleIcon from '@cardstack/boxel-icons/message-circle';
import { Case } from './case';
import { FitRows, TypeMark, lowercase } from './components/fit-rows';
import { Employee } from '../hr/employee';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Chip } from '@cardstack/pretui/components/chip';
import { Panel } from '@cardstack/pretui/components/panel';
import { Stat } from '@cardstack/pretui/components/stat';
import { FitTile } from '../shared/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';

export const REPLY_DIRECTIONS = ['inbound', 'outbound'] as const;

export const ReplyDirectionField = markDefinition(
  enumField(StringField, {
    displayName: 'Reply Direction',
    options: REPLY_DIRECTIONS as unknown as string[],
  }),
);

export const REPLY_CHANNELS = [
  'email',
  'portal',
  'phone-note',
  'chat-transcript',
] as const;

export const ReplyChannelField = markDefinition(
  enumField(StringField, {
    displayName: 'Reply Channel',
    options: REPLY_CHANNELS as unknown as string[],
  }),
);

const CHANNEL_LABELS: Record<string, string> = {
  email: 'Email',
  portal: 'Portal',
  'phone-note': 'Phone note',
  'chat-transcript': 'Chat transcript',
};

function stamp(
  value: Date | null | undefined,
  opts: Intl.DateTimeFormatOptions,
) {
  return value
    ? new Intl.DateTimeFormat('en-US', opts).format(new Date(value))
    : '';
}
const TIME = { hour: '2-digit', minute: '2-digit', hour12: false } as const;
const SHORT = { month: 'short', day: 'numeric', ...TIME } as const;
const LONG = {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  ...TIME,
} as const;
const DAY = { month: 'short', day: 'numeric', year: 'numeric' } as const;

/** First sentence of the message as a quote, for the fact line. */
function quote(body?: string | null) {
  let text = (body ?? '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  let end = text.search(/[.!?](\s|$)/);
  let first = end === -1 ? text : text.slice(0, end);
  return `“${first}…”`;
}

// Values set in the mono face: identifiers and timestamps.
const MONO_KEYS = new Set(['Sent', 'Case ID', 'Case']);
const isMono = (key: string) => MONO_KEYS.has(key);

/** The strings every SupportCustomerReply format shows, read once. */
function replyView(m?: Partial<CustomerReply>) {
  let out = m?.direction === 'outbound';
  let channel = CHANNEL_LABELS[m?.channel ?? ''] ?? m?.channel ?? '';
  let authorName = m?.author?.title as string | undefined;
  let sent = m?.sentAt ?? undefined;
  let who = out ? authorName : m?.fromAddress;
  let subline = [
    `${channel} ${out ? 'to' : 'from'} the customer`.trim(),
    stamp(sent, SHORT),
  ]
    .filter(Boolean)
    .join(' · ');
  let facts: KeyValueItem[] = [
    { key: 'Direction', value: out ? 'Outbound' : 'Inbound' },
    { key: 'Channel', value: channel || '—' },
    { key: 'Sent', value: stamp(sent, LONG) || '—' },
    { key: out ? 'Author' : 'From', value: who ?? '—' },
    { key: 'Case', value: m?.case?.caseId?.value ?? '—' },
  ];
  return {
    title: m?.title ?? 'Customer Reply',
    out,
    directionLabel: out ? 'Outbound' : 'Inbound',
    directionTone: (out ? 'info' : 'neutral') as PretuiToneArg,
    channel,
    subline,
    quote: quote(m?.body),
    facts,
    time: stamp(sent, TIME),
    day: stamp(sent, DAY),
    caseId: m?.case?.caseId?.value ?? '',
    // embedded rows: the facts, with the two links as atoms
    rows: [
      { key: 'Direction', value: out ? 'Outbound' : 'Inbound' },
      { key: 'Channel', value: channel || '—' },
      { key: 'Sent', value: stamp(sent, LONG) || '—' },
      { key: out ? 'Author' : 'From', value: who ?? '—' },
      { key: 'Case ID', value: m?.case?.caseId?.value ?? '—' },
      ...(m?.case ? [{ key: 'Case', value: '' }] : []),
    ] as KeyValueItem[],
    linked: [
      ...(m?.case ? [{ key: 'Case', value: '' }] : []),
      ...(m?.author ? [{ key: 'Author', value: '' }] : []),
    ] as KeyValueItem[],
    // fitted rows, highest priority first; a row the tile can't hold drops
    fitRows: [
      ...(channel ? [{ key: 'Channel', value: channel }] : []),
      ...(sent ? [{ key: 'Sent', value: stamp(sent, SHORT) }] : []),
      ...(m?.author
        ? [{ key: 'Author', value: '' }]
        : who
          ? [{ key: 'From', value: who }]
          : []),
      ...(m?.case ? [{ key: 'Case', value: '' }] : []),
      { key: 'Direction', value: out ? 'Outbound' : 'Inbound' },
      ...(m?.case?.caseId?.value
        ? [{ key: 'Case ID', value: m.case.caseId.value }]
        : []),
    ] as KeyValueItem[],
  };
}

/**
 * The RECORD of one customer communication — not the transport. No inbound
 * webhook or mail runtime exists on the platform, so replies are recorded by
 * agents (or imported); the record is what the clocks, the thread and the
 * auditor read.
 *
 * Clock interactions live in the commands, not here: the first OUTBOUND reply
 * satisfies the first-response timer; an INBOUND reply resumes a paused
 * resolution clock. Resolve Case refuses while no outbound reply exists —
 * you don't resolve silently.
 */
export class CustomerReply extends CardDef {
  static displayName = 'Customer Reply';
  static icon = MessageCircleIcon;

  @field case = linksTo(() => Case);
  /** Denormalised link id: consumers join on this instead of touching
      `case` (a lazy linksTo that would load mid-render). */
  @field caseRefId = contains(StringField, {
    computeVia: function (this: CustomerReply) {
      return this.case?.id;
    },
  });
  @field direction = contains(ReplyDirectionField);
  @field channel = contains(ReplyChannelField);
  @field body = contains(MarkdownField);
  @field author = linksTo(() => Employee, {
    description: 'The agent, for outbound. Inbound carries fromAddress.',
  });
  @field fromAddress = contains(StringField);
  @field sentAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: CustomerReply) {
      let dir = this.direction === 'inbound' ? '↓ in' : '↑ out';
      let who =
        this.direction === 'inbound'
          ? this.fromAddress
          : (this.author?.title as string | undefined);
      return `${dir} · ${who ?? 'unknown'}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return replyView(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <TypeMark @label='Re' />
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.title}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
        </header>
        {{#if this.v.quote}}<p class='emb-quote'>{{this.v.quote}}</p>{{/if}}
        <KeyValue
          class='emb-kv'
          @items={{this.v.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
        >
          <:value as |item|>
            {{#if (eq item.key 'Case')}}
              <span class='cell'><@fields.case
                  @format='atom'
                  @displayContainer={{false}}
                /></span>
            {{else}}
              <span class={{if (isMono item.key) 'mono'}}>{{item.value}}</span>
            {{/if}}
          </:value>
        </KeyValue>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: grid;
            align-content: start;
            background: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
            border-bottom: 1px solid var(--border);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .emb-sub,
          .emb-quote {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-quote {
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm) 0;
          }
          .emb-kv {
            padding: var(--boxel-sp-4xs) var(--boxel-sp-sm) var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .cell {
            display: flex;
            min-width: 0;
            max-width: 100%;
            overflow: hidden;
          }
          .mono {
            font-family: var(--font-mono);
            font-size: var(--boxel-font-size-xs);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get v() {
      return replyView(this.args.model);
    }
    <template>
      <span class='atom'>
        <TypeMark @label='Re' @size='sm' />
        <span class='atom-name'>{{this.v.title}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            color: var(--card-foreground);
          }
          .atom-name {
            min-width: 0;
            font-weight: 600;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return replyView(this.args.model);
    }
    get directionHint() {
      return this.v.out ? 'to the customer' : 'from the customer';
    }
    <template>
      <article class='iso'>
        <Panel>
          <div class='iso-head-row'>
            <TypeMark @label='Re' />
            <div class='iso-id'>
              <h1 class='iso-title'>{{this.v.title}}</h1>
              <p class='iso-sub'>{{this.v.subline}}</p>
            </div>
            <span class='iso-state'>
              <Chip
                @tone={{this.v.directionTone}}
                @appearance='plain'
              >{{lowercase this.v.directionLabel}}</Chip>
              {{#if this.v.channel}}<Chip @appearance='plain'>{{lowercase
                    this.v.channel
                  }}</Chip>{{/if}}
            </span>
          </div>
        </Panel>
        <Panel>
          <div class='iso-stats'>
            <Stat
              @label='Direction'
              @tone={{this.v.directionTone}}
              @value={{if this.v.out 'Out' 'In'}}
              @hint={{this.directionHint}}
              @roll={{false}}
            />
            <Stat
              @label='Sent'
              @value={{if this.v.time this.v.time '—'}}
              @hint={{this.v.day}}
              @roll={{false}}
            />
            <Stat
              @label='Channel'
              @value={{if this.v.channel this.v.channel '—'}}
              @hint={{this.v.caseId}}
              @roll={{false}}
            />
          </div>
        </Panel>
        <div class='iso-grid'>
          <div class='iso-col'>
            <Panel @title='Message' @variant='inspector'>
              <div class='iso-body'><@fields.body /></div>
            </Panel>
          </div>
          <div class='iso-col'>
            {{#if this.v.linked.length}}
              <Panel @title='Linked' @variant='inspector'>
                <KeyValue
                  @items={{this.v.linked}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                >
                  <:value as |item|>
                    {{#if (eq item.key 'Case')}}
                      <span class='cell'><@fields.case @format='atom' /></span>
                    {{else}}
                      <span class='cell'><@fields.author
                          @format='atom'
                        /></span>
                    {{/if}}
                  </:value>
                </KeyValue>
              </Panel>
            {{/if}}
            <Panel @title='Details' @variant='inspector'>
              <KeyValue
                @items={{this.v.facts}}
                @labelStyle='eyebrow'
                @divided={{true}}
              >
                <:value as |item|>
                  <span
                    class={{if (isMono item.key) 'mono'}}
                  >{{item.value}}</span>
                </:value>
              </KeyValue>
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            display: grid;
            align-content: start;
            gap: var(--boxel-sp-xs);
            min-height: 100%;
            padding: var(--boxel-sp-xs);
            background: var(--muted);
            color: var(--card-foreground);
            font-size: var(--boxel-font-size-sm);
          }
          .iso-head-row {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .iso-id {
            min-width: 0;
          }
          .iso-title {
            margin: 0;
            font-family: var(--font-sans);
            font-size: var(--boxel-font-size);
            font-weight: 700;
            line-height: 1.3;
          }
          .iso-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .iso-state {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          }
          .iso-stats > * {
            padding-inline: var(--boxel-sp-sm);
          }
          .iso-stats > * + * {
            border-inline-start: 1px solid var(--border);
          }
          .iso-stats > :first-child {
            padding-inline-start: 0;
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp-xs);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .iso-body {
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .cell {
            display: flex;
            min-width: 0;
            max-width: 100%;
            overflow: hidden;
          }
          .mono {
            font-family: var(--font-mono);
            font-size: var(--boxel-font-size-xs);
          }
          @container (width < 40rem) {
            .iso-head-row {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-state {
              grid-column: 1 / -1;
            }
            .iso-grid {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return replyView(this.args.model);
    }
    <template>
      <FitRows @items={{this.v.fitRows}}>
        <:tile>
          <FitTile>
            <:avatar><TypeMark @label='Re' /></:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.title}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              <Chip
                @tone={{this.v.directionTone}}
                @appearance='plain'
              >{{lowercase this.v.directionLabel}}</Chip>
            </:status>
          </FitTile>
        </:tile>
        <:row as |item|>
          {{#if (eq item.key 'Author')}}
            <@fields.author @format='atom' @displayContainer={{false}} />
          {{else if (eq item.key 'Case')}}
            <@fields.case @format='atom' @displayContainer={{false}} />
          {{else}}
            <span class={{if (isMono item.key) 'mono'}}>{{item.value}}</span>
          {{/if}}
        </:row>
      </FitRows>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .mono {
            font-family: var(--font-mono);
          }
        }
      </style>
    </template>
  };
}
