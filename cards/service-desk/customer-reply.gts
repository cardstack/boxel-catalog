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
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { relativeStamp } from '@cardstack/catalog/fields/created-at/created-at';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';

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

class CustomerReplyEdit extends Component<typeof CustomerReply> {
  @tracked activeSection = 'message';

  sections = [
    { id: 'message', label: 'Message' },
    { id: 'provenance', label: 'Provenance' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.reply-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='reply-edit'>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "message") "focused"}}'
            data-sect='message'
          >
            <h3>Message</h3>
            <FieldContainer @label='Direction' @vertical={{true}}>
              <@fields.direction />
            </FieldContainer>
            <FieldContainer @label='Channel' @vertical={{true}}>
              <@fields.channel />
            </FieldContainer>
            <FieldContainer @label='Body' @vertical={{true}}>
              <@fields.body />
            </FieldContainer>
          </section>
          <section
            class='sect {{if (eq this.activeSection "provenance") "focused"}}'
            data-sect='provenance'
          >
            <h3>Provenance
              <span class='sect-hint'>outbound replies are attributed to their
                author</span></h3>
            <FieldContainer @label='From address (inbound)' @vertical={{true}}>
              <@fields.fromAddress />
            </FieldContainer>
            <FieldContainer @label='Sent at' @vertical={{true}}>
              <@fields.sentAt />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .reply-edit {
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

  static isolated = class Isolated extends Component<typeof this> {
    get sentLabel() {
      return relativeStamp(this.args.model.sentAt ?? undefined);
    }
    <template>
      <article class='reply-page'>
        <header class='reply-head'>
          <h1><@fields.title /></h1>
          <span class='reply-meta'>{{@model.channel}}
            ·
            {{this.sentLabel}}
            · on
            <@fields.case @format='atom' /></span>
        </header>
        <div class='reply-body'><@fields.body /></div>
      </article>
      <style scoped>
        .reply-page {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          background: var(--background, var(--boxel-light));
          color: var(--foreground, var(--boxel-dark));
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
        .reply-meta {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .reply-body {
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp);
          background: var(--card, var(--boxel-light));
          max-width: 70ch;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get sentLabel() {
      return relativeStamp(this.args.model.sentAt ?? undefined);
    }
    <template>
      <div class='reply {{if (eqDir @model.direction) "reply-out"}}'>
        <span class='reply-line'>
          <span class='reply-dir'>{{if
              (eqDir @model.direction)
              '↑ out'
              '↓ in'
            }}</span>
          <span class='reply-who'>{{if
              (eqDir @model.direction)
              @model.author.title
              @model.fromAddress
            }}</span>
          <span class='reply-when'>{{this.sentLabel}}
            ·
            {{@model.channel}}</span>
        </span>
        <div class='reply-excerpt'><@fields.body /></div>
      </div>
      <style scoped>
        .reply {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          width: 100%;
          min-width: 0;
        }
        .reply-out {
          border-left: 0.1875rem solid var(--primary, var(--boxel-highlight));
        }
        .reply-line {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
          font-size: var(--boxel-font-size-xs);
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          color: var(--muted-foreground, var(--boxel-450));
        }
        .reply-who {
          font-weight: 600;
          color: var(--foreground, var(--boxel-dark));
        }
        .reply-excerpt {
          font-size: var(--boxel-font-size-sm);
          max-height: 6.5rem;
          overflow: hidden;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='reply-atom'>{{@model.title}}</span>
      <style scoped>
        .reply-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='reply-fitted'>
        <MessageCircleIcon class='reply-icon' aria-hidden='true' />
        <div class='reply-fitted-body'>
          <span class='reply-fitted-title'>{{@model.title}}</span>
          <span class='reply-fitted-meta'>{{@model.channel}}</span>
          <div class='reply-fitted-body-excerpt'><@fields.body /></div>
        </div>
      </div>
      <style scoped>
        .reply-fitted {
          height: 100%;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .reply-icon {
          flex: none;
          width: 1.25rem;
          height: 1.25rem;
          color: var(--primary, var(--boxel-highlight));
        }
        .reply-fitted-body {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
        }
        .reply-fitted-title {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .reply-fitted-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .reply-fitted-body-excerpt {
          display: none;
        }
        @container fitted-card (height > 170px) {
          .reply-fitted-body-excerpt {
            display: block;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground, var(--boxel-450));
            overflow: hidden;
            max-height: 7rem;
            margin-top: var(--boxel-sp-4xs);
          }
        }
        @container fitted-card (height <= 80px) {
          .reply-fitted {
            align-items: center;
          }
          .reply-fitted-meta {
            display: none;
          }
        }
      </style>
    </template>
  };
  static edit = CustomerReplyEdit;
}

function eqDir(direction?: string | null) {
  return direction === 'outbound';
}

export default CustomerReply;
