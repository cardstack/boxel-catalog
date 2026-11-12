import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import UrlField from '@cardstack/base/url';
import MarkdownField from '@cardstack/base/markdown';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import WrenchIcon from '@cardstack/boxel-icons/wrench';

import RecordIdentifierField from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import RecordOwnerField from '@cardstack/catalog/fields/record-owner/record-owner-field';
import RelationshipSetField from '@cardstack/catalog/fields/relationship-set/relationship-set-field';
import ExternalReferenceField from '@cardstack/catalog/fields/external-reference/external-reference-field';
import Acquisition from '../sneakers/acquisition';
import ConditionGrade from '@cardstack/catalog/fields/condition-grade/condition-grade';
import CriticalityField from './criticality-field';
import WarrantyField from './warranty-field';
import CustodyTransferField from './custody-transfer-field';
import { AssetStatusField, ASSET_STATUS_HUE } from './maintenance-vocabulary';
import { Location } from '../events/location';
import { AssetCategory } from './asset-category';
// Cyclic (both link to Asset); read only in constructors and actions.
import { MaintenancePlan } from './maintenance-plan';
import { Meter } from './meter';
import { WorkOrder } from './work-order';
import { FitTile } from '../shared/fit-tile';
import {
  Chip,
  Brief,
  Dot,
  Fact,
  Head,
  Mark,
  Row,
  Section,
  Sheet,
  dash,
  enumText,
  join,
  money,
  monthYear,
  num,
  shortDate,
  hueTone,
  type KvItem,
} from './card-ui';

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
      <Chip
        @bare={{true}}
        @mark='As'
        @name={{if @model.name @model.name @model.tag}}
        @tone={{hueTone @model.statusHue}}
        @meta={{enumText @model.status}}
      />
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get next() {
      return nextDue(this.args.model.nextDueLabel);
    }
    <template>
      <Brief
        @mark='As'
        @title={{if @model.name @model.name 'Untitled asset'}}
        @meta={{metaLine @model}}
      >
        <:status><StatusDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Next:'
            @strong={{this.next.plan}}
            @rest={{this.next.due}}
          /></:fact>
        <:default>
          <KeyValue
            @items={{summaryRows @model}}
            @labelStyle='eyebrow'
            @divided={{true}}
          />
          <LinkedRows @model={{@model}} @fields={{@fields}} />
        </:default>
      </Brief>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get next() {
      return nextDue(this.args.model.nextDueLabel);
    }
    <template>
      <FitTile>
        <:avatar><Mark @text='As' @size='lg' /></:avatar>
        <:title>{{if @model.name @model.name 'Untitled asset'}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><StatusDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Next:'
            @strong={{this.next.plan}}
            @rest={{this.next.due}}
          /></:fact>
        <:relations>
          {{#if @model.category}}<@fields.category @format='atom' />{{/if}}
          {{#if @model.location}}<@fields.location @format='atom' />{{/if}}
        </:relations>
      </FitTile>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    private planQuery: ReturnType<getCards> | undefined;
    private meterQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      let byAsset = (card: unknown) => () => {
        let ref = identifyCard(card as typeof MaintenancePlan);
        let id = this.args.model?.id;
        return ref && id
          ? { filter: { on: ref, every: [{ eq: { 'asset.id': id } }] } }
          : undefined;
      };
      this.planQuery = this.args.context?.getCards(
        this,
        byAsset(MaintenancePlan),
        () => this.realms,
        { isLive: true },
      );
      this.meterQuery = this.args.context?.getCards(
        this,
        byAsset(Meter),
        () => this.realms,
        { isLive: true },
      );
    }

    private get realms(): string[] | undefined {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    }

    get plans(): MaintenancePlan[] {
      return (this.planQuery?.instances ?? []).filter(
        Boolean,
      ) as MaintenancePlan[];
    }

    get meter(): Meter | undefined {
      let meters = (this.meterQuery?.instances ?? []).filter(
        Boolean,
      ) as Meter[];
      let unit = this.args.model.primaryMeterUnit;
      return meters.find((m) => m.unit === unit) ?? meters[0];
    }

    get next() {
      return nextDue(this.args.model.nextDueLabel);
    }

    get identity(): KvItem[] {
      let m = this.args.model;
      return [
        { key: 'Asset id', value: dash(m.tag) },
        { key: 'Manufacturer', value: dash(m.manufacturer) },
        { key: 'Model', value: dash(m.model) },
        { key: 'Serial', value: dash(m.serialNumber) },
      ];
    }

    get acquisition(): KvItem[] {
      let a = this.args.model.acquisition;
      let w = this.args.model.warranty;
      return [
        {
          key: 'Acquired',
          value: a?.acquiredOn
            ? join(shortDate(a.acquiredOn), a.source)
            : dash(a?.source),
        },
        {
          key: 'Price',
          value: money(a?.price?.amount, a?.price?.currency?.code, 0),
        },
        { key: 'Purchase order', value: dash(a?.reference) },
        {
          key: 'Warranty',
          value: w?.endsOn
            ? `${shortDate(w.startsOn)} – ${shortDate(w.endsOn)}`
            : '—',
        },
        { key: 'Terms', value: dash(w?.terms?.split('.')[0]) },
        { key: 'Claim ref', value: dash(w?.claimReference) },
      ];
    }

    get details(): KvItem[] {
      let m = this.args.model;
      let a = m.acquisition;
      return [
        ...summaryRows(m).slice(0, 5),
        { key: 'Acquired', value: shortDate(a?.acquiredOn) },
        {
          key: 'Price',
          value: money(a?.price?.amount, a?.price?.currency?.code, 0),
        },
        { key: 'ERP ref', value: dash(m.externalRefs?.[0]?.externalId) },
      ];
    }

    raiseWorkOrder = async () => {
      let create = this.args.createCard;
      let ref = identifyCard(WorkOrder);
      let realmHref = this.realms?.[0];
      let id = this.args.model.id;
      if (!create || !ref || !realmHref || !id) return;
      await create(ref, undefined, {
        realmURL: new URL(realmHref),
        doc: {
          data: {
            meta: { adoptsFrom: ref },
            relationships: { subjectAsset: { links: { self: id } } },
          },
        },
      });
    };

    logReading = () => {
      if (this.meter) this.args.viewCard?.(this.meter, 'isolated');
    };

    <template>
      <Sheet>
        <:head>
          <Head
            @mark='As'
            @title={{if @model.name @model.name 'Untitled asset'}}
            @meta={{metaLine @model}}
          >
            <:status><StatusDots @model={{@model}} /></:status>
            <:actions>
              <Button
                @size='s'
                @disabled={{if @createCard false true}}
                {{on 'click' this.raiseWorkOrder}}
              >Raise work order</Button>
              <Button
                @tone='neutral'
                @appearance='outlined'
                @size='s'
                @disabled={{if this.meter false true}}
                {{on 'click' this.logReading}}
              >Log reading</Button>
            </:actions>
          </Head>
        </:head>
        <:stats>
          <Stat
            @label='Running hours'
            @value={{num @model.primaryMeterValue @model.primaryMeterUnit}}
            @hint={{if
              this.meter.lastReadAt
              (concat 'read ' (shortDate this.meter.lastReadAt))
              'no reading yet'
            }}
            @roll={{false}}
          />
          <Stat
            @label='Next due'
            @value={{dash this.next.due}}
            @hint={{dash this.next.plan}}
            @roll={{false}}
          />
          <Stat
            @label='Condition'
            @value={{dash @model.condition.code}}
            @hint={{if
              @model.condition.valueRetention
              (concat @model.condition.valueRetention '% value retained')
              '—'
            }}
            @roll={{false}}
          />
          <Stat
            @label='Warranty'
            @value={{monthYear @model.warranty.endsOn}}
            @hint={{join @model.warranty.providerName @model.warranty.kind}}
            @roll={{false}}
          />
        </:stats>
        <:main>
          {{#if @model.notes}}
            <Section @title='Notes'><p>{{@model.notes}}</p></Section>
          {{/if}}
          <Section @title='Identity'>
            <KeyValue
              @items={{this.identity}}
              @labelStyle='eyebrow'
              @divided={{true}}
            />
          </Section>
          <Section @title='Acquisition & warranty'>
            <KeyValue
              @items={{this.acquisition}}
              @labelStyle='eyebrow'
              @divided={{true}}
            />
          </Section>
          <Section @title='Custody'>
            {{#each @model.custodyLog as |c|}}
              <Row
                @title={{custodyTitle c}}
                @meta={{join (shortDate c.at) c.toTeamName c.note}}
                @state={{if c.conditionCode (concat 'grade ' c.conditionCode)}}
              />
            {{else}}
              <Row @title='No custody events' />
            {{/each}}
          </Section>
          <Section @title='Plans'>
            {{#each this.plans as |p|}}
              <Row
                @title={{p.name}}
                @meta={{p.dueLabel}}
                @tone={{if p.active 'ok'}}
                @state={{if p.active 'active' 'paused'}}
              />
            {{else}}
              <Row @title='No maintenance plans' />
            {{/each}}
          </Section>
        </:main>
        <:side>
          <Section @title='Linked'>
            <LinkedRows @model={{@model}} @fields={{@fields}} />
          </Section>
          <Section @title='Details'>
            <KeyValue
              @items={{this.details}}
              @labelStyle='eyebrow'
              @divided={{true}}
            />
          </Section>
        </:side>
      </Sheet>
    </template>
  };
}

function concat(...parts: unknown[]) {
  return parts.join('');
}

function metaLine(m: Partial<Asset>) {
  return join(m.tag, [m.manufacturer, m.model].filter(Boolean).join(' '));
}

/** "12 days · Quarterly service" → due "in 12 days", plan "Quarterly service" */
function nextDue(label?: string | null) {
  let [due, plan] = (label ?? '').split(' · ');
  return {
    due: due ? (/^\d/.test(due) ? `in ${due}` : due) : undefined,
    plan: plan || due || 'Not scheduled',
  };
}

function summaryRows(m: Partial<Asset>): KvItem[] {
  let c = m.condition;
  return [
    {
      key: 'Running hours',
      value: num(m.primaryMeterValue, m.primaryMeterUnit),
    },
    { key: 'Last serviced', value: shortDate(m.lastServicedAt) },
    { key: 'Serial', value: dash(m.serialNumber) },
    {
      key: 'Condition',
      value: c?.code
        ? join(
            c.code,
            c.valueRetention != null ? `${c.valueRetention}% value` : null,
          )
        : '—',
    },
    { key: 'Warranty to', value: shortDate(m.warranty?.endsOn) },
    { key: 'Acquired', value: shortDate(m.acquisition?.acquiredOn) },
  ];
}

function custodyTitle(c: CustodyTransferField) {
  return c.kind === 'transfer' && c.toName
    ? `Assigned to ${c.toName}`
    : c.label;
}

const LINKED: KvItem[] = [
  { key: 'Category', value: '' },
  { key: 'Location', value: '' },
  { key: 'Custodian', value: '' },
  { key: 'Related', value: '' },
];

const StatusDots: TemplateOnlyComponent<{
  Args: { model: Partial<Asset> };
}> = <template>
  <Dot @tone={{hueTone @model.statusHue}} @label={{enumText @model.status}} />
  {{#if @model.criticality.level}}
    <Dot
      @tone={{criticalityTone @model.criticality.level}}
      @label={{@model.criticality.level}}
    />
  {{/if}}
</template>;

function criticalityTone(level?: string | null) {
  return level === 'critical' ? 'bad' : level === 'high' ? 'warn' : undefined;
}

function relatedName(title?: string | null) {
  let parts = (title ?? '').split(' · ');
  return parts[parts.length - 1] || '—';
}

const LinkedRows: TemplateOnlyComponent<{
  Args: { model: Partial<Asset>; fields: any };
}> = <template>
  <KeyValue @items={{LINKED}} @labelStyle='eyebrow' @divided={{true}}>
    <:value as |item|>
      {{#if (eq item.key 'Category')}}
        {{#if @model.category}}<@fields.category
            @format='atom'
          />{{else}}—{{/if}}
      {{else if (eq item.key 'Location')}}
        {{#if @model.location}}<@fields.location
            @format='atom'
          />{{else}}—{{/if}}
      {{else if (eq item.key 'Custodian')}}
        {{#if @model.custodianName}}
          <span class='person'><Avatar
              @name={{@model.custodianName}}
              @size={{16}}
              @shape='rounded'
            />{{@model.custodianName}}</span>
        {{else}}—{{/if}}
      {{else}}
        {{#each @model.relationships.relations as |r|}}
          <Chip @bare={{true}} @mark='As' @name={{relatedName r.targetTitle}} />
        {{else}}—{{/each}}
      {{/if}}
    </:value>
  </KeyValue>
  <style scoped>
    .person {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      font-weight: 600;
    }
  </style>
</template>;

export default Asset;
