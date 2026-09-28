import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import enumField from 'https://cardstack.com/base/enum';
import TagIcon from '@cardstack/boxel-icons/tag';
import { stateColor } from '@cardstack/catalog/components/state-pill';
import { pillStyle } from './utils';

export const SKILL_CATEGORIES = [
  'language',
  'framework',
  'tool',
  'platform',
  'practice',
];

export const SKILL_CATEGORY_COLORS: Record<string, { bg: string; fg: string }> =
  {
    language: stateColor('purple'),
    framework: stateColor('blue'),
    tool: stateColor('amber'),
    platform: stateColor('pink'),
    practice: stateColor('green'),
  };

const UNCATEGORISED = {
  bg: 'var(--muted)',
  fg: 'var(--muted-foreground)',
};

/** The chip colours for a skill's category; an unknown or empty category gets the muted pair. */
export function skillCategoryStyle(category?: string | null) {
  return pillStyle(SKILL_CATEGORY_COLORS[category ?? ''] ?? UNCATEGORISED);
}

export const SkillCategoryField = enumField(StringField, {
  options: SKILL_CATEGORIES.map((category) => ({
    value: category,
    label: category,
  })),
  displayName: 'Skill Category',
});

export class Skill extends CardDef {
  static displayName = 'Skill';
  static icon = TagIcon;

  @field name = contains(StringField);
  @field category = contains(SkillCategoryField);

  @field title = contains(StringField, {
    computeVia: function (this: Skill) {
      return this.name?.trim() || 'Unnamed Skill';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <article class='skill-isolated'>
        <span class='icon-chip'>
          <TagIcon class='icon-chip-svg' />
        </span>
        <h1>{{@model.title}}</h1>
        {{#if @model.category}}
          <span
            class='category-chip'
            style={{skillCategoryStyle @model.category}}
          >
            {{@model.category}}
          </span>
        {{/if}}
      </article>
      <style scoped>
        .skill-isolated {
          padding: var(--boxel-sp-xl);
          height: 100%;
          box-sizing: border-box;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: var(--boxel-sp-sm);
        }
        .icon-chip {
          width: 3rem;
          height: 3rem;
          border-radius: var(--radius);
          background-color: var(--accent);
          color: var(--accent-foreground);
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .icon-chip-svg {
          width: 1.5rem;
          height: 1.5rem;
        }
        h1 {
          margin: 0;
          font-weight: 800;
          font-size: var(--boxel-font-size-xl);
          letter-spacing: -0.02em;
        }
        .category-chip {
          padding: 0.25rem 0.75rem;
          border-radius: 999px;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='skill-chip' style={{skillCategoryStyle @model.category}}>
        {{@model.title}}
      </span>
      <style scoped>
        .skill-chip {
          display: inline-flex;
          align-items: center;
          padding: 0.2rem 0.6rem;
          border-radius: 999px;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='skill-atom'>{{@model.title}}</span>
      <style scoped>
        .skill-atom {
          font-size: 0.8125rem;
          font-weight: 500;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <span
          class='chip'
          style={{skillCategoryStyle @model.category}}
        >{{@model.title}}</span>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: flex;
          align-items: center;
          padding: 0.25rem 0.5rem;
          overflow: hidden;
        }
        .chip {
          display: inline-flex;
          align-items: center;
          padding: 0.2rem 0.6rem;
          border-radius: 999px;
          font-size: 0.75rem;
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
      </style>
    </template>
  };
}
