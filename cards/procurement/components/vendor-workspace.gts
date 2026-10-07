import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';

import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Stat } from '@cardstack/pretui/components/stat';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import type { Vendor } from '@cardstack/catalog/cards/procurement/vendor';
import { VendorQuote } from '../vendor-quote';
import {
  PurchaseOrder,
  PO_STATUS_LABELS,
  PO_STATUS_HUES,
} from '../purchase-order';
import { VendorProfile } from '../vendor-profile';

// Vendor Workspace — the buyer's 360° dossier ON one vendor (single-persona
// reinterpretation of the tracked concept: this is NOT a vendor-facing
// portal). Aggregates live realm data — the vendor's profile/compliance,
// their quotes, their POs and receipt states, win rate, and spend — via
// live queries rather than hand-maintained link arrays, so the dossier
// stays current as quotes and POs are created elsewhere.

interface Signature {
  Args: {
    vendor: Vendor | undefined;
    context?: any;
  };
  Element: HTMLElement;
}

export class VendorWorkspace extends GlimmerComponent<Signature> {
  private quoteList: ReturnType<getCards> | undefined;
  private poList: ReturnType<getCards> | undefined;
  private profileList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    this.quoteList = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(VendorQuote);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
    this.poList = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(PurchaseOrder);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
    this.profileList = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(VendorProfile);
        return ref ? { filter: { type: ref } } : undefined;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = (this.args.vendor as any)?.[realmURL];
    return url ? [url.href] : undefined;
  }

  private get vendorId(): string | undefined {
    return this.args.vendor?.id;
  }

  get quotes(): VendorQuote[] {
    let id = this.vendorId;
    if (!id) {
      return [];
    }
    return ((this.quoteList?.instances ?? []) as VendorQuote[]).filter((q) => {
      try {
        return q.vendor?.id === id;
      } catch {
        return false;
      }
    });
  }

  get pos(): PurchaseOrder[] {
    let id = this.vendorId;
    if (!id) {
      return [];
    }
    return ((this.poList?.instances ?? []) as PurchaseOrder[]).filter((po) => {
      try {
        return po.vendor?.id === id;
      } catch {
        return false;
      }
    });
  }

  get profile(): VendorProfile | undefined {
    let id = this.vendorId;
    if (!id) {
      return undefined;
    }
    return ((this.profileList?.instances ?? []) as VendorProfile[]).find(
      (p) => {
        try {
          return p.linkedVendor?.id === id;
        } catch {
          return false;
        }
      },
    );
  }

  get complianceKnown(): boolean {
    return Boolean(this.profile);
  }

  get complianceOk(): boolean {
    return Boolean(this.profile?.complianceOk);
  }

  get winRate(): string {
    let quotes = this.quotes.length;
    if (!quotes) {
      return '—';
    }
    let wins = this.pos.length;
    return `${Math.round((Math.min(wins, quotes) / quotes) * 100)}%`;
  }

  get spend(): string {
    let total = this.pos
      .filter((po) =>
        [
          'approved',
          'sent',
          'partially-received',
          'received',
          'closed',
        ].includes(po.status ?? ''),
      )
      .reduce((sum, po) => sum + (po.totalAmount ?? 0), 0);
    return formatMoney(total, 'USD');
  }

  poStatusLabel = (po: PurchaseOrder) =>
    PO_STATUS_LABELS[po.status ?? ''] ?? 'Draft';

  poStatusHue = (po: PurchaseOrder) =>
    PO_STATUS_HUES[po.status ?? 'draft'] ?? 'slate';

  totalOf = (record: PurchaseOrder | VendorQuote) => record.totalAmount ?? 0;

  <template>
    <div class='workspace' ...attributes>
      <div class='stats'>
        <Stat
          class='stat'
          @label='Quotes recorded'
          @value={{this.quotes.length}}
          @roll={{false}}
        />
        <Stat
          class='stat'
          @label='Win rate'
          @value={{this.winRate}}
          @roll={{false}}
        />
        <Stat
          class='stat'
          @label='Committed + spent'
          @value={{this.spend}}
          @roll={{false}}
        />
        <div class='stat compliance'>
          <span class='stat-label'>Compliance</span>
          {{#if this.complianceKnown}}
            <StatePill
              @label={{if this.complianceOk 'current' 'lapsed'}}
              @hue={{if this.complianceOk 'green' 'red'}}
              @dot={{true}}
            />
          {{else}}
            <StatePill @label='no profile' @hue='slate' @chrome={{true}} />
          {{/if}}
        </div>
      </div>

      <div class='cols'>
        <section class='col'>
          <h3>Purchase Orders</h3>
          {{#each this.pos as |po|}}
            <div class='mini-row'>
              <span class='mini-name'>{{po.poNumber}}</span>
              <Money class='mini-num' @amount={{this.totalOf po}} @code='USD' />
              <StatePill
                class='mini-status'
                @label={{this.poStatusLabel po}}
                @hue={{this.poStatusHue po}}
              />
            </div>
          {{else}}
            <EmptyState
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='No POs yet'
              @message='Purchase orders raised to this vendor appear here.'
            />
          {{/each}}
        </section>
        <section class='col'>
          <h3>Quotes</h3>
          {{#each this.quotes as |q|}}
            <div class='mini-row'>
              <span class='mini-name'>{{q.title}}</span>
              <Money class='mini-num' @amount={{this.totalOf q}} @code='USD' />
            </div>
          {{else}}
            <EmptyState
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='No quotes recorded'
              @message='Quotes this vendor sends against an RFQ appear here.'
            />
          {{/each}}
        </section>
      </div>
    </div>
    <style scoped>
      .workspace {
        display: grid;
        gap: var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .stat {
        --text-stat: 1.25rem;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-sm);
      }
      .compliance {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        align-items: flex-start;
      }
      .stat-label,
      h3 {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .cols {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp);
      }
      .col {
        min-width: 0;
      }
      h3 {
        margin: 0 0 var(--boxel-sp-xs);
      }
      .mini-row {
        display: grid;
        grid-template-columns: 1fr auto auto;
        gap: var(--boxel-sp-xs);
        align-items: baseline;
        padding: var(--boxel-sp-4xs) 0;
        border-bottom: 1px solid var(--border);
      }
      .mini-name {
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-family: var(--font-mono);
        font-size: 0.8125rem;
      }
      .mini-num {
        font-variant-numeric: tabular-nums;
      }
      .mini-status {
        justify-self: end;
      }
      @container (max-width: 560px) {
        .cols {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}
