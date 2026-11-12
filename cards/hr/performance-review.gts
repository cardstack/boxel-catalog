import { markDefinition } from '@cardstack/base/mark-definition';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
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
import { DotLabel, dotEnumField } from './dot-enum-field';
import CalendarRangeIcon from '@cardstack/boxel-icons/calendar-range';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';
import { identifyCard } from '@cardstack/runtime-common';
import { eq } from '@cardstack/boxel-ui/helpers';

import { Employee } from './employee';
import { ScorecardField } from './scorecard-field';
import { ApprovalChainField } from './approval-chain-field';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '@cardstack/pretui/components/avatar';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import {
  BarList,
  type BarListItem,
} from '@cardstack/pretui/components/bar-list';
import {
  Descriptions,
  type DescriptionsItem,
} from '@cardstack/pretui/components/descriptions';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { QUIET_AVATAR_HUE, hueOf, stateColorsOf } from './hr-ui';
import { daysBetween } from './utils';
import { EmbCard, IsoHead, IsoPage, Kv, kv, Panel, Sheet, SheetLine, SheetRows, SheetSection, SheetStat, StatStrip, type StripItem } from '../shared/compact-sheet';
import { IsoFrame } from '../shared/compact-sheet';

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

export const ReviewCycleStatusField = markDefinition(
  dotEnumField(
    {
      options: REVIEW_CYCLE_STATUSES.map((status) => ({
        value: status,
        label: status,
      })),
      displayName: 'Review Cycle Status',
    },
    REVIEW_CYCLE_STATUS_HUES,
  ),
);

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
      <IsoFrame>
        <Sheet
          class='cycle-isolated'
          @title={{@model.title}}
          @meta={{this.period}}
        >
          <:mark><Avatar
              @name='Review Cycle'
              @hue={{QUIET_AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            /></:mark>
          <:aside>{{#if @model.status}}
              <StatePill
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
                @dot={{true}}
              />
            {{/if}}
            <StatePill @label={{this.reviewCount}} /></:aside>
          <:default>

            <SheetSection @label='Summary'>
              <SheetStat
                @label='Reviews'
                @value={{this.reviews.length}}
                @hint='{{this.signedOffCount}} signed off'
              />
              <SheetStat
                @label='Period'
                @value={{cycleShort @model.name}}
                @hint={{this.period}}
              />
              {{#if this.daysLeft}}
                <SheetStat
                  @label='Days left'
                  @value={{this.daysLeft}}
                  @hint={{this.endsLabel}}
                />
              {{/if}}
            </SheetSection>

            <div class='iso-body'>
              <div class='iso-col'>
                {{#if @model.description}}
                  <SheetSection @label='About this cycle'>
                    <p class='iso-text'>{{@model.description}}</p>
                  </SheetSection>
                {{/if}}
                <SheetSection @label='Reviews'>
                  {{#if this.reviews.length}}
                    <ul class='review-list'>
                      {{#each this.reviews as |review|}}
                        <li>
                          {{#let (getComponent review) as |ReviewCard|}}
                            <ReviewCard @format='atom' />
                          {{/let}}
                          <span class='row-sub'>{{reviewScoreLine
                              review
                            }}</span>
                        </li>
                      {{/each}}
                    </ul>
                  {{else}}
                    <p class='iso-muted'>No reviews link to this cycle yet.</p>
                  {{/if}}
                </SheetSection>
              </div>
              <div class='iso-col'>
                <SheetSection @label='Details'>
                  <SheetRows @items={{this.details}} />
                </SheetSection>
              </div>
            </div>
          </:default>
        </Sheet>
      </IsoFrame>
      <style scoped>
        @layer PretComponent {
          .cycle-isolated {
            background: var(--card);
            color: var(--card-foreground);
            border: 1px solid var(--border);
            border-radius: var(--radius);
            min-height: 100%;
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-lg);
            padding: var(--boxel-sp-lg);
            color: var(--card-foreground);
            container-type: inline-size;
          }
          h1 {
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
            color: var(--primary-ink);
            overflow-wrap: break-word;
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
        /* the body wrappers flow straight into the Sheet's one card */
        .iso-body,
        .iso-col {
          display: contents;
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
              <DotLabel
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
              />
            </div>
          {{/if}}
        </header>
        {{#if @model.description}}
          <p class='emb-fact'>{{@model.description}}</p>
        {{/if}}
        {{#if this.details.length}}
          <Descriptions
            class='emb-kv kv-pad'
            @items={{this.details}}
            @columns={{3}}
            @layout='vertical'
            @size='s'
          />
        {{/if}}
      </article>
      <style scoped>
        .kv-pad {
          padding-inline: var(--boxel-sp-sm);
        }

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
            overflow-wrap: break-word;
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

    // RichFittedCard carries who / state / fact at every size; from 170 tall the
    // block below it adds the mockup's extra rows, each shown only where a
    // whole row fits (see the container queries).
    <template>
      <div class='fit-wrap'>
        <RichFittedCard class='fit-top'>
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
              <DotLabel
                @label={{@model.status}}
                @hue={{hueOf REVIEW_CYCLE_STATUS_HUES @model.status}}
              />
            {{/if}}
          </:status>
          <:fact>{{this.fact}}</:fact>
        </RichFittedCard>
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
            {{! Wrapper carries the hide/show rule; see offer.gts. }}
            <div class='fit-bar'><ProgressBar
                @value={{this.elapsed}}
                @max={{100}}
                @label='Period elapsed'
                @count='{{this.elapsed}}%'
              /></div>
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
            color: var(--primary-ink);
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
          <DotLabel
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

// The labels every PerformanceReview format shares, so isolated, embedded,
// fitted and atom never print the same fact two ways.
// A tone as the DotLabel hue.
function toneHue(tone?: string) {
  return (
    tone === 'success'
      ? 'green'
      : tone === 'danger'
        ? 'red'
        : tone === 'warning'
          ? 'amber'
          : tone === 'info'
            ? 'blue'
            : 'slate'
  ) as 'green' | 'red' | 'amber' | 'blue' | 'slate';
}

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

    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        {
          label: 'Average score',
          value: m?.scoreLabel || '—',
          hint: this.criteriaHint,
          tone: 'success',
        },
        {
          label: 'Sign-off',
          value:
            signOffProgress(m as PerformanceReview).replace(' of ', ' / ') ||
            '—',
          hint: this.filedHint,
          tone: 'success',
        },
        {
          label: 'Cycle',
          value: cycleShort(m?.cycleName),
          hint: this.cyclePeriod,
          tone: 'info',
        },
      ];
    }
    get linkRows() {
      return this.links.map((l) => ({ key: String(l.label), value: '' }));
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{this.subline}}>
            <:mark><ReviewMark /></:mark>
            <:aside>{{#if @model.status}}<DotLabel
                  @label={{@model.status}}
                  @hue={{toneHue this.statusTone}}
                />{{/if}}</:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Scorecard' @meta={{this.criteriaHint}}>
            {{#if this.scoreRows.length}}
              <SheetLine><BarList
                  class='bars'
                  @rows={{this.scoreRows}}
                  @max={{5}}
                  @ranked={{false}}
                  @format={{outOfFive}}
                  @label='Scorecard'
                /></SheetLine>
            {{else}}
              <SheetLine><span class='muted'>Not scored yet.</span></SheetLine>
            {{/if}}
          </Panel>
          {{#if @model.managerSummary}}
            <Panel @title='Manager summary'><SheetLine><span
                  class='prose'
                >{{@model.managerSummary}}</span></SheetLine></Panel>
          {{/if}}
          {{#if @model.selfAssessment}}
            <Panel @title='Self assessment'><SheetLine><span
                  class='prose'
                >{{@model.selfAssessment}}</span></SheetLine></Panel>
          {{/if}}
          <Panel @title='Sign-off'><@fields.signOff
              @format='embedded'
            /></Panel>
        </:main>
        <:aside>
          {{#if this.links.length}}
            <Panel @title='Linked'>
              <Kv @items={{this.linkRows}}>
                <:value as |item|>
                  {{#if (eq item.key 'Employee')}}
                    <@fields.employee
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq item.key 'Reviewer')}}
                    <@fields.reviewer
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else}}
                    <@fields.cycle @format='atom' @displayContainer={{false}} />
                  {{/if}}
                </:value>
              </Kv>
            </Panel>
          {{/if}}
          <Panel @title='Details'><Kv @items={{kv this.fullFacts}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .bars {
          flex: 1;
          min-width: 0;
        }
        .muted {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .prose {
          white-space: pre-line;
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends ReviewView {
    get rows() {
      return [...kv(this.facts), { key: 'Employee', value: '' }];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.subline}}>
        <:mark><ReviewMark /></:mark>
        <:aside>{{#if @model.status}}<DotLabel
              @label={{@model.status}}
              @hue={{toneHue this.statusTone}}
            />{{/if}}</:aside>
        <:default>
          <Kv @items={{this.rows}}>
            <:value as |row|>{{#if (eq row.key 'Employee')}}{{#if
                  @model.employee
                }}<@fields.employee
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}{{else}}{{row.value}}{{/if}}</:value>
          </Kv>
        </:default>
      </EmbCard>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends ReviewView {
    get strip(): StripItem[] {
      let m = this.args.model;
      return [
        { label: 'Score', value: m?.scoreLabel || '—' },
        {
          label: 'Sign-off',
          value:
            signOffProgress(m as PerformanceReview).replace(' of ', ' / ') ||
            '—',
        },
        { label: 'Cycle', value: cycleShort(m?.cycleName) },
      ];
    }
    <template>
      <RichFittedCard>
<:avatar><ReviewMark /></:avatar>
<:title>{{@model.title}}</:title>
<:status>{{#if @model.status}}<DotLabel
              @label={{@model.status}}
              @hue={{toneHue this.statusTone}}
            />{{/if}}</:status>
<:subtitle><span
              class='meta'
            >{{this.subline}}</span></:subtitle>
<:metric>{{#let (get this.strip 0) as |s|}}{{#if s}}<Metric @value={{s.value}} @label={{s.label}} />{{/if}}{{/let}}</:metric>
<:details>
          
          <Detail @label='Score'>{{if
              @model.scoreLabel
              @model.scoreLabel
              '—'
            }}</Detail>
          <Detail @label='Sign-off'>{{signOffProgress @model}}</Detail>
          {{#if @model.employee}}
            <Detail @label='Employee'><@fields.employee
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}
          {{#if @model.cycle}}
            <Detail @label='Cycle'><@fields.cycle
                @format='atom'
                @displayContainer={{false}}
              /></Detail>
          {{/if}}
          
          {{#each this.fullFacts as |f|}}
            <Detail @label={{f.label}}>{{f.value}}</Detail>
          {{/each}}
        </:details>
</RichFittedCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends ReviewView {
    <template>
      <span class='review-atom'>
        <ReviewMark class='atom-mark' />
        <span class='review-atom-name'>{{@model.title}}</span>
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
