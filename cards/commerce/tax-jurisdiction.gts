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
import { hasNumber } from '../crm/utils';
import { IsoFrame } from '../shared/compact-sheet';

// Tax Jurisdiction — a region with its own tax rate. A lookup table, reused
// across every invoice for that region, not duplicated per invoice.

function rateFraction(rate?: number | null) {
  return (rate ?? 0) / 100;
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
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
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
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
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
          gap: var(--boxel-sp-xs);
        }
        .doc-icon {
          width: 1.125rem;
          height: 1.125rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          flex: 1;
        }
        .rate {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-xs);
          white-space: nowrap;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            justify-content: center;
            padding: var(--boxel-sp-xs);
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) {
          .strip {
            display: flex;
            padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof TaxJurisdiction> {
    <template>
      <IsoFrame>
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
      </IsoFrame>
      <style scoped>
        .tj-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 32rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .th {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
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
          margin: 0 0 var(--boxel-sp-6xs);
          color: var(--muted-foreground);
        }
        h1 {
          font-size: var(--boxel-font-size-lg);
          line-height: 1.1;
        }
        .rate-line {
          font-size: var(--boxel-font-size);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
