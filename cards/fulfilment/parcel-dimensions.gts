import {
  Component,
  FieldDef,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import BoxIcon from '@cardstack/boxel-icons/box';

// Parcel Dimensions (PD) — what the packing station measures, and what the
// carrier actually bills on.
//
// Carriers charge for the greater of actual weight and *volumetric* weight
// (a big light box occupies the same van space as a small heavy one). The
// divisor that converts volume to weight differs per carrier, so the block does
// not pick one: the consumer supplies `dimDivisor` (the Carrier card stores it
// and stamps it onto the shipment). With no divisor the block reports actual
// weight rather than inventing a number.
//
// Non-goals: metric only. An imperial variant is a separate concern and would
// need unit-aware serialization, not a display toggle.
export class ParcelDimensionsField extends FieldDef {
  static displayName = 'Parcel Dimensions';
  static icon = BoxIcon;

  @field length = contains(NumberField);
  @field width = contains(NumberField);
  @field height = contains(NumberField);
  @field weight = contains(NumberField);
  @field dimDivisor = contains(NumberField);

  @field volume = contains(NumberField, {
    computeVia: function (this: ParcelDimensionsField) {
      let { length: l, width: w, height: h } = this;
      if (!l || !w || !h) {
        return undefined;
      }
      return Math.round(l * w * h);
    },
  });

  @field volumetricWeight = contains(NumberField, {
    computeVia: function (this: ParcelDimensionsField) {
      let volume = this.volume;
      let divisor = this.dimDivisor;
      if (!volume || !divisor) {
        return undefined;
      }
      return Math.round((volume / divisor) * 100) / 100;
    },
  });

  @field billableWeight = contains(NumberField, {
    computeVia: function (this: ParcelDimensionsField) {
      let actual = this.weight ?? 0;
      let volumetric = this.volumetricWeight ?? 0;
      let billable = Math.max(actual, volumetric);
      return billable > 0 ? billable : undefined;
    },
  });

  get sizeLabel() {
    let { length: l, width: w, height: h } = this;
    if (!l || !w || !h) {
      return undefined;
    }
    return `${l} × ${w} × ${h} cm`;
  }

  // True when the carrier will bill more than the scale says — the number a
  // packer can act on by choosing a smaller box.
  get isVolumetric() {
    return (
      this.volumetricWeight != null &&
      this.weight != null &&
      this.volumetricWeight > this.weight
    );
  }

  static atom = class Atom extends Component<typeof ParcelDimensionsField> {
    <template>
      {{#if @model.billableWeight}}
        <span class='pd-atom'>{{@model.billableWeight}} kg</span>
      {{else}}
        <span class='pd-atom pd-empty'>Not measured</span>
      {{/if}}

      <style scoped>
        .pd-atom {
          font-family: var(--font-mono);
          font-size: 0.9em;
          font-variant-numeric: tabular-nums;
          color: var(--foreground);
        }
        .pd-empty {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof ParcelDimensionsField
  > {
    <template>
      <div class='pd'>
        <span class='pd-size'>{{if
            @model.sizeLabel
            @model.sizeLabel
            'Unmeasured parcel'
          }}</span>
        <span class='pd-sep' aria-hidden='true'></span>
        <span class='pd-weight'>{{if @model.weight @model.weight '—'}} kg</span>
        {{#if @model.isVolumetric}}
          <span class='pd-billable'>bills at
            {{@model.volumetricWeight}}
            kg</span>
        {{/if}}
      </div>

      <style scoped>
        .pd {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs);
          font-size: 0.85rem;
          color: var(--foreground);
        }
        .pd-size {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .pd-sep {
          width: 0.1875rem;
          height: 0.1875rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .pd-weight {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
        /* The dimensional-weight warning is the only thing here a packer can
           act on, so it is the only thing that gets a tint. */
        .pd-billable {
          font-size: 0.75rem;
          font-weight: 600;
          padding: 0.0625rem 0.375rem;
          border-radius: 999px;
          color: var(--muted-foreground);
          background-color: color-mix(
            in oklch,
            var(--muted-foreground) 12%,
            transparent
          );
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof ParcelDimensionsField> {
    <template>
      <fieldset class='pd-edit'>
        <legend class='pd-legend'>Measured at the packing station</legend>
        <div class='pd-grid'>
          <FieldContainer @label='Length (cm)' @vertical={{true}}>
            <@fields.length />
          </FieldContainer>
          <FieldContainer @label='Width (cm)' @vertical={{true}}>
            <@fields.width />
          </FieldContainer>
          <FieldContainer @label='Height (cm)' @vertical={{true}}>
            <@fields.height />
          </FieldContainer>
          <FieldContainer @label='Weight (kg)' @vertical={{true}}>
            <@fields.weight />
          </FieldContainer>
        </div>

        {{#if @model.billableWeight}}
          <p class='pd-readout'>
            Billable weight
            <strong>{{@model.billableWeight}} kg</strong>
            {{#if @model.isVolumetric}}
              — volumetric, from
              {{@model.volume}}
              cm³. A smaller box would lower this.
            {{else}}
              — actual weight.
            {{/if}}
          </p>
        {{/if}}
      </fieldset>

      <style scoped>
        .pd-edit {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          padding: var(--boxel-sp-sm);
          margin: 0;
          background-color: var(--card);
        }
        .pd-legend {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding: 0 var(--boxel-sp-2xs);
        }
        .pd-grid {
          display: grid;
          gap: var(--boxel-sp-xs);
          grid-template-columns: repeat(auto-fit, minmax(5.5rem, 1fr));
        }
        .pd-readout {
          margin: var(--boxel-sp-sm) 0 0;
          font-size: 0.8rem;
          color: var(--muted-foreground);
        }
        .pd-readout strong {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          color: var(--foreground);
        }
      </style>
    </template>
  };
}

export default ParcelDimensionsField;
