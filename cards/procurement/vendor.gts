import {
  CardDef,
  Component,
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import UrlField from '@cardstack/base/url';
import EmailField from '@cardstack/base/email';
import BuildingIcon from '@cardstack/boxel-icons/building';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Avatar } from '@cardstack/pretui/components/avatar';
import type {
  PretuiTone,
  PretuiToneArg,
} from '@cardstack/pretui/pretui-primitives';
import { type KeyValueItem } from '@cardstack/pretui/components/key-value';
import { formatDate } from '@cardstack/pretui/internal/reading-format';

import ScoreField from '@cardstack/catalog/fields/rating/rating';
import { DurationField } from '../hr/duration-field';
import { durationInDays } from '../hr/duration-field';
import { Money } from '../hr/hr-ui';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  Sheet,
  SheetLine,
  SheetSection,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';
import { DotLabel } from '../hr/dot-enum-field';
import { codeRef, realmURL } from '@cardstack/runtime-common';
import type { BaseDef } from '@cardstack/base/card-api';

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
    <Sheet @title={{@title}} @meta={{@subtitle}} ...attributes>
      <:mark>{{yield to='avatar'}}</:mark>
      <:aside>{{yield to='chips'}}</:aside>
      <:default>
        {{#if (has-block 'stats')}}
          <SheetSection @label='Summary'>{{yield to='stats'}}</SheetSection>
        {{/if}}
        {{yield to='main'}}
        {{yield to='side'}}
      </:default>
    </Sheet>
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

/** The talent cards' atom: a 20px avatar and the name; an optional chip block. */
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
      /* the compact atom every tracker table shows: 22px, 20px mark, 12px 600 */
      .rec-atom {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        max-inline-size: 100%;
        block-size: 1.375rem;
        vertical-align: middle;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        line-height: 1.375rem;
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

// Records linked TO this vendor, found by live query (they link to it, not
// the other way), as runtime refs so this module imports none of them.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const vendorHere: string = import.meta.url;
const purchaseOrderRef = codeRef(
  vendorHere,
  './purchase-order',
  'PurchaseOrder',
);
const rfqRef = codeRef(vendorHere, './rfq', 'Rfq');
const vendorProfileRef = codeRef(
  vendorHere,
  './vendor-profile',
  'VendorProfile',
);
type LinkedRecord = CardDef & { status?: string | null };

function vendorQuery(
  owner: Component<typeof Vendor>,
  ref: ReturnType<typeof codeRef>,
  path: string,
) {
  return owner.args.context?.getCards(
    owner,
    () => {
      let id = owner.args.model?.id;
      return id ? { filter: { on: ref, eq: { [path]: id } } } : undefined;
    },
    () => {
      let url = owner.args.model?.[realmURL]?.href;
      return url ? [url] : [];
    },
    { isLive: true },
  );
}

// A linked card's own component, so it renders in its atom format.
function cardComponent(card: BaseDef | undefined) {
  return card
    ? (card.constructor as typeof BaseDef).getComponent(card)
    : undefined;
}

// A Pret UI tone as the DotLabel hue.
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
    ordersQuery = vendorQuery(this, purchaseOrderRef, 'vendor.id');
    rfqsQuery = vendorQuery(this, rfqRef, 'invitedVendors.id');
    profileQuery = vendorQuery(this, vendorProfileRef, 'linkedVendor.id');

    get v() {
      return vendorView(this.args.model);
    }
    get orders(): LinkedRecord[] {
      return (this.ordersQuery?.instances ?? []) as LinkedRecord[];
    }
    get rfqs(): LinkedRecord[] {
      return (this.rfqsQuery?.instances ?? []) as LinkedRecord[];
    }
    linkedCard = (key: string): LinkedRecord | undefined =>
      key === 'Profile'
        ? ((this.profileQuery?.instances ?? [])[0] as LinkedRecord | undefined)
        : key === 'Order'
          ? this.orders[0]
          : this.rfqs[0];
    linkedRows = [
      { key: 'Profile', value: '' },
      { key: 'Order', value: '' },
      { key: 'RFQ', value: '' },
    ];
    get strip(): StripItem[] {
      let v = this.v;
      let n = this.orders.length;
      return [
        {
          label: 'Spend YTD',
          value: v.spend,
          hint: n + (n === 1 ? ' purchase order' : ' purchase orders'),
          tone: 'neutral',
        },
        {
          label: 'Rating',
          value: v.rating,
          hint: 'performance',
          tone: 'success',
        },
        {
          label: 'Contract',
          value: v.lengthShort,
          hint: v.start ? 'from ' + v.start : undefined,
          tone: 'neutral',
        },
        {
          label: 'Open RFQs',
          value: String(this.rfqs.length),
          hint: 'invited',
          tone: 'info',
        },
      ];
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
      let m = this.args.model;
      return [
        { key: 'Spend YTD', value: orDash(v.spend) },
        { key: 'Rating', value: orDash(v.rating) },
        { key: 'Contract', value: orDash(v.contract) },
        { key: 'Contact', value: orDash(m?.contactName) },
        { key: 'Email', value: orDash(m?.email) },
        ...v.rates,
        { key: 'Terms', value: orDash(v.payment) },
      ];
    }
    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{this.v.subtitle}}>
            <:mark><Avatar
                @name={{orEmpty @model.title}}
                @hue='var(--muted)'
                @shape='rounded'
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside>{{#if this.v.rating}}<DotLabel
                  @label={{this.v.rating}}
                  @hue={{toneHue this.v.ratingTone}}
                />{{/if}}{{#if this.v.lengthLong}}<span
                  class='mono'
                >{{this.v.lengthLong}}</span>{{/if}}</:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Agreement terms'><SheetLine>{{if
                @model.agreementTerms
                @model.agreementTerms
                'No terms recorded.'
              }}</SheetLine></Panel>
          <Panel @title='Contact'><Kv @items={{this.contactItems}} /></Panel>
          <Panel @title='Recent orders'>
            {{#each this.orders as |po|}}
              <SheetLine>
                {{#let (cardComponent po) as |Atom|}}<Atom
                    @format='atom'
                    @displayContainer={{false}}
                  />{{/let}}
                <span class='grow'></span>
                {{#if po.status}}<span class='st'>{{po.status}}</span>{{/if}}
              </SheetLine>
            {{else}}
              <SheetLine><span class='muted'>No purchase orders yet.</span></SheetLine>
            {{/each}}
          </Panel>
          {{#if this.v.rates.length}}
            <Panel @title='Rate card'><Kv @items={{this.v.rates}} /></Panel>
          {{/if}}
        </:main>
        <:aside>
          <Panel @title='Linked'>
            <Kv @items={{this.linkedRows}}>
              <:value as |row|>
                {{#let (this.linkedCard row.key) as |card|}}
                  {{#if card}}{{#let (cardComponent card) as |Atom|}}<Atom
                        @format='atom'
                        @displayContainer={{false}}
                      />{{/let}}{{#if card.status}}<span
                        class='st'
                      >{{card.status}}</span>{{/if}}{{else}}—{{/if}}
                {{/let}}
              </:value>
            </Kv>
          </Panel>
          <Panel @title='Details'><Kv @items={{this.detailItems}} /></Panel>
        </:aside>
      </IsoPage>
      <style scoped>
        .mono {
          font-weight: 500;
          font-size: var(--boxel-font-size-2xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
        .muted {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .grow {
          flex: 1;
        }
        .st {
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return vendorView(this.args.model);
    }
    get rows(): KeyValueItem[] {
      let v = this.v;
      let m = this.args.model;
      return [
        { key: 'Spend YTD', value: orDash(v.spend) },
        { key: 'Rating', value: orDash(v.rating) },
        { key: 'Contract', value: orDash(v.contract) },
        { key: 'Contact', value: orDash(m?.contactName) },
        { key: 'Email', value: orDash(m?.email) },
        ...v.rates.slice(0, 2),
      ];
    }
    <template>
      <EmbCard @title={{@model.title}} @meta={{this.v.subtitle}}>
        <:mark><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted)'
            @shape='rounded'
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if this.v.rating}}<DotLabel
              @label={{this.v.rating}}
              @hue={{toneHue this.v.ratingTone}}
            />{{/if}}</:aside>
        <:default><Kv @items={{this.rows}} /></:default>
      </EmbCard>
    </template>
  };

  // Atom: name and rating on one line.
  static atom = class Atom extends Component<typeof this> {
    get v() {
      return vendorView(this.args.model);
    }
    <template><RecordAtom @name={{@model.title}} /></template>
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
    // spend and contract already have their own rows above
    get moreFacts(): KeyValueItem[] {
      return this.facts.slice(3);
    }
    get leadStat(): StripItem | undefined {
      return this.strip[0];
    }

    get strip(): StripItem[] {
      let v = this.v;
      return [
        { label: 'Spend', value: orDash(v.spend) },
        { label: 'Rating', value: orDash(v.rating) },
        { label: 'Contract', value: orDash(v.lengthShort) },
      ];
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted)'
            @shape='rounded'
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:status>{{#if this.v.rating}}<DotLabel
              @label={{this.v.rating}}
              @hue={{toneHue this.v.ratingTone}}
            />{{/if}}</:status>
        <:subtitle><span class='meta'>{{this.v.subtitle}}</span></:subtitle>
        <:metric>{{#if this.leadStat}}<Metric
              @value={{this.leadStat.value}}
              @label={{this.leadStat.label}}
            />{{/if}}</:metric>
        <:details>
          <Detail @label='Spend YTD'><span class='mono'>{{orDash
                this.v.spend
              }}</span></Detail>
          <Detail @label='Contract'><span class='mono'>{{orDash
                this.v.contract
              }}</span></Detail>

          {{#each this.moreFacts as |f|}}
            <Detail @label={{f.key}}>{{f.value}}</Detail>
          {{/each}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          color: var(--muted-foreground);
        }
        .mono {
          font-family: var(--font-mono);
          font-weight: 500;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
