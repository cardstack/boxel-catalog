import {
  CardDef,
  Component,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import { identifyCard, type getCards } from '@cardstack/runtime-common';

import { CollectionShell, type CollectionBadge } from '../collection-shell';
import { CollectionPanel } from '../collection-panel';
import { CollectionToolbar, type ToolbarBadge } from '../collection-toolbar';
import type { TableColumn } from '../table';
import { CollectibleProduct } from '../../cards/collectibles/collectible-product';

const COLUMNS: TableColumn[] = [
  { key: 'displayTitle', label: 'Product' },
  { key: 'colorway', label: 'Colorway' },
  { key: 'sku', label: 'SKU' },
];

class CollectionExampleIsolated extends Component<typeof CollectionExample> {
  private products: ReturnType<getCards> | undefined;
  @tracked search = '';
  @tracked badge = 'all';

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.products = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(CollectibleProduct);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  get realms(): string[] {
    let url = (this.args.model as any)?.[realmURL];
    return url ? [url.href] : [];
  }

  get productRef() {
    return identifyCard(CollectibleProduct) as
      | { module: string; name: string }
      | undefined;
  }

  get items(): CollectibleProduct[] {
    return (this.products?.instances ?? []) as CollectibleProduct[];
  }

  get shellBadges(): CollectionBadge[] {
    return [{ id: 'all', label: 'All', count: this.items.length }];
  }

  get toolbarBadges(): ToolbarBadge[] {
    let withSku = this.items.filter((p) => p.sku).length;
    return [
      { id: 'all', label: 'All', count: this.items.length },
      { id: 'sku', label: 'With SKU', count: withSku },
    ];
  }

  setSearch = (value: string) => {
    this.search = value;
  };

  setBadge = (id: string) => {
    this.badge = id;
  };

  open = (card: any) => {
    (this.args as any).viewCard?.(card, 'isolated');
  };

  <template>
    <article class='collection-example'>
      <header>
        <p class='kicker'>Collection components</p>
        <h1>{{@model.title}}</h1>
      </header>

      <section aria-labelledby='collection-shell-heading'>
        <h2 id='collection-shell-heading'>Collection Shell</h2>
        <CollectionShell
          @noun='products'
          @singular='Product'
          @cardTypeRef={{this.productRef}}
          @items={{this.items}}
          @realms={{this.realms}}
          @context={{@context}}
          @badges={{this.shellBadges}}
          @columns={{COLUMNS}}
          @onOpen={{this.open}}
        />
      </section>

      <section aria-labelledby='collection-panel-heading'>
        <h2 id='collection-panel-heading'>Collection Panel</h2>
        <CollectionPanel
          @cardClass={{CollectibleProduct}}
          @context={{@context}}
          @realms={{this.realms}}
          @columns={{COLUMNS}}
          @label='Products'
          @sortBy='sku'
          @allowCreate={{false}}
        />
      </section>

      <section aria-labelledby='collection-toolbar-heading'>
        <h2 id='collection-toolbar-heading'>Collection Toolbar</h2>
        <CollectionToolbar
          @search={{this.search}}
          @onSearch={{this.setSearch}}
          @placeholder='Search products'
          @badges={{this.toolbarBadges}}
          @activeBadge={{this.badge}}
          @onBadge={{this.setBadge}}
        />
      </section>
    </article>
    <style scoped>
      .collection-example {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-lg);
        background: var(--background);
        color: var(--foreground);
      }
      .kicker {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      h1 {
        margin: 0;
      }
      section {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      h2 {
        margin: 0;
        font-size: var(--boxel-font-size);
      }
    </style>
  </template>
}

/** Shows the three collection components over the catalog's Collectible Products. */
export class CollectionExample extends CardDef {
  static displayName = 'Collection Example';

  @field title = contains(StringField);

  static isolated = CollectionExampleIsolated;
}
