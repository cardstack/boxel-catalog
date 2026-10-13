import {
  CardDef,
  Component,
  FileDef,
  StringField,
  contains,
  field,
  linksToMany,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import enumField from '@cardstack/base/enum';
import { RichMarkdownField } from '@cardstack/base/rich-markdown';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FormatDate } from '@cardstack/pretui/components/format-date';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import { DurationField } from '../hr/duration-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const LESSON_KINDS = [
  { value: 'video', label: 'Video' },
  { value: 'reading', label: 'Reading' },
  { value: 'live', label: 'Live session' },
  { value: 'exercise', label: 'Exercise' },
];

export const LESSON_KIND_HUES: Record<string, Hue> = {
  video: 'purple',
  reading: 'blue',
  live: 'teal',
  exercise: 'amber',
};

export const LESSON_KIND_GLYPH: Record<string, string> = {
  video: '▶',
  reading: '¶',
  live: '●',
  exercise: '✎',
};

export const LessonKindField = enumField(StringField, {
  displayName: 'Lesson Kind',
  options: LESSON_KINDS,
});

/**
 * The smallest unit a learner consumes: one video, one reading, one live
 * hour, one exercise. Lessons are their own cards (not fields on Module) so a
 * live lesson can be the thing an Attendance Record points at and the thing
 * the cohort calendar shows. Media are linked file cards.
 */
export class Lesson extends CardDef {
  static displayName = 'Lesson';
  static icon = BookOpenIcon;

  @field title = contains(StringField);
  @field kind = contains(LessonKindField);
  @field order = contains(NumberField);
  @field duration = contains(DurationField);
  @field summary = contains(StringField);
  @field content = contains(RichMarkdownField);
  @field media = linksToMany(() => FileDef);
  @field liveSessionAt = contains(DateTimeField, {
    description: 'Live lessons only: when the room opens.',
  });
  @field meetingUrl = contains(UrlField);

