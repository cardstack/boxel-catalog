import {
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import UrlField from '@cardstack/base/url';
import BooleanField from '@cardstack/base/boolean';
import { Component } from '@cardstack/base/card-api';

import {
  LICENSES,
  joinNames,
  licenseInfo,
  licenseLabel,
} from '@cardstack/catalog/utils/file-metadata';

// The shared vocabulary for provenance — who made a thing, and who put it
// out. Two fields rather than one, because they answer different questions
// and a consumer usually wants only one of them: a photo credit needs the
// creator, a compliance check needs the licence.
//
// ## Why these are new fields and not a rename of something existing
//
// These facts are already being captured, but per family and under family
// names: a 3D model stores `designer` and `license` on `model3d`, a Word
// document stores its author inside `DocumentInfoField`, an image stores
// EXIF. Nothing reads "who made this?" across families, because there is
// nowhere to read it from.
//
// ## The consolidation trap, stated up front
//
// Adding a shared field on its own makes things WORSE, not better: a
// document would then have authorship in two places that can disagree.
// These are only finished when the per-family facts are projected into them
// — the same way every 3D format projects onto one `Model3dMetadataField`
// instead of each carrying its own mesh counts. Until that projection
// exists, treat these as the destination, not as the source of truth.

// ── Authorship ──────────────────────────────────────────────────────────────

/**
 * Who made this — the creative credit, not the legal owner.
 *
 * `creators` is a list because most real work has more than one hand on it,
 * and a single `author` string forces the first person to stand for all of
 * them. `organization` is separate from the people: a studio is not a
 * co-author, and collapsing them loses the distinction a credit line needs.
 *
 * `tool` records what produced the artifact — a slicer, a camera, a
 * generator. It belongs with authorship rather than publishing because it
 * answers "how was this made", and because a file whose only authorship fact
 * is `generator: Bambu Studio` still tells a reader something real.
 */
export class AuthorshipMetadataField extends FieldDef {
  static displayName = 'Authorship Metadata';

  @field creators = containsMany(StringField, {
    description: 'People credited with making this, in credit order.',
  });
  @field organization = contains(StringField, {
    description: 'The studio, agency or company — not a co-author.',
  });
  @field tool = contains(StringField, {
    description:
      'What produced the artifact: a slicer, camera, generator, application.',
  });
  @field sourceUrl = contains(UrlField, {
    description: 'Where this came from, when it came from somewhere.',
  });
  @field createdOn = contains(DateField);
  @field note = contains(StringField);

  // A single line a credit slot can print without knowing the shape. Falls
  // through creators → organization → tool, so something legible survives
  // even when only one fact was extractable.
  @field credit = contains(StringField, {
    computeVia: function (this: AuthorshipMetadataField) {
      let people = joinNames(this.creators, 3);
      if (people && this.organization) {
        return `${people} · ${this.organization}`;
      }
      return people || this.organization || this.tool || '';
    },
  });

  @field hasCredit = contains(BooleanField, {
    computeVia: function (this: AuthorshipMetadataField) {
      return Boolean(this.credit);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='by'>
        {{! credit falls through creators -> organization -> tool, so this
          line prints something legible whichever facts were extractable. }}
        <span class='credit'>{{if
            @model.hasCredit
            @model.credit
            'No credit recorded'
          }}</span>
        {{#if @model.tool}}
          <span class='meta'>made with {{@model.tool}}</span>
        {{/if}}
      </div>
      <style scoped>
        .by {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .credit {
          font: 600 var(--boxel-font-sm);
        }
        .meta {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// ── Publishing ──────────────────────────────────────────────────────────────

/**
 * Who put this out, and on what terms.
 *
 * Deliberately separate from authorship: the person who made a thing and the
 * entity that licenses it are routinely different, and a reader checking
 * whether they may reuse something does not care who drew it.
 *
 * `license` holds an SPDX identifier where one applies. `LICENSES` is a
 * presentation lookup, never a validation gate — a licence the registry has
 * not heard of is a real licence, not an error, so an unrecognised value
 * stores fine and displays as itself.
 */
export class PublishingMetadataField extends FieldDef {
  static displayName = 'Publishing Metadata';

  @field publisher = contains(StringField);
  @field publishedOn = contains(DateField);
  @field license = contains(StringField, {
    description:
      'SPDX identifier where one applies (CC-BY-4.0, MIT, Apache-2.0, proprietary…). Free text is accepted.',
  });
  @field rightsHolder = contains(StringField, {
    description: 'Who holds copyright, when that is not the publisher.',
  });
  @field edition = contains(StringField, {
    description: 'Version, edition or revision as the publisher names it.',
  });
  @field attributionRequired = contains(BooleanField);

  @field licenseName = contains(StringField, {
    computeVia: function (this: PublishingMetadataField) {
      return licenseLabel(this.license);
    },
  });

  @field licenseUrl = contains(UrlField, {
    computeVia: function (this: PublishingMetadataField) {
      return licenseInfo(this.license)?.url || undefined;
    },
  });

  // The one fact a reader actually scans for. Undefined — not false — when
  // the licence is unrecognised, because "we do not know" and "commercial
  // reuse is not permitted" are different answers and must not render the
  // same.
  @field permitsCommercialUse = contains(BooleanField, {
    computeVia: function (this: PublishingMetadataField) {
      return licenseInfo(this.license)?.permissive;
    },
  });

  @field isLicensed = contains(BooleanField, {
    computeVia: function (this: PublishingMetadataField) {
      return Boolean(this.license);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='pub'>
        <span class='lic'>{{if
            @model.isLicensed
            @model.licenseName
            'No licence recorded'
          }}</span>
        <span class='meta'>
          {{#if @model.publisher}}{{@model.publisher}}{{/if}}
          {{#if @model.rightsHolder}} · © {{@model.rightsHolder}}{{/if}}
        </span>
        {{! undefined, not false, when the licence is unrecognised — "we do
          not know" must never render as "not permitted". }}
        {{#if @model.isLicensed}}
          {{#if @model.permitsCommercialUse}}
            <span class='ok'>commercial use permitted</span>
          {{else}}
            <span class='no'>commercial use not permitted</span>
          {{/if}}
        {{/if}}
      </div>
      <style scoped>
        .pub {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .lic {
          font: 600 var(--boxel-font-sm);
        }
        .meta {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
        .ok,
        .no {
          font: var(--boxel-font-xs);
        }
        .ok {
          color: var(--success);
        }
        .no {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

// Re-exported so a consumer building a licence picker does not have to reach
// into utils for the registry the field is already using.
export { LICENSES };
