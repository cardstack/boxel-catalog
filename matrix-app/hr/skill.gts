import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import enumField from 'https://cardstack.com/base/enum';
import TagIcon from '@cardstack/boxel-icons/tag';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { hueOf } from './hr-ui';

export const SKILL_CATEGORIES = [
  'language',
  'framework',
  'tool',
  'platform',
  'practice',
];

// Category hues only; the status hues follow the theme's status tokens.
export const SKILL_CATEGORY_HUES: Record<string, Hue> = {
  language: 'purple',
  framework: 'blue',
  tool: 'teal',
  platform: 'pink',
  practice: 'slate',
};

/** The chip hue for a skill's category; an unknown or empty category gets StatePill's slate. */
export function skillCategoryHue(category?: string | null): Hue | undefined {
  return hueOf(SKILL_CATEGORY_HUES, category);
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
        <StatePill
          class='category-chip'
          @label={{@model.category}}
          @hue={{skillCategoryHue @model.category}}
        />
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
          text-transform: capitalize;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <StatePill
        @label={{@model.title}}
        @hue={{skillCategoryHue @model.category}}
      />
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
        <StatePill
          @label={{@model.title}}
          @hue={{skillCategoryHue @model.category}}
        />
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
      </style>
    </template>
  };
}
