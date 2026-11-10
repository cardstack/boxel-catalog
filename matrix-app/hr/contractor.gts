import { markDefinition } from '@cardstack/base/mark-definition';
import {
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import { dotEnumField } from './dot-enum-field';
import ShieldIcon from '@cardstack/boxel-icons/shield';

import { PersonBase } from '../people/person-base';
import { Project } from '../projects/project';
import { RecordAtom, Vendor, mediumDate } from '../procurement/vendor';
import { Avatar } from '@cardstack/pretui/components/avatar';
import type { PretuiToneArg } from '@cardstack/pretui/pretui-primitives';
import { eq } from '@cardstack/boxel-ui/helpers';

import { type Hue } from '@cardstack/catalog/components/state-pill';
import { stateColorsOf } from './hr-ui';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { daysUntil } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  StatStrip,
  type StripItem,
} from './compact-sheet';

// Inside this window the contract window turns amber; past zero it turns red.
const EXPIRY_WARNING_DAYS = 30;

// Shared by every format so a tile and the isolated view can never disagree
// about how urgent the same end date is.
export function expiryTone(
  days: number | undefined,
): 'expired' | 'warning' | undefined {
  if (days == null) {
    return undefined;
  }
  if (days < 0) {
    return 'expired';
  }
  if (days <= EXPIRY_WARNING_DAYS) {
    return 'warning';
  }
  return undefined;
}

export const EXPIRY_TONE_HUES: Record<string, Hue> = {
  warning: 'amber',
  expired: 'red',
};

export const EXPIRY_TONE_COLORS = stateColorsOf(EXPIRY_TONE_HUES);

export const CONTRACTOR_STATUSES = ['active', 'inactive', 'terminated'];

export const CONTRACTOR_STATUS_HUES: Record<string, Hue> = {
  active: 'green',
  inactive: 'amber',
  terminated: 'red',
};

export const CONTRACTOR_STATUS_COLORS = stateColorsOf(CONTRACTOR_STATUS_HUES);

const CONTRACTOR_STATUS_TONES: Record<string, PretuiToneArg> = {
  active: 'success',
  inactive: 'warning',
  terminated: 'danger',
};

const EXPIRY_TONES: Record<string, PretuiToneArg> = {
  warning: 'warning',
  expired: 'danger',
};

export function statusTone(status?: string | null): PretuiToneArg {
  return CONTRACTOR_STATUS_TONES[status ?? ''] ?? 'neutral';
}

export function statusLabel(status?: string | null): string {
  return capitalize(status) ?? '—';
}

function capitalize(value?: string | null): string | undefined {
  return value ? value[0].toUpperCase() + value.slice(1) : undefined;
}

// Every format reads the same labels, so a tile and the isolated view can
// never word the same contract differently.
function contractorView(m?: Partial<Contractor>) {
  let rate = m?.billableRate;
  let days = m?.daysRemaining ?? undefined;
  let start = mediumDate(m?.contractStartDate);
  let end = mediumDate(m?.contractEndDate);
  let tone = expiryTone(days);
  let months: number | undefined;
  let elapsed: number | undefined;
  if (m?.contractStartDate && m?.contractEndDate) {
    let from = new Date(m.contractStartDate).getTime();
    let to = new Date(m.contractEndDate).getTime();
    months = Math.max(1, Math.round((to - from) / (30.44 * 86400000)));
    elapsed =
      to > from
        ? Math.min(100, Math.max(0, ((Date.now() - from) / (to - from)) * 100))
        : undefined;
  }
  let daysText =
    days == null
      ? undefined
      : days < 0
        ? 'expired'
        : days === 0
          ? 'ends today'
          : `${days} days`;
  return {
    rateShort: rate == null ? undefined : `$${rate}/h`,
    rateLong: rate == null ? undefined : `$${rate} / hour`,
    invoicing: capitalize(m?.invoiceFrequency),
    invoicingLower: m?.invoiceFrequency || undefined,
    start,
    end,
    range: start && end ? `${start} – ${end}` : (start ?? end),
    daysText,
    daysChip:
      days == null
        ? undefined
        : days < 0 || days === 0
          ? daysText
          : `${days} days left`,
    daysTone: tone ? EXPIRY_TONES[tone] : ('neutral' as PretuiToneArg),
    months: months == null ? undefined : `${months} months`,
    elapsed: elapsed == null ? undefined : Math.round(elapsed),
    statusLabel: capitalize(m?.status),
    subtitle:
      [m?.vendorName, rate == null ? undefined : `$${rate}/h`]
        .filter(Boolean)
        .join(' · ') || undefined,
    statusTone: CONTRACTOR_STATUS_TONES[m?.status ?? ''] ?? 'neutral',
  };
}

function orDash(value?: string) {
  return value || '—';
}

export const ContractorStatusField = markDefinition(
  dotEnumField(
    {
      options: CONTRACTOR_STATUSES.map((status) => ({
        value: status,
        label: status,
      })),
      displayName: 'Contract Status',
    },
    CONTRACTOR_STATUS_HUES,
  ),
);

