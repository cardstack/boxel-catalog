import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
  Component,
  getComponent,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import MarkdownField from '@cardstack/base/markdown';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import { ConditionGrade } from '@cardstack/catalog/fields/condition-grade/condition-grade';
import ArchiveIcon from '@cardstack/boxel-icons/archive';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { MarketplaceMember } from './marketplace-member';
import { Acquisition } from './acquisition';
import { formatMoneyDelta, moneyText } from './money-format';
import { DotLabel } from '../hr/dot-enum-field';
import { RichFittedCard, Media } from '../shared/rich-fitted-card';
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

// CollectionItem — one physical thing someone owns, catalogued.
//
// The block is deliberately NOT about sneakers. `item` links to any CardDef, so
// the same block catalogues a sneaker, a watch, a record, or a first edition; the
// consumer narrows the link type and supplies the grading vocabulary. Nothing in
// this module names a domain.
//
// Two schema decisions worth reading before changing them:
//
// 1. THRESHOLD FLAGS ARE EVENT FACTS. `verified` and `forSale` are computed from
//    `verifiedOn` and `listedAt`. Storing either boolean lets it drift from the
//    thing that caused it — the classic failure is a card that reads "not for
//    sale" while an active listing points at it. Dates are also attributes, so
//    they survive prerendered fitted views, where a linksTo would not resolve.
//
// 2. NO CURRENT-MARKET-VALUE FIELD. "What is this worth right now" is a
//    reporting rollup over active listings — unbounded, and a live realm query
//    belongs in a metrics component a consumer composes, never link-arrayed onto
//    the hot card. `lastKnownValue` + `valuedOn` is the fitted-safe snapshot: an
//    attribute a tile can render without running a query.
export class CollectionItem extends CardDef {
  static displayName = 'Collection Item';
  static icon = ArchiveIcon;

  // The catalogued thing. Consumers narrow this (linksTo(() => Product)).
  //
  // `searchable: true` pulls the linked card's fields into this card's search
  // document, which is what lets a collection view filter and sort by the thing
  // owned ("all my Jordan 1s") instead of only by this card's own attributes.
  @field item = linksTo(CardDef, { searchable: true });

  // The size/edition/variant label, and the scale it is expressed on.
  // Checked and rejected as substitutes: catalog `quantity` is a bounded count,
  // catalog `discrete-range-field` is a range. A single graded value on a named
  // scale is neither, and the scale is the consumer's ('US', 'UK', 'EU', 'cm').
  @field variant = contains(StringField);
  @field variantScale = contains(StringField);

  @field condition = contains(ConditionGrade);

  // 'OG All', 'Replacement Box', 'No Box' — a fixed list per domain, so the
  // consumer supplies enum options on its own override of this field.
  @field packaging = contains(StringField);

  @field acquisition = contains(Acquisition);

  // The owner's own photos. Takes a pasted URL or a file uploaded into the
  // realm; `photos.primaryUrl` is the fitted visual anchor.
  @field photos = contains(MultiImageSourceField);

  // --- authentication, as event facts ---
  @field verifiedOn = contains(DateField);
  @field verifiedBy = contains(StringField);
  @field verificationReference = contains(StringField);
  @field verified = contains(BooleanField, {
    computeVia: function (this: CollectionItem) {
      return this.verifiedOn != null;
    },
  });

  // --- for-sale state, as an event fact ---
  @field listedAt = contains(DateField);
  @field forSale = contains(BooleanField, {
    computeVia: function (this: CollectionItem) {
      return this.listedAt != null;
    },
  });

  // Fitted-safe valuation snapshot. See note 2 above.
  @field lastKnownValue = contains(AmountWithCurrency);
  @field valuedOn = contains(DateField);

  // Whose copy this is.
  @field owner = linksTo(() => MarketplaceMember, { searchable: true });

  @field notes = contains(MarkdownField);

