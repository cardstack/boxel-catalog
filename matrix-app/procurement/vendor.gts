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
import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { concat } from '@ember/helper';
import { Avatar } from '../../ui-component/components/avatar';
import { Descriptions } from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import { Panel } from '../../ui-component/components/panel';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type {
  PretuiTone,
  PretuiToneArg,
} from '../../ui-component/pretui-primitives';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { formatDate } from '../../ui-component/internal/reading-format';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from '../hr/duration-field';
import { durationInDays } from '../hr/duration-field';
import { Money } from '../hr/hr-ui';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

// Avatar needs a string even before the card has a name.
export function orEmpty(value?: string | null): string {
  return value ?? '';
}

function isNumber(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v);
}

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
        <span class='rate-amount'>{{#if (isNumber @model.hourlyRate)}}<Money
              @amount={{@model.hourlyRate}}
            />/hr{{else}}—{{/if}}</span>
      </span>
      <style scoped>
        @layer PretComponent {
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
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
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

export const VENDOR_CONTRACT_TONES: Record<string, PretuiTone> = {
  upcoming: 'neutral',
  active: 'success',
  expiring: 'warning',
  expired: 'danger',
};

const RENEWAL_WINDOW_MONTHS = 6;
const MAX_STARS = 5;

interface ContractShape {
  contractStart?: Date | null;
  contractLength?: { value?: number | null; unit?: string | null } | null;
}

// Shared by isolated and fitted so the two formats can never disagree about
// what state a contract is in, or when it ends.
export function contractFacts(model: ContractShape) {
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

// The shortest truthful wording for the contract chip: it survives to the
// smallest fitted size and sits in the embedded line.
function contractChipLabel(facts: ReturnType<typeof contractFacts>) {
  let { state, monthsLeft } = facts;
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

const DATE_OPTIONS = { dateStyle: 'medium' } as const;

/** `Feb 15, 2027`, the date wording every talent card uses. */
export function mediumDate(value?: Date | null): string | undefined {
  return value ? formatDate(new Date(value), 'en-US', DATE_OPTIONS) : undefined;
}

export interface FittedStat {
  key: string;
  value: string;
}

export interface FittedProgress {
  label: string;
  /** 0–100 */
  value: number;
  valueText: string;
}

interface FittedExtrasSignature {
  Args: {
    /** key facts, one per line (two columns from 400 wide) */
    facts?: KeyValueItem[];
    /** the three-number strip, on expanded cards only */
    stats?: FittedStat[];
    progress?: FittedProgress;
    /** one label per linked card the `relation` block renders */
    relations?: string[];
  };
  Blocks: {
    /** the card's FitTile */
    default: [];
    /** the linked card for one label, as its own atom */
    relation: [label: string, index: number];
  };
}

// shortcut: FitTile budgets only who / state / fact / relations, so the rows
// tall fitted sizes add (key facts, one relation per line, a progress bar, a
// stat strip) are budgeted here around it; move this into FitTile when the kit
// grows an extras region. Every list wraps whole items out of sight in a
// column that starts past the right edge, so nothing is ever half-cut.
export class FittedExtras extends GlimmerComponent<FittedExtrasSignature> {
  get hasRelations() {
    return Boolean(this.args.relations?.length);
  }
  get hasFacts() {
    return Boolean(this.args.facts?.length);
  }
  <template>
    <div class='fitx'>
      <div class='fitx-tile'>{{yield}}</div>
      {{#if @stats}}
        <dl class='fitx-stats'>
          {{#each @stats as |stat|}}
            <div class='fitx-stat'>
              <dt>{{stat.key}}</dt>
              <dd>{{stat.value}}</dd>
            </div>
          {{/each}}
        </dl>
      {{/if}}
      {{#if @progress}}
        {{! The wrapper carries the hide/show rule: ProgressBar's own root
          rule (display: grid, same layer, same specificity) would otherwise
          override a class passed to it, and the bar would show at every size. }}
        <div class='fitx-bar'>
          <ProgressBar
            @value={{@progress.value}}
            @label={{@progress.label}}
            @count={{@progress.valueText}}
            @valueText={{@progress.valueText}}
          />
        </div>
      {{/if}}
      {{#if this.hasFacts}}
        <dl class='fitx-facts'>
          {{#each @facts as |item|}}
            <div class='fitx-fact'>
              <dt>{{item.key}}</dt>
              <dd>{{item.value}}</dd>
            </div>
          {{/each}}
        </dl>
      {{/if}}
      {{#if this.hasRelations}}
        <ul class='fitx-rels'>
          {{#each @relations as |label index|}}
            <li class='fitx-rel'>
              <span class='fitx-rel-k'>{{label}}</span>
              <span class='fitx-rel-v'>{{yield
                  label
                  index
                  to='relation'
                }}</span>
            </li>
          {{/each}}
        </ul>
      {{/if}}
    </div>
    <style scoped>
      @layer PretComponent {
        .fitx {
          display: flex;
          flex-direction: column;
          block-size: 100%;
          overflow: hidden;
        }
        .fitx-tile {
          flex: 1 1 0;
          min-block-size: 0;
        }
        .fitx-stats,
        .fitx-bar,
        .fitx-facts,
        .fitx-rels {
          display: none;
          margin: 0;
          padding: 0 var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.5;
        }
        .fitx-stats {
          grid-template-columns: repeat(3, minmax(0, 1fr));
          gap: var(--boxel-sp-xs);
          margin-block-end: var(--boxel-sp-xs);
        }
        .fitx-stat dt,
        .fitx-fact dt,
        .fitx-rel-k {
          color: var(--muted-foreground);
        }
        .fitx-stat dt,
        .fitx-stat dd {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .fitx-stat dd {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          color: var(--primary);
          font-variant-numeric: tabular-nums;
        }
        .fitx-bar {
          margin-block-end: var(--boxel-sp-xs);
        }
        /* a column of whole rows; a row that doesn't fit wraps into the
           next column, which starts past the right edge */
        .fitx-facts,
        .fitx-rels {
          flex-direction: column;
          flex-wrap: wrap;
          align-content: flex-start;
          row-gap: var(--boxel-sp-4xs);
          column-gap: var(--boxel-sp);
          min-block-size: 0;
          overflow: hidden;
          list-style: none;
        }
        .fitx-facts {
          flex: 1 1 0;
        }
        .fitx-rels {
          flex: 0 1 auto;
          padding-block-end: var(--boxel-sp-sm);
        }
        .fitx-fact,
        .fitx-rel {
          box-sizing: border-box;
          inline-size: 100%;
          min-inline-size: 0;
        }
        .fitx-fact {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          white-space: nowrap;
        }
        .fitx-fact dd {
          margin: 0;
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .fitx-rel {
          display: grid;
          grid-template-columns: auto minmax(0, 1fr);
          align-items: center;
          gap: var(--boxel-sp-xs);
          block-size: 1.375rem;
          white-space: nowrap;
        }
        .fitx-rel-v {
          display: flex;
          min-inline-size: 0;
          font-size: var(--boxel-font-size-xs);
        }

        /* 170 tall, or a wide strip: one relation per line */
        @container fitted-card (height >= 170px) or ((height >= 105px) and (width >= 400px)) {
          .fitx-tile {
            flex: none;
          }
          .fitx-rels {
            display: flex;
          }
        }
        @container fitted-card (height < 170px) {
          .fitx-rels {
            padding-block-end: var(--boxel-sp-xs);
          }
        }
        /* under 250 wide the atom needs the line, its label goes */
        @container fitted-card (width < 250px) {
          .fitx-rel-k {
            display: none;
          }
        }
        /* 250 tall and up: the key-fact list */
        @container fitted-card (height >= 250px) {
          .fitx-facts {
            display: flex;
          }
        }
        @container fitted-card (width >= 400px) {
          .fitx-fact {
            inline-size: calc((100% - var(--boxel-sp)) / 2);
          }
        }
        /* full cards add the progress bar, expanded cards the stat strip */
        @container fitted-card (height >= 275px) and (width >= 400px) {
          .fitx-bar {
            display: block;
          }
        }
        @container fitted-card (height >= 400px) and (width >= 400px) {
          .fitx-stats {
            display: grid;
          }
        }
      }
    </style>
  </template>
}

interface RecordIsolatedSignature {
  Args: { title?: string | null; subtitle?: string | null };
  Blocks: {
    avatar: [];
    chips: [];
    /** Panel-wrapped Stats, three across */
    stats: [];
    /** the wide column's Panels */
    main: [];
    /** the narrow column's Panels */
    side: [];
  };
  Element: HTMLElement;
}

/** The talent cards' isolated layout: header, stat strip, two columns of
 * Panels that fold to one under 45rem. */
export const RecordIsolated: TemplateOnlyComponent<RecordIsolatedSignature> =
  <template>
    <article class='rec-iso' ...attributes>
      <Panel class='rec-iso-shell'>
        <header class='rec-iso-head'>
          {{yield to='avatar'}}
          <div class='rec-iso-id'>
            <h1>{{@title}}</h1>
            {{#if @subtitle}}<p class='rec-iso-sub'>{{@subtitle}}</p>{{/if}}
          </div>
          <div class='rec-chips'>{{yield to='chips'}}</div>
        </header>
        {{#if (has-block 'stats')}}
          <div class='rec-iso-stats'>{{yield to='stats'}}</div>
        {{/if}}
        <div class='rec-iso-body'>
          <div class='rec-iso-col'>{{yield to='main'}}</div>
          <div class='rec-iso-col'>{{yield to='side'}}</div>
        </div>
      </Panel>
    </article>
    <style scoped>
      @layer PretComponent {
        .rec-iso {
          container-type: inline-size;
          min-block-size: 100%;
          box-sizing: border-box;
          padding: var(--boxel-sp-lg);
          background: var(--canvas);
          color: var(--foreground);
        }
        .rec-iso-shell {
          padding: var(--boxel-sp-xs);
        }
        .rec-iso-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp);
        }
        .rec-iso-id {
          flex: 1 1 12rem;
          min-inline-size: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          line-height: 1.25;
          color: var(--primary);
          overflow-wrap: anywhere;
        }
        .rec-iso-sub {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .rec-chips {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .rec-iso-stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
          gap: var(--boxel-sp);
          margin-block-start: var(--boxel-sp-lg);
        }
        .rec-iso-body {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr);
          gap: var(--boxel-sp-lg);
          margin-block-start: var(--boxel-sp-lg);
          font-size: var(--boxel-font-size-sm);
          font-variant-numeric: tabular-nums;
          overflow-wrap: anywhere;
        }
        .rec-iso-col {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          min-inline-size: 0;
        }
        @container (width < 45rem) {
          .rec-iso-body {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      }
    </style>
  </template>;

interface RecordEmbeddedSignature {
  Args: { title?: string | null; subtitle?: string | null };
  Blocks: {
    avatar: [];
    chips: [];
    /** one sentence: the fact that explains the state */
    fact: [];
    /** a Descriptions grid */
    details: [];
    /** linked cards as labelled atoms */
    relations: [];
  };
  Element: HTMLElement;
}

/** The talent cards' embedded layout: identity, chips (under the name below
 * 25rem), a fact line, a detail grid and labelled relations. */
export const RecordEmbedded: TemplateOnlyComponent<RecordEmbeddedSignature> =
  <template>
    <article class='rec-emb' ...attributes>
      <header class='rec-emb-head'>
        {{yield to='avatar'}}
        <div class='rec-emb-id'>
          <h3 class='rec-emb-title'>{{@title}}</h3>
          {{#if @subtitle}}<p class='rec-emb-sub'>{{@subtitle}}</p>{{/if}}
        </div>
        <div class='rec-chips'>{{yield to='chips'}}</div>
      </header>
      {{#if (has-block 'fact')}}
        <p class='rec-emb-fact'>{{yield to='fact'}}</p>
      {{/if}}
      {{#if (has-block 'details')}}
        <div class='rec-emb-details'>{{yield to='details'}}</div>
      {{/if}}
      {{#if (has-block 'relations')}}
        <p class='rec-emb-rels'>{{yield to='relations'}}</p>
      {{/if}}
    </article>
    <style scoped>
      @layer PretComponent {
        .rec-emb {
          container-type: inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
          color: var(--foreground);
        }
        .rec-emb-head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
        .rec-emb-id {
          flex: 1 1 0;
          min-inline-size: 0;
        }
        .rec-emb-title {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          overflow-wrap: anywhere;
        }
        .rec-emb-sub {
          margin: var(--boxel-sp-6xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .rec-chips {
          display: flex;
          flex-wrap: wrap;
          justify-content: flex-end;
          gap: var(--boxel-sp-4xs);
        }
        .rec-emb-fact {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .rec-emb-details {
          padding-block-start: var(--boxel-sp-4xs);
          border-block-start: 1px solid var(--border);
        }
        .rec-emb-rels {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp);
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        @container (width < 25rem) {
          .rec-chips {
            flex-basis: 100%;
            justify-content: flex-start;
          }
        }
      }
    </style>
  </template>;

interface RecordAtomSignature {
  Args: { name?: string | null; src?: string | null };
  Blocks: { default: [] };
  Element: HTMLSpanElement;
}

/** The talent cards' atom: a 20px avatar, the name, at most one chip. */
export const RecordAtom: TemplateOnlyComponent<RecordAtomSignature> = <template>
  <span class='rec-atom' ...attributes>
    <Avatar
      @name={{orEmpty @name}}
      @src={{if @src @src undefined}}
      @hue='var(--muted-foreground)'
      @size={{20}}
      aria-hidden='true'
    />
    <span class='rec-atom-name'>{{@name}}</span>
    <span class='rec-atom-chip'>{{yield}}</span>
  </span>
  <style scoped>
    @layer PretComponent {
      .rec-atom {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        max-inline-size: 100%;
        vertical-align: middle;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        line-height: 1.5;
        color: var(--foreground);
        white-space: nowrap;
      }
      .rec-atom-name {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .rec-atom-chip {
        display: flex;
        flex: none;
        max-inline-size: 50%;
      }
      .rec-atom-chip:empty {
        display: none;
      }
    }
  </style>
</template>;

const RATING_TONES: Record<number, PretuiToneArg> = {
  5: 'success',
  4: 'success',
  3: 'warning',
};

function vendorView(m?: Partial<Vendor>) {
  let facts = contractFacts(m ?? {});
  let rating =
    typeof m?.performanceRating === 'number' ? m.performanceRating : undefined;
  let spend =
    typeof m?.spendYtd === 'number'
      ? m.spendYtd.toLocaleString('en-US', {
          style: 'currency',
          currency: 'USD',
          maximumFractionDigits: 0,
        })
      : undefined;
  let length = m?.contractLength;
  let lengthLong =
    length?.value != null && length.unit
      ? `${length.value} ${length.value === 1 ? length.unit.replace(/s$/, '') : length.unit}`
      : undefined;
  let lengthShort =
    length?.value != null && length.unit
      ? `${length.value} ${length.unit.startsWith('month') ? 'mo' : length.unit}`
      : undefined;
  let start = mediumDate(facts.start);
  let payment = m?.agreementTerms?.match(/net-\d+/i)?.[0]?.toLowerCase();
  let actionable = facts.state === 'expiring' || facts.state === 'expired';
  return {
    facts,
    spend,
    payment,
    start,
    lengthLong,
    lengthShort,
    contract: [start, lengthShort].filter(Boolean).join(' · ') || undefined,
    rating: rating == null ? undefined : `${rating} / ${MAX_STARS}`,
    ratingPercent: rating == null ? undefined : (rating / MAX_STARS) * 100,
    ratingTone: (rating == null
      ? 'neutral'
      : (RATING_TONES[Math.round(rating)] ?? 'danger')) as PretuiToneArg,
    // the contract chip takes the length chip's place once it needs action
    termChip: actionable ? contractChipLabel(facts) : lengthLong,
    termTone: (actionable
      ? VENDOR_CONTRACT_TONES[facts.state]
      : 'neutral') as PretuiToneArg,
    subtitle:
      [m?.serviceCategory, m?.contactName].filter(Boolean).join(' · ') ||
      undefined,
    rates: (m?.rateCard ?? []).map((r) => ({
      key: r.role || 'Any role',
      value: typeof r.hourlyRate === 'number' ? `$${r.hourlyRate} / h` : '—',
    })),
  };
}

function orDash(value?: string) {
  return value || '—';
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
    get v() {
      return vendorView(this.args.model);
    }
    get contactItems(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Contact', value: orDash(m?.contactName) },
        { key: 'Email', value: orDash(m?.email) },
        {
          key: 'Website',
          value: orDash(m?.website?.replace(/^https?:\/\//, '')),
        },
      ];
    }
    get detailItems(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Spend YTD', value: orDash(v.spend) },
        { key: 'Rating', value: orDash(v.rating) },
        { key: 'Contract', value: orDash(v.contract) },
        { key: 'Contact', value: orDash(this.args.model?.contactName) },
        ...v.rates,
        { key: 'Email', value: orDash(this.args.model?.email) },
      ];
    }
    <template>
      <RecordIsolated @title={{@model.title}} @subtitle={{this.v.subtitle}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if this.v.rating}}
            <StatusChip @value={{this.v.rating}} @tone={{this.v.ratingTone}} />
          {{/if}}
          {{#if this.v.termChip}}
            <StatusChip @value={{this.v.termChip}} @tone={{this.v.termTone}} />
          {{/if}}
        </:chips>
        <:stats>
          <Panel><Stat
              @label='Spend YTD'
              @value={{orDash this.v.spend}}
              @hint='year to date'
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Rating'
              @value={{orDash this.v.rating}}
              @hint='performance'
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Contract'
              @value={{orDash this.v.lengthShort}}
              @hint={{if this.v.start (concat 'from ' this.v.start)}}
              @roll={{false}}
            /></Panel>
        </:stats>
        <:main>
          <Panel @title='Rate card'>
            {{#if this.v.rates.length}}
              <KeyValue @items={{this.v.rates}} />
            {{else}}
              <p class='iso-text'>No rates recorded.</p>
            {{/if}}
          </Panel>
          <Panel @title='Agreement terms'>
            <p class='iso-text'>{{if
                @model.agreementTerms
                @model.agreementTerms
                'No terms recorded.'
              }}</p>
          </Panel>
          <Panel @title='Contact'>
            <KeyValue @items={{this.contactItems}} />
          </Panel>
        </:main>
        <:side>
          <Panel @title='Details'>
            <KeyValue @items={{this.detailItems}} />
          </Panel>
        </:side>
      </RecordIsolated>
      <style scoped>
        @layer PretComponent {
          .iso-text {
            margin: 0;
            white-space: pre-line;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return vendorView(this.args.model);
    }
    get kvItems() {
      let v = this.v;
      return [
        { label: 'Spend YTD', value: v.spend },
        { label: 'Rating', value: v.rating },
        { label: 'Contract', value: v.contract },
        { label: 'Contact', value: this.args.model?.contactName ?? undefined },
        ...v.rates.slice(0, 2).map((r) => ({ label: r.key, value: r.value })),
      ];
    }
    <template>
      <RecordEmbedded @title={{@model.title}} @subtitle={{this.v.subtitle}}>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if this.v.rating}}
            <StatusChip @value={{this.v.rating}} @tone={{this.v.ratingTone}} />
          {{/if}}
          {{#if this.v.termChip}}
            <StatusChip @value={{this.v.termChip}} @tone={{this.v.termTone}} />
          {{/if}}
        </:chips>
        <:fact>{{#if this.v.spend}}Spend YTD
            <b class='strong'>{{this.v.spend}}</b>{{#if this.v.payment}}
              &middot;
              {{this.v.payment}}{{/if}}{{/if}}</:fact>
        <:details><Descriptions
            @items={{this.kvItems}}
            @layout='vertical'
            @columns={{3}}
          /></:details>
      </RecordEmbedded>
      <style scoped>
        @layer PretComponent {
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
        }
      </style>
    </template>
  };

  // Atom: name and rating on one line.
  static atom = class Atom extends Component<typeof this> {
    get v() {
      return vendorView(this.args.model);
    }
    <template>
      <RecordAtom @name={{@model.title}}>
        {{#if this.v.rating}}
          <StatusChip @value={{this.v.rating}} @tone={{this.v.ratingTone}} />
        {{/if}}
      </RecordAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get v() {
      return vendorView(this.args.model);
    }
    get facts(): KeyValueItem[] {
      let v = this.v;
      return [
        { key: 'Spend YTD', value: orDash(v.spend) },
        { key: 'Rating', value: orDash(v.rating) },
        { key: 'Contract', value: orDash(v.contract) },
        { key: 'Contact', value: orDash(this.args.model?.contactName) },
        ...v.rates,
        { key: 'Email', value: orDash(this.args.model?.email) },
      ];
    }
    get stats(): FittedStat[] {
      let v = this.v;
      return [
        { key: 'Spend YTD', value: orDash(v.spend) },
        { key: 'Rating', value: orDash(v.rating) },
        { key: 'Contract', value: orDash(v.lengthShort) },
      ];
    }
    get progress(): FittedProgress | undefined {
      let v = this.v;
      return v.ratingPercent == null || !v.rating
        ? undefined
        : { label: 'Rating', value: v.ratingPercent, valueText: v.rating };
    }
    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @progress={{this.progress}}
      >
        <FitTile>
          <:avatar>
            <Avatar
              @name={{orEmpty @model.title}}
              @hue='var(--muted-foreground)'
              @size={{32}}
              aria-hidden='true'
            />
          </:avatar>
          <:title><span
              class='fit-title'
              role='heading'
              aria-level='3'
            >{{@model.title}}</span></:title>
          <:subtitle>{{this.v.subtitle}}</:subtitle>
          <:status>
            {{#if this.v.rating}}
              <StatusChip
                @value={{this.v.rating}}
                @tone={{this.v.ratingTone}}
              />
            {{/if}}
            {{#if this.v.termChip}}
              <StatusChip
                @value={{this.v.termChip}}
                @tone={{this.v.termTone}}
              />
            {{/if}}
          </:status>
          <:fact>{{#if this.v.spend}}Spend YTD
              {{this.v.spend}}{{#if this.v.payment}}
                &middot;
                {{this.v.payment}}{{/if}}{{/if}}</:fact>
        </FitTile>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        }
      </style>
    </template>
  };
}
