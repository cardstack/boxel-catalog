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
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import type { TemplateOnlyComponent } from '@ember/component/template-only';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import { PersonBase } from '../people/person-base';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import {
  RecBlock,
  RecBody,
  RecCard,
  RecHead,
  RecLine,
  RecRow,
  RecStats,
} from './components/record';
import { IsoFrame } from '../shared/compact-sheet';

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
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead
            @mark='Th'
            @title={{@model.cardTitle}}
            @sub={{threadSub @model}}
          >
            <:status><ThreadStatus @model={{@model}} /></:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='Posts'
              @tone='neutral'
              @value={{postsCount @model}}
              @hint={{peopleHint @model}}
              @roll={{false}}
            />
            <Stat
              @label='Last activity'
              @tone='neutral'
              @value={{shortDate @model.lastActivityAt}}
              @hint={{@model.lastAuthorName}}
              @roll={{false}}
            />
            <Stat
              @label='State'
              @tone='neutral'
              @value={{if @model.closed 'Closed' 'Open'}}
              @hint={{if @model.pinned 'pinned' ''}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
              <RecBlock @title='Posts'>
                {{#each @model.posts as |post|}}
                  <RecLine><span class='post'><strong>{{post.authorName}}
                        ·
                        {{shortDate post.postedAt}}</strong><span
                        class='body'
                      >{{plain post.body}}</span></span></RecLine>
                {{else}}
                  <EmptyState
                    @title='No posts yet'
                    @message='The first post sets the tone.'
                    @texture={{false}}
                    style={{COMPACT_EMPTY_STYLE}}
                  />
                {{/each}}
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Linked'>
                <RecRow @label='About'>{{#if @model.about}}<@fields.about
                      @format='atom'
                    />{{else}}—{{/if}}</RecRow>
              </RecBlock>
              <RecBlock @title='Details'>
                <ThreadFacts @model={{@model}} />
              </RecBlock>
            </:side>
          </RecBody>
        </RecCard>
      </IsoFrame>
      <style scoped>
        .post {
          display: grid;
          gap: var(--boxel-sp-5xs);
        }
        .body {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead
          @mark='Th'
          @title={{@model.cardTitle}}
          @sub={{threadSub @model}}
        >
          <:status><ThreadStatus @model={{@model}} /></:status>
        </RecHead>
        <ThreadFacts @model={{@model}} />
        <RecRow @label='About'>{{#if @model.about}}<@fields.about
              @format='atom'
            />{{else}}—{{/if}}</RecRow>
      </RecCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Th</span>
        <span class='nm'>{{@model.cardTitle}}</span>
        <Chip @appearance='plain'>{{postsLabel @model.postCount}}</Chip>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: var(--boxel-font-size-xs);
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: var(--boxel-icon-xs);
          block-size: var(--boxel-icon-xs);
          border: 1px solid var(--border);
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          line-height: 1;
          color: var(--muted-foreground);
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Posts', value: String(m?.postCount ?? 0) },
        { key: 'Last post', value: shortDate(m?.lastActivityAt) },
        { key: 'Last author', value: m?.lastAuthorName || '—' },
        { key: 'Pinned', value: m?.pinned ? 'yes' : 'no' },
        { key: 'Closed', value: m?.closed ? 'yes' : 'no' },
      ];
    }
    <template>
      <RichFittedCard>
        <:avatar><span class='mark' aria-hidden='true'>Th</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{threadSub @model}}</:subtitle>
        <:status><ThreadStatus @model={{@model}} /></:status>
        <:fact>Last activity
          <strong>{{shortDate @model.lastActivityAt}}</strong></:fact>
        <:details>
          {{#each this.facts as |item|}}<Detail
              @label={{item.key}}
              @value={{item.value}}
            />{{/each}}
          <Detail @label='About'>{{#if @model.about}}<@fields.about
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          display: grid;
          place-items: center;
          inline-size: 100%;
          block-size: 100%;
          border: 1px solid var(--border);
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          line-height: 1;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

type ThreadModel = Partial<Thread> | null | undefined;

// Status as dot + text: pinned / closed, then the post count.
const ThreadStatus: TemplateOnlyComponent<{ Args: { model: ThreadModel } }> =
  <template>
    {{#if @model.pinned}}<Chip
        @appearance='plain'
        @tone='info'
      >pinned</Chip>{{/if}}{{#if @model.closed}}<Chip
        @appearance='plain'
      >closed</Chip>{{/if}}<Chip @appearance='plain'>{{postsLabel
        @model.postCount
      }}</Chip>
  </template>;

const ThreadFacts: TemplateOnlyComponent<{ Args: { model: ThreadModel } }> =
  <template>
    <RecRow @label='Posts' @mono={{true}}>{{@model.postCount}}</RecRow>
    <RecRow @label='Last post' @mono={{true}}>{{longDate
        @model.lastActivityAt
      }}</RecRow>
    <RecRow @label='Last author'>{{if
        @model.lastAuthorName
        @model.lastAuthorName
        '—'
      }}</RecRow>
    <RecRow @label='Pinned'>{{if @model.pinned 'yes' 'no'}}</RecRow>
    <RecRow @label='Closed'>{{if @model.closed 'yes' 'no'}}</RecRow>
  </template>;

function threadSub(t: ThreadModel): string {
  let last = t?.lastAuthorName;
  return last ? `Thread · last ${last}` : 'Thread';
}

function peopleHint(t: ThreadModel): string {
  let n = new Set((t?.posts ?? []).map((p: any) => p?.authorName)).size;
  return n === 1 ? '1 person' : `${n} people`;
}

function postsCount(t: ThreadModel): number {
  return t?.postCount ?? 0;
}

function postsLabel(n?: number | null): string {
  return n === 1 ? '1 post' : `${n ?? 0} posts`;
}

function shortDate(d?: Date | string | null): string {
  return d
    ? new Date(d).toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
      })
    : '—';
}

function longDate(d?: Date | string | null): string {
  return d
    ? new Date(d).toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}

function plain(md?: string | null): string {
  return (md ?? '').replace(/[#*_>`]/g, '');
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

export default Thread;