export const InvoiceFrequencyOptions = ['monthly', 'quarterly', 'annually'];

export const InvoiceFrequencyField = markDefinition(
  enumField(StringField, {
    options: InvoiceFrequencyOptions.map((freq) => ({
      value: freq,
      label: freq,
    })),
    displayName: 'Invoice Frequency',
  }),
);

export class Contractor extends PersonBase {
  static displayName = 'Contractor';
  static icon = ShieldIcon;

  @field status = contains(ContractorStatusField);
  @field billableRate = contains(NumberField, {
    description: 'Hourly or day rate in dollars',
  });
  @field vatId = contains(StringField, {
    description: 'VAT ID for invoicing',
  });
  @field invoiceFrequency = contains(InvoiceFrequencyField);
  @field contractStartDate = contains(DateField);
  @field contractEndDate = contains(DateField, {
    description: 'When the current contract window closes',
  });
  // One-directional by design — a deliberate live-query choice over a
  // linksToMany back-reference on Contractor, matching PtoRequest's employee link.
  @field vendor = linksTo(() => Vendor, {
    description: 'Agency or supplier this contractor comes through',
  });
  // One-directional by design — a deliberate live-query choice over a
  // linksToMany back-reference on Contractor, matching PtoRequest's employee link.
  @field project = linksTo(() => Project, {
    description: 'Project this contractor is currently staffed on',
  });

  // Signed days until the contract window closes; negative once expired,
  // undefined when no end date is set (an open-ended engagement is not the
  // same fact as one expiring today).
  @field daysRemaining = contains(NumberField, {
    computeVia: function (this: Contractor) {
      return daysUntil(this.contractEndDate);
    },
  });

  // Denormalized for fitted — prerendered fitted reads this own attribute
  // instead of re-deriving from contractEndDate at render time, and the
  // grid stays truthful even before hydration. '' (not undefined) when
  // open-ended so the tile row simply doesn't render.
  @field expiryLabel = contains(StringField, {
    computeVia: function (this: Contractor) {
      let days = daysUntil(this.contractEndDate);
      if (days == null) {
        return '';
      }
      if (days < 0) {
        return 'expired';
      }
      if (days === 0) {
        return 'ends today';
      }
      return `${days}d left`;
    },
  });

  // Denormalized for fitted — prerendered fitted does not resolve linksTo,
  // so the tall tiles read these own attributes instead of walking
  // vendor/project. Same pattern as OnboardingChecklist.personName.
  @field vendorName = contains(StringField, {
    computeVia: function (this: Contractor) {
      return this.vendor?.name ?? '';
    },
  });

