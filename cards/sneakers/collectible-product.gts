import {
  CardDef,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
  Component,
  getComponent,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import MarkdownField from '@cardstack/base/markdown';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import Tag from '@cardstack/base/tag';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import PackageIcon from '@cardstack/boxel-icons/package';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { formatMoney, moneyText } from './money-format';
import { DotLabel } from '../hr/dot-enum-field';
import {
  RichFittedCard,
  Media,
  Metric,
  Detail,
} from '../shared/rich-fitted-card';
import {
  SnAtom,
  SnEmbedded,
  SnKv,
  SnRow,
  SnSection,
  SnSheet,
  SnStat,
  day,
  instances,
  linkedQuery,
} from './parts';
import { IsoFrame } from '../shared/compact-sheet';

// CollectibleProduct — a catalogue entry for a manufactured collectible: the
// thing itself, not anyone's copy of it.
//
// NAMED `CollectibleProduct`, NOT `Product`, because `experiments-realm/product.gts`
// already exports a `Product` (an e-commerce demo card with seller/lead-time
// fields). Two `Product`s at one realm root would be a coin-flip for any importer.
//
// The split against CollectionItem is the whole point and is worth stating: this
// card is the CATALOGUE (one row per SKU, shared by everyone), CollectionItem is
// the OWNED COPY (one row per person per pair, with condition and acquisition).
// Retail price lives here because it is a fact about the product; what someone
// paid lives on their CollectionItem because it is a fact about their purchase.

export class CollectibleProduct extends CardDef {
  static displayName = 'Collectible Product';
  static icon = PackageIcon;

  // The definitive identifier — a UPC-like code. Kept as its own field rather
  // than folded into the title because it is looked up, read aloud and typed
  // into other systems.
  //
  @field sku = contains(StringField);

  @field colorway = contains(StringField);

  // Taxonomy, deliberately links rather than strings: 'Air Jordan 1 High' and
  // 'Nike' are shared vocabulary, so Silhouette and Brand ride on Tag rather
  // than being cards of their own.
  @field silhouette = linksTo(Tag, { searchable: true });
  @field brand = linksTo(Tag, { searchable: true });

  @field releaseDate = contains(DateField);
  @field retailPrice = contains(AmountWithCurrency);

  @field images = contains(MultiImageSourceField);
  @field productDescription = contains(MarkdownField);

  // The manufacturer's size run. containsMany of a plain string because the
  // scale is the consumer's — see CollectionItem.variantScale for the same call.
  @field availableVariants = containsMany(StringField);

  @field collabPartner = contains(StringField);
  @field tags = containsMany(StringField);

  // NO `lowestPrice` AND NO `listingCount`. They are unbounded rollups over
  // active listings: a live query belongs in a metrics component the consumer
  // composes, never link-arrayed or cached onto the hot catalogue card. A
  // consumer reads them with a reverse query on Listing.

  @field displayTitle = contains(StringField, {
    computeVia: function (this: CollectibleProduct) {
      let base = this.cardInfo?.name ?? '';
      return this.colorway ? `${base} "${this.colorway}"` : base;
    },
  });

  static isolated = class Isolated extends Component<
    typeof CollectibleProduct
  > {
    // Owned copies and the sets that include this product both point here.
    private ownedQuery = linkedQuery(
      this,
      'CollectionItem',
      './collection-item',
      'item.id',
    );
    private setsQuery = linkedQuery(
      this,
      'CompletionSet',
      './completion-set',
      'products.id',
    );

    get owned() {
      return instances(this.ownedQuery);
    }

    get sets() {
      return instances(this.setsQuery);
    }

    get ownedHint() {
      return (
        this.owned
          .map((c) => c.variantLabel)
          .filter(Boolean)
          .join(', ') || 'none owned'
      );
    }

    <template>
      <IsoFrame>
        <SnSheet @title={{@model.cardTitle}} @src={{photoOf @model}}>
          <:meta>{{metaLine @model}}</:meta>
          <:stats>
            <SnStat
              @label='Retail'
              @value={{moneyText @model.retailPrice}}
              @hint={{day @model.releaseDate}}
            />
            <SnStat
              @label='Sizes'
              @value={{sizeCount @model}}
              @hint={{sizeRange @model}}
            />
            <SnStat
              @label='In collection'
              @value={{countText this.owned}}
              @hint={{this.ownedHint}}
            />
          </:stats>
          <:main>
            <SnSection @title='Description'>
              {{#if @model.productDescription}}<@fields.productDescription
                />{{else}}—{{/if}}
            </SnSection>
            <SnSection @title='Available sizes'>
              <span class='mono'>{{listText @model.availableVariants}}</span>
            </SnSection>
            <SnSection @title='Tags'>{{listText @model.tags}}</SnSection>
          </:main>
          <:side>
            <SnSection @title='Linked' @flush={{true}}>
              <SnKv>
                {{#each this.owned as |copy|}}
                  <SnRow @label='Owned as'>
                    {{#let (getComponent copy) as |Copy|}}
                      <Copy @format='atom' @displayContainer={{false}} />
                    {{/let}}
                    {{#if copy.condition.code}}<DotLabel
                        @label={{copy.condition.code}}
                        @hue='green'
                      />{{/if}}
                  </SnRow>
                {{/each}}
                {{#each this.sets as |set|}}
                  <SnRow @label='Set'>
                    {{#let (getComponent set) as |SetCard|}}
                      <SetCard @format='atom' @displayContainer={{false}} />
                    {{/let}}
                    <DotLabel
                      @label={{if set.isPublic 'public' 'private'}}
                      @hue={{if set.isPublic 'blue' 'slate'}}
                    />
                  </SnRow>
                {{/each}}
                {{#unless this.owned.length}}{{#unless this.sets.length}}
                    <SnRow @label='Owned as'>—</SnRow>
                  {{/unless}}{{/unless}}
              </SnKv>
            </SnSection>
            <SnSection @title='Details' @flush={{true}}>
              <DetailRows @model={{@model}} />
            </SnSection>
          </:side>
        </SnSheet>
      </IsoFrame>
      <style scoped>
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof CollectibleProduct
  > {
    <template>
      <SnEmbedded @title={{@model.cardTitle}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:default><DetailRows @model={{@model}} /></:default>
      </SnEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof CollectibleProduct> {
    <template>
      <SnAtom @title={{@model.cardTitle}} @src={{photoOf @model}} />
    </template>
  };

  static fitted = class Fitted extends Component<typeof CollectibleProduct> {
    <template>
      <RichFittedCard>
        <:media><Media @src={{photoOf @model}} @alt=''><PackageIcon
              width='40%'
              height='40%'
            /></Media></:media>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><DotLabel @label={{sizeRange @model}} /></:status>
        <:fact>Retail
          {{moneyText @model.retailPrice}}
          ·
          {{if @model.releaseDate (day @model.releaseDate) '—'}}</:fact>
        <:metric>{{#if (formatMoney @model.retailPrice)}}<Metric
              @value={{formatMoney @model.retailPrice}}
              @label='Retail'
            />{{/if}}</:metric>
        <:details>
          {{#if @model.brand}}<Detail @label='Brand'><@fields.brand
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.silhouette}}<Detail
              @label='Silhouette'
            ><@fields.silhouette
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.collabPartner}}<Detail
              @label='Collab'
              @value={{@model.collabPartner}}
            />{{/if}}
          {{#if @model.availableVariants.length}}<Detail
              @label='Variants'
              @value={{sizeCount @model}}
            />{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };
}

// The Details rows the isolated side panel and the embedded format share.
const DetailRows: TemplateOnlyComponent<{
  Args: { model: Partial<CollectibleProduct> };
}> = <template>
  <SnKv>
    <SnRow @label='SKU'>{{or @model.sku}}</SnRow>
    <SnRow @label='Colorway'>{{or @model.colorway}}</SnRow>
    <SnRow @label='Released' @value={{day @model.releaseDate}} />
    <SnRow @label='Retail'>{{moneyText @model.retailPrice}}</SnRow>
    <SnRow @label='Sizes'>{{sizeRange @model}}</SnRow>
    <SnRow @label='Variants'>{{sizeCount @model}}</SnRow>
  </SnKv>
</template>;

function or(v: string | null | undefined): string {
  return v || '—';
}

function photoOf(m: Partial<CollectibleProduct>): string | undefined {
  return m.images?.resolvedUrls?.[0];
}

function metaLine(m: Partial<CollectibleProduct>): string {
  return [m.colorway, m.sku].filter(Boolean).join(' · ') || '—';
}

function sizes(m: Partial<CollectibleProduct>): string[] {
  return (m.availableVariants ?? []).filter(Boolean);
}

function sizeCount(m: Partial<CollectibleProduct>): string {
  let n = sizes(m).length;
  return n ? String(n) : '—';
}

function sizeRange(m: Partial<CollectibleProduct>): string {
  let s = sizes(m);
  if (!s.length) {
    return '—';
  }
  return s.length === 1 ? s[0] : `${s[0]} – ${s[s.length - 1]}`;
}

function listText(list: string[] | null | undefined): string {
  return (list ?? []).filter(Boolean).join(' · ') || '—';
}

function countText(list: unknown[]): string {
  return String(list.length);
}

export default CollectibleProduct;
