import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import MarkdownField from 'https://cardstack.com/base/markdown';
import enumField from 'https://cardstack.com/base/enum';
import BookOpenIcon from '@cardstack/boxel-icons/book-open';

import { TicketCategory } from './ticket-category';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { Avatar as PretAvatar } from '@cardstack/pretui/components/avatar';
import { FitTile } from '../shared/fit-tile';
import { FittedExtras } from '../procurement/vendor';
import {
  RecCard,
  RecHead,
  RecStats,
  RecBody,
  RecBlock,
  RecRow,
  RecText,
} from './components/record';
import { eq } from '@cardstack/boxel-ui/helpers';
import { IsoFrame } from '../shared/compact-sheet';

export const ARTICLE_VISIBILITIES = ['Public', 'Internal'] as const;
export const ARTICLE_STATUSES = ['Draft', 'Published', 'Archived'] as const;

const VisibilityField = enumField(StringField, {
  displayName: 'Visibility',
  options: ARTICLE_VISIBILITIES as unknown as string[],
});

const ArticleStatusField = enumField(StringField, {
  displayName: 'Article Status',
  options: ARTICLE_STATUSES as unknown as string[],
});

const STOP_WORDS = new Set([
  'the',
  'a',
  'an',
  'and',
  'or',
  'but',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'to',
  'of',
  'in',
  'on',
  'at',
  'for',
  'with',
  'my',
  'i',
  'it',
  'this',
  'that',
  'cant',
  'cannot',
  'not',
  'have',
  'has',
  'get',
  'when',
  'why',
  'how',
]);

