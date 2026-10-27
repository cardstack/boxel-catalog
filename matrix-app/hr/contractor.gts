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
import ShieldIcon from '@cardstack/boxel-icons/shield';

import { PersonBase } from '../people/person-base';
import { Project } from '../projects/project';
import {
  FittedExtras,
  RecordAtom,
  RecordEmbedded,
  RecordIsolated,
  Vendor,
  mediumDate,
  type FittedProgress,
  type FittedStat,
} from '../procurement/vendor';
import { Avatar } from '../../ui-component/components/avatar';
import { Descriptions } from '../../ui-component/components/descriptions';
import { FitTile } from '../../ui-component/components/fit-tile';
import { KeyValue } from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { eq } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';

import { type Hue } from '@cardstack/catalog/components/state-pill';
import { stateColorsOf } from './hr-ui';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { daysUntil } from '@cardstack/catalog/fields/effective-period/effective-period-field';

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

export const ContractorStatusField = enumField(StringField, {
  options: CONTRACTOR_STATUSES.map((status) => ({
    value: status,
    label: status,
  })),
  displayName: 'Contract Status',
});

export const InvoiceFrequencyOptions = ['monthly', 'quarterly', 'annually'];

export const InvoiceFrequencyField = enumField(StringField, {
  options: InvoiceFrequencyOptions.map((freq) => ({
    value: freq,
    label: freq,
  })),
  displayName: 'Invoice Frequency',
});

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

    <template>
      <RecordIsolated @title={{@model.title}} @subtitle={{this.v.subtitle}}>
        <:avatar><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.v.statusTone}} />
          {{/if}}
          {{#if this.v.daysChip}}
            <StatusChip @value={{this.v.daysChip}} @tone={{this.v.daysTone}} />
          {{/if}}
        </:chips>
        <:stats>
          <Panel><Stat
              @label='Billable rate'
              @value={{orDash this.v.rateShort}}
              @hint={{if
                this.v.invoicingLower
                (concat this.v.invoicingLower ' invoices')
              }}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Ends in'
              @value={{orDash this.v.daysText}}
              @hint={{this.v.end}}
              @roll={{false}}
            /></Panel>
          <Panel><Stat
              @label='Contract length'
              @value={{orDash this.v.months}}
              @hint={{if this.v.start (concat 'from ' this.v.start)}}
              @roll={{false}}
            /></Panel>
        </:stats>
        <:main>
          <Panel @title='Contract'>
            <KeyValue @items={{this.contractItems}} />
          </Panel>
          <Panel @title='Contact'>
            <KeyValue @items={{this.contactItems}} />
          </Panel>
        </:main>
        <:side>
          <Panel @title='Linked'>
            <KeyValue @items={{this.linkedItems}}>
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
            </KeyValue>
          </Panel>
          <Panel @title='Details'>
            <KeyValue @items={{this.detailItems}} />
          </Panel>
        </:side>
      </RecordIsolated>
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

    <template>
      <RecordEmbedded @title={{@model.title}} @subtitle={{this.v.subtitle}}>
        <:avatar><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{40}}
            aria-hidden='true'
          /></:avatar>
        <:chips>
          {{#if @model.status}}
            <StatusChip @value={{@model.status}} @tone={{this.v.statusTone}} />
          {{/if}}
          {{#if this.v.daysChip}}
            <StatusChip @value={{this.v.daysChip}} @tone={{this.v.daysTone}} />
          {{/if}}
        </:chips>
        <:fact>{{#if this.v.end}}Contract ends
            <b class='strong'>{{this.v.end}}</b>{{#if this.v.invoicingLower}}
              &middot; invoices
              {{this.v.invoicingLower}}{{/if}}{{/if}}</:fact>
        <:details><Descriptions
            @items={{this.kvItems}}
            @layout='vertical'
            @columns={{3}}
          /></:details>
        <:relations>
          {{#if @model.vendor}}
            <span class='rel'>Vendor
              <@fields.vendor
                @format='atom'
                @displayContainer={{false}}
              /></span>
          {{/if}}
          {{#if @model.project}}
            <span class='rel'>Project
              <@fields.project
                @format='atom'
                @displayContainer={{false}}
              /></span>
          {{/if}}
        </:relations>
      </RecordEmbedded>
      <style scoped>
        @layer PretComponent {
          .strong {
            font-weight: 600;
            color: var(--foreground);
          }
          .rel {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-xs);
            min-inline-size: 0;
            max-inline-size: 100%;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get statusTone() {
      return contractorView(this.args.model).statusTone;
    }

    <template>
      <RecordAtom @name={{@model.title}} @src={{@model.photo.resolvedUrl}}>
        {{#if @model.status}}
          <StatusChip @value={{@model.status}} @tone={{this.statusTone}} />
        {{/if}}
      </RecordAtom>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // Attribute-only: every label comes from the contractor's own
    // (denormalized/computed-scalar) attributes; only the relations render
    // linked cards, as their own atoms.
    get v() {
      return contractorView(this.args.model);
    }

    get facts() {
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

    get stats(): FittedStat[] {
      let v = this.v;
      return [
        { key: 'Billable rate', value: orDash(v.rateShort) },
        { key: 'Ends in', value: orDash(v.daysText) },
        { key: 'Contract length', value: orDash(v.months) },
      ];
    }

    get progress(): FittedProgress | undefined {
      let elapsed = this.v.elapsed;
      return elapsed == null
        ? undefined
        : {
            label: 'Contract elapsed',
            value: elapsed,
            valueText: `${elapsed}%`,
          };
    }

    get relations() {
      let m = this.args.model;
      return [
        ...(m?.vendorName ? ['Vendor'] : []),
        ...(m?.projectName ? ['Project'] : []),
      ];
    }

    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @progress={{this.progress}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name={{if @model.name @model.name '?'}}
                @src={{@model.photo.resolvedUrl}}
                @hue={{AVATAR_HUE}}
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
              {{#if @model.status}}
                <StatusChip
                  @value={{@model.status}}
                  @tone={{this.v.statusTone}}
                />
              {{/if}}
              {{#if this.v.daysChip}}
                <StatusChip
                  @value={{this.v.daysChip}}
                  @tone={{this.v.daysTone}}
                />
              {{/if}}
            </:status>
            <:fact>{{#if this.v.end}}Contract ends
                {{this.v.end}}{{#if this.v.invoicingLower}}
                  &middot; invoices
                  {{this.v.invoicingLower}}{{/if}}{{/if}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Vendor')}}
            <@fields.vendor @format='atom' />
          {{else}}
            <@fields.project @format='atom' />
          {{/if}}
        </:relation>
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
