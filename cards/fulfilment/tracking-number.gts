import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import { CopyButton } from '@cardstack/pretui/components/copy-button';
import { Token } from '@cardstack/pretui/components/token';
import BarcodeIcon from '@cardstack/boxel-icons/barcode';

// Tracking Number (TN) — a carrier's reference for a package, plus enough
// context to turn it into a link.
//
// The block has no opinion about which carriers exist. A tracking URL is built
// from a pattern the CONSUMER supplies (the Carrier card stores it, and copies
// it onto the shipment when the label is created), so adding a carrier never
// means editing this file. `{number}` is the only placeholder.
export class TrackingNumberField extends FieldDef {
  static displayName = 'Tracking Number';
  static icon = BarcodeIcon;

  @field number = contains(StringField);
  @field carrierCode = contains(StringField);
  @field trackingUrlPattern = contains(StringField);

  @field trackingUrl = contains(StringField, {
    computeVia: function (this: TrackingNumberField) {
      let n = this.number?.trim();
      let pattern = this.trackingUrlPattern?.trim();
      if (!n || !pattern || !pattern.includes('{number}')) {
        return undefined;
      }
      return pattern.replace('{number}', encodeURIComponent(n));
    },
  });

  // Carriers group their reference numbers in fours; unbroken 12-digit runs are
  // near-impossible to read back off a screen to someone on the phone.
  @field grouped = contains(StringField, {
    computeVia: function (this: TrackingNumberField) {
      let n = this.number?.replace(/\s+/g, '');
      if (!n) {
        return undefined;
      }
      return n.replace(/(.{4})/g, '$1 ').trim();
    },
  });

  static atom = class Atom extends Component<typeof TrackingNumberField> {
    <template>
      {{#if @model.number}}
        <span class='tn-atom' title={{@model.number}}>{{@model.number}}</span>
      {{else}}
        <span class='tn-empty'>—</span>
      {{/if}}

      <style scoped>
        .tn-atom {
          font-family: var(--font-mono);
          font-size: 0.9em;
          letter-spacing: 0.02em;
          color: var(--foreground);
        }
        .tn-empty {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<
    typeof TrackingNumberField
  > {
    <template>
      {{#if @model.number}}
        <div class='tn'>
          <div class='tn-main'>
            {{#if @model.carrierCode}}
              <span class='tn-carrier'>{{@model.carrierCode}}</span>
            {{/if}}
            {{#if @model.trackingUrl}}
              <a
                class='tn-link'
                href={{@model.trackingUrl}}
                target='_blank'
                rel='noopener noreferrer'
              ><Token class='tn-token' @value={{@model.grouped}} /></a>
            {{else}}
              <Token class='tn-token' @value={{@model.grouped}} />
            {{/if}}
          </div>
          <CopyButton
            class='tn-copy'
            @text={{@model.number}}
            @label='Copy tracking number'
            @variant='ghost'
            @size='xs'
          />
        </div>
      {{else}}
        <span class='tn-empty'>No tracking number yet</span>
      {{/if}}

      <style scoped>
        .tn {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
        }
        .tn-main {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
        }
        .tn-carrier {
          font-family: var(--font-mono);
          font-size: 0.7rem;
          font-weight: 700;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Pret UI Token: a tracking number is an id. The hue is the muted
           ink, since the number is not an action, and the body knob lands the
           pill at the old 0.85rem (Token draws at the knob minus 3.5px). */
        .tn-main .tn-token {
          --pretui-token-hue: var(--muted-foreground);
          --text-body: calc(0.85rem + 3.5px);
          margin-inline: 0;
          min-width: 0;
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .tn-link {
          display: flex;
          min-width: 0;
        }
        /* Token is an inline block, so the link's underline is drawn on it. */
        .tn-main .tn-link .tn-token {
          text-decoration: underline;
          text-underline-offset: 0.1875rem;
          text-decoration-color: color-mix(
            in oklch,
            var(--foreground) 35%,
            transparent
          );
        }
        /* The copied check reads the success ink, not the fill. */
        .tn-copy :deep(.pretui-copy-check) {
          color: var(--success-ink);
        }
        .tn-empty {
          color: var(--muted-foreground);
          font-size: 0.85rem;
        }
      </style>
    </template>
  };
}

export default TrackingNumberField;
