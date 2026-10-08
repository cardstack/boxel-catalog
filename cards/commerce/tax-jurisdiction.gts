import {
  CardDef,
  Component,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import PercentageField from '@cardstack/base/percentage';
import LandmarkIcon from '@cardstack/boxel-icons/landmark';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';

// Tax Jurisdiction — a region with its own tax rate. A lookup table, reused
// across every invoice for that region, not duplicated per invoice.

function rateFraction(rate: number) {
  return rate / 100;
}

// The rate as every format shows it, a 0% rate included.
const RatePercent: TemplateOnlyComponent<{
  Args: { rate?: number | null };
  Element: HTMLSpanElement;
}> = <template>
  {{#if (hasNumber @rate)}}
    <span ...attributes><FormatNumber
        @value={{rateFraction @rate}}
        @style='percent'
        @locale='en-US'
        @maximumFractionDigits={{4}}
      /></span>
  {{/if}}
</template>;

export class TaxJurisdiction extends CardDef {
  static displayName = 'Tax Jurisdiction';
  static icon = LandmarkIcon;

  @field country = contains(StringField);
  @field region = contains(StringField);
  @field rate = contains(PercentageField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: TaxJurisdiction) {
      if (!this.country?.trim()) {
        return `Untitled ${this.constructor.displayName}`;
      }
      return this.region ? `${this.region}, ${this.country}` : this.country;
    },
  });

  static atom = class Atom extends Component<typeof TaxJurisdiction> {
    <template>
      <span class='tj-atom'>
        <LandmarkIcon class='tja-icon' />
        <span class='tja-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .tj-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .tja-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .tja-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof TaxJurisdiction> {
    <template>
      <div class='tj-row'>
        <LandmarkIcon class='icon' />
        <span class='name'>{{@model.cardTitle}}</span>
        <RatePercent class='rate' @rate={{@model.rate}} />
      </div>
      <style scoped>
        .tj-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: 0.875rem;
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          flex: 1;
          font-weight: 600;
        }
        .rate {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof TaxJurisdiction> {
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <LandmarkIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
          <RatePercent class='rate' @rate={{@model.rate}} />
        </div>
        <div class='fmt strip'>
          <LandmarkIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
          <RatePercent class='rate' @rate={{@model.rate}} />
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
          align-items: center;
          gap: 0.5rem;
        }
        .doc-icon {
          width: 1.125rem;
          height: 1.125rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
        }
        .rate {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: 0.8125rem;
          white-space: nowrap;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            justify-content: center;
            padding: 0.5rem;
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) {
          .strip {
            display: flex;
            padding: 0.625rem 0.75rem;
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof TaxJurisdiction> {
    <template>
      <article class='tj-page'>
        <header class='th'>
          <LandmarkIcon class='avatar-icon' />
          <div class='th-id'>
            <p class='doc-kind'>Tax Jurisdiction</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
        </header>
        {{#if (hasNumber @model.rate)}}
          <p class='rate-line'><RatePercent @rate={{@model.rate}} /> rate</p>
        {{/if}}
      </article>
      <style scoped>
        .tj-page {
          max-width: 32rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1rem;
        }
        .th {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 2px solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .avatar-icon {
          width: 2.5rem;
          height: 2.5rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .doc-kind {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          margin: 0 0 0.125rem;
          color: var(--muted-foreground);
        }
        h1 {
          margin: 0;
          font-size: 1.625rem;
          line-height: 1.1;
        }
        .rate-line {
          font-size: 1.125rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          margin: 0;
        }
      </style>
    </template>
  };
}
