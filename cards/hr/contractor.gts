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

import { PersonBase } from '@cardstack/catalog/cards/people/person-base';
import { Project } from '@cardstack/catalog/cards/projects/project';
import { Vendor } from '@cardstack/catalog/cards/procurement/vendor';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { eq } from '@cardstack/boxel-ui/helpers';

import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import {
  AVATAR_HUE,
  FactList,
  QUIET_AVATAR_HUE,
  hueOf,
  stateColorsOf,
} from './hr-ui';

// Inside this window the contract window turns amber; past zero it turns red.
const EXPIRY_WARNING_DAYS = 30;

// Signed variant of utils' daysBetween — that helper clamps at 0
// (Math.max(0, …)), which is right for "days since applied" but erases the
// difference between "ends today" and "ended three weeks ago". A contract
// window needs the sign.
function signedDaysUntil(date?: Date | string | null): number | undefined {
  if (!date) {
    return undefined;
  }
  let end = new Date(date);
  if (isNaN(end.getTime())) {
    return undefined;
  }
  return Math.round((end.getTime() - Date.now()) / 86400000);
}

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
      return signedDaysUntil(this.contractEndDate);
    },
  });

  // Denormalized for fitted — prerendered fitted reads this own attribute
  // instead of re-deriving from contractEndDate at render time, and the
  // grid stays truthful even before hydration. '' (not undefined) when
  // open-ended so the tile row simply doesn't render.
  @field expiryLabel = contains(StringField, {
    computeVia: function (this: Contractor) {
      let days = signedDaysUntil(this.contractEndDate);
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
    get rateLabel(): string | undefined {
      let rate = this.args.model?.billableRate;
      if (rate == null) {
        return undefined;
      }
      return `$${rate}/hr`;
    }

    get expiryToneKey(): string | undefined {
      return expiryTone(this.args.model?.daysRemaining ?? undefined);
    }

    get daysRemainingLabel(): string | undefined {
      let days = this.args.model?.daysRemaining;
      if (days == null) {
        return undefined;
      }
      if (days < 0) {
        return `expired ${Math.abs(days)}d ago`;
      }
      if (days === 0) {
        return 'ends today';
      }
      return `${days} days remaining`;
    }

    get contactFacts() {
      let m = this.args.model;
      return [
        { key: 'Email', value: m?.email || '—' },
        { key: 'Phone', value: m?.phone || '—' },
      ];
    }

    get termsFacts() {
      return [
        { key: 'Billable rate', value: this.rateLabel ?? '—' },
        {
          key: 'Invoice frequency',
          value: this.args.model?.invoiceFrequency || '—',
        },
      ];
    }

    get contractFacts() {
      return [
        { key: 'Status', value: this.args.model?.status || '—' },
        { key: 'Starts', value: '' },
        { key: 'Ends', value: '' },
        { key: 'Remaining', value: '' },
        { key: 'Vendor', value: '' },
        { key: 'Project', value: '' },
        { key: 'VAT ID', value: this.args.model?.vatId || '—' },
      ];
    }

    <template>
      <article class='contractor-isolated'>
        <header class='hero'>
          <Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{52}}
            aria-hidden='true'
          />
          <div class='hero-text'>
            <h1>{{@model.title}}</h1>
            <p class='byline'>Contractor</p>
            <div class='pill-row'>
              {{#if @model.status}}
                <StatePill
                  @label={{@model.status}}
                  @hue={{hueOf CONTRACTOR_STATUS_HUES @model.status}}
                  @dot={{true}}
                />
              {{/if}}
              {{#if this.rateLabel}}
                <StatePill @label={{this.rateLabel}} />
              {{/if}}
            </div>
          </div>
        </header>

        <div class='body'>
          <div class='main'>
            <h2 class='panel-title'>Contact</h2>
            <FactList @items={{this.contactFacts}} />

            <h2 class='panel-title spaced'>Rate & Terms</h2>
            <FactList @items={{this.termsFacts}} />
          </div>

          <aside class='side'>
            <h2 class='panel-title'>Contract</h2>
            <FactList @items={{this.contractFacts}}>
              <:value as |row|>
                {{#if (eq row.key 'Starts')}}
                  {{#if @model.contractStartDate}}<@fields.contractStartDate
                    />{{else}}&mdash;{{/if}}
                {{else if (eq row.key 'Ends')}}
                  {{#if @model.contractEndDate}}<@fields.contractEndDate
                    />{{else}}&mdash; open-ended{{/if}}
                {{else if (eq row.key 'Remaining')}}
                  {{#if this.daysRemainingLabel}}
                    <StatePill
                      @label={{this.daysRemainingLabel}}
                      @hue={{hueOf EXPIRY_TONE_HUES this.expiryToneKey}}
                    />
                  {{else}}&mdash;{{/if}}
                {{else if (eq row.key 'Vendor')}}
                  {{#if @model.vendor}}<@fields.vendor
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}&mdash; direct{{/if}}
                {{else if (eq row.key 'Project')}}
                  {{#if @model.project}}<@fields.project
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}&mdash; unassigned{{/if}}
                {{else}}
                  {{row.value}}
                {{/if}}
              </:value>
            </FactList>
          </aside>
        </div>
      </article>
      <style scoped>
        .contractor-isolated {
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
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
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
        .pill-row {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-5xs);
          margin-top: var(--boxel-sp-xs);
        }
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
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
        }
        .panel-title.spaced {
          margin-top: var(--boxel-sp-lg);
        }
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
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    // The expiry chip only appears when the window is closing (or closed);
    // an expiry that needs no action is noise in a one-line row.
    get expiryTone() {
      return expiryTone(this.args.model?.daysRemaining ?? undefined);
    }

    <template>
      <div class='contractor-embedded'>
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{QUIET_AVATAR_HUE}}
          @size={{28}}
          aria-hidden='true'
        />
        <div class='ce-main'>
          <span class='ce-name'>{{if @model.name @model.name 'Unnamed'}}</span>
        </div>
        <div class='ce-side'>
          {{#if @model.status}}
            <StatePill
              @label={{@model.status}}
              @hue={{hueOf CONTRACTOR_STATUS_HUES @model.status}}
            />
          {{/if}}
          {{#if this.expiryTone}}
            <StatePill
              @label={{@model.expiryLabel}}
              @hue={{hueOf EXPIRY_TONE_HUES this.expiryTone}}
            />
          {{/if}}
        </div>
      </div>
      <style scoped>
        .contractor-embedded {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.75rem;
          font-size: 0.8125rem;
        }
        .ce-main {
          display: flex;
          flex-direction: column;
          gap: 0.0625rem;
          min-width: 0;
          flex: 1;
        }
        .ce-name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ce-side {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: 0.1875rem;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get expiryTone() {
      return expiryTone(this.args.model?.daysRemaining ?? undefined);
    }

    <template>
      <span class='contractor-atom'>
        <span class='contractor-atom-name'>{{@model.title}}</span>
        {{#if this.expiryTone}}
          <StatePill
            class='contractor-atom-chip'
            @label={{@model.expiryLabel}}
            @hue={{hueOf EXPIRY_TONE_HUES this.expiryTone}}
          />
        {{/if}}
      </span>
      <style scoped>
        .contractor-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .contractor-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .contractor-atom-chip {
          flex: none;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get rateLabel(): string | undefined {
      let rate = this.args.model?.billableRate;
      if (rate == null) {
        return undefined;
      }
      return `$${rate}/hr`;
    }

    // Attribute-only: expiryLabel and daysRemaining are the contractor's OWN
    // (denormalized/computed-scalar) attributes — no linksTo read happens in
    // this prerendered format.
    get expiryTone() {
      return expiryTone(this.args.model?.daysRemaining ?? undefined);
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          <Avatar
            class='avatar'
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{28}}
            aria-hidden='true'
          />
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
          </div>
          {{#if @model.status}}
            <StatePill
              class='fit-pill'
              @label={{@model.status}}
              @hue={{hueOf CONTRACTOR_STATUS_HUES @model.status}}
              @dot={{true}}
            />
          {{/if}}
        </div>

        <div class='fit-mid'>
          {{#if this.rateLabel}}
            <span class='money'>{{this.rateLabel}}</span>
          {{/if}}
          {{#if @model.expiryLabel}}
            {{#if this.expiryTone}}
              <StatePill
                class='fit-expiry'
                @label={{@model.expiryLabel}}
                @hue={{hueOf EXPIRY_TONE_HUES this.expiryTone}}
              />
            {{else}}
              <span class='fit-sub'>{{@model.expiryLabel}}</span>
            {{/if}}
          {{/if}}
        </div>

        <dl class='fit-add'>
          {{#if @model.contractEndDate}}
            <div><dt>Ends</dt><dd><@fields.contractEndDate /></dd></div>
          {{/if}}
          {{#if @model.invoiceFrequency}}
            <div><dt>Invoice</dt><dd>{{@model.invoiceFrequency}}</dd></div>
          {{/if}}
          {{#if @model.vatId}}
            <div><dt>VAT</dt><dd>{{@model.vatId}}</dd></div>
          {{/if}}
          {{! Denormalized own attributes — safe in prerendered fitted. }}
          {{#if @model.vendorName}}
            <div class='deep'><dt>Vendor</dt><dd
              >{{@model.vendorName}}</dd></div>
          {{/if}}
          {{#if @model.projectName}}
            <div class='deep'><dt>Project</dt><dd
              >{{@model.projectName}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: 0.28rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          --fit-name: clamp(11px, 3.2cqi, 15px);
          --fit-small: clamp(11px, 2.6cqi, 12px);
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
          overflow: visible;
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
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        .fit-mid {
          flex: none;
          display: none;
          flex-direction: column;
          gap: 1px;
        }
        .money {
          font-size: calc(var(--fit-name) * 1.15);
          font-weight: 800;
          letter-spacing: -0.02em;
          font-variant-numeric: tabular-nums;
        }
        .fit-sub {
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-expiry {
          align-self: flex-start;
        }
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
        }

        /* Vendor/project rows only join on the tall cells. */
        .fit-add > .deep {
          display: none;
        }

        @container fitted-card (height > 80px) {
          .fit-mid {
            display: flex;
          }
        }
        @container fitted-card (width > 240px) {
          .fit-mid {
            display: flex;
          }
        }
        /* Double Strip (250×65): the expiry chip row half-clips — the rate
           figure alone fits, so the chip yields below 105px. */
        @container fitted-card (height < 105px) {
          .fit-expiry,
          .fit-mid .fit-sub {
            display: none;
          }
        }
        @container fitted-card (height > 130px) and (width >= 170px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 340px) and (height > 130px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }
        /* TIER 5 — vendor + project names on tall cells. */
        @container fitted-card (height >= 170px) and (width >= 170px) {
          .fit-add > .deep {
            display: flex;
          }
        }
        @container fitted-card (height <= 90px) {
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
      </style>
    </template>
  };
}
