import GlimmerComponent from '@glimmer/component';
import { getComponent } from '@cardstack/base/card-api';
import QRField from '@cardstack/catalog/fields/qr-code/qr-code';

type LabelSize = 'sm' | 'md' | 'lg';

interface Signature {
  Args: {
    /** The human identifier printed under the code — "AST-2026-0041". */
    value: string;
    /** What the QR encodes; defaults to `value`. Pass the card URL so a phone camera opens the card. */
    payload?: string;
    /** Second line — the thing's name. */
    name?: string;
    /** Third line — location short path, category, anything small. */
    sub?: string;
    /** 25×15 mm (sm), 50×25 mm (md, default), 100×50 mm (lg). */
    size?: LabelSize;
    /** Render with a print-cut border. */
    outlined?: boolean;
  };
  Element: HTMLElement;
}

/**
 * A printable label for any Record Identifier: QR + the id in monospace +
 * up to two lines of context. Identical on screen and on paper.
 *
 * The QR itself is the catalog's `fields/qr-code` field (consumed, not
 * rebuilt): a QRField instance is constructed from the payload and its
 * embedded template renders the SVG. This component owns only the label
 * layout and the three physical sizes.
 *
 * Generic: any card with a Record Identifier can mount it.
 */
export class QrLabel extends GlimmerComponent<Signature> {
  get size(): LabelSize {
    return this.args.size ?? 'md';
  }

  get payload() {
    return this.args.payload ?? this.args.value;
  }

  get qr() {
    let instance = new QRField({ data: this.payload });
    return getComponent(instance);
  }

  <template>
    <figure
      class='qr-label qr-label--{{this.size}}
        {{if @outlined "qr-label--outlined"}}'
      ...attributes
    >
      <div class='qr-label-code'>
        <this.qr @format='embedded' />
      </div>
      <figcaption class='qr-label-text'>
        <code class='qr-label-id'>{{@value}}</code>
        {{#if @name}}<span class='qr-label-name'>{{@name}}</span>{{/if}}
        {{#if @sub}}<span class='qr-label-sub'>{{@sub}}</span>{{/if}}
      </figcaption>
    </figure>
    <style scoped>
      .qr-label {
        --label-w: 50mm;
        --label-h: 25mm;
        --label-pad: 2mm;
        --id-size: 3.2mm;
        --line-size: 2.4mm;
        margin: 0;
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: var(--label-pad);
        align-items: center;
        width: var(--label-w);
        height: var(--label-h);
        padding: var(--label-pad);
        box-sizing: border-box;
        background: var(--card);
        color: var(--foreground);
        border-radius: 1.5mm;
        overflow: hidden;
        break-inside: avoid;
      }
      .qr-label--outlined {
        border: 0.25mm dashed var(--border);
      }
      .qr-label--sm {
        --label-w: 25mm;
        --label-h: 15mm;
        --label-pad: 1mm;
        --id-size: 2mm;
        --line-size: 1.6mm;
      }
      .qr-label--lg {
        --label-w: 100mm;
        --label-h: 50mm;
        --label-pad: 4mm;
        --id-size: 6mm;
        --line-size: 4mm;
      }
      .qr-label-code {
        height: calc(var(--label-h) - 2 * var(--label-pad));
        aspect-ratio: 1;
        display: grid;
        place-items: center;
        background: white;
        border-radius: 1mm;
        padding: 0.5mm;
        box-sizing: border-box;
      }
      .qr-label-code :deep(svg),
      .qr-label-code svg {
        width: 100%;
        height: 100%;
        display: block;
      }
      .qr-label-text {
        display: grid;
        gap: 0.4mm;
        min-width: 0;
      }
      .qr-label-id {
        font-family: var(--font-mono);
        font-size: var(--id-size);
        font-weight: 600;
        letter-spacing: 0.04em;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .qr-label-name {
        font-size: var(--line-size);
        font-weight: 500;
        line-height: 1.2;
        overflow: hidden;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
      }
      .qr-label-sub {
        font-size: calc(var(--line-size) * 0.85);
        color: var(--muted-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      @media print {
        .qr-label {
          background: white;
          color: black;
        }
      }
    </style>
  </template>
}

export default QrLabel;
