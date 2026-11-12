import { markDefinition } from '@cardstack/base/mark-definition';
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
import { IsoFrame } from '../shared/compact-sheet';
import { RichFittedCard } from '../shared/rich-fitted-card';

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

export const SkillCategoryField = markDefinition(
  enumField(StringField, {
    options: SKILL_CATEGORIES.map((category) => ({
      value: category,
      label: category,
    })),
    displayName: 'Skill Category',
  }),
);

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
      <IsoFrame>
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
      </IsoFrame>
      <style scoped>
        .skill-isolated {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp-xl);
          height: 100%;
          box-sizing: border-box;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          align-items: flex-start;
          gap: var(--boxel-sp-sm);
          color: var(--card-foreground);
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
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <RichFittedCard>
        <:avatar><TagIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.title}}</:title>
        <:status>{{#if @model.category}}<StatePill
              class='category-chip'
              @label={{@model.category}}
              @hue={{skillCategoryHue @model.category}}
            />{{/if}}</:status>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
        .category-chip {
          text-transform: capitalize;
        }
      </style>
    </template>
  };
}
