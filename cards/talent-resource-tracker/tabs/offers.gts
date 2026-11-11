import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
import { REJECTION_REASON_LABELS } from '../../hr/rejection-reason-field';
import { daysBetween, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import {
  ListToolbar,
  TrackerSection,
  TrackerEmpty,
  TrackerPage,
  type TrackerStat,
} from '../shared';

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
    // tracker.isLoading spans every query; only an empty offers list waits on it
    return this.args.tracker.isLoading && !n
      ? '—'
      : `${n} ${n === 1 ? 'offer' : 'offers'}`;
  }

  get stats(): TrackerStat[] {
    return [
      {
        label: 'Accept rate',
        dot: 'success',
        value: this.acceptRateLabel,
        hint: 'Of decided offers',
      },
      {
        label: 'Median time to offer',
        dot: 'info',
        value: this.medianTimeToOfferLabel,
        hint: 'Applied → offer extended',
      },
      {
        label: 'Top rejection reason',
        dot: 'destructive',
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
    return `${median} ${median === 1 ? 'day' : 'days'}`;
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
    <TrackerPage
      @group='Hiring'
      @title='Offers'
      @subtitle={{this.subtitle}}
      @stats={{this.stats}}
    >
      <:default>
        <ListToolbar
          @label='Offers'
          @searchValue={{@tracker.offersSearch}}
          @searchPlaceholder='Search offers…'
          @onSearch={{this.setOffersSearch}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.offersView}}
          @onView={{this.setOffersView}}
        />
        <TrackerSection
          @title='Offers'
          @meta={{this.panelMeta}}
          @padded={{true}}
        >
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
                      {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
                    >
                      <entry.component />
                    </div>
                  </Item>
                </Grid>
              {{else}}
                {{#if results.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No offers extended yet</TrackerEmpty>{{/if}}
              {{/if}}
            </Search>
          {{/let}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
      .tile {
        height: 100%;
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
    </style>
  </template>
}
