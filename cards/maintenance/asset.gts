import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import UrlField from '@cardstack/base/url';
import MarkdownField from '@cardstack/base/markdown';
import { FieldContainer, FittedCard } from '@cardstack/boxel-ui/components';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import WrenchIcon from '@cardstack/boxel-icons/wrench';
import MapPinIcon from '@cardstack/boxel-icons/map-pin';

import RecordIdentifierField from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import RecordOwnerField from '@cardstack/catalog/fields/record-owner/record-owner-field';
import RelationshipSetField from '@cardstack/catalog/fields/relationship-set/relationship-set-field';
import ExternalReferenceField from '@cardstack/catalog/fields/external-reference/external-reference-field';
import Acquisition from '@cardstack/catalog/cards/collectibles/acquisition';
import ConditionGrade from '@cardstack/catalog/fields/condition-grade/condition-grade';
import CriticalityField from './criticality-field';
import WarrantyField from './warranty-field';
import CustodyTransferField from './custody-transfer-field';
import { AssetStatusField, ASSET_STATUS_HUE } from './maintenance-vocabulary';
import { Location } from '@cardstack/catalog/cards/events/location';
import { AssetCategory, categoryIcon } from './asset-category';
import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';
import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';
import { QrLabel } from './components/qr-label';

/**
 * One physical thing worth tracking individually — tagged, located,
 * categorised, held by someone, covered (or not) by a warranty.
 *
 * The register's unit. Identity comes from the record-ops layer
 * (Record Identifier), custody from Record Owner (field name `ownership`
 * so the shared Assign Owner command accepts it) with an append-only
 * `custodyLog`; place is a Location link (locations nest via `parent`);
 * coverage is a Warranty; value is Acquisition + Condition Grade.
 *
 * `status` is written only by commands (Raise / Complete Work Order,
 * Transfer Custody, Dispose Asset). `nextDueLabel`, `lastServicedAt` and the
 * primary meter snapshot are stamped by the plan/meter commands so fitted
 * tiles can show them without resolving links.
 */
export class Asset extends CardDef {
  static displayName = 'Asset';
  static icon = WrenchIcon;

  @field identifier = contains(RecordIdentifierField);
  @field name = contains(StringField);
  @field category = linksTo(() => AssetCategory);
  @field serialNumber = contains(StringField);
  @field manufacturer = contains(StringField);
  @field model = contains(StringField);
  @field status = contains(AssetStatusField);
  @field criticality = contains(CriticalityField);
  @field location = linksTo(() => Location);
  @field parentAsset = linksTo(() => Asset);
  @field ownership = contains(RecordOwnerField, {
    description:
      'Current custodian. Written by Assign Owner / Transfer Custody.',
  });
  @field custodyLog = containsMany(CustodyTransferField);
  @field acquisition = contains(Acquisition);
  @field condition = contains(ConditionGrade);
  @field warranty = contains(WarrantyField);
  @field relationships = contains(RelationshipSetField);
  @field externalRefs = containsMany(ExternalReferenceField);
  @field photoUrls = containsMany(UrlField);
  @field lastServicedAt = contains(DateField);
  @field nextDueLabel = contains(StringField, {
    description: 'Stamped by the plan side — "12 days · Quarterly service".',
  });
  @field primaryMeterValue = contains(NumberField);
  @field primaryMeterUnit = contains(StringField);
  @field notes = contains(MarkdownField);

