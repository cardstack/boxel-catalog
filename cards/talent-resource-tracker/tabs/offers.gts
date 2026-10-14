import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { REJECTION_REASON_LABELS } from '../../hr/rejection-reason-field';
import { daysBetween, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class OffersTab extends GlimmerComponent<Signature> {
  setOffersView = (view: 'grid' | 'strip') => {
    this.args.tracker.offersView = view;
  };

  setOffersSearch = (value: string) => {
    this.args.tracker.debouncedSetOffersSearch(value);
  };

  get acceptRateLabel(): string {
    let decided = this.args.tracker.offers.filter(
      (o) => o.status === 'accepted' || o.status === 'declined',
    );
    if (!decided.length) {
      return '—';
    }
    let accepted = decided.filter((o) => o.status === 'accepted').length;
    return `${Math.round((accepted / decided.length) * 100)}%`;
  }

  get medianTimeToOfferLabel(): string {
    let days = this.args.tracker.offers
      .filter((o) => o.candidate?.appliedDate && o.extendedDate)
      .map((o) =>
        daysBetween(
          toLocalDate(o.candidate!.appliedDate!),
          toLocalDate(o.extendedDate!),
        ),
      )
      .filter((d): d is number => d != null && d >= 0)
      .sort((a, b) => a - b);
    if (!days.length) {
      return '—';
    }
    let mid = Math.floor(days.length / 2);
    let median =
      days.length % 2 ? days[mid] : Math.round((days[mid - 1] + days[mid]) / 2);
    return `${median} days`;
  }

  get topRejectionReasonLabel(): string {
    let rejected = this.args.tracker.candidates.filter(
      (c) => c.status === 'rejected' && c.rejectionReason,
    );
    if (!rejected.length) {
      return '—';
    }
    let counts = new Map<string, number>();
    for (let c of rejected) {
      let reason = c.rejectionReason!;
      counts.set(reason, (counts.get(reason) ?? 0) + 1);
    }
    let [topReason, topCount] = [...counts.entries()].sort(
      (a, b) => b[1] - a[1],
    )[0];
    let label = REJECTION_REASON_LABELS[topReason] ?? topReason;
    return `${label} · ${topCount}/${rejected.length}`;
  }

  get expiringOfferCount(): number {
    let now = Date.now();
    let sevenDays = 7 * 24 * 60 * 60 * 1000;
    return this.args.tracker.offers.filter(
      (o) =>
        o.status === 'extended' &&
        o.expirationDate &&
        toLocalDate(o.expirationDate).getTime() - now <= sevenDays &&
        toLocalDate(o.expirationDate).getTime() - now >= 0,
    ).length;
  }

  <template>
    <div class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Offers</h2>
          <p class='byline'>Sorted by soonest to expire
            {{#if this.expiringOfferCount}}
              ·
              <span class='byline-bad'>{{this.expiringOfferCount}}
                expiring within 7 days</span>
            {{/if}}</p>
        </div>
      </div>
      <div class='stats-row'>
        <div class='stat-card'>
          <div class='stat-label'>Accept Rate</div>
          <div class='stat-value'>{{this.acceptRateLabel}}</div>
          <div class='stat-trend'>Of decided offers</div>
        </div>
        <div class='stat-card'>
          <div class='stat-label'>Median Time to Offer</div>
          <div class='stat-value'>{{this.medianTimeToOfferLabel}}</div>
          <div class='stat-trend'>Applied → offer extended</div>
        </div>
        <div class='stat-card'>
          <div class='stat-label'>Top Rejection Reason</div>
          <div class='stat-value stat-value-sm'>
            {{this.topRejectionReasonLabel}}
          </div>
          <div class='stat-trend'>Of rejected candidates</div>
        </div>
      </div>
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.offersSearch}}
            @placeholder='Search offers…'
            @onInput={{this.setOffersSearch}}
            aria-label='Search offers'
          />
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if (eq @tracker.offersView 'grid') 'primary' 'ghost'}}
            aria-pressed={{if (eq @tracker.offersView 'grid') 'true' 'false'}}
            @label='Grid view'
            {{on 'click' (fn this.setOffersView 'grid')}}
          ><LayoutGridIcon
              class='view-icon'
              width='16'
              height='16'
            /></IconButton>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if (eq @tracker.offersView 'strip') 'primary' 'ghost'}}
            aria-pressed={{if (eq @tracker.offersView 'strip') 'true' 'false'}}
            @label='List view'
            {{on 'click' (fn this.setOffersView 'strip')}}
          ><ListIcon class='view-icon' width='16' height='16' /></IconButton>
        </div>
      </div>
      {{#let (component @context.searchResultsComponent) as |Search|}}
        <Search @query={{@tracker.offersSearchQuery}} @mode='none' as |results|>
          <div
            class='tile-grid
              {{if (eq @tracker.offersView "strip") "strip-view"}}'
          >
            {{#each results.entries key='id' as |entry|}}
              <div
                class='tile
                  {{if (eq @tracker.offersView "strip") "strip-tile"}}'
                role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                {{on 'click' (fn @tracker.viewEntry entry.id)}}
                {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
              >
                <entry.component />
              </div>
            {{else}}
              {{#if results.isLoading}}
                <p class='empty-note' role='status'>Loading…</p>
              {{else}}
                <p class='empty-note' role='status'>No offers extended yet</p>
              {{/if}}
            {{/each}}
          </div>
        </Search>
      {{/let}}
    </div>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.25rem;
        margin: 0 0 0.1875rem;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 0.7188rem;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .byline-bad {
        color: color-mix(
          in oklch,
          var(--destructive) 38%,
          var(--card-foreground)
        );
        font-weight: 700;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .stats-row {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8.75rem, 1fr));
        gap: var(--boxel-sp);
      }
      .stat-card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        box-shadow: var(--shadow-xs);
      }
      .stat-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .stat-value {
        margin-top: var(--boxel-sp-4xs);
        font-family: var(--font-sans);
        font-size: 1.75rem;
        font-weight: 800;
        letter-spacing: -0.02em;
        line-height: 1;
        font-variant-numeric: tabular-nums;
        color: var(--card-foreground);
      }
      .stat-trend {
        margin-top: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--success-ink);
      }
      .stat-value-sm {
        font-size: 1.1rem;
      }
      .empty-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .tile-grid {
        margin-top: var(--boxel-sp);
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp);
      }
      .tile {
        border: 1px solid var(--border);
        border-radius: 1.25rem;
        overflow: hidden;

        height: 13.5rem;
        background: var(--card);
        box-shadow: var(--shadow-xs);
        transition:
          border-color 0.15s ease-out,
          box-shadow 0.15s ease-out;
      }
      .tile:hover {
        border-color: var(--primary-ink);
        box-shadow: var(--shadow-sm);
      }
      .tile:focus-within {
        border-color: var(--primary-ink);
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
      .tile-grid.strip-view {
        grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .tile.strip-tile {
        height: 4rem;
      }
      .list-toolbar {
        margin-top: var(--boxel-sp-lg);
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp);
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .view-toggle {
        display: flex;
        margin-left: auto;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        flex: none;
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
