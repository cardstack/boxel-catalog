import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
  getComponent,
  StringField,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import CalendarRangeIcon from '@cardstack/boxel-icons/calendar-range';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import { identifyCard } from '@cardstack/runtime-common';
import { eq } from '@cardstack/boxel-ui/helpers';

import { Employee } from './employee';
import { ScorecardField } from './scorecard-field';
import { ApprovalChainField } from './approval-chain-field';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { Chip } from '../../ui-component/components/chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import {
  BarList,
  type BarListItem,
} from '../../ui-component/components/bar-list';
import {
  Descriptions,
  type DescriptionsItem,
} from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import { Panel } from '../../ui-component/components/panel';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { Stat } from '../../ui-component/components/stat';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { QUIET_AVATAR_HUE, hueOf, stateColorsOf } from './hr-ui';
import { daysBetween } from './utils';

export const REVIEW_CYCLE_STATUSES = ['planned', 'active', 'closed'];

// Colocated with ReviewCycle — planned amber (upcoming, needs scheduling),
// active green (reviews are being written now), closed slate (archived).
export const REVIEW_CYCLE_STATUS_HUES: Record<string, Hue> = {
  planned: 'amber',
  active: 'green',
  closed: 'slate',
};

export const REVIEW_CYCLE_STATUS_COLORS = stateColorsOf(
  REVIEW_CYCLE_STATUS_HUES,
);

export const ReviewCycleStatusField = enumField(StringField, {
  options: REVIEW_CYCLE_STATUSES.map((status) => ({
    value: status,
    label: status,
  })),
  displayName: 'Review Cycle Status',
});

// The review's lifecycle mirrors its sign-off chain (see PerformanceReview's
// `status` computed): draft → in-review → signed-off.
export const REVIEW_STATUSES = ['draft', 'in-review', 'signed-off'];

export const REVIEW_STATUS_HUES: Record<string, Hue> = {
  draft: 'slate',
  'in-review': 'amber',
  'signed-off': 'green',
};

export const REVIEW_STATUS_COLORS = stateColorsOf(REVIEW_STATUS_HUES);

