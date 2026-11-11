import {
  CardDef,
  field,
  contains,
  linksToMany,
  StringField,
  Component,
  realmURL,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import TargetArrowIcon from '@cardstack/boxel-icons/target-arrow';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { identifyCard } from '@cardstack/runtime-common';
import { CollectibleProduct } from './collectible-product';
// CollectionItem is read ONLY inside the isolated component's methods, never at
// module-evaluation time. That is what keeps this import cycle legal —
// collection-item.gts does not import this module today, but the reverse query
// below is the shape that creates one, so do not hoist this usage to the top
// level "for clarity".
import { CollectionItem } from './collection-item';
import { DotLabel } from '../hr/dot-enum-field';
import { FitTile } from '../shared/fit-tile';
import {
  SnAtom,
  SnEmbedded,
  SnKv,
  SnMark,
  SnRow,
  SnSection,
  SnSheet,
  SnStat,
} from './parts';

// CompletionSet — a curated collecting goal and the arithmetic for how far along
// it is. "All Travis Scott x Nike", "every Chicago colourway", "my top 10 grails".
//
// THE ONE DECISION THAT SHAPES THIS BLOCK: membership is DATA, progress is
// DERIVED. Those are opposite answers to the same-looking question, so both are
// spelled out:
//
//   `products` is a curated linksToMany, NOT a query. A collecting set is not
//   "everything matching a rule": sneaker sets are emergent and personal, and
//   the user hand-confirms the list. Ordering is
//   meaningful. That is textbook curated membership, so it is a link.
//
//   `progress` / `ownedCount` / `missingProducts` are NOT stored and are NOT
//   fields. They are a rollup over CollectionItems intersected with this list:
//   the isolated view counts every CollectionItem in the set's realm, and
//   Calculate Completion counts the same or, given an `ownerId`, one owner's.
//   Storing them guarantees drift the moment a pair is bought or sold. The arithmetic ships as the exported pure function below so the app,
//   the card and any future consumer share ONE implementation instead of three
//   subtly different ones.

export type CompletionRule = 'own-any' | 'own-all';

export const COMPLETION_RULES = [
  {
    value: 'own-any',
    label: 'Own any variant',
  },
  {
    value: 'own-all',
    label: 'Own every variant',
  },
];

const CompletionRuleField = enumField(StringField, {
  options: COMPLETION_RULES,
  displayName: 'Completion Rule',
});

export interface CompletionResult {
  ownedCount: number;
  targetCount: number;
  /** 0–100, rounded. 0 when the set is empty — never NaN. */
  percent: number;
  /** Product ids in the set that the owner does not have. Order preserved. */
  missingProductIds: string[];
}

/** One owned copy: the product it is a copy of, and which variant it is. */
export interface OwnedCopy {
  productId: string;
  variant?: string | null;
}

/** A product in the set, with the variants `own-all` asks for. */
export interface SetProduct {
  id: string | undefined | null;
  variants?: (string | undefined | null)[] | null;
}

function normaliseVariant(variant: string | undefined | null): string {
  return (variant ?? '').trim().toLowerCase();
}

/**
 * The single implementation of set completion.
 *
 * Pure on purpose: it takes ids and variant labels rather than cards, so it
 * needs no store, no query and no realm — which is what lets the app, a command
 * and a test all call the same function. `owned` is whatever the caller's own
 * query resolved: one entry per CollectionItem in its scope.
 *
 * Under `own-any` a product is complete once any copy of it is owned. Under
 * `own-all` every one of the product's `availableVariants` must be owned; a
 * product that lists no variants has only the one, so any copy completes it.
 *
 * Guards the two cases that silently produce a wrong number rather than an error:
 * a set with no products (percent must be 0, not NaN from a divide-by-zero), and
 * dead link slots (a deleted product leaves an `undefined` in the array while
 * `.length` still counts it, so a raw length would inflate the denominator).
 */
export function computeCompletion(
  products: SetProduct[],
  owned: Iterable<OwnedCopy>,
  rule: CompletionRule | string | null | undefined = 'own-any',
): CompletionResult {
  let target = products.filter((p): p is SetProduct & { id: string } =>
    Boolean(p?.id),
  );
  let variantsOwned = new Map<string, Set<string>>();
  for (let copy of owned) {
    let seen = variantsOwned.get(copy.productId) ?? new Set<string>();
    seen.add(normaliseVariant(copy.variant));
    variantsOwned.set(copy.productId, seen);
  }
  let isComplete = (product: SetProduct & { id: string }) => {
    let seen = variantsOwned.get(product.id);
    if (!seen) {
      return false;
    }
    if (rule !== 'own-all') {
      return true;
    }
    let wanted = (product.variants ?? []).map(normaliseVariant).filter(Boolean);
    return wanted.every((variant) => seen.has(variant));
  };
  let missing = target.filter((p) => !isComplete(p)).map((p) => p.id);
  let ownedCount = target.length - missing.length;
  return {
    ownedCount,
    targetCount: target.length,
    percent:
      target.length === 0 ? 0 : Math.round((ownedCount / target.length) * 100),
    missingProductIds: missing,
  };
}

export class CompletionSet extends CardDef {
  static displayName = 'Completion Set';
  static icon = TargetArrowIcon;

  @field goal = contains(MarkdownField);
  @field coverImage = contains(ImageSourceField);

  // Curated membership. See the header note — this is deliberately a link.
  @field products = linksToMany(() => CollectibleProduct, { searchable: true });

  @field completionRule = contains(CompletionRuleField);
  @field isPublic = contains(BooleanField);

  // The DENOMINATOR is safe to store as a computed field: it depends only on this
  // card's own link array, not on any owner's collection. The numerator is not,
  // which is exactly why only one of the two lives here.
  @field targetCount = contains(NumberField, {
    computeVia: function (this: CompletionSet) {
      return (this.products ?? []).filter(Boolean).length;
    },
  });

  static isolated = class Isolated extends Component<typeof CompletionSet> {
    get realms() {
      let realmUrl = this.args.model?.[realmURL];
      return realmUrl ? [realmUrl.href] : [];
    }

    // The reverse query: every CollectionItem in the realm, intersected against
    // this set's curated product links below.
    //
    // A plain `type` filter, so it needs no `on:` anchor — that requirement
    // belongs to eq/contains/range filters, where an unanchored field path
    // resolves against CardDef and 500s. Worth stating because the obvious
    // "optimisation" here is to push the intersection into the query as
    // `eq: { 'item.id': ... }`, and THAT form does need the anchor.
    //
    // `isLive` so acquiring or selling a pair moves the percentage without a
    // reload — the number is only trustworthy if it cannot go stale.
    private itemsQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(CollectionItem);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );

    // Read `.instances` at the point of use and filter dead slots: a deleted
    // target leaves its slot in place, so a raw iteration renders an empty row
    // and a raw `.length` counts members that no longer exist.
    get ownedCopies(): OwnedCopy[] {
      let copies: OwnedCopy[] = [];
      for (let item of (this.itemsQuery?.instances ?? []) as CollectionItem[]) {
        let productId = item?.item?.id;
        if (productId) {
          copies.push({ productId, variant: item.variant });
        }
      }
      return copies;
    }

    get products(): CollectibleProduct[] {
      return ((this.args.model?.products ?? []) as CollectibleProduct[]).filter(
        Boolean,
      );
    }

    get result() {
      return computeCompletion(
        this.products.map((p) => ({
          id: p?.id,
          variants: p?.availableVariants,
        })),
        this.ownedCopies,
        this.args.model?.completionRule,
      );
    }

    get owned(): CollectibleProduct[] {
      let missing = new Set(this.result.missingProductIds);
      return this.products.filter((p) => p?.id && !missing.has(p.id));
    }

    get missing(): CollectibleProduct[] {
      let missing = new Set(this.result.missingProductIds);
      return this.products.filter((p) => !p?.id || missing.has(p.id));
    }

    // The query is absent when there is no `context` (some render modes have
    // none) and empty before it resolves. Those are different states and only
    // one of them should paint a "0% complete" claim.
    get isLoading() {
      return Boolean(this.itemsQuery?.isLoading);
    }

    <template>
      <SnSheet
        @title={{@model.cardTitle}}
        @src={{@model.coverImage.resolvedUrl}}
      >
        <:meta>{{metaLine @model}}</:meta>
        <:actions><Visibility @model={{@model}} /></:actions>
        <:stats>
          <SnStat
            @label='Owned'
            @value={{if
              this.isLoading
              '…'
              (ownedText this.result.ownedCount this.result.targetCount)
            }}
            @hint='linked products'
          />
          <SnStat
            @label='Rule'
            @value={{if (isAll @model) 'All' 'Any'}}
            @hint={{if
              (isAll @model)
              'every variant counts'
              'any variant counts'
            }}
          />
          <SnStat
            @label='Visibility'
            @value={{if @model.isPublic 'Public' 'Private'}}
            @hint={{if @model.isPublic 'on profile' 'only you'}}
          />
        </:stats>
        <:main>
          <SnSection @title='Goal'>
            {{#if @model.goal}}<@fields.goal />{{else}}—{{/if}}
          </SnSection>
          <SnSection @title='Products' @flush={{true}}>
            <SnKv>
              {{#each this.owned as |p|}}
                <SnRow @label={{p.cardTitle}}>{{p.colorway}}
                  <DotLabel @label='owned' @hue='green' /></SnRow>
              {{/each}}
              {{#each this.missing as |p|}}
                <SnRow @label={{p.cardTitle}}>{{p.colorway}}
                  <DotLabel @label='missing' @hue='amber' /></SnRow>
              {{/each}}
              {{#unless this.products.length}}
                <SnRow @label='Products'>—</SnRow>
              {{/unless}}
            </SnKv>
          </SnSection>
        </:main>
        <:side>
          <SnSection @title='Linked' @flush={{true}}>
            <LinkedRows @model={{@model}} @fields={{@fields}} />
          </SnSection>
          <SnSection @title='Details' @flush={{true}}>
            <SnKv>
              <DetailRows @model={{@model}} />
              <SnRow @label='Owned'>{{if
                  this.isLoading
                  '…'
                  this.result.ownedCount
                }}</SnRow>
              <SnRow @label='Still needed'>{{if
                  this.isLoading
                  '…'
                  this.result.missingProductIds.length
                }}</SnRow>
            </SnKv>
          </SnSection>
        </:side>
      </SnSheet>
    </template>
  };

  // Progress needs a query over the collection, so the compact formats show
  // only what the set itself stores.
  static embedded = class Embedded extends Component<typeof CompletionSet> {
    <template>
      <SnEmbedded
        @title={{@model.cardTitle}}
        @src={{@model.coverImage.resolvedUrl}}
      >
        <:meta>{{metaLine @model}}</:meta>
        <:status><Visibility @model={{@model}} /></:status>
        <:default>
          <SnKv><DetailRows @model={{@model}} /></SnKv>
          <LinkedRows @model={{@model}} @fields={{@fields}} />
        </:default>
      </SnEmbedded>
    </template>
  };

  static atom = class Atom extends Component<typeof CompletionSet> {
    <template>
      <SnAtom
        @title={{@model.cardTitle}}
        @src={{@model.coverImage.resolvedUrl}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof CompletionSet> {
    <template>
      <FitTile>
        <:avatar><SnMark
            @src={{@model.coverImage.resolvedUrl}}
            @size='lg'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Visibility @model={{@model}} /></:status>
        <:fact>{{productCount @model}} products</:fact>
      </FitTile>
    </template>
  };
}

const Visibility: TemplateOnlyComponent<{
  Args: { model: Partial<CompletionSet> };
}> = <template>
  <DotLabel
    @label={{if @model.isPublic 'public' 'private'}}
    @hue={{if @model.isPublic 'blue' 'slate'}}
  />
</template>;

// Rows (not a whole list) so the isolated Details can append the counts.
const DetailRows: TemplateOnlyComponent<{
  Args: { model: Partial<CompletionSet> };
}> = <template>
  <SnRow @label='Rule'>{{ruleLabel @model}}</SnRow>
  <SnRow @label='Visibility'>{{if @model.isPublic 'Public' 'Private'}}</SnRow>
  <SnRow @label='Products'>{{productCount @model}}</SnRow>
</template>;

const LinkedRows: TemplateOnlyComponent<{
  Args: { model: Partial<CompletionSet>; fields: any };
}> = <template>
  <SnKv>
    <SnRow @label='Products'>{{#if @model.products.length}}<@fields.products
          @format='atom'
          @displayContainer={{false}}
        />{{else}}—{{/if}}</SnRow>
  </SnKv>
</template>;

function isAll(m: Partial<CompletionSet>): boolean {
  return m.completionRule === 'own-all';
}

function ruleLabel(m: Partial<CompletionSet>): string {
  return (
    COMPLETION_RULES.find((r) => r.value === m.completionRule)?.label ??
    'Own any variant'
  );
}

function metaLine(m: Partial<CompletionSet>): string {
  return `${ruleLabel(m)} · ${m.isPublic ? 'public' : 'private'}`;
}

function productCount(m: Partial<CompletionSet>): number {
  return m.targetCount ?? 0;
}

function ownedText(owned: number, target: number): string {
  return `${owned} / ${target}`;
}

export default CompletionSet;
