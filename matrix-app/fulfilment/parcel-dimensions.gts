import {
  Component,
  FieldDef,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import { Chip } from '@cardstack/pretui/components/chip';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
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
        <FormatNumber
          class='pd-atom'
          @value={{@model.billableWeight}}
          @style='unit'
          @unit='kilogram'
        />
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
        <FormatNumber
          class='pd-weight'
          @value={{@model.weight}}
          @style='unit'
          @unit='kilogram'
        />
        {{#if @model.isVolumetric}}
          <Chip class='pd-billable' @dot={{false}}>bills at
            <FormatNumber
              @value={{@model.volumetricWeight}}
              @style='unit'
              @unit='kilogram'
            /></Chip>
        {{/if}}
      </div>

      <style scoped>
        .pd {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-sm);
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
           act on, so it is the only thing that gets a tint: a Pret UI Chip on
           its default muted hue, at StatePill's checked recipe. */
        .pd .pd-billable {
          --pretui-chip-mix: 14%;
          --pretui-ink-mix: 62%;
          --pretui-chip-font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
      </style>
    </template>
  };
}

export default ParcelDimensionsField;
