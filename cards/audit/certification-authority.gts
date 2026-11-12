import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import BuildingIcon from '@cardstack/boxel-icons/building';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';

import { array, hash } from '@ember/helper';
import { Avatar } from '@cardstack/pretui/components/avatar';

import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import {
  EmbCard,
  IsoHead,
  IsoPage,
  Kv,
  Panel,
  StatStrip,
  type StripItem,
} from '../shared/compact-sheet';
import { DotLabel } from '../hr/dot-enum-field';

// What every format shows, in one place so the formats cannot drift.
function facts(m?: Partial<CertificationAuthority> | null) {
  let prefix = m?.numberPrefix?.trim() || 'CERT';
  let last = m?.lastSequence ?? 0;
  let issued = m?.issuedCount ?? 0;
  let pad = (n: number) => String(n).padStart(6, '0');
  let verify = m?.verificationBaseUrl?.replace(/^https?:\/\//, '') || '—';
  return {
    prefix,
    issued,
    last,
    lastText: String(last),
    signatory: m?.signatoryName || '—',
    title: m?.signatoryTitle || '—',
    verifyUrl: m?.verificationBaseUrl || '—',
    issuedText: String(issued),
    meta: [m?.signatoryName, m?.signatoryTitle].filter(Boolean).join(' · '),
    latest: last ? pad(last) : '—',
    next: pad(last + 1),
    verify,
    strip: [
      { label: 'Issued', value: String(issued), hint: 'certificates' },
      { label: 'Prefix', value: prefix, hint: 'numbering' },
      { label: 'Next', value: pad(last + 1), hint: 'sequence' },
    ] as StripItem[],
  };
}

/**
 * The body whose name stands behind a certificate — the
 * **Certification Authority** block. Domain-neutral: an academy, a safety
 * board, a professional institute. It owns three things a certificate needs
 * and a course does not: the signatory, the seal, and the number sequence.
 *
 * `lastSequence` is the one mutable fact: whatever issues a certificate
 * increments it. A realm has no global counter; this is where the counter
 * lives.
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
          <IsoHead @title={{@model.cardTitle}}>
            <:mark><Avatar
                @name={{sealName @model.name}}
                @src={{@model.seal.resolvedUrl}}
                @hue={{AVATAR_HUE}}
                @size={{36}}
                aria-hidden='true'
              /></:mark>
            <:stats><StatStrip @items={{this.f.strip}} /></:stats>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Signatory'>
            <Kv
              @items={{array
                (hash key='Name' value=this.f.signatory)
                (hash key='Title' value=this.f.title)
              }}
            />
          </Panel>
          <Panel @title='Numbering'>
            <Kv
              @items={{array
                (hash key='Last sequence' value=this.f.lastText)
                (hash key='Verify base URL' value=this.f.verifyUrl)
              }}
            />
          </Panel>
        </:main>
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
              (hash key='Signatory' value=this.f.signatory)
              (hash key='Title' value=this.f.title)
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
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          font-size: var(--boxel-font-size-xs);
          font-weight: bold;
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
      <RichFittedCard>
        <:avatar><Avatar
            @name={{sealName @model.name}}
            @src={{@model.seal.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status><DotLabel @label='{{this.f.prefix}} prefix' /></:status>
        <:subtitle><span class='meta'>{{this.f.meta}}</span></:subtitle>
        <:details>

          <Detail @label='Last number'><span
              class='mono'
            >{{this.f.latest}}</span></Detail>
          <Detail @label='Issued'><span
              class='mono'
            >{{this.f.issued}}</span></Detail>
          <Detail @label='Title'>{{this.f.title}}</Detail>
          <Detail @label='Last sequence'><span
              class='mono'
            >{{this.f.last}}</span></Detail>
          <Detail @label='Verify base'>{{this.f.verify}}</Detail>
        </:details>
      </RichFittedCard>
      <style scoped>
        .meta {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-2xs);
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
