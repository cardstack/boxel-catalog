import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import MessagesSquareIcon from '@cardstack/boxel-icons/messages-square';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { RelativeTime } from '@cardstack/pretui/components/relative-time';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';

/** One message in a thread. Author is any PersonBase — an Employee or a Learner. */
export class PostField extends FieldDef {
  static displayName = 'Post';
  @field author = linksTo(() => PersonBase);
  @field body = contains(MarkdownField);
  @field postedAt = contains(DateTimeField);

  @field authorName = contains(StringField, {
    computeVia: function (this: PostField) {
      return this.author?.name ?? 'Unknown';
    },
  });
  @field authorInitials = contains(StringField, {
    computeVia: function (this: PostField) {
      return this.author?.initials ?? '?';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='post'>
        <span class='ini' aria-hidden='true'>{{@model.authorInitials}}</span>
        <div class='post-body'>
          <div class='post-head'>
            <span class='who'>{{@model.authorName}}</span>
            {{#if @model.postedAt}}
              <RelativeTime
                class='when'
                @date={{@model.postedAt}}
                @format='short'
              />
            {{/if}}
          </div>
          <div class='text'><@fields.body /></div>
        </div>
      </div>
      <style scoped>
        .post {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp-xs);
          align-items: start;
        }
        .ini {
          width: 1.75rem;
          height: 1.75rem;
          display: grid;
          place-items: center;
          border-radius: 50%;
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .post-head {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
        }
        .who {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
        .when {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .text {
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
        }
      </style>
    </template>
  };
}

/**
 * The Structures-layer **Thread**: an ordered conversation about one card.
 * Domain-neutral — `about` is any CardDef (here a Cohort; elsewhere a ticket,
 * a contract). Posts are contained because a post has no life outside its
 * thread; authors are linked because people do. Post to Thread is the single
 * writer, so `lastActivityAt` can be derived rather than stored.
 */
export class Thread extends CardDef {
  static displayName = 'Thread';
  static icon = MessagesSquareIcon;

  @field title = contains(StringField);
  @field about = linksTo(() => CardDef);
  @field pinned = contains(BooleanField);
  @field closed = contains(BooleanField);
  @field posts = containsMany(PostField);

  @field postCount = contains(NumberField, {
    computeVia: function (this: Thread) {
      return (this.posts ?? []).length;
    },
  });
  @field lastActivityAt = contains(DateTimeField, {
    computeVia: function (this: Thread): Date | undefined {
      return lastPostedAt(this);
    },
  });
  @field lastAuthorName = contains(StringField, {
    computeVia: function (this: Thread) {
      let posts = this.posts ?? [];
      return posts.length ? (posts[posts.length - 1] as any).authorName : '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Thread) {
      return this.title?.trim() || 'Untitled thread';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='thread'>
        <header class='hero'>
          <div>
            <span class='eyebrow'>
              {{#if @model.pinned}}<span class='pin'>Pinned</span>{{/if}}
              {{#if @model.closed}}<span class='pin closed'>Closed</span>{{/if}}
              {{@model.postCount}}
              {{if (isOne @model.postCount) 'post' 'posts'}}
              {{#if @model.lastActivityAt}}
                · last
                <RelativeTime
                  @date={{@model.lastActivityAt}}
                  @format='short'
                />{{/if}}
            </span>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.about}}
              <div class='about'>About <@fields.about @format='atom' /></div>
            {{/if}}
          </div>
        </header>
        <section class='posts'>
          {{#each @fields.posts as |Post|}}
            <div class='post-wrap'><Post /></div>
          {{else}}
            <EmptyState
              @title='No posts yet'
              @message='The first post sets the tone.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/each}}
        </section>
      </article>
      <style scoped>
        .thread {
          max-width: 46rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .eyebrow {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          align-items: center;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .pin {
          padding: 1px var(--boxel-sp-xs);
          border-radius: 999px;
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          color: color-mix(
            in oklab,
            var(--primary) 45%,
            var(--card-foreground)
          );
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .pin.closed {
          background: var(--muted);
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15 var(--font-heading);
        }
        .about {
          margin-top: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .posts {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .post-wrap {
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='glyph' aria-hidden='true'>{{if
            @model.pinned
            '📌'
            '💬'
          }}</span>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{#if
              @model.lastAuthorName
            }}{{@model.lastAuthorName}} · {{/if}}{{#if
              @model.lastActivityAt
            }}<RelativeTime
                @date={{@model.lastActivityAt}}
                @format='short'
              />{{/if}}</span>
        </div>
        <span class='count'>{{@model.postCount}}</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .glyph {
          font-size: var(--boxel-font-size-sm);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .count {
          min-width: 1.5rem;
          text-align: center;
          padding: 1px var(--boxel-sp-4xs);
          border-radius: 999px;
          background: var(--muted);
          font-size: var(--boxel-font-size-xs);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>💬 {{@model.cardTitle}} ({{@model.postCount}})</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <span class='badge'>{{@model.postCount}}</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.cardTitle}}</h3>
            <span class='fit-eb'>{{if
                @model.lastAuthorName
                @model.lastAuthorName
                'No posts'
              }}{{#if @model.lastActivityAt}}
                ·
                <RelativeTime
                  @date={{@model.lastActivityAt}}
                  @format='short'
                />{{/if}}</span>
          </div>
        </div>
        {{#if @model.posts.length}}
          <p class='fit-last'>{{lastBody @model}}</p>
        {{/if}}
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .badge {
          flex: none;
          min-width: 2rem;
          height: 2rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: color-mix(in oklab, var(--primary) 14%, var(--card));
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .fit-head {
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fit-last {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 150px) {
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-last {
            display: -webkit-box;
            -webkit-line-clamp: 4;
            -webkit-box-orient: vertical;
            overflow: hidden;
          }
        }
      </style>
    </template>
  };
}

export function lastPostedAt(
  t: Partial<Thread> | null | undefined,
): Date | undefined {
  let posts = t?.posts ?? [];
  let dates = posts
    .map((p: any) => (p?.postedAt ? new Date(p.postedAt).getTime() : 0))
    .filter((n: number) => n > 0);
  return dates.length ? new Date(Math.max(...dates)) : undefined;
}

function lastBody(t: Partial<Thread> | null | undefined): string {
  let posts = t?.posts ?? [];
  let last = posts[posts.length - 1] as any;
  return (last?.body ?? '').replace(/[#*_>`]/g, '').slice(0, 200);
}

/**
 * A short "5m ago" / "3d ago" stamp, for callers that need the text rather
 * than Pret UI's RelativeTime component.
 */
export function fmtWhen(d: Date | string | null | undefined): string {
  if (!d) return '';
  let date = new Date(d);
  let diff = Date.now() - date.getTime();
  if (diff < 3600_000) return `${Math.max(1, Math.round(diff / 60_000))}m ago`;
  if (diff < 86_400_000) return `${Math.round(diff / 3600_000)}h ago`;
  if (diff < 7 * 86_400_000) return `${Math.round(diff / 86_400_000)}d ago`;
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function isOne(n?: number | null) {
  return n === 1;
}

export default Thread;
