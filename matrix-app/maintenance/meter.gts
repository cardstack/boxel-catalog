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
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import QuantityField from '@cardstack/catalog/fields/quantity/quantity';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import GaugeIcon from '@cardstack/boxel-icons/gauge';

import MeterReadingField from './meter-reading-field';
import { MeterKindField } from './maintenance-vocabulary';
import { Asset } from './asset';
// Cyclic (a plan links to Asset); read only in the constructor.
import { MaintenancePlan } from './maintenance-plan';
import RecordMeterReadingCommand from './commands/record-meter-reading-command';
import { FitTile } from '../shared/fit-tile';
import {
  AtomLine,
  Brief,
  Dot,
  Fact,
  Head,
  Mark,
  Row,
  Section,
  Sheet,
  dash,
  join,
  num,
  shortDate,
  type KvItem,
} from './utils/parts';

function sorted(readings: MeterReadingField[] | null | undefined) {
  return (readings ?? [])
    .filter((r) => r && r.value != null)
    .slice()
    .sort((a, b) => {
      let ta = a.readAt ? new Date(a.readAt).getTime() : 0;
      let tb = b.readAt ? new Date(b.readAt).getTime() : 0;
      return ta - tb;
    });
}

// What every format reads: readings newest first with their change, and the
// meter-triggered plan on the same asset (for "to service" and Linked).
class MeterView extends Component<typeof Meter> {
  private planQuery: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.planQuery = this.args.context?.getCards(
      this,
      () => {
        let ref = identifyCard(MaintenancePlan);
        let id = this.args.model?.asset?.id;
        return ref && id
          ? { filter: { on: ref, every: [{ eq: { 'asset.id': id } }] } }
          : undefined;
      },
      () => {
        let url = (this.args.model as any)?.[realmURL];
        return url ? [url.href] : undefined;
      },
      { isLive: true },
    );
  }

  get plan(): MaintenancePlan | undefined {
    let plans = (this.planQuery?.instances ?? []).filter(
      Boolean,
    ) as MaintenancePlan[];
    return plans.find((p) => p.trigger?.meterThreshold) ?? plans[0];
  }

  get rows() {
    let s = sorted(this.args.model.readings);
    let unit = this.args.model.unit;
    return s
      .map((r, i) => {
        let prev = i > 0 ? s[i - 1].value : undefined;
        let delta =
          prev != null && r.value != null ? r.value - prev : undefined;
        return {
          value: num(r.value, unit),
          meta: join(
            shortDate(r.readAt),
            r.readByName,
            delta ? `${delta > 0 ? '+' : ''}${num(delta, unit)}` : null,
          ),
          source: r.source ?? 'manual',
        };
      })
      .reverse();
  }

  get last() {
    let s = sorted(this.args.model.readings);
    return s[s.length - 1];
  }

  get sinceLabel() {
    let s = sorted(this.args.model.readings).slice(-8);
    return s.length > 1 ? `average since ${shortDate(s[0].readAt)}` : '—';
  }

  get toService(): number | undefined {
    let due = this.plan?.nextDueMeter;
    let c = this.args.model.current;
    return due != null && c != null ? Math.round(due - c) : undefined;
  }

  get details(): KvItem[] {
    let m = this.args.model;
    let u = m.unit;
    return [
      { key: 'Current', value: num(m.current, u) },
      {
        key: 'Last change',
        value: m.lastDelta != null ? `+${num(m.lastDelta, u)}` : '—',
      },
      { key: 'Per week', value: num(m.averagePerWeek, u) },
      { key: 'Warn above', value: num(m.warnAbove, u) },
      { key: 'Next service', value: num(this.plan?.nextDueMeter, u) },
      { key: 'Readings', value: String(sorted(m.readings).length) },
      { key: 'Kind', value: capital(m.kind) },
    ];
  }
}

class MeterIsolated extends MeterView {
  // Commands need the host; a card rendered without one cannot act.
  private get commandContext() {
    let context = this.args.context?.commandContext;
    if (!context) {
      throw new Error('This action needs a running host.');
    }
    return context;
  }

  @tracked newValue = '';
  @tracked recordError: string | undefined;

  get recordDisabled() {
    return this.newValue.trim() === '' || isNaN(Number(this.newValue));
  }

  get thresholds(): KvItem[] {
    let m = this.args.model;
    return [
      { key: 'Warn above', value: num(m.warnAbove, m.unit) },
      { key: 'Warn below', value: num(m.warnBelow, m.unit) },
      { key: 'Unit', value: dash(m.unit) },
    ];
  }

  setNewValue = (v: string) => {
    this.newValue = v;
  };

