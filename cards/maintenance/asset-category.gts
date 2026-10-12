import {
  CardDef,
  Component,
  contains,
  field,
  linksToMany,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import MarkdownField from '@cardstack/base/markdown';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import TagsIcon from '@cardstack/boxel-icons/tags';
import WindIcon from '@cardstack/boxel-icons/wind';
import ForkliftIcon from '@cardstack/boxel-icons/forklift';
import FlameIcon from '@cardstack/boxel-icons/flame';
import LaptopIcon from '@cardstack/boxel-icons/laptop';
import PlugIcon from '@cardstack/boxel-icons/plug';
import BoxesIcon from '@cardstack/boxel-icons/boxes';

import CriticalityField from './criticality-field';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { Asset } from './asset';
import { MaintenancePlan } from './maintenance-plan';

/** Icon names a category may pick; anything else falls back to boxes. */
export const CATEGORY_ICONS: Record<string, unknown> = {
  wind: WindIcon,
  forklift: ForkliftIcon,
  flame: FlameIcon,
  laptop: LaptopIcon,
  plug: PlugIcon,
  boxes: BoxesIcon,
};

export function categoryIcon(name?: string | null) {
  return (CATEGORY_ICONS[name ?? ''] ?? BoxesIcon) as typeof BoxesIcon;
}

/**
 * A class of asset — HVAC, material handling, IT hardware — carrying the
 * defaults every asset of that kind inherits: expected life, default
 * criticality, the team that maintains it. Maintenance plans with no asset
 * link to a category and act as templates.
 */
export class AssetCategory extends CardDef {
  static displayName = 'Asset Category';
  static icon = TagsIcon;

  @field name = contains(StringField);
  @field code = contains(StringField, {
    description: 'Short code — HVAC, MH, IT',
  });
  @field description = contains(MarkdownField);
  @field expectedLifeMonths = contains(NumberField);
  @field defaultCriticality = contains(CriticalityField);
  @field defaultTeamName = contains(StringField, {
    description:
      'The team that receives generated work orders for this category.',
  });
  @field icon = contains(StringField, {
    description: 'wind | forklift | flame | laptop | plug | boxes',
  });
  @field defaultPlans = linksToMany(() => MaintenancePlan, {
    description:
      'Maintenance Plan templates (asset = null) that a new asset in this category can adopt.',
  });

  @field expectedLifeLabel = contains(StringField, {
    computeVia: function (this: AssetCategory) {
      let m = this.expectedLifeMonths;
      if (!m) return '';
      return m % 12 === 0 ? `${m / 12} yr life` : `${m} mo life`;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AssetCategory) {
      return this.name?.trim() || 'Untitled category';
    },
  });

  static atom = class Atom extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.icon);
    }
    <template>
      <span class='cat-atom'><this.Icon
          class='cat-atom-icon'
        />{{@model.cardTitle}}</span>
      <style scoped>
        .cat-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--foreground);
        }
        .cat-atom-icon {
          width: 0.9rem;
          height: 0.9rem;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.icon);
    }
    <template>
      <div class='cat'>
        <span class='cat-disc'><this.Icon class='cat-icon' /></span>
        <div class='cat-body'>
          <div class='cat-name'>{{@model.cardTitle}}
            {{#if @model.code}}<code
                class='cat-code'
              >{{@model.code}}</code>{{/if}}</div>
          <div class='cat-meta'>
            {{#if @model.expectedLifeLabel}}{{@model.expectedLifeLabel}}{{/if}}
            {{#if @model.defaultTeamName}}· {{@model.defaultTeamName}}{{/if}}
          </div>
        </div>
        <@fields.defaultCriticality @format='atom' />
      </div>
      <style scoped>
        .cat {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .cat-disc {
          flex: none;
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .cat-icon {
          width: 1rem;
          height: 1rem;
        }
        .cat-body {
          flex: 1;
          min-width: 0;
        }
        .cat-name {
          font-weight: 600;
          color: var(--foreground);
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
        }
        .cat-code {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .cat-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.icon);
    }
    <template>
      <FittedCard class='fit' @titleTag='h3'>
        <:placeholder><this.Icon width='24' height='24' /></:placeholder>
        <:eyebrow><span class='mono'>{{@model.code}}</span></:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.expectedLifeLabel}}{{#if @model.defaultTeamName}}
            ·
            {{@model.defaultTeamName}}{{/if}}</:subtitle>
      </FittedCard>
      <style scoped>
        .fit {
          --fc-title-font-size: var(--boxel-font-size-sm);
          --fc-subtitle-font-size: var(--boxel-font-size-xs);
        }
        .mono {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.icon);
    }

    // The two facts a manager actually opens this page for before assigning
    // an asset to it: how many already use it, and which plan templates
    // apply. `assetCount` can't be a model-level computeVia (no live search
    // inside a card's own field), so it's a live query here.
    assetQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      let realmHref = (this.args.model as any)?.[realmURL]?.href;
      this.assetQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(Asset);
          return ref ? { filter: { type: ref } } : undefined;
        },
        () => (realmHref ? [realmHref] : undefined),
        { isLive: true },
      );
    }

    get assetCount(): number {
      let id = this.args.model.id;
      if (!id) return 0;
      return ((this.assetQuery?.instances ?? []) as Asset[]).filter(
        (a) => a?.category?.id === id,
      ).length;
    }

    <template>
      <article class='iso'>
        <header class='iso-hero'>
          <span class='iso-disc'><this.Icon class='iso-icon' /></span>
          <div class='iso-head'>
            <h1 class='iso-title'>{{@model.cardTitle}}</h1>
            <p class='iso-meta'>Asset category
              {{#if @model.code}}· <code>{{@model.code}}</code>{{/if}}</p>
          </div>
          <@fields.defaultCriticality @format='embedded' />
        </header>
        <dl class='iso-facts'>
          <div><dt>Assets in this category</dt><dd
            >{{this.assetCount}}</dd></div>
          <div><dt>Expected life</dt><dd>{{if
                @model.expectedLifeLabel
                @model.expectedLifeLabel
                '—'
              }}</dd></div>
          <div><dt>Maintained by</dt><dd>{{if
                @model.defaultTeamName
                @model.defaultTeamName
                '—'
              }}</dd></div>
        </dl>
        {{#if @model.defaultPlans.length}}
          <section class='iso-plans'>
            <h2>Default maintenance plans</h2>
            <ul class='iso-plans-list'>
              {{#each @fields.defaultPlans as |Plan|}}
                <li><Plan @format='embedded' /></li>
              {{/each}}
            </ul>
          </section>
        {{else}}
          <p class='iso-plans-empty'>No default maintenance plan templates yet —
            every asset in this category will need its own plan.</p>
        {{/if}}
        {{#if @model.description}}
          <section class='iso-desc'><@fields.description /></section>
        {{/if}}
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
          color: var(--foreground);
          background: var(--card);
        }
        .iso-hero {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          flex-wrap: wrap;
        }
        .iso-disc {
          width: 3.5rem;
          height: 3.5rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .iso-icon {
          width: 1.75rem;
          height: 1.75rem;
        }
        .iso-head {
          flex: 1;
          min-width: 0;
        }
        .iso-meta {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .iso-meta code {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
        }
        .iso-title {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          text-wrap: balance;
        }
        .iso-facts {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp-sm);
        }
        .iso-facts dt {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .iso-facts dd {
          margin: 0;
          font-size: var(--boxel-font-size);
          font-weight: 600;
        }
        .iso-desc {
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp);
        }
        .iso-plans {
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp);
        }
        .iso-plans h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .iso-plans-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .iso-plans-empty {
          border-top: 1px solid var(--border);
          padding-top: var(--boxel-sp);
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
          font-style: italic;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'defaults', label: 'Defaults' },
      { id: 'plans', label: 'Default plans' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Category sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer @label='Code' @vertical={{true}}><@fields.code
            /></FieldContainer>
          <FieldContainer @label='Icon' @vertical={{true}}><@fields.icon
            /></FieldContainer>
          <FieldContainer
            @label='Description'
            @vertical={{true}}
          ><@fields.description /></FieldContainer>
        </e.Section>
        <e.Section
          @id='defaults'
          @title='Defaults'
          @hint='inherited by every asset of this kind'
          @cols={{2}}
        >
          <FieldContainer
            @label='Expected life (months)'
            @vertical={{true}}
          ><@fields.expectedLifeMonths /></FieldContainer>
          <FieldContainer
            @label='Maintained by (team)'
            @vertical={{true}}
          ><@fields.defaultTeamName /></FieldContainer>
          <FieldContainer
            @label='Default criticality'
            @vertical={{true}}
          ><@fields.defaultCriticality /></FieldContainer>
        </e.Section>
        <e.Section
          @id='plans'
          @title='Default maintenance plans'
          @hint='templates a new asset in this category can adopt'
        >
          <FieldContainer
            @label='Plan templates'
            @vertical={{true}}
          ><@fields.defaultPlans /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

export default AssetCategory;
