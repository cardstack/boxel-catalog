import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
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
  instanceRealmId,
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
  getDeclaredOperations,
  operation,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import {
  baseCardRef,
  chooseCard,
  chooseFile,
  identifyCard,
  realmURL,
  RealmPaths,
  ri,
  rri,
  subscribeToRealm,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import AuthedFetchTool from '@cardstack/boxel-host/tools/authed-fetch';
import ReadSourceTool from '@cardstack/boxel-host/tools/read-source';
import WriteTextFileTool from '@cardstack/boxel-host/tools/write-text-file';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Callout } from '@cardstack/pretui/components/callout';
import { Chip } from '@cardstack/pretui/components/chip';
import { Dialog } from '@cardstack/pretui/components/dialog';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import { Combobox } from '@cardstack/pretui/components/combobox';
import { DatePicker } from '@cardstack/pretui/components/date-picker';
import { Descriptions } from '@cardstack/pretui/components/descriptions';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Field } from '@cardstack/pretui/components/field';
import { FieldError } from '@cardstack/pretui/components/field-error';
import { RadioGroup } from '@cardstack/pretui/components/radio-group';
import { InputGroup } from '@cardstack/pretui/components/input-group';
import { Fieldset } from '@cardstack/pretui/components/fieldset';
import { FormSection } from '@cardstack/pretui/components/form-section';
import { FormatBytes } from '@cardstack/pretui/components/format-bytes';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { Input } from '@cardstack/pretui/components/input';
import { Item } from '@cardstack/pretui/components/item';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { NumberInput } from '@cardstack/pretui/components/number-input';
import { PanelSection } from '@cardstack/pretui/components/panel-section';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { Switch } from '@cardstack/pretui/components/switch';
import { Table } from '@cardstack/pretui/components/table';
import { TimeInput } from '@cardstack/pretui/components/time-input';
import { Token } from '@cardstack/pretui/components/token';
import { eq } from '@cardstack/pretui/helpers';
import CalendarCheckIcon from '@cardstack/boxel-icons/calendar-check';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import PlugIcon from '@cardstack/boxel-icons/plug';
import PlusIcon from '@cardstack/boxel-icons/plus';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import TrashIcon from '@cardstack/boxel-icons/trash-2';
import ZapIcon from '@cardstack/boxel-icons/zap';
import {
  cronProblem,
  describeCron,
} from '@cardstack/catalog/automation/describe-cron';
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

type TimeZoneOption = { value: string; label: string };
function timeZoneOption(zone: string): TimeZoneOption {
  return { value: zone, label: zone.replaceAll('_', ' ') };
}
// Every zone this runtime knows. Some engines leave UTC out of
// `supportedValuesOf`, though they accept it, so it's added here.
let timeZoneOptions: TimeZoneOption[] | undefined;
function timeZones(): TimeZoneOption[] {
  if (!timeZoneOptions) {
    let zones = Intl.supportedValuesOf('timeZone');
    timeZoneOptions = (zones.includes('UTC') ? zones : ['UTC', ...zones]).map(
      timeZoneOption,
    );
  }
  return timeZoneOptions;
}

// A problem with a list as a whole, in Pret UI's issue shape.
function listIssue(targetPath: string, message: string) {
  return { targetPath, severity: 'error' as const, message };
}
// Params need a name each, and no two may share one.
function paramsIssue(
  params: { name?: string | null }[] | undefined,
  targetPath: string,
) {
  let names = (params ?? []).map((p) => (p.name ?? '').trim());
  if (names.some((name) => !name)) {
    return listIssue(targetPath, 'Every param needs a name');
  }
  let repeated = names.find((name, i) => names.indexOf(name) !== i);
  return repeated
    ? listIssue(targetPath, `Two params share the name “${repeated}”`)
    : undefined;
}

// DateField holds a local Date; the date controls speak `yyyy-mm-dd`.
function isoDate(date: Date | null | undefined): string | undefined {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) {
    return undefined;
  }
  let pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}
