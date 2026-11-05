import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import BuildingIcon from '@cardstack/boxel-icons/building';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';

import { array, hash } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';

import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import {
  EmbCard,
  FitCard,
  FitRow,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  StatStrip,
  type StripItem,
} from '../hr/compact-sheet';
import { DotLabel } from '../hr/dot-enum-field';

// What every format shows, in one place so the formats cannot drift.
function facts(m?: Partial<CertificationAuthority> | null) {
  let prefix = m?.numberPrefix?.trim() || 'CERT';
  let last = m?.lastSequence ?? 0;
  let issued = m?.issuedCount ?? 0;
  // shortcut: the authority stores no issue year, so the latest number uses this year; read it from the latest Certificate once one links back.
  let year = new Date().getFullYear();
  let pad = (n: number) => String(n).padStart(6, '0');
  let verify = m?.verificationBaseUrl?.replace(/^https?:\/\//, '') || '—';
  return {
    prefix,
    issued,
    last,
    lastText: String(last),
    issuedText: String(issued),
    meta: [m?.signatoryName, m?.signatoryTitle].filter(Boolean).join(' · '),
    latest: last ? `${prefix}-${year}-${pad(last)}` : '—',
    next: pad(last + 1),
    verify,
    strip: [
      { label: 'Issued', value: String(issued), hint: 'certificates' },
      { label: 'Prefix', value: prefix, hint: 'numbering' },
      { label: 'Next', value: pad(last + 1), hint: 'sequence' },
    ] as StripItem[],
    details: [
      { key: 'Signatory', value: m?.signatoryName || '—' },
      { key: 'Title', value: m?.signatoryTitle || '—' },
      { key: 'Prefix', value: prefix },
      { key: 'Last sequence', value: String(last) },
      { key: 'Issued', value: String(issued) },
      { key: 'Verify base', value: verify },
    ],
  };
}

/**
 * The body whose name stands behind a certificate — the
 * **Certification Authority** block. Domain-neutral: an academy, a safety
 * board, a professional institute. It owns three things a certificate needs
 * and a course does not: the signatory, the seal, and the number sequence.
 *
 * `lastSequence` is the one mutable fact: whatever issues a certificate
 * increments it. A realm has no global
 * counter; this is where the counter lives.
 */
export class CertificationAuthority extends CardDef {
  static displayName = 'Certification Authority';
  static icon = BuildingIcon;

  @field name = contains(StringField);
  @field signatoryName = contains(StringField);
  @field signatoryTitle = contains(StringField);
  @field seal = contains(ImageSourceField);
  @field verificationBaseUrl = contains(UrlField, {
    description:
      'Certificate numbers are appended to this to form a verify link.',
  });
  @field numberPrefix = contains(StringField, {
    description: 'Letters printed before the year in every number, e.g. ACAD.',
  });
  @field lastSequence = contains(NumberField, {
    description: 'Maintained by Issue Certificate. Do not edit by hand.',
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: CertificationAuthority) {
      return this.name?.trim() || 'Unnamed authority';
    },
  });
  @field issuedCount = contains(NumberField, {
    computeVia: function (this: CertificationAuthority) {
      return this.lastSequence ?? 0;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get f() {
      return facts(this.args.model);
    }
    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.cardTitle}} @meta={{this.f.meta}}>
            <:mark><Avatar
                @name={{sealName @model.name}}
                @src={{@model.seal.resolvedUrl}}
                @hue={{AVATAR_HUE}}
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:aside><DotLabel @label='{{this.f.prefix}} prefix' /><DotLabel
                @label='{{this.f.issued}} issued'
                @hue='blue'
              /></:aside>
            <:stats><StatStrip @items={{this.f.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Signatory'>
            <Kv
              @items={{array
                (hash key='Name' value=(or @model.signatoryName '—'))
                (hash key='Title' value=(or @model.signatoryTitle '—'))
                (hash key='Seal' value='')
              }}
            >
              <:value as |item|>{{#if (eq item.key 'Seal')}}<Avatar
                    @name={{sealName @model.name}}
                    @src={{@model.seal.resolvedUrl}}
                    @hue={{AVATAR_HUE}}
                    @size={{24}}
                    aria-label='Seal'
                  />{{else}}{{item.value}}{{/if}}</:value>
            </Kv>
          </Panel>
          <Panel @title='Numbering'>
            <Kv
              @items={{array
                (hash key='Prefix' value=this.f.prefix)
                (hash key='Last sequence' value=this.f.lastText)
                (hash
                  key='Verify base URL'
                  value=(or @model.verificationBaseUrl '—')
                )
              }}
            />
          </Panel>
        </:main>
        <:aside>
          <Panel @title='Linked'>
            <Kv
              @items={{array
                (hash key='Latest' value=this.f.latest)
                (hash key='Signatory' value=(or @model.signatoryName '—'))
              }}
            />
          </Panel>
          <Panel @title='Details'><Kv @items={{this.f.details}} /></Panel>
        </:aside>
      </IsoPage>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get f() {
      return facts(this.args.model);
    }
    <template>
      <EmbCard @title={{@model.cardTitle}} @meta={{this.f.meta}}>
        <:mark><Avatar
            @name={{sealName @model.name}}
            @src={{@model.seal.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{24}}
            aria-hidden='true'
          /></:mark>
        <:aside><DotLabel @label='{{this.f.prefix}} prefix' /><DotLabel
            @label='{{this.f.issued}} issued'
            @hue='blue'
          /></:aside>
        <:default>
          <Kv
            @items={{array
              (hash key='Last number' value=this.f.latest)
              (hash key='Signatory' value=(or @model.signatoryName '—'))
              (hash key='Title' value=(or @model.signatoryTitle '—'))
              (hash key='Prefix' value=this.f.prefix)
              (hash key='Issued' value=this.f.issuedText)
              (hash key='Verify base' value=this.f.verify)
            }}
          />
        </:default>
      </EmbCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><Avatar
          @name={{sealName @model.name}}
          @src={{@model.seal.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{16}}
          aria-hidden='true'
        /><span class='n'>{{@model.cardTitle}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          font-size: 0.75rem;
          font-weight: 600;
        }
        .n {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get f() {
      return facts(this.args.model);
    }
    <template>
      <FitCard @title={{@model.cardTitle}}>
        <:mark><Avatar
            @name={{sealName @model.name}}
            @src={{@model.seal.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{20}}
            aria-hidden='true'
          /></:mark>
        <:status><DotLabel @label='{{this.f.prefix}} prefix' /></:status>
        <:default>
          <FitRow @left={{true}}><span class='meta'>{{this.f.meta}}</span></FitRow>
          <FitRow @label='Last number'><span
              class='mono'
            >{{this.f.latest}}</span></FitRow>
          <FitRow @label='Issued'><span
              class='mono'
            >{{this.f.issued}}</span></FitRow>
          <FitRow @label='Title'>{{or @model.signatoryTitle '—'}}</FitRow>
          <FitRow @label='Last sequence'><span
              class='mono'
            >{{this.f.last}}</span></FitRow>
          <FitRow @label='Verify base'>{{this.f.verify}}</FitRow>
        </:default>
      </FitCard>
      <style scoped>
        .meta {
          color: var(--muted-foreground);
          font-size: 0.6875rem;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

// The seal's initials come from the authority's own name; an unnamed one
// shows `?` rather than the "Unnamed authority" title's initials.
function sealName(name?: string | null): string {
  return name?.trim() || '?';
}

export default CertificationAuthority;
