import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import UrlField from '@cardstack/base/url';
import enumField from '@cardstack/base/enum';
import FingerprintIcon from '@cardstack/boxel-icons/fingerprint';

import { Document } from './document';
import { AttributionField } from './attribution-field';
import { TrustMetadataField } from '@cardstack/catalog/fields/trust-metadata/trust-metadata-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import {
  integrityOf,
  shortHash,
  INTEGRITY_LABELS,
  type Integrity,
} from './utils/evidence-hash';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const PROOF_KINDS = [
  'document',
  'screenshot',
  'log-export',
  'signed-form',
  'photo',
  'link',
  'statement',
] as const;

export const PROOF_KIND_LABELS: Record<string, string> = {
  document: 'Document',
  screenshot: 'Screenshot',
  'log-export': 'Log export',
  'signed-form': 'Signed form',
  photo: 'Photo',
  link: 'Link',
  statement: 'Statement',
};

const INTEGRITY_HUE: Record<Integrity, Hue> = {
  intact: 'green',
  changed: 'red',
  unverified: 'slate',
};

export const ProofKindField = enumField(StringField, {
  displayName: 'Proof Kind',
  options: PROOF_KINDS.map((value) => ({
    value,
    label: PROOF_KIND_LABELS[value],
  })),
});

/**
 * One piece of evidence, with its provenance and its tamper check.
 *
 * The artefact arrives one of three ways and the `kind` says which: a linked
 * Document for anything with bytes, a `url` for something that lives
 * elsewhere, or a written `statement` when the evidence is somebody's word.
 * All three are legitimate; what is not legitimate is a control marked
 * satisfied with none of them, which is why Evaluation Status has `unproven`.
 *
 * `sha256` is the hash recorded when this proof was attached. Comparing it to
 * the linked Document's current `contentHash` is the whole point: a hash
 * stored next to the bytes it describes proves nothing, because whoever
 * replaced the bytes could rewrite it. Two hashes recorded at two moments by
 * two writers is what makes replacement visible.
 */
export class ProofField extends FieldDef {
  static displayName = 'Proof';
  static icon = FingerprintIcon;

  @field kind = contains(ProofKindField);
  @field document = linksTo(() => Document);
  @field url = contains(UrlField);
  @field statement = contains(TextAreaField);
  /** SHA-256 seen at attach time, lower-case hex. */
  @field sha256 = contains(StringField);
  @field attribution = contains(AttributionField);
  @field trust = contains(TrustMetadataField);

  @field label = contains(StringField, {
    computeVia: function (this: ProofField) {
      return PROOF_KIND_LABELS[this.kind ?? ''] ?? '';
    },
  });

  /** intact / changed / unverified — never a bare boolean. */
  @field integrity = contains(StringField, {
    computeVia: function (this: ProofField) {
      return integrityOf(this.sha256, this.document?.contentHash);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get integrity(): Integrity {
      return (this.args.model?.integrity as Integrity) ?? 'unverified';
    }
    get integrityLabel() {
      return INTEGRITY_LABELS[this.integrity] ?? 'unverified';
    }
    get integrityHue() {
      return INTEGRITY_HUE[this.integrity] ?? 'slate';
    }
    get hashLabel() {
      return shortHash(this.args.model?.sha256);
    }
    <template>
      <div class='proof'>
        <div class='head'>
          <span class='kind'>{{@model.label}}</span>
          {{#if this.hashLabel}}
            <span
              class='hash mono'
              title={{@model.sha256}}
            >{{this.hashLabel}}</span>
          {{/if}}
          <StatePill
            @label={{this.integrityLabel}}
            @hue={{this.integrityHue}}
            @dot={{true}}
          />
        </div>

        {{#if @model.document}}
          <div class='artefact'><@fields.document @format='embedded' /></div>
        {{else if @model.url}}
          <a
            class='artefact-link'
            href={{@model.url}}
            target='_blank'
            rel='noopener'
          >{{@model.url}}</a>
        {{else if @model.statement}}
          <p class='statement'>{{@model.statement}}</p>
        {{else}}
          <p class='statement empty'>No artefact attached.</p>
        {{/if}}

        {{#if @model.trust}}
          <div class='line'><@fields.trust /></div>
        {{/if}}
        {{#if @model.attribution}}
          <div class='line'><@fields.attribution /></div>
        {{/if}}
      </div>
      <style scoped>
        .proof {
          display: grid;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) 0;
          min-width: 0;
        }
        .head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .kind {
          font-size: 0.8125rem;
          font-weight: 600;
        }
        .hash {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .artefact {
          min-width: 0;
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--boxel-border-radius-sm);
        }
        .artefact-link {
          font-size: 0.8125rem;
          color: var(--foreground, var(--boxel-dark));
          text-decoration: underline;
          text-underline-offset: 2px;
          overflow-wrap: anywhere;
        }
        .statement {
          margin: 0;
          font-size: 0.8125rem;
          line-height: 1.5;
        }
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .line {
          min-width: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get integrity(): Integrity {
      return (this.args.model?.integrity as Integrity) ?? 'unverified';
    }
    get integrityHue() {
      return INTEGRITY_HUE[this.integrity] ?? 'slate';
    }
    <template>
      <span class='atom'>
        <span class='kind'>{{@model.label}}</span>
        <StatePill @label={{@model.integrity}} @hue={{this.integrityHue}} />
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
        }
        .kind {
          font-size: 0.75rem;
          font-weight: 600;
        }
      </style>
    </template>
  };
}

export default ProofField;
