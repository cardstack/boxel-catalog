import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import StickyNoteIcon from '@cardstack/boxel-icons/sticky-note';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import CreatedAtField from '@cardstack/catalog/fields/created-at/created-at';
import { User } from '../crm/user';
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';

/**
 * A freeform written record, usually about something — the base card
 * content-calendar found missing (its ContentIdea had to extend CardDef
 * directly and recorded the gap). The block is deliberately small: a title,
 * a markdown body, who wrote it, when, and the one link that gives a note
 * its power — `about`, the card it annotates. Apps extend it additively
 * (a session note adds its quest, a call note adds its deal).
 */
const EXCERPT_LENGTH = 140;

function excerpt(body: string | null | undefined): string {
  if (!body?.trim()) {
    return '';
  }
  let plain = body
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/[#*_>`[\]()!-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return plain.length > EXCERPT_LENGTH
    ? plain.slice(0, EXCERPT_LENGTH).trimEnd() + '…'
    : plain;
}

export class Note extends CardDef {
  static displayName = 'Note';
  static icon = StickyNoteIcon;

  @field title = contains(StringField);
  @field body = contains(MarkdownField);
  @field about = linksTo(CardDef);
  @field author = linksTo(() => User);
  @field createdAt = contains(CreatedAtField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Note) {
      if (this.title?.trim()?.length) {
        return this.title;
      }
      let fromBody = excerpt(this.body);
      return fromBody.length ? fromBody.slice(0, 60) : 'Untitled note';
    },
  });

  static embedded = class Embedded extends Component<typeof Note> {
    get excerpt() {
      return excerpt(this.args.model?.body);
    }
    <template>
      <div class='note-row'>
        <div class='n-main'>
          <span class='n-title'>{{@model.cardTitle}}</span>
          {{#if this.excerpt}}
            <span class='n-excerpt'>{{this.excerpt}}</span>
          {{/if}}
        </div>
        <span class='n-when'>{{#if @model.createdAt}}<@fields.createdAt
              @format='atom'
            />{{else}}<span class='n-empty'>—</span>{{/if}}</span>
      </div>
      <style scoped>
        .note-row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .n-main {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          flex: 1;
          min-width: 0;
        }
        .n-title {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .n-excerpt {
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .n-when {
          flex-shrink: 0;
          min-width: 4rem;
          text-align: right;
        }
        .n-empty {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Note> {
    <template>
      <span class='note-atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .note-atom {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Note> {
    <template>
      <IsoFrame>
        <article class='note-page'>
          <header>
            <h1>{{@model.cardTitle}}</h1>
            <div class='byline'>
              {{#if @model.author}}
                <span>{{@model.author.name}}</span>
              {{/if}}
              {{#if @model.createdAt}}
                <span class='muted'><@fields.createdAt @format='atom' /></span>
              {{/if}}
              {{#if @model.about}}
                <span class='about'>on <@fields.about @format='atom' /></span>
              {{/if}}
            </div>
          </header>
          {{#if @model.body}}
            <section class='body'><@fields.body /></section>
          {{else}}
            <EmptyState
              @title='Nothing written yet.'
              @texture={{false}}
              style={{COMPACT_EMPTY_STYLE}}
            />
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .note-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 40rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        header {
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
        }
        h1 {
          font-size: var(--boxel-font-size-lg);
          line-height: 1.2;
          font-family: var(--font-heading);
        }
        .byline {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
        }
        .muted {
          color: var(--muted-foreground);
        }
        .about {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          color: var(--muted-foreground);
        }
        .body {
          line-height: 1.55;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Note> {
    get excerpt() {
      return excerpt(this.args.model?.body);
    }
    <template>
      <RichFittedCard>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{#if @model.createdAt}}<@fields.createdAt
              @format='atom'
            />{{/if}}</:subtitle>
        <:fact>{{this.excerpt}}</:fact>
        <:details>
          {{#if @model.author}}<Detail @label='Author'><@fields.author
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.about}}<Detail @label='About'><@fields.about
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };
}

export default Note;