// Whether this runtime knows the time zone by that IANA name.
function isTimeZone(name: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name });
    return true;
  } catch {
    return false;
  }
}
// The time zone of whoever is looking, as an IANA name.
function localTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone;
}
function lowerFirst(text: string): string {
  return text.charAt(0).toLowerCase() + text.slice(1);
}
// "Dec 31, 2026", for sentences.
function readableDate(date: Date | null | undefined): string | undefined {
  return isoDate(date)
    ? (date as Date).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : undefined;
}
// "17:30" as "5:30 PM".
function readableTime(time: string): string {
  let match = /^(\d{1,2}):(\d{2})$/.exec(time.trim());
  if (!match) {
    return time;
  }
  let hour = Number(match[1]);
  let h = hour % 12 === 0 ? 12 : hour % 12;
  return `${h}:${match[2]} ${hour < 12 ? 'AM' : 'PM'}`;
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

// A wait in minutes as people say it: "1 hour", "1 hour 30 minutes".
function waitLength(minutes: number): string {
  let hours = Math.floor(minutes / 60);
  let rest = minutes % 60;
  let h = hours === 1 ? '1 hour' : `${hours} hours`;
  let m = rest === 1 ? '1 minute' : `${rest} minutes`;
  return hours === 0 ? m : rest === 0 ? h : `${h} ${m}`;
}
const DEFAULT_BATCH_DEADLINE_MINUTES = 60;

// Whether the limits let a run make any AI request at all: it needs at least
// one AI request and some credits to spend on them.
function allowsAIRequests(model: {
  caps?: { resolveCalls?: number | null; aiCredits?: number | null } | null;
}) {
  return (
    (model.caps?.resolveCalls ?? 0) > 0 && (model.caps?.aiCredits ?? 0) > 0
  );
}

function count(value: number | null | undefined): string {
  return typeof value === 'number' ? value.toLocaleString('en-US') : '—';
}
// The limits a new automation starts with: enough for a typical automation
// to work, with AI on, spending a small share of the 2,000 credits a user
// gets each day (1,000 credits to the dollar).
const CAP_DEFAULTS: Record<string, number> = {
  callApiCalls: 10,
  responseBytes: 5_000_000,
  resolveCalls: 5,
  aiCredits: 300,
  writes: 50,
  seconds: 300,
  dailyCredits: 500,
  monthlyCredits: 10_000,
};
const REQUIRED_LIMIT = 'Required: enter a number, or 0 to forbid this';
const NOT_SET_HINT =
  'Required: Boxel won’t run this automation until this limit is set';
const NO_CREDIT_LIMIT = 'Set a daily or a monthly limit, or both';

// A cap of 0 forbids the thing outright, which reads better as a word.
function capValue(value: number | null | undefined): string {
  return value === 0 ? 'None' : count(value);
}

// A name and a value handed to the script. Values are text; the script parses
// what it needs.
export class AutomationParam extends FieldDef {
  static displayName = 'Param';

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

// How to write a cron expression: the five fields, the symbols, and common
// schedules a person can pick from, each with its plain reading.
const CRON_EXAMPLES = [
  '0 7 * * MON',
  '30 8 * * 1-5',
  '0 9,17 * * *',
  '0 */4 * * *',
  '*/15 * * * *',
  '0 9 1 * *',
  '@daily',
];
const CRON_FIELDS = [
  { position: '1st', name: 'Minute', values: '0–59', sample: '30' },
  {
    position: '2nd',
    name: 'Hour',
    values: '0–23, on a 24-hour clock',
    sample: '8',
  },
  { position: '3rd', name: 'Day of the month', values: '1–31', sample: '*' },
  { position: '4th', name: 'Month', values: '1–12, or JAN–DEC', sample: '*' },
  {
    position: '5th',
    name: 'Day of the week',
    values: '0–6 from Sunday, or SUN–SAT',
    sample: '1-5',
  },
];
const CRON_SYMBOLS = [
  { symbol: '*', meaning: 'Every value' },
  { symbol: ',', meaning: 'A list: 9,17 is 9 and 17' },
  { symbol: '-', meaning: 'A range: 1-5 is Monday through Friday' },
  {
    symbol: '*/n',
    meaning: 'Every nth: */15 in the minute field is every 15 minutes',
  },
];

class CronHelp extends GlimmerComponent<{
  Args: { onPick: (expression: string) => void };
}> {
  @tracked open = false;
  examples = CRON_EXAMPLES.map((expression) => ({
    expression,
    reading: describeCron(expression)?.summary ?? '',
  }));
  fields = CRON_FIELDS;
  symbols = CRON_SYMBOLS;
  show = () => (this.open = true);
  close = () => (this.open = false);
  pick = (expression: string) => {
    this.args.onPick(expression);
    this.open = false;
  };
  <template>
    <Button
      @appearance='link'
      @size='s'
      class='cron-help__open'
      {{on 'click' this.show}}
    >How to write a schedule</Button>
    <Dialog
      @open={{this.open}}
      @onClose={{this.close}}
      @size='m'
      @label='How to write a schedule'
    >
      <:title>How to write a schedule</:title>
      <:default>
        <div class='cron-help'>
          <p class='cron-help__lead'>
            A schedule is a cron expression: five values separated by spaces.
            Each value’s position says what it sets: the first is the minute,
            the second the hour, then the day of the month, the month and the
            day of the week. Times are in the trigger’s time zone, and a
            schedule can run at most once every 5 minutes.
          </p>
          <figure class='cron-help__anatomy'>
            <div class='cron-help__parts'>
              {{#each this.fields as |field|}}
                <div class='cron-help__part'>
                  <code class='cron-help__value'>{{field.sample}}</code>
                  <span class='cron-help__label'>{{field.name}}</span>
                </div>
              {{/each}}
            </div>
            <figcaption>
              <Token @value='30 8 * * 1-5' />
              runs at 8:30 AM, Monday through Friday.
            </figcaption>
          </figure>
          <Table @label='What each position sets'>
            <:head>
              <tr>
                <th scope='col'>Position</th>
                <th scope='col'>Sets</th>
                <th scope='col'>Values</th>
              </tr>
            </:head>
            <:body>
              {{#each this.fields as |field|}}
                <tr>
                  <td>{{field.position}}</td>
                  <td>{{field.name}}</td>
                  <td>{{field.values}}</td>
                </tr>
              {{/each}}
            </:body>
          </Table>
          <Table @label='What each symbol means'>
            <:head>
              <tr><th scope='col'>Symbol</th><th scope='col'>Means</th></tr>
            </:head>
            <:body>
              {{#each this.symbols as |row|}}
                <tr>
                  <td><Token @value={{row.symbol}} /></td>
                  <td>{{row.meaning}}</td>
                </tr>
              {{/each}}
            </:body>
          </Table>
          <h3 class='cron-help__heading'>Common schedules</h3>
          <ul class='cron-help__examples'>
            {{#each this.examples as |example|}}
              <li class='cron-help__example'>
                <Token @value={{example.expression}} />
                <span>{{example.reading}}</span>
                <Button
                  @appearance='outlined'
                  @size='xs'
                  {{on 'click' (fn this.pick example.expression)}}
                >Use this</Button>
              </li>
            {{/each}}
          </ul>
        </div>
      </:default>
      <:footer>
        <Button @appearance='outlined' {{on 'click' this.close}}>Close</Button>
      </:footer>
    </Dialog>
    <style scoped>
      .cron-help__open {
        justify-self: start;
      }
      .cron-help {
        display: grid;
        gap: var(--boxel-sp);
      }
      .cron-help__anatomy {
        display: grid;
        gap: var(--boxel-sp-sm);
        margin: 0;
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        font-size: var(--boxel-font-size-sm);
      }
      .cron-help__parts {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .cron-help__part {
        display: grid;
        justify-items: center;
        align-content: start;
        gap: var(--boxel-sp-4xs);
        text-align: center;
      }
      .cron-help__value {
        width: 100%;
        padding: var(--boxel-sp-4xs) 0;
        border-bottom: 2px solid var(--primary-ink);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-lg);
        font-weight: 600;
      }
      .cron-help__label {
        color: var(--muted-foreground);
      }
      .cron-help__heading {
        margin: var(--boxel-sp-xs) 0 0;
      }
      .cron-help__examples {
        display: grid;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .cron-help__example {
        display: grid;
        grid-template-columns: 9rem minmax(0, 1fr) auto;
        gap: var(--boxel-sp-sm);
        align-items: center;
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
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
  static displayName = 'Trigger';

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

  static embedded = class Embedded extends Component<typeof AutomationTrigger> {
    get kindLabel() {
      return (
        TRIGGER_KINDS.find((k) => k.value === this.args.model.kind)?.label ??
        'Unknown'
      );
    }
    get schedule() {
      return describeCron(this.args.model.expression);
    }
    get summary() {
      let { kind } = this.args.model;
      if (kind === 'cron') {
        let summary = this.schedule?.summary;
        return summary
          ? `On a schedule: ${lowerFirst(summary)}`
          : 'On a schedule';
      }
      if (kind === 'once') {
        return 'Once';
      }
      return 'When a delivery arrives at';
    }
    // A one-time run, as a sentence.
    get once() {
      let { date, time, timeZone } = this.args.model;
      let when = [
        time ? `at ${readableTime(time)}` : undefined,
        `on ${readableDate(date) ?? 'a date not yet set'}`,
      ]
        .filter(Boolean)
        .join(' ');
      return `This trigger fires once, ${when}, in ${timeZone} time.`;
    }
    // When a schedule stops, as a sentence, or '' when it runs indefinitely.
    get stops() {
      let { count, untilDate, untilTime } = this.args.model;
      let runs =
        typeof count === 'number'
          ? `after ${count} run${count === 1 ? '' : 's'}`
          : undefined;
      let day = readableDate(untilDate);
      let until = day
        ? untilTime
          ? `at ${readableTime(untilTime)} on ${day}`
          : `at the end of ${day}`
        : undefined;
      if (runs && until) {
        return `This trigger stops ${runs} or ${until}, whichever comes first.`;
      }
      return runs || until ? `This trigger stops ${runs ?? until}.` : '';
    }
    <template>
      <Item
        @size='s'
        @wrap={{true}}
        @alignStart={{true}}
        class='automation-trigger'
      >
        <:leading>
          <span class='automation-trigger__icon' title={{this.kindLabel}}>
            {{#if (eq @model.kind 'cron')}}
              <RepeatIcon width='18' height='18' aria-hidden='true' />
            {{else if (eq @model.kind 'once')}}
              <CalendarCheckIcon width='18' height='18' aria-hidden='true' />
            {{else}}
              <ZapIcon width='18' height='18' aria-hidden='true' />
            {{/if}}
            <VisuallyHidden>{{this.kindLabel}}</VisuallyHidden>
          </span>
        </:leading>
        <:title>{{@model.label}}</:title>
        <:description>
          {{this.summary}}
          {{#if (eq @model.kind 'webhook')}}
            <Token @value={{@model.webhookPath}} />
          {{/if}}
        </:description>
        <:default>
          {{#if (eq @model.kind 'webhook')}}
            {{! A delivery carries no time of its own. }}
          {{else}}
            <div class='automation-trigger__detail'>
              {{#if (eq @model.kind 'cron')}}
                {{#if this.schedule.groups.length}}
                  {{#each this.schedule.groups as |group index|}}
                    <p class='automation-trigger__sentence'>
                      {{#if (eq index 0)}}
                        This trigger fires in
                        {{@model.timeZone}}
                        time,
                        {{group.label}}:
                      {{else}}
                        and
                        {{group.label}}:
                      {{/if}}
                    </p>
                    <ul class='automation-trigger__list'>
                      {{#each group.items as |item|}}
                        <li>{{item}}</li>
                      {{/each}}
                    </ul>
                  {{/each}}
                {{else}}
                  <p class='automation-trigger__sentence'>
                    This trigger fires in
                    {{@model.timeZone}}
                    time.
                  </p>
                {{/if}}
                {{#if this.stops}}
                  <p class='automation-trigger__sentence'>{{this.stops}}</p>
                {{/if}}
                <p class='automation-trigger__cron'>
                  Written as cron
                  <Token @value={{@model.expression}} />
                </p>
              {{else}}
                <p class='automation-trigger__sentence'>{{this.once}}</p>
              {{/if}}
            </div>
          {{/if}}
        </:default>
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
          gap: var(--boxel-sp-4xs);
          margin-top: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-sm);
        }
        .automation-trigger__list {
          margin: 0 0 var(--boxel-sp-4xs);
          padding-inline-start: var(--boxel-sp-lg);
        }
        .automation-trigger__cron {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof AutomationTrigger> {
    constructor(owner: Owner, args: Edit['args']) {
      super(owner, args);
      // A new trigger is a schedule, as the editor shows it, and a schedule
      // or one-time run with no time zone yet starts in the editor's own, the
      // one its author most likely means. Filled after this render rather
      // than during it.
      Promise.resolve().then(() => {
        let model = this.args.model;
        if (this.isDestroying) {
          return;
        }
        if (!model.kind) {
          model.kind = 'cron';
        }
        if (!model.timeZone && model.kind !== 'webhook') {
          model.timeZone = localTimeZone();
        }
      });
    }
    // The trigger's own zone is always among the options, so the picker
    // shows it even when this runtime doesn't list it.
    get timeZones() {
      let zone = this.args.model.timeZone;
      let all = timeZones();
      return zone && !all.some((option) => option.value === zone)
        ? [timeZoneOption(zone), ...all]
        : all;
    }
    // What's wrong with each field, shown under it as the author types. The
    // server checks the same and more when the automation is turned on; these
    // catch the common slips early.
    get problems() {
      let m = this.args.model;
      let today = isoDate(new Date())!;
      let untilDate = isoDate(m.untilDate);
      let date = isoDate(m.date);
      let blank = (value: string | null | undefined) => !value?.trim();
      return {
        label: blank(m.label)
          ? 'Required: give this trigger a name'
          : undefined,
        expression: blank(m.expression)
          ? 'Required: enter when it runs, such as 0 7 * * MON'
          : cronProblem(m.expression),
        timeZone: blank(m.timeZone)
          ? 'Required: pick a time zone'
          : isTimeZone(m.timeZone!)
            ? undefined
            : 'Not a time zone; pick one from the list',
        webhookPath: blank(m.webhookPath)
          ? 'Required: enter one of this workspace’s incoming webhooks'
          : undefined,
        time: blank(m.time) ? 'Required: enter a time' : undefined,
        untilDate:
          untilDate && untilDate < today
            ? 'That day has already passed'
            : undefined,
        untilTime:
          m.untilTime && !untilDate ? 'Pick the last day too' : undefined,
        date: !date
          ? 'Required: pick a day'
          : date < today
            ? 'That day has already passed'
            : undefined,
      };
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
    // Switching to a schedule or a one-time run brings a time zone along.
    setKind = (kind: string) => {
      this.assign('kind', kind);
      if (kind !== 'webhook' && !this.args.model.timeZone) {
        this.assign('timeZone', localTimeZone());
      }
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
              @onValueChange={{this.setKind}}
              aria-labelledby={{labelId}}
            />
          </Field>
          <Field
            @label='Label'
            @hint='Boxel counts this trigger’s runs under this name'
            @error={{this.problems.label}}
            @required={{true}}
            as |id msgId|
          >
            <Input
              @controlId={{id}}
              @required={{true}}
              @invalid={{if this.problems.label true false}}
              @describedBy={{msgId}}
              @value={{@model.label}}
              @onInput={{fn this.setText 'label'}}
            />
          </Field>
        </div>
        {{#if (eq this.kind 'cron')}}
          <div class='automation-trigger-edit__cron'>
            <div class='automation-trigger-edit__row'>
              <Field
                @label='Cron expression'
                @hint='Five fields, such as 0 7 * * MON, or a macro like @daily'
                @error={{this.problems.expression}}
                @required={{true}}
                as |id msgId|
              >
                <div class='automation-trigger-edit__mono'>
                  <Input
                    @controlId={{id}}
                    @required={{true}}
                    @invalid={{if this.problems.expression true false}}
                    @describedBy={{msgId}}
                    @value={{@model.expression}}
                    @placeholder='0 7 * * MON'
                    @onInput={{fn this.setText 'expression'}}
                  />
                </div>
              </Field>
              <Field
                @label='Time zone'
                @labelTag='span'
                @error={{this.problems.timeZone}}
                @required={{true}}
                as |_id _msg labelId|
              >
                <Combobox
                  @label='Time zone'
                  @invalid={{if this.problems.timeZone true false}}
                  @options={{this.timeZones}}
                  @value={{@model.timeZone}}
                  @placeholder='America/Chicago'
                  @onValueChange={{fn this.setText 'timeZone'}}
                  aria-labelledby={{labelId}}
                />
              </Field>
            </div>
            <CronHelp @onPick={{fn this.setText 'expression'}} />
          </div>
          <CronReading
            @expression={{@model.expression}}
            class='automation-trigger-edit__reading'
          />
          <Fieldset
            @legend='When this trigger stops'
            @description='Set a number of runs, a last day, or both: this trigger stops at whichever comes first. Leave both empty to keep this trigger running.'
            class='automation-trigger-edit__stops'
          >
            <div
              class='automation-trigger-edit__row automation-trigger-edit__row--3'
            >
              <Field
                @label='Number of runs'
                @hint='A count, such as 52 for a year of weekly runs'
                as |id|
              >
                <NumberInput
                  @controlId={{id}}
                  @value={{@model.count}}
                  @min={{1}}
                  @precision={{0}}
                  @placeholder='No limit'
                  @onInput={{fn this.assign 'count'}}
                />
              </Field>
              <Field
                @label='Last day'
                @labelTag='span'
                @error={{this.problems.untilDate}}
              >
                <DatePicker
                  @value={{this.untilDate}}
                  @onValueChange={{fn this.setDate 'untilDate'}}
                />
              </Field>
              <Field
                @label='Time on the last day'
                @labelTag='span'
                @hint='Runs through the end of the day when empty'
                @error={{this.problems.untilTime}}
              >
                <TimeInput
                  @value={{@model.untilTime}}
                  @label='Time on the last day'
                  @onValueChange={{fn this.setText 'untilTime'}}
                />
              </Field>
            </div>
          </Fieldset>
        {{else if (eq this.kind 'once')}}
          <div
            class='automation-trigger-edit__row automation-trigger-edit__row--3'
          >
            <Field
              @label='Date'
              @labelTag='span'
              @error={{this.problems.date}}
              @required={{true}}
              @reserveMessage={{false}}
            >
              <DatePicker
                @value={{this.date}}
                @onValueChange={{fn this.setDate 'date'}}
              />
            </Field>
            <Field
              @label='Time'
              @labelTag='span'
              @error={{this.problems.time}}
              @required={{true}}
              @reserveMessage={{false}}
            >
              <TimeInput
                @value={{@model.time}}
                @label='Time'
                @onValueChange={{fn this.setText 'time'}}
              />
            </Field>
            <Field
              @label='Time zone'
              @labelTag='span'
              @error={{this.problems.timeZone}}
              @required={{true}}
              @reserveMessage={{false}}
              as |_id _msg labelId|
            >
              <Combobox
                @label='Time zone'
                @invalid={{if this.problems.timeZone true false}}
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
            @error={{this.problems.webhookPath}}
            @required={{true}}
            as |id msgId|
          >
            <div class='automation-trigger-edit__mono'>
              <Input
                @controlId={{id}}
                @required={{true}}
                @invalid={{if this.problems.webhookPath true false}}
                @describedBy={{msgId}}
                @value={{@model.webhookPath}}
                @onInput={{fn this.setText 'webhookPath'}}
              />
            </div>
          </Field>
        {{/if}}
      </div>
      <style scoped>
        .automation-trigger-edit {
          display: grid;
          gap: var(--boxel-sp);
          container-type: inline-size;
        }
        /* Pret UI's Field starts its control at the left, at its own width;
           a picker fills its column like the inputs beside it. */
        .automation-trigger-edit :deep(.pretui-combobox) {
          justify-self: stretch;
        }
        /* Each fieldset is a section of its own, with room above its title. */
        .automation-trigger-edit :deep(fieldset) {
          margin-top: var(--boxel-sp-xs);
        }
        .automation-trigger-edit__row {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: var(--boxel-sp);
        }
        .automation-trigger-edit__row--3 {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        /* The schedule help belongs to the cron field, so it sits close. */
        .automation-trigger-edit__cron {
          display: grid;
          gap: var(--boxel-sp-2xs);
        }
        /* Date and time pickers size to their text; in a row they fill their
           column, like the inputs beside them. */
        .automation-trigger-edit__row :deep(.pretui-datepicker),
        .automation-trigger-edit__row :deep(.pretui-datepicker .pretui-popover),
        .automation-trigger-edit__row
          :deep(.pretui-datepicker .pretui-popup-anchor) {
          display: block;
          width: 100%;
        }
        .automation-trigger-edit__row :deep(.pretui-time) {
          display: flex;
          box-sizing: border-box;
          width: 100%;
        }
        .automation-trigger-edit__reading {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background-color: var(--background);
          font-size: var(--boxel-font-size-sm);
        }
        .automation-trigger-edit__stops :deep(.pretui-time) {
          width: 100%;
        }
        /* Pret UI's Input inherits its font, so a wrapper sets it. */
        .automation-trigger-edit__mono {
          justify-self: stretch;
          font-family: var(
            --font-mono,
            var(--boxel-monospace-font-family, monospace)
          );
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

// An outside service as it reads: its call, and the card type it is on.
// `openIssues` reads as "Open issues".
function operationTitle(name: string | null | undefined): string {
  let words = (name ?? '').replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

class OperationView extends Component<typeof AutomationOperation> {
  // Both halves are set by Add an outside service; a row missing either
  // came from somewhere else and can't be called.
  get complete() {
    return Boolean(
      this.args.model.operation && this.args.model.targetType?.name,
    );
  }
  get title() {
    return operationTitle(this.args.model.operation);
  }
  <template>
    <Item @size='s' @wrap={{true}}>
      <:leading>
        <span class='automation-operation__icon' aria-hidden='true'>
          <PlugIcon width='18' height='18' />
        </span>
      </:leading>
      <:title>{{if this.complete this.title 'Not chosen'}}</:title>
      <:description>
        {{#if this.complete}}
          <Token @value={{@model.operation}} />
          on
          <Token @value={{@model.targetType.name}} />
        {{else}}
          Remove this, and add the outside service again.
        {{/if}}
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
}

// A `callApi` operation the script may call: the card type that declares it
// and the operation's name.
export class AutomationOperation extends FieldDef {
  static displayName = 'Outside Service';

  @field targetType = contains(CodeRefField);
  @field operation = contains(StringField);

  static embedded = OperationView;

  // Chosen with Add an outside service, not typed: shown as it reads.
  static edit = OperationView;
}

// The limits, in the words the card shows them in: what each run may use, and
// what the automation may spend in a month.
const RUN_LIMITS = [
  {
    key: 'callApiCalls',
    label: 'Outside calls',
    hint: 'Requests to services outside this workspace',
    noneHint: 'No calls to services outside this workspace',
  },
  {
    key: 'responseBytes',
    label: 'Data received',
    hint: 'The total size of what those services send back',
    editLabel: 'Data received, in MB',
    editHint: 'The total size of what those services send back',
    // Saved in bytes, edited in megabytes.
    scale: 1_000_000,
    precision: 1,
    noneHint: 'Nothing may come back from outside services',
  },
  {
    key: 'writes',
    label: 'Saves',
    hint: 'Files and cards a run may create or change',
    noneHint: 'A run may not create or change any file or card',
  },
  {
    key: 'resolveCalls',
    label: 'AI requests',
    hint: 'Requests to an AI model',
    noneHint: 'No AI requests',
  },
  {
    key: 'aiCredits',
    label: 'AI spending',
    hint: 'Credits a run’s AI requests may cost',
    editLabel: 'AI spending, in credits',
    editHint:
      'Boxel counts each AI request at the request’s highest possible cost',
    noneHint: 'No credits for AI requests',
  },
  {
    key: 'seconds',
    label: 'Run time',
    hint: 'How long a run may last, up to 20 minutes',
    noneHint: 'How long a run may last, up to 20 minutes',
    editLabel: 'Run time, in minutes',
    editHint: 'Up to 20 minutes',
    // Saved in seconds, edited in minutes.
    scale: 60,
    max: 20,
    precision: 1,
  },
] as const;

// What the automation may spend, counting every charge: runs, AI and storage.
const CREDIT_LIMITS = [
  {
    key: 'dailyCredits',
    label: 'Credits a day',
    hint: 'The most this automation may spend in a day, counting every charge',
  },
  {
    key: 'monthlyCredits',
    label: 'Credits a month',
    hint: 'The most this automation may spend in a calendar month, counting every charge',
  },
] as const;

// What one run may do, and what the automation may spend in a calendar month.
// Each is a ceiling: Boxel stops a run that tries to go past one, and 0
// means the run may not do that at all.
export class AutomationCaps extends FieldDef {
  static displayName = 'Automation Caps';

  @field callApiCalls = contains(NumberField);
  @field responseBytes = contains(NumberField);
  @field resolveCalls = contains(NumberField);
  // Credits a run's AI requests may cost in all. Boxel refuses an AI request
  // whose most possible cost would take the run past it.
  @field aiCredits = contains(NumberField);
  @field writes = contains(NumberField);
  // At most 1200 (20 minutes).
  @field seconds = contains(NumberField);
  // At most `monthlyCredits`.
  @field dailyCredits = contains(NumberField);
  @field monthlyCredits = contains(NumberField);

  static embedded = class Embedded extends Component<typeof AutomationCaps> {
    get runItems() {
      let caps = this.args.model as unknown as Record<
        string,
        number | undefined
      >;
      return RUN_LIMITS.map((limit) => ({
        key: limit.key,
        label: limit.label,
        value:
          caps[limit.key] == null
            ? 'Not set'
            : limit.key === 'seconds'
              ? duration(caps.seconds)
              : limit.key === 'aiCredits' && caps.aiCredits !== 0
                ? `${count(caps.aiCredits)} credits`
                : capValue(caps[limit.key]),
      }));
    }
    // The line under each limit's value: what it covers, or what 0 forbids.
    hintFor = (key: string | undefined) => {
      let limit = RUN_LIMITS.find((l) => l.key === key);
      let caps = this.args.model as unknown as Record<
        string,
        number | undefined
      >;
      if (!limit || !key) {
        return '';
      }
      if (caps[key] == null) {
        return NOT_SET_HINT;
      }
      if (caps[key] === 0) {
        return limit.noneHint;
      }
      // Either AI limit at 0 forbids AI requests, so the other AI limit
      // names the one that stops it.
      if (key === 'resolveCalls' && caps.aiCredits === 0) {
        return 'Unused while AI spending is 0';
      }
      if (key === 'aiCredits' && caps.resolveCalls === 0) {
        return 'Unused while AI requests is 0';
      }
      return limit.hint;
    };
    get dayCredits() {
      return count(this.args.model.dailyCredits);
    }
    get monthCredits() {
      return count(this.args.model.monthlyCredits);
    }
    get hasBoth() {
      return this.hasDay && this.hasMonth;
    }
    get hasDay() {
      return this.args.model.dailyCredits != null;
    }
    get hasMonth() {
      return this.args.model.monthlyCredits != null;
    }
    get spendsNothing() {
      return (
        this.args.model.dailyCredits === 0 ||
        this.args.model.monthlyCredits === 0
      );
    }
    <template>
      <div class='automation-limits'>
        <Descriptions
          @items={{this.runItems}}
          @columns={{3}}
          @layout='vertical'
          @bordered={{true}}
        >
          <:value as |item|>
            <span class='automation-limits__value'>
              {{#if (eq item.value 'None')}}
                None
              {{else if (eq item.value 'Not set')}}
                Not set
              {{else if (eq item.key 'responseBytes')}}
                <FormatBytes @value={{@model.responseBytes}} @base='decimal' />
              {{else}}
                {{item.value}}
              {{/if}}
            </span>
            <span class='automation-limits__hint'>{{this.hintFor
                item.key
              }}</span>
          </:value>
        </Descriptions>
        <p class='automation-limits__month'>
          {{#if this.spendsNothing}}
            This automation may not spend any credits.
          {{else if this.hasBoth}}
            This automation may spend at most
            <strong>{{this.dayCredits}}</strong>
            credits a day and
            <strong>{{this.monthCredits}}</strong>
            credits a calendar month, counting every charge: runs, AI and
            storage.
          {{else if this.hasDay}}
            This automation may spend at most
            <strong>{{this.dayCredits}}</strong>
            credits a day, counting every charge: runs, AI and storage.
          {{else if this.hasMonth}}
            This automation may spend at most
            <strong>{{this.monthCredits}}</strong>
            credits a calendar month, counting every charge: runs, AI and
            storage.
          {{else}}
            No credit limit is set. Boxel won’t run this automation until a
            daily or a monthly limit is.
          {{/if}}
        </p>
      </div>
      <style scoped>
        .automation-limits {
          display: grid;
          gap: var(--boxel-sp);
        }
        .automation-limits__value {
          display: block;
          font-size: var(--boxel-font-size-md);
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
    // Run time is edited in minutes and data in megabytes, and saved as the
    // seconds and bytes the server reads.
    editLabel = (limit: (typeof RUN_LIMITS)[number]) =>
      'editLabel' in limit ? limit.editLabel : limit.label;
    scaleOf = (limit: (typeof RUN_LIMITS)[number]) =>
      'scale' in limit ? limit.scale : 1;
    maxOf = (limit: (typeof RUN_LIMITS)[number]) =>
      'max' in limit ? limit.max : undefined;
    precisionOf = (limit: (typeof RUN_LIMITS)[number]) =>
      'precision' in limit ? limit.precision : 0;
    shown = (limit: (typeof RUN_LIMITS)[number]) => {
      let value = this.value(limit.key);
      return value == null ? undefined : value / this.scaleOf(limit);
    };
    assignScaled = (limit: (typeof RUN_LIMITS)[number], value: number | null) =>
      this.assign(
        limit.key,
        value == null ? null : Math.round(value * this.scaleOf(limit)),
      );
    // An empty run limit is an error: every one must be set.
    runProblem = (key: string) =>
      this.value(key) == null ? REQUIRED_LIMIT : undefined;
    editHint = (limit: (typeof RUN_LIMITS)[number]) =>
      'editHint' in limit ? limit.editHint : limit.hint;
    // Either credit limit is enough; with one empty, the other governs.
    creditHint = (limit: (typeof CREDIT_LIMITS)[number]) => {
      if (this.value(limit.key) != null) {
        return limit.hint;
      }
      return limit.key === 'dailyCredits'
        ? 'No daily limit: only the monthly limit applies'
        : 'No monthly limit: only the daily limit applies';
    };
    creditLimits = CREDIT_LIMITS;
    // The daily cap is a share of the monthly one, never more.
    creditProblem = (key: string) => {
      let { dailyCredits, monthlyCredits } = this.args.model;
      if (dailyCredits == null && monthlyCredits == null) {
        return NO_CREDIT_LIMIT;
      }
      return key === 'dailyCredits' &&
        typeof dailyCredits === 'number' &&
        typeof monthlyCredits === 'number' &&
        dailyCredits > monthlyCredits
        ? 'Can’t be more than the credits a month.'
        : undefined;
    };
    assign = (name: string, value: number | null) => {
      (this.args.model as Record<string, unknown>)[name] = value;
    };
    value = (name: string) =>
      (this.args.model as Record<string, unknown>)[name] as number | undefined;
    <template>
      <div class='automation-caps-edit'>
        {{#each this.runLimits as |limit|}}
          <Field
            class={{if
              (eq limit.key 'aiCredits')
              'automation-caps-edit__footnoted'
            }}
            @label={{this.editLabel limit}}
            @hint={{this.editHint limit}}
            @error={{this.runProblem limit.key}}
            @required={{true}}
            as |id|
          >
            <NumberInput
              @controlId={{id}}
              @required={{true}}
              @invalid={{if (this.runProblem limit.key) true false}}
              @value={{this.shown limit}}
              @min={{0}}
              @max={{this.maxOf limit}}
              @precision={{this.precisionOf limit}}
              @onInput={{fn this.assignScaled limit}}
            />
          </Field>
        {{/each}}
      </div>
      <div class='automation-caps-edit automation-caps-edit--credits'>
        {{#each this.creditLimits as |limit|}}
          <Field
            @label={{limit.label}}
            @hint={{this.creditHint limit}}
            @error={{this.creditProblem limit.key}}
            as |id|
          >
            <NumberInput
              @controlId={{id}}
              @invalid={{if (this.creditProblem limit.key) true false}}
              @value={{this.value limit.key}}
              @min={{0}}
              @precision={{0}}
              @onInput={{fn this.assign limit.key}}
            />
          </Field>
        {{/each}}
      </div>
      <p class='automation-caps-edit__footnote'><sup
          class='automation-caps-edit__mark'
        >†</sup>
        Boxel charges the actual amount once the AI provider reports the amount.</p>
      <style scoped>
        .automation-caps-edit {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(14rem, 1fr));
          gap: var(--boxel-sp-xs) var(--boxel-sp);
        }
        /* The AI spending hint points at the footnote below. Field's hint
           is plain text, so the mark goes on after it here, on the hint
           only: an error in its place gets none. */
        .automation-caps-edit__footnoted
          :deep(.pretui-cue[data-kind='description'] .pretui-cue-text::after) {
          content: '†';
          margin-left: 0.1em;
          font-size: 0.9em;
          font-weight: 600;
          line-height: 0;
          vertical-align: super;
        }
        .automation-caps-edit__mark {
          font-size: 0.9em;
          font-weight: 600;
          line-height: 0;
        }
        .automation-caps-edit__footnote {
          margin: var(--boxel-sp) 0 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        /* Spending gets a row of its own: a day and a month side by side. */
        .automation-caps-edit--credits {
          margin-top: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };
}

type Tools = NonNullable<CardContext['toolContext']>;

type ScriptState = {
  text: string | undefined;
  failure: string | undefined;
  loading: boolean;
};

// The text of the script an automation links, read through the host's file
// tool and read again whenever the workspace reports the file changed. With
// no tools (a prerendered view) it stays unloaded.
function scriptText(
  owner: object,
  args: () => {
    url: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    tools: Tools | undefined;
  },
) {
  // The resource runs again whenever an argument it reads changes, such as
  // the card context after a save. The state lives across those runs while
  // the script is the same file, so a run never blanks text already read,
  // which would empty the editor and make it read-only until the read ends.
  let kept: { url: string | undefined; state: ScriptState } | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { url, realm, realmId, tools } = args();
      if (!kept || kept.url !== url) {
        kept = {
          url,
          state: new TrackedObject<ScriptState>({
            text: undefined,
            failure: undefined,
            loading: false,
          }),
        };
      }
      let state = kept.state;
      if (!url || !tools) {
        return state;
      }
      let ended = false;
      let latest = 0;
      let read = async () => {
        let asked = ++latest;
        // Not while the resource runs: the page may have read `loading`
        // already in this render.
        await Promise.resolve();
        if (ended || asked !== latest) {
          return;
        }
        state.loading = true;
        try {
          let file = await new ReadSourceTool(tools).execute({ path: url });
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
      // The realm reports changed files by URL; the link may be a URL or a
      // prefix-form identifier, so the two meet at the path in the realm.
      let path = realmId ? pathInRealm(url, realmId) : undefined;
      let unsubscribe =
        realm && path
          ? subscribeToRealm(realm, (event) => {
              if (
                event.eventName === 'index' &&
                'invalidations' in event &&
                event.invalidations.includes(realm + path)
              ) {
                read();
              }
            })
          : undefined;
      on.cleanup(() => {
        ended = true;
        unsubscribe?.();
      });
      return state;
    }),
  );
}

// A file's path within its realm, or undefined when it's in another realm.
// `realmId` is the realm in the same form as the card's ids (see
// `instanceRealmId`), so the two compare without the realm mappings.
function pathInRealm(id: string, realmId: string): string | undefined {
  let paths = new RealmPaths(ri(realmId));
  let file = rri(id);
  return paths.inRealm(file) ? paths.local(file) : undefined;
}

function toolsOf(context: CardContext | undefined): Tools | undefined {
  return context?.toolContext ?? context?.commandContext;
}

function fileName(url: string | undefined): string | undefined {
  return url?.split('/').pop();
}

// What the server knows about an automation: whether someone switched the
// automation on, its state, who pays, and how far each trigger has got. The
// realm's `_automation-status` route answers only the realm's direct writers,
// so for anyone else `visible` stays false and the views show the card's own
// fields alone.
type AutomationState = 'active' | 'paused' | 'waiting-for-credits' | 'done';
type PauseReason =
  | 'requested'
  | 'realm-archived'
  | 'payer-lost-access'
  | 'caps-raised'
  | 'batched-ai-enabled';
interface TriggerStatus {
  label: string;
  runs: number;
  runsLeft?: number;
  runsLeftAtLeast?: boolean;
  until?: string;
  nextRun?: string;
  spent?: boolean;
}
type ServerStatus =
  | { switchedOn: false }
  | {
      switchedOn: true;
      state: AutomationState;
      pauseReason: PauseReason | null;
      payer: string | null;
      viewerIsPayer: boolean;
      nextRun: string | null;
      lastResult: 'complete' | 'error' | 'canceled' | null;
      lastFinishedAt: string | null;
      triggers: TriggerStatus[];
    };
type StatusState = {
  visible: boolean;
  status: ServerStatus | undefined;
};

const STATUS_PATH = '_automation-status';

function automationStatus(
  owner: object,
  args: () => {
    id: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    tools: Tools | undefined;
  },
) {
  return use(
    owner,
    resource(({ on }) => {
      let { id, realm, realmId, tools } = args();
      let state = new TrackedObject<StatusState>({
        visible: false,
        status: undefined,
      });
      let path = id && realmId ? pathInRealm(id, realmId) : undefined;
      if (!realm || path === undefined || !tools) {
        return state;
      }
      let url = `${realm}${STATUS_PATH}?automation=${encodeURIComponent(
        realm + path,
      )}`;
      let ended = false;
      let latest = 0;
      let read = async () => {
        let asked = ++latest;
        await Promise.resolve();
        if (ended || asked !== latest) {
          return;
        }
        try {
          let result = await new AuthedFetchTool(tools).execute({
            url,
            acceptHeader: 'application/json',
          });
          if (ended || asked !== latest) {
            return;
          }
          let status = result.ok
            ? (result.body?.data?.attributes as ServerStatus | undefined)
            : undefined;
          state.status = status;
          state.visible = Boolean(status);
        } catch {
          if (!ended && asked === latest) {
            state.status = undefined;
            state.visible = false;
          }
        }
      };
      read();
      // An edit to the card changes its triggers, so their runs left change
      // too.
      let unsubscribe = subscribeToRealm(realm, (event) => {
        if (
          event.eventName === 'index' &&
          'invalidations' in event &&
          event.invalidations.some(
            (u) => u === realm + path || u === `${realm}${path}.json`,
          )
        ) {
          read();
        }
      });
      on.cleanup(() => {
        ended = true;
        unsubscribe?.();
      });
      return state;
    }),
  );
}

type Tone = 'neutral' | 'success' | 'warning' | 'info';
interface StateLook {
  label: string;
  tone: Tone;
}

function stateLook(status: ServerStatus | undefined): StateLook | undefined {
  if (!status) {
    return undefined;
  }
  if (!status.switchedOn) {
    return { label: 'Off', tone: 'neutral' };
  }
  switch (status.state) {
    case 'active':
      return { label: 'On', tone: 'success' };
    case 'paused':
      return { label: 'Paused', tone: 'warning' };
    case 'waiting-for-credits':
      return { label: 'Waiting for credits', tone: 'warning' };
    case 'done':
      return { label: 'Done', tone: 'info' };
  }
}

// What the state means for the next run, as a sentence.
function stateSentence(status: ServerStatus): string {
  if (!status.switchedOn) {
    return 'Nobody has turned this automation on, so Boxel runs nothing. Anyone who can edit this workspace can turn the automation on, and that person then pays for every run.';
  }
  switch (status.state) {
    case 'active':
      return 'Boxel runs this automation each time a trigger fires and charges the payer for every run.';
    case 'waiting-for-credits':
      return 'The payer has no credits left, so Boxel holds every run. Boxel runs the automation again once the payer adds credits.';
    case 'done':
      return 'Every trigger has started as many runs as the trigger allows, so Boxel runs nothing more. Adding a trigger starts the automation again.';
    case 'paused':
      switch (status.pauseReason) {
        case 'realm-archived':
          return 'Someone archived this workspace, so Boxel paused the automation. Boxel runs nothing until someone restores the workspace and resumes the automation.';
        case 'payer-lost-access':
          return 'The payer can no longer edit this workspace, so Boxel paused the automation. Boxel runs nothing until someone who can edit this workspace resumes the automation and becomes the new payer.';
        case 'caps-raised':
          return 'An edit raised a limit above what the payer agreed to pay for, so Boxel paused the automation. Boxel runs nothing until someone who can edit this workspace resumes the automation and agrees to the new limits.';
        case 'batched-ai-enabled':
          return 'An edit turned on batched AI after the payer agreed to the limits, so Boxel paused the automation. Boxel runs nothing until someone who can edit this workspace resumes the automation and agrees to batched AI.';
        default:
          return 'Someone who can edit this workspace paused the automation, so Boxel runs nothing until someone resumes the automation.';
      }
  }
}

function payerText(status: ServerStatus): string {
  if (!status.switchedOn) {
    return 'Nobody yet';
  }
  if (status.viewerIsPayer) {
    return 'You';
  }
  return status.payer ?? 'A person who shares no workspace with you';
}

function lastRunText(status: ServerStatus): string | undefined {
  if (!status.switchedOn || !status.lastResult) {
    return undefined;
  }
  return status.lastResult === 'complete'
    ? 'Completed'
    : status.lastResult === 'error'
      ? 'Failed'
      : 'Canceled';
}

function tally(n: number): string {
  return n.toLocaleString('en-US');
}

// "26", "At least 10,000", "None", or undefined for a trigger with no bound.
function runsLeftText(trigger: TriggerStatus): string | undefined {
  if (trigger.runsLeft === undefined) {
    return undefined;
  }
  if (trigger.runsLeft === 0) {
    return 'None';
  }
  let left = tally(trigger.runsLeft);
  return trigger.runsLeftAtLeast ? `At least ${left}` : left;
}

interface StatusItem {
  label: string;
  value?: string;
  date?: string;
  // The zone a `date` reads in; the viewer's own when absent.
  timeZone?: string;
  look?: StateLook;
}

function statusItems(status: ServerStatus): StatusItem[] {
  let items: StatusItem[] = [
    { label: 'State', look: stateLook(status) },
    { label: 'Paid by', value: payerText(status) },
  ];
  if (status.switchedOn) {
    items.push(
      status.state === 'paused'
        ? { label: 'Next run', value: 'None while paused' }
        : status.nextRun
          ? { label: 'Next run', date: status.nextRun }
          : { label: 'Next run', value: 'None scheduled' },
    );
    let last = lastRunText(status);
    items.push(
      last && status.lastFinishedAt
        ? { label: `Last run: ${last}`, date: status.lastFinishedAt }
        : { label: 'Last run', value: 'No runs yet' },
    );
  }
  return items;
}

// A trigger's times read in the trigger's own zone, as the trigger's
// sentences do.
function triggerItems(
  trigger: TriggerStatus,
  timeZone: string | null | undefined,
): StatusItem[] {
  let zone = timeZone && isTimeZone(timeZone) ? timeZone : undefined;
  let items: StatusItem[] = [
    { label: 'Runs so far', value: tally(trigger.runs) },
  ];
  let left = runsLeftText(trigger);
  if (left) {
    items.push({ label: 'Runs left', value: left });
  }
  if (trigger.until) {
    items.push({
      label: 'Ends no later than',
      date: trigger.until,
      timeZone: zone,
    });
  }
  if (trigger.nextRun) {
    items.push({ label: 'Next run', date: trigger.nextRun, timeZone: zone });
  }
  return items;
}

function itemAt(items: StatusItem[], index: number): StatusItem | undefined {
  return items[index];
}

// A grid of status facts: plain values, times in the viewer's time zone, and
// the state as a chip.
class StatusFacts extends GlimmerComponent<{
  Args: { items: StatusItem[]; columns?: number; size?: 's' | 'm' };
}> {
  <template>
    <Descriptions
      @items={{@items}}
      @columns={{if @columns @columns 4}}
      @layout='vertical'
      @size={{if @size @size 'm'}}
    >
      <:value as |_item index|>
        {{#let (itemAt @items index) as |fact|}}
          {{#if fact.look}}
            <Chip
              @label={{fact.look.label}}
              @tone={{fact.look.tone}}
              data-test-automation-state={{fact.look.label}}
            />
          {{else if fact.date}}
            <FormatDate
              @date={{fact.date}}
              @dateStyle='medium'
              @timeStyle='short'
              @timeZone={{fact.timeZone}}
            />
          {{else}}
            {{fact.value}}
          {{/if}}
        {{/let}}
      </:value>
    </Descriptions>
  </template>
}

// The status of one trigger, by its label, for a direct writer.
function statusOfTrigger(
  status: ServerStatus | undefined,
  label: string | null | undefined,
): TriggerStatus | undefined {
  if (!status?.switchedOn || !label) {
    return undefined;
  }
  let trigger = status.triggers.find((t) => t.label === label);
  // A paused automation runs nothing, whatever its schedule says.
  return trigger && status.state === 'paused'
    ? { ...trigger, nextRun: undefined }
    : trigger;
}

// The linked script, read-only.
class ScriptView extends GlimmerComponent<{
  Args: {
    url: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    context: CardContext | undefined;
  };
}> {
  private script = scriptText(this, () => ({
    url: this.args.url,
    realm: this.args.realm,
    realmId: this.args.realmId,
    tools: toolsOf(this.args.context),
  }));
  get state() {
    return this.script.current;
  }
  get empty() {
    return this.state.text === '';
  }
  <template>
    {{#if this.state.failure}}
      <Callout @tone='warning' @title='The script can’t be shown'>
        {{this.state.failure}}
      </Callout>
    {{else if this.empty}}
      <EmptyState
        @size='s'
        @texture={{false}}
        @title='This script is empty'
        @message='Write the script in the edit view.'
        data-test-automation-script-empty
      />
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
  Args: {
    url: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    context: CardContext | undefined;
  };
}> {
  @tracked private draft: string | undefined;
  @tracked private saving = false;
  @tracked private saveFailure: string | undefined;
  private script = scriptText(this, () => ({
    url: this.args.url,
    realm: this.args.realm,
    realmId: this.args.realmId,
    tools: toolsOf(this.args.context),
  }));
  get state() {
    return this.script.current;
  }
  // The file has been read. Until then, or after a read that failed, the
  // editor is read-only and Save is off, so typing can't replace a script
  // nobody has seen.
  get loaded() {
    return this.state.text !== undefined;
  }
  get text() {
    return this.draft ?? this.state.text ?? '';
  }
  get dirty() {
    return (
      this.loaded && this.draft !== undefined && this.draft !== this.state.text
    );
  }
  setDraft = (code: string) => {
    this.draft = code;
  };
  save = async () => {
    let tools = toolsOf(this.args.context);
    if (!this.args.url || !tools || !this.loaded || !this.dirty) {
      return;
    }
    this.saving = true;
    this.saveFailure = undefined;
    let content = this.draft;
    try {
      await new WriteTextFileTool(tools).execute({
        path: this.args.url,
        content,
        overwrite: true,
      });
      // The file now holds what was saved; the realm's index event re-reads
      // the same text. Anything typed while the save was in flight stays a
      // draft on top of it.
      this.state.text = content;
      if (this.draft === content) {
        this.draft = undefined;
      }
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
        {{#if this.state.failure}}
          <Callout
            @tone='warning'
            @title='The script can’t be shown'
            data-test-automation-script-read-failure
          >
            {{this.state.failure}}
          </Callout>
        {{else if this.state.loading}}
          {{#unless this.loaded}}
            <LoadingState @label='Loading the script' />
          {{/unless}}
        {{/if}}
        <CodeEdit
          @code={{this.text}}
          @language='javascript'
          @label={{fileName @url}}
          @readOnly={{if this.loaded false true}}
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
              data-test-automation-script-discard
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
  // Leads the triggers: how many there are, and how they combine.
  get showsBatchedAI() {
    return (
      Boolean(this.args.model.batchedAI) && allowsAIRequests(this.args.model)
    );
  }
  get batchedAILabel() {
    let minutes =
      this.args.model.batchDeadlineMinutes ?? DEFAULT_BATCH_DEADLINE_MINUTES;
    return `Batched AI, waits up to ${waitLength(minutes)}`;
  }
  get triggerLead() {
    let n = this.args.model.triggers?.length ?? 0;
    return n === 1
      ? 'This automation has one trigger and runs each time that trigger fires.'
      : `This automation has ${n} triggers and runs each time any one of those triggers fires.`;
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
  get scriptURL() {
    return this.args.model.script?.id;
  }
  get realmHref() {
    return this.args.model[realmURL]?.href;
  }
  get realmId() {
    return instanceRealmId(this.args.model as Automation);
  }
  private server = automationStatus(this, () => ({
    id: this.args.model.id,
    realm: this.realmHref,
    realmId: this.realmId,
    tools: toolsOf(this.args.context),
  }));
  get status() {
    return this.server.current.visible ? this.server.current.status : undefined;
  }
  get look() {
    return stateLook(this.status);
  }
  get stateSentence() {
    return this.status ? stateSentence(this.status) : undefined;
  }
  get statusItems() {
    return this.status ? statusItems(this.status) : [];
  }
  timeZoneAt = (index: number) => this.args.model.triggers?.[index]?.timeZone;
  triggerStatusAt = (index: number) =>
    statusOfTrigger(this.status, this.args.model.triggers?.[index]?.label);
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
        <div class='automation__chips'>
          {{#if this.look}}
            <Chip
              @label={{this.look.label}}
              @tone={{this.look.tone}}
              data-test-automation-header-state={{this.look.label}}
            />
          {{/if}}
          {{#if this.showsBatchedAI}}
            <Chip @label={{this.batchedAILabel}} @tone='info' />
          {{/if}}
        </div>
      </header>

      {{#if this.status}}
        <PanelSection
          @title='Status'
          @collapsible={{false}}
          data-test-automation-status
        >
          <p class='automation__lead' data-test-automation-state-sentence>
            {{this.stateSentence}}
          </p>
          <StatusFacts @items={{this.statusItems}} />
        </PanelSection>
      {{else}}
        <Callout
          @tone='info'
          @title='Who turns this automation on, and who pays'
          data-test-automation-who-pays
        >
          This automation runs only after someone who can edit this workspace
          turns the automation on. That person pays for every run.
        </Callout>
      {{/if}}

      <PanelSection @title='Script' @collapsible={{false}}>
        <p class='automation__lead'>
          The script is what actually runs each time this automation runs.
        </p>
        {{#if this.scriptURL}}
          <ScriptView
            @url={{this.scriptURL}}
            @realm={{this.realmHref}}
            @realmId={{this.realmId}}
            @context={{@context}}
          />
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No script'
            @message='Link a script file, or create one, in the edit view. This automation won’t run without a script.'
          />
        {{/if}}
      </PanelSection>

      <PanelSection @title='When the automation runs' @collapsible={{false}}>
        {{#if @model.triggers.length}}
          <p class='automation__lead'>{{this.triggerLead}}</p>
          <div class='automation__rows'>
            {{#each @fields.triggers as |Trigger index|}}
              <div class='automation__row'>
                <Trigger />
                {{#let (this.triggerStatusAt index) as |progress|}}
                  {{#if progress}}
                    <div
                      class='automation__progress'
                      data-test-automation-trigger-progress={{progress.label}}
                    >
                      <StatusFacts
                        @items={{triggerItems progress (this.timeZoneAt index)}}
                        @size='s'
                      />
                    </div>
                  {{/if}}
                {{/let}}
              </div>
            {{/each}}
          </div>
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No triggers'
            @message='Add a schedule, a one-time run or a webhook to say when this automation runs.'
          />
        {{/if}}
      </PanelSection>

      <PanelSection @title='Limits' @collapsible={{false}}>
        <p class='automation__lead'>
          Boxel allows you to configure limits on what automations may do. Boxel
          stops any run that tries to exceed these limits.
        </p>
        <@fields.caps />
      </PanelSection>

      <PanelSection @title='Outside services' @collapsible={{false}}>
        {{#if this.hasOperations}}
          <p class='automation__lead'>
            The only outside calls the script may make. The script can’t reach
            any other service.
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
            @message='The script can’t contact any service outside this workspace.'
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
            @message='Values handed to the script at the start of each run.'
          />
        {{/if}}
      </PanelSection>

      {{! The script declares its milestones and reports each one as a run
          reaches it; they come from the runs, not from a field here. }}
      <PanelSection @title='Run milestones' @collapsible={{false}}>
        <EmptyState
          @size='s'
          @texture={{false}}
          @title='Shown from runs'
          @message='The steps the script reports as it runs will show here.'
        />
      </PanelSection>
    </article>
    <style scoped>
      .automation {
        display: grid;
        align-content: start;
        gap: var(--boxel-sp-lg);
        height: 100%;
        overflow-y: auto;
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
      .automation__eyebrow {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .automation__summary {
        margin-top: var(--boxel-sp-4xs);
        color: var(--muted-foreground);
        max-width: 60ch;
      }
      .automation__lead {
        margin: 0 0 var(--boxel-sp-sm);
        color: var(--foreground);
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
      .automation__progress {
        margin-top: var(--boxel-sp-xs);
        padding-inline-start: calc(2rem + var(--boxel-sp-sm));
      }
      .automation__chips {
        display: flex;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: var(--boxel-sp-2xs);
      }
      @container (inline-size < 40rem) {
        .automation {
          padding: var(--boxel-sp);
        }
      }
    </style>
  </template>
}

// What a new script starts with: a comment on what a script is, and one
// reported step, so it runs as soon as it's created.
const STARTER_SCRIPT = `/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation's \`realm\` object. Find cards with realm.cards.search, write
// files with realm.fs.writeText, and report each step with realm.activity.

await realm.activity({ message: 'Starting', current: 1, total: 1 });
`;

// A file path inside the workspace, without its extension: letters, digits,
// dashes, underscores and dots, with folders separated by slashes.
const SCRIPT_PATH =
  /^[A-Za-z0-9_-][A-Za-z0-9_.-]*(\/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*$/;

function slugOf(title: string | undefined) {
  return (title ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

// Creates a script file in the card's workspace, starting from a short
// outline, and links it to the card. Shaped like code mode's new-file
// dialog, with the workspace fixed: an automation's script must live in its
// own workspace.
class NewScript extends GlimmerComponent<{
  Args: {
    realm: string | undefined;
    context: CardContext | undefined;
    cardTitle: string | undefined;
    onCreated: (file: FileDef) => void;
  };
}> {
  @tracked open = false;
  @tracked name: string | undefined;
  @tracked creating = false;
  @tracked failure: string | undefined;
  get suggested() {
    return `scripts/${slugOf(this.args.cardTitle) || 'automation'}`;
  }
  get path() {
    return (this.name ?? this.suggested).trim().replace(/\.js$/, '');
  }
  get scriptFile() {
    return `${this.path}.js`;
  }
  get problem() {
    if (this.name === undefined) {
      return undefined;
    }
    if (!this.path) {
      return 'Enter a file name.';
    }
    if (!SCRIPT_PATH.test(this.path) || this.path.split('/').includes('..')) {
      return 'Use letters, numbers, dashes and underscores, with folders separated by a slash.';
    }
    return undefined;
  }
  get available() {
    return Boolean(this.args.realm && toolsOf(this.args.context));
  }
  get canCreate() {
    return !this.problem && Boolean(this.path) && !this.creating;
  }
  show = () => {
    this.name = undefined;
    this.failure = undefined;
    this.open = true;
  };
  close = () => {
    if (!this.creating) {
      this.open = false;
    }
  };
  setName = (value: string) => {
    this.name = value;
    this.failure = undefined;
  };
  create = async () => {
    let tools = toolsOf(this.args.context);
    let store = this.args.context?.store;
    if (!this.canCreate || !tools || !store || !this.args.realm) {
      return;
    }
    let url = new URL(`${this.path}.js`, this.args.realm).href;
    this.creating = true;
    this.failure = undefined;
    try {
      await new WriteTextFileTool(tools).execute({
        path: url,
        content: STARTER_SCRIPT,
      });
      let file = await store.get(url, { type: 'file-meta' });
      if (!(file instanceof FileDef)) {
        throw new Error('The script was created, but couldn’t be linked.');
      }
      this.args.onCreated(file);
      this.open = false;
    } catch (e) {
      let message = e instanceof Error ? e.message : String(e);
      this.failure = message.startsWith('File already exists')
        ? 'A file with that name already exists. Choose another name, or link the existing file with Link a file.'
        : message;
    } finally {
      this.creating = false;
    }
  };
  <template>
    {{#if this.available}}
      <Button
        @tone='neutral'
        @appearance='outlined'
        {{on 'click' this.show}}
        data-test-automation-new-script
      >New script</Button>
      <Dialog
        @open={{this.open}}
        @onClose={{this.close}}
        @size='m'
        @label='New script'
      >
        <:title>New script</:title>
        <:default>
          <div class='new-script'>
            <Field
              @label='File name'
              @hint='In this workspace. Use a slash for folders.'
              @error={{this.problem}}
              as |id|
            >
              <InputGroup
                @controlId={{id}}
                @value={{this.path}}
                @onInput={{this.setName}}
                data-test-automation-new-script-name
              >
                <:end>.js</:end>
              </InputGroup>
            </Field>
            {{#unless this.problem}}
              <div class='new-script__path'>
                <span>Will be created as</span>
                <Token @value={{this.scriptFile}} @wrap={{true}} />
                <span>The new script starts from a short outline and is linked
                  to this automation.</span>
              </div>
            {{/unless}}
            {{#if this.failure}}
              <div data-test-automation-new-script-failure>
                <Callout @tone='danger' @title='The script wasn’t created'>
                  {{this.failure}}
                </Callout>
              </div>
            {{/if}}
          </div>
        </:default>
        <:footer>
          <Button
            @tone='neutral'
            @appearance='outlined'
            @disabled={{this.creating}}
            {{on 'click' this.close}}
          >Cancel</Button>
          <Button
            @busy={{this.creating}}
            @disabled={{if this.canCreate false true}}
            {{on 'click' this.create}}
            data-test-automation-new-script-create
          >Create</Button>
        </:footer>
      </Dialog>
    {{/if}}
    <style scoped>
      .new-script {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .new-script__path {
        display: grid;
        gap: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// One outside call a card can make, as the chooser lists it.
interface OutsideCall {
  name: string;
  label: string;
  host: string;
}

// Adds an outside service by choosing, not typing: pick the card the script
// will call, then one of the outside calls its type declares. Saved as the
// card's type and the call's name, which is what the server checks a run
// against.
class AddOutsideService extends GlimmerComponent<{
  Args: {
    realm: string | undefined;
    realmId: string | undefined;
    context: CardContext | undefined;
    onAdd: (targetType: ResolvedCodeRef, operation: string) => void;
  };
}> {
  @tracked open = false;
  @tracked card: CardDef | undefined;
  @tracked calls: OutsideCall[] = [];
  @tracked picked: string | undefined;
  @tracked failure: string | undefined;
  get available() {
    return Boolean(this.args.context?.store);
  }
  get cardName() {
    return this.card?.cardTitle ?? 'This card';
  }
  get options() {
    return this.calls.map((call) => ({
      value: call.name,
      label: call.label,
      description: call.host,
    }));
  }
  // The script names the card by its path in the workspace.
  get scriptLine() {
    let id = this.card?.id ?? '';
    let realmId = this.args.realmId;
    let path = (realmId ? pathInRealm(id, realmId) : undefined) ?? id;
    return `realm.operations.invoke('${path}', '${this.picked ?? ''}', {})`;
  }
  choose = async () => {
    this.failure = undefined;
    // The dialog is modal, so the card chooser can't be used while it's
    // open. It reopens once a card is picked, or when the chooser is
    // cancelled from Choose another card.
    let wasOpen = this.open;
    this.open = false;
    let id = await chooseCard(
      { filter: { type: baseCardRef } },
      this.args.realm
        ? {
            consumingRealm: new URL(this.args.realm),
            preselectConsumingRealm: true,
          }
        : undefined,
    );
    if (!id) {
      this.open = wasOpen;
      return;
    }
    let card = await this.args.context?.store.get(id);
    if (!(card instanceof CardDef)) {
      this.failure = 'That card couldn’t be loaded.';
      this.open = true;
      return;
    }
    this.card = card;
    this.calls = Object.entries(getDeclaredOperations(card))
      .filter(([, declaration]) => declaration.base === 'callApi')
      .map(([name, declaration]) => {
        let url = (declaration as { url?: string }).url ?? '';
        let host = '';
        try {
          host = new URL(url).host;
        } catch {
          host = url;
        }
        return { name, label: declaration.label ?? name, host };
      });
    this.picked = this.calls[0]?.name;
    this.open = true;
  };
  pick = (name: string) => (this.picked = name);
  close = () => (this.open = false);
  add = () => {
    let ref = this.card ? identifyCard(this.card.constructor) : undefined;
    if (!ref || !('module' in ref) || !this.picked) {
      return;
    }
    this.args.onAdd(ref as ResolvedCodeRef, this.picked);
    this.open = false;
  };
  <template>
    {{#if this.available}}
      <div>
        <Button
          @icon={{PlusIcon}}
          @tone='neutral'
          @appearance='outlined'
          {{on 'click' this.choose}}
          data-test-automation-add-service
        >Add an outside service</Button>
      </div>
      <Dialog
        @open={{this.open}}
        @onClose={{this.close}}
        @size='m'
        @label='Add an outside service'
      >
        <:title>Add an outside service</:title>
        <:default>
          <div class='add-service'>
            {{#if this.failure}}
              <p class='add-service__note'>{{this.failure}}</p>
            {{else if this.calls.length}}
              <p class='add-service__note'>The outside calls
                {{this.cardName}}
                can make:</p>
              <RadioGroup
                @options={{this.options}}
                @value={{this.picked}}
                @label='Outside calls'
                @onValueChange={{this.pick}}
                data-test-automation-service-calls
              />
              <div class='add-service__script'>
                <span>The script makes this call with</span>
                <Token @value={{this.scriptLine}} @wrap={{true}} />
              </div>
            {{else}}
              <p class='add-service__note' data-test-automation-no-calls>
                {{this.cardName}}
                makes no outside calls. Choose a card whose type declares one,
                such as a card for a GitHub repository.
              </p>
            {{/if}}
          </div>
        </:default>
        <:footer>
          <Button
            @tone='neutral'
            @appearance='outlined'
            {{on 'click' this.choose}}
            data-test-automation-choose-another-service
          >Choose another card</Button>
          <Button
            @disabled={{if this.picked false true}}
            {{on 'click' this.add}}
            data-test-automation-add-service-confirm
          >Add</Button>
        </:footer>
      </Dialog>
    {{/if}}
    <style scoped>
      .add-service {
        display: grid;
        gap: var(--boxel-sp);
      }
      .add-service {
        min-inline-size: 0;
      }
      .add-service__script {
        display: grid;
        gap: var(--boxel-sp-4xs);
        justify-items: start;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

class Edit extends Component<typeof Automation> {
  // A new automation starts with every limit filled in, so it can run as soon
  // as it has a script and a trigger. Only a card with no limits at all is
  // filled; one that has any keeps them as they are.
  constructor(owner: Owner, args: Edit['args']) {
    super(owner, args);
    Promise.resolve().then(() => {
      let caps = this.args.model.caps as unknown as
        | Record<string, unknown>
        | undefined;
      if (!caps || Object.keys(CAP_DEFAULTS).some((k) => caps![k] != null)) {
        return;
      }
      for (let [key, value] of Object.entries(CAP_DEFAULTS)) {
        caps[key] = value;
      }
    });
  }
  // Batched AI only changes how AI requests are sent, so it means nothing
  // while the limits allow no AI request or no AI spending.
  get allowsAI() {
    return allowsAIRequests(this.args.model);
  }
  // Left switchable while on, so a card that allows no AI requests can still
  // turn it off.
  get batchedAILocked() {
    return !this.allowsAI && !this.args.model.batchedAI;
  }
  setBatchedAI = (value: boolean) => (this.args.model.batchedAI = value);
  setBatchDeadline = (value: number | null) =>
    (this.args.model.batchDeadlineMinutes = value ?? undefined);
  get batchDeadlineHint() {
    let minutes =
      this.args.model.batchDeadlineMinutes ?? DEFAULT_BATCH_DEADLINE_MINUTES;
    return `Waits ${waitLength(minutes)}${
      this.args.model.batchDeadlineMinutes == null ? ' when left empty' : ''
    }. Up to 1,440 (24 hours).`;
  }
  get batchDeadlineProblem() {
    let minutes = this.args.model.batchDeadlineMinutes;
    return typeof minutes === 'number' && minutes < 60
      ? 'Under an hour, more answers miss the deadline and cost full price.'
      : undefined;
  }
  get scriptURL() {
    return this.args.model.script?.id;
  }
  @tracked scriptIssue: ReturnType<typeof listIssue> | undefined;
  linkScript = (file: FileDef) => {
    this.scriptIssue = undefined;
    this.args.model.script = file;
  };
  // Each trigger's runs are counted under its label, so no two may share one.
  get triggersIssue() {
    let labels = (this.args.model.triggers ?? [])
      .map((t) => (t.label ?? '').trim())
      .filter(Boolean);
    let repeated = labels.find((label, i) => labels.indexOf(label) !== i);
    return repeated
      ? listIssue(
          'triggers',
          `Two triggers share the label “${repeated}”: each needs its own`,
        )
      : undefined;
  }
  get paramsIssue() {
    return paramsIssue(this.args.model.params, 'params');
  }
  addOperation = (targetType: ResolvedCodeRef, operation: string) => {
    this.args.model.operations = [
      ...(this.args.model.operations ?? []),
      new AutomationOperation({ targetType, operation }),
    ];
  };
  // Triggers and params are lists drawn here, with Pret UI's buttons, rather
  // than the base list editor's. Each change replaces the list so the card
  // notices it.
  addTrigger = () => {
    this.args.model.triggers = [
      ...(this.args.model.triggers ?? []),
      new AutomationTrigger(),
    ];
  };
  // Each row's controls are named for their row, so a screen reader's list
  // of buttons says which trigger, service or param each one removes. A row
  // with no name yet goes by its position.
  removeTriggerLabel = (index: number) => {
    let label = this.args.model.triggers?.[index]?.label?.trim();
    return `Remove this trigger, ${label || `trigger ${index + 1}`}`;
  };
  removeServiceLabel = (index: number) => {
    let operation = this.args.model.operations?.[index]?.operation;
    return operation
      ? `Remove the outside service ${operationTitle(operation)}`
      : `Remove outside service ${index + 1}`;
  };
  removeParamLabel = (index: number) => {
    let name = this.args.model.params?.[index]?.name?.trim();
    return name ? `Remove the param ${name}` : `Remove param ${index + 1}`;
  };
  paramInputLabel = (index: number, part: 'Name' | 'Value') =>
    `${part} of param ${index + 1}`;
  removeTrigger = (index: number) => {
    this.args.model.triggers = (this.args.model.triggers ?? []).filter(
      (_, i) => i !== index,
    );
  };
  // Each change replaces the list so the card notices it.
  setParam = (index: number, key: 'name' | 'value', value: string) => {
    let params = [...(this.args.model.params ?? [])];
    params[index][key] = value;
    this.args.model.params = params;
  };
  addParam = () => {
    this.args.model.params = [
      ...(this.args.model.params ?? []),
      new AutomationParam({ name: '', value: '' }),
    ];
  };
  removeParam = (index: number) => {
    this.args.model.params = (this.args.model.params ?? []).filter(
      (_, i) => i !== index,
    );
  };
  removeOperation = (index: number) => {
    this.args.model.operations = (this.args.model.operations ?? []).filter(
      (_, i) => i !== index,
    );
  };
  // A run reads its script from the automation's own workspace, so a file
  // from another one can't be linked.
  chooseScript = async () => {
    let file = await chooseFile();
    if (!file) {
      return;
    }
    let realmId = this.realmId;
    if (realmId && file.id && !pathInRealm(file.id, realmId)) {
      this.scriptIssue = listIssue(
        'script',
        'Choose a file in this workspace: an automation runs a script from its own workspace',
      );
      return;
    }
    this.linkScript(file);
  };
  get realmHref() {
    return this.args.model[realmURL]?.href;
  }
  get realmId() {
    return instanceRealmId(this.args.model as Automation);
  }
  <template>
    <div class='automation-edit'>
      <FormSection @title='About'>
        <@fields.cardInfo />
      </FormSection>
      <FormSection
        @title='Script'
        @description='The script is what actually runs each time this automation runs: a JavaScript file in this workspace.'
      >
        {{#if @model.script}}
          <@fields.script />
        {{else}}
          {{! Both ways to get a script, drawn alike: link a file that's
              already here, or create one from a short outline. }}
          <div class='automation-edit__script-pick'>
            <Button
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.chooseScript}}
              data-test-automation-link-script
            >Link a file</Button>
            <NewScript
              @realm={{this.realmHref}}
              @context={{@context}}
              @cardTitle={{@model.cardTitle}}
              @onCreated={{this.linkScript}}
            />
          </div>
          {{#if this.scriptIssue}}
            <FieldError
              @issue={{this.scriptIssue}}
              data-test-automation-script-problem
            />
          {{/if}}
        {{/if}}
        <ScriptEditor
          @url={{this.scriptURL}}
          @realm={{this.realmHref}}
          @realmId={{this.realmId}}
          @context={{@context}}
        />
      </FormSection>
      <FormSection
        @title='When the automation runs'
        @description='A trigger says when this automation runs: on a schedule, once at a set time, or when a delivery arrives at a webhook. The automation runs each time any one of the triggers fires.'
      >
        {{#each @fields.triggers as |Trigger index|}}
          <div
            class='automation-edit__item'
            data-test-automation-trigger={{index}}
          >
            <Trigger />
            <Button
              @icon={{TrashIcon}}
              @tone='neutral'
              @appearance='plain'
              @size='s'
              class='automation-edit__remove'
              aria-label={{this.removeTriggerLabel index}}
              {{on 'click' (fn this.removeTrigger index)}}
              data-test-automation-remove-trigger={{index}}
            >Remove this trigger</Button>
          </div>
        {{/each}}
        <div>
          <Button
            @icon={{PlusIcon}}
            @tone='neutral'
            @appearance='outlined'
            {{on 'click' this.addTrigger}}
            data-test-automation-add-trigger
          >Add a trigger</Button>
        </div>
        {{#if this.triggersIssue}}
          <FieldError
            @issue={{this.triggersIssue}}
            data-test-automation-triggers-problem
          />
        {{/if}}
      </FormSection>
      <FormSection
        @title='Limits'
        @description='Boxel allows you to configure limits on what automations may do. Boxel stops any run that tries to exceed these limits. Enter 0 to forbid something outright, such as AI requests. For credits, a daily or a monthly limit is enough.'
      >
        <@fields.caps />
      </FormSection>
      <FormSection
        @title='Batched AI'
        @description='Lets the script send AI requests that can wait as one batch, instead of one at a time.'
      >
        {{#unless this.allowsAI}}
          <p class='automation-edit__note'>This automation may not make AI
            requests. To use batched AI, set AI requests and AI spending under
            Limits above 0.</p>
        {{/unless}}
        <div class='automation-edit__batch-row'>
          <Field
            @label='Pay less, wait longer'
            @hint='About half price, but answers come back later'
            as |id|
          >
            <Switch
              @controlId={{id}}
              @checked={{@model.batchedAI}}
              @onCheckedChange={{this.setBatchedAI}}
              @disabled={{this.batchedAILocked}}
            />
          </Field>
          {{#if @model.batchedAI}}
            <Field
              @label='Deadline, in minutes'
              @hint={{this.batchDeadlineHint}}
              @error={{this.batchDeadlineProblem}}
              as |id|
            >
              <NumberInput
                @controlId={{id}}
                @invalid={{if this.batchDeadlineProblem true false}}
                @value={{@model.batchDeadlineMinutes}}
                @min={{1}}
                @max={{1440}}
                @precision={{0}}
                @placeholder='60'
                @onInput={{this.setBatchDeadline}}
              />
            </Field>
          {{/if}}
        </div>
        <Callout @tone='info' @title='When batched AI pays off'>
          <ul class='automation-edit__list'>
            <li>Batched AI answers cost about half as much, but come back later
              instead of right away. Most arrive within minutes, and nearly all
              within an hour.</li>
            <li>The deadline is how long a run waits for batched answers. An
              answer that isn’t back by then is requested again at full price,
              and the batch is still paid for.</li>
            <li>Set the deadline to an hour or more, so nearly every answer
              makes it. Use batched AI for work nobody is waiting on, such as a
              nightly report.</li>
          </ul>
        </Callout>

      </FormSection>
      <FormSection
        @title='Outside services'
        @description='The only outside calls the script may make. Each one is a call a card’s type declares, such as listing a GitHub repository’s open issues.'
      >
        {{#if @model.operations.length}}
          <div class='automation-edit__operations'>
            {{#each @fields.operations as |Operation index|}}
              <div class='automation-edit__operation'>
                <Operation @format='embedded' />
                <IconButton
                  @label={{this.removeServiceLabel index}}
                  @icon={{TrashIcon}}
                  @tone='neutral'
                  @appearance='plain'
                  @size='s'
                  {{on 'click' (fn this.removeOperation index)}}
                  data-test-automation-remove-service
                />
              </div>
            {{/each}}
          </div>
        {{/if}}
        <AddOutsideService
          @realm={{this.realmHref}}
          @realmId={{this.realmId}}
          @context={{@context}}
          @onAdd={{this.addOperation}}
        />
      </FormSection>
      <FormSection
        @title='Params'
        @description='Values handed to the script at the start of each run'
      >
        {{#if @model.params.length}}
          <div class='automation-edit__params'>
            <span
              class='automation-edit__param-head'
              aria-hidden='true'
            >Name</span>
            <span
              class='automation-edit__param-head'
              aria-hidden='true'
            >Value</span>
            <span></span>
            {{#each @model.params as |param index|}}
              <div
                class='automation-edit__param'
                data-test-automation-param={{index}}
              >
                <Input
                  @value={{param.name}}
                  aria-label={{this.paramInputLabel index 'Name'}}
                  @onInput={{fn this.setParam index 'name'}}
                />
                <Input
                  @value={{param.value}}
                  aria-label={{this.paramInputLabel index 'Value'}}
                  @onInput={{fn this.setParam index 'value'}}
                />
                <IconButton
                  @label={{this.removeParamLabel index}}
                  @icon={{TrashIcon}}
                  @tone='neutral'
                  @appearance='plain'
                  @size='s'
                  {{on 'click' (fn this.removeParam index)}}
                  data-test-automation-remove-param={{index}}
                />
              </div>
            {{/each}}
          </div>
        {{/if}}
        <div>
          <Button
            @icon={{PlusIcon}}
            @tone='neutral'
            @appearance='outlined'
            {{on 'click' this.addParam}}
            data-test-automation-add-param
          >Add a param</Button>
        </div>
        {{#if this.paramsIssue}}
          <FieldError
            @issue={{this.paramsIssue}}
            data-test-automation-params-problem
          />
        {{/if}}
      </FormSection>
    </div>
    <style scoped>
      /* The switch and its deadline sit side by side, and stack when the
         section is too narrow for both. */
      .automation-edit__batch-row {
        display: flex;
        flex-wrap: wrap;
        align-items: flex-start;
        gap: var(--boxel-sp) var(--boxel-sp-2xl);
      }
      .automation-edit__batch-row > :deep(*) {
        flex: 0 1 20rem;
      }
      /* each trigger is a panel of its own, with its remove button at the
         top right */
      .automation-edit__item {
        position: relative;
        display: grid;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp);
        border-radius: var(--radius);
        background-color: var(--muted);
      }
      .automation-edit__remove {
        justify-self: end;
      }
      /* One grid for the whole list: Name and Value head it once, and each
         row's inputs and remove button sit centered on one line. */
      .automation-edit__params {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 2fr) auto;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .automation-edit__param {
        display: contents;
      }
      .automation-edit__param-head {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .automation-edit__operations {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      /* Each service is a full-width row, shaded like a trigger's panel, with
         its remove button at the right edge, in line with the params'. */
      .automation-edit__operation {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-xs)
          var(--boxel-sp-sm);
        border-radius: var(--radius);
        background-color: var(--muted);
      }
      .automation-edit__operation > :first-child {
        min-width: 0;
      }
      .automation-edit__script-pick {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .automation-edit__note {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .automation-edit__list {
        display: grid;
        gap: var(--boxel-sp-2xs);
        margin: 0;
        padding-inline-start: var(--boxel-sp);
      }
      .automation-edit {
        --pretui-section-gap: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp-2xl);
        padding: var(--boxel-sp-xl);
      }
      /* A legend sits outside its fieldset's grid, so the section gap never
         reaches the line under it; give what follows the rule room. */
      .automation-edit :deep(.pretui-formsection-legend) {
        margin-bottom: var(--boxel-sp-sm);
      }
    </style>
  </template>
}

// When a trigger fires, as a short phrase for the fitted view.
function triggerPhrase(trigger: AutomationTrigger): string {
  let { kind, expression, date, time, webhookPath } = trigger;
  if (kind === 'cron') {
    return describeCron(expression)?.summary ?? 'On a schedule';
  }
  if (kind === 'once') {
    let when = [
      time ? `at ${readableTime(time)}` : undefined,
      readableDate(date) ? `on ${readableDate(date)}` : undefined,
    ]
      .filter(Boolean)
      .join(' ');
    return when ? `Once, ${when}` : 'Once';
  }
  return webhookPath
    ? `When a delivery arrives at ${webhookPath}`
    : 'When a delivery arrives';
}

// The server's view of an automation, for a view that shows only its state.
class WithStatus extends Component<typeof Automation> {
  private server = automationStatus(this, () => ({
    id: this.args.model.id,
    realm: this.args.model[realmURL]?.href,
    realmId: instanceRealmId(this.args.model as Automation),
    tools: toolsOf(this.args.context),
  }));
  get look() {
    return this.server.current.visible
      ? stateLook(this.server.current.status)
      : undefined;
  }
}

class Fitted extends WithStatus {
  get triggers() {
    return this.args.model.triggers ?? [];
  }
  get when() {
    let first = this.triggers[0];
    return first ? triggerPhrase(first) : 'No triggers yet';
  }
  get moreTriggers() {
    let more = this.triggers.length - 1;
    return more > 0
      ? `Plus ${more} more trigger${more === 1 ? '' : 's'}`
      : undefined;
  }
  get firstKind() {
    return this.triggers[0]?.kind;
  }
  get hasScript() {
    return Boolean(this.args.model.script);
  }
  get showsBatchedAI() {
    return (
      Boolean(this.args.model.batchedAI) && allowsAIRequests(this.args.model)
    );
  }
  <template>
    <FittedCard
      class='automation-fitted'
      @titleTag='h3'
      data-test-automation-fitted
    >
      <:placeholder>
        <span class='automation-fitted__icon' aria-hidden='true'>
          <CalendarClockIcon width='24' height='24' />
        </span>
      </:placeholder>
      <:eyebrow>Automation</:eyebrow>
      <:title>{{@model.cardTitle}}</:title>
      <:subtitle>
        <span class='automation-fitted__when' data-test-automation-fitted-when>
          {{#if (eq this.firstKind 'cron')}}
            <RepeatIcon width='14' height='14' aria-hidden='true' />
          {{else if (eq this.firstKind 'once')}}
            <CalendarCheckIcon width='14' height='14' aria-hidden='true' />
          {{else if this.firstKind}}
            <ZapIcon width='14' height='14' aria-hidden='true' />
          {{/if}}
          <span>{{this.when}}</span>
        </span>
      </:subtitle>
      <:meta>
        <div class='automation-fitted__meta'>
          {{#if this.moreTriggers}}
            <p
              class='automation-fitted__more'
              data-test-automation-fitted-more
            >{{this.moreTriggers}}</p>
          {{/if}}
          {{#if @model.cardDescription}}
            <p class='automation-fitted__summary'>{{@model.cardDescription}}</p>
          {{/if}}
        </div>
      </:meta>
      <:footer>
        {{#if this.look}}
          <Chip
            @label={{this.look.label}}
            @tone={{this.look.tone}}
            data-test-automation-fitted-state={{this.look.label}}
          />
        {{/if}}
        {{#unless this.hasScript}}
          <Chip
            @label='No script yet'
            @tone='warning'
            data-test-automation-fitted-no-script
          />
        {{/unless}}
        {{#if this.showsBatchedAI}}
          <Chip
            @label='Batched AI'
            @tone='info'
            class='automation-fitted__batched'
            data-test-automation-fitted-batched-ai
          />
        {{/if}}
      </:footer>
    </FittedCard>
    <style scoped>
      .automation-fitted {
        --fc-title-font-size: var(--boxel-font-size-sm);
        --fc-subtitle-font-size: var(--boxel-font-size-xs);
        --fc-subtitle-line-clamp: 2;
        --fc-footer-justify: flex-start;
      }
      .automation-fitted__icon {
        display: grid;
        place-items: center;
        width: 2.5rem;
        height: 2.5rem;
        border-radius: var(--radius);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .automation-fitted__when {
        display: inline-flex;
        align-items: flex-start;
        gap: var(--boxel-sp-5xs);
      }
      .automation-fitted__meta {
        display: grid;
        gap: var(--boxel-sp-5xs);
        min-width: 0;
      }
      /* Too narrow for two chips: the missing script matters more. */
      @container fitted-card (max-width: 180px) or ((max-width: 260px) and (max-height: 180px)) {
        .automation-fitted__batched {
          display: none;
        }
      }
      .automation-fitted__summary {
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 3;
        overflow: hidden;
        color: var(--muted-foreground);
      }
      @container fitted-card (max-height: 199px) {
        .automation-fitted__summary {
          display: none;
        }
      }
      .automation-fitted__when > svg {
        flex-shrink: 0;
        margin-top: 0.1em;
      }
    </style>
  </template>
}

// One line per trigger, in words, with the automation's state for a direct
// writer.
class Embedded extends WithStatus {
  get triggers() {
    return (this.args.model.triggers ?? []).map((trigger) => ({
      kind: trigger.kind,
      phrase: triggerPhrase(trigger),
    }));
  }
  <template>
    <div class='automation-embedded' data-test-automation-embedded>
      <Item
        @size='s'
        @alignStart={{true}}
        @title={{@model.cardTitle}}
        @description={{@model.cardDescription}}
      >
        <:leading>
          <span class='automation-embedded__icon' aria-hidden='true'>
            <CalendarClockIcon width='20' height='20' />
          </span>
        </:leading>
        <:trailing>
          {{#if this.look}}
            <Chip
              @label={{this.look.label}}
              @tone={{this.look.tone}}
              data-test-automation-embedded-state={{this.look.label}}
            />
          {{/if}}
        </:trailing>
      </Item>
      {{#if this.triggers.length}}
        <ul class='automation-embedded__triggers'>
          {{#each this.triggers as |trigger|}}
            <li data-test-automation-embedded-trigger>
              {{#if (eq trigger.kind 'cron')}}
                <RepeatIcon width='14' height='14' aria-hidden='true' />
              {{else if (eq trigger.kind 'once')}}
                <CalendarCheckIcon width='14' height='14' aria-hidden='true' />
              {{else}}
                <ZapIcon width='14' height='14' aria-hidden='true' />
              {{/if}}
              <span>{{trigger.phrase}}</span>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <EmptyState
          @size='s'
          @texture={{false}}
          @title='No triggers'
          @message='Add a schedule, a one-time run or a webhook in the edit view.'
        />
      {{/if}}
    </div>
    <style scoped>
      .automation-embedded {
        display: grid;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
      }
      .automation-embedded__icon {
        display: grid;
        place-items: center;
        width: 2.25rem;
        height: 2.25rem;
        border-radius: var(--radius);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .automation-embedded__triggers {
        display: grid;
        gap: var(--boxel-sp-4xs);
        margin: 0;
        padding: 0;
        list-style: none;
        font-size: var(--boxel-font-size-xs);
        line-height: var(--boxel-line-height-xs);
        color: var(--muted-foreground);
      }
      .automation-embedded__triggers li {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-2xs);
      }
      .automation-embedded__triggers svg {
        flex-shrink: 0;
        margin-top: 0.2em;
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
  // Lets a run hand its AI requests to a provider's batch API, ending the run
  // and continuing in a follow-up run when the batch finishes. Off unless set.
  @field batchedAI = contains(BooleanField);
  // With batchedAI on: how many minutes a batch may take, at most 1440 (24
  // hours) and 60 when unset. Answers not back by then are requested again at
  // the normal price.
  @field batchDeadlineMinutes = contains(NumberField);

  // A run acts with its payer's authority, and its payer administers the
  // realm. So no policy grant may change this card's definition: each write
  // below is open only to a caller the realm's own permissions let write.
  // These are the writes a card carries, declared in their built-in form so
  // they can be marked; each does what it does on any other card. `create`
  // isn't marked, since a new automation runs nothing until a direct writer
  // turns it on. The linked script file is a separate file, which these marks
  // don't cover.
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
  static embedded = Embedded;
  static fitted = Fitted;
  static edit = Edit;
}
