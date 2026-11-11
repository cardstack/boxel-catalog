import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { resource, use } from 'ember-resources';
import { TrackedObject } from 'tracked-built-ins';
import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
  linksTo,
  type CardContext,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import CodeRefField from '@cardstack/base/code-ref';
import enumField from '@cardstack/base/enum';
import { FileDef } from '@cardstack/base/file-api';
import {
  operation,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { subscribeToRealm } from '@cardstack/runtime-common';
import ReadTextFileTool from '@cardstack/boxel-host/tools/read-text-file';
import WriteTextFileTool from '@cardstack/boxel-host/tools/write-text-file';
import { Button } from '@cardstack/pretui/components/button';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Callout } from '@cardstack/pretui/components/callout';
import { Chip } from '@cardstack/pretui/components/chip';
import { Combobox } from '@cardstack/pretui/components/combobox';
import { DatePicker } from '@cardstack/pretui/components/date-picker';
import { Descriptions } from '@cardstack/pretui/components/descriptions';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Field } from '@cardstack/pretui/components/field';
import { FormSection } from '@cardstack/pretui/components/form-section';
import { FormatBytes } from '@cardstack/pretui/components/format-bytes';
import { Input } from '@cardstack/pretui/components/input';
import { Item } from '@cardstack/pretui/components/item';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { NumberInput } from '@cardstack/pretui/components/number-input';
import { PanelSection } from '@cardstack/pretui/components/panel-section';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { StepList } from '@cardstack/pretui/components/step-list';
import { Switch } from '@cardstack/pretui/components/switch';
import { TimeInput } from '@cardstack/pretui/components/time-input';
import { Token } from '@cardstack/pretui/components/token';
import { eq } from '@cardstack/pretui/helpers';
import CalendarCheckIcon from '@cardstack/boxel-icons/calendar-check';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import PlugIcon from '@cardstack/boxel-icons/plug';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import ZapIcon from '@cardstack/boxel-icons/zap';
import { describeCron } from '@cardstack/catalog/automation/describe-cron';
import { CodeEdit, CodeView } from '@cardstack/catalog/fields/code/code';

// An automation's definition: the Realm Runner script it runs, when it runs,
// and what each run may do and spend. The server reads these fields from the
// index as data and never runs this module to learn them, so every field the
// server reads is a stored value, never a computed. Who pays for an
// automation and whether it is switched on are server state, not fields here.

const TRIGGER_KINDS = [
  { value: 'cron', label: 'Schedule' },
  { value: 'once', label: 'Once' },
  { value: 'webhook', label: 'Webhook' },
];

export const AutomationTriggerKind = markDefinition(
  enumField(StringField, {
    displayName: 'Trigger Kind',
    options: TRIGGER_KINDS,
  }),
);

let timeZoneOptions: { value: string; label: string }[] | undefined;
function timeZones() {
  timeZoneOptions ??= Intl.supportedValuesOf('timeZone').map((zone) => ({
    value: zone,
    label: zone.replaceAll('_', ' '),
  }));
  return timeZoneOptions;
}

// DateField holds a local Date; the date controls speak `yyyy-mm-dd`.
function isoDate(date: Date | null | undefined): string | undefined {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return undefined;
  }
  let pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
