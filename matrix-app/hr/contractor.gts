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
  RecordAtom,
  RecordEmbedded,
  RecordIsolated,
  Vendor,
  mediumDate,
} from '../procurement/vendor';
import { Avatar } from '../../ui-component/components/avatar';
import { Descriptions } from '../../ui-component/components/descriptions';
import { KeyValue } from '../../ui-component/components/key-value';
import { Panel } from '../../ui-component/components/panel';
import { Stat } from '../../ui-component/components/stat';
import { StatusChip } from '../../ui-component/components/status-chip';
import type { PretuiToneArg } from '../../ui-component/pretui-primitives';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { concat } from '@ember/helper';
import { htmlSafe } from '@ember/template';

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
            <StatusChip
              @value={{statusLabel @model.status}}
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />
          {{/if}}
          {{#if this.v.daysChip}}
            <StatusChip
              @value={{this.v.daysChip}}
              @tone={{this.v.daysTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />
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
            <KeyValue @rows='ruled' @items={{this.contractItems}} />
          </Panel>
          <Panel @title='Contact'>
            <KeyValue @rows='ruled' @items={{this.contactItems}} />
          </Panel>
        </:main>
        <:side>
          <Panel @title='Linked'>
            <KeyValue @rows='ruled' @items={{this.linkedItems}}>
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
            <KeyValue @rows='ruled' @items={{this.detailItems}} />
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
            <StatusChip
              @value={{statusLabel @model.status}}
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />
          {{/if}}
          {{#if this.v.daysChip}}
            <StatusChip
              @value={{this.v.daysChip}}
              @tone={{this.v.daysTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />
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
          <StatusChip
            @value={{statusLabel @model.status}}
            @tone={{this.statusTone}}
            @appearance='soft'
            @shape='pill'
            @dot={{false}}
          />
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

    get progressStyle() {
      return htmlSafe(`inline-size:${this.v.elapsed ?? 0}%`);
    }

    <template>
      <article class='fit'>
        <header class='who'>
          <span class='mark'><Avatar
              @name={{if @model.name @model.name '?'}}
              @src={{@model.photo.resolvedUrl}}
              @hue={{AVATAR_HUE}}
              @size={{32}}
              aria-hidden='true'
            /></span>
          <div class='id'>
            <div class='line1'>
              <h3 class='title'>{{@model.title}}</h3>
              <span class='chips chips-inline'>
                {{#if @model.status}}<StatusChip
                    @value={{statusLabel @model.status}}
                    @tone={{this.v.statusTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  />{{/if}}
                {{#if this.v.daysChip}}<StatusChip
                    class='chip-extra'
                    @value={{this.v.daysChip}}
                    @tone={{this.v.daysTone}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  />{{/if}}
              </span>
            </div>
            <p class='sub'>{{this.v.subtitle}}</p>
          </div>
        </header>
        <span class='chips chips-row'>
          {{#if @model.status}}<StatusChip
              @value={{statusLabel @model.status}}
              @tone={{this.v.statusTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />{{/if}}
          {{#if this.v.daysChip}}<StatusChip
              class='chip-extra'
              @value={{this.v.daysChip}}
              @tone={{this.v.daysTone}}
              @appearance='soft'
              @shape='pill'
              @dot={{false}}
            />{{/if}}
        </span>
        {{#if this.v.end}}<p class='fact'>Contract ends
            <strong>{{this.v.end}}</strong>{{#if this.v.invoicingLower}}
              &middot; invoices
              {{this.v.invoicingLower}}{{/if}}</p>{{/if}}
        {{#if (or @model.vendorName @model.projectName)}}<ul class='rels'>
            {{#if @model.vendorName}}
              <li><span class='k'>Vendor</span><@fields.vendor
                  @format='atom'
                  @displayContainer={{false}}
                /></li>
            {{/if}}
            {{#if @model.projectName}}
              <li><span class='k'>Project</span><@fields.project
                  @format='atom'
                  @displayContainer={{false}}
                /></li>
            {{/if}}
          </ul>{{/if}}
        {{#if this.v.elapsed}}
          <div class='meter'>
            <span class='meter-label'><span>Contract elapsed</span><span
              >{{this.v.elapsed}}%</span></span>
            <span class='meter-bar' aria-hidden='true'><span
                style={{this.progressStyle}}
              ></span></span>
          </div>
        {{/if}}
        <dl class='stats'>
          <div><dt>Billable rate</dt><dd>{{orDash this.v.rateShort}}</dd></div>
          <div><dt>Ends in</dt><dd>{{orDash this.v.daysText}}</dd></div>
          <div><dt>Contract length</dt><dd>{{orDash this.v.months}}</dd></div>
        </dl>
        <dl class='kv'>
          {{#each this.facts as |f|}}
            <div class='kv-i'><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
      </article>
      <style scoped>
        @layer PretComponent {
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
          .kv dd {
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
          .rels {
            font-size: var(--boxel-font-size-xs);
          }
          .sub,
          .fact,
          .k,
          .kv dt {
            color: var(--muted-foreground);
          }
          .fact strong {
            font-weight: 600;
            color: var(--foreground);
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
          .chip-extra,
          .kv,
          .rels .k,
          .stats,
          .meter {
            display: none;
          }
          .chips-inline {
            flex: none;
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
          .stats {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: var(--_fit-gap);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stats dt,
          .stats dd {
            margin: 0;
          }
          .stats dd {
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            color: var(--foreground);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .meter {
            gap: var(--_fit-hair);
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .meter-label {
            display: flex;
            justify-content: space-between;
          }
          .meter-bar {
            display: block;
            block-size: 0.25rem;
            border-radius: var(--boxel-border-radius-pill);
            background: var(--muted);
            overflow: hidden;
          }
          .meter-bar > span {
            display: block;
            block-size: 100%;
            background: var(--primary);
          }

          /* ── per size: the container is the host's fitted-card ── */

          /* the avatar shows from 250 wide and 105 tall, and from 250 tall */
          @container fitted-card ((width >= 250px) and (height >= 105px)) or (height >= 250px) {
            .mark {
              display: block;
            }
          }
          /* the days-left chip joins the status from 250 wide */
          @container fitted-card (width >= 250px) {
            .chip-extra {
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
            .fact strong {
              font-weight: inherit;
              color: inherit;
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
              max-block-size: 1.375rem;
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
          /* under 65 tall: status only beside the title */
          @container fitted-card (height < 65px) {
            .sub,
            .chip-extra {
              display: none;
            }
          }
          @container fitted-card (height < 65px) and (width < 250px) {
            .chips-inline {
              display: none;
            }
          }
          @container fitted-card (height < 105px) and (width < 400px) {
            .chip-extra {
              display: none;
            }
          }
          /* 250 tall: roomier padding; under 250 wide the avatar stacks
             above the name */
          @container fitted-card (height >= 250px) {
            .fit {
              padding: var(--boxel-sp);
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
          /* 275 tall: progress and the remaining facts fill the space left */
          @container fitted-card (height >= 275px) {
            .kv,
            .meter {
              display: grid;
            }
          }
          @container fitted-card (height >= 275px) and (height < 400px) and (width >= 400px) {
            .kv {
              grid-template-columns: repeat(2, minmax(0, 1fr));
            }
          }
          /* 400 tall: the headline numbers lead */
          @container fitted-card (height >= 400px) {
            .stats {
              display: grid;
            }
          }
        }
      </style>
    </template>
  };
}
