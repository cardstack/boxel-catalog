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
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Button } from '../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../ui-component/components/data-table';
import { FormatDate } from '../../ui-component/components/format-date';
import { FormatNumber } from '../../ui-component/components/format-number';
import {
  PageScaffold,
  PageSection,
} from '../../ui-component/components/page-scaffold';
import { Avatar } from '../../ui-component/components/avatar';
import { EmptyState } from '../../ui-component/components/empty-state';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiTone } from '../../ui-component/pretui-primitives';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';

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
function orEmpty(value?: string | null): string {
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

// `1 Oct 2026`, in local time (toISOString would shift a day in UTC+).
function shortDay(d: Date): string {
  return d.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
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
    get facts() {
      return contractFacts(this.args.model ?? {});
    }
    get contractTone() {
      return VENDOR_CONTRACT_TONES[this.facts.state] ?? 'neutral';
    }
    get contractStateLabel() {
      switch (this.facts.state) {
        case 'expired':
          return 'Contract ended';
        case 'upcoming':
          return 'Not started';
        default:
          return 'Contract active';
      }
    }
    // The countdown, only when there is an end date to count toward.
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
    get ratingLabel() {
      let v = this.args.model?.performanceRating;
      return typeof v === 'number' ? `${v} / ${MAX_STARS}` : undefined;
    }
    get eyebrow() {
      return ['Vendor', this.args.model?.serviceCategory]
        .filter(Boolean)
        .join(' · ');
    }
    get subtitle() {
      return [this.args.model?.contactName, this.args.model?.email]
        .filter(Boolean)
        .join(' · ');
    }
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
        return `Inside the ${RENEWAL_WINDOW_MONTHS}-month renewal window: ${left}. Check any project depending on this vendor before renewing.`;
      }
      return `${left}. No action needed yet.`;
    }
    get stats() {
      let model = this.args.model;
      let { start, end } = this.facts;
      let spend = model?.spendYtd;
      return [
        {
          label: 'Spend YTD',
          value:
            typeof spend === 'number'
              ? spend.toLocaleString('en-US', {
                  style: 'currency',
                  currency: 'USD',
                  maximumFractionDigits: 0,
                })
              : '—',
          hint: 'recorded on the vendor',
        },
        {
          label: 'Performance',
          value: this.ratingLabel ?? '—',
          hint: this.ratingLabel ? 'buyer rating' : 'not yet rated',
        },
        {
          label: 'Contract',
          value: model?.contractLength?.label ?? '—',
          hint: start ? `from ${shortDay(start)}` : 'no start date',
        },
        {
          label: 'Renewal',
          value: end ? shortDay(end) : '—',
          hint: this.expiryLabel ?? 'open-ended',
        },
      ];
    }

    contractRows: KeyValueItem[] = [
      { key: 'Service', value: 'service' },
      { key: 'Starts', value: 'start' },
      { key: 'Length', value: 'length' },
      { key: 'Projected end', value: 'end' },
    ];
    contactRows: KeyValueItem[] = [
      { key: 'Contact', value: 'contact' },
      { key: 'Email', value: 'email' },
      { key: 'Website', value: 'website' },
    ];
    rateColumns: DataColumn<RateCardEntryField>[] = [
      { key: 'role', label: 'Role', value: (r) => r.role ?? 'Any role' },
      { key: 'rate', label: 'Hourly rate', align: 'end' },
    ];
    get rateRows() {
      return (this.args.model?.rateCard ?? []).filter(Boolean);
    }

    <template>
      <PageScaffold
        @eyebrow={{this.eyebrow}}
        @title={{@model.title}}
        @subtitle={{this.subtitle}}
        @stats={{this.stats}}
      >
        <:lead>
          <Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          />
        </:lead>
        <:chips>
          <StatusChip
            @value={{this.contractStateLabel}}
            @tone={{this.contractTone}}
          />
          {{#if this.expiryLabel}}
            <StatusChip
              @value={{this.expiryLabel}}
              @tone={{this.contractTone}}
            />
          {{/if}}
        </:chips>
        <:actions>
          {{#if @model.website}}
            <Button
              @tone='neutral'
              @appearance='outlined'
              @shape='pill'
              @href={{@model.website}}
            >Website</Button>
          {{/if}}
        </:actions>
        <:default>
          <div class='vendor-iso-grid'>
            <PageSection @title='Contract' @hint={{this.renewalNote}}>
              <KeyValue @items={{this.contractRows}} @layout='stacked'>
                <:value as |row|>
                  {{#if (eq row.value 'service')}}
                    {{if @model.serviceCategory @model.serviceCategory '—'}}
                  {{else if (eq row.value 'start')}}
                    <FormatDate
                      @date={{@model.contractStart}}
                      @locale='en-GB'
                      @dateStyle='medium'
                    />
                  {{else if (eq row.value 'length')}}
                    {{if
                      @model.contractLength.label
                      @model.contractLength.label
                      '—'
                    }}
                  {{else}}
                    <FormatDate
                      @date={{this.facts.end}}
                      @locale='en-GB'
                      @dateStyle='medium'
                    />
                  {{/if}}
                </:value>
              </KeyValue>
            </PageSection>
            <PageSection @title='Contact'>
              <KeyValue @items={{this.contactRows}} @layout='stacked'>
                <:value as |row|>
                  {{#if (eq row.value 'contact')}}
                    {{if @model.contactName @model.contactName '—'}}
                  {{else if (eq row.value 'email')}}
                    {{if @model.email @model.email '—'}}
                  {{else}}
                    {{#if @model.website}}<@fields.website />{{else}}—{{/if}}
                  {{/if}}
                </:value>
              </KeyValue>
            </PageSection>
          </div>

          <PageSection @title='Rate card'>
            <DataTable
              @columns={{this.rateColumns}}
              @rows={{this.rateRows}}
              @label='Rate card'
              @columnMenu={{false}}
              @sortable={{false}}
              @striped={{false}}
            >
              <:empty><EmptyState
                  @size='s'
                  @texture={{false}}
                  @title='No rate card on file'
                  @message='Rates are negotiated per engagement.'
                /></:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'rate')}}
                  <FormatNumber
                    @value={{row.hourlyRate}}
                    @style='currency'
                    @currency='USD'
                  />/hr
                {{else}}
                  {{text}}
                {{/if}}
              </:cell>
            </DataTable>
          </PageSection>

          <PageSection @title='Agreement terms'>
            {{#if @model.agreementTerms}}
              <p class='vendor-iso-prose'>{{@model.agreementTerms}}</p>
            {{else}}
              <EmptyState @size='s' @title='No agreement terms recorded' />
            {{/if}}
          </PageSection>
        </:default>
      </PageScaffold>
      <style scoped>
        .vendor-iso-grid {
          display: grid;
          grid-template-columns: repeat(
            auto-fit,
            minmax(min(100%, 18rem), 1fr)
          );
          gap: var(--boxel-sp-lg);
        }
        .vendor-iso-prose {
          white-space: pre-wrap;
        }
      </style>
    </template>
  };

  // Embedded: identity line plus the contract chip and the rating; the
  // chips drop in a narrow slot such as a table cell.
  static embedded = class Embedded extends Component<typeof this> {
    get meta() {
      return [this.args.model?.contactName, this.args.model?.email]
        .filter(Boolean)
        .join(' · ');
    }
    get facts() {
      return contractFacts(this.args.model ?? {});
    }
    get contractTone() {
      return VENDOR_CONTRACT_TONES[this.facts.state] ?? 'neutral';
    }
    get contractLabel() {
      return contractChipLabel(this.facts);
    }
    get ratingLabel() {
      let v = this.args.model?.performanceRating;
      return typeof v === 'number' ? `${v} / ${MAX_STARS}` : undefined;
    }
    <template>
      <div class='vendor-emb'>
        <Avatar
          @name={{orEmpty @model.title}}
          @hue='var(--muted-foreground)'
          @size={{32}}
          aria-hidden='true'
        />
        <span class='vendor-emb-who'>
          <strong class='vendor-emb-name'>{{@model.title}}</strong>
          {{#if this.meta}}<span
              class='vendor-emb-sub'
            >{{this.meta}}</span>{{/if}}
        </span>
        <span class='vendor-emb-status'>
          {{#if this.ratingLabel}}<span
              class='vendor-emb-rating'
            >{{this.ratingLabel}}</span>{{/if}}
          <StatusChip
            @value={{this.contractLabel}}
            @tone={{this.contractTone}}
          />
        </span>
      </div>
      <style scoped>
        .vendor-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .vendor-emb-who {
          flex: 1;
          display: grid;
          min-width: 0;
        }
        .vendor-emb-name,
        .vendor-emb-sub {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .vendor-emb-name {
          font-weight: 600;
        }
        .vendor-emb-sub,
        .vendor-emb-rating {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .vendor-emb-status {
          flex: none;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-variant-numeric: tabular-nums;
        }
        @container embedded-card (width < 26rem) {
          .vendor-emb {
            padding: 0;
          }
          .vendor-emb-status {
            display: none;
          }
        }
      </style>
    </template>
  };

  // Atom: the vendor's name as raw inline text.
  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='vendor-atom'>{{@model.title}}</span>
      <style scoped>
        .vendor-atom {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  // Fitted: FittedCard routes the sizes. Avatar media, category eyebrow,
  // name, contact; contract chip in meta; rating and length in the footer.
  static fitted = class Fitted extends Component<typeof this> {
    get facts() {
      return contractFacts(this.args.model ?? {});
    }
    get contractTone() {
      return VENDOR_CONTRACT_TONES[this.facts.state] ?? 'neutral';
    }
    get contractLabel() {
      return contractChipLabel(this.facts);
    }
    get footLine() {
      let v = this.args.model?.performanceRating;
      let rating = typeof v === 'number' ? `${v} / ${MAX_STARS}` : undefined;
      return [rating, this.args.model?.contractLength?.label]
        .filter(Boolean)
        .join(' · ');
    }
    <template>
      <FittedCard class='vendor-fit' @titleTag='h3'>
        <:placeholder><Avatar
            @name={{orEmpty @model.title}}
            @hue='var(--muted-foreground)'
            @size={{28}}
            aria-hidden='true'
          /></:placeholder>
        <:eyebrow>{{@model.serviceCategory}}</:eyebrow>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{@model.contactName}}</:subtitle>
        <:meta>
          <StatusChip
            @value={{this.contractLabel}}
            @tone={{this.contractTone}}
          />
        </:meta>
        <:footer><span
            class='vendor-fit-foot'
          >{{this.footLine}}</span></:footer>
      </FittedCard>
      <style scoped>
        .vendor-fit {
          --fc-image-background: var(--muted);
          --fc-image-width: 3rem;
          --fc-image-min-width: 3rem;
        }
        .vendor-fit-foot {
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
