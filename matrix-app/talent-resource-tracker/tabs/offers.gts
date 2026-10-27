import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { Grid } from '../../../ui-component/components/grid';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { REJECTION_REASON_LABELS } from '../../hr/rejection-reason-field';
import { daysBetween, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead } from '../shared';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class OffersTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setOffersView = (view: string) => {
    this.args.tracker.offersView = view as 'grid' | 'strip';
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
  ];

  get subtitle(): string {
    let n = this.expiringOfferCount;
    return n
      ? `Sorted by soonest to expire · ${n} expiring within 7 days`
      : 'Sorted by soonest to expire';
  }

  get panelMeta(): string {
    let n = this.args.tracker.offers.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'offer' : 'offers'}`;
  }

  get stats() {
    return [
      {
        label: 'Accept rate',
        value: this.acceptRateLabel,
        hint: 'Of decided offers',
      },
      {
        label: 'Median time to offer',
        value: this.medianTimeToOfferLabel,
        hint: 'Applied → offer extended',
      },
      {
        label: 'Top rejection reason',
        value: this.topRejectionReasonLabel,
        hint: 'Of rejected candidates',
      },
    ];
  }

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
    <PageScaffold
      @title='Offers'
      @subtitle={{this.subtitle}}
      @stats={{this.stats}}
    >
      <:default>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.offersSearch}}
            @placeholder='Search offers…'
            @label='Search offers'
            @onInput={{this.setOffersSearch}}
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.offersView}}
            @onValueChange={{this.setOffersView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Offers'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#let (component @context.searchResultsComponent) as |Search|}}
              <Search
                @query={{@tracker.offersSearchQuery}}
                @mode='none'
                as |results|
              >
                {{#if results.entries.length}}
                  <Grid
                    @items={{this.asEntries results.entries}}
                    @size={{if
                      (eq @tracker.offersView 'strip')
                      'double-wide-strip'
                      'regular-tile'
                    }}
                    as |entry Item|
                  >
                    <Item>
                      <div
                        class='tile'
                        role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                        tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                        {{on 'click' (fn @tracker.viewEntry entry.id)}}
                        {{on
                          'keydown'
                          (fn @tracker.viewEntryOnKeydown entry.id)
                        }}
                      >
                        <entry.component />
                      </div>
                    </Item>
                  </Grid>
                {{else}}
                  {{#if results.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No offers extended yet'
                    />{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          </:default>
        </Panel>
      </:default>
    </PageScaffold>
    <style scoped>
      .list-toolbar {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .list-toolbar > :last-child {
        margin-left: auto;
      }
      .tile {
        box-sizing: border-box;
        height: 100%;
        border-radius: var(--boxel-border-radius-lg);
        overflow: hidden;
        background: var(--card);
        box-shadow: var(--pretui-card-shadow, var(--shadow-xs));
        transition: box-shadow 0.15s ease-out;
      }
      .tile:hover,
      .tile:focus-within {
        /* a ring, not a border: a border would take 2px from the fitted
           card and drop it into the next smaller size tier */
        box-shadow:
          0 0 0 1px var(--primary-ink),
          var(--pretui-card-shadow, var(--shadow-xs));
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
    </style>
  </template>
}