  recordReading = async (event?: Event) => {
    event?.preventDefault();
    this.recordError = undefined;
    let value = Number(this.newValue);
    if (this.newValue.trim() === '' || isNaN(value)) {
      this.recordError = 'Enter a numeric value.';
      return;
    }
    try {
      await new RecordMeterReadingCommand(this.commandContext).execute({
        meter: this.args.model,
        value,
      } as any);
      this.newValue = '';
    } catch (e: any) {
      this.recordError = e?.message ?? 'Could not record this reading.';
    }
  };

  <template>
    <Sheet>
      <:head>
        <Head @mark='Me' @title={{@model.name}} @meta={{metaLine @model}}>
          <:status><MeterDots @model={{@model}} /></:status>
          <:actions>
            <form class='log' {{on 'submit' this.recordReading}}>
              <Input
                class='log-input'
                aria-label='Reading value'
                @value={{this.newValue}}
                @onInput={{this.setNewValue}}
                @placeholder={{if @model.unit @model.unit 'Value'}}
                @type='number'
              />
              <Button
                class='log-btn'
                @size='s'
                @disabled={{this.recordDisabled}}
                type='submit'
              >Log reading</Button>
            </form>
          </:actions>
        </Head>
        {{#if this.recordError}}
          <p class='log-error' role='alert'>{{this.recordError}}</p>
        {{/if}}
      </:head>
      <:stats>
        <Stat
          @label='Current'
          @value={{num @model.current @model.unit}}
          @hint={{if
            this.last
            (concat 'read ' (shortDate this.last.readAt))
            'no readings yet'
          }}
          @roll={{false}}
        />
        <Stat
          @label='Per week'
          @value={{num @model.averagePerWeek @model.unit}}
          @hint={{this.sinceLabel}}
          @roll={{false}}
        />
        <Stat
          @label='To service'
          @value={{num this.toService @model.unit}}
          @hint={{if
            this.plan.nextDueMeter
            (concat 'due at ' (num this.plan.nextDueMeter @model.unit))
            'no meter plan'
          }}
          @roll={{false}}
        />
      </:stats>
      <:main>
        <Section @title='Readings'>
          {{#each this.rows as |r|}}
            <Row @title={{r.value}} @meta={{r.meta}} @state={{r.source}} />
          {{else}}
            <Row @title='No readings recorded yet' />
          {{/each}}
        </Section>
        <Section @title='Thresholds'>
          <KeyValue
            @items={{this.thresholds}}
            @labelStyle='eyebrow'
            @divided={{true}}
          />
        </Section>
      </:main>
      <:side>
        <Section @title='Linked'>
          <MeterLinks
            @model={{@model}}
            @fields={{@fields}}
            @plan={{this.plan}}
          />
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
    <style scoped>
      .log-btn {
        flex: none;
      }
      .log {
        flex: none;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin: 0;
      }
      .log-input {
        inline-size: 6rem;
      }
      .log-error {
        margin: 0;
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-xs);
        font-size: 0.6875rem;
        color: var(--destructive);
      }
    </style>
  </template>
}

/**
 * A per-asset counter or gauge — running hours, km, cycles, kWh, °C.
 * Readings are appended (Record Meter Reading is the single writer; a
 * cumulative meter must be monotonic). Meter-based maintenance plans fire
 * when the delta since the last completion crosses their threshold.
 */
export class Meter extends CardDef {
  static displayName = 'Meter';
  static icon = GaugeIcon;

  @field asset = linksTo(() => Asset);
  @field name = contains(StringField);
  @field kind = contains(MeterKindField);
  @field unit = contains(StringField);
  @field readings = containsMany(MeterReadingField);
  @field warnAbove = contains(QuantityField, {
    configuration: { options: { min: -Infinity } },
  });
  @field warnBelow = contains(QuantityField, {
    configuration: { options: { min: -Infinity } },
  });

  @field current = contains(NumberField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      return s.length ? s[s.length - 1].value : undefined;
    },
  });
  @field lastReadAt = contains(DateTimeField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      return s.length ? s[s.length - 1].readAt : undefined;
    },
  });
  @field lastDelta = contains(NumberField, {
    computeVia: function (this: Meter) {
      let s = sorted(this.readings);
      if (s.length < 2) return undefined;
      let a = s[s.length - 2].value ?? 0;
      let b = s[s.length - 1].value ?? 0;
      return Math.round((b - a) * 100) / 100;
    },
  });
  @field averagePerWeek = contains(NumberField, {
    computeVia: function (this: Meter) {
      if (this.kind === 'gauge') return undefined;
      let s = sorted(this.readings).slice(-8);
      if (s.length < 2) return undefined;
      let first = s[0];
      let last = s[s.length - 1];
      let weeks =
        (new Date(last.readAt!).getTime() - new Date(first.readAt!).getTime()) /
        (7 * 86_400_000);
      if (weeks <= 0) return undefined;
      return (
        Math.round((((last.value ?? 0) - (first.value ?? 0)) / weeks) * 10) / 10
      );
    },
  });
  @field isWarning = contains(StringField, {
    computeVia: function (this: Meter) {
      let c = this.current;
      if (c == null) return '';
      if (this.warnAbove != null && c > this.warnAbove) return 'above';
      if (this.warnBelow != null && c < this.warnBelow) return 'below';
      return '';
    },
  });
  @field assetId = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.id;
    },
  });
  @field assetTag = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.identifier?.value;
    },
  });
  @field assetName = contains(StringField, {
    computeVia: function (this: Meter) {
      return this.asset?.name;
    },
  });
  @field currentLabel = contains(StringField, {
    computeVia: function (this: Meter) {
      if (this.current == null) return 'No readings';
      return `${this.current.toLocaleString()} ${this.unit ?? ''}`.trim();
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Meter) {
      let n = this.name?.trim() || 'Meter';
      return this.assetTag ? `${this.assetTag} · ${n}` : n;
    },
  });

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AtomLine
        @mark='Me'
        @name={{join @model.assetName @model.name}}
        @tone={{if @model.isWarning 'warn' 'info'}}
        @meta={{if @model.current @model.currentLabel}}
      />
    </template>
  };

  static embedded = class Embedded extends MeterView {
    <template>
      <Brief @mark='Me' @title={{@model.name}} @meta={{metaLine @model}}>
        <:status><MeterDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Last read'
            @strong={{shortDate this.last.readAt}}
            @rest={{this.last.readByName}}
          /></:fact>
        <:default>
          <KeyValue
            @items={{this.details}}
            @labelStyle='eyebrow'
            @divided={{true}}
          />
          <MeterLinks
            @model={{@model}}
            @fields={{@fields}}
            @plan={{this.plan}}
          />
        </:default>
      </Brief>
    </template>
  };

  static fitted = class Fitted extends MeterView {
    <template>
      <FitTile>
        <:avatar><Mark @text='Me' @size='lg' /></:avatar>
        <:title>{{@model.name}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><MeterDots @model={{@model}} /></:status>
        <:fact><Fact
            @lead='Last read'
            @strong={{shortDate this.last.readAt}}
            @rest={{this.last.readByName}}
          /></:fact>
        <:relations>
          {{#if @model.asset}}<@fields.asset @format='atom' />{{/if}}
        </:relations>
      </FitTile>
    </template>
  };

  static isolated = MeterIsolated;
}

function concat(...parts: unknown[]) {
  return parts.join('');
}

function capital(s?: string | null) {
  return s ? s[0].toUpperCase() + s.slice(1) : '—';
}

function metaLine(m: Partial<Meter>) {
  return join(m.assetTag, m.assetName, m.kind);
}

const MeterDots: TemplateOnlyComponent<{ Args: { model: Partial<Meter> } }> =
  <template>
    <Dot
      @tone={{if @model.isWarning 'warn' 'info'}}
      @label={{@model.currentLabel}}
    />
    {{#if @model.warnAbove}}
      <Dot @label='warn at {{num @model.warnAbove}}' />
    {{else if @model.warnBelow}}
      <Dot @label='warn under {{num @model.warnBelow}}' />
    {{/if}}
  </template>;

const LINKS: KvItem[] = [
  { key: 'Asset', value: '' },
  { key: 'Read by', value: '' },
  { key: 'Plan', value: '' },
];

const MeterLinks: TemplateOnlyComponent<{
  Args: { model: Partial<Meter>; fields: any; plan?: MaintenancePlan };
}> = <template>
  <KeyValue @items={{LINKS}} @labelStyle='eyebrow' @divided={{true}}>
    <:value as |item|>
      {{#if (eq item.key 'Asset')}}
        {{#if @model.asset}}<@fields.asset @format='atom' />{{else}}—{{/if}}
      {{else if (eq item.key 'Read by')}}
        {{dash (lastReader @model)}}
      {{else if @plan}}
        <AtomLine
          @mark='Pl'
          @name={{@plan.name}}
          @tone={{if @plan.active 'ok'}}
          @meta={{if @plan.active 'active' 'paused'}}
        />
      {{else}}—{{/if}}
    </:value>
  </KeyValue>
</template>;

function lastReader(m: Partial<Meter>) {
  let s = sorted(m.readings);
  return s[s.length - 1]?.readByName;
}

export default Meter;
