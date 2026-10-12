import { Component, StringField } from '@cardstack/base/card-api';
import CertificateIcon from '@cardstack/boxel-icons/certificate';

import { formatMemberNumber } from '@cardstack/catalog/cards/loyalty/member-number-field';

/**
 * The number printed on a certificate and quoted by whoever verifies it —
 * a label, not a key. Shape is the realm's shared `PREFIX-YYYY-SEQUENCE`
 * (reusing `formatMemberNumber` from the Member Number block, width 6), so a
 * certificate and a membership card read as siblings. Sequencing is the
 * Certification Authority's job: it stores `lastSequence`, and Issue
 * Certificate increments it — a realm has no global counter.
 */
export class CertificateNumberField extends StringField {
  static displayName = 'Certificate Number';
  static icon = CertificateIcon;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='cert-no'>{{if @model @model '—'}}</span>
      <style scoped>
        .cert-no {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          letter-spacing: 0.04em;
          color: var(--foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='cert-no-atom'>{{if @model @model '—'}}</span>
      <style scoped>
        .cert-no-atom {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.04em;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export const CERTIFICATE_NUMBER_PATTERN = /^[A-Z0-9]{2,8}-\d{4}-\d{6}$/;

export function nextCertificateNumber(
  prefix: string | null | undefined,
  year: number,
  lastSequence: number | null | undefined,
): { number: string; sequence: number } {
  let sequence = (lastSequence ?? 0) + 1;
  let p = (prefix?.trim() || 'CERT').toUpperCase().replace(/[^A-Z0-9]/g, '');
  return { number: formatMemberNumber(p, year, sequence, 6), sequence };
}

export function isValidCertificateNumber(n?: string | null): boolean {
  return !!n && CERTIFICATE_NUMBER_PATTERN.test(n);
}

export default CertificateNumberField;