function localDate(iso: string): Date | null {
  if (!iso) {
    return null;
  }
  let [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
}

function duration(seconds: number | null | undefined): string {
  if (typeof seconds !== 'number') {
    return '—';
  }
  let minutes = Math.floor(seconds / 60);
  let rest = seconds % 60;
  if (minutes === 0) {
    return `${rest} s`;
  }
  return rest === 0 ? `${minutes} min` : `${minutes} min ${rest} s`;
}

function count(value: number | null | undefined): string {
  return typeof value === 'number' ? value.toLocaleString('en-US') : '—';
}

// A name and a value handed to the script. Values are text; the script parses
// what it needs.
export class AutomationParam extends FieldDef {
  static displayName = 'Automation Param';

  @field name = contains(StringField);
  @field value = contains(StringField);

  static embedded = class Embedded extends Component<typeof AutomationParam> {
    get items() {
      return [
        { key: this.args.model.name ?? '', value: this.args.model.value ?? '' },
      ];
    }
    <template><KeyValue @items={{this.items}} @layout='inline' /></template>
  };

  static edit = class Edit extends Component<typeof AutomationParam> {
    setName = (value: string) => (this.args.model.name = value);
    setValue = (value: string) => (this.args.model.value = value);
    <template>
      <div class='automation-pair'>
        <Field @label='Name' @reserveMessage={{false}} as |id|>
          <Input
            @controlId={{id}}
            @value={{@model.name}}
            @onInput={{this.setName}}
          />
        </Field>
        <Field @label='Value' @reserveMessage={{false}} as |id|>
          <Input
            @controlId={{id}}
            @value={{@model.value}}
            @onInput={{this.setValue}}
          />
        </Field>
      </div>
      <style scoped>
        .automation-pair {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 2fr);
          gap: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };
}

// A cron expression's plain reading: a one-line summary, then the times,
// days or months it names as bulleted lists.
class CronReading extends GlimmerComponent<{
  Args: { expression?: string | null };
  Element: HTMLDivElement;
}> {
  get reading() {
    return describeCron(this.args.expression);
  }
  <template>
    {{#if this.reading}}
      <div class='cron-reading' ...attributes>
        <p class='cron-reading__summary'>{{this.reading.summary}}</p>
        {{#each this.reading.groups as |group|}}
          <div class='cron-reading__group'>
            <span class='cron-reading__label'>{{group.label}}</span>
            <ul class='cron-reading__list'>
              {{#each group.items as |item|}}
                <li>{{item}}</li>
              {{/each}}
            </ul>
          </div>
        {{/each}}
      </div>
    {{/if}}
    <style scoped>
      .cron-reading {
        display: grid;
        gap: var(--boxel-sp-2xs);
      }
      .cron-reading__summary {
        margin: 0;
        font-weight: 600;
      }
      .cron-reading__group {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      .cron-reading__label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .cron-reading__list {
        margin: 0;
        padding-inline-start: var(--boxel-sp);
      }
    </style>
  </template>
}

// When the automation runs. Which fields apply depends on `kind`:
//
// - `cron`: `expression` (five fields, or a macro such as `@daily`) in
//   `timeZone`, firing at most once every 5 minutes. It stops after `count`
//   runs, or after `untilDate` (at `untilTime`, else the end of that day, in
//   `timeZone`), whichever comes first.
// - `once`: `date` at `time` in `timeZone`.
// - `webhook`: a delivery to the realm's incoming webhook at `webhookPath`.
//
// Times are wall-clock `HH:MM`. `label` names the trigger within its
// automation. The server counts a trigger's runs by its label, so editing the
// trigger's schedule keeps its count and renaming it starts a new one.
export class AutomationTrigger extends FieldDef {
  static displayName = 'Automation Trigger';

  @field kind = contains(AutomationTriggerKind);
  @field label = contains(StringField);
  @field expression = contains(StringField);
  @field timeZone = contains(StringField);
  @field untilDate = contains(DateField);
  @field untilTime = contains(StringField);
  @field count = contains(NumberField);
  @field date = contains(DateField);
  @field time = contains(StringField);
  @field webhookPath = contains(StringField);
  // Merged over the automation's own `params` for runs this trigger starts.
  @field params = containsMany(AutomationParam);

  static embedded = class Embedded extends Component<typeof AutomationTrigger> {
    get kindLabel() {
      return (
        TRIGGER_KINDS.find((k) => k.value === this.args.model.kind)?.label ??
        'Unknown'
      );
    }
    get until() {
      let date = isoDate(this.args.model.untilDate);
      return date
        ? `Until ${date} ${this.args.model.untilTime ?? '23:59'}`
        : '';
    }
    get runs() {
      let n = this.args.model.count;
      return typeof n === 'number' ? `${n} run${n === 1 ? '' : 's'}` : '';
    }
    get onDate() {
      return isoDate(this.args.model.date) ?? '—';
    }
    get schedule() {
      return describeCron(this.args.model.expression);
    }
    <template>
      <Item @size='s' @wrap={{true}} class='automation-trigger'>
        <:leading>
          <span class='automation-trigger__icon' aria-hidden='true'>
            {{#if (eq @model.kind 'cron')}}
              <RepeatIcon width='18' height='18' />
            {{else if (eq @model.kind 'once')}}
              <CalendarCheckIcon width='18' height='18' />
            {{else}}
              <ZapIcon width='18' height='18' />
            {{/if}}
          </span>
        </:leading>
        <:title>{{@model.label}}</:title>
        <:description>
          {{#if (eq @model.kind 'cron')}}
            {{#if this.schedule}}
              {{this.schedule.summary}}
            {{else}}
              On the schedule below
            {{/if}}
            ·
            {{@model.timeZone}}
          {{else if (eq @model.kind 'once')}}
            {{this.onDate}}
            at
            {{@model.time}}
            in
            {{@model.timeZone}}
          {{else}}
            Delivery to
            <Token @value={{@model.webhookPath}} />
          {{/if}}
        </:description>
        <:default>
          {{#if (eq @model.kind 'cron')}}
            <div class='automation-trigger__detail'>
              <Token @value={{@model.expression}} />
              {{#each this.schedule.groups as |group|}}
                <div class='automation-trigger__group'>
                  <span class='automation-trigger__group-label'>
                    {{group.label}}
                  </span>
                  <ul class='automation-trigger__list'>
                    {{#each group.items as |item|}}
                      <li>{{item}}</li>
                    {{/each}}
                  </ul>
                </div>
              {{/each}}
            </div>
          {{/if}}
        </:default>
        <:trailing>
          <span class='automation-trigger__meta'>
            {{#if this.runs}}
              <Chip @label={{this.runs}} @appearance='plain' />
            {{/if}}
            {{#if this.until}}
              <Chip @label={{this.until}} @appearance='plain' />
            {{/if}}
            <Chip @label={{this.kindLabel}} @appearance='soft' @dot={{false}} />
          </span>
        </:trailing>
      </Item>
      <style scoped>
        .automation-trigger {
          container-type: inline-size;
        }
        .automation-trigger__icon {
          display: grid;
          place-items: center;
          width: 2rem;
          height: 2rem;
          border-radius: var(--radius);
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
        .automation-trigger__detail {
          display: grid;
          justify-items: start;
          gap: var(--boxel-sp-2xs);
          margin-top: var(--boxel-sp-2xs);
        }
        .automation-trigger__group {
          display: grid;
          gap: var(--boxel-sp-5xs);
        }
        .automation-trigger__group-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--muted-foreground);
        }
        .automation-trigger__list {
          margin: 0;
          padding-inline-start: var(--boxel-sp);
          font-size: var(--boxel-font-size-sm);
        }
        .automation-trigger__meta {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs);
          justify-content: end;
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof AutomationTrigger> {
    get timeZones() {
      return timeZones();
    }
    get kind() {
      return this.args.model.kind ?? 'cron';
    }
    get untilDate() {
      return isoDate(this.args.model.untilDate);
    }
    get date() {
      return isoDate(this.args.model.date);
    }
    assign = (name: string, value: unknown) => {
      (this.args.model as Record<string, unknown>)[name] = value;
    };
    setText = (name: string, value: string) =>
      this.assign(name, value === '' ? null : value);
    setDate = (name: string, value: string) =>
      this.assign(name, localDate(value));
    <template>
      <div class='automation-trigger-edit'>
        <div class='automation-trigger-edit__row'>
          <Field @label='Runs on' @labelTag='span' as |_id _msg labelId|>
            <SegmentedControl
              @options={{TRIGGER_KINDS}}
              @value={{this.kind}}
              @onValueChange={{fn this.assign 'kind'}}
              aria-labelledby={{labelId}}
            />
          </Field>
          <Field
            @label='Label'
            @hint='Its run count is kept under this name'
            as |id|
          >
            <Input
              @controlId={{id}}
              @value={{@model.label}}
              @onInput={{fn this.setText 'label'}}
            />
          </Field>
        </div>
        {{#if (eq this.kind 'cron')}}
          <div class='automation-trigger-edit__row'>
            <Field
              @label='Cron expression'
              @hint='Five fields or a macro like @daily; at most every 5 minutes'
              as |id|
            >
              <Input
                @controlId={{id}}
                @value={{@model.expression}}
                @placeholder='0 7 * * MON'
                @onInput={{fn this.setText 'expression'}}
                class='automation-trigger-edit__mono'
              />
            </Field>
            <Field @label='Time zone' @labelTag='span' as |_id _msg labelId|>
              <Combobox
                @options={{this.timeZones}}
                @value={{@model.timeZone}}
                @placeholder='America/Chicago'
                @onValueChange={{fn this.setText 'timeZone'}}
                aria-labelledby={{labelId}}
              />
            </Field>
          </div>
          <CronReading
            @expression={{@model.expression}}
            class='automation-trigger-edit__reading'
          />
          <div
            class='automation-trigger-edit__row automation-trigger-edit__row--3'
          >
            <Field
              @label='Stop after'
              @hint='Runs; leave empty for no limit'
              as |id|
            >
              <NumberInput
                @controlId={{id}}
                @value={{@model.count}}
                @min={{1}}
                @precision={{0}}
                @onInput={{fn this.assign 'count'}}
              />
            </Field>
            <Field @label='Until date' @labelTag='span'>
              <DatePicker
                @value={{this.untilDate}}
                @onValueChange={{fn this.setDate 'untilDate'}}
              />
            </Field>
            <Field
              @label='Until time'
              @labelTag='span'
              @hint='End of the day when empty'
            >
              <TimeInput
                @value={{@model.untilTime}}
                @label='Until time'
                @onValueChange={{fn this.setText 'untilTime'}}
              />
            </Field>
          </div>
        {{else if (eq this.kind 'once')}}
          <div
            class='automation-trigger-edit__row automation-trigger-edit__row--3'
          >
            <Field @label='Date' @labelTag='span'>
              <DatePicker
                @value={{this.date}}
                @onValueChange={{fn this.setDate 'date'}}
              />
            </Field>
            <Field @label='Time' @labelTag='span'>
              <TimeInput
                @value={{@model.time}}
                @label='Time'
                @onValueChange={{fn this.setText 'time'}}
              />
            </Field>
            <Field @label='Time zone' @labelTag='span' as |_id _msg labelId|>
              <Combobox
                @options={{this.timeZones}}
                @value={{@model.timeZone}}
                @placeholder='America/Chicago'
                @onValueChange={{fn this.setText 'timeZone'}}
                aria-labelledby={{labelId}}
              />
            </Field>
          </div>
        {{else}}
          <Field
            @label='Webhook path'
            @hint='One of this workspace’s incoming webhooks'
            as |id|
          >
            <Input
              @controlId={{id}}
              @value={{@model.webhookPath}}
              @onInput={{fn this.setText 'webhookPath'}}
              class='automation-trigger-edit__mono'
            />
          </Field>
        {{/if}}
        <Field
          @label='Params for this trigger'
          @labelTag='span'
          @hint='Merged over the automation’s own params'
        >
          <@fields.params />
        </Field>
      </div>
      <style scoped>
        .automation-trigger-edit {
          display: grid;
          gap: var(--boxel-sp-xs);
          container-type: inline-size;
        }
        .automation-trigger-edit__row {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--boxel-sp);
        }
        .automation-trigger-edit__row--3 {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        .automation-trigger-edit__reading {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-radius: var(--radius);
          background-color: var(--muted);
        }
        .automation-trigger-edit__mono {
          font-family: var(--font-mono);
        }
        @container (inline-size < 36rem) {
          .automation-trigger-edit__row,
          .automation-trigger-edit__row--3 {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      </style>
    </template>
  };
}

// A `callApi` operation the script may call: the card type that declares it
// and the operation's name.
export class AutomationOperation extends FieldDef {
  static displayName = 'Automation Operation';

  @field targetType = contains(CodeRefField);
  @field operation = contains(StringField);

  static embedded = class Embedded extends Component<
    typeof AutomationOperation
  > {
    // `openIssues` reads as "Open issues".
    get title() {
      let name = this.args.model.operation ?? '';
      let words = name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
      return words.charAt(0).toUpperCase() + words.slice(1);
    }
    <template>
      <Item @size='s' @wrap={{true}}>
        <:leading>
          <span class='automation-operation__icon' aria-hidden='true'>
            <PlugIcon width='18' height='18' />
          </span>
        </:leading>
        <:title>{{this.title}}</:title>
        <:description>
          <Token @value={{@model.operation}} />
          on
          <Token @value={{@model.targetType.name}} />
        </:description>
      </Item>
      <style scoped>
        .automation-operation__icon {
          display: grid;
          place-items: center;
          width: 2rem;
          height: 2rem;
          border-radius: var(--radius);
          background-color: var(--muted);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof AutomationOperation> {
    setOperation = (value: string) => (this.args.model.operation = value);
    <template>
      <div class='automation-operation-edit'>
        <Field @label='Card type' @labelTag='span'>
          <@fields.targetType />
        </Field>
        <Field
          @label='Operation'
          @hint='The name of one of that card type’s outside calls'
          as |id|
        >
          <Input
            @controlId={{id}}
            @value={{@model.operation}}
            @onInput={{this.setOperation}}
          />
        </Field>
      </div>
      <style scoped>
        .automation-operation-edit {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };
}

// The limits, in the words the card shows them in: what each run may use, and
// what the automation may spend in a month.
const RUN_LIMITS = [
  {
    key: 'callApiCalls',
    label: 'Outside calls',
    hint: 'Requests to services outside this workspace',
  },
  {
    key: 'responseBytes',
    label: 'Data received',
    hint: 'The total size of what those services send back',
  },
  {
    key: 'resolveCalls',
    label: 'AI requests',
    hint: 'Requests to an AI model',
  },
  {
    key: 'writes',
    label: 'Saves',
    hint: 'Files and cards it may create or change',
  },
  {
    key: 'seconds',
    label: 'Run time',
    hint: 'How long it may run, up to 20 minutes',
  },
] as const;

const MONTH_LIMIT = {
  key: 'monthlyCredits',
  label: 'Credits a month',
  hint: 'The most all of its runs together may spend in a calendar month',
} as const;

// What one run may do, and what the automation may spend in a calendar month.
// A run stops when it reaches any of them.
export class AutomationCaps extends FieldDef {
  static displayName = 'Automation Caps';

  @field callApiCalls = contains(NumberField);
  @field responseBytes = contains(NumberField);
  @field resolveCalls = contains(NumberField);
  @field writes = contains(NumberField);
  // At most 1200 (20 minutes).
  @field seconds = contains(NumberField);
  @field monthlyCredits = contains(NumberField);

  static embedded = class Embedded extends Component<typeof AutomationCaps> {
    get runItems() {
      let caps = this.args.model as Record<string, number | undefined>;
      return RUN_LIMITS.map((limit) => ({
        key: limit.key,
        label: limit.label,
        hint: limit.hint,
        value:
          limit.key === 'seconds'
            ? duration(caps.seconds)
            : count(caps[limit.key]),
      }));
    }
    get monthItems() {
      return [
        {
          key: MONTH_LIMIT.key,
          label: MONTH_LIMIT.label,
          hint: MONTH_LIMIT.hint,
          value: count(this.args.model.monthlyCredits),
        },
      ];
    }
    <template>
      <div class='automation-limits'>
        <Descriptions
          @title='Each run'
          @items={{this.runItems}}
          @columns={{3}}
          @layout='vertical'
          @bordered={{true}}
        >
          <:value as |item|>
            <span class='automation-limits__value'>
              {{#if (eq item.key 'responseBytes')}}
                <FormatBytes @value={{@model.responseBytes}} @base='decimal' />
              {{else}}
                {{item.value}}
              {{/if}}
            </span>
            <span class='automation-limits__hint'>{{item.hint}}</span>
          </:value>
        </Descriptions>
        <Descriptions
          @title='Each month'
          @items={{this.monthItems}}
          @columns={{3}}
          @layout='vertical'
          @bordered={{true}}
        >
          <:value as |item|>
            <span class='automation-limits__value'>{{item.value}}</span>
            <span class='automation-limits__hint'>{{item.hint}}</span>
          </:value>
        </Descriptions>
      </div>
      <style scoped>
        .automation-limits {
          display: grid;
          gap: var(--boxel-sp);
        }
        .automation-limits__value {
          display: block;
          font-size: var(--boxel-font-size-med);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        .automation-limits__hint {
          display: block;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof AutomationCaps> {
    runLimits = RUN_LIMITS;
    monthLimit = MONTH_LIMIT;
    assign = (name: string, value: number | null) => {
      (this.args.model as Record<string, unknown>)[name] = value;
    };
    value = (name: string) =>
      (this.args.model as Record<string, unknown>)[name] as number | undefined;
    <template>
      <div class='automation-caps-edit'>
        {{#each this.runLimits as |limit|}}
          <Field @label={{limit.label}} @hint={{limit.hint}} as |id|>
            <NumberInput
              @controlId={{id}}
              @value={{this.value limit.key}}
              @min={{0}}
              @max={{if (eq limit.key 'seconds') 1200}}
              @precision={{0}}
              @onInput={{fn this.assign limit.key}}
            />
          </Field>
        {{/each}}
        <Field
          @label={{this.monthLimit.label}}
          @hint={{this.monthLimit.hint}}
          as |id|
        >
          <NumberInput
            @controlId={{id}}
            @value={{@model.monthlyCredits}}
            @min={{0}}
            @precision={{0}}
            @onInput={{fn this.assign 'monthlyCredits'}}
          />
        </Field>
      </div>
      <style scoped>
        .automation-caps-edit {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
          gap: var(--boxel-sp-xs) var(--boxel-sp);
        }
      </style>
    </template>
  };
}

type Tools = NonNullable<CardContext['toolContext']>;

interface ScriptState {
  text: string | undefined;
  failure: string | undefined;
  loading: boolean;
}

// The text of the script an automation links, read through the host's file
// tool and read again whenever the workspace reports the file changed. With
// no tools (a prerendered view) it stays unloaded.
function scriptText(
  owner: object,
  args: () => { url: string | undefined; tools: Tools | undefined },
) {
  return use(
    owner,
    resource(({ on }) => {
      let state = new TrackedObject<ScriptState>({
        text: undefined,
        failure: undefined,
        loading: false,
      });
      let { url, tools } = args();
      if (!url || !tools) {
        return state;
      }
      let ended = false;
      let latest = 0;
      let read = async () => {
        let asked = ++latest;
        state.loading = true;
        try {
          let file = await new ReadTextFileTool(tools).execute({ path: url });
          if (!ended && asked === latest) {
            state.text = file.content ?? '';
            state.failure = undefined;
          }
        } catch (e) {
          if (!ended && asked === latest) {
            state.failure = e instanceof Error ? e.message : String(e);
          }
        } finally {
          if (!ended && asked === latest) {
            state.loading = false;
          }
        }
      };
      read();
      let realm = new URL('./', url).href;
      let unsubscribe = subscribeToRealm(realm, (event) => {
        if (
          event.eventName === 'index' &&
          'invalidations' in event &&
          event.invalidations.includes(url)
        ) {
          read();
        }
      });
      on.cleanup(() => {
        ended = true;
        unsubscribe();
      });
      return state;
    }),
  );
}

function toolsOf(context: CardContext | undefined): Tools | undefined {
  return context?.toolContext ?? context?.commandContext;
}

function fileName(url: string | undefined): string | undefined {
  return url?.split('/').pop();
}

// The linked script, read-only.
class ScriptView extends GlimmerComponent<{
  Args: { url: string | undefined; context: CardContext | undefined };
}> {
  private script = scriptText(this, () => ({
    url: this.args.url,
    tools: toolsOf(this.args.context),
  }));
  get state() {
    return this.script.current;
  }
  <template>
    {{#if this.state.failure}}
      <Callout @tone='warning' @title='The script can’t be shown'>
        {{this.state.failure}}
      </Callout>
    {{else if this.state.text}}
      <CodeView
        @code={{this.state.text}}
        @language='javascript'
        @filename={{fileName @url}}
      />
    {{else if this.state.loading}}
      <LoadingState @label='Loading the script' />
    {{/if}}
  </template>
}

// The linked script, edited in place and saved back to its file. Changes the
// file gets from elsewhere (code mode, another editor) replace the text here
// unless it has edits of its own that aren't saved yet.
class ScriptEditor extends GlimmerComponent<{
  Args: { url: string | undefined; context: CardContext | undefined };
}> {
  @tracked private draft: string | undefined;
  @tracked private saving = false;
  @tracked private saveFailure: string | undefined;
  private script = scriptText(this, () => ({
    url: this.args.url,
    tools: toolsOf(this.args.context),
  }));
  get state() {
    return this.script.current;
  }
  get text() {
    return this.draft ?? this.state.text ?? '';
  }
  get dirty() {
    return this.draft !== undefined && this.draft !== this.state.text;
  }
  setDraft = (code: string) => {
    this.draft = code;
  };
  save = async () => {
    let tools = toolsOf(this.args.context);
    if (!this.args.url || !tools || !this.dirty) {
      return;
    }
    this.saving = true;
    this.saveFailure = undefined;
    try {
      await new WriteTextFileTool(tools).execute({
        path: this.args.url,
        content: this.draft,
        overwrite: true,
      });
      this.draft = undefined;
    } catch (e) {
      this.saveFailure = e instanceof Error ? e.message : String(e);
    } finally {
      this.saving = false;
    }
  };
  revert = () => {
    this.draft = undefined;
  };
  <template>
    {{#if @url}}
      <div class='script-editor'>
        <CodeEdit
          @code={{this.text}}
          @language='javascript'
          @label={{fileName @url}}
          @onInput={{this.setDraft}}
          data-test-automation-script-editor
        />
        <div class='script-editor__actions'>
          {{#if this.dirty}}
            <Chip
              @label='Unsaved changes'
              @tone='warning'
              data-test-automation-script-unsaved
            />
            <Button
              @tone='neutral'
              @appearance='plain'
              @size='s'
              {{on 'click' this.revert}}
            >Discard</Button>
          {{/if}}
          <Button
            @size='s'
            @busy={{this.saving}}
            @disabled={{if this.dirty false true}}
            {{on 'click' this.save}}
            data-test-automation-script-save
          >Save script</Button>
        </div>
        {{#if this.saveFailure}}
          <Callout @tone='danger' @title='The script wasn’t saved'>
            {{this.saveFailure}}
          </Callout>
        {{/if}}
      </div>
    {{/if}}
    <style scoped>
      .script-editor {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .script-editor__actions {
        display: flex;
        align-items: center;
        justify-content: end;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}

class Isolated extends Component<typeof Automation> {
  get triggerSummary() {
    let n = this.args.model.triggers?.length ?? 0;
    return `${n} trigger${n === 1 ? '' : 's'}`;
  }
  get hasOperations() {
    return (this.args.model.operations?.length ?? 0) > 0;
  }
  get params() {
    return (this.args.model.params ?? []).map((p) => ({
      key: p.name ?? '',
      value: p.value ?? '',
    }));
  }
  get milestones() {
    return (this.args.model.milestones ?? []).map((label) => ({ label }));
  }
  get scriptURL() {
    return this.args.model.script?.id;
  }
  <template>
    <article class='automation'>
      <header class='automation__header'>
        <span class='automation__badge' aria-hidden='true'>
          <CalendarClockIcon width='28' height='28' />
        </span>
        <div class='automation__intro'>
          <p class='automation__eyebrow'>Automation</p>
          <h1 class='automation__title'><@fields.cardTitle /></h1>
          {{#if @model.cardDescription}}
            <p class='automation__summary'><@fields.cardDescription /></p>
          {{/if}}
        </div>
        {{#if @model.batchedAI}}
          <Chip @label='Batched AI' @tone='info' />
        {{/if}}
      </header>

      <Callout @tone='info' @title='Who runs it, and who pays'>
        It runs only after someone who can edit this workspace turns it on. That
        person pays for its runs.
      </Callout>

      <PanelSection @title='Script' @collapsible={{false}}>
        <ScriptView @url={{this.scriptURL}} @context={{@context}} />
      </PanelSection>

      <PanelSection
        @title='When it runs'
        @summary={{this.triggerSummary}}
        @collapsible={{false}}
      >
        {{#if @model.triggers.length}}
          <div class='automation__rows'>
            {{#each @fields.triggers as |Trigger|}}
              <Trigger class='automation__row' />
            {{/each}}
          </div>
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No triggers'
            @message='Add a schedule, a one-time run or a webhook to say when it runs.'
          />
        {{/if}}
      </PanelSection>

      <PanelSection @title='Limits' @collapsible={{false}}>
        <p class='automation__lead'>
          A run stops as soon as it reaches any of these.
        </p>
        <@fields.caps />
      </PanelSection>

      <PanelSection @title='Outside services' @collapsible={{false}}>
        {{#if this.hasOperations}}
          <p class='automation__lead'>
            The only outside calls its script may make. It can’t reach any other
            service.
          </p>
          <div class='automation__rows'>
            {{#each @fields.operations as |Operation|}}
              <Operation class='automation__row' />
            {{/each}}
          </div>
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No outside services'
            @message='Its script can’t contact any service outside this workspace.'
          />
        {{/if}}
      </PanelSection>

      <PanelSection @title='Params' @collapsible={{false}}>
        {{#if this.params.length}}
          <KeyValue @items={{this.params}} @divided={{true}} />
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No params'
            @message='Values the script is handed when it runs.'
          />
        {{/if}}
      </PanelSection>

      <PanelSection @title='Run milestones' @collapsible={{false}}>
        {{#if this.milestones.length}}
          <StepList
            @steps={{this.milestones}}
            @label='Run milestones'
            @announce={{false}}
          />
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No milestones'
            @message='The steps a run reports as it goes.'
          />
        {{/if}}
      </PanelSection>
    </article>
    <style scoped>
      .automation {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-xl);
        container-type: inline-size;
      }
      .automation__header {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        align-items: start;
        gap: var(--boxel-sp);
      }
      .automation__badge {
        display: grid;
        place-items: center;
        width: 3.5rem;
        height: 3.5rem;
        border-radius: var(--radius);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .automation__intro > * {
        margin: 0;
      }
      .automation__eyebrow {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        letter-spacing: var(--boxel-lsp-lg);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .automation__title {
        font-size: var(--boxel-font-size-xl);
        font-weight: 600;
        line-height: 1.2;
      }
      .automation__summary {
        margin-top: var(--boxel-sp-4xs);
        color: var(--muted-foreground);
        max-width: 60ch;
      }
      .automation__lead {
        margin: 0 0 var(--boxel-sp-sm);
        color: var(--muted-foreground);
      }
      .automation__rows {
        display: grid;
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .automation__row + .automation__row {
        border-top: 1px solid var(--border);
      }
      .automation__row {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      @container (inline-size < 40rem) {
        .automation {
          padding: var(--boxel-sp);
        }
      }
    </style>
  </template>
}

class Edit extends Component<typeof Automation> {
  setBatchedAI = (value: boolean) => (this.args.model.batchedAI = value);
  get scriptURL() {
    return this.args.model.script?.id;
  }
  <template>
    <div class='automation-edit'>
      <FormSection @title='About'>
        <@fields.cardInfo />
      </FormSection>
      <FormSection
        @title='Script'
        @description='The code it runs: a script file in this workspace'
      >
        <@fields.script />
        <ScriptEditor @url={{this.scriptURL}} @context={{@context}} />
      </FormSection>
      <FormSection
        @title='When it runs'
        @description='Each trigger keeps its own count of runs'
      >
        <@fields.triggers />
      </FormSection>
      <FormSection
        @title='Limits'
        @description='A run stops as soon as it reaches any of these'
      >
        <@fields.caps />
      </FormSection>
      <FormSection
        @title='Outside services'
        @description='The only outside calls its script may make'
      >
        <@fields.operations />
      </FormSection>
      <FormSection
        @title='Params'
        @description='Values the script is handed when it runs'
      >
        <@fields.params />
      </FormSection>
      <FormSection
        @title='Run milestones'
        @description='The steps a run reports as it goes, in order'
      >
        <@fields.milestones />
      </FormSection>
      <FormSection @title='AI'>
        <Field
          @label='Batched AI'
          @orientation='horizontal'
          @hint='Send its AI requests as one batch for a lower price. The run pauses until the batch is done.'
          as |id|
        >
          <Switch
            @controlId={{id}}
            @checked={{@model.batchedAI}}
            @onCheckedChange={{this.setBatchedAI}}
          />
        </Field>
      </FormSection>
    </div>
    <style scoped>
      .automation-edit {
        display: grid;
        gap: var(--boxel-sp-lg);
        padding: var(--boxel-sp-xl);
      }
    </style>
  </template>
}

export class Automation extends CardDef {
  static displayName = 'Automation';
  static icon = CalendarClockIcon;

  // A script file in the same realm as this card.
  @field script = linksTo(FileDef);
  @field triggers = containsMany(AutomationTrigger);
  @field operations = containsMany(AutomationOperation);
  @field caps = contains(AutomationCaps);
  @field params = containsMany(AutomationParam);
  // The run's milestone names, in the order a run reaches them.
  @field milestones = containsMany(StringField);
  // Lets a run hand its AI requests to a provider's batch API, ending the run
  // and continuing in a follow-up run when the batch finishes. Off unless set.
  @field batchedAI = contains(BooleanField);

  // A run acts with its payer's authority, and its payer administers the
  // realm. So whoever can change what an automation does acts with an
  // administrator's authority: no policy grant may write one, and each write
  // is open only to a caller the realm's own permissions let write. These are
  // the writes a card carries, declared in their built-in form so they can be
  // marked. Each does what it does on any other card.
  @operation static update = {
    base: 'update',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static delete = {
    base: 'delete',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static transform = {
    base: 'transform',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  @operation static appendContainsMany = {
    base: 'appendContainsMany',
    nonGrantable: true,
  } satisfies OperationDeclaration;

  static isolated = Isolated;
  static edit = Edit;
}
