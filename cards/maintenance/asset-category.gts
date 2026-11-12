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
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import TagsIcon from '@cardstack/boxel-icons/tags';
import WindIcon from '@cardstack/boxel-icons/wind';
import ForkliftIcon from '@cardstack/boxel-icons/forklift';
import FlameIcon from '@cardstack/boxel-icons/flame';
import LaptopIcon from '@cardstack/boxel-icons/laptop';
import PlugIcon from '@cardstack/boxel-icons/plug';
import BoxesIcon from '@cardstack/boxel-icons/boxes';

import CriticalityField from './criticality-field';
import { Asset } from './asset';
import { MaintenancePlan } from './maintenance-plan';
import { RichFittedCard } from '../shared/rich-fitted-card';
import {
  Chip,
  Brief,
  Dot,
  Fact,
  Head,
  Mark,
  Row,
  Section,
  Sheet,
  dash,
  enumText,
  join,
  hueTone,
  type KvItem,
} from './card-ui';
import { IsoFrame } from '../shared/compact-sheet';

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

// The assets in a category, which every format shows (count, in service,
// the list); a live query because a card cannot search from a computed.
class CategoryView extends Component<typeof AssetCategory> {
  private assetQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.assetQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(Asset);
        let id = this.args.model?.id;
        return ref && id
          ? { filter: { on: ref, every: [{ eq: { 'category.id': id } }] } }
          : undefined;
      },
      () => {
        let url = (this.args.model as any)?.[realmURL];
        return url ? [url.href] : undefined;
      },
      { isLive: true },
    );
  }

  get assets(): Asset[] {
    return (this.assetQuery?.instances ?? []).filter(Boolean) as Asset[];
  }

  get inService(): number {
    return this.assets.filter((a) => a.status === 'in-service').length;
  }

  get level() {
    return this.args.model.defaultCriticality?.level;
  }

  get rows(): KvItem[] {
    let m = this.args.model;
    return [
      { key: 'Code', value: dash(m.code) },
      { key: 'Expected life', value: lifeYears(m.expectedLifeMonths, true) },
      { key: 'Criticality', value: capital(this.level) },
      { key: 'Default team', value: dash(m.defaultTeamName) },
      { key: 'Assets', value: String(this.assets.length) },
      { key: 'In service', value: String(this.inService) },
    ];
  }
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
    <template>
      <Chip
        @bare={{true}}
        @mark='Ca'
        @name={{@model.cardTitle}}
        @meta={{@model.code}}
      />
    </template>
  };

  static embedded = class Embedded extends CategoryView {
    <template>
      <Brief @mark='Ca' @title={{@model.cardTitle}} @meta={{metaLine @model}}>
        <:status><CategoryDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Expected life'
            @strong={{lifeYears @model.expectedLifeMonths true}}
            @rest={{if @model.defaultTeamName (teamText @model)}}
          /></:fact>
        <:default>
          <KeyValue
            class='kv-pad'
            @items={{this.rows}}
            @labelStyle='eyebrow'
            @divided={{true}}
          />
          <AssetAtoms @assets={{this.assets}} />
        </:default>
      </Brief>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends CategoryView {
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='Ca' @size='lg' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><CategoryDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Expected life'
            @strong={{lifeYears @model.expectedLifeMonths true}}
            @rest={{if @model.defaultTeamName (teamText @model)}}
          /></:fact>
        <:relations>
          {{#each this.assets as |a|}}
            <Chip
              @bare={{true}}
              @mark='As'
              @name={{a.name}}
              @tone={{hueTone a.statusHue}}
            />
          {{/each}}
        </:relations>
      </RichFittedCard>
    </template>
  };

  static isolated = class Isolated extends CategoryView {
    get defaults(): KvItem[] {
      let m = this.args.model;
      return [
        { key: 'Code', value: dash(m.code) },
        {
          key: 'Expected life',
          value: m.expectedLifeMonths ? `${m.expectedLifeMonths} months` : '—',
        },
        { key: 'Default criticality', value: '' },
        { key: 'Default team', value: dash(m.defaultTeamName) },
      ];
    }

    get details(): KvItem[] {
      return [...this.rows, { key: 'Icon', value: dash(this.args.model.icon) }];
    }

    <template>
      <IsoFrame>
        <Sheet>
          <:head>
            <Head
              @mark='Ca'
              @title={{@model.cardTitle}}
              @meta={{metaLine @model}}
            >
              <:status><CategoryDots @model={{@model}} /></:status>
            </Head>
          </:head>
          <:stats>
            <Stat
              @label='Assets'
              @value={{this.assets.length}}
              @hint='{{this.inService}} in service'
              @roll={{false}}
            />
            <Stat
              @label='Expected life'
              @value={{lifeYears @model.expectedLifeMonths}}
              @hint={{if
                @model.expectedLifeMonths
                (concat @model.expectedLifeMonths ' months')
                '—'
              }}
              @roll={{false}}
            />
            <Stat
              @label='Criticality'
              @value={{capital this.level}}
              @hint='default for new assets'
              @roll={{false}}
            />
          </:stats>
          <:main>
            {{#if @model.description}}
              <Section @title='Description'><p
                >{{@model.description}}</p></Section>
            {{/if}}
            <Section @title='Defaults'>
              <KeyValue
                class='kv-pad'
                @items={{this.defaults}}
                @labelStyle='eyebrow'
                @divided={{true}}
              >
                <:value as |item|>
                  {{#if item.value}}{{item.value}}{{else if this.level}}<Dot
                      @tone={{criticalityTone this.level}}
                      @label={{this.level}}
                    />{{else}}—{{/if}}
                </:value>
              </KeyValue>
            </Section>
            <Section @title='Assets'>
              {{#each this.assets as |a|}}
                <Row
                  @title={{a.name}}
                  @meta={{join a.tag (shortPlace a.location.name)}}
                  @tone={{hueTone a.statusHue}}
                  @state={{enumText a.status}}
                />
              {{else}}
                <Row @title='No assets in this category yet' />
              {{/each}}
            </Section>
          </:main>
          <:side>
            <Section @title='Linked'>
              <AssetAtoms @assets={{this.assets}} />
            </Section>
            <Section @title='Details'>
              <KeyValue
                class='kv-pad'
                @items={{this.details}}
                @labelStyle='eyebrow'
                @divided={{true}}
              />
            </Section>
          </:side>
        </Sheet>
      </IsoFrame>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };
}

function concat(...parts: unknown[]) {
  return parts.join('');
}

function capital(s?: string | null) {
  return s ? s[0].toUpperCase() + s.slice(1) : '—';
}

function criticalityTone(level?: string | null) {
  return level === 'critical' ? 'bad' : level === 'high' ? 'warn' : undefined;
}

/** 180 → "15 yrs" (or "15 years" long); months under a year stay months */
function lifeYears(months?: number | null, long = false) {
  if (!months) return '—';
  if (months % 12) return `${months} months`;
  return `${months / 12} ${long ? 'years' : 'yrs'}`;
}

function teamText(m: Partial<AssetCategory>) {
  return `team ${m.defaultTeamName}`;
}

function metaLine(m: Partial<AssetCategory>) {
  return join(m.code, m.description);
}

/** "Room 214 — Compressor Room" → "Room 214" */
function shortPlace(name?: string | null) {
  return name ? name.split(' — ')[0] : undefined;
}

const CategoryDots: TemplateOnlyComponent<{
  Args: { model: Partial<AssetCategory> };
}> = <template>
  {{#if @model.code}}<Dot @label={{@model.code}} />{{/if}}
  {{#if @model.defaultCriticality.level}}
    <Dot
      @tone={{criticalityTone @model.defaultCriticality.level}}
      @label={{@model.defaultCriticality.level}}
    />
  {{/if}}
</template>;

const AssetAtoms: TemplateOnlyComponent<{ Args: { assets: Asset[] } }> =
  <template>
    <KeyValue
      class='kv-pad'
      @items={{assetItems @assets}}
      @labelStyle='eyebrow'
      @divided={{true}}
    >
      <:value as |item|>
        <Chip
          @bare={{true}}
          @mark='As'
          @name={{item.value}}
          @tone={{hueTone (itemHue @assets item)}}
          @meta={{enumText (itemStatus @assets item)}}
        />
      </:value>
    </KeyValue>
    <style scoped>
      .kv-pad {
        --pretui-kv-pad-inline: var(--boxel-sp-sm);
      }
    </style>
  </template>;

// KeyValue items are strings; a row finds its asset again by name.
function assetItems(assets: Asset[]): KvItem[] {
  return assets.map((a) => ({ key: 'Asset', value: a.name ?? a.tag ?? '—' }));
}
function itemOf(assets: Asset[], item: KvItem) {
  return assets.find((a) => (a.name ?? a.tag ?? '—') === item.value);
}
function itemHue(assets: Asset[], item: KvItem) {
  return itemOf(assets, item)?.statusHue;
}
function itemStatus(assets: Asset[], item: KvItem) {
  return itemOf(assets, item)?.status;
}

export default AssetCategory;