// "Aug 5, 2026", the date style of the other HR cards and the approval steps.
function shortDate(value?: Date | string | null): string | undefined {
  return toDate(value)?.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function periodLabel(
  start?: Date | string | null,
  end?: Date | string | null,
): string | undefined {
  let s = shortDate(start);
  let e = shortDate(end);
  if (!s && !e) {
    return undefined;
  }
  if (s && e) {
    return `${s} – ${e}`;
  }
  return s ?? e;
}

// "H2 2026 Review Cycle" → "H2 2026": the short name a stat or fact row has
// room for.
const CYCLE_SUFFIX_RE = /\s+(review cycle|reviews?)$/i;

export function cycleShort(name?: string | null): string {
  let n = name?.trim();
  return n ? n.replace(CYCLE_SUFFIX_RE, '') || n : '';
}

/** Whole days until a cycle ends; undefined once it has no end date or is closed. */
function daysLeft(cycle?: ReviewCycle): number | undefined {
  if (!cycle?.periodEnd || cycle.status === 'closed') {
    return undefined;
  }
  return daysBetween(new Date(), cycle.periodEnd);
}

/** Share of the cycle's period already gone, 0–100; undefined without both dates. */
function elapsedPct(cycle?: ReviewCycle): number | undefined {
  let total = daysBetween(cycle?.periodStart, cycle?.periodEnd);
  if (!total) {
    return undefined;
  }
  let gone = daysBetween(cycle?.periodStart) ?? 0;
  return Math.min(100, Math.round((gone / total) * 100));
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`;
}

// A named review period ("H2 2026 Reviews") that PerformanceReviews attach
// to via linksTo — the cycle itself does NOT hold a linksToMany of reviews;
// the app lists a cycle's reviews via a live query, so late-added reviews
// appear without touching the cycle card.
export class ReviewCycle extends CardDef {
  static displayName = 'Review Cycle';
  static icon = CalendarRangeIcon;

  @field name = contains(StringField, {
    description: 'Cycle name, e.g. "H2 2026 Reviews"',
  });
  @field periodStart = contains(DateField);
  @field periodEnd = contains(DateField);
  @field status = contains(ReviewCycleStatusField);
  @field description = contains(TextAreaField);

  @field title = contains(StringField, {
    computeVia: function (this: ReviewCycle) {
      return this.name?.trim() || 'Unnamed Cycle';
    },
  });

  // Stack header renders cardTitle (base fallback "Untitled <type>" when
  // cardInfo.name is unset) — route it through our computed title.
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ReviewCycle) {
      return this.cardInfo?.name?.trim() || this.title;
    },
  });

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof this
  > {
    get realms(): string[] {
      let url = this.args.model?.[realmURL]?.href;
      return url ? [url] : [];
    }

    // The cycle's reviews, live: a review links to its cycle, never the
    // other way round. `identifyCard(PerformanceReview)` runs only inside
    // this callback, after the module (and that class) has evaluated.
    reviewsQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(PerformanceReview);
        let id = this.args.model?.id;
        return ref && id
          ? { filter: { on: ref, every: [{ eq: { 'cycle.id': id } }] } }
          : undefined;
      },
      () => this.realms,
      { isLive: true },
    );

    get reviews(): PerformanceReview[] {
      return (this.reviewsQuery?.instances ?? []).filter(
        Boolean,
      ) as PerformanceReview[];
    }

    get reviewCount(): string {
      return plural(this.reviews.length, 'review', 'reviews');
    }

    get signedOffCount(): number {
      return this.reviews.filter((r) => r.status === 'signed-off').length;
    }

    get inReviewCount(): number {
      return this.reviews.filter((r) => r.status === 'in-review').length;
    }

    get period(): string | undefined {
      return periodLabel(
        this.args.model?.periodStart,
        this.args.model?.periodEnd,
      );
    }

    get daysLeft(): number | undefined {
      return daysLeft(this.args.model as ReviewCycle);
    }

    get endsLabel(): string | undefined {
      let end = shortDate(this.args.model?.periodEnd);
      return end ? `ends ${end}` : undefined;
    }

    get details(): DescriptionsItem[] {
      let m = this.args.model;
      let items: DescriptionsItem[] = [];
      if (this.period) {
        items.push({ label: 'Period', value: this.period });
      }
      items.push(
        { label: 'Reviews', value: String(this.reviews.length) },
        { label: 'Signed off', value: String(this.signedOffCount) },
        { label: 'In review', value: String(this.inReviewCount) },
      );
      if (this.daysLeft != null) {
        items.push({ label: 'Days left', value: String(this.daysLeft) });
      }
      if (m?.status) {
        items.push({ label: 'Status', value: m.status });
      }
      return items;
    }

    <template>
      <article class='cycle-isolated'>
        <header class='iso-head'>
          <Avatar
            @name='Review Cycle'
            @hue={{QUIET_AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            {{#if this.period}}
              <p class='iso-sub'>{{this.period}}</p>
            {{/if}}
          </div>
          <div class='chips'>
            {{#if @model.status}}
              <StatePill
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
                @dot={{true}}
              />
            {{/if}}
            <StatePill @label={{this.reviewCount}} />
          </div>
        </header>

        <div class='stat-row'>
          <Panel class='stat-tile'>
            <Stat
              @label='Reviews'
              @value={{this.reviews.length}}
              @hint='{{this.signedOffCount}} signed off'
            />
          </Panel>
          <Panel class='stat-tile'>
            <Stat
              @label='Period'
              @value={{cycleShort @model.name}}
              @hint={{this.period}}
              @roll={{false}}
            />
          </Panel>
          {{#if this.daysLeft}}
            <Panel class='stat-tile'>
              <Stat
                @label='Days left'
                @value={{this.daysLeft}}
                @hint={{this.endsLabel}}
              />
            </Panel>
          {{/if}}
        </div>

        <div class='iso-body'>
          <div class='iso-col'>
            {{#if @model.description}}
              <Panel @title='About this cycle'>
                <p class='iso-text'>{{@model.description}}</p>
              </Panel>
            {{/if}}
            <Panel @title='Reviews'>
              {{#if this.reviews.length}}
                <ul class='review-list'>
                  {{#each this.reviews as |review|}}
                    <li>
                      {{#let (getComponent review) as |ReviewCard|}}
                        <ReviewCard @format='atom' />
                      {{/let}}
                      <span class='row-sub'>{{reviewScoreLine review}}</span>
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='iso-muted'>No reviews link to this cycle yet.</p>
              {{/if}}
            </Panel>
          </div>
          <div class='iso-col'>
            <Panel @title='Details'>
              <Descriptions @items={{this.details}} @columns={{1}} @size='sm' />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .cycle-isolated {
            min-height: 100%;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            padding: var(--boxel-sp-lg);
            background: var(--background);
            color: var(--foreground);
            container-type: inline-size;
          }
          .iso-head {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 0;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary);
            overflow-wrap: anywhere;
          }
          .iso-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
            font-variant-numeric: tabular-nums;
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            gap: var(--boxel-sp-lg);
            align-items: start;
          }
          .iso-col {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .iso-text {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
            white-space: pre-line;
          }
          .iso-muted {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .review-list {
            list-style: none;
            margin: 0;
            padding: 0;
          }
          .review-list li {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-6xs);
            padding: var(--boxel-sp-sm) 0;
            border-top: 1px solid var(--border);
          }
          .review-list li:first-child {
            border-top: 0;
            padding-top: 0;
          }
          .review-list li:last-child {
            padding-bottom: 0;
          }
          .row-sub {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          @container (width < 45rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof this
  > {
    get period(): string | undefined {
      return periodLabel(
        this.args.model?.periodStart,
        this.args.model?.periodEnd,
      );
    }

    get daysLeft(): number | undefined {
      return daysLeft(this.args.model as ReviewCycle);
    }

    get details(): DescriptionsItem[] {
      let m = this.args.model;
      let items: DescriptionsItem[] = [];
      if (this.period) {
        items.push({ label: 'Period', value: this.period });
      }
      if (this.daysLeft != null) {
        items.push({ label: 'Days left', value: String(this.daysLeft) });
      }
      if (m?.status) {
        items.push({ label: 'Status', value: m.status });
      }
      return items;
    }

    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar
            @name='Review Cycle'
            @hue={{QUIET_AVATAR_HUE}}
            @size={{40}}
            aria-hidden='true'
          />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.title}}</h3>
            {{#if this.period}}
              <p class='emb-sub'>{{this.period}}</p>
            {{/if}}
          </div>
          {{#if @model.status}}
            <div class='emb-chips'>
              <StatePill
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
                @dot={{true}}
              />
            </div>
          {{/if}}
        </header>
        {{#if @model.description}}
          <p class='emb-fact'>{{@model.description}}</p>
        {{/if}}
        {{#if this.details.length}}
          <Descriptions
            class='emb-kv'
            @items={{this.details}}
            @columns={{3}}
            @layout='vertical'
            @size='sm'
          />
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            container-type: inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            color: var(--foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            overflow-wrap: anywhere;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            font-variant-numeric: tabular-nums;
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            justify-content: flex-end;
            gap: var(--boxel-sp-4xs);
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
            display: -webkit-box;
            -webkit-box-orient: vertical;
            -webkit-line-clamp: 2;
            overflow: hidden;
          }
          .emb-kv {
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
          }
          @container (width < 25rem) {
            .emb-head {
              flex-wrap: wrap;
            }
            .emb-chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof this
  > {
    get period(): string | undefined {
      return periodLabel(
        this.args.model?.periodStart,
        this.args.model?.periodEnd,
      );
    }

    get daysLeft(): number | undefined {
      return daysLeft(this.args.model as ReviewCycle);
    }

    get fact(): string | undefined {
      let end = shortDate(this.args.model?.periodEnd);
      if (this.daysLeft != null && end) {
        return `${plural(this.daysLeft, 'day', 'days')} left · ends ${end}`;
      }
      return end ? `Ended ${end}` : undefined;
    }

    get elapsed(): number | undefined {
      return elapsedPct(this.args.model as ReviewCycle);
    }

    get facts(): DescriptionsItem[] {
      let m = this.args.model;
      let items: DescriptionsItem[] = [];
      if (this.period) {
        items.push({ label: 'Period', value: this.period });
      }
      if (this.daysLeft != null) {
        items.push({ label: 'Days left', value: String(this.daysLeft) });
      }
      if (m?.status) {
        items.push({ label: 'Status', value: m.status });
      }
      return items;
    }

    // FitTile carries who / state / fact at every size; from 170 tall the
    // block below it adds the mockup's extra rows, each shown only where a
    // whole row fits (see the container queries).
    <template>
      <div class='fit-wrap'>
        <FitTile class='fit-top'>
          <:avatar>
            <Avatar
              @name='Review Cycle'
              @hue={{QUIET_AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              class='fit-title'
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{this.period}}</:subtitle>
          <:status>
            {{#if @model.status}}
              <StatePill
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
                @dot={{true}}
              />
            {{/if}}
          </:status>
          <:fact>{{this.fact}}</:fact>
        </FitTile>
        <div class='fit-more'>
          <dl class='fit-stats'>
            <div><dt>Period</dt><dd>{{cycleShort @model.name}}</dd></div>
            <div><dt>Days left</dt><dd>{{if
                  this.daysLeft
                  this.daysLeft
                  '—'
                }}</dd></div>
            <div><dt>Elapsed</dt><dd>{{if
                  this.elapsed
                  this.elapsed
                  0
                }}%</dd></div>
          </dl>
          {{#if this.elapsed}}
            <ProgressBar
              class='fit-bar'
              @value={{this.elapsed}}
              @max={{100}}
              @label='Period elapsed'
              @count='{{this.elapsed}}%'
            />
          {{/if}}
          {{#if this.facts.length}}
            <dl class='fit-kv'>
              {{#each this.facts as |item|}}
                <div class='kv-i'><dt>{{item.label}}</dt><dd
                  >{{item.value}}</dd></div>
              {{/each}}
            </dl>
          {{/if}}
        </div>
      </div>
      <style scoped>
        @layer PretComponent {
          .fit-wrap {
            block-size: 100%;
            display: flex;
            flex-direction: column;
            overflow: hidden;
          }
          .fit-wrap > .fit-top {
            flex: none;
            block-size: auto;
            padding-block-end: 0;
          }
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .fit-more {
            display: none;
            flex-direction: column;
            gap: var(--boxel-sp-xs);
            min-height: 0;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-xs);
            line-height: 1.5;
            color: var(--muted-foreground);
          }
          .fit-stats,
          .fit-bar {
            display: none;
          }
          .fit-stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
            margin: 0;
          }
          .fit-stats div {
            min-width: 0;
          }
          .fit-stats dd {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            color: var(--primary);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            font-variant-numeric: tabular-nums;
          }
          .fit-kv {
            display: grid;
            grid-template-columns: minmax(0, 1fr);
            gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .kv-i {
            display: flex;
            justify-content: space-between;
            gap: var(--boxel-sp-xs);
            min-width: 0;
          }
          .kv-i:nth-child(n + 2) {
            display: none;
          }
          .kv-i dt {
            flex: none;
          }
          .kv-i dd {
            margin: 0;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            text-align: right;
            font-weight: 600;
            color: var(--foreground);
            font-variant-numeric: tabular-nums;
          }
          @container fitted-card (height >= 170px) {
            .fit-more {
              display: flex;
            }
          }
          @container fitted-card (height >= 170px) and (width >= 400px) {
            .fit-kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .kv-i:nth-child(-n + 3) {
              display: flex;
            }
          }
          @container fitted-card (height >= 250px) {
            .kv-i:nth-child(-n + 3) {
              display: flex;
            }
          }
          @container fitted-card (height >= 275px) and (width >= 400px) {
            .fit-bar {
              display: grid;
            }
          }
          @container fitted-card (height >= 400px) {
            .fit-stats {
              display: grid;
            }
            .fit-kv {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<typeof this> {
    <template>
      <span class='cycle-atom'>
        <CalendarRangeIcon class='atom-icon' />
        <span class='atom-name'>{{@model.title}}</span>
        {{#if @model.status}}
          <StatePill
            @label={{@model.status}}
            @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
          />
        {{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .cycle-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-icon {
            flex: none;
            width: var(--boxel-icon-xs);
            height: var(--boxel-icon-xs);
            color: var(--muted-foreground);
          }
          .atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };
}

// ── PerformanceReview helpers (plain functions, callable from templates) ──

/** Approved steps over all steps of the sign-off chain, "2 of 2"; undefined with no chain. */
function signOffProgress(review?: Partial<PerformanceReview>): string {
  let steps = review?.signOff?.steps ?? [];
  if (!steps.length) {
    return '';
  }
  let approved = steps.filter((s) => s?.decision === 'approved').length;
  return `${approved} of ${steps.length}`;
}

interface ReviewFactParts {
  lead: string;
  strong?: string;
  tail?: string;
}

/** The fact row: when it was signed off, or how far sign-off has got. */
function reviewFactParts(
  review?: Partial<PerformanceReview>,
): ReviewFactParts | undefined {
  let progress = signOffProgress(review);
  if (!progress) {
    return review ? { lead: 'No sign-off chain yet' } : undefined;
  }
  if (review?.status === 'signed-off') {
    let steps = review.signOff?.steps ?? [];
    let filed = shortDate(steps[steps.length - 1]?.decidedAt);
    return { lead: 'Signed off', strong: filed, tail: `· ${progress}` };
  }
  return { lead: `Sign-off ${progress} approved` };
}

/** "Reviewer Marcus Webb · H2 2026 Review Cycle" */
function reviewSubline(
  review?: Partial<PerformanceReview>,
): string | undefined {
  let parts = [
    review?.reviewerName ? `Reviewer ${review.reviewerName}` : undefined,
    review?.cycleName || undefined,
  ].filter(Boolean);
  return parts.length ? parts.join(' · ') : undefined;
}

/** "Reviewer Marcus Webb · 4.3 / 5", the line under a review in a cycle's list. */
function reviewScoreLine(review?: Partial<PerformanceReview>): string {
  return [
    review?.reviewerName ? `Reviewer ${review.reviewerName}` : undefined,
    review?.scoreLabel || 'Not scored yet',
  ]
    .filter(Boolean)
    .join(' · ');
}

const REVIEW_STATUS_TONES: Record<string, PretuiToneArg> = {
  draft: 'neutral',
  'in-review': 'warning',
  'signed-off': 'success',
};

export function statusTone(status?: string | null): PretuiToneArg {
  return (status && REVIEW_STATUS_TONES[status]) || 'neutral';
}

// "signed-off" → "Signed-Off", the label every format prints.
export function statusLabel(status?: string | null): string {
  return (status ?? '').replace(
    /(^|-)([a-z])/g,
    (_m, sep: string, c: string) => sep + c.toUpperCase(),
  );
}

/** Score chip tone: success from 4, warning from 3, danger below. */
function scoreTone(avg?: number | null): PretuiToneArg {
  if (typeof avg !== 'number') {
    return 'neutral';
  }
  return avg >= 4 ? 'success' : avg >= 3 ? 'warning' : 'danger';
}

function outOfFive(score?: number | null): string {
  return typeof score === 'number' ? `${score} / 5` : '—';
}

/** Score, each criterion, sign-off and cycle; `full` adds reviewer and filed date. */
function reviewFacts(
  review?: Partial<PerformanceReview>,
  full = false,
): DescriptionsItem[] {
  if (!review) {
    return [];
  }
  let items: DescriptionsItem[] = [];
  if (review.scoreLabel) {
    items.push({ label: 'Score', value: review.scoreLabel });
  }
  for (let c of review.scorecard?.criteria ?? []) {
    if (c?.name) {
      items.push({ label: c.name, value: outOfFive(c.score) });
    }
  }
  let progress = signOffProgress(review);
  if (progress) {
    items.push({ label: 'Sign-off', value: `${progress} approved` });
  }
  let cycle = cycleShort(review.cycleName);
  if (cycle) {
    items.push({ label: 'Cycle', value: cycle });
  }
  if (full) {
    if (review.reviewerName) {
      items.push({ label: 'Reviewer', value: review.reviewerName });
    }
    if (review.status === 'signed-off') {
      let steps = review.signOff?.steps ?? [];
      let filed = shortDate(steps[steps.length - 1]?.decidedAt);
      if (filed) {
        items.push({ label: 'Filed', value: filed });
      }
    }
  }
  return items;
}

// The record's type mark: a square, not an Avatar, because a review is not
// a person. Knobs: `--review-mark-size`, `--review-mark-font-size`.
const ReviewMark: TemplateOnlyComponent<{ Element: HTMLSpanElement }> =
  <template>
    <span class='review-mark' aria-hidden='true' ...attributes>Rv</span>
    <style scoped>
      @layer PretComponent {
        .review-mark {
          display: inline-grid;
          flex: none;
          place-items: center;
          inline-size: var(--review-mark-size, 2rem);
          block-size: var(--review-mark-size, 2rem);
          border-radius: calc(var(--radius) - 2px);
          background: var(--card);
          box-shadow: inset 0 0 0 1px var(--border);
          color: var(--primary-ink);
          font-size: var(--review-mark-font-size, var(--boxel-font-size-xs));
          font-weight: 600;
          line-height: 1;
        }
      }
    </style>
  </template>;

// Sign-off status and score as soft pills, the one chip set the isolated and
// embedded formats print.
const ReviewChips: TemplateOnlyComponent<{
  Args: { model?: Partial<PerformanceReview> };
  Element: HTMLDivElement;
}> = <template>
  <div class='review-chips' ...attributes>
    {{#if @model.status}}<Chip
        @tone={{statusTone @model.status}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >{{statusLabel @model.status}}</Chip>{{/if}}
    {{#if @model.scoreLabel}}<Chip
        @tone={{scoreTone @model.scorecard.averageScore}}
        @appearance='soft'
        @shape='pill'
        @dot={{false}}
      >{{@model.scoreLabel}}</Chip>{{/if}}
  </div>
  <style scoped>
    @layer PretComponent {
      .review-chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
    }
  </style>
</template>;

// "Signed off Aug 5, 2026 · 2 of 2", the date set in the foreground ink.
// Knobs: `--review-fact-strong-weight`, `--review-fact-strong-color`.
const ReviewFact: TemplateOnlyComponent<{
  Args: { fact?: ReviewFactParts };
  Element: HTMLParagraphElement;
}> = <template>
  <p class='review-fact' ...attributes>{{@fact.lead}}
    {{#if @fact.strong}}<strong>{{@fact.strong}}</strong>{{/if}}
    {{@fact.tail}}</p>
  <style scoped>
    @layer PretComponent {
      .review-fact strong {
        font-weight: var(--review-fact-strong-weight, 600);
        color: var(--review-fact-strong-color, var(--foreground));
      }
    }
  </style>
</template>;

// The labels every PerformanceReview format shares, so isolated, embedded,
// fitted and atom never print the same fact two ways.
class ReviewView extends Component<typeof PerformanceReview> {
  get statusTone(): PretuiToneArg {
    return statusTone(this.args.model?.status);
  }
  get scoreTone(): PretuiToneArg {
    return scoreTone(this.args.model?.scorecard?.averageScore);
  }
  get subline(): string | undefined {
    return reviewSubline(this.args.model as PerformanceReview);
  }
  get fact(): ReviewFactParts | undefined {
    return reviewFactParts(this.args.model as PerformanceReview);
  }
  get facts(): DescriptionsItem[] {
    return reviewFacts(this.args.model as PerformanceReview);
  }
  get fullFacts(): DescriptionsItem[] {
    return reviewFacts(this.args.model as PerformanceReview, true);
  }
}

// A point-in-time review of one employee within one cycle. The SECOND
// consumer of ScorecardField (after Meeting's interview scorecard — its
// criteria become review dimensions like "Delivery" or "Collaboration") and
// the FIFTH of ApprovalChainField (the employee-acknowledge + HR-approve
// sign-off chain).
export class PerformanceReview extends CardDef {
  static displayName = 'Performance Review';
  static icon = ClipboardCheckIcon;

  // One-directional by design — a deliberate live-query choice over a
  // linksToMany back-reference on Employee, matching PtoRequest's employee link.
  @field employee = linksTo(() => Employee);
  @field reviewer = linksTo(() => Employee);
  @field cycle = linksTo(() => ReviewCycle);
  // Reused UNCHANGED from scorecard-field.gts — criteria + recommendation +
  // averageScore, exactly as Meeting consumes it.
  @field scorecard = contains(ScorecardField);
  @field selfAssessment = contains(TextAreaField);
  @field managerSummary = contains(TextAreaField);
  // Reused UNCHANGED from approval-chain-field.gts: step 0 is the employee's
  // own acknowledgement, step 1 HR's approval.
  @field signOff = contains(ApprovalChainField);

  // draft (no sign-off chain yet) → in-review (chain configured but not
  // fully approved — includes a rejected/sent-back chain, which loops back
  // into review) → signed-off.
  @field status = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      if (!this.signOff?.steps?.length) {
        return 'draft';
      }
      return this.signOff.status === 'approved' ? 'signed-off' : 'in-review';
    },
  });

  // Denormalized for fitted — prerendered fitted does not resolve linksTo.
  @field employeeName = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      return this.employee?.name ?? '';
    },
  });

  @field reviewerName = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      return this.reviewer?.name ?? '';
    },
  });

  @field cycleName = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      return this.cycle?.name ?? '';
    },
  });

  // Denormalized score label — fitted-safe scalar derived from the
  // scorecard's own computed average. '' (not undefined) when unscored so
  // the tile row hides cleanly.
  @field scoreLabel = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      let avg = this.scorecard?.averageScore;
      return typeof avg === 'number' ? `${avg} / 5` : '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      let name = this.employeeName?.trim() || 'Unassigned review';
      let cycle = this.cycleName?.trim();
      return cycle ? `${name} — ${cycle}` : name;
    },
  });

  // Stack header renders cardTitle (base fallback "Untitled <type>" when
  // cardInfo.name is unset) — route it through our computed title.
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PerformanceReview) {
      return this.cardInfo?.name?.trim() || this.title;
    },
  });

  static isolated: BaseDefComponent = class Isolated extends ReviewView {
    get scoreRows(): BarListItem[] {
      return (this.args.model?.scorecard?.criteria ?? [])
        .filter((c) => c?.name && typeof c.score === 'number')
        .map((c) => ({ name: c.name as string, value: c.score as number }));
    }

    get criteriaHint(): string | undefined {
      let n = this.scoreRows.length;
      return n ? plural(n, 'criterion', 'criteria') : undefined;
    }

    get filedHint(): string | undefined {
      let m = this.args.model as PerformanceReview | undefined;
      if (m?.status !== 'signed-off') {
        return undefined;
      }
      let steps = m.signOff?.steps ?? [];
      let filed = shortDate(steps[steps.length - 1]?.decidedAt);
      return filed ? `filed ${filed}` : undefined;
    }

    get cyclePeriod(): string | undefined {
      let cycle = this.args.model?.cycle;
      return periodLabel(cycle?.periodStart, cycle?.periodEnd);
    }

    get links(): DescriptionsItem[] {
      let m = this.args.model;
      return [
        m?.employee ? { label: 'Employee' } : undefined,
        m?.reviewer ? { label: 'Reviewer' } : undefined,
        m?.cycle ? { label: 'Cycle' } : undefined,
      ].filter(Boolean) as DescriptionsItem[];
    }

    <template>
      <article class='review-isolated'>
        <header class='iso-head'>
          <ReviewMark class='iso-mark' />
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            {{#if this.subline}}
              <p class='iso-sub'>{{this.subline}}</p>
            {{/if}}
          </div>
          <ReviewChips @model={{@model}} />
        </header>

        <div class='stat-row'>
          <Panel class='stat-tile'>
            <Stat
              @label='Average score'
              @value={{if @model.scoreLabel @model.scoreLabel ''}}
              @hint={{this.criteriaHint}}
              @roll={{false}}
            />
          </Panel>
          <Panel class='stat-tile'>
            <Stat
              @label='Sign-off'
              @value={{signOffProgress @model}}
              @hint={{this.filedHint}}
              @roll={{false}}
            />
          </Panel>
          <Panel class='stat-tile'>
            <Stat
              @label='Cycle'
              @value={{cycleShort @model.cycleName}}
              @hint={{this.cyclePeriod}}
              @roll={{false}}
            />
          </Panel>
        </div>

        <div class='iso-body'>
          <div class='iso-col'>
            <Panel @title='Scorecard'>
              {{#if this.scoreRows.length}}
                <BarList
                  @rows={{this.scoreRows}}
                  @max={{5}}
                  @ranked={{false}}
                  @format={{outOfFive}}
                  @label='Scorecard'
                />
              {{else}}
                <p class='iso-muted'>Not scored yet.</p>
              {{/if}}
            </Panel>
            {{#if @model.managerSummary}}
              <Panel @title='Manager summary'>
                <p class='iso-text'>{{@model.managerSummary}}</p>
              </Panel>
            {{/if}}
            {{#if @model.selfAssessment}}
              <Panel @title='Self assessment'>
                <p class='iso-text'>{{@model.selfAssessment}}</p>
              </Panel>
            {{/if}}
            <Panel @title='Sign-off'>
              <@fields.signOff @format='embedded' />
            </Panel>
          </div>
          <div class='iso-col'>
            {{#if this.links.length}}
              <Panel @title='Linked'>
                <Descriptions @items={{this.links}} @columns={{1}} @size='sm'>
                  <:value as |item|>
                    {{#if (eq item.label 'Employee')}}
                      <@fields.employee
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else if (eq item.label 'Reviewer')}}
                      <@fields.reviewer
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{else}}
                      <@fields.cycle
                        @format='atom'
                        @displayContainer={{false}}
                      />
                    {{/if}}
                  </:value>
                </Descriptions>
              </Panel>
            {{/if}}
            <Panel @title='Details'>
              <Descriptions
                @items={{reviewFacts @model true}}
                @columns={{1}}
                @size='sm'
              />
            </Panel>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .review-isolated {
            min-height: 100%;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            padding: var(--boxel-sp-lg);
            background: var(--background);
            color: var(--foreground);
            container-type: inline-size;
          }
          .iso-head {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: var(--boxel-sp);
          }
          .iso-mark {
            --review-mark-size: 3rem;
            --review-mark-font-size: var(--boxel-font-size-sm);
          }
          .iso-id {
            flex: 1 1 0;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary);
            overflow-wrap: anywhere;
          }
          .iso-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
            gap: var(--boxel-sp-lg);
            align-items: start;
          }
          .iso-col {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .iso-text {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
            white-space: pre-line;
          }
          .iso-muted {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          @container (width < 45rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends ReviewView {
    <template>
      <article class='review-embedded'>
        <header class='emb-head'>
          <ReviewMark />
          <div class='emb-id'>
            <h3 class='emb-title'>{{@model.title}}</h3>
            {{#if this.subline}}
              <p class='emb-sub'>{{this.subline}}</p>
            {{/if}}
          </div>
          <ReviewChips class='emb-chips' @model={{@model}} />
        </header>
        <ReviewFact class='emb-fact' @fact={{this.fact}} />
        {{#if this.facts.length}}
          <dl class='emb-kv'>
            {{#each this.facts as |f|}}
              <div><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
            {{/each}}
          </dl>
        {{/if}}
        <div class='emb-rels'>
          {{#if @model.employee}}
            <span class='rel'>Employee
              <@fields.employee @format='atom' @displayContainer={{false}} />
            </span>
          {{/if}}
          {{#if @model.reviewer}}
            <span class='rel'>Reviewer
              <@fields.reviewer @format='atom' @displayContainer={{false}} />
            </span>
          {{/if}}
          {{#if @model.cycle}}
            <span class='rel'>Cycle
              <@fields.cycle @format='atom' @displayContainer={{false}} />
            </span>
          {{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .review-embedded {
            container-type: inline-size;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp);
            background-color: var(--card);
            color: var(--card-foreground);
          }
          .emb-head {
            display: flex;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 0;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.25;
            overflow-wrap: anywhere;
          }
          .emb-sub {
            margin: var(--boxel-sp-6xs) 0 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            justify-content: flex-end;
          }
          .emb-fact {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm) var(--boxel-sp);
            margin: 0;
            padding-top: var(--boxel-sp-sm);
            border-top: 1px solid var(--border);
            font-size: var(--boxel-font-size-xs);
          }
          .emb-kv > div {
            min-inline-size: 0;
          }
          .emb-kv dt {
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-rels:empty {
            display: none;
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            max-width: 100%;
            min-width: 0;
          }
          @container (max-width: 25rem) {
            .emb-kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
            .emb-head {
              flex-wrap: wrap;
            }
            .emb-chips {
              flex-basis: 100%;
              justify-content: flex-start;
            }
          }
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends ReviewView {
    <template>
      <article class='fit'>
        <header class='who'>
          {{! the record's type mark, not a person: a square, not an Avatar }}
          <span class='mark' aria-hidden='true'>Rv</span>
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              <span class='chips chips-inline'>
                {{#if @model.status}}<Chip
                    @tone={{this.statusTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{statusLabel @model.status}}</Chip>{{/if}}
                {{#if @model.scoreLabel}}<Chip
                    class='chip-score'
                    @tone={{this.scoreTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  >{{@model.scoreLabel}}</Chip>{{/if}}
              </span>
            </div>
            <p class='sub'>{{this.subline}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          {{#if @model.status}}<Chip
              @tone={{this.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{statusLabel @model.status}}</Chip>{{/if}}
          {{#if @model.scoreLabel}}<Chip
              class='chip-score'
              @tone={{this.scoreTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            >{{@model.scoreLabel}}</Chip>{{/if}}
        </span>
        <ReviewFact class='fact' @fact={{this.fact}} />
        <dl class='stats'>
          <div><dt>Average score</dt><dd>{{if
                @model.scoreLabel
                @model.scoreLabel
                '—'
              }}</dd></div>
          <div><dt>Sign-off</dt><dd>{{if
                (signOffProgress @model)
                (signOffProgress @model)
                '—'
              }}</dd></div>
          <div><dt>Cycle</dt><dd>{{if
                (cycleShort @model.cycleName)
                (cycleShort @model.cycleName)
                '—'
              }}</dd></div>
        </dl>
        <dl class='kv'>
          {{#each this.fullFacts as |f|}}
            <div class='kv-i'><dt>{{f.label}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <ul class='rels'>
          {{#if @model.employee}}
            <li><span class='k'>Employee</span><@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#if @model.reviewer}}
            <li><span class='k'>Reviewer</span><@fields.reviewer
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
          {{#if @model.cycle}}
            <li><span class='k'>Cycle</span><@fields.cycle
                @format='atom'
                @displayContainer={{false}}
              /></li>
          {{/if}}
        </ul>
      </article>
      <style scoped>
        @layer PretComponent {
          /* off-ladder gaps from the IMS rule (8 / 4 / 2); type reads the
             ladder, set here so a host's font-size never leaks in */
          .fit {
            --_fit-gap: 0.5rem;
            --_fit-gap-tight: 0.25rem;
            --_fit-hair: 0.125rem;

            display: flex;
            flex-direction: column;
            gap: var(--_fit-gap);
            block-size: 100%;
            box-sizing: border-box;
            padding: var(--boxel-sp-sm);
            overflow: hidden;
            font-size: var(--boxel-font-size-sm);
            line-height: 1.5;
          }
          .fit > * {
            flex: none;
            min-inline-size: 0;
            margin: 0;
          }
          .who {
            display: flex;
            align-items: flex-start;
            gap: var(--boxel-sp-sm);
            min-inline-size: 0;
          }
          .mark {
            display: none;
            flex: none;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: inset 0 0 0 1px var(--border);
            color: var(--primary-ink);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .id {
            display: flex;
            flex: 1 1 auto;
            flex-direction: column;
            gap: var(--_fit-hair);
            min-inline-size: 0;
          }
          .line1 {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
          }
          .title {
            flex: 1 1 auto;
            min-inline-size: 7rem;
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
          }
          .title,
          .sub,
          .fact,
          .kv dd,
          .stats dt,
          .stats dd {
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
          }
          .sub {
            margin: 0;
          }
          .sub,
          .fact,
          .kv,
          .stats,
          .rels {
            font-size: var(--boxel-font-size-xs);
          }
          .sub,
          .fact,
          .k,
          .kv dt,
          .stats dt {
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            gap: var(--_fit-gap-tight);
            min-inline-size: 0;
            overflow: hidden;
          }
          .chips > * {
            flex: none;
          }
          .chips-inline,
          .chip-score,
          .stats,
          .kv,
          .rels .k {
            display: none;
          }
          .chips-inline {
            flex: none;
          }
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--boxel-sp-sm);
            margin: 0;
          }
          .stats dd {
            margin: 0;
            font-size: var(--boxel-font-size);
            font-weight: 600;
            color: var(--primary);
            font-variant-numeric: tabular-nums;
          }
          /* as many rows as fit the space left; rows past the bottom get
             zero height, so none shows half */
          .kv {
            flex: 1 1 0;
            grid-template-columns: minmax(0, 1fr);
            grid-template-rows: repeat(auto-fill, 1.125rem);
            grid-auto-rows: 0;
            gap: var(--_fit-gap-tight) var(--boxel-sp-sm);
            min-block-size: 0;
            margin: 0;
            overflow: hidden;
          }
          .kv-i {
            display: flex;
            justify-content: space-between;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            overflow: hidden;
          }
          .kv dt {
            flex: none;
          }
          .kv dd {
            margin: 0;
            font-weight: 600;
            text-align: end;
            font-variant-numeric: tabular-nums;
          }
          /* a link that doesn't fit wraps into a second column, which the
             overflow clips, so no row ever shows half */
          .rels {
            display: flex;
            flex: 1 1 0;
            flex-flow: column wrap;
            align-content: flex-start;
            min-block-size: 0;
            max-block-size: 1.375rem;
            gap: var(--_fit-gap-tight);
            margin: 0;
            padding: 0;
            list-style: none;
            overflow: hidden;
          }
          .rels li {
            display: flex;
            align-items: center;
            gap: var(--_fit-gap);
            min-inline-size: 0;
            flex: none;
            inline-size: 100%;
            block-size: 1.375rem;
            overflow: hidden;
            line-height: 1.375rem;
          }
          .rels .k {
            flex: none;
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the type mark shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: grid;
            }
          }
          /* the score chip joins the status from 250 wide */
          @container fitted-card (width >= 250px) {
            .chip-score {
              display: inline-flex;
            }
          }
          /* relations name their link from 250 wide and 170 tall */
          @container fitted-card (width >= 250px) and (height >= 170px) {
            .rels .k {
              display: inline;
            }
          }
          @container fitted-card (width <= 150px) {
            .fact {
              --review-fact-strong-weight: inherit;
              --review-fact-strong-color: inherit;
            }
          }
          /* 400 wide: state moves beside the title */
          @container fitted-card (width >= 400px) {
            .chips-inline {
              display: flex;
            }
            .chips-row {
              display: none;
            }
          }
          /* under 170 tall: tight rows */
          @container fitted-card (height < 170px) {
            .fit {
              gap: var(--_fit-gap-tight);
              padding: var(--_fit-gap) var(--boxel-sp-sm);
            }
          }
          /* 105 – 169 tall, under 400 wide: no relations line */
          @container fitted-card (height < 170px) and (width < 400px) {
            .rels {
              display: none;
            }
          }
          /* 105 – 169 tall, 400 wide: the relations are one line of atoms */
          @container fitted-card (height < 170px) and (width >= 400px) {
            .rels {
              flex-flow: row wrap;
            }
            .rels li {
              inline-size: auto;
              max-inline-size: 100%;
            }
          }
          /* 170 – 249 tall: one relation, two from 400 wide */
          @container fitted-card (height >= 170px) and (height < 250px) and (width >= 400px) {
            .rels {
              max-block-size: 3.125rem;
            }
          }
          @container fitted-card (height >= 250px) {
            .rels {
              max-block-size: 3.125rem;
            }
          }
          /* 275 tall: all three relations keep their rows, the facts get
             the space left */
          @container fitted-card (height >= 275px) {
            .rels {
              flex: none;
              max-block-size: 4.875rem;
            }
          }
          /* under 105 tall: who only, state beside the title from 250 wide */
          @container fitted-card (height < 105px) {
            .chips-row,
            .fact,
            .rels {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width >= 250px) {
            .chips-inline {
              display: flex;
            }
          }
          /* a pill strip under 400 wide keeps the status only */
          @container fitted-card (height < 105px) and (width < 400px) {
            .chip-score {
              display: none;
            }
          }
          /* 250 wide under 65 tall: status only beside the title */
          @container fitted-card (height < 65px) {
            .sub,
            .chip-score {
              display: none;
            }
          }
          @container fitted-card (height < 65px) and (width < 250px) {
            .chips-inline {
              display: none;
            }
          }
          /* 250 tall: roomier padding and a larger mark; under 250 wide the
             mark stacks above the name */
          @container fitted-card (height >= 250px) {
            .fit {
              padding: var(--boxel-sp);
            }
            .mark {
              inline-size: 2.5rem;
              block-size: 2.5rem;
              font-size: var(--boxel-font-size-sm);
            }
          }
          @container fitted-card (height >= 250px) and (width < 250px) {
            .who {
              flex-direction: column;
              gap: var(--_fit-gap);
            }
            .id {
              align-self: stretch;
            }
          }
          /* 275 tall and 250 wide: the remaining facts fill the space left */
          @container fitted-card (height >= 275px) and (width >= 250px) {
            .kv {
              display: grid;
            }
          }
          @container fitted-card (height >= 275px) and (height < 400px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
          }
          /* 400 tall: the score, sign-off and cycle stats lead */
          @container fitted-card (height >= 400px) {
            .stats {
              display: grid;
            }
          }
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends ReviewView {
    <template>
      <span class='review-atom'>
        <ReviewMark class='atom-mark' />
        <span class='review-atom-name'>{{@model.title}}</span>
        {{#if @model.status}}<Chip
            @tone={{this.statusTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          >{{statusLabel @model.status}}</Chip>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .review-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            vertical-align: middle;
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .atom-mark {
            --review-mark-size: 1.25rem;
            --review-mark-font-size: var(--boxel-font-size-2xs);
          }
          .review-atom-name {
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
        }
      </style>
    </template>
  };
}
