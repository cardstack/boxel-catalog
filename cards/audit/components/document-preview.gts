import GlimmerComponent from '@glimmer/component';
import type { BoxComponent, Format } from '@cardstack/base/card-api';
import type { FileDef } from '@cardstack/base/file-api';
import FileTextIcon from '@cardstack/boxel-icons/file-text';

import FileDownloadLink from '@cardstack/catalog/cards/hr/components/file-download-link';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import {
  integrityOf,
  shortHash,
  INTEGRITY_LABELS,
  type Integrity,
} from '../utils/evidence-hash';
import type { Hue } from '@cardstack/catalog/components/state-pill';

// Structural, not the Document class: importing the card here would close a
// module cycle (the card's isolated view renders this component). Same
// reasoning as base's `FileModelLike`.
interface DocumentLike {
  title?: string | null;
  kind?: string | null;
  version?: string | null;
  contentHash?: string | null;
  hashedAt?: Date | null;
  file?: FileDef | null;
  supersedes?: DocumentLike | null;
}

const INTEGRITY_HUE: Record<Integrity, Hue> = {
  intact: 'green',
  changed: 'red',
  unverified: 'slate',
};

interface Signature {
  Args: {
    document?: DocumentLike | null;
    /**
     * The host's `@fields.file` component. Rendering the file through its own
     * format is what routes to the right previewer — the file def's shell
     * already picks the family renderer, so this component never sniffs a
     * content type.
     */
    fileField?: BoxComponent | null;
    /** Passed through to the file's own format. */
    format?: Format;
    /** Hide the provenance strip when a parent already shows it. */
    bare?: boolean;
  };
  Element: HTMLElement;
}

/**
 * A document with its evidence provenance around it: the file rendered through
 * the platform's own preview routing, the recorded hash, and the version chain
 * it supersedes.
 *
 * The integrity verdict shown here is deliberately weak — a Document knows
 * only its own recorded hash, so it reports "hashed" or "not hashed". The
 * tamper comparison needs two hashes and belongs to Proof Field, which holds
 * the one recorded when the evidence was attached.
 */
export class DocumentPreview extends GlimmerComponent<Signature> {
  get doc() {
    return this.args.document ?? null;
  }

  get format() {
    return this.args.format ?? 'embedded';
  }

  get hasFile() {
    return Boolean(this.doc?.file);
  }

  // Recorded against nothing to compare with: "unverified" until a proof
  // supplies the hash it saw at attach time.
  get integrity(): Integrity {
    return integrityOf(this.doc?.contentHash, this.doc?.contentHash);
  }

  get integrityLabel() {
    return INTEGRITY_LABELS[this.integrity];
  }

  get integrityHue() {
    return INTEGRITY_HUE[this.integrity];
  }

  get hashLabel() {
    return shortHash(this.doc?.contentHash);
  }

  get supersededTitle() {
    return this.doc?.supersedes?.title ?? null;
  }

  <template>
    <div class='doc-preview' ...attributes>
      <div class='stage'>
        {{#if @fileField}}
          <@fileField @format={{this.format}} />
        {{else if this.hasFile}}
          <FileDownloadLink @file={{this.doc.file}} />
        {{else}}
          <div class='no-file'>
            <FileTextIcon class='nf-icon' aria-hidden='true' />
            <span>No file attached — the record exists, the artefact does not.</span>
          </div>
        {{/if}}
      </div>

      {{#unless @bare}}
        <div class='provenance'>
          {{#if this.hashLabel}}
            <span class='hash mono' title={{this.doc.contentHash}}>sha256
              {{this.hashLabel}}</span>
          {{/if}}
          <StatePill
            @label={{this.integrityLabel}}
            @hue={{this.integrityHue}}
            @dot={{true}}
          />
          {{#if this.doc.version}}
            <span class='meta'>v{{this.doc.version}}</span>
          {{/if}}
          {{#if this.supersededTitle}}
            <span class='meta'>supersedes {{this.supersededTitle}}</span>
          {{/if}}
        </div>
      {{/unless}}
    </div>

    <style scoped>
      .doc-preview {
        display: grid;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .stage {
        min-width: 0;
        overflow: hidden;
        border-radius: var(--boxel-border-radius-sm);
      }
      .no-file {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border: 1px dashed var(--border, var(--boxel-200));
        border-radius: var(--boxel-border-radius-sm);
        font-size: 0.8125rem;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .nf-icon {
        width: 16px;
        height: 16px;
        flex: none;
      }
      .provenance {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        font-size: 0.75rem;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .hash {
        font-weight: 600;
      }
      .mono {
        font-family: var(--font-mono, ui-monospace, monospace);
      }
    </style>
  </template>
}

export default DocumentPreview;