function tokens(text?: string | null): string[] {
  return (text ?? '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((word) => word.length > 2 && !STOP_WORDS.has(word));
}

/**
 * A written answer.
 *
 * The spec puts the knowledge base in v1.1. It is here in v1 because the
 * workspace's suggestion panel is one of the three things that make the
 * workspace worth building, and a suggestion panel with nothing to suggest is
 * an empty box with a heading.
 */
export class KnowledgeArticle extends CardDef {
  static displayName = 'Knowledge Article';
  static icon = BookOpenIcon;

  @field headline = contains(StringField);
  @field body = contains(MarkdownField);
  @field category = linksTo(() => TicketCategory);
  @field visibility = contains(VisibilityField);
  @field status = contains(ArticleStatusField);
  @field keywords = containsMany(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: KnowledgeArticle) {
      return this.headline?.trim() || 'Untitled article';
    },
  });

  @field categoryName = contains(StringField, {
    computeVia: function (this: KnowledgeArticle) {
      return this.category?.title ?? '';
    },
  });

  @field excerpt = contains(StringField, {
    computeVia: function (this: KnowledgeArticle) {
      let text = (this.body ?? '')
        .replace(/[#*_`>[\]()]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
      return text.length > 180 ? `${text.slice(0, 177)}…` : text;
    },
  });

  /* The tall fitted quanta had a second slot that re-printed categoryName —
     the same word the body already showed, so 5 of the 16 sizes spent a row
     saying nothing new. Keywords were declared and never rendered anywhere,
     which made them the obvious thing to put there. Capped at 4 so the row
     stays one line at 150px. */
  @field keywordLabel = contains(StringField, {
    computeVia: function (this: KnowledgeArticle) {
      return (this.keywords ?? []).filter(Boolean).slice(0, 4).join(' · ');
    },
  });

  @field isInternal = contains(StringField, {
    computeVia: function (this: KnowledgeArticle) {
      return this.visibility === 'Internal' ? 'Internal' : '';
    },
  });

  /**
   * How well this article answers a ticket, 0–100.
   *
   * Deterministic keyword overlap, not a model call. A suggestion panel that
   * goes blank when the AI credits run out is worse than one that is merely
   * approximate, and support teams judge these suggestions constantly — a
   * wrong-but-explainable score survives that scrutiny, a black box does not.
   *
   * Weighting: an explicit keyword is worth three title words, and a title
   * word is worth three body words, because authors choose keywords precisely
   * and bodies mention everything in passing.
   */
  relevanceTo(subject?: string | null): number {
    let needles = new Set(tokens(subject));
    if (!needles.size) {
      return 0;
    }
    let score = 0;
    for (let keyword of this.keywords ?? []) {
      if (tokens(keyword).some((t) => needles.has(t))) {
        score += 9;
      }
    }
    for (let word of new Set(tokens(this.headline))) {
      if (needles.has(word)) {
        score += 3;
      }
    }
    for (let word of new Set(tokens(this.body).slice(0, 400))) {
      if (needles.has(word)) {
        score += 1;
      }
    }
    // Normalised against the size of the question, so a long ticket does not
    // make every article look like a better match than a short one does.
    return Math.min(100, Math.round((score / (needles.size * 3)) * 100));
  }

  static isolated = class Isolated extends Component<typeof this> {
    get visLower() {
      return String(this.args.model?.visibility ?? '').toLowerCase();
    }
    get keywordCount() {
      return (this.args.model?.keywords ?? []).filter(Boolean).length;
    }
    <template>
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead
            @mark='KB'
            @title={{@model.title}}
            @sub='{{@model.categoryName}} · {{this.visLower}}'
          >
            <:status>
              {{#if @model.status}}<Chip
                  @appearance='plain'
                  @tone={{if
                    (eq @model.status 'Published')
                    'success'
                    'warning'
                  }}
                >{{@model.status}}</Chip>{{/if}}
              {{#if @model.visibility}}<Chip
                  @appearance='plain'
                >{{@model.visibility}}</Chip>{{/if}}
            </:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='Status'
              @tone={{if (eq @model.status 'Published') 'success' 'warning'}}
              @value={{if @model.status @model.status '—'}}
              @hint={{@model.visibility}}
              @roll={{false}}
            />
            <Stat
              @label='Category'
              @tone='neutral'
              @value={{if @model.categoryName @model.categoryName '—'}}
              @roll={{false}}
            />
            <Stat
              @label='Keywords'
              @tone='neutral'
              @value={{this.keywordCount}}
              @hint={{@model.keywordLabel}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
              <RecBlock @title='Article'>
                <RecText><@fields.body /></RecText>
              </RecBlock>
              <RecBlock @title='Keywords'>
                <RecText><span class='mono'>{{if
                      @model.keywordLabel
                      @model.keywordLabel
                      '—'
                    }}</span></RecText>
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Linked'>
                <RecRow @label='Category'>{{#if
                    @model.category
                  }}<@fields.category
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</RecRow>
              </RecBlock>
              <RecBlock @title='Details'>
                <RecRow @label='Status'>{{if
                    @model.status
                    @model.status
                    '—'
                  }}</RecRow>
                <RecRow @label='Visibility'>{{if
                    @model.visibility
                    @model.visibility
                    '—'
                  }}</RecRow>
                <RecRow @label='Category'>{{if
                    @model.categoryName
                    @model.categoryName
                    '—'
                  }}</RecRow>
                <RecRow @label='Keywords'>{{if
                    @model.keywordLabel
                    @model.keywordLabel
                    '—'
                  }}</RecRow>
              </RecBlock>
            </:side>
          </RecBody>
        </RecCard>
      </IsoFrame>
      <style scoped>
        .mono {
          font-family: var(--font-mono);
          font-size: 0.6875rem;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead
          @mark='KB'
          @title={{@model.title}}
          @sub={{@model.categoryName}}
        >
          <:status>{{#if @model.status}}<Chip
                @appearance='plain'
                @tone={{if (eq @model.status 'Published') 'success' 'warning'}}
              >{{@model.status}}</Chip>{{/if}}</:status>
        </RecHead>
        <RecText>{{@model.excerpt}}</RecText>
        <RecRow @label='Visibility'>{{if
            @model.visibility
            @model.visibility
            '—'
          }}</RecRow>
        <RecRow @label='Category'>{{if
            @model.categoryName
            @model.categoryName
            '—'
          }}</RecRow>
        <RecRow @label='Keywords'>{{if
            @model.keywordLabel
            @model.keywordLabel
            '—'
          }}</RecRow>
      </RecCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>KB</span>
        <span class='nm'>{{@model.title}}</span>
        {{#if @model.visibility}}<Chip
            @appearance='plain'
          >{{@model.visibility}}</Chip>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.3125rem;
          min-inline-size: 0;
          max-inline-size: 100%;
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
    // Whole ruled rows the tall fitted sizes add under the FitTile.
    get facts() {
      let m = this.args.model;
      return [
        {
          key: 'Category',
          value: String(m?.categoryName ?? '') || '—',
        },
        {
          key: 'Visibility',
          value: String(m?.visibility ?? '') || '—',
        },
        { key: 'Status', value: String(m?.status ?? '') || '—' },
        {
          key: 'Keywords',
          value: String(m?.keywordLabel ?? '') || '—',
        },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar><PretAvatar
                @name='KB'
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.title}}</:title>
            <:subtitle>{{@model.categoryName}}</:subtitle>
            <:status>{{#if @model.status}}<Chip
                  @appearance='plain'
                  @tone={{if
                    (eq @model.status 'Published')
                    'success'
                    'warning'
                  }}
                >{{@model.status}}</Chip>{{/if}}</:status>
            <:fact>{{@model.excerpt}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
    </template>
  };
}