  // DENORMALIZED FOR PRERENDERED FITTED — do not "simplify" this to
  // `@model.item.title` in a template.
  //
  // A collection view draws its grid and list from prerendered fitted HTML, and
  // prerendered fitted cannot resolve linksTo/linksToMany. A tile that reads the
  // linked card directly renders blank — which is every tile in the grid, since
  // the thing owned is the tile's headline. A computed field is resolved at INDEX
  // time and stored in the search document, so it is a plain attribute by the time
  // fitted renders and survives the trip.
  //
  // Defensive on purpose: `item` may be unlinked (the block is neutral, the link
  // is optional) or not yet loaded, so this optional-chains and falls back to the
  // card's own title rather than rendering 'undefined'.
  @field itemTitle = contains(StringField, {
    computeVia: function (this: CollectionItem) {
      return this.item?.cardInfo?.name ?? this.cardInfo?.name ?? '';
    },
  });

  @field variantLabel = contains(StringField, {
    computeVia: function (this: CollectionItem) {
      if (!this.variant) {
        return '';
      }
      return this.variantScale
        ? `${this.variantScale} ${this.variant}`
        : this.variant;
    },
  });

  static isolated = class Isolated extends Component<typeof CollectionItem> {
    // The certificate and the listing point at this item, not the reverse.
    private certQuery = linkedQuery(
      this,
      'AuthenticationRecord',
      './authentication-record',
      'item.id',
    );
    private listingQuery = linkedQuery(
      this,
      'Listing',
      './listing',
      'collectionItem.id',
    );

    get certificate() {
      return instances(this.certQuery)[0];
    }

    get listing() {
      return instances(this.listingQuery)[0];
    }

    get delta() {
      return formatMoneyDelta(
        this.args.model?.lastKnownValue,
        this.args.model?.acquisition?.price,
      );
    }

    <template>
      <IsoFrame>
        <SnSheet @title={{@model.cardTitle}} @src={{photoOf @model}}>
          <:meta>{{metaLine @model}}</:meta>
          <:actions>
            {{#if @model.verified}}<DotLabel
                @label='verified'
                @hue='green'
              />{{/if}}
            {{#if @model.condition.code}}<DotLabel
                @label={{@model.condition.code}}
                @hue='green'
              />{{/if}}
            {{#if @model.forSale}}<DotLabel
                @label='for sale'
                @hue='orange'
              />{{/if}}
          </:actions>
          <:stats>
            <SnStat
              @label='Value'
              @value={{moneyText @model.lastKnownValue}}
              @hint={{day @model.valuedOn}}
            />
            <SnStat
              @label='Paid'
              @value={{moneyText @model.acquisition.price}}
              @hint={{day @model.acquisition.acquiredOn}}
            />
            <SnStat
              @label='Gain'
              @value={{if this.delta this.delta.text '—'}}
              @hint={{if this.delta this.delta.percent}}
            />
          </:stats>
          <:main>
            <SnSection @title='Notes'>
              {{#if @model.notes}}<@fields.notes />{{else}}—{{/if}}
            </SnSection>
            <SnSection @title='Acquisition' @flush={{true}}>
              <SnKv>
                <SnRow @label='Price'>{{moneyText
                    @model.acquisition.price
                  }}</SnRow>
                <SnRow
                  @label='Acquired'
                  @value={{day @model.acquisition.acquiredOn}}
                />
                <SnRow @label='Source'>{{or @model.acquisition.source}}</SnRow>
                <SnRow @label='Reference'>{{or
                    @model.acquisition.reference
                  }}</SnRow>
              </SnKv>
            </SnSection>
            <SnSection @title='Verification' @flush={{true}}>
              <SnKv>
                <SnRow @label='Verified' @value={{day @model.verifiedOn}} />
                <SnRow @label='By'>{{or @model.verifiedBy}}</SnRow>
                <SnRow @label='Reference'>{{or
                    @model.verificationReference
                  }}</SnRow>
              </SnKv>
            </SnSection>
          </:main>
          <:side>
            <SnSection @title='Linked' @flush={{true}}>
              <SnKv>
                <SnRow @label='Product'>{{#if @model.item}}<@fields.item
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</SnRow>
                <SnRow @label='Owner'>{{#if @model.owner}}<@fields.owner
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</SnRow>
                <SnRow @label='Certificate'>
                  {{#if this.certificate}}
                    {{#let (getComponent this.certificate) as |Cert|}}
                      <Cert @format='atom' @displayContainer={{false}} />
                    {{/let}}
                    <DotLabel
                      @label={{this.certificate.outcome}}
                      @hue={{outcomeHue this.certificate.outcome}}
                    />
                  {{else}}—{{/if}}
                </SnRow>
                <SnRow @label='Listing'>
                  {{#if this.listing}}
                    {{#let (getComponent this.listing) as |ListingCard|}}
                      <ListingCard @format='atom' @displayContainer={{false}} />
                    {{/let}}
                    <DotLabel
                      @label={{this.listing.listingStatus}}
                      @hue={{listingHue this.listing.listingStatus}}
                    />
                  {{else}}—{{/if}}
                </SnRow>
              </SnKv>
            </SnSection>
            <SnSection @title='Details' @flush={{true}}>
              <DetailRows @model={{@model}} />
            </SnSection>
          </:side>
        </SnSheet>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof CollectionItem> {
    <template>
      <SnEmbedded @title={{@model.cardTitle}} @src={{photoOf @model}}>
        <:meta>{{metaLine @model}}</:meta>
        <:status><DotLabel
            @label={{if @model.verified 'verified' 'unverified'}}
            @hue={{if @model.verified 'green' 'slate'}}
          /></:status>
        <:default>
          <DetailRows @model={{@model}} />
          <SnKv>
            <SnRow @label='Product'>{{#if @model.item}}<@fields.item
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</SnRow>
            <SnRow @label='Owner'>{{#if @model.owner}}<@fields.owner
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</SnRow>
          </SnKv>
        </:default>
      </SnEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof CollectionItem> {
    <template>
      <SnAtom @title={{@model.cardTitle}} @src={{photoOf @model}} />
    </template>
  };

  // Attributes only: a prerendered grid tile cannot resolve links.
  static fitted = class Fitted extends Component<typeof CollectionItem> {
    <template>
      <RichFittedCard>
        <:media><Media @src={{photoOf @model}} @alt=''><ArchiveIcon
              width='40%'
              height='40%'
            /></Media></:media>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><DotLabel
            @label={{if @model.verified 'verified' 'unverified'}}
            @hue={{if @model.verified 'green' 'slate'}}
          /></:status>
        <:fact>Value
          {{moneyText @model.lastKnownValue}}
          · Paid
          {{moneyText @model.acquisition.price}}</:fact>
      </RichFittedCard>
    </template>
  };
}

// The Details rows the isolated side panel and the embedded format share.
const DetailRows: TemplateOnlyComponent<{
  Args: { model: Partial<CollectionItem> };
}> = <template>
  <SnKv>
    <SnRow @label='Value'>{{moneyText @model.lastKnownValue}}</SnRow>
    <SnRow @label='Paid'>{{moneyText @model.acquisition.price}}</SnRow>
    <SnRow @label='Gain'>{{gainText @model}}</SnRow>
    <SnRow @label='Size'>{{or @model.variantLabel}}</SnRow>
    <SnRow @label='Condition'>{{or @model.condition.summary}}</SnRow>
    <SnRow @label='Packaging'>{{or @model.packaging}}</SnRow>
    <SnRow @label='Acquired' @value={{day @model.acquisition.acquiredOn}} />
    <SnRow @label='Source'>{{or @model.acquisition.source}}</SnRow>
    <SnRow @label='Verified'>{{verifiedText @model}}</SnRow>
  </SnKv>
</template>;

function or(v: string | null | undefined): string {
  return v || '—';
}

function photoOf(m: Partial<CollectionItem>): string | undefined {
  return m.photos?.resolvedUrls?.[0];
}

function metaLine(m: Partial<CollectionItem>): string {
  return [m.itemTitle, m.packaging].filter(Boolean).join(' · ') || '—';
}

function gainText(m: Partial<CollectionItem>): string {
  return formatMoneyDelta(m.lastKnownValue, m.acquisition?.price)?.text ?? '—';
}

function verifiedText(m: Partial<CollectionItem>): string {
  if (!m.verifiedOn) {
    return '—';
  }
  return [day(m.verifiedOn), m.verifiedBy].filter(Boolean).join(' · ');
}

type Hue = DotLabel['args']['hue'];

function outcomeHue(outcome: string | undefined): Hue {
  return outcome === 'passed'
    ? 'green'
    : outcome === 'failed'
      ? 'red'
      : 'amber';
}

function listingHue(status: string | undefined): Hue {
  return status === 'active' ? 'green' : 'slate';
}

export default CollectionItem;