  @field projectName = contains(StringField, {
    computeVia: function (this: Contractor) {
      return this.project?.name ?? '';
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: Contractor) {
      return this.name?.trim() || 'Unnamed Contractor';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get v() {
      return contractorView(this.args.model);
    }

    get contractItems() {
      let v = this.v;
      return [
        { key: 'Start', value: orDash(v.start) },
        { key: 'End', value: v.end ?? '— open-ended' },
        { key: 'Invoice frequency', value: orDash(v.invoicing) },
        { key: 'VAT ID', value: orDash(this.args.model?.vatId) },
      ];
    }

    get contactItems() {
      let m = this.args.model;
      return [
        { key: 'Email', value: orDash(m?.email) },
        { key: 'Phone', value: orDash(m?.phone) },
      ];
    }

    get linkedItems() {
      return [
        { key: 'Vendor', value: '— direct' },
        { key: 'Project', value: '— unassigned' },
      ];
    }

    get detailItems() {
      let v = this.v;
      let m = this.args.model;
      return [
        { key: 'Rate', value: orDash(v.rateLong) },
        { key: 'Contract', value: orDash(v.range) },
        { key: 'Ends in', value: orDash(v.daysText) },
        { key: 'Invoicing', value: orDash(v.invoicing) },
        { key: 'VAT ID', value: orDash(m?.vatId) },
        { key: 'Email', value: orDash(m?.email) },
        { key: 'Phone', value: orDash(m?.phone) },
        { key: 'Status', value: orDash(v.statusLabel) },
      ];
    }

    get strip(): StripItem[] {
      let v = this.v;
      return [
        {
          label: 'Billable rate',
          value: v.rateShort,
          hint: v.invoicingLower ? `${v.invoicingLower} invoices` : undefined,
          tone: 'success',
        },
        { label: 'Ends in', value: v.daysText, hint: v.end, tone: 'warning' },
        {
          label: 'Contract length',
          value: v.months,
          hint: v.start ? `from ${v.start}` : undefined,
          tone: 'neutral',
        },
      ];
    }

    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.title}} @meta={{this.v.subtitle}}>
            <:mark><Avatar
                @name={{if @model.name @model.name '?'}}
                @src={{@model.photo.resolvedUrl}}
                @hue={{AVATAR_HUE}}
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside>{{#if @model.status}}<@fields.status
                  @format='atom'
                  @displayContainer={{false}}
                />{{/if}}</:aside>
            <:stats><StatStrip @items={{this.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Contract'><Kv @items={{this.contractItems}} /></Panel>
          <Panel @title='Contact'><Kv @items={{this.contactItems}} /></Panel>
        </:main>
        <:aside>
          <Panel @title='Linked'>
            <Kv @items={{this.linkedItems}}>
              <:value as |row|>
                {{#if (eq row.key 'Vendor')}}
                  {{#if @model.vendor}}<@fields.vendor
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{else}}
                  {{#if @model.project}}<@fields.project
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}{{row.value}}{{/if}}
                {{/if}}
              </:value>
            </Kv>
          </Panel>
          <Panel @title='Details'>
            <Kv @items={{this.detailItems}}>
              <:value as |row|>{{#if (eq row.key 'Status')}}{{#if
                    @model.status
                  }}<@fields.status
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}{{else}}{{row.value}}{{/if}}</:value>
            </Kv>
          </Panel>
        </:aside>
      </IsoPage>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get v() {
      return contractorView(this.args.model);
    }

    get kvItems() {
      let v = this.v;
      return [
        { label: 'Rate', value: v.rateLong },
        { label: 'Contract', value: v.range },
        { label: 'Ends in', value: v.daysText },
        { label: 'Invoicing', value: v.invoicing },
        { label: 'VAT ID', value: this.args.model?.vatId ?? undefined },
        { label: 'Email', value: this.args.model?.email ?? undefined },
      ];
    }

    get rows() {
      return [
        ...this.kvItems.map((i) => ({ key: i.label, value: i.value ?? '—' })),
        { key: 'Vendor', value: '— direct' },
        { key: 'Project', value: '— unassigned' },
      ];
    }

    <template>
      <EmbCard @title={{@model.title}} @meta={{this.v.subtitle}}>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:aside>
        <:default>
          {{#if this.v.end}}
            <p class='emb-fact'>Contract ends
              <strong>{{this.v.end}}</strong>{{#if this.v.invoicingLower}}
                · invoices
                {{this.v.invoicingLower}}{{/if}}</p>
          {{/if}}
          <Kv @items={{this.rows}}>
            <:value as |row|>
              {{#if (eq row.key 'Vendor')}}
                {{#if @model.vendor}}<@fields.vendor
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}{{row.value}}{{/if}}
              {{else if (eq row.key 'Project')}}
                {{#if @model.project}}<@fields.project
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}{{row.value}}{{/if}}
              {{else}}{{row.value}}{{/if}}
            </:value>
          </Kv>
        </:default>
      </EmbCard>
      <style scoped>
        .emb-fact {
          margin: 0;
          padding: 0.4375rem 0.625rem;
          border-top: 1px solid var(--border);
          font-size: 0.75rem;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <RecordAtom @name={{@model.title}} @src={{@model.photo.resolvedUrl}} />
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // Attribute-only: every label comes from the contractor's own
    // (denormalized/computed-scalar) attributes; only the relations render
    // linked cards, as their own atoms.
    get v() {
      return contractorView(this.args.model);
    }

    get strip(): StripItem[] {
      let v = this.v;
      let d = this.args.model?.daysRemaining;
      return [
        { label: 'Rate', value: v.rateShort },
        { label: 'Ends in', value: d == null ? '—' : `${d} d` },
        {
          label: 'Length',
          value: v.months ? v.months.replace(' months', ' mo') : '—',
        },
      ];
    }

    <template>
      <FitCard @title={{@model.title}}>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:status>{{#if @model.status}}<@fields.status
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:status>
        <:default>
          <FitRow @left={{true}}><span
              class='meta'
            >{{this.v.subtitle}}</span></FitRow>
          <FitRow @label='Rate'><span class='mono'>{{orDash
                this.v.rateLong
              }}</span></FitRow>
          <FitRow @label='Ends in'><span class='mono'>{{orDash
                this.v.daysText
              }}</span></FitRow>
          {{#if @model.vendor}}
            <FitRow @label='Vendor' @left={{true}}><@fields.vendor
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <StatStrip @compact={{true}} @items={{this.strip}} />
          {{#if @model.project}}
            <FitRow @label='Project' @left={{true}}><@fields.project
                @format='atom'
                @displayContainer={{false}}
              /></FitRow>
          {{/if}}
          <FitRow @label='Contract'><span class='mono'>{{orDash
                this.v.range
              }}</span></FitRow>
          <FitRow @label='Invoicing'>{{orDash this.v.invoicing}}</FitRow>
          <FitRow @label='VAT ID'><span class='mono'>{{orDash
                @model.vatId
              }}</span></FitRow>
          <FitRow @label='Email'><span class='mono'>{{orDash
                @model.email
              }}</span></FitRow>
          <FitRow @label='Phone'><span class='mono'>{{orDash
                @model.phone
              }}</span></FitRow>
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .mono {
          overflow: hidden;
          text-overflow: ellipsis;
          font: 500 0.6875rem var(--font-mono);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