  @field kindLabel = contains(StringField, {
    computeVia: function (this: Lesson) {
      return lessonKindLabel(this.kind);
    },
  });
  @field durationLabel = contains(StringField, {
    computeVia: function (this: Lesson) {
      return durationLabel(this.duration);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Lesson) {
      return this.title?.trim() || 'Untitled lesson';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <article class='lesson'>
        <header class='hero'>
          <span class='glyph' aria-hidden='true'>{{glyphFor @model.kind}}</span>
          <div class='hero-text'>
            <div class='eyebrow'>
              <StatePill
                @label={{@model.kindLabel}}
                @hue={{this.hue}}
                @dot={{true}}
              />
              {{#if @model.durationLabel}}
                <span class='dur'>{{@model.durationLabel}}</span>
              {{/if}}
            </div>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.summary}}
              <p class='summary'>{{@model.summary}}</p>
            {{/if}}
          </div>
        </header>
        {{#if @model.liveSessionAt}}
          <section class='live'>
            <span class='live-when'>Live
              <FormatDate
                @date={{@model.liveSessionAt}}
                @weekday='short'
                @month='short'
                @day='numeric'
                @hour='numeric'
                @minute='2-digit'
              /></span>
            {{#if @model.meetingUrl}}
              <Button
                @href={{@model.meetingUrl}}
                @appearance='link'
                target='_blank'
                rel='noopener noreferrer'
              >Join room ↗</Button>
            {{/if}}
          </section>
        {{/if}}
        <section class='body'>
          {{#if @model.content.content}}
            <@fields.content />
          {{else}}
            <EmptyState
              @size='s'
              @title='No content yet'
              @message='Add a reading, a transcript or the exercise brief.'
            />
          {{/if}}
        </section>
        {{#if @model.media.length}}
          <section class='media'>
            <h2>Materials</h2>
            <div class='media-grid'><@fields.media @format='embedded' /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .lesson {
          max-width: 52rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          gap: var(--boxel-sp);
          align-items: start;
        }
        .glyph {
          width: 3.25rem;
          height: 3.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--radius);
          background: var(--muted);
          color: var(--primary-ink);
          font-size: 1.5rem;
        }
        .eyebrow {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: center;
        }
        .dur {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        h1 {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
          letter-spacing: -0.01em;
        }
        .summary {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
        }
        .live {
          display: flex;
          justify-content: space-between;
          align-items: center;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border-radius: var(--radius);
          border: 1px solid var(--border);
          background: var(--card);
        }
        .live-when {
          font-weight: 600;
        }
        .body {
          line-height: 1.6;
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .media-grid {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <div class='row'>
        <span class='glyph' aria-hidden='true'>{{glyphFor @model.kind}}</span>
        <span class='title'>{{@model.cardTitle}}</span>
        <StatePill
          @label={{@model.kindLabel}}
          @hue={{this.hue}}
          @chrome={{true}}
        />
        <span class='dur'>{{if
            @model.durationLabel
            @model.durationLabel
            '—'
          }}</span>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto 4.5rem;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .glyph {
          width: 1.5rem;
          height: 1.5rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--muted);
          font-size: var(--boxel-font-size-xs);
        }
        .title {
          font-weight: 600;
          color: var(--foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .dur {
          text-align: end;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{glyphFor @model.kind}} {{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'content', label: 'Content' },
      { id: 'live', label: 'Live session' },
      { id: 'materials', label: 'Materials' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Lesson sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Title' @vertical={{true}}><@fields.title
            /></FieldContainer>
          <FieldContainer @label='Kind' @vertical={{true}}><@fields.kind
            /></FieldContainer>
          <FieldContainer @label='Order' @vertical={{true}}><@fields.order
            /></FieldContainer>
          <FieldContainer @label='Duration' @vertical={{true}}><@fields.duration
            /></FieldContainer>
        </e.Section>
        <e.Section @id='content' @title='Content' @cols={{1}}>
          <FieldContainer @label='Summary' @vertical={{true}}><@fields.summary
            /></FieldContainer>
          <FieldContainer @label='Content' @vertical={{true}}><@fields.content
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='live'
          @title='Live session'
          @hint='live lessons only'
          @cols={{2}}
        >
          <FieldContainer
            @label='Session time'
            @vertical={{true}}
          ><@fields.liveSessionAt /></FieldContainer>
          <FieldContainer
            @label='Meeting URL'
            @vertical={{true}}
          ><@fields.meetingUrl /></FieldContainer>
        </e.Section>
        <e.Section @id='materials' @title='Materials' @cols={{1}}>
          <FieldContainer @label='Files' @vertical={{true}}><@fields.media
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <FittedCard @titleTag='h3'>
        <:placeholder><span class='glyph' aria-hidden='true'>{{glyphFor
              @model.kind
            }}</span></:placeholder>
        <:eyebrow>{{@model.kindLabel}}{{#if @model.durationLabel}}
            ·
            {{@model.durationLabel}}{{/if}}</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.summary}}</:subtitle>
        <:badgeRight><StatePill
            @label={{@model.kindLabel}}
            @hue={{this.hue}}
          /></:badgeRight>
        <:footer>{{#if @model.liveSessionAt}}Live
            <FormatDate
              @date={{@model.liveSessionAt}}
              @weekday='short'
              @month='short'
              @day='numeric'
              @hour='numeric'
              @minute='2-digit'
            />{{/if}}</:footer>
      </FittedCard>
      <style scoped>
        .glyph {
          font-size: var(--boxel-font-size-lg);
          color: var(--primary-ink);
        }
      </style>
    </template>
  };
}

export function lessonKindLabel(kind?: string | null): string {
  return LESSON_KINDS.find((k) => k.value === kind)?.label ?? 'Lesson';
}

export function glyphFor(kind?: string | null): string {
  return LESSON_KIND_GLYPH[kind ?? ''] ?? '•';
}

export function durationLabel(d?: Partial<DurationField> | null): string {
  if (!d?.value) return '';
  if ((d as any).label) return (d as any).label;
  return `${d.value} ${d.unit ?? 'minutes'}`;
}

export function lessonMinutes(d?: Partial<DurationField> | null): number {
  if (!d?.value) return 0;
  let factor: Record<string, number> = {
    minutes: 1,
    hours: 60,
    days: 60 * 8,
    weeks: 60 * 40,
    months: 60 * 160,
    years: 60 * 1920,
  };
  return d.value * (factor[d.unit ?? 'minutes'] ?? 1);
}

export function fmtDateTime(d: Date | string | null | undefined): string {
  if (!d) return '';
  return new Date(d).toLocaleString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export default Lesson;
