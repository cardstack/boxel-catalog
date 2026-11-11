import { Component } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Token } from '@cardstack/pretui/components/token';
import { ID_TOKEN_STYLE } from '@cardstack/catalog/components/pretui-helpers';

// Purchase Order number — the immutable document identity referenced on
// packing slips, invoices, and audits. Snapshot pattern (same as Invoice
// Number): AwardRfqCommand / ApprovePurchaseOrderCommand assign it exactly
// once at issue time and nothing ever recomputes it. The field itself is a
// StringField that renders in document style (mono, tabular) so a PO number
// reads as a reference everywhere it appears. Embedded keeps plain document
// type because the Purchase Order sets it as its headline; the atom is a
// Pret UI Token.
export class PONumberField extends StringField {
  static displayName = 'PO Number';

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='po-number'>{{@model}}</span>
      <style scoped>
        .po-number {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          letter-spacing: 0.02em;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      {{#if @model}}
        <Token @value={{@model}} style={{ID_TOKEN_STYLE.sm}} />
      {{/if}}
    </template>
  };
}

// Sequence helper used by the single writers that stamp a number at issue
// time. Year-scoped; the tail is the issue time in base-36 plus a random
// suffix, so two numbers collide only when issued in the same millisecond
// and the suffix also matches. shortcut: no uniqueness check against stored
// POs; upgrade to a counter service when issuance is concurrent at scale.
export function nextPoNumber(now: Date = new Date()): string {
  let time = now.getTime().toString(36).toUpperCase();
  let salt = Math.floor(Math.random() * 36 ** 3)
    .toString(36)
    .toUpperCase()
    .padStart(3, '0');
  return `PO-${now.getFullYear()}-${time}${salt}`;
}

export default PONumberField;