  // ---- computed (one hop only; templates read these, never lazy links) ----
  @field tag = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.identifier?.value ?? '';
    },
  });
  @field categoryName = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.category?.name;
    },
  });
  @field categoryIconName = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.category?.icon;
    },
  });
  @field categoryId = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.category?.id;
    },
  });
  @field locationName = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.location?.pathLabel ?? this.location?.name;
    },
  });
  @field locationId = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.location?.id;
    },
  });
  @field parentAssetId = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.parentAsset?.id;
    },
  });
  @field parentAssetName = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.parentAsset?.name;
    },
  });
  @field custodianName = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.ownership?.ownerName ?? this.ownership?.teamName;
    },
  });
  @field warrantyActive = contains(StringField, {
    computeVia: function (this: Asset) {
      return this.warranty?.isActive ? 'covered' : '';
    },
  });
  @field statusHue = contains(StringField, {
    computeVia: function (this: Asset) {
      return ASSET_STATUS_HUE[this.status ?? ''] ?? 'slate';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Asset) {
      let name = this.name?.trim();
      let tag = this.identifier?.value;
      if (name && tag) return `${tag} · ${name}`;
      return name || tag || 'Untitled asset';
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='asset-atom'>
        <span class='dot dot-{{@model.statusHue}}'></span>
        <code class='tag'>{{if @model.tag @model.tag 'untagged'}}</code>
        <span class='nm'>{{@model.name}}</span>
      </span>
      <style scoped>
        .asset-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--foreground);
          min-width: 0;
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background: var(--muted-foreground);
          flex: none;
        }
        .dot-green {
          background: color-mix(
            in oklab,
            var(--foreground) 0%,
            oklch(0.62 0.17 150)
          );
        }
        .dot-orange {
          background: oklch(0.7 0.18 50);
        }
        .dot-amber {
          background: oklch(0.78 0.16 80);
        }
        .dot-teal {
          background: oklch(0.65 0.12 190);
        }
        .tag {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-weight: 500;
        }
        .nm {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.categoryIconName);
    }
    <template>
      <div class='asset'>
        <span class='disc'><this.Icon class='disc-icon' /></span>
        <div class='body'>
          <div class='row1'>
            <code class='tag'>{{if @model.tag @model.tag 'untagged'}}</code>
            <span class='name'>{{@model.name}}</span>
          </div>
          <div class='row2'>
            {{#if @model.locationName}}<span class='meta'><MapPinIcon
                  class='mini'
                />{{@model.locationName}}</span>{{/if}}
            {{#if @model.custodianName}}<span class='meta'>·
                {{@model.custodianName}}</span>{{/if}}
            {{#if @model.nextDueLabel}}<span class='meta'>· PM
                {{@model.nextDueLabel}}</span>{{/if}}
          </div>
        </div>
        <@fields.status @format='atom' />
      </div>
      <style scoped>
        .asset {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
          color: var(--foreground);
        }
        .disc {
          flex: none;
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .disc-icon {
          width: 1rem;
          height: 1rem;
        }
        .body {
          flex: 1;
          min-width: 0;
        }
        .row1 {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .tag {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          flex: none;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .row2 {
          display: flex;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          white-space: nowrap;
        }
        .meta {
          display: inline-flex;
          align-items: center;
          gap: 2px;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .mini {
          width: 0.75rem;
          height: 0.75rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.categoryIconName);
    }
    get hue() {
      return (this.args.model?.statusHue ?? 'slate') as Hue;
    }
    <template>
      <FittedCard class='fit' @titleTag='h3'>
        <:placeholder><this.Icon width='24' height='24' /></:placeholder>
        <:eyebrow><span class='mono'>{{if
              @model.tag
              @model.tag
              'untagged'
            }}</span></:eyebrow>
        <:title>{{if @model.name @model.name 'Unnamed asset'}}</:title>
        <:subtitle>{{@model.locationName}}</:subtitle>
        <:meta>{{#if @model.nextDueLabel}}PM
            {{@model.nextDueLabel}}{{else}}No PM scheduled{{/if}}</:meta>
        <:badge><StatePill
            @label={{@model.status}}
            @hue={{this.hue}}
            @dot={{true}}
          /></:badge>
      </FittedCard>
      <style scoped>
        .fit {
          --fc-title-font-size: var(--boxel-font-size-sm);
          --fc-subtitle-font-size: var(--boxel-font-size-xs);
        }
        .mono {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    get Icon() {
      return categoryIcon(this.args.model?.categoryIconName);
    }
    get acquisitionLabel() {
      let a = this.args.model.acquisition;
      if (!a?.price?.amount) return undefined;
      let money = formatMoneyDisplay(a.price.amount, a.price.currency?.code);
      return a.acquiredOnDay ? `${money} · ${a.acquiredOnDay}` : money;
    }
    get meterLabel() {
      let m = this.args.model;
      if (m.primaryMeterValue == null) return undefined;
      return `${m.primaryMeterValue.toLocaleString()} ${m.primaryMeterUnit ?? ''}`.trim();
    }
    <template>
      <article class='iso'>
        <header class='hero'>
          {{#if @model.tag}}
            {{! 'md' — the isolated view has room the register's list rows
                don't; 'sm' truncated the location path in @sub. }}
            <QrLabel
              class='hero-qr'
              @value={{@model.tag}}
              @payload={{@model.id}}
              @name={{@model.name}}
              @sub={{@model.locationName}}
              @size='md'
            />
          {{else}}
            <div class='hero-chip'>
              <span class='dot dot-{{@model.statusHue}}'></span>
              <code class='hero-tag'>untagged</code>
            </div>
          {{/if}}
          <div class='hero-head'>
            <h1 class='hero-title'>{{if
                @model.name
                @model.name
                'Unnamed asset'
              }}</h1>
            <div class='hero-sub'>
              <span class='hero-disc'><this.Icon class='hero-icon' /></span>
              <span>{{if
                  @model.categoryName
                  @model.categoryName
                  'Uncategorised'
                }}</span>
              {{#if @model.manufacturer}}<span>·
                  {{@model.manufacturer}}
                  {{@model.model}}</span>{{/if}}
              {{#if @model.serialNumber}}<span>· S/N
                  <code>{{@model.serialNumber}}</code></span>{{/if}}
            </div>
          </div>
          <div class='hero-state'>
            <@fields.status @format='embedded' />
            <@fields.criticality @format='atom' />
          </div>
        </header>

        <section class='glance'>
          <div class='g'>
            <span class='g-l'>Next PM</span>
            <span class='g-v'>{{if
                @model.nextDueLabel
                @model.nextDueLabel
                'Not scheduled'
              }}</span>
          </div>
          <div class='g'>
            <span class='g-l'>Warranty</span>
            <span class='g-v'><@fields.warranty @format='atom' /></span>
          </div>
          <div class='g'>
            <span class='g-l'>Meter</span>
            <span class='g-v mono'>{{if
                this.meterLabel
                this.meterLabel
                '—'
              }}</span>
          </div>
          <div class='g'>
            <span class='g-l'>Condition</span>
            <span class='g-v'><@fields.condition @format='atom' /></span>
          </div>
          <div class='g'>
            <span class='g-l'>Last serviced</span>
            <span class='g-v'>{{#if
                @model.lastServicedAt
              }}<@fields.lastServicedAt @format='atom' />{{else}}—{{/if}}</span>
          </div>
        </section>

        {{! Alert-only — the dates, provider and ref live in the coverage
            panel below (Warranty's own embedded format); repeating that
            detail here read as the same fact stated twice. }}
        {{#if @model.warranty.isActive}}
          <p class='banner'><strong>Covered</strong>
            — claim, don't pay for parts.</p>
        {{/if}}

        <div class='grid'>
          <section class='panel'>
            <h2>Place &amp; custody</h2>
            <dl class='facts'>
              <div><dt>Location</dt><dd>{{#if @model.location}}<@fields.location
                      @format='atom'
                    />{{else}}—{{/if}}</dd></div>
              {{#if @model.parentAsset}}<div><dt>Part of</dt><dd
                  ><@fields.parentAsset @format='atom' /></dd></div>{{/if}}
              <div><dt>Custodian</dt><dd><@fields.ownership
                    @format='embedded'
                  /></dd></div>
            </dl>
            {{#if @model.custodyLog.length}}
              <h3>Custody log</h3>
              <ul class='list'>
                {{#each @fields.custodyLog as |Entry|}}<li><Entry
                      @format='embedded'
                    /></li>{{/each}}
              </ul>
            {{/if}}
          </section>

          <section class='panel'>
            <h2>Coverage &amp; value</h2>
            <@fields.warranty @format='embedded' />
            <dl class='facts'>
              <div><dt>Acquired</dt><dd>{{if
                    this.acquisitionLabel
                    this.acquisitionLabel
                    '—'
                  }}</dd></div>
              {{#if @model.acquisition.reference}}<div><dt>Reference</dt><dd
                    class='mono'
                  >{{@model.acquisition.reference}}</dd></div>{{/if}}
              <div><dt>Condition</dt><dd><@fields.condition
                    @format='embedded'
                  /></dd></div>
            </dl>
          </section>

          <section class='panel'>
            <h2>Links</h2>
            <@fields.relationships @format='embedded' />
            {{#if @model.externalRefs.length}}
              <h3>External references</h3>
              <ul class='list'>
                {{#each @fields.externalRefs as |Ref|}}<li><Ref
                      @format='embedded'
                    /></li>{{/each}}
              </ul>
            {{/if}}
          </section>

          {{#if @model.notes}}
            <section class='panel panel-wide'>
              <h2>Notes</h2>
              <@fields.notes />
            </section>
          {{/if}}
        </div>
      </article>
      <style scoped>
        .iso {
          container-type: inline-size;
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
          color: var(--foreground);
          background: var(--card);
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp);
          align-items: start;
        }
        .hero-chip {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background: var(--background);
          align-self: center;
        }
        .dot {
          width: 0.625rem;
          height: 0.625rem;
          border-radius: 50%;
          background: var(--muted-foreground);
        }
        .dot-green {
          background: oklch(0.62 0.17 150);
        }
        .dot-orange {
          background: oklch(0.7 0.18 50);
        }
        .dot-amber {
          background: oklch(0.78 0.16 80);
        }
        .dot-teal {
          background: oklch(0.65 0.12 190);
        }
        .hero-tag {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: var(--boxel-font-size-lg);
          font-weight: 600;
          letter-spacing: 0.02em;
        }
        .hero-head {
          min-width: 0;
        }
        .hero-title {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          text-wrap: balance;
        }
        .hero-sub {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .hero-sub code,
        .mono {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
        }
        .hero-disc {
          display: inline-grid;
          place-items: center;
          width: 1.4rem;
          height: 1.4rem;
          border-radius: 50%;
          background: var(--muted);
        }
        .hero-icon {
          width: 0.85rem;
          height: 0.85rem;
        }
        .hero-state {
          display: grid;
          gap: var(--boxel-sp-4xs);
          justify-items: end;
        }
        .glance {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(8.75rem, 1fr));
          gap: 1px;
          background: var(--border);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          overflow: hidden;
        }
        .g {
          background: var(--card);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: grid;
          gap: 2px;
        }
        .g-l {
          font-size: var(--boxel-font-size-xs);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .g-v {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
          font-variant-numeric: tabular-nums;
        }
        .banner {
          margin: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--primary);
          border-radius: var(--boxel-border-radius);
          background: color-mix(in oklch, var(--primary) 10%, var(--card));
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-lg);
          background: var(--card);
          box-shadow: var(--shadow-2xs);
          padding: var(--boxel-sp);
          display: grid;
          gap: var(--boxel-sp-sm);
          align-content: start;
        }
        .panel-wide {
          grid-column: 1 / -1;
        }
        .panel h2 {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .panel h3 {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
        }
        .facts {
          margin: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .facts dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .facts dd {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
        .list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        @container (width < 40rem) {
          .hero {
            grid-template-columns: 1fr;
          }
          .hero-state {
            justify-items: start;
          }
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'class', label: 'Classification' },
      { id: 'place', label: 'Place & custody' },
      { id: 'value', label: 'Coverage & value' },
      { id: 'links', label: 'Links & notes' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Asset sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{2}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer
            @label='Asset tag'
            @vertical={{true}}
          ><@fields.identifier /></FieldContainer>
          <FieldContainer
            @label='Serial number'
            @vertical={{true}}
          ><@fields.serialNumber /></FieldContainer>
          <FieldContainer
            @label='Manufacturer'
            @vertical={{true}}
          ><@fields.manufacturer /></FieldContainer>
          <FieldContainer @label='Model' @vertical={{true}}><@fields.model
            /></FieldContainer>
        </e.Section>
        <e.Section @id='class' @title='Classification' @cols={{2}}>
          <FieldContainer @label='Category' @vertical={{true}}><@fields.category
            /></FieldContainer>
          <FieldContainer @label='Status' @vertical={{true}}><@fields.status
            /></FieldContainer>
          <FieldContainer
            @label='Criticality'
            @vertical={{true}}
          ><@fields.criticality /></FieldContainer>
          <FieldContainer
            @label='Part of (parent asset)'
            @vertical={{true}}
          ><@fields.parentAsset /></FieldContainer>
        </e.Section>
        <e.Section
          @id='place'
          @title='Place & custody'
          @hint='custody changes go through Transfer Custody'
          @cols={{2}}
        >
          <FieldContainer @label='Location' @vertical={{true}}><@fields.location
            /></FieldContainer>
          <FieldContainer
            @label='Custodian'
            @vertical={{true}}
          ><@fields.ownership /></FieldContainer>
        </e.Section>
        <e.Section @id='value' @title='Coverage & value' @cols={{2}}>
          <FieldContainer @label='Warranty' @vertical={{true}}><@fields.warranty
            /></FieldContainer>
          <FieldContainer
            @label='Acquisition'
            @vertical={{true}}
          ><@fields.acquisition /></FieldContainer>
          <FieldContainer
            @label='Condition'
            @vertical={{true}}
          ><@fields.condition /></FieldContainer>
          <FieldContainer
            @label='Last serviced'
            @vertical={{true}}
          ><@fields.lastServicedAt /></FieldContainer>
        </e.Section>
        <e.Section @id='links' @title='Links & notes' @cols={{1}}>
          <FieldContainer
            @label='Relationships'
            @vertical={{true}}
          ><@fields.relationships /></FieldContainer>
          <FieldContainer
            @label='External references'
            @vertical={{true}}
          ><@fields.externalRefs /></FieldContainer>
          <FieldContainer
            @label='Photo URLs'
            @vertical={{true}}
          ><@fields.photoUrls /></FieldContainer>
          <FieldContainer @label='Notes' @vertical={{true}}><@fields.notes
            /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };
}

export default Asset;
