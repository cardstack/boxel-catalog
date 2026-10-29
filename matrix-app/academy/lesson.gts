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
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
import {
  AcademyAtom,
  AcademyEmbedded,
  AcademyIsolated,
  AcademyPanel,
  type FormatFact,
} from './components/card-formats';
import { Button } from '../../ui-component/components/button';
import { EmptyState } from '../../ui-component/components/empty-state';
import { FormatDate } from '../../ui-component/components/format-date';
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
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Kind', value: m?.kindLabel || '—' },
        { key: 'Order', value: m?.order == null ? '—' : String(m.order) },
        { key: 'Duration', value: m?.durationLabel || '—' },
        { key: 'Live session', value: fmtDateTime(m?.liveSessionAt) || '—' },
      ];
    }
    <template>
      <AcademyIsolated
        @mark='Le'
        @title={{@model.cardTitle}}
        @subtitle={{@model.summary}}
      >
        <:chips>
          <StatePill
            @label={{@model.kindLabel}}
            @hue={{this.hue}}
            @dot={{true}}
          />
        </:chips>
        <:stats>
          <Stat
            @label='Kind'
            @value={{if @model.kindLabel @model.kindLabel '—'}}
            @hint={{glyphFor @model.kind}}
            @roll={{false}}
          />
          <Stat
            @label='Duration'
            @value={{if @model.durationLabel @model.durationLabel '—'}}
            @hint='time to complete'
            @roll={{false}}
          />
          <Stat
            @label='Order'
            @value={{if @model.order @model.order '—'}}
            @hint='position in the module'
            @roll={{false}}
          />
        </:stats>
        <:main>
          <AcademyPanel @title='Content'>
            {{#if @model.content.content}}
              <@fields.content />
            {{else}}
              <EmptyState
                @size='s'
                @title='No content yet'
                @message='Add a reading, a transcript or the exercise brief.'
              />
            {{/if}}
          </AcademyPanel>
          {{#if @model.media.length}}
            <AcademyPanel @title='Materials'>
              <div class='media-grid'><@fields.media @format='embedded' /></div>
            </AcademyPanel>
          {{/if}}
        </:main>
        <:side>
          {{#if @model.liveSessionAt}}
            <AcademyPanel @title='Live session'>
              <p class='live-when'>
                <FormatDate
                  @date={{@model.liveSessionAt}}
                  @weekday='short'
                  @month='short'
                  @day='numeric'
                  @hour='numeric'
                  @minute='2-digit'
                />
              </p>
              {{#if @model.meetingUrl}}
                <Button
                  @href={{@model.meetingUrl}}
                  @appearance='link'
                  target='_blank'
                  rel='noopener noreferrer'
                >Join room ↗</Button>
              {{/if}}
            </AcademyPanel>
          {{/if}}
          <AcademyPanel @title='Details'>
            <KeyValue @items={{this.details}} @rows='ruled' />
          </AcademyPanel>
        </:side>
      </AcademyIsolated>
      <style scoped>
        @layer PretComponent {
          .media-grid {
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .live-when {
            margin: 0 0 var(--boxel-sp-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    get facts(): FormatFact[] {
      let m = this.args.model;
      return [
        { key: 'Kind', value: m?.kindLabel || '—' },
        { key: 'Duration', value: m?.durationLabel || '—' },
        { key: 'Order', value: m?.order != null ? String(m.order) : '—' },
        { key: 'Live session', value: fmtDateTime(m?.liveSessionAt) || '—' },
      ];
    }
    <template>
      <AcademyEmbedded
        @mark='Le'
        @title={{@model.cardTitle}}
        @subtitle={{@model.summary}}
        @facts={{this.facts}}
      >
        <:chips><StatePill @label={{@model.kindLabel}} @hue={{this.hue}} />
        </:chips>
        <:relations></:relations>
      </AcademyEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <AcademyAtom @mark='Le' @name={{@model.cardTitle}}>
        <StatePill @label={{@model.kindLabel}} @hue={{this.hue}} />
      </AcademyAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return LESSON_KIND_HUES[this.args.model?.kind ?? ''] ?? 'slate';
    }
    get fact() {
      let m = this.args.model;
      return m?.liveSessionAt
        ? `Live ${fmtDateTime(m.liveSessionAt)}`
        : m?.durationLabel || '';
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Kind', value: m?.kindLabel || '—' },
        { key: 'Duration', value: m?.durationLabel || '—' },
        { key: 'Order', value: m?.order != null ? String(m.order) : '—' },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Le'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.cardTitle}}</span></:title>
            <:subtitle>{{@model.summary}}</:subtitle>
            <:status><StatePill
                @label={{@model.kindLabel}}
                @hue={{this.hue}}
              /></:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
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
