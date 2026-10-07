import {
  CardDef,
  Component,
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import UrlField from '@cardstack/base/url';
import EmailField from '@cardstack/base/email';
import BuildingIcon from '@cardstack/boxel-icons/building';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from '@cardstack/catalog/cards/hr/duration-field';
import { durationInDays } from '@cardstack/catalog/cards/hr/duration-field';
import { Money } from '@cardstack/catalog/cards/hr/hr-ui';
import {
  AVATAR_HUE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';
import {
  StatePill,
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

// One row of a vendor's rate card. A containsMany of these rather than a
// free-text blob: role→rate pairs are the thing a staffing conversation
// actually queries ("what does TalentBridge charge for a senior QE?"), and
// structured rows can be compared against what a contractor bills.
export class RateCardEntryField extends FieldDef {
  static displayName = 'Rate Card Entry';

  @field role = contains(StringField, {
    description: 'Role or seniority band, e.g. "Senior Backend Engineer"',
  });
  @field hourlyRate = contains(NumberField, {
    description: 'Billable hourly rate in dollars',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='rate-entry'>
        <span class='rate-role'>{{if @model.role @model.role 'Any role'}}</span>
        <span class='rate-amount'><Money
            @amount={{@model.hourlyRate}}
          />/hr</span>
      </span>
      <style scoped>
        .rate-entry {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
        }
        .rate-role {
          min-width: 0;
          overflow-wrap: anywhere;
        }
        .rate-amount {
          flex: none;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = RateCardEntryField.embedded;
}

// Contract lifecycle colours. The state is DERIVED — a contract is "expiring"
// when its computed end date falls inside the renewal window — so the palette
// keys on that derivation rather than on a persisted status field.
export const VENDOR_CONTRACT_HUES: Record<string, Hue> = {
  upcoming: 'slate',
  active: 'teal',
  expiring: 'amber',
  expired: 'red',
};

export const VENDOR_CONTRACT_COLORS: Record<string, StateColor> =
  Object.fromEntries(
    Object.entries(VENDOR_CONTRACT_HUES).map(([k, hue]) => [
      k,
      stateColor(hue),
    ]),
  );

const RENEWAL_WINDOW_MONTHS = 6;
const MAX_STARS = 5;

interface ContractShape {
  contractStart?: Date | null;
  contractLength?: { value?: number | null; unit?: string | null } | null;
}

// Shared by isolated and fitted so the two formats can never disagree about
// what state a contract is in, or when it ends.
function contractFacts(model: ContractShape) {
  let start = model.contractStart ? new Date(model.contractStart) : undefined;
  if (start && isNaN(start.getTime())) {
    start = undefined;
  }
  let days = durationInDays(
    model.contractLength?.value,
    model.contractLength?.unit,
  );
  let end: Date | undefined;
  if (start && days != null) {
    end = new Date(start.getTime());
    end.setDate(end.getDate() + Math.round(days));
  }
  // Classify on the unrounded difference and round only for display: a
  // contract that ended days ago rounds to -0 months, which is not < 0.
  let rawMonths = end
    ? (end.getTime() - Date.now()) / (1000 * 60 * 60 * 24 * 30)
    : undefined;
  let monthsLeft = rawMonths == null ? undefined : Math.round(rawMonths);
  let state = 'upcoming';
  if (start && start.getTime() > Date.now()) {
    state = 'upcoming';
  } else if (rawMonths != null) {
    state =
      rawMonths < 0
        ? 'expired'
        : rawMonths <= RENEWAL_WINDOW_MONTHS
          ? 'expiring'
          : 'active';
  } else if (start) {
    state = 'active';
  }
  return { start, end, monthsLeft, state };
}

export class Vendor extends CardDef {
  static displayName = 'Vendor';
  static icon = BuildingIcon;

  @field name = contains(StringField);
  @field contactName = contains(StringField);
  @field email = contains(EmailField);
  @field website = contains(UrlField);
  @field serviceCategory = contains(StringField, {
    description: 'e.g. staffing agency, payroll, freelance design',
  });
  @field contractStart = contains(DateField);
  @field contractLength = contains(DurationField);
  @field performanceRating = contains(ScoreField);
  @field rateCard = containsMany(RateCardEntryField);
  @field agreementTerms = contains(TextAreaField, {
    description: 'Key commercial terms: payment schedule, notice, exclusivity',
  });
  @field spendYtd = contains(NumberField, {
    description: 'Total spend with this vendor year-to-date, in dollars',
  });

  @field title = contains(StringField, {
    computeVia: function (this: Vendor) {
      return this.name?.trim() || 'Unnamed Vendor';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get avatarName(): string {
      return this.args.model?.title ?? 'Vendor';
    }

    get facts() {
      return contractFacts(this.args.model ?? {});
    }

    get contractHue(): Hue {
      return VENDOR_CONTRACT_HUES[this.facts.state] ?? 'slate';
    }

    get contractStateLabel() {
      switch (this.facts.state) {
        case 'expired':
          return 'Contract ended';
        case 'expiring':
          return 'Contract active';
        case 'upcoming':
          return 'Not started';
        default:
          return 'Contract active';
      }
    }

    // Second pill: the countdown. Only shown when there is an end date to
    // count toward, so an open-ended contract renders one pill, not a blank.
    get expiryLabel() {
      let { monthsLeft, state } = this.facts;
      if (monthsLeft == null) {
        return undefined;
      }
      if (state === 'expired') {
        let ago = Math.abs(monthsLeft);
        return ago === 0 ? 'Ended this month' : `Ended ${ago} mo ago`;
      }
      if (monthsLeft === 0) {
        return 'Ends this month';
      }
      return `${monthsLeft} mo to renewal`;
    }

    get contractEndLabel() {
      let { end } = this.facts;
      return end ? end.toISOString().slice(0, 10) : undefined;
    }

    get ratingLabel() {
      let v = this.args.model?.performanceRating;
      return typeof v === 'number' ? `${v} / ${MAX_STARS}` : undefined;
    }

    contractRows: KeyValueItem[] = [
      { key: 'Service', value: 'service' },
      { key: 'Starts', value: 'start' },
      { key: 'Length', value: 'length' },
      { key: 'Projected end', value: 'end' },
      { key: 'Performance', value: 'performance' },
      { key: 'Spend YTD', value: 'spend' },
    ];

    contactRows: KeyValueItem[] = [
      { key: 'Contact', value: 'contact' },
      { key: 'Email', value: 'email' },
      { key: 'Website', value: 'website' },
    ];

    // One getter rather than branching in the template — keeps the template
    // free of helper imports and puts the wording next to the logic.
    get renewalNote() {
      let { state } = this.facts;
      let left = this.expiryLabel;
      if (!left) {
        return undefined;
      }
      if (state === 'expired') {
        return 'This contract has ended. Confirm no work is still in flight before archiving the vendor.';
      }
      if (state === 'expiring') {
        return `Inside the ${RENEWAL_WINDOW_MONTHS}-month renewal window — ${left}. Check any project depending on this vendor before renewing.`;
      }
      return `${left}. No action needed yet.`;
    }

    <template>
      <article class='vendor-isolated'>
        <header class='hero'>
          <Avatar
            class='avatar'
            @name={{this.avatarName}}
            @hue={{AVATAR_HUE}}
          />
          <div class='hero-text'>
            <h1>{{@model.title}}</h1>
            <p class='byline'>
              {{#if @model.serviceCategory}}{{@model.serviceCategory}}{{/if}}
              {{#if @model.contractLength.label}}
                <span class='sep-dot'>&middot;</span>
                {{@model.contractLength.label}}
                contract
              {{/if}}
            </p>
            <div class='pill-row'>
              <StatePill
                @label={{this.contractStateLabel}}
                @hue={{this.contractHue}}
                @dot={{true}}
              />
              {{#if this.expiryLabel}}
                <StatePill
                  @label={{this.expiryLabel}}
                  @hue={{this.contractHue}}
                  @dot={{true}}
                />
              {{/if}}
            </div>
          </div>
          {{#if this.ratingLabel}}
            <div class='hero-rating'>
              <@fields.performanceRating />
              <span class='rating-num'>Performance {{this.ratingLabel}}</span>
            </div>
          {{/if}}
        </header>

        <div class='body'>
          <div class='main'>
            <h2 class='panel-title'>Contract</h2>
            <KeyValue
              class='facts'
              @items={{this.contractRows}}
              @labelStyle='eyebrow'
            >
              <:value as |row|>
                {{#if (eq row.value 'service')}}
                  {{if @model.serviceCategory @model.serviceCategory '—'}}
                {{else if (eq row.value 'start')}}
                  {{#if @model.contractStart}}<@fields.contractStart
                    />{{else}}&mdash;{{/if}}
                {{else if (eq row.value 'length')}}
                  {{if
                    @model.contractLength.label
                    @model.contractLength.label
                    '—'
                  }}
                {{else if (eq row.value 'end')}}
                  {{#if this.contractEndLabel}}
                    {{this.contractEndLabel}}
                    {{#if this.expiryLabel}}
                      <span class='dd-note'>&middot; {{this.expiryLabel}}</span>
                    {{/if}}
                  {{else}}
                    &mdash;
                  {{/if}}
                {{else if (eq row.value 'performance')}}
                  {{if this.ratingLabel this.ratingLabel '— not yet rated'}}
                {{else}}
                  <Money @amount={{@model.spendYtd}} />
                {{/if}}
              </:value>
            </KeyValue>

            <h2 class='panel-title spaced'>Rate card</h2>
            {{#if @model.rateCard.length}}
              <ul class='rate-card'>
                {{#each @fields.rateCard as |Entry|}}
                  <li><Entry
                      @format='embedded'
                      @displayContainer={{false}}
                    /></li>
                {{/each}}
              </ul>
            {{else}}
              <EmptyState
                @title='No rate card on file'
                @message='Rates are negotiated per engagement.'
                @texture={{false}}
                style={{COMPACT_EMPTY_STYLE}}
              />
            {{/if}}

            <h2 class='panel-title spaced'>Agreement terms</h2>
            {{#if @model.agreementTerms}}
              <p class='prose'>{{@model.agreementTerms}}</p>
            {{else}}
              <EmptyState
                @title='No agreement terms recorded'
                @texture={{false}}
                style={{COMPACT_EMPTY_STYLE}}
              />
            {{/if}}
          </div>

          <aside class='side'>
            <h2 class='panel-title'>Contact</h2>
            <KeyValue
              class='facts'
              @items={{this.contactRows}}
              @layout='stacked'
              @labelStyle='eyebrow'
            >
              <:value as |row|>
                {{#if (eq row.value 'contact')}}
                  {{if @model.contactName @model.contactName '—'}}
                {{else if (eq row.value 'email')}}
                  {{if @model.email @model.email '—'}}
                {{else}}
                  {{#if @model.website}}<@fields.website
                    />{{else}}&mdash;{{/if}}
                {{/if}}
              </:value>
            </KeyValue>

            {{#if this.renewalNote}}
              <h2 class='panel-title spaced'>Renewal</h2>
              <p class='side-note'>{{this.renewalNote}}</p>
            {{/if}}
          </aside>
        </div>
      </article>
      <style scoped>
        .vendor-isolated {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          background: var(--background);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        /* ---------- hero ---------- */
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        .avatar {
          flex: none;
          --pretui-avatar-size: 3.25rem;
        }
        .hero-text {
          flex: 1;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: anywhere;
        }
        .byline {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sep-dot {
          margin: 0 0.25rem;
        }
        .pill-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-5xs);
          margin-top: var(--boxel-sp-xs);
        }
        .hero-rating {
          flex: none;
          text-align: right;
        }
        .rating-num {
          display: block;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        /* ---------- body: two columns ---------- */
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
          /* Fill whatever height is left so the aside's surface reaches the
             bottom edge. Without this the grid is only as tall as its content
             and the panel stops mid-card, reading as a cut-off seam. */
          flex: 1;
          min-height: 0;
          align-content: start;
        }
        .main {
          padding: var(--boxel-sp-lg);
          min-width: 0;
        }
        .side {
          padding: var(--boxel-sp-lg);
          border-left: 1px solid var(--border);
          background: var(--muted);
        }
        .panel-title {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        .panel-title.spaced {
          margin-top: var(--boxel-sp-lg);
        }
        .dd-note {
          color: var(--muted-foreground);
        }
        .side-note {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
          color: var(--muted-foreground);
        }
        .rate-card {
          list-style: none;
          margin: 0;
          padding: 0;
        }
        .rate-card > li {
          padding: 0.45rem 0;
          border-bottom: 1px solid var(--border);
        }
        .rate-card > li:last-child {
          border-bottom: 0;
        }
        .prose {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.65;
          max-width: 56ch;
          white-space: pre-line;
        }
        /* ---------- narrow container collapses to one column ---------- */
        @container iso (max-width: 40rem) {
          .body {
            grid-template-columns: 1fr;
          }
          .side {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
          .hero {
            flex-wrap: wrap;
          }
          .hero-rating {
            text-align: left;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    rows: KeyValueItem[] = [
      { key: 'Contact', value: 'contact' },
      { key: 'Contract start', value: 'start' },
      { key: 'Length', value: 'length' },
      { key: 'Rating', value: 'rating' },
    ];

    <template>
      <div class='vendor-embedded'>
        <header>
          <h3>{{@model.title}}</h3>
          <span class='category'>{{@model.serviceCategory}}</span>
        </header>
        <KeyValue
          class='facts'
          @items={{this.rows}}
          @layout='inline'
          @labelStyle='eyebrow'
        >
          <:value as |row|>
            {{#if (eq row.value 'contact')}}
              {{@model.contactName}}
            {{else if (eq row.value 'start')}}
              <@fields.contractStart />
            {{else if (eq row.value 'length')}}
              <@fields.contractLength />
            {{else}}
              <@fields.performanceRating />
            {{/if}}
          </:value>
        </KeyValue>
      </div>
      <style scoped>
        .vendor-embedded {
          padding: var(--boxel-sp);
          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
          transition: box-shadow 0.15s ease-out;
        }
        header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size);
        }
        .category {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .facts {
          margin-top: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='vendor-atom'>
        <BuildingIcon class='vendor-atom-icon' />
        <span class='vendor-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .vendor-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .vendor-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .vendor-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get avatarName(): string {
      return this.args.model?.title ?? 'Vendor';
    }

    get facts() {
      return contractFacts(this.args.model ?? {});
    }

    get contractHue(): Hue {
      return VENDOR_CONTRACT_HUES[this.facts.state] ?? 'slate';
    }

    // Shortest truthful wording — this pill survives to the smallest tier, so
    // it has to fit a badge without being cut.
    get contractPillLabel() {
      let { state, monthsLeft } = this.facts;
      if (state === 'expired') {
        return 'Ended';
      }
      if (state === 'upcoming') {
        return 'Not started';
      }
      if (state === 'expiring' && monthsLeft != null) {
        return monthsLeft > 0 ? `${monthsLeft} mo left` : 'Ends soon';
      }
      return 'Active';
    }

    get contractEndShort() {
      let { end } = this.facts;
      return end ? end.toISOString().slice(0, 7) : undefined;
    }

    get contractStartShort() {
      let { start } = this.facts;
      return start ? start.toISOString().slice(0, 7) : undefined;
    }

    get ratingLabel() {
      let v = this.args.model?.performanceRating;
      return typeof v === 'number' ? `${v} / ${MAX_STARS}` : undefined;
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <Avatar
            class='avatar'
            @name={{this.avatarName}}
            @hue={{AVATAR_HUE}}
          />
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.serviceCategory}}
              <span class='fit-eb'>{{@model.serviceCategory}}</span>
            {{/if}}
          </div>
          {{! Status pill is the last thing to be dropped — never hidden. }}
          <StatePill
            class='fit-pill'
            @label={{this.contractPillLabel}}
            @hue={{this.contractHue}}
            @dot={{true}}
          />
        </div>

        {{#if this.ratingLabel}}
          <div class='fit-rating'>
            <@fields.performanceRating />
            <span class='rating-text'>{{this.ratingLabel}}
              {{#if @model.contractLength.label}}
                &middot;
                {{@model.contractLength.label}}
              {{/if}}
            </span>
          </div>
        {{/if}}

        <dl class='fit-add'>
          {{#if @model.contactName}}
            <div><dt>Contact</dt><dd>{{@model.contactName}}</dd></div>
          {{/if}}
          {{#if this.contractStartShort}}
            <div><dt>From</dt><dd>{{this.contractStartShort}}</dd></div>
          {{/if}}
          {{#if this.contractEndShort}}
            <div><dt>Until</dt><dd>{{this.contractEndShort}}</dd></div>
          {{/if}}
          {{#if @model.email}}
            <div><dt>Email</dt><dd>{{@model.email}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four deliberate tiers. Each larger tier ADDS fields rather than
           enlarging the same ones; anything that cannot fit at a readable
           size is removed, never shrunk below the 0.6875rem floor. */
        .fit {
          height: 100%;
          /* Flex, not a three-row grid: with `minmax(0, 1fr)` in the middle
             a taller bottom block squeezed the middle row and clipped its
             text. Here the middle keeps its natural height and the extras
             block is pushed to the bottom by `margin-top: auto`. */
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          /* 0.6875rem floor, scaling with the tile but never below readable. */
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .avatar {
          flex: none;
          --pretui-avatar-size: 1.6rem;
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        /* --- category: tier 2, hidden on the badge --- */
        .fit-eb {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        /* --- rating: tier 3 --- */
        .fit-rating {
          flex: none;
          display: none;
          align-items: baseline;
          gap: 0.3rem;
          flex-wrap: wrap;
        }
        .rating-text {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        /* --- extra facts: tier 4, width-driven --- */
        .fit-add {
          display: none;
          margin: 0;
          margin-top: auto;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          grid-template-columns: 1fr 1fr;
          gap: 0.05rem 0.5rem;
        }
        .fit-add > div {
          display: flex;
          gap: 0.25rem;
          min-width: 0;
        }
        .fit-add dt {
          flex: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-add dd {
          margin: 0;
          font-size: var(--fit-small);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          font-variant-numeric: tabular-nums;
        }

        /* ===== TIER 2 — add the service category.
           Two rules rather than one, because container queries have no `or`:
           reached either by having vertical room, or by being a wide strip. */
        @container fitted-card (height > 5rem) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 15rem) {
          .fit-eb {
            display: block;
          }
        }

        /* ===== TIER 3 — add the star rating + contract length. */
        @container fitted-card (height > 8.125rem) and (width > 11.25rem) {
          .fit-rating {
            display: flex;
          }
        }

        /* ===== TIER 4 — add four more facts. Width-driven, which is the tier
           the previous implementation was missing entirely. */
        @container fitted-card (height > 9.375rem) and (width > 11.25rem) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 21.25rem) and (height > 8.125rem) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }

        /* ===== Short strip: go horizontal and drop the name to one line. */
        @container fitted-card (height <= 5.625rem) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }

        /* ===== Smallest tier: the category goes, the pill stays. */
        @container fitted-card (height <= 3.125rem) {
          .avatar {
            --pretui-avatar-size: 1.25rem;
          }
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
