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
import { Employee } from '../hr/employee';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Chip } from '../../ui-component/components/chip';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { FittedExtras, type FittedStat } from '../procurement/vendor';

export const REPLY_DIRECTIONS = ['inbound', 'outbound'] as const;

export const ReplyDirectionField = enumField(StringField, {
  displayName: 'Reply Direction',
  options: REPLY_DIRECTIONS as unknown as string[],
});

export const REPLY_CHANNELS = [
  'email',
  'portal',
  'phone-note',
  'chat-transcript',
] as const;

export const ReplyChannelField = enumField(StringField, {
  displayName: 'Reply Channel',
  options: REPLY_CHANNELS as unknown as string[],
});

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
    directionTone: (out ? 'primary' : 'neutral') as PretuiToneArg,
    channel,
    subline,
    quote: quote(m?.body),
    facts,
    time: stamp(sent, TIME),
    day: stamp(sent, DAY),
    hasAuthor: Boolean(m?.author),
    hasCase: Boolean(m?.case),
    relations: [...(m?.case ? ['Case'] : []), ...(m?.author ? ['Author'] : [])],
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
          <span class='mark' aria-hidden='true'>Re</span>
          <div class='emb-id'>
            <h3 class='emb-title'>{{this.v.title}}</h3>
            <p class='emb-sub'>{{this.v.subline}}</p>
          </div>
          <span class='emb-chips'>
            <Chip
              @tone={{this.v.directionTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.directionLabel}}</Chip>
            {{#if this.v.channel}}<Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.channel}}</Chip>{{/if}}
          </span>
        </header>
        {{#if this.v.quote}}<p class='emb-quote'>{{this.v.quote}}</p>{{/if}}
        <KeyValue class='emb-facts' @items={{this.v.facts}} @layout='stacked' />
        <div class='emb-rels'>
          {{#if this.v.hasCase}}<span class='emb-rel'><span
                class='emb-rel-k'
              >Case</span><@fields.case
                @format='atom'
                @displayContainer={{false}}
              /></span>{{/if}}
          {{#if this.v.hasAuthor}}<span class='emb-rel'><span
                class='emb-rel-k'
              >Author</span><@fields.author
                @format='atom'
                @displayContainer={{false}}
              /></span>{{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            container-type: inline-size;
            display: grid;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
          }
          .emb-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .emb-id {
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .emb-sub,
          .emb-quote {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-facts {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
            grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            font-weight: 600;
          }
          .emb-rel-k {
            font-weight: 400;
            color: var(--muted-foreground);
          }
          @container (max-width: 25rem) {
            .emb-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .emb-chips {
              grid-column: 1 / -1;
            }
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
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
        <span class='atom-mark' aria-hidden='true'>Re</span>
        <span class='atom-name'>{{this.v.title}}</span>
        {{#if this.v.channel}}<Chip
            @tone='neutral'
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{this.v.channel}}</Chip>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            font-size: var(--boxel-font-size-sm);
          }
          .atom-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .atom-name {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
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
        <header class='iso-head'>
          <span class='iso-mark' aria-hidden='true'>Re</span>
          <div class='iso-id'>
            <h1 class='iso-title'>{{this.v.title}}</h1>
            <p class='iso-sub'>{{this.v.subline}}</p>
          </div>
          <span class='iso-chips'>
            <Chip
              @tone={{this.v.directionTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{this.v.directionLabel}}</Chip>
            {{#if this.v.channel}}<Chip
                @tone='neutral'
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.channel}}</Chip>{{/if}}
          </span>
        </header>
        <div class='iso-stats'>
          <Panel><Stat
              @label='Direction'
              @value={{if this.v.out 'Out' 'In'}}
              @hint={{this.directionHint}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Sent'
              @value={{if this.v.time this.v.time '—'}}
              @hint={{this.v.day}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Channel'
              @value={{if this.v.channel this.v.channel '—'}}
              @roll={{false}}
            /></Panel>
        </div>
        <div class='iso-grid'>
          <div class='iso-col'>
            <Panel @title='Message'>
              <div class='iso-body'><@fields.body /></div>
            </Panel>
          </div>
          <div class='iso-col'>
            <Panel @title='Linked'>
              <div class='iso-links'>
                {{#if this.v.hasCase}}<span class='iso-link'><span
                      class='iso-link-k'
                    >Case</span><span class='iso-link-v'><@fields.case
                        @format='atom'
                        @displayContainer={{false}}
                      /></span></span>{{/if}}
                {{#if this.v.hasAuthor}}<span class='iso-link'><span
                      class='iso-link-k'
                    >Author</span><span class='iso-link-v'><@fields.author
                        @format='atom'
                        @displayContainer={{false}}
                      /></span></span>{{/if}}
              </div>
            </Panel>
            <Panel @title='Details'>
              <KeyValue @items={{this.v.facts}} @rows='ruled' />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .iso {
            container-type: inline-size;
            min-block-size: 100%;
            background: var(--canvas);
            display: grid;
            gap: var(--boxel-sp);
            padding: var(--boxel-sp-lg);
          }
          .iso-head {
            display: grid;
            grid-template-columns: auto minmax(0, 1fr) auto;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .iso-title {
            margin: 0;
            font-size: 1.5rem;
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
          }
          .iso-sub {
            margin: 0;
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: inline-flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .iso-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-grid {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
            gap: var(--boxel-sp);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp);
            min-width: 0;
          }
          .iso-links {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .iso-link {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            padding-bottom: var(--boxel-sp-xs);
            border-bottom: 1px solid var(--border);
          }
          .iso-link-k {
            color: var(--muted-foreground);
          }
          .iso-link-v {
            display: inline-flex;
            align-items: center;
            min-width: 0;
            font-weight: 600;
          }
          .iso-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          @container (max-width: 40rem) {
            .iso-head {
              grid-template-columns: auto minmax(0, 1fr);
            }
            .iso-chips {
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
    get stats(): FittedStat[] {
      return [
        { key: 'Direction', value: this.v.out ? 'Out' : 'In' },
        { key: 'Sent', value: this.v.time || '—' },
        { key: 'Channel', value: this.v.channel || '—' },
      ];
    }

    <template>
      <FittedExtras
        @facts={{this.v.facts}}
        @stats={{this.stats}}
        @relations={{this.v.relations}}
      >
        <:default>
          <FitTile>
            <:avatar>
              {{! the record's type mark, not a person: a square, not an Avatar }}
              <span class='fit-mark' aria-hidden='true'>Re</span>
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{this.v.title}}</span></:title>
            <:subtitle>{{this.v.subline}}</:subtitle>
            <:status>
              <Chip
                @tone={{this.v.directionTone}}
                @appearance='soft'
                @shape='pill'
                @dot={{false}}
              >{{this.v.directionLabel}}</Chip>
              {{#if this.v.channel}}<Chip
                  @tone='neutral'
                  @appearance='soft'
                  @shape='pill'
                  @dot={{false}}
                >{{this.v.channel}}</Chip>{{/if}}
            </:status>
            <:fact>{{this.v.quote}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          <span class='fit-rel'>
            {{#if (eq label 'Case')}}
              <@fields.case @format='atom' @displayContainer={{false}} />
            {{else}}
              <@fields.author @format='atom' @displayContainer={{false}} />
            {{/if}}
          </span>
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-rel {
            display: block;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-weight: 600;
          }
          .fit-mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

export default CustomerReply;
