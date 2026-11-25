import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { cached, tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { consume } from 'ember-provide-consume-context';
import { resource, use } from 'ember-resources';
import { TrackedObject, TrackedSet } from 'tracked-built-ins';
import { markDefinition } from '@cardstack/base/mark-definition';
import { nowDate } from '@cardstack/base/helpers/clock';
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
import AutomationRequestTool from '@cardstack/boxel-host/tools/automation-request';
import OpenSecureWindowTool from '@cardstack/boxel-host/tools/open-secure-window';
import ReadAutomationRunTool from '@cardstack/boxel-host/tools/read-automation-run';
import ReadSourceTool from '@cardstack/boxel-host/tools/read-source';
import WriteTextFileTool from '@cardstack/boxel-host/tools/write-text-file';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { List } from '@cardstack/pretui/components/list';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Pagination } from '@cardstack/pretui/components/pagination';
import { Callout } from '@cardstack/pretui/components/callout';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { RelativeTime } from '@cardstack/pretui/components/relative-time';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
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
import { Select } from '@cardstack/pretui/components/select';
import { Switch } from '@cardstack/pretui/components/switch';
import { Stack } from '@cardstack/pretui/components/stack';
import {
  Timeline,
  type TimelineEvent,
} from '@cardstack/pretui/components/timeline';
import {
  StatementTable,
  type StatementColumn,
  type StatementRow,
} from '@cardstack/pretui/components/statement-table';
import { Table } from '@cardstack/pretui/components/table';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { TimeInput } from '@cardstack/pretui/components/time-input';
import { Token } from '@cardstack/pretui/components/token';
import { and, bool, eq, gt, or } from '@cardstack/pretui/helpers';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';
import CalendarCheckIcon from '@cardstack/boxel-icons/calendar-check';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';
import CircleDashedIcon from '@cardstack/boxel-icons/circle-dashed';
import CirclePauseIcon from '@cardstack/boxel-icons/circle-pause';
import CircleXIcon from '@cardstack/boxel-icons/circle-x';
import HourglassIcon from '@cardstack/boxel-icons/hourglass';
import OctagonAlertIcon from '@cardstack/boxel-icons/octagon-alert';
import PlugIcon from '@cardstack/boxel-icons/plug';
import PlusIcon from '@cardstack/boxel-icons/plus';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import TrashIcon from '@cardstack/boxel-icons/trash-2';
import ZapIcon from '@cardstack/boxel-icons/zap';
import LayoutListIcon from '@cardstack/boxel-icons/layout-list';
import {
  AutomationsConsoleContextName,
  showAutomationInConsole,
} from '@cardstack/base/realm-automations';
import { describeCron } from '@cardstack/catalog/automation/describe-cron';
import { cronTriggerProblem } from '@cardstack/runtime-common/automation-cron-rule';
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
  seconds: 1200,
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
// - `webhook`: a delivery to the incoming webhook at `webhookPath`, one the
//   realm can use: a webhook a direct writer of the realm made. The editor
//   picks it from the realm's `_automation-webhooks` list, and the server
//   refuses any other webhook when someone turns the automation on.
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
    // expression is checked in the trigger's time zone with the rule the
    // server reads the declaration with, so an expression accepted here is
    // one the server accepts. The server checks more of the card when someone
    // turns the automation on; the rest of these catch the common slips early.
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
          : cronTriggerProblem(m.expression!, m.timeZone ?? undefined)?.message,
        timeZone: blank(m.timeZone)
          ? 'Required: pick a time zone'
          : isTimeZone(m.timeZone!)
            ? undefined
            : 'Not a time zone; pick one from the list',
        webhookPath: blank(m.webhookPath)
          ? !this.webhooks.list
            ? 'Required: enter one of this workspace’s incoming webhooks'
            : this.webhooks.list.length
              ? 'Required: pick one of this workspace’s incoming webhooks'
              : undefined
          : this.webhooks.list &&
              !this.webhooks.list.some(
                (webhook) => webhook.webhookPath === m.webhookPath,
              )
            ? 'Pick one of this workspace’s incoming webhooks: Boxel turns the automation on only with a webhook that a realm administrator made'
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
    // The incoming webhooks the trigger may name, read only while the trigger
    // is a webhook trigger.
    private webhookList = automationWebhooks(this, () => ({
      wanted: this.kind === 'webhook',
      realmId: instanceRealmId(this.args.model as unknown as CardDef),
      tools: toolsOf(this.args.context),
    }));
    get webhooks(): WebhooksState {
      return this.webhookList.current;
    }
    // Whether the route answered, so the editor picks from its list. An
    // empty list counts: the editor then says the workspace has no webhook.
    get hasWebhookList() {
      return this.webhooks.list !== undefined;
    }
    // Each webhook as a choice. A path the card already holds that the list
    // lacks stays a choice too, so the picker shows the current value and
    // the problem under the field says why it can't stay.
    get webhookOptions() {
      let list = this.webhooks.list ?? [];
      let options = list.map((webhook) => ({
        value: webhook.webhookPath,
        label: webhook.webhookPath,
        meta: `${webhook.owner} made this webhook`,
      }));
      let current = this.args.model.webhookPath;
      if (current && !list.some((webhook) => webhook.webhookPath === current)) {
        options.unshift({
          value: current,
          label: current,
          meta: 'Not one of this workspace’s webhooks',
        });
      }
      return options;
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
        {{else if this.hasWebhookList}}
          <Field
            @label='Webhook'
            @hint='Each delivery to this webhook starts a run. The list shows every webhook that a realm administrator made.'
            @error={{this.problems.webhookPath}}
            @required={{true}}
            as |id|
          >
            {{#if this.webhookOptions.length}}
              <Select
                @controlId={{id}}
                @options={{this.webhookOptions}}
                @value={{@model.webhookPath}}
                @placeholder='Pick a webhook'
                @searchEnabled={{true}}
                @onValueChange={{fn this.setText 'webhookPath'}}
                data-test-automation-webhook-picker
              />
            {{else}}
              <EmptyState
                @size='s'
                @texture={{false}}
                @title='No incoming webhooks'
                @message='No realm administrator has made an incoming webhook. Once a realm administrator makes a webhook, reopen the editor to pick the webhook.'
                data-test-automation-webhook-picker-empty
              />
            {{/if}}
          </Field>
        {{else if this.webhooks.loading}}
          <LoadingState
            @label='Reading this workspace’s incoming webhooks'
            data-test-automation-webhook-picker-loading
          />
        {{else}}
          {{! Without the list (no way to ask, a failed request, or a viewer
              who isn't a direct writer), the path is typed; the server
              still checks the path on switch-on. }}
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
// realm's `_automation-status` route shows this only to the realm's direct
// writers. Any other viewer the realm admits is told they aren't a direct
// writer (`meta.directWriter: false`): a viewer the realm's permissions let
// read, and a viewer the realm hands to its policy, whom a grant may admit to
// the card but never to the server's state. Then `visible` stays false and the
// views show the card's own fields alone, as they do when the route can't be
// asked or the request fails.
type AutomationState =
  | 'active'
  | 'paused'
  | 'waiting-for-credits'
  | 'waiting-for-key-approval'
  | 'done';
type PauseReason =
  | 'requested'
  | 'realm-archived'
  | 'payer-lost-access'
  | 'caps-raised'
  | 'batched-ai-enabled'
  | 'webhook-changed'
  | 'webhook-owner-lost-access'
  | 'repeated-failures'
  | 'invalid-declaration';
// One thing the server found wrong when the server read the card as an
// automation: a `path` into the card (`triggers.0.expression`, `caps.writes`)
// and a message for a person.
interface DeclarationProblem {
  code: string;
  path: string;
  message: string;
}
interface TriggerStatus {
  label: string;
  runs: number;
  runsLeft?: number;
  runsLeftAtLeast?: boolean;
  until?: string;
  nextRun?: string;
  spent?: boolean;
}
// The automation's last run that started and has ended, with the milestones
// its script reported: the script declares them with
// `realm.progress.plan([...])` and marks each with
// `realm.progress.milestone(name)`, so they come from the run, never from a
// field on the card.
interface RunMilestone {
  name: string;
  planned: boolean;
  startedAt: string;
  endedAt: string | null;
  ms: number;
  // The notable tasks the script reported inside the milestone with
  // `realm.progress.task(text)`, in order.
  tasks?: RunTask[];
}
interface RunTask {
  text: string;
  at: string;
}
interface LastRun {
  runId: string;
  // A running run names the milestone it is in.
  current?: string | null;
  state: 'pending' | 'running' | 'complete' | 'error' | 'canceled';
  startedAt: string | null;
  finishedAt: string | null;
  plan: string[];
  milestones: RunMilestone[];
  ahead: string[];
  failedIn: string | null;
  dropped: number;
  // Tasks the script reported that the run didn't record: past the most a
  // run records, or inside a milestone the run didn't record.
  tasksDropped?: number;
}
interface RunFailure {
  runId: string;
  reason: string | null;
  message: string | null;
  finishedAt: string;
}
// What the automation's last run used of each per-run limit.
type RunUsage = {
  callApiCalls: number;
  responseBytes: number;
  resolveCalls: number;
  aiCredits: number;
  writes: number;
  seconds: number | null;
};
type ServerStatus =
  | {
      switchedOn: false;
      lastRun?: LastRun | null;
      currentRun?: LastRun | null;
      lastRunUsage?: RunUsage | null;
    }
  | {
      switchedOn: true;
      lastRun?: LastRun | null;
      currentRun?: LastRun | null;
      state: AutomationState;
      pauseReason: PauseReason | null;
      // What the server found wrong with the card, when the pause reason is
      // `invalid-declaration`.
      pauseProblems?: DeclarationProblem[] | null;
      payer: string | null;
      viewerIsPayer: boolean;
      nextRun: string | null;
      lastResult: 'complete' | 'error' | 'canceled' | null;
      lastFinishedAt: string | null;
      // The automation's failure streak: how many of its scheduled runs
      // failed in a row since its last complete one, counting from its
      // switch-on or latest resume, and the latest of them. Either may be
      // absent.
      failuresInARow?: number;
      lastFailure?: RunFailure | null;
      // The monthly credit cap the payer agreed to, or null when there is
      // none, and what the automation was charged this UTC month. Absent
      // from a server that doesn't report them.
      monthlyCredits?: number | null;
      spentThisMonth?: number;
      // The daily credit cap the payer agreed to, or null when there is none,
      // and what the automation was charged this UTC day.
      dailyCredits?: number | null;
      spentToday?: number;
      lastRunUsage?: RunUsage | null;
      triggers: TriggerStatus[];
      // Each declared operation's key approvals, read only by a view that
      // asks for them (`keyApprovals=true`). Absent when the realm can't
      // check them.
      keyApprovals?: KeyApprovalStatus;
    };
// Where one credential slot of an operation stands: its key's owner
// approved the automation's use of the key (`approved`), hasn't yet
// (`waiting`), or the slot can't be served at all for now: no share in the
// realm (`no-share`), a request changed since its owner approved the request
// (`needs-reapproval`), a suspended share (`share-suspended`), or a key the
// service refused (`key-rejected`).
type SlotApprovalState =
  | 'approved'
  | 'waiting'
  | 'no-share'
  | 'needs-reapproval'
  | 'share-suspended'
  | 'key-rejected';
// The secure window page that fixes a slot, when the viewer can fix it.
type SlotApprovalFix =
  | 'approve'
  | 'review-changes'
  | 'replace-key'
  | 'swap-key'
  | 'share-key';
interface SlotApproval {
  slot: string;
  kind: 'userKey' | 'apiKey';
  state: SlotApprovalState;
  // The share the slot sends. A suspended share says why: a realm
  // administrator suspended the share (`suspended-by-writer`, with who in
  // `suspendedBy` when the viewer may see them, or `suspendedByViewer`), the
  // key's owner is no longer a realm administrator (`owner-lost-write`), or
  // the key's owner deleted the key (`key-deleted`).
  share?: {
    id: string;
    label: string;
    suspensionReason?: string;
    suspendedBy?: string | null;
    suspendedByViewer?: boolean;
  };
  // The personal key the slot sends, named only to the key's owner.
  key?: { name: string };
  viewerIsKeyOwner: boolean;
  // The key owner's Matrix id, only when ADR 011 lets the viewer see them;
  // null otherwise.
  keyOwner: string | null;
  approvedAt?: string;
  fix?: SlotApprovalFix;
  // Set when the viewer can't fix the slot: the key's owner fixes it.
  actor?: 'key-owner';
}
interface OperationApproval {
  operation: string;
  targetType: { module: string; name: string };
  state: 'approved' | 'missing' | 'unavailable';
  refusal?: { code: string; detail: string };
  slots: SlotApproval[];
}
interface KeyApprovalStatus {
  approved: boolean;
  operations: OperationApproval[];
}
// A limit the automation is near or at.
interface LimitNear {
  name: string;
  // The limit in a word or two, for a chip.
  short: string;
  reached: boolean;
  share: number;
  text: string;
}
// The share of a limit from which the card says the automation is near it.
const LIMIT_NEAR_SHARE = 0.8;
// A byte count as people read it: "4.6 MB".
const oneDecimal = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 });
function bytes(n: number): string {
  if (n >= 1_000_000) {
    return `${oneDecimal.format(n / 1_000_000)} MB`;
  }
  if (n >= 1_000) {
    return `${oneDecimal.format(n / 1_000)} KB`;
  }
  return `${tally(n)} bytes`;
}
type StatusState = {
  // Whether the view knows what to show: the route answered, or the view
  // has no way to ask (no tools, as in a prerender).
  known: boolean;
  visible: boolean;
  status: ServerStatus | undefined;
};

const STATUS_PATH = '_automation-status';

// An incoming webhook an automation may name, as the realm's
// `_automation-webhooks` route lists it: one that a direct writer of the
// realm made. The route lists webhooks only to the realm's direct writers.
// Any other viewer the realm admits, whether the realm's permissions let them
// read or the realm hands them to its policy, is told they aren't a direct
// writer (`meta.directWriter: false`). Then the editor takes a typed path, as
// it does when the route can't be asked or the request fails.
interface AutomationWebhook {
  webhookPath: string;
  owner: string;
}
type WebhooksState = {
  loading: boolean;
  // Undefined until the route answers, and when the route can't be asked,
  // fails, or says the viewer isn't a direct writer: the editor then takes a
  // typed path.
  list: AutomationWebhook[] | undefined;
};
const WEBHOOKS_PATH = '_automation-webhooks';

function automationWebhooks(
  owner: object,
  args: () => {
    // Whether the trigger is a webhook trigger: the list is read only then.
    wanted: boolean;
    realmId: string | undefined;
    tools: Tools | undefined;
  },
) {
  // The resource runs again on every edit to the trigger, since the trigger
  // is one tracked field of its card. The list is read once per realm and
  // kept across those runs, so an edit never asks the route again, and a
  // list already read stays while the author edits.
  let kept:
    | { realmId: string | undefined; state: WebhooksState; asked: boolean }
    | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { wanted, realmId, tools } = args();
      if (!kept || kept.realmId !== realmId) {
        kept = {
          realmId,
          asked: false,
          state: new TrackedObject<WebhooksState>({
            loading: false,
            list: undefined,
          }),
        };
      }
      let current = kept;
      let state = current.state;
      if (!wanted || !realmId || !tools || current.asked) {
        return state;
      }
      current.asked = true;
      let ended = false;
      on.cleanup(() => {
        ended = true;
      });
      (async () => {
        // Not while the resource runs: the page may have read `loading`
        // already in this render.
        await Promise.resolve();
        state.loading = true;
        try {
          // The realm identifier may be in prefix form; the tool resolves it
          // to the realm's URL.
          let result = await new AuthedFetchTool(tools).execute({
            url: `${realmId}${WEBHOOKS_PATH}`,
            acceptHeader: 'application/json',
          });
          if (result.ok && result.body?.meta?.directWriter !== false) {
            state.list = (
              (result.body?.data ?? []) as { attributes: AutomationWebhook }[]
            ).map(({ attributes }) => attributes);
          }
        } catch {
          // The editor takes a typed path while there is no list.
        } finally {
          state.loading = false;
          if (ended && !state.list) {
            // Torn down before the answer: a later run may ask again.
            current.asked = false;
          }
        }
      })();
      return state;
    }),
  );
}

function automationStatus(
  owner: object,
  args: () => {
    id: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    tools: Tools | undefined;
    // Ask for the automation's key approvals too. Checking them looks up
    // each declared operation, so only the isolated view, which shows them,
    // asks.
    keyApprovals?: boolean;
  },
) {
  let kept: { url: string | undefined; state: StatusState } | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { id, realm, realmId, tools, keyApprovals } = args();
      let path = id && realmId ? pathInRealm(id, realmId) : undefined;
      let url =
        realm && path !== undefined
          ? `${realm}${STATUS_PATH}?automation=${encodeURIComponent(
              realm + path,
            )}`
          : undefined;
      // The answer lives across the resource's runs while the card is the
      // same, so a run never swaps the status back to the reader's callout
      // while it asks again.
      if (!kept || kept.url !== url) {
        kept = {
          url,
          state: new TrackedObject<StatusState>({
            known: false,
            visible: false,
            status: undefined,
          }),
        };
      }
      let state = kept.state;
      if (!realm || path === undefined || !url || !tools) {
        state.known = true;
        return state;
      }
      let ended = false;
      let latest = 0;
      // A run moving (a `job` event) changes no key approval, so that read
      // skips the check, which looks up every declared operation, and keeps
      // the approvals the last read answered.
      let read = async ({ checkKeys = true }: { checkKeys?: boolean } = {}) => {
        let asked = ++latest;
        await Promise.resolve();
        if (ended || asked !== latest) {
          return;
        }
        try {
          let result = await new AuthedFetchTool(tools).execute({
            url: keyApprovals && checkKeys ? `${url}&keyApprovals=true` : url,
            acceptHeader: 'application/json',
          });
          if (ended || asked !== latest) {
            return;
          }
          let status =
            result.ok && result.body?.meta?.directWriter !== false
              ? (result.body?.data?.attributes as ServerStatus | undefined)
              : undefined;
          let kept = state.status?.switchedOn && state.status.keyApprovals;
          if (
            keyApprovals &&
            !checkKeys &&
            kept &&
            status?.switchedOn &&
            !status.keyApprovals
          ) {
            status = { ...status, keyApprovals: kept };
          }
          state.status = status;
          state.visible = Boolean(status);
          state.known = true;
        } catch {
          if (!ended && asked === latest) {
            state.status = undefined;
            state.visible = false;
            state.known = true;
          }
        }
      };
      read();
      // An edit to the card changes its triggers, so their runs left change
      // too. A run of the automation that moves (it starts, reaches a
      // milestone, commits or ends, or a pause cancels it), and a change to
      // the automation's own state (such as switching it on, pausing,
      // resuming or removing it), change its row and not the card. The
      // realm tells its direct writers, the viewers this route shows the row
      // to, with a `job` event for a run and an `automation` event for the
      // automation, each naming the automation by its identifier, spelled as
      // the card's id is.
      let unsubscribe = subscribeToRealm(realm, (event) => {
        if (
          (event.eventName === 'index' &&
            'invalidations' in event &&
            event.invalidations.some(
              (u) => u === realm + path || u === `${realm}${path}.json`,
            )) ||
          (event.eventName === 'automation' && event.automation === id)
        ) {
          read();
        } else if (event.eventName === 'job' && event.automation === id) {
          read({ checkKeys: false });
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

// An automation's runs, newest first, as the realm's `_automation-runs` route
// lists them to the realm's direct writers: what started each run, where the
// run is, how the run ended and why, and the trigger's later slots that
// joined a run while the run waited (the slots Boxel skipped). Any other
// viewer is told the viewer isn't a direct writer, and the card shows no runs.
type RunState = 'pending' | 'running' | 'complete' | 'error' | 'canceled';
interface JoinedSlot {
  trigger: string;
  slot: string;
  at: string;
}
interface ListedRun {
  id: string;
  startedBy: 'trigger' | 'preview' | 'run-now';
  trigger: string | null;
  slot: string | null;
  state: RunState;
  // The step the run is in, or the step an ended run got to: an error at
  // `admission` means Boxel never started the script.
  step: 'admission' | 'script' | 'commit' | null;
  errorReason: string | null;
  errorMessage: string | null;
  scriptLine: number | null;
  // The cap a `hit-a-cap` run reached, by the caps' own names.
  cap: string | null;
  canceledBy: string | null;
  canceledByAPerson: boolean;
  viewerCanceled: boolean;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
  joined: JoinedSlot[];
  // The milestones the script planned and the run reached, in the shape the
  // status route gives the last run's.
  milestones: LastRun | null;
  // For a run still waiting for its first attempt, what the run waits for:
  // the automation's run ahead of it in the queue, or a Boxel worker.
  waitingFor:
    | {
        kind: 'run';
        runId: string;
        startedBy: ListedRun['startedBy'];
        trigger: string | null;
        slot: string | null;
        state: 'pending' | 'running';
      }
    | { kind: 'worker' }
    | null;
}
type RunsState = {
  // Whether the route answered that the viewer is a direct writer.
  visible: boolean;
  loading: boolean;
  runs: ListedRun[];
  // The page shown, counting from 1, how many pages the runs fill, and how
  // many runs there are in all.
  page: number;
  pages: number;
  total: number;
  failed: boolean;
  // A page the viewer asked for is still loading.
  paging: boolean;
  // When the shown page was read, which the rows' relative times count from.
  readAt: Date;
};

const RUNS_PATH = '_automation-runs';
// The runs one page holds.
const RUNS_PAGE = 20;

interface RunsPage {
  visible: boolean;
  runs: ListedRun[];
  page: number;
  pages: number;
  total: number;
}

async function readRunsPage(
  tools: Tools,
  url: string,
  page: number,
): Promise<RunsPage | undefined> {
  let result = await new AuthedFetchTool(tools).execute({
    url: `${url}&limit=${RUNS_PAGE}&page=${page}`,
    acceptHeader: 'application/json',
  });
  if (!result.ok) {
    return undefined;
  }
  let meta = result.body?.meta;
  if (meta?.directWriter === false) {
    return { visible: false, runs: [], page: 1, pages: 1, total: 0 };
  }
  let data = (result.body?.data ?? []) as {
    id: string;
    attributes: Omit<ListedRun, 'id'>;
  }[];
  return {
    visible: true,
    runs: data.map(({ id, attributes }) => ({ id, ...attributes })),
    page: Number(meta?.page ?? page),
    pages: Number(meta?.pages ?? 1),
    total: Number(meta?.total ?? data.length),
  };
}

// The automation's runs, a page at a time, kept live: a `job` realm event
// naming the automation (a run is made, starts, reaches a milestone,
// commits or ends) and an `automation` event (a pause or remove cancels the
// automation's runs) read the page shown again.
function automationRuns(
  owner: object,
  args: () => {
    id: string | undefined;
    realm: string | undefined;
    realmId: string | undefined;
    tools: Tools | undefined;
  },
) {
  let kept:
    | {
        url: string | undefined;
        state: RunsState;
        // The page the reads ask for: kept out of tracked state, since the
        // resource's first read runs while the resource sets up, and a
        // tracked read there would run the resource again on every answer.
        page: number;
        showPage: (page: number) => void;
      }
    | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { id, realm, realmId, tools } = args();
      let path = id && realmId ? pathInRealm(id, realmId) : undefined;
      let url =
        realm && path !== undefined
          ? `${realm}${RUNS_PATH}?automation=${encodeURIComponent(
              realm + path,
            )}`
          : undefined;
      if (!kept || kept.url !== url) {
        kept = {
          url,
          state: new TrackedObject<RunsState>({
            visible: false,
            loading: true,
            runs: [],
            page: 1,
            pages: 1,
            total: 0,
            failed: false,
            paging: false,
            readAt: nowDate(),
          }),
          page: 1,
          showPage: () => undefined,
        };
      }
      let current = kept;
      let state = current.state;
      if (!url || !tools) {
        state.loading = false;
        return current;
      }
      let ended = false;
      let latest = 0;
      let read = async (page: number) => {
        let asked = ++latest;
        await Promise.resolve();
        if (ended || asked !== latest) {
          return;
        }
        try {
          let answer = await readRunsPage(tools, url, page);
          if (ended || asked !== latest) {
            return;
          }
          if (answer) {
            current.page = answer.page;
            state.visible = answer.visible;
            state.runs = answer.runs;
            state.readAt = nowDate();
            state.page = answer.page;
            state.pages = answer.pages;
            state.total = answer.total;
            state.failed = false;
          } else {
            state.failed = state.visible;
          }
        } catch {
          if (!ended && asked === latest) {
            state.failed = state.visible;
          }
        } finally {
          if (!ended && asked === latest) {
            state.loading = false;
            state.paging = false;
          }
        }
      };
      current.showPage = (page: number) => {
        current.page = page;
        state.paging = true;
        read(page);
      };
      read(current.page);
      let unsubscribe = subscribeToRealm(realm!, (event) => {
        if (
          (event.eventName === 'job' || event.eventName === 'automation') &&
          event.automation === id
        ) {
          read(current.page);
        }
      });
      on.cleanup(() => {
        ended = true;
        unsubscribe?.();
      });
      return current;
    }),
  );
}

type RunTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';

// The admission refusals that mean Boxel never started the run, in plain
// words: each says why, and who does what so the next run starts.
const NOT_STARTED: Record<string, string> = {
  'insufficient-credits':
    'Boxel didn’t start the run because the payer’s credit balance was too low. Boxel starts the next run once the payer adds credits.',
  'daily-credit-cap-reached':
    'Boxel didn’t start the run because the automation reached the daily credit limit. Boxel starts runs again the next day, or once a realm administrator raises the limit and resumes the automation.',
  'monthly-credit-cap-reached':
    'Boxel didn’t start the run because the automation reached the monthly credit limit. Boxel starts runs again the next month, or once a realm administrator raises the limit and resumes the automation.',
  'pricing-unavailable':
    'Boxel didn’t start the run because Boxel couldn’t read the current prices. Boxel starts the next run once Boxel can read the prices again.',
  'not-a-direct-writer':
    'Boxel didn’t start the run because the person the run acts as is no longer a realm administrator. A realm administrator resumes the automation and becomes the payer.',
  'session-revoked':
    'Boxel didn’t start the run because the person the run acts as signed out of every session. That person signs in again, and a realm administrator resumes the automation.',
  'account-deactivated':
    'Boxel didn’t start the run because someone deactivated the account of the person the run acts as. A realm administrator resumes the automation and becomes the payer.',
  'account-unverifiable':
    'Boxel didn’t start the run because Boxel couldn’t check the account of the person the run acts as. Boxel checks again at the next run.',
  'payer-changed':
    'Boxel didn’t start the run because someone else became the payer after Boxel queued the run. The next run acts as the new payer.',
  'automation-paused':
    'Boxel didn’t start the run because a realm administrator paused the automation after Boxel queued the run. Boxel starts runs again once a realm administrator resumes the automation.',
  'not-switched-on':
    'Boxel didn’t start the run because nobody has the automation turned on. Boxel starts runs once a realm administrator turns the automation on.',
  'missing-script':
    'Boxel didn’t start the run because Boxel couldn’t read the script. Someone fixes the script link in the edit view.',
  'not-an-automation':
    'Boxel didn’t start the run because the card no longer reads as an automation. Someone fixes the automation’s settings in the edit view.',
  'binding-not-approved':
    'Boxel didn’t start the run because nobody approved an outside service the automation calls. The person the run acts as approves the service in the secure window.',
  'binding-needs-reapproval':
    'Boxel didn’t start the run because an outside service the automation calls changed since someone approved the service. The person the run acts as approves the service again in the secure window.',
  'share-suspended':
    'Boxel didn’t start the run because someone suspended the shared key an outside service uses. A realm administrator resumes the shared key, or replaces the shared key with another key.',
  'credential-rejected':
    'Boxel didn’t start the run because the outside service refused the key or connection the automation uses. The person the run acts as reconnects or replaces the key.',
  'waiting-for-key-approval':
    'Boxel didn’t start the run because the automation is waiting for key approval. Boxel starts runs again once someone approves the automation’s use of each key.',
  'key-approval-ended':
    'Boxel didn’t start the run because an approval of the automation’s use of a key ended, or someone changed the automation after the approval. Boxel starts runs again once someone approves the automation’s use of each key again.',
  'run-admission-failed':
    'Boxel didn’t start the run because Boxel couldn’t ask the workspace whether the run may start. Boxel asks again at the next run.',
  'run-admission-unavailable':
    'Boxel didn’t start the run because a published workspace doesn’t run automations.',
};

// Why Boxel stopped the automation, for a run a pause canceled when no
// person asked for the pause, or that the wait for key approval canceled.
const PAUSE_CANCELED: Record<string, string> = {
  'caps-raised':
    'Boxel canceled the run because someone raised a limit above what the payer agreed to pay for.',
  'batched-ai-enabled':
    'Boxel canceled the run because someone turned on batched AI after the payer agreed to the limits.',
  'webhook-changed':
    'Boxel canceled the run because a realm administrator pointed a trigger at a webhook the payer didn’t agree to.',
  'webhook-owner-lost-access':
    'Boxel canceled the run because the person who made a trigger’s incoming webhook is no longer a realm administrator.',
  'payer-lost-access':
    'Boxel canceled the run because the payer is no longer a realm administrator.',
  'realm-archived':
    'Boxel canceled the run because someone archived this workspace.',
  'repeated-failures':
    'Boxel canceled the run because the automation’s runs kept failing.',
  'invalid-declaration':
    'Boxel canceled the run because the automation’s settings have problems.',
  'waiting-for-key-approval':
    'Boxel canceled the run because the automation is waiting for key approval. Boxel starts runs again once someone approves the automation’s use of each key.',
};

// A run's per-run limit in words, by the cap's name in a capped run's `cap`.
const CAP_WORDS: Record<string, string> = {
  callApiCalls: 'outside calls',
  responseBytes: 'outside response size',
  resolveCalls: 'AI requests',
  aiCredits: 'AI spending',
  writes: 'saves',
  seconds: 'time',
};

interface RunReason {
  // A sentence on why the run ended as the run did.
  text: string;
  // The server's own detail, when the sentence doesn't already carry it.
  detail?: string;
  // The script line a script's error points at.
  line?: number;
}

function runReason(run: ListedRun): RunReason | undefined {
  if (run.state === 'canceled') {
    if (run.canceledByAPerson) {
      return {
        text: run.viewerCanceled
          ? 'You canceled the run.'
          : run.canceledBy
            ? `${run.canceledBy} canceled the run.`
            : 'A person who shares no workspace with you canceled the run.',
      };
    }
    return {
      text:
        (run.errorReason && PAUSE_CANCELED[run.errorReason]) ??
        'Boxel canceled the run.',
    };
  }
  if (run.state !== 'error') {
    return undefined;
  }
  let reason = run.errorReason ?? '';
  let message = run.errorMessage ?? undefined;
  switch (reason) {
    case 'script-error':
      return run.step === 'admission'
        ? {
            text: 'Boxel didn’t start the run because the script is empty, too long, or doesn’t parse. Someone fixes the script in the edit view.',
            detail: message,
          }
        : {
            text:
              run.scriptLine !== null
                ? 'The script threw an error on line'
                : 'The script threw an error.',
            detail: message,
            line: run.scriptLine ?? undefined,
          };
    case 'call-failed':
      return {
        text: 'A call the script made failed, and the script didn’t catch the error.',
        detail: message,
      };
    case 'timed-out':
      return {
        text: 'Boxel stopped the run when the run reached the time limit. A realm administrator raises the limit in the edit view and resumes the automation.',
      };
    case 'hit-a-cap': {
      let words = run.cap ? CAP_WORDS[run.cap] : undefined;
      return {
        text: `${
          words
            ? `Boxel stopped the run when the run reached the limit on ${words}.`
            : 'Boxel stopped the run when the run reached one of the run’s limits.'
        } A realm administrator raises the limit in the edit view and resumes the automation.`,
      };
    }
  }
  let notStarted = NOT_STARTED[reason];
  if (notStarted) {
    return { text: notStarted, detail: message };
  }
  if (run.step === 'admission') {
    return {
      text: 'Boxel didn’t start the run because Boxel couldn’t use an outside service the automation calls. Someone fixes the service in the automation’s settings.',
      detail: message,
    };
  }
  return {
    text: 'Boxel couldn’t finish the run.',
    detail: message ?? (reason || undefined),
  };
}

function runLook(run: ListedRun): { label: string; tone: RunTone } {
  switch (run.state) {
    case 'pending':
      return { label: 'Waiting', tone: 'neutral' };
    case 'running':
      return { label: 'Running', tone: 'info' };
    case 'complete':
      return { label: 'Complete', tone: 'success' };
    case 'canceled':
      return { label: 'Canceled', tone: 'warning' };
    case 'error':
      return run.step === 'admission'
        ? { label: 'Didn’t start', tone: 'warning' }
        : { label: 'Failed', tone: 'danger' };
  }
}

// How far a run got through the script's milestones, in a line: the
// milestone a running run is in with the last task the script reported in
// it, the one a failed run failed in, or how many a run that ended reached.
// Undefined when the script reported none.
function runProgress(run: ListedRun): string | undefined {
  let m = run.milestones;
  if (!m || (m.milestones.length === 0 && m.plan.length === 0)) {
    return undefined;
  }
  let reached = m.milestones.length;
  let total = reached + m.ahead.length;
  let last = m.milestones.at(-1);
  if (run.state === 'running') {
    let task = last?.tasks?.at(-1)?.text;
    return m.current
      ? `Milestone ${tally(reached)} of ${tally(total)}: ${m.current}${task ? ` — ${task}` : ''}`
      : `The run has reached no milestone yet; the script plans ${tally(total)}.`;
  }
  if (run.state === 'error' && m.failedIn) {
    return `Failed in milestone ${tally(reached)} of ${tally(total)}: ${m.failedIn}`;
  }
  if (run.state === 'canceled' && last) {
    return `Stopped in milestone ${tally(reached)} of ${tally(total)}: ${last.name}`;
  }
  return reached === 0
    ? 'The run reached no milestone.'
    : `Reached ${tally(reached)} of ${tally(total)} ${
        total === 1 ? 'milestone' : 'milestones'
      }`;
}

// A time in a row's accessible name, as the row shows the time: "Nov 20,
// 10:00 AM" in the viewer's own zone. One formatter serves every row, since
// each formatter holds native memory the engine never frees.
const ROW_TIME = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
});
function rowTime(iso: string): string {
  let date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : ROW_TIME.format(date);
}

// One row of the run list: a run, or a later slot that joined a run.
// `skipped` is the joined slot on a skipped slot's row, absent on a run's.
interface RunRow {
  key: string;
  run: ListedRun;
  skipped?: JoinedSlot;
}

function runRows(runs: ListedRun[]): RunRow[] {
  let rows: RunRow[] = [];
  for (let run of runs) {
    // A slot joins a run after the run was made, so the slots come first,
    // newest first, like the runs.
    for (let slot of [...run.joined].reverse()) {
      rows.push({ key: `${run.id}:${slot.slot}`, run, skipped: slot });
    }
    rows.push({ key: run.id, run });
  }
  return rows;
}

// When a scheduled slot fires, as an ISO time; undefined for a webhook
// delivery's id.
function slotTime(slot: string | null): string | undefined {
  return slot && !Number.isNaN(Date.parse(slot)) ? slot : undefined;
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
    case 'waiting-for-key-approval':
      return { label: 'Waiting for key approval', tone: 'warning' };
    case 'done':
      return { label: 'Done', tone: 'info' };
  }
}

// The ways a realm administrator can fix what paused the automation, when
// there is a choice, with the sentence that introduces them. The isolated
// view shows these in place of the state sentence, which stands alone in the
// views that have no room for a list.
function stateSteps(
  status: ServerStatus,
): { lead: string; steps: string[] } | undefined {
  if (
    status.switchedOn &&
    status.state === 'paused' &&
    status.pauseReason === 'webhook-owner-lost-access'
  ) {
    return {
      lead: 'The person who made a trigger’s incoming webhook is no longer a realm administrator, so Boxel paused the automation. Boxel runs nothing until a realm administrator does one of these two things and then resumes the automation:',
      steps: [
        'Edit the automation, and in the trigger’s Webhook field pick one of this workspace’s webhooks, or',
        'Make the person who made the webhook a realm administrator again.',
      ],
    };
  }
  return undefined;
}

// What the state means for the next run, as a sentence.
function stateSentence(status: ServerStatus): string {
  if (!status.switchedOn) {
    return 'Nobody has turned this automation on, so Boxel runs nothing. A realm administrator can turn this automation on, and that person then pays for every run.';
  }
  switch (status.state) {
    case 'active':
      return 'Boxel runs this automation each time a trigger fires and charges the payer for every run.';
    case 'waiting-for-credits':
      return 'The payer has no credits left, so Boxel holds every run. Boxel runs the automation again once the payer adds credits.';
    case 'waiting-for-key-approval':
      return 'Boxel holds every run until someone approves the automation’s use of each key.';
    case 'done':
      return 'The automation has no runs left on any trigger, so Boxel runs nothing more. Boxel runs the automation again when a realm administrator adds a trigger.';
    case 'paused':
      switch (status.pauseReason) {
        case 'realm-archived':
          return 'Someone archived this workspace, so Boxel paused the automation. Boxel runs nothing until a realm administrator restores the workspace and resumes the automation.';
        case 'payer-lost-access':
          return 'The payer is no longer a realm administrator, so Boxel paused the automation. Boxel runs nothing until a realm administrator resumes the automation and becomes the new payer.';
        case 'caps-raised':
          return 'Someone raised a limit above what the payer agreed to pay for, so Boxel paused the automation. Boxel runs nothing until a realm administrator resumes the automation and agrees to the new limits.';
        case 'batched-ai-enabled':
          return 'Someone turned on batched AI after the payer agreed to the limits, so Boxel paused the automation. Boxel runs nothing until a realm administrator resumes the automation and agrees to batched AI.';
        case 'webhook-changed':
          return 'A realm administrator pointed a trigger at an incoming webhook the payer didn’t agree to, so Boxel paused the automation. Boxel runs nothing until a realm administrator resumes the automation and agrees to the new webhook.';
        case 'webhook-owner-lost-access':
          return 'The person who made a trigger’s incoming webhook is no longer a realm administrator, so Boxel paused the automation. Boxel runs nothing until a realm administrator fixes the trigger’s webhook and resumes the automation.';
        case 'repeated-failures':
          return repeatedFailuresSentence(status);
        case 'invalid-declaration':
          return 'Boxel paused the automation because the automation’s settings have problems. Boxel will resume the automation once a realm administrator fixes each problem below.';
        default:
          return 'A realm administrator paused the automation, so Boxel runs nothing until a realm administrator resumes the automation.';
      }
  }
}

// Why the automation paused itself after its runs kept failing. The last
// run's error shows on its own, under _Last error_ (see `statusItems`).
function repeatedFailuresSentence(
  status: Extract<ServerStatus, { switchedOn: true }>,
): string {
  let count = status.failuresInARow;
  let runs =
    count === 1
      ? 'a run'
      : `${count && count > 1 ? tally(count) : 'several'} runs in a row`;
  return `Boxel paused the automation after ${runs} failed. Boxel runs nothing until a realm administrator fixes what the runs fail on and resumes the automation.`;
}

// Each problem the server found, with where on the card the problem is: a
// trigger by its label, or the section of the card.
interface PauseProblemRow {
  place: string;
  message: string;
}

const PROBLEM_SECTIONS: Record<string, string> = {
  script: 'Script',
  operations: 'Outside services',
  caps: 'Limits',
  params: 'Params',
  batchedAI: 'Batched AI',
  batchDeadlineMinutes: 'Batched AI',
};

function pauseProblemRows(
  status: ServerStatus | undefined,
  triggerLabels: (string | null | undefined)[],
): PauseProblemRow[] {
  if (
    !status?.switchedOn ||
    status.state !== 'paused' ||
    status.pauseReason !== 'invalid-declaration'
  ) {
    return [];
  }
  return (status.pauseProblems ?? []).map(({ path, message }) => {
    let [section, index] = path.split('.');
    let place = PROBLEM_SECTIONS[section] ?? 'Automation';
    if (section === 'triggers' && index !== undefined) {
      let label = triggerLabels[Number(index)]?.trim();
      place = label ? `Trigger “${label}”` : `Trigger ${Number(index) + 1}`;
    }
    return { place, message };
  });
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
      : 'Stopped';
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
    { label: 'Payer', value: payerText(status) },
  ];
  if (status.switchedOn) {
    items.push(
      status.state === 'paused'
        ? { label: 'Next run', value: 'None while paused' }
        : status.state === 'waiting-for-key-approval'
          ? { label: 'Next run', value: 'None while waiting for key approval' }
          : status.nextRun
            ? { label: 'Next run', date: status.nextRun }
            : { label: 'Next run', value: 'None' },
    );
    let last = lastRunText(status);
    items.push(
      last && status.lastFinishedAt
        ? { label: `Last run: ${last}`, date: status.lastFinishedAt }
        : { label: 'Last run', value: 'No runs yet' },
    );
    let error = status.lastFailure?.message || status.lastFailure?.reason;
    if (error && status.failuresInARow) {
      items.push({ label: 'Last error', value: error });
    }
  }
  return items;
}

// The milestones a script declares with `realm.progress.plan([...])`: the
// names of the first such call whose array holds only string literals.
// Undefined when the script declares none that way, such as a plan built at
// run time; then the milestones show once a run reports them.
const PLAN_CALL = /realm\s*\.\s*progress\s*\.\s*plan\s*\(\s*\[([^\]]*)\]\s*\)/;
const STRING_LITERAL =
  /'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)"|`((?:[^`\\$]|\\.)*)`/g;

function declaredMilestones(script: string): string[] | undefined {
  let call = PLAN_CALL.exec(script);
  if (!call) {
    return undefined;
  }
  let body = call[1];
  let names: string[] = [];
  for (let match of body.matchAll(STRING_LITERAL)) {
    let raw = match[1] ?? match[2] ?? match[3] ?? '';
    names.push(raw.replace(/\\(.)/g, '$1').trim());
  }
  let rest = body.replace(STRING_LITERAL, '').replace(/[\s,]/g, '');
  if (rest !== '' || names.length === 0 || names.some((name) => !name)) {
    return undefined;
  }
  return names;
}

// "under a second", "4 s", "2 min 5 s", "1 h 3 min".
function durationText(ms: number): string {
  let seconds = Math.round(ms / 1000);
  if (seconds < 1) {
    return 'under a second';
  }
  if (seconds < 60) {
    return `${seconds} s`;
  }
  let minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    let rest = seconds % 60;
    return rest ? `${minutes} min ${rest} s` : `${minutes} min`;
  }
  let hours = Math.floor(minutes / 60);
  let rest = minutes % 60;
  return rest ? `${hours} h ${rest} min` : `${hours} h`;
}

// Where a run stands at one milestone: reached and done, running now, where
// the run ended with an error, where Boxel stopped the run, or not reached.
type MilestoneState =
  | 'reached'
  | 'running'
  | 'failed'
  | 'stopped'
  | 'not-started';

interface MilestoneRow {
  id: string;
  // Tells one run's milestone from another's at the same place, so a list of
  // tasks opened on one run stays closed on the next.
  key: string;
  name: string;
  state: MilestoneState;
  badge: string;
  tone: 'neutral' | 'info' | 'success' | 'danger';
  detail?: string;
  // The notable tasks the script reported inside the milestone, in order.
  tasks: string[];
}

// How long the milestone of each name took on an earlier run: the first
// time that run reached the milestone, as a run's plan names each milestone
// once.
function milestoneTimes(run: LastRun | undefined): Map<string, number> {
  let times = new Map<string, number>();
  for (let milestone of run?.milestones ?? []) {
    if (!times.has(milestone.name)) {
      times.set(milestone.name, milestone.ms);
    }
  }
  return times;
}

// One row per milestone the run reached, in the order reached, then one per
// milestone of the plan the run hasn't reached. With `previous`, the run
// before this one, each row also says how long the milestone took on that
// run, so a running run's current milestone and the ones ahead read against
// the last run's pace.
function runMilestoneRows(run: LastRun, previous?: LastRun): MilestoneRow[] {
  let lastIndex = run.milestones.length - 1;
  let before = milestoneTimes(previous);
  let lastRunPart = (name: string) => {
    let ms = before.get(name);
    return ms === undefined ? undefined : `Last run took ${durationText(ms)}`;
  };
  let rows: MilestoneRow[] = run.milestones.map((milestone, index) => {
    let last = index === lastIndex;
    let state: MilestoneState =
      last && run.state === 'running'
        ? 'running'
        : last && run.failedIn !== null
          ? 'failed'
          : last && run.state === 'canceled'
            ? 'stopped'
            : 'reached';
    let time = durationText(milestone.ms);
    let parts = [
      state === 'running'
        ? `Running for ${time}`
        : state === 'reached'
          ? `Took ${time}`
          : `Ran for ${time}`,
      lastRunPart(milestone.name),
      !milestone.planned && run.plan.length > 0 ? 'Not in the plan' : undefined,
    ].filter((part): part is string => Boolean(part));
    let look = MILESTONE_LOOKS[state];
    return {
      id: `${index}`,
      key: `${run.runId}:${index}`,
      name: milestone.name,
      state,
      badge: look.badge,
      tone: look.tone,
      detail: parts.join(' · '),
      tasks: (milestone.tasks ?? []).map(({ text }) => text),
    };
  });
  return [
    ...rows,
    ...run.ahead.map((name, index) => ({
      id: `ahead-${index}`,
      key: `${run.runId}:ahead-${index}`,
      name,
      state: 'not-started' as const,
      badge: 'Not started',
      tone: 'neutral' as const,
      detail: lastRunPart(name),
      tasks: [],
    })),
  ];
}

// The milestones a script declares, before a run has reached any of them.
function declaredMilestoneRows(names: string[]): MilestoneRow[] {
  return names.map((name, index) => ({
    id: `${index}`,
    key: `declared-${index}`,
    name,
    state: 'not-started',
    badge: 'Not started',
    tone: 'neutral',
    tasks: [],
  }));
}

const MILESTONE_LOOKS: Record<
  MilestoneState,
  { badge: string; tone: MilestoneRow['tone'] }
> = {
  reached: { badge: 'Done', tone: 'success' },
  running: { badge: 'Running', tone: 'info' },
  failed: { badge: 'Failed here', tone: 'danger' },
  stopped: { badge: 'Stopped here', tone: 'neutral' },
  'not-started': { badge: 'Not started', tone: 'neutral' },
};

function runLead(run: LastRun): string {
  let lead: string;
  if (run.state === 'running') {
    lead = 'The milestones the script has reported on the run in progress.';
  } else {
    let ended =
      run.state === 'complete'
        ? 'completed'
        : run.state === 'error'
          ? 'ended with an error'
          : 'Boxel stopped';
    lead = `The milestones the script reported on the last run, which ${ended}.`;
  }
  if (run.dropped > 0) {
    lead += ` The script marked ${tally(run.dropped)} more ${
      run.dropped === 1 ? 'milestone' : 'milestones'
    } past the ${tally(MAX_RUN_MILESTONES)} a run records, so the last milestone shown also holds the time of the unrecorded milestones.`;
  }
  let tasksDropped = run.tasksDropped ?? 0;
  if (tasksDropped > 0) {
    lead += ` Boxel didn’t record ${tally(tasksDropped)} more ${
      tasksDropped === 1 ? 'task' : 'tasks'
    } the script reported: a run records at most ${tally(MAX_RUN_TASKS)} tasks, and none inside a milestone Boxel didn’t record.`;
  }
  return lead;
}

// The most tasks a milestone lists before a button shows the rest: the
// latest ones, since the latest says what the run did last.
const SHOWN_TASKS = 5;

// The milestones as a timeline, one row each, joined by the timeline's rail
// so they read as a progression. Each marker is shaded in its state's color:
// gray before the milestone runs, blue while it runs, green once it is
// done, red where the run ended with an error. Under each milestone, the
// notable tasks the script reported inside the milestone, in order.
class MilestoneTimeline extends GlimmerComponent<{
  Args: { rows: MilestoneRow[]; label: string };
}> {
  // The milestones whose every task shows, by row key.
  private allTasksShown = new TrackedSet<string>();
  // Each milestone's state chip sits on the milestone's title line, in the
  // state's own tone.
  get events(): TimelineEvent[] {
    return this.args.rows.map((row) => ({
      id: row.id,
      title: row.name,
      status: row.badge,
      statusTone: row.tone,
    }));
  }
  rowOf = (event: TimelineEvent): MilestoneRow =>
    this.args.rows.find((row) => row.id === event.id)!;
  // The tasks a milestone shows, and the earlier ones the toggle shows or
  // hides. The toggle stays where it is either way, so focus stays on it.
  shownTasks = (
    row: MilestoneRow,
  ): { tasks: string[]; earlier: number; expanded: boolean } => {
    let earlier = Math.max(row.tasks.length - SHOWN_TASKS, 0);
    let expanded = this.allTasksShown.has(row.key);
    return {
      tasks: expanded ? row.tasks : row.tasks.slice(-SHOWN_TASKS),
      earlier,
      expanded,
    };
  };
  earlierTasksLabel = (earlier: number, expanded: boolean): string =>
    `${expanded ? 'Hide' : 'Show'} ${tally(earlier)} earlier ${
      earlier === 1 ? 'task' : 'tasks'
    }`;
  toggleEarlierTasks = (row: MilestoneRow) => {
    if (this.allTasksShown.has(row.key)) {
      this.allTasksShown.delete(row.key);
    } else {
      this.allTasksShown.add(row.key);
    }
  };
  <template>
    <Timeline
      @events={{this.events}}
      @label={{@label}}
      class='milestones'
      data-test-automation-milestone-list
    >
      <:marker as |event|>
        {{#let (this.rowOf event) as |row|}}
          <span
            class='milestones__mark'
            data-milestone-state={{row.state}}
            data-test-milestone-state={{row.state}}
          >
            {{#if (eq row.state 'reached')}}
              <CircleCheckIcon width='14' height='14' />
            {{else if (eq row.state 'running')}}
              <HourglassIcon width='13' height='13' />
            {{else if (eq row.state 'failed')}}
              <CircleXIcon width='14' height='14' />
            {{else if (eq row.state 'stopped')}}
              <CirclePauseIcon width='14' height='14' />
            {{else}}
              <CircleDashedIcon width='14' height='14' />
            {{/if}}
          </span>
        {{/let}}
      </:marker>
      <:default as |event|>
        {{#let (this.rowOf event) as |row|}}
          {{#if row.detail}}
            <span class='milestones__text'>{{row.detail}}</span>
          {{/if}}
          {{#if row.tasks.length}}
            {{#let (this.shownTasks row) as |shown|}}
              {{#if shown.earlier}}
                <Button
                  @appearance='link'
                  @size='s'
                  class='milestones__earlier'
                  aria-expanded={{if shown.expanded 'true' 'false'}}
                  data-test-automation-milestone-earlier-tasks
                  {{on 'click' (fn this.toggleEarlierTasks row)}}
                >{{this.earlierTasksLabel
                    shown.earlier
                    shown.expanded
                  }}</Button>
              {{/if}}
              <ul
                class='milestones__tasks'
                aria-label='Tasks in {{row.name}}'
                data-test-automation-milestone-tasks
              >
                {{#each shown.tasks as |task|}}
                  <li
                    class='milestones__task'
                    data-test-automation-milestone-task
                  >{{task}}</li>
                {{/each}}
              </ul>
            {{/let}}
          {{/if}}
        {{/let}}
      </:default>
    </Timeline>
    <style scoped>
      .milestones {
        max-inline-size: 34rem;
      }
      /* Fills the timeline's marker with a light tint of the state's color,
         the glyph in the color's ink, which keeps the glyph legible on the
         tint in both light and dark themes. */
      .milestones__mark {
        --milestone-color: var(--muted-foreground);
        --milestone-ink: var(--milestone-color);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        inline-size: 100%;
        block-size: 100%;
        border-radius: 50%;
        color: var(--milestone-ink);
        background: color-mix(
          in oklab,
          var(--milestone-color) 14%,
          var(--card, #fff)
        );
      }
      .milestones__mark[data-milestone-state='reached'] {
        --milestone-color: var(--success);
        --milestone-ink: var(--success-ink);
      }
      .milestones__mark[data-milestone-state='running'] {
        --milestone-color: var(--info);
        --milestone-ink: var(--info-ink);
      }
      .milestones__mark[data-milestone-state='failed'] {
        --milestone-color: var(--destructive);
        --milestone-ink: var(--destructive-ink);
      }
      .milestones__mark[data-milestone-state='not-started'] {
        background: var(--card, #fff);
      }
      .milestones__text {
        color: var(--muted-foreground);
      }
      .milestones__earlier {
        margin-block-start: var(--boxel-sp-4xs);
      }
      .milestones__tasks {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        margin: var(--boxel-sp-4xs) 0 0;
        /* Wide enough that each bullet sits under the milestone's name, not
           out over the timeline's rail. */
        padding-inline-start: var(--boxel-sp-lg);
        list-style: disc;
        overflow-wrap: break-word;
      }
      .milestones__task::marker {
        color: var(--muted-foreground);
      }
    </style>
  </template>
}

// The milestones a fitted view lists: the isolated view's timeline, compact,
// with each milestone's state marked as the isolated view marks it and its
// name, and its time, last task or where Boxel stopped the run beside it.
class FittedMilestones extends GlimmerComponent<{
  // `details` adds each milestone's time and last task under its name, for a
  // view tall enough for two lines a milestone.
  // `earlier` and `later` say how many milestones the list leaves out
  // before and after it; the list marks each by running its rail on past
  // the marker and
  // tells assistive technology the count.
  Args: {
    steps: StepItem[];
    details?: boolean;
    earlier?: string;
    later?: string;
  };
}> {
  get events(): TimelineEvent[] {
    return this.args.steps.map((step, index) => ({
      id: String(index),
      title: step.label,
    }));
  }
  stepOf = (event: TimelineEvent): StepItem =>
    this.args.steps[Number(event.id)];
  // The list's first milestone is the plan's first when nothing comes before
  // it, so no rail runs up from its marker.
  startsRail = (event: TimelineEvent): boolean =>
    event.id === '0' && !this.args.earlier;
  <template>
    {{#if @earlier}}
      <span
        class='fm__more'
        data-side='earlier'
        data-test-automation-fitted-milestones-earlier
      >
        <VisuallyHidden>{{@earlier}}</VisuallyHidden>
      </span>
    {{/if}}
    <Timeline
      @events={{this.events}}
      @density='compact'
      @label='Milestones'
      class='fm'
      data-test-automation-fitted-milestone-list
    >
      <:marker as |event|>
        {{#let (this.stepOf event) as |step|}}
          <span
            class='fm__mark'
            data-step-state={{step.state}}
            data-rail-start={{if (this.startsRail event) 'true'}}
          >
            {{#if (eq step.state 'complete')}}
              <CircleCheckIcon width='16' height='16' />
            {{else if (eq step.state 'in-progress')}}
              <HourglassIcon width='16' height='16' />
            {{else if (eq step.state 'error')}}
              <CircleXIcon width='16' height='16' />
            {{else if (eq step.state 'blocked')}}
              <CirclePauseIcon width='16' height='16' />
            {{else}}
              <CircleDashedIcon width='16' height='16' />
            {{/if}}
          </span>
        {{/let}}
      </:marker>
      <:default as |event|>
        {{#let (this.stepOf event) as |step|}}
          {{#if (and @details step.detail)}}
            <span
              class='fm__detail'
              data-milestone-detail
            >{{step.detail}}</span>
          {{/if}}
        {{/let}}
      </:default>
    </Timeline>
    {{#if @later}}
      <span
        class='fm__more'
        data-side='later'
        data-test-automation-fitted-milestones-later
      >
        <VisuallyHidden>{{@later}}</VisuallyHidden>
      </span>
    {{/if}}
    <style scoped>
      /* The rail runs on past the first milestone's marker when milestones
         come before the ones listed, and past the last one's when more come
         after; where the list starts or ends the plan, the rail stops at
         the marker. Below the list the stretch starts at the last marker,
         since the rail itself stops there. */
      .fm__more {
        position: relative;
        display: block;
        inline-size: 1rem;
        block-size: 0.375rem;
      }
      .fm__more::after {
        content: '';
        position: absolute;
        top: 0;
        bottom: 0;
        /* Pret UI's rail starts at the marker's middle, so this one does. */
        left: 50%;
        width: 1px;
        background: var(--border);
      }
      .fm__more[data-side='later']::after {
        top: -0.75rem;
      }
      .fm {
        font-size: var(--boxel-font-size-xs);
      }
      /* Pret UI's marker is a square that hides the rail behind it; the
         glyph's circle sits inside that square, which left a gap between
         the rail and the circle. The marker is clear instead, and a disc
         the size of the glyph's circle hides the rail, so the rail runs
         right up to the circle. */
      .fm :deep(.pretui-timeline-marker) {
        background: transparent;
      }
      /* Pret UI draws no rail on the last row, and the row is taller than
         its marker, so the rail from the row above stops short of the last
         marker. The last row's rail runs down to its marker's middle. */
      .fm :deep(.pretui-timeline-event:last-child::before) {
        display: block;
        bottom: 50%;
      }
      .fm__mark {
        background: radial-gradient(
          circle 7px at center,
          var(--card, var(--background)) 100%,
          transparent 100%
        );
        --milestone-color: var(--muted-foreground);
        position: relative;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        inline-size: 100%;
        block-size: 100%;
        color: var(--milestone-color);
      }
      /* The row is taller than the marker, so the rail shows above the first
         marker; a list with nothing before it covers that stub. */
      .fm__mark[data-rail-start='true']::before {
        content: '';
        position: absolute;
        bottom: 100%;
        left: calc(50% - 1px);
        inline-size: 2px;
        block-size: 0.5rem;
        background: var(--card, var(--background));
      }
      .fm__mark[data-step-state='complete'] {
        --milestone-color: var(--success-ink);
      }
      .fm__mark[data-step-state='in-progress'] {
        --milestone-color: var(--info-ink);
      }
      .fm__mark[data-step-state='error'] {
        --milestone-color: var(--destructive-ink);
      }
      .fm__detail {
        display: block;
        overflow: hidden;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    </style>
  </template>
}

// The most milestones and the most tasks the server records for one run.
const MAX_RUN_MILESTONES = 200;
const MAX_RUN_TASKS = 200;

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

// A grid of status facts: plain values, times with their zone named (the
// status reads in the viewer's zone and each trigger in the trigger's own),
// and the state as a chip.
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
              @month='short'
              @day='numeric'
              @year='numeric'
              @hour='numeric'
              @minute='2-digit'
              @timeZoneName='short'
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
  // A paused automation, or one waiting for key approval, runs nothing,
  // whatever its schedule says.
  return trigger &&
    (status.state === 'paused' || status.state === 'waiting-for-key-approval')
    ? { ...trigger, nextRun: undefined }
    : trigger;
}

// The linked script, read-only, from the text the isolated view read.
class ScriptView extends GlimmerComponent<{
  Args: {
    url: string | undefined;
    state: ScriptState;
  };
}> {
  get state() {
    return this.args.state;
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

// One run as the automations console shows the run when its row opens, read
// from the realm server's `_automation-run-report` route through the host's
// `read-automation-run` tool, for the realm's direct writers.
type RunLogLevel = 'log' | 'info' | 'warn' | 'error';
interface RunCallApiCall {
  seq: number;
  at: string;
  operation: string;
  method?: string;
  // The request's destination, with query values masked.
  destination?: string;
  // The vendor's status; absent when Boxel refused the call or the call
  // failed, and `code` then says which.
  status?: number;
  code?: string;
  ms?: number;
  bytes?: number;
}
// An AI request. The report carries no cost for it: an end user sees what AI
// cost only as the credits Boxel charged (boxel ADR 049 §1.4), on the Cost
// tab.
interface RunResolveCall {
  seq: number;
  at: string;
  model?: string;
  status?: number;
  ms?: number;
  // The tokens the request read and wrote, as the provider reported them.
  inputTokens?: number;
  outputTokens?: number;
}
interface RunReport {
  dryRun: boolean;
  state: RunState;
  timings: {
    createdAt: string;
    startedAt: string | null;
    commitStartedAt: string | null;
    committedAt: string | null;
    finishedAt: string | null;
    queuedMs: number | null;
    runMs: number | null;
    commitMs: number | null;
  };
  log: {
    lines: number;
    dropped: number;
    byLevel: Partial<Record<RunLogLevel, number>>;
  };
  callApiCalls: RunCallApiCall[];
  resolveCalls: RunResolveCall[];
  writes: {
    count: number;
    // A complete Preview's staged files, unless a later Preview replaced
    // the batch (`stagedReplacedBy`).
    staged?: { path: string; size: number }[];
    stagedReplacedBy?: string;
    // The realm-local paths a landed commit saved.
    committed?: string[];
  };
  cost: {
    credits: number;
    creditsByKind: Record<string, number>;
    callApiCalls: number;
    callApiResponseBytes: number;
    resolveCalls: number;
    writes: number;
    aiCreditsSpent: number;
    aiCreditsReserved: number;
  };
}
interface ReadRunAnswer {
  ok: boolean;
  status: number;
  body: {
    data?: { id: string; attributes: Record<string, unknown> };
  };
}

async function readRun(
  tools: Tools,
  input: Record<string, unknown>,
): Promise<ReadRunAnswer | undefined> {
  let result = await new ReadAutomationRunTool(tools).execute({
    json: input,
  });
  return result?.json as ReadRunAnswer | undefined;
}

// Why a read of a run came back empty: the realm server refused the viewer
// (a 4xx: only the realm's direct writers read a run), or the read failed
// on the way and the console tries again.
type RunReadFailure = 'refused' | 'unreachable';

type RunReportState = {
  loading: boolean;
  failure: RunReadFailure | undefined;
  report: RunReport | undefined;
};

// How often the console asks for new lines while the run is pending or
// running and no `job` event wakes the console sooner, and how long the
// console waits before reading again after a read fails on the way.
const RUN_LOG_FOLLOW_MS = 2000;
// The most lines one page of the log holds.
const RUN_LOG_PAGE = 500;

function refused(answer: ReadRunAnswer | undefined): boolean {
  return Boolean(answer && answer.status >= 400 && answer.status < 500);
}

// A run's report, read again on each `job` realm event naming the run (the
// run started, reached a milestone, reported a task, committed or ended),
// and whenever `reread` is called: the run's log reads a new page, since a
// call, an AI request or a console line sends no `job` event, and Boxel
// writes the run's charges after the run's last event. A read that fails on
// the way is tried again after `RUN_LOG_FOLLOW_MS`; a refusal ends the
// reads. The state is kept for as long as the run is the same, so a change
// to the card (a save) keeps what the tabs show.
function automationRunReport(
  owner: object,
  args: () => {
    realm: string | undefined;
    runId: string;
    tools: Tools | undefined;
  },
) {
  let kept:
    | { key: string; state: RunReportState; reread: () => void }
    | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { realm, runId, tools } = args();
      let key = `${realm}|${runId}`;
      if (!kept || kept.key !== key) {
        kept = {
          key,
          state: new TrackedObject<RunReportState>({
            loading: true,
            failure: undefined,
            report: undefined,
          }),
          reread: () => undefined,
        };
      }
      let current = kept;
      let state = current.state;
      if (!realm || !tools) {
        state.loading = false;
        return current;
      }
      let ended = false;
      let latest = 0;
      let retry: ReturnType<typeof setTimeout> | undefined;
      let read = async () => {
        let asked = ++latest;
        clearTimeout(retry);
        await Promise.resolve();
        if (ended || asked !== latest || state.failure === 'refused') {
          return;
        }
        let answer: ReadRunAnswer | undefined;
        try {
          answer = await readRun(tools, {
            realm,
            run: runId,
            read: 'report',
          });
        } catch {
          answer = undefined;
        }
        if (ended || asked !== latest) {
          return;
        }
        state.loading = false;
        let attributes = answer?.ok ? answer.body.data?.attributes : undefined;
        if (attributes) {
          state.report = attributes as unknown as RunReport;
          state.failure = undefined;
        } else if (refused(answer)) {
          state.failure = 'refused';
        } else {
          state.failure = 'unreachable';
          retry = setTimeout(() => read(), RUN_LOG_FOLLOW_MS);
        }
      };
      current.reread = () => {
        read();
      };
      read();
      let unsubscribe = subscribeToRealm(realm, (event) => {
        if (event.eventName === 'job' && event.runId === runId) {
          read();
        }
      });
      on.cleanup(() => {
        ended = true;
        clearTimeout(retry);
        unsubscribe?.();
      });
      return current;
    }),
  );
}

// The storage an automation's runs keep, as the realm server's
// `_automation-storage` route answers it: each file a run created that still
// exists, with its size on disk and in the index, and what one day of that
// storage costs in credits at today's prices (null while the server has no
// prices).
interface AutomationStorage {
  switchedOn: boolean;
  files: { path: string; run: string; fileBytes: number; indexBytes: number }[];
  fileBytes: number;
  indexBytes: number;
  dailyCredits: number | null;
}
type AutomationStorageState = {
  storage: AutomationStorage | undefined;
  failure: RunReadFailure | undefined;
};

// The automation's storage, read when a run opens and again whenever
// `reread` is called: the run's log reads a new page, so a commit that saved
// files shows in the storage too. A read that fails on the way is tried
// again after `RUN_LOG_FOLLOW_MS`; a refusal ends the reads.
function automationStorage(
  owner: object,
  args: () => {
    realm: string | undefined;
    automation: string | undefined;
    tools: Tools | undefined;
  },
) {
  let kept:
    | { key: string; state: AutomationStorageState; reread: () => void }
    | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { realm, automation, tools } = args();
      let key = `${realm}|${automation}`;
      if (!kept || kept.key !== key) {
        kept = {
          key,
          state: new TrackedObject<AutomationStorageState>({
            storage: undefined,
            failure: undefined,
          }),
          reread: () => undefined,
        };
      }
      let current = kept;
      let state = current.state;
      if (!realm || !automation || !tools) {
        return current;
      }
      let ended = false;
      let latest = 0;
      let retry: ReturnType<typeof setTimeout> | undefined;
      let read = async () => {
        let asked = ++latest;
        clearTimeout(retry);
        await Promise.resolve();
        if (ended || asked !== latest || state.failure === 'refused') {
          return;
        }
        let answer: ReadRunAnswer | undefined;
        try {
          answer = await readRun(tools, { realm, automation, read: 'storage' });
        } catch {
          answer = undefined;
        }
        if (ended || asked !== latest) {
          return;
        }
        let attributes = answer?.ok ? answer.body.data?.attributes : undefined;
        if (attributes) {
          state.storage = attributes as unknown as AutomationStorage;
          state.failure = undefined;
        } else if (refused(answer)) {
          state.failure = 'refused';
        } else {
          state.failure = 'unreachable';
          retry = setTimeout(() => read(), RUN_LOG_FOLLOW_MS);
        }
      };
      current.reread = () => {
        read();
      };
      read();
      on.cleanup(() => {
        ended = true;
        clearTimeout(retry);
      });
      return current;
    }),
  );
}

interface RunLogLine {
  seq: number;
  // ms since the epoch
  at: number;
  source: 'script' | 'platform';
  kind: string;
  level?: RunLogLevel;
  message: string;
  scriptLine?: number;
}
type RunLogState = {
  loading: boolean;
  failure: RunReadFailure | undefined;
  // The run's state as the last page read the run.
  runState: RunState | undefined;
  lines: RunLogLine[];
  // The lines Boxel refused past the log's cap.
  dropped: number;
};

// A run's log, kept only to the levels asked for, followed while the run
// goes. This follows the rules of the platform's `followAutomationRunLog`
// (`runtime-common/automation-run-log-follow.ts`), which reads through a
// fetch a card doesn't have, so a change to one belongs in both: the console
// reads page after page, reads on at once while a page says the log holds
// more, and otherwise asks again every `RUN_LOG_FOLLOW_MS` while the run is
// pending or running. A `job` event naming the run reads at once, and one
// that comes while a read is in flight ends the next wait at once. Boxel
// writes the run's last line just after the run ends, so once a page finds
// the run ended with nothing more, the console reads once more an interval
// later, which a wake doesn't shorten, and then stops. A refusal stops the
// reads; any other failure is tried again at the next interval, or at once
// on a wake. `onProgress` hears of each page that brings lines or a new
// state. The state and the place in the log are kept for as long as the
// run and the levels are the same, so a change to the card (a save) picks
// the log up where the log was.
function automationRunLog(
  owner: object,
  args: () => {
    realm: string | undefined;
    runId: string;
    tools: Tools | undefined;
    levels: RunLogLevel[];
    onProgress: () => void;
  },
) {
  let kept:
    | {
        key: string;
        state: RunLogState;
        after: number;
        endedReads: number;
        done: boolean;
      }
    | undefined;
  return use(
    owner,
    resource(({ on }) => {
      let { realm, runId, tools, levels, onProgress } = args();
      let key = `${realm}|${runId}|${levels.join(',')}`;
      if (!kept || kept.key !== key) {
        kept = {
          key,
          state: new TrackedObject<RunLogState>({
            loading: true,
            failure: undefined,
            runState: undefined,
            lines: [],
            dropped: 0,
          }),
          after: -1,
          endedReads: 0,
          done: false,
        };
      }
      let current = kept;
      let state = current.state;
      if (!realm || !tools || levels.length === 0 || current.done) {
        state.loading = false;
        return state;
      }
      let stopped = false;
      let woken = false;
      let timer: ReturnType<typeof setTimeout> | undefined;
      let wakeUp: (() => void) | undefined;
      let wait = (wakeable: boolean) =>
        new Promise<void>((settle) => {
          if (wakeable && woken) {
            woken = false;
            settle();
            return;
          }
          let done = () => {
            clearTimeout(timer);
            wakeUp = undefined;
            settle();
          };
          timer = setTimeout(done, RUN_LOG_FOLLOW_MS);
          if (wakeable) {
            wakeUp = done;
          }
        });
      let follow = async () => {
        await Promise.resolve();
        while (!stopped) {
          woken = false;
          let answer: ReadRunAnswer | undefined;
          try {
            answer = await readRun(tools, {
              realm,
              run: runId,
              read: 'log',
              after: current.after,
              limit: RUN_LOG_PAGE,
              levels,
            });
          } catch {
            answer = undefined;
          }
          if (stopped) {
            return;
          }
          state.loading = false;
          let page = answer?.ok
            ? (answer.body.data?.attributes as
                | {
                    state: RunState;
                    lines: RunLogLine[];
                    next: number;
                    more: boolean;
                    dropped: number;
                  }
                | undefined)
            : undefined;
          if (!page) {
            if (refused(answer)) {
              state.failure = 'refused';
              current.done = true;
              return;
            }
            state.failure = 'unreachable';
            await wait(true);
            continue;
          }
          state.failure = undefined;
          let moved = page.lines.length > 0 || page.state !== state.runState;
          if (page.lines.length > 0) {
            state.lines = [...state.lines, ...page.lines];
          }
          state.dropped = page.dropped;
          state.runState = page.state;
          current.after = page.next;
          if (moved) {
            onProgress();
          }
          if (page.more) {
            continue;
          }
          if (page.state === 'pending' || page.state === 'running') {
            await wait(true);
            continue;
          }
          if (current.endedReads > 0) {
            // The trailing read: the run's charges land after the run's
            // last event, so the report reads once more too.
            onProgress();
            current.done = true;
            return;
          }
          current.endedReads++;
          await wait(false);
        }
      };
      follow();
      let unsubscribe = subscribeToRealm(realm, (event) => {
        if (event.eventName === 'job' && event.runId === runId) {
          if (wakeUp) {
            wakeUp();
          } else {
            woken = true;
          }
        }
      });
      on.cleanup(() => {
        stopped = true;
        clearTimeout(timer);
        unsubscribe?.();
      });
      return state;
    }),
  );
}

// The log's levels, most severe first. The filter shows a level and every
// level more severe than it, as log filters do: Warnings shows warnings and
// errors, and All shows every line.
const LOG_LEVELS: { value: RunLogLevel; label: string }[] = [
  { value: 'error', label: 'Errors' },
  { value: 'warn', label: 'Warnings' },
  { value: 'info', label: 'Info' },
  { value: 'log', label: 'All' },
];
function levelsFrom(least: RunLogLevel): RunLogLevel[] {
  let index = LOG_LEVELS.findIndex(({ value }) => value === least);
  return LOG_LEVELS.slice(0, index + 1).map(({ value }) => value);
}
const LEVEL_LOOKS: Record<RunLogLevel, { label: string; tone: RunTone }> = {
  error: { label: 'Error', tone: 'danger' },
  warn: { label: 'Warning', tone: 'warning' },
  info: { label: 'Info', tone: 'info' },
  log: { label: 'Log', tone: 'neutral' },
};
// The most log lines the console lists at first: the latest ones, since the
// latest say what the run did last. A button lists earlier lines a batch at
// a time, so a long log never renders whole at once.
const SHOWN_LOG_LINES = 200;
const EARLIER_LOG_LINES = 500;

// A time of a run, to the second, in the viewer's own time zone, which one
// line at the top of an opened run names.
const RUN_CLOCK = new Intl.DateTimeFormat('en-US', {
  hour: 'numeric',
  minute: '2-digit',
  second: '2-digit',
});
function runClock(at: string | number): string {
  return RUN_CLOCK.format(new Date(at));
}
function msBetween(from: string | null, to: string | null): number | undefined {
  return from && to ? Date.parse(to) - Date.parse(from) : undefined;
}

// The run's steps, in order: Boxel admits the run, the script runs, and
// Boxel commits the files the script staged. The script's step holds the
// run milestones. A step another part of a run needs, such as the batches
// of AI requests a batched run waits on, goes into `RUN_STEPS` between the
// script and the commit.
const RUN_STEPS: {
  step: NonNullable<ListedRun['step']>;
  name: string;
}[] = [
  { step: 'admission', name: 'Admission' },
  { step: 'script', name: 'Script' },
  { step: 'commit', name: 'Commit' },
];

function runStepRows(
  run: ListedRun,
  report: RunReport | undefined,
): MilestoneRow[] {
  let reached = RUN_STEPS.findIndex(({ step }) => step === run.step);
  let timings = report?.timings;
  // A run canceled while waiting, or one Boxel ended because the run's job
  // was lost, ended before any attempt started the run: the run stopped at
  // admission.
  let endedUnstarted =
    reached < 0 && (run.state === 'error' || run.state === 'canceled');
  if (endedUnstarted) {
    reached = 0;
  }
  return RUN_STEPS.map(({ step, name }, index) => {
    let state: MilestoneState =
      reached < 0 || index > reached
        ? 'not-started'
        : index < reached
          ? 'reached'
          : run.state === 'running'
            ? 'running'
            : run.state === 'error'
              ? 'failed'
              : run.state === 'canceled'
                ? 'stopped'
                : 'reached';
    let look = MILESTONE_LOOKS[state];
    let badge = look.badge;
    let detail: string | undefined;
    if (step === 'admission') {
      if (endedUnstarted) {
        detail = 'The run ended before Boxel started the run.';
      } else if (run.state === 'pending') {
        detail = 'Waiting to start';
      } else if (run.startedAt) {
        let waited = msBetween(run.createdAt, run.startedAt);
        detail = `Started ${runClock(run.startedAt)}${
          waited === undefined ? '' : ` · Waited ${durationText(waited)}`
        }`;
      }
    } else if (step === 'script') {
      if (state !== 'not-started' && !run.milestones?.milestones.length) {
        detail = 'The script reported no milestones on the run.';
      }
    } else if (run.startedBy === 'preview' && run.state === 'complete') {
      badge = 'Skipped';
      detail = 'A Preview saves nothing, so Boxel skipped the commit.';
    } else if (timings?.commitMs != null) {
      detail = `Took ${durationText(timings.commitMs)}`;
    }
    return {
      id: step,
      key: `${run.id}:${step}`,
      name,
      state,
      badge,
      tone: look.tone,
      detail,
      tasks: [],
    };
  });
}

const CREDIT_KINDS: { kind: string; label: string }[] = [
  { kind: 'run', label: 'Compute and network' },
  { kind: 'ai', label: 'AI requests' },
  { kind: 'batched_ai', label: 'Batched AI requests' },
  { kind: 'run_indexing', label: 'Indexing the saved files' },
];

function credits(n: number): string {
  return n.toLocaleString('en-US', { maximumFractionDigits: 2 });
}

// One opened run: the run's steps, with the script's milestones inside the
// script's step, then the run's log, calls, writes, and cost, a tab each.
// Everything reads live while the run goes.
class RunDetail extends GlimmerComponent<{
  Args: {
    run: ListedRun;
    realm: string | undefined;
    // The automation card's id, whose storage the run adds to.
    automation: string | undefined;
    // The per-run limits the automation sets, which the Limits tab measures
    // the run against.
    caps: AutomationCaps | undefined;
    tools: Tools | undefined;
    // The automation's run before this one, whose milestone times the
    // milestones read against.
    previous: LastRun | undefined;
  };
}> {
  // A row's run is the same run for as long as the row is open.
  private runId = this.args.run.id;
  @tracked tab = 'log';
  // The least severe level the log shows; every more severe level shows too.
  @tracked leastLevel: RunLogLevel = 'log';
  get levels(): RunLogLevel[] {
    return levelsFrom(this.leastLevel);
  }
  @tracked shownLineCount = SHOWN_LOG_LINES;

  private reportResource = automationRunReport(this, () => ({
    realm: this.args.realm,
    runId: this.runId,
    tools: this.args.tools,
  }));
  private logResource = automationRunLog(this, () => ({
    realm: this.args.realm,
    runId: this.runId,
    tools: this.args.tools,
    levels: this.levels,
    onProgress: () => {
      this.reportResource.current.reread();
      this.storageResource.current.reread();
    },
  }));
  private storageResource = automationStorage(this, () => ({
    realm: this.args.realm,
    automation: this.args.automation,
    tools: this.args.tools,
  }));

  get report() {
    return this.reportResource.current.state.report;
  }
  // Why the run's details didn't read, while no earlier read shows them.
  get reportFailure() {
    return this.report ? undefined : this.reportResource.current.state.failure;
  }
  get log() {
    return this.logResource.current;
  }
  get steps() {
    return runStepRows(this.args.run, this.report);
  }
  // Once the run reaches its commit the script is over, so every milestone
  // the script reached is finished. The commit's own step says how the run
  // ended, which the server's milestones would otherwise also pin on the
  // last milestone.
  get milestoneRows() {
    let { milestones, step } = this.args.run;
    if (!milestones) {
      return [];
    }
    return runMilestoneRows(
      step === 'commit'
        ? { ...milestones, state: 'complete', failedIn: null, current: null }
        : milestones,
      this.args.previous,
    );
  }
  // One serial timeline: admission, then the script's milestones in the
  // order the script runs them (the ones ahead included), then the steps
  // after the script. The script shows as a step of its own only when the
  // run has no milestones to stand for the script.
  get timelineRows(): MilestoneRow[] {
    let milestones = this.milestoneRows;
    let rows = this.steps.flatMap((row) =>
      row.id === 'script' && milestones.length > 0 ? milestones : [row],
    );
    // An ended run says when the run ended, and how long the run took from
    // start to finish, on the row where the run ended.
    let { run } = this.args;
    if (run.finishedAt) {
      let last = -1;
      rows.forEach((row, index) => {
        if (row.state !== 'not-started' && row.badge !== 'Skipped') {
          last = index;
        }
      });
      if (last >= 0) {
        let took = msBetween(run.startedAt, run.finishedAt);
        let end = `${run.state === 'complete' ? 'Finished' : 'Ended'} ${runClock(
          run.finishedAt,
        )}${took === undefined ? '' : ` · ${durationText(took)} in all`}`;
        let row = rows[last];
        rows[last] = {
          ...row,
          detail: row.detail ? `${row.detail} · ${end}` : end,
        };
      }
    }
    return rows;
  }
  // The viewer's own time zone, which every time of the run reads in.
  get timeZone() {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
  }
  get running() {
    return (
      this.args.run.state === 'pending' || this.args.run.state === 'running'
    );
  }
  get tabs() {
    return [
      { value: 'log', label: 'Log' },
      { value: 'calls', label: 'Calls' },
      { value: 'writes', label: 'Writes' },
      { value: 'cost', label: 'Cost' },
      { value: 'limits', label: 'Limits' },
    ];
  }
  showTab = (tab: string) => (this.tab = tab);

  // Each level's count. The report counts only the lines that store a level,
  // while the log's level filter reads a line with no level (a milestone, a
  // task, most of Boxel's own lines) as info, so info is every line the
  // other levels don't count.
  get levelOptions() {
    let log = this.report?.log;
    let counts: Partial<Record<RunLogLevel, number>> = {};
    if (log) {
      let { byLevel } = log;
      counts = {
        log: byLevel.log ?? 0,
        warn: byLevel.warn ?? 0,
        error: byLevel.error ?? 0,
      };
      counts.info = Math.max(
        log.lines - counts.log! - counts.warn! - counts.error!,
        0,
      );
    }
    // Each option counts the lines the option shows: its level and every
    // more severe one.
    return LOG_LEVELS.map(({ value, label }) => {
      let n = log
        ? levelsFrom(value).reduce(
            (sum, level) => sum + (counts[level] ?? 0),
            0,
          )
        : undefined;
      return {
        value,
        label: n === undefined ? label : `${label} (${tally(n)})`,
      };
    });
  }
  showLevels = (value: string) => {
    this.leastLevel = value as RunLogLevel;
    this.shownLineCount = SHOWN_LOG_LINES;
  };
  get shownLines(): RunLogLine[] {
    return this.log.lines.slice(-this.shownLineCount);
  }
  get earlierLines() {
    return Math.min(
      Math.max(this.log.lines.length - this.shownLineCount, 0),
      EARLIER_LOG_LINES,
    );
  }
  get earlierLinesLabel() {
    let n = this.earlierLines;
    return `Show ${tally(n)} earlier ${n === 1 ? 'line' : 'lines'}`;
  }
  showEarlierLines = () => (this.shownLineCount += EARLIER_LOG_LINES);
  get droppedSentence() {
    let n = this.log.dropped;
    return `Boxel didn’t keep ${tally(n)} more ${
      n === 1 ? 'line' : 'lines'
    }: a run’s log holds at most 10,000 lines and 5,000,000 characters.`;
  }
  lineTime = (line: RunLogLine) => runClock(line.at);
  lineLook = (line: RunLogLine) => LEVEL_LOOKS[line.level ?? 'info'];
  lineSource = (line: RunLogLine) =>
    line.source === 'script' ? 'Script' : 'Boxel';
  lineNumber = (line: RunLogLine) =>
    line.scriptLine === undefined ? undefined : `line ${line.scriptLine}`;

  // A call's time, to the millisecond below a second, since most calls
  // take less than one.
  callTime = (ms: number | undefined) =>
    ms === undefined
      ? '—'
      : ms < 1000
        ? `${Math.round(ms)} ms`
        : durationText(ms);
  callStatus = (call: RunCallApiCall): { label: string; tone: RunTone } =>
    call.status !== undefined
      ? {
          label: String(call.status),
          tone: call.status < 400 ? 'success' : 'danger',
        }
      : {
          label: call.code === 'failed' ? 'Failed' : 'Refused',
          tone: 'danger',
        };
  tokens = (call: RunResolveCall) =>
    call.inputTokens === undefined && call.outputTokens === undefined
      ? '—'
      : `${tally(call.inputTokens ?? 0)} in · ${tally(call.outputTokens ?? 0)} out`;
  resolveStatus = (call: RunResolveCall): { label: string; tone: RunTone } =>
    call.status === undefined
      ? { label: 'No answer', tone: 'danger' }
      : {
          label: String(call.status),
          tone: call.status < 400 ? 'success' : 'danger',
        };

  get writesSentence() {
    let report = this.report;
    if (!report) {
      return undefined;
    }
    let { writes, dryRun, state } = report;
    if (dryRun) {
      if (state === 'pending' || state === 'running') {
        return 'A Preview stages the files the script writes, and keeps the files once the Preview completes. A Preview saves nothing to the workspace.';
      }
      if (state !== 'complete') {
        return 'The Preview ended before completing, so Boxel kept none of the files the script staged.';
      }
      if (writes.stagedReplacedBy) {
        return 'A later Preview of the automation replaced the files this Preview staged.';
      }
      return writes.staged?.length
        ? `The Preview staged ${tally(writes.staged.length)} ${
            writes.staged.length === 1 ? 'file' : 'files'
          }, and saved nothing to the workspace.`
        : 'The script staged no files.';
    }
    if (writes.committed) {
      return `The run saved ${tally(writes.count)} ${
        writes.count === 1 ? 'file' : 'files'
      } to the workspace.`;
    }
    if (writes.count > 0) {
      return `The run saved ${tally(writes.count)} ${
        writes.count === 1 ? 'file' : 'files'
      } to the workspace. The run’s log reached the log’s limit before the log named the files.`;
    }
    return state === 'complete'
      ? 'The run saved no files.'
      : state === 'pending' || state === 'running'
        ? 'The run saves the files the script writes once the script finishes.'
        : 'The run saved no files: the run ended before the commit.';
  }

  get storage() {
    return this.storageResource.current.state.storage;
  }
  // The run's charges as a receipt: one line per kind of charge, and a
  // total that is the sum of the lines, so the total reads as their sum.
  get receiptColumns(): StatementColumn[] {
    return [
      { key: 'charge', label: 'Charge' },
      {
        key: 'credits',
        label: 'Boxel Credits',
        kind: 'number',
        digits: this.receiptDigits,
        width: '8rem',
      },
    ];
  }
  get receiptLines(): { key: string; label: string; credits: number }[] {
    let byKind = this.report?.cost.creditsByKind ?? {};
    let lines = CREDIT_KINDS.map(({ kind, label }) => ({
      key: kind,
      label,
      credits: byKind[kind] ?? 0,
    }));
    let named = new Set(CREDIT_KINDS.map(({ kind }) => kind));
    let other = Object.entries(byKind)
      .filter(([kind]) => !named.has(kind))
      .reduce((sum, [, credits]) => sum + credits, 0);
    if (other) {
      lines.push({ key: 'other', label: 'Other charges', credits: other });
    }
    return lines;
  }
  get receiptDigits() {
    return this.receiptLines.every(({ credits }) => Number.isInteger(credits))
      ? 0
      : 2;
  }
  get receiptRows(): StatementRow[] {
    let lines = this.receiptLines;
    let total = lines.reduce((sum, { credits }) => sum + credits, 0);
    return [
      ...lines.map(({ key, label, credits }) => ({
        key,
        cells: { charge: label, credits },
        data: { testAutomationRunCharge: key },
      })),
      {
        key: 'total',
        role: 'total' as const,
        cells: { charge: 'Total charged for the run', credits: total },
        data: { testAutomationRunCharge: 'total' },
      },
    ];
  }
  // What the run adds to the automation's storage: the files the run created
  // that still exist, and their size on disk and in the index.
  get runStorage() {
    let files = (this.storage?.files ?? []).filter(
      (file) => file.run === this.args.run.id,
    );
    return {
      count: files.length,
      bytes: files.reduce(
        (sum, file) => sum + file.fileBytes + file.indexBytes,
        0,
      ),
    };
  }
  get storageBytes() {
    let storage = this.storage;
    return storage ? storage.fileBytes + storage.indexBytes : 0;
  }
  // A day of storage for every file the automation's runs keep, margin
  // included, as the server prices the daily storage charge, to two
  // significant figures: a few small files cost a small fraction of a credit
  // a day.
  get dailyStorageCredits() {
    let credits = this.storage?.dailyCredits;
    return credits == null
      ? undefined
      : credits.toLocaleString('en-US', { maximumSignificantDigits: 2 });
  }
  get heldCredits() {
    let held = this.report?.cost.aiCreditsReserved ?? 0;
    return held > 0 ? credits(held) : undefined;
  }
  plural = (n: number, one: string, many: string) =>
    `${tally(n)} ${n === 1 ? one : many}`;
  // What the run adds to the automation's storage, what the automation's
  // runs keep in all, and what a day of that storage costs.
  get storageSentence() {
    let storage = this.storage;
    if (!storage) {
      return 'Boxel is reading the automation’s storage.';
    }
    let { count, bytes: runBytes } = this.runStorage;
    let sentences = [
      count === 1
        ? `The run saved 1 file (${bytes(runBytes)}) that still exists.`
        : count > 1
          ? `The run saved ${count} files (${bytes(runBytes)}) that still exist.`
          : 'The run added no files the automation keeps.',
      `The automation’s runs keep ${this.plural(
        storage.files.length,
        'file',
        'files',
      )} in all (${bytes(this.storageBytes)}).`,
    ];
    if (this.dailyStorageCredits) {
      sentences.push(
        `A day of storage for those files costs ${this.dailyStorageCredits} credits.`,
      );
    }
    return sentences.join(' ');
  }
  // How far the run went toward each limit the automation sets for a run, in
  // the order the card's limits list them. A limit the card leaves unset
  // reads as no limit; a limit of 0 allows none of that use.
  get limitRows(): {
    key: string;
    label: string;
    text: string;
    value: number;
    max: number;
    hue: string | undefined;
    reached: boolean;
  }[] {
    let report = this.report;
    if (!report) {
      return [];
    }
    let { cost, timings } = report;
    let caps = this.args.caps;
    let ranMs =
      timings.runMs ??
      (this.args.run.startedAt
        ? Date.now() - Date.parse(this.args.run.startedAt)
        : 0);
    let used: Record<string, number> = {
      callApiCalls: cost.callApiCalls,
      responseBytes: cost.callApiResponseBytes,
      writes: cost.writes,
      resolveCalls: cost.resolveCalls,
      aiCredits: cost.aiCreditsSpent,
      seconds: Math.round(ranMs / 1000),
    };
    let show = (key: string, n: number) =>
      key === 'responseBytes'
        ? bytes(n)
        : key === 'seconds'
          ? durationText(n * 1000)
          : key === 'aiCredits'
            ? `${tally(n)} ${n === 1 ? 'credit' : 'credits'}`
            : tally(n);
    return RUN_LIMITS.map(({ key, label }) => {
      let n = used[key] ?? 0;
      let cap = caps?.[key as keyof AutomationCaps] as
        | number
        | null
        | undefined;
      let limited = typeof cap === 'number';
      let limit = limited ? (cap as number) : 0;
      let share = limit > 0 ? n / limit : n > 0 ? 1 : 0;
      let reached = limited && n >= limit && (limit > 0 || n > 0);
      return {
        key,
        label,
        text: !limited
          ? `${show(key, n)}, no limit set`
          : limit === 0
            ? n > 0
              ? `${show(key, n)} of none allowed`
              : 'None allowed'
            : `${key === 'aiCredits' ? tally(n) : show(key, n)} of ${show(
                key,
                limit,
              )}`,
        value: limit > 0 ? Math.min(n, limit) : reached ? 1 : 0,
        max: limit > 0 ? limit : 1,
        hue: reached
          ? 'var(--destructive)'
          : limited && share >= LIMIT_NEAR_SHARE
            ? 'var(--warning)'
            : undefined,
        reached,
      };
    });
  }

  <template>
    <div class='run-detail' data-test-automation-run-timeline={{@run.id}}>
      <p class='run-detail__note' data-test-automation-run-time-zone>
        All times are in the local time zone,
        {{this.timeZone}}.
      </p>
      <div data-test-automation-run-milestones>
        <MilestoneTimeline
          @rows={{this.timelineRows}}
          @label='Timeline of the run'
        />
      </div>

      {{#if (eq this.reportFailure 'refused')}}
        <Callout
          @tone='warning'
          @title='Only a realm administrator can read the run’s details'
          data-test-automation-run-report-failed='refused'
        />
      {{else if this.reportFailure}}
        <Callout
          @tone='warning'
          @title='Boxel couldn’t read the run’s details'
          data-test-automation-run-report-failed='unreachable'
        >
          Boxel tries again every few seconds.
        </Callout>
      {{/if}}

      <Tabs
        @options={{this.tabs}}
        @value={{this.tab}}
        @onValueChange={{this.showTab}}
        data-test-automation-run-tabs
      >
        <:default as |tab|>
          {{#if (eq tab 'log')}}
            <div class='run-detail__panel' data-test-automation-run-log>
              <div class='run-detail__levels'>
                <SegmentedControl
                  @label='Lines to show'
                  @options={{this.levelOptions}}
                  @value={{this.leastLevel}}
                  @onValueChange={{this.showLevels}}
                  data-test-automation-run-log-levels
                />
                <span class='run-detail__note'>Each level includes the more
                  severe ones.</span>
              </div>
              {{#if this.log.dropped}}
                <p
                  class='run-detail__note'
                  data-test-automation-run-log-dropped
                >
                  {{this.droppedSentence}}
                </p>
              {{/if}}
              {{#if (eq this.log.failure 'refused')}}
                <Callout
                  @tone='warning'
                  @title='Only a realm administrator can read the run’s log'
                  data-test-automation-run-log-failed='refused'
                />
              {{else if this.log.failure}}
                <Callout
                  @tone='warning'
                  @title='Boxel couldn’t read the run’s log'
                  data-test-automation-run-log-failed='unreachable'
                >
                  Boxel tries again every few seconds.
                </Callout>
              {{/if}}
              {{#if this.shownLines.length}}
                {{#if this.earlierLines}}
                  <Button
                    @appearance='link'
                    @size='s'
                    data-test-automation-run-log-earlier
                    {{on 'click' this.showEarlierLines}}
                  >{{this.earlierLinesLabel}}</Button>
                {{/if}}
                <Table @label='Lines of the run’s log' @striped={{false}}>
                  <:head>
                    <tr>
                      <th scope='col'>Time</th>
                      <th scope='col'>Level</th>
                      <th scope='col'>From</th>
                      <th scope='col'>Message</th>
                    </tr>
                  </:head>
                  <:body>
                    {{#each this.shownLines as |line|}}
                      {{#let (this.lineLook line) as |look|}}
                        <tr
                          data-test-automation-run-log-line={{line.seq}}
                          data-test-automation-run-log-level={{look.label}}
                        >
                          <td class='run-detail__time'>{{this.lineTime
                              line
                            }}</td>
                          <td>
                            <Chip
                              @label={{look.label}}
                              @tone={{look.tone}}
                              @appearance='plain'
                            />
                          </td>
                          <td>{{this.lineSource line}}</td>
                          <td class='run-detail__message'>
                            {{line.message}}
                            {{#let (this.lineNumber line) as |number|}}
                              {{#if number}}
                                <Token @value={{number}} />
                              {{/if}}
                            {{/let}}
                          </td>
                        </tr>
                      {{/let}}
                    {{/each}}
                  </:body>
                </Table>
              {{else if this.log.failure}}
                {{! The callout above says why no line shows. }}
              {{else if this.log.loading}}
                <LoadingState @label='Loading the log' />
              {{else}}
                <EmptyState
                  @size='s'
                  @texture={{false}}
                  @title='No lines'
                  @message={{if
                    this.running
                    'The run hasn’t written a line at this level yet.'
                    'The run wrote no lines at this level.'
                  }}
                  data-test-automation-run-log-empty
                />
              {{/if}}
            </div>
          {{else if (eq tab 'calls')}}
            <div class='run-detail__panel' data-test-automation-run-calls>
              {{#if this.report}}
                <h4 class='run-detail__heading'>Outside service calls</h4>
                {{#if this.report.callApiCalls.length}}
                  <Table
                    @label='Outside service calls of the run'
                    @striped={{false}}
                  >
                    <:head>
                      <tr>
                        <th scope='col'>Operation</th>
                        <th scope='col'>Status</th>
                        <th scope='col'>Time</th>
                        <th scope='col'>Size</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.report.callApiCalls as |call|}}
                        {{#let (this.callStatus call) as |status|}}
                          <tr data-test-automation-run-call={{call.seq}}>
                            <td class='run-detail__message'>
                              {{operationTitle call.operation}}
                              {{#if call.destination}}
                                <Token
                                  @value='{{call.method}} {{call.destination}}'
                                  @wrap={{true}}
                                />
                              {{/if}}
                            </td>
                            <td>
                              <Chip
                                @label={{status.label}}
                                @tone={{status.tone}}
                                @appearance='plain'
                              />
                            </td>
                            <td class='run-detail__time'>{{this.callTime
                                call.ms
                              }}</td>
                            <td>
                              {{#if call.bytes}}
                                <FormatBytes
                                  @value={{call.bytes}}
                                  @base='decimal'
                                />
                              {{else}}
                                —
                              {{/if}}
                            </td>
                          </tr>
                        {{/let}}
                      {{/each}}
                    </:body>
                  </Table>
                {{else}}
                  <EmptyState
                    @size='s'
                    @texture={{false}}
                    @title='No outside service calls'
                    @message='The script called no outside service.'
                    data-test-automation-run-no-calls
                  />
                {{/if}}
                <h4 class='run-detail__heading'>AI requests</h4>
                {{#if this.report.resolveCalls.length}}
                  <Table @label='AI requests of the run' @striped={{false}}>
                    <:head>
                      <tr>
                        <th scope='col'>Model</th>
                        <th scope='col'>Status</th>
                        <th scope='col'>Tokens</th>
                        <th scope='col'>Time</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.report.resolveCalls as |call|}}
                        {{#let (this.resolveStatus call) as |status|}}
                          <tr data-test-automation-run-resolve={{call.seq}}>
                            <td class='run-detail__message'>
                              {{#if call.model}}
                                <Token @value={{call.model}} @wrap={{true}} />
                              {{else}}
                                —
                              {{/if}}
                            </td>
                            <td>
                              <Chip
                                @label={{status.label}}
                                @tone={{status.tone}}
                                @appearance='plain'
                              />
                            </td>
                            <td
                              class='run-detail__time'
                              data-test-automation-run-resolve-tokens
                            >{{this.tokens call}}</td>
                            <td class='run-detail__time'>{{this.callTime
                                call.ms
                              }}</td>
                          </tr>
                        {{/let}}
                      {{/each}}
                    </:body>
                  </Table>
                {{else}}
                  <EmptyState
                    @size='s'
                    @texture={{false}}
                    @title='No AI requests'
                    @message='The script made no AI requests.'
                    data-test-automation-run-no-resolves
                  />
                {{/if}}
              {{else if this.reportFailure}}
                {{! The callout above says Boxel couldn't read the run. }}
              {{else}}
                <LoadingState @label='Loading the calls' />
              {{/if}}
            </div>
          {{else if (eq tab 'writes')}}
            <div class='run-detail__panel' data-test-automation-run-writes>
              {{#if this.report}}
                <p data-test-automation-run-writes-sentence>
                  {{this.writesSentence}}
                </p>
                {{#if this.report.writes.staged.length}}
                  <Table @label='Files the Preview staged' @striped={{false}}>
                    <:head>
                      <tr>
                        <th scope='col'>File</th>
                        <th scope='col'>Size</th>
                      </tr>
                    </:head>
                    <:body>
                      {{#each this.report.writes.staged as |file|}}
                        <tr data-test-automation-run-staged={{file.path}}>
                          <td class='run-detail__message'><Token
                              @value={{file.path}}
                              @wrap={{true}}
                            /></td>
                          <td><FormatBytes
                              @value={{file.size}}
                              @base='decimal'
                            /></td>
                        </tr>
                      {{/each}}
                    </:body>
                  </Table>
                {{/if}}
                {{#if this.report.writes.committed.length}}
                  <Table @label='Files the run saved' @striped={{false}}>
                    <:head>
                      <tr><th scope='col'>File</th></tr>
                    </:head>
                    <:body>
                      {{#each this.report.writes.committed as |path|}}
                        <tr data-test-automation-run-saved={{path}}>
                          <td class='run-detail__message'><Token
                              @value={{path}}
                              @wrap={{true}}
                            /></td>
                        </tr>
                      {{/each}}
                    </:body>
                  </Table>
                {{/if}}
              {{else if this.reportFailure}}
                {{! The callout above says Boxel couldn't read the run. }}
              {{else}}
                <LoadingState @label='Loading the writes' />
              {{/if}}
            </div>
          {{else if (eq tab 'limits')}}
            <div class='run-detail__panel' data-test-automation-run-limits>
              {{#if this.report}}
                <p class='run-detail__note'>
                  How far the run went toward each limit the automation sets for
                  a run. Boxel stops a run that tries to go past a limit.
                </p>
                <ul class='run-detail__limits'>
                  {{#each this.limitRows as |limit|}}
                    <li
                      class='run-detail__limit'
                      data-test-automation-run-limit={{limit.key}}
                      data-test-automation-run-limit-reached={{if
                        limit.reached
                        'true'
                      }}
                    >
                      <span class='run-detail__limit-head'>
                        <span
                          class='run-detail__limit-name'
                        >{{limit.label}}</span>
                        <span
                          class='run-detail__limit-text'
                        >{{limit.text}}</span>
                      </span>
                      <ProgressBar
                        @value={{limit.value}}
                        @max={{limit.max}}
                        @hue={{limit.hue}}
                        @steps={{false}}
                        @valueText={{limit.text}}
                        aria-label={{limit.label}}
                      />
                    </li>
                  {{/each}}
                </ul>
              {{else if this.reportFailure}}
                {{! The callout above says Boxel couldn't read the run. }}
              {{else}}
                <LoadingState @label='Loading the limits' />
              {{/if}}
            </div>
          {{else}}
            <div class='run-detail__panel' data-test-automation-run-cost>
              {{#if this.report}}
                <h4 class='run-detail__heading'>Charges for the run</h4>
                <StatementTable
                  @columns={{this.receiptColumns}}
                  @rows={{this.receiptRows}}
                  @label='Charges for the run'
                  @zero='show'
                  @density='compact'
                  data-test-automation-run-receipt
                />
                {{#unless this.report.dryRun}}
                  <p
                    class='run-detail__note'
                    data-test-automation-run-indexing-note
                  >
                    Boxel charges for indexing the saved files once Boxel
                    finishes indexing the files, which can come after the run
                    ends.
                  </p>
                {{/unless}}
                {{#if this.heldCredits}}
                  <p class='run-detail__note' data-test-automation-run-held>
                    Boxel also holds
                    {{this.heldCredits}}
                    credits for AI answers still to come. Boxel charges what the
                    answers cost once the answers arrive, and the hold goes
                    away.
                  </p>
                {{/if}}

                <h4 class='run-detail__heading'>Storage, charged daily</h4>
                <p data-test-automation-run-storage>
                  {{this.storageSentence}}
                </p>
                <Callout
                  @tone='info'
                  @title='How Boxel charges for storage'
                  data-test-automation-run-storage-rules
                >
                  <ul class='run-detail__rules'>
                    <li>Storage isn’t part of any one run’s total. Boxel charges
                      the automation’s payer once a day for every file the
                      automation’s runs created that still exists, and for the
                      files’ entries in the workspace’s search index.</li>
                    <li>Boxel charges every day the automation is switched on,
                      including while the automation is paused or done. Removing
                      the automation, or deleting the files, stops the charge.</li>
                    <li>Boxel charges whole credits: the daily amounts add up,
                      and Boxel charges the days together once the days cost at
                      least 1 credit.</li>
                    <li>A Preview saves no files, so a Preview adds no storage.</li>
                  </ul>
                </Callout>

              {{else if this.reportFailure}}
                {{! The callout above says Boxel couldn't read the run. }}
              {{else}}
                <LoadingState @label='Loading the cost' />
              {{/if}}
            </div>
          {{/if}}
        </:default>
      </Tabs>
    </div>
    <style scoped>
      .run-detail {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .run-detail__panel {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding-block-start: var(--boxel-sp-xs);
        min-width: 0;
      }
      .run-detail__heading {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      /* A section after the first starts clear of the one above it. */
      .run-detail__heading:not(:first-child) {
        margin-block-start: var(--boxel-sp-sm);
      }
      .run-detail__note {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .run-detail__levels {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .run-detail__limits {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        margin: 0;
        padding: 0;
        list-style: none;
        max-inline-size: 34rem;
      }
      .run-detail__limit {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
      }
      .run-detail__limit-head {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .run-detail__limit-name {
        font-weight: 600;
      }
      .run-detail__limit-text {
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .run-detail__rules {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        margin: 0;
        padding-inline-start: var(--boxel-sp-lg);
      }
      .run-detail__time {
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      .run-detail__message {
        min-width: 0;
        overflow-wrap: break-word;
      }
    </style>
  </template>
}

// The automation's runs, for the realm's direct writers: one row per run,
// newest first, with what started the run, the run's state, and why a run
// that didn't complete ended as the run did. A later slot of a schedule that
// came due before the schedule's run had started, and joined that run, shows
// as its own row above the run. Runs are listed a page at a time, from the
// moment a trigger fires. Shows nothing to anyone else.
class AutomationRuns extends GlimmerComponent<{
  Args: {
    runs: RunsState;
    showPage: (page: number) => void;
    // The kind of each trigger the card declares, by label.
    triggerKind: (label: string | null) => string | undefined;
    // What an opened run reads its details with, and the limits the run is
    // measured against.
    realm: string | undefined;
    automation: string | undefined;
    caps: AutomationCaps | undefined;
    tools: Tools | undefined;
  };
}> {
  get rows() {
    return runRows(this.args.runs.runs);
  }
  // The automation's run before `run` on the page shown that started and
  // ended, leaving Previews out as the automation's last run does, and
  // leaving out a run admission refused: the run whose milestone times an
  // opened run's milestones read against.
  previousRun = (run: ListedRun): LastRun | undefined => {
    let runs = this.args.runs.runs;
    let index = runs.findIndex(({ id }) => id === run.id);
    return (
      runs.slice(index + 1).find(
        (earlier) =>
          earlier.startedBy !== 'preview' &&
          earlier.startedAt !== null &&
          earlier.finishedAt !== null &&
          // A run admission refused never ran the script, so the run
          // has no milestone times to read against.
          !(earlier.state === 'error' && earlier.step === 'admission'),
      )?.milestones ?? undefined
    );
  };
  rowKey = (row: RunRow) => row.key;
  // Each row's accessible name, which names the row's expander and detail:
  // with the slot's time, or, for a run that served no slot, the time the
  // run was made, so rows of one trigger read apart.
  rowLabel = (row: RunRow) => {
    if (row.skipped) {
      return `Skipped ${row.skipped.trigger} slot for ${rowTime(row.skipped.slot)}`;
    }
    let slot = slotTime(row.run.slot);
    let when = slot
      ? `for ${rowTime(slot)}`
      : `made ${rowTime(row.run.createdAt)}`;
    return `${this.startedBy(row.run)} run ${when}, ${runLook(row.run).label}`;
  };
  startedBy = (run: ListedRun): string => {
    switch (run.startedBy) {
      case 'preview':
        return 'Preview';
      case 'run-now':
        return 'Run now';
      default:
        return run.trigger || 'Unnamed trigger';
    }
  };
  // What fired the run, under its name.
  firedBy = (run: ListedRun): string => {
    switch (run.startedBy) {
      case 'preview':
        return 'Someone previewed the script: a Preview saves nothing.';
      case 'run-now':
        return 'Someone ran the automation by hand.';
    }
    let kind = this.args.triggerKind(run.trigger);
    if (kind === 'webhook') {
      return 'A webhook delivery fired the run.';
    }
    return slotTime(run.slot)
      ? kind === 'once'
        ? 'The one-time trigger fired the run for'
        : 'The schedule fired the run for'
      : 'The trigger fired the run.';
  };
  look = (run: ListedRun) => runLook(run);
  // The run ahead of a waiting run in the automation's queue, when one is.
  aheadOf = (run: ListedRun) =>
    run.waitingFor?.kind === 'run' ? run.waitingFor : undefined;
  // Whether the run is in its admission checks: an attempt started the run
  // and checks that the run may start before the script runs.
  admitting = (run: ListedRun) =>
    run.state === 'running' && run.step === 'admission';
  // The name a run goes by in a sentence: its trigger's label, or Preview or
  // Run now.
  runName = (run: Pick<ListedRun, 'startedBy' | 'trigger'>): string => {
    switch (run.startedBy) {
      case 'preview':
        return 'Preview';
      case 'run-now':
        return 'Run now';
      default:
        return run.trigger || 'unnamed trigger';
    }
  };
  progress = (run: ListedRun) => runProgress(run);
  reason = (run: ListedRun) => runReason(run);
  slotTime = (slot: string | null) => slotTime(slot);
  // When the row's run last moved: when the run ended, started, or was made.
  when = (run: ListedRun) => run.finishedAt ?? run.startedAt ?? run.createdAt;
  showPage = (page: number) => this.args.showPage(page);

  <template>
    {{#if @runs.failed}}
      <Callout
        @tone='warning'
        @title='Boxel couldn’t read the runs'
        data-test-automation-runs-failed
      >
        Boxel reads the runs again the next time a run moves.
      </Callout>
    {{/if}}
    {{#if this.rows.length}}
      <List
        @items={{this.rows}}
        @key={{this.rowKey}}
        @rowLabel={{this.rowLabel}}
        @label='Runs of the automation'
        @bordered={{true}}
        @busy={{@runs.paging}}
        data-test-automation-runs
      >
        <:item as |row|>
          {{#if row.skipped}}
            <Item
              @size='s'
              @wrap={{true}}
              @alignStart={{true}}
              data-test-automation-skipped={{row.skipped.slot}}
            >
              <:leading>
                <span class='runs__state'>
                  <Chip @label='Skipped' @tone='neutral' />
                </span>
              </:leading>
              <:title>{{row.skipped.trigger}}</:title>
              <:description>
                Boxel started no run for the
                <FormatDate
                  @date={{row.skipped.slot}}
                  @month='short'
                  @day='numeric'
                  @hour='numeric'
                  @minute='2-digit'
                />
                slot because the
                {{this.startedBy row.run}}
                run
                {{#let (this.slotTime row.run.slot) as |runSlot|}}
                  {{#if runSlot}}
                    for
                    <FormatDate
                      @date={{runSlot}}
                      @month='short'
                      @day='numeric'
                      @hour='numeric'
                      @minute='2-digit'
                    />
                  {{/if}}
                {{/let}}
                hadn’t started yet. The slot joined that run.
              </:description>
              <:trailing>
                <RelativeTime @date={{row.skipped.at}} @now={{@runs.readAt}} />
              </:trailing>
            </Item>
          {{else}}
            {{#let (this.look row.run) (this.reason row.run) as |look reason|}}
              <Item
                @size='s'
                @wrap={{true}}
                @alignStart={{true}}
                data-test-automation-run={{row.run.id}}
                data-test-automation-run-state={{look.label}}
              >
                <:leading>
                  <span class='runs__state'>
                    <Chip @label={{look.label}} @tone={{look.tone}} />
                  </span>
                </:leading>
                <:title>{{this.startedBy row.run}}</:title>
                <:description>
                  {{this.firedBy row.run}}
                  {{#let (this.slotTime row.run.slot) as |runSlot|}}
                    {{#if runSlot}}
                      <FormatDate
                        @date={{runSlot}}
                        @month='short'
                        @day='numeric'
                        @hour='numeric'
                        @minute='2-digit'
                      />
                    {{/if}}
                  {{/let}}
                </:description>
                <:trailing>
                  <RelativeTime
                    @date={{this.when row.run}}
                    @now={{@runs.readAt}}
                  />
                </:trailing>
                <:default>
                  {{#if row.run.waitingFor}}
                    <p
                      class='runs__reason'
                      data-test-automation-run-waiting={{row.run.waitingFor.kind}}
                    >
                      {{#let (this.aheadOf row.run) as |ahead|}}
                        {{#if ahead}}
                          Waiting for the
                          {{this.runName ahead}}
                          run
                          {{#let (this.slotTime ahead.slot) as |aheadSlot|}}
                            {{#if aheadSlot}}
                              for
                              <FormatDate
                                @date={{aheadSlot}}
                                @month='short'
                                @day='numeric'
                                @hour='numeric'
                                @minute='2-digit'
                              />
                            {{/if}}
                          {{/let}}
                          to finish first: Boxel runs one run of an automation
                          at a time.
                        {{else}}
                          Waiting for a Boxel worker.
                        {{/if}}
                      {{/let}}
                    </p>
                  {{else if (this.admitting row.run)}}
                    <p class='runs__reason' data-test-automation-run-admitting>
                      Boxel is checking that the run may start: the payer’s
                      access, the script, the outside services the automation
                      calls, and the credits.
                    </p>
                  {{/if}}
                  {{#let (this.progress row.run) as |progress|}}
                    {{#if progress}}
                      <p
                        class='runs__progress'
                        data-test-automation-run-progress
                      >{{progress}}</p>
                    {{/if}}
                  {{/let}}
                  {{#if reason}}
                    <p
                      class='runs__reason'
                      data-test-automation-run-reason={{row.run.errorReason}}
                    >
                      {{reason.text}}
                      {{#if reason.line}}
                        <Token @value={{reason.line}} />
                      {{/if}}
                    </p>
                    {{#if reason.detail}}
                      <Token
                        class='runs__detail'
                        @value={{reason.detail}}
                        @wrap={{true}}
                        data-test-automation-run-detail
                      />
                    {{/if}}
                  {{/if}}
                </:default>
              </Item>
            {{/let}}
          {{/if}}
        </:item>
        <:expanded as |row|>
          {{#if row.skipped}}
            <p class='runs__expanded-note'>
              Boxel started no run for the skipped slot, so the skipped slot has
              no milestones.
            </p>
          {{else}}
            <RunDetail
              @run={{row.run}}
              @realm={{@realm}}
              @automation={{@automation}}
              @caps={{@caps}}
              @tools={{@tools}}
              @previous={{this.previousRun row.run}}
            />
          {{/if}}
        </:expanded>
      </List>
      {{#if (gt @runs.pages 1)}}
        <Pagination
          class='runs__pager'
          @pages={{@runs.pages}}
          @page={{@runs.page}}
          @onPageChange={{this.showPage}}
          data-test-automation-runs-pager
        />
      {{/if}}
    {{else if @runs.loading}}
      <LoadingState @label='Loading runs' />
    {{else}}
      <EmptyState
        @size='s'
        @texture={{false}}
        @title='No runs yet'
        @message='A run shows here as soon as a trigger fires, or someone previews or runs the automation by hand.'
        data-test-automation-runs-empty
      />
    {{/if}}
    <style scoped>
      /* One width for the state column, so each row's title starts at the
         same place whatever the state's label. */
      .runs__state {
        display: block;
        inline-size: 7.5rem;
      }
      .runs__progress {
        margin-top: var(--boxel-sp-4xs);
        font-weight: 600;
      }
      .runs__expanded-note {
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .runs__reason {
        margin-top: var(--boxel-sp-4xs);
      }
      .runs__detail {
        margin-top: var(--boxel-sp-4xs);
      }
      .runs__pager {
        margin-top: var(--boxel-sp-sm);
      }
    </style>
  </template>
}

// What the realm server's switch-on estimate says (`GET
// /_automation-switch-on`): the monthly limit the card sets, which turning
// the automation on agrees to, what the automation is likely to cost a month,
// and who beyond the people the workspace names can read what the automation
// writes.
interface SwitchOnEstimate {
  switchedOn: boolean;
  monthlyCredits: number | null;
  estimate: {
    credits: number;
    perRun: { totalCredits: number };
    unboundedRunsPerMonth: number;
    boundedRunsPerMonth: number;
    onceRuns: number;
    webhookTriggers: string[];
    // What the viewer's latest finished Preview of the automation cost,
    // absent before the viewer's first one.
    recentPreviewCredits?: number;
  };
  // Each declared operation's key approval, with the viewer as the payer
  // before the automation is on, and with the payer once the automation is
  // on. Absent when the realm can't check.
  keyApprovals?: KeyApprovals;
}

// Who can give a key approval the automation is missing: the payer (for the
// payer's own key, or a share whose key the payer owns), the owner of the key
// a share in the realm holds, or nobody yet, when no share in the realm fills
// an `{{apiKey}}` slot.
type KeyApprover = 'payer' | 'another-key-owner' | 'nobody-yet';

// A share that can fill a slot. The realm server names the share's owner
// only to a viewer who may see that person, and null otherwise.
interface KeyApprovalShare {
  id: string;
  label: string;
  owner: string | null;
  // The share's owner resumes or swaps a suspended share before anyone can
  // approve the slot.
  suspended?: true;
}

interface OperationKeyApproval {
  operation: string;
  targetType: { module: string; name: string };
  state: 'approved' | 'missing' | 'unavailable';
  missing?: {
    slot: string;
    canApprove: KeyApprover;
    shares?: KeyApprovalShare[];
  }[];
  refusal?: { code: string; detail: string };
}

// The automation's key approvals, as the switch-on routes answer them.
interface KeyApprovals {
  approved: boolean;
  version: string;
  operations: OperationKeyApproval[];
}

// One row of the screen's key approvals: an operation, the operation's
// state, and who gives a missing approval.
interface KeyApprovalRow {
  key: string;
  title: string;
  typeName: string;
  look: { label: string; tone: 'success' | 'warning' | 'danger' | 'info' };
  detail?: string;
}

// A missing approval someone other than the payer gives: the share's key and
// the person who owns the key.
interface OtherApprover {
  label: string;
  owner: string;
}

type MissingKeyApproval = NonNullable<OperationKeyApproval['missing']>[number];

// A missing approval whose share is suspended: the share's owner resumes the
// share before anyone approves the slot.
function waitsOnSuspendedShare(missing: MissingKeyApproval): boolean {
  return (
    Boolean(missing.shares?.length) &&
    missing.shares!.every((share) => share.suspended)
  );
}

// Who a missing approval waits on most: a slot nobody can fill yet, then a
// suspended share, then one another person approves, then one the payer
// approves.
function neediestWait(
  operation: OperationKeyApproval,
): KeyApprover | 'share-suspended' | undefined {
  let missing = operation.missing ?? [];
  if (missing.some((m) => m.canApprove === 'nobody-yet')) {
    return 'nobody-yet';
  }
  if (missing.some(waitsOnSuspendedShare)) {
    return 'share-suspended';
  }
  return (['another-key-owner', 'payer'] as const).find((a) =>
    missing.some((m) => m.canApprove === a),
  );
}

function ownerName(share: KeyApprovalShare | undefined): string {
  return share?.owner ?? 'The owner of the key';
}

const APPROVAL_REREAD_MS = 4_000;

// The routes the switch-on screen calls on the realm server. Each acts as the
// signed-in person, and answers only a direct writer of the workspace.
const SWITCH_ON_ROUTE = '_automation-switch-on';
const RESUME_ROUTE = '_automation-resume';

// How long the screen waits, after writing a new monthly limit to the card,
// for the realm server to read the card with that limit.
const CAP_SAVED_WAIT_MS = 30_000;
const NO_LIMITS =
  'The automation has no limits yet. Set the limits in the automation’s editor, then turn on the automation.';
const CAP_SAVED_POLL_MS = 500;

// Whether a paused automation waits for someone to agree to what its card
// asks for beyond the payer's agreement: a limit raised above what the payer
// agreed to, or batched AI turned on. Resuming such an automation goes through the switch-on screen,
// which shows the estimate and the monthly limit again.
function needsReconfirm(status: ServerStatus | undefined): boolean {
  return (
    status?.switchedOn === true &&
    status.state === 'paused' &&
    (status.pauseReason === 'caps-raised' ||
      status.pauseReason === 'batched-ai-enabled')
  );
}

// The switch-on screen's key approvals: each declared operation with the
// operation's key approval, and what each missing approval waits for. Before
// the person confirms, the copy says what turning on does; after, the copy
// says what the automation waits for.
class SwitchOnKeyApprovals extends GlimmerComponent<{
  Args: {
    rows: KeyApprovalRow[];
    otherApprovers: OtherApprover[];
    nobodyYet: boolean;
    payerApproves: boolean;
    confirmed: boolean;
    windowFailure: string | undefined;
    onShareKey: () => void;
  };
}> {
  <template>
    {{#if @rows.length}}
      <PanelSection
        @title='Keys the automation uses'
        @collapsible={{false}}
        @level={{4}}
        data-test-automation-switch-on-keys
      >
        <Stack @gap='xs'>
          {{#each @rows as |row|}}
            <div data-test-automation-switch-on-key={{row.key}}>
              <Item @size='s' @wrap={{true}}>
                <:title>{{row.title}}</:title>
                <:description>
                  on
                  <Token @value={{row.typeName}} />
                  {{#if row.detail}}
                    <span
                      class='switch-on-keys__detail'
                      data-test-automation-switch-on-key-detail
                    >{{row.detail}}</span>
                  {{/if}}
                </:description>
                <:trailing>
                  <Chip
                    @label={{row.look.label}}
                    @tone={{row.look.tone}}
                    data-test-automation-switch-on-key-state={{row.look.label}}
                  />
                </:trailing>
              </Item>
            </div>
          {{/each}}
        </Stack>
      </PanelSection>
      {{#if @otherApprovers.length}}
        <Callout
          @tone='warning'
          @title='Another person approves a key'
          data-test-automation-switch-on-other-approvers
        >
          <ul class='switch-on-keys__list'>
            {{#each @otherApprovers as |approver|}}
              <li>{{approver.owner}}
                approves the automation’s use of the key
                <strong>{{approver.label}}</strong>.</li>
            {{/each}}
          </ul>
          {{#unless @confirmed}}
            Boxel turns on the automation now.
          {{/unless}}
          The automation waits and runs nothing until all approvals are in
          place.
        </Callout>
      {{/if}}
      {{#if @nobodyYet}}
        <Callout
          @tone='warning'
          @title='No key shared with the realm'
          data-test-automation-switch-on-no-share
        >
          <:default>
            The automation calls a service with a key that a realm administrator
            shares with the realm, and nobody has shared a key yet.
            {{#if @confirmed}}
              The automation waits and runs nothing until a realm administrator
              shares a key and the key’s owner approves the automation’s use of
              the key.
            {{else}}
              Share a key with the realm first, and then turn on the automation.
            {{/if}}
          </:default>
          <:action>
            {{#if @confirmed}}
              <Button
                @appearance='outlined'
                @size='sm'
                {{on 'click' @onShareKey}}
                data-test-automation-switch-on-share-key
              >Share a key</Button>
            {{/if}}
          </:action>
        </Callout>
      {{/if}}
      {{#if @payerApproves}}
        <Callout
          @tone='info'
          @title='You approve the keys in the same step'
          data-test-automation-switch-on-payer-approves
        >
          Turning on the automation opens Boxel’s secure window, where you
          approve the calls the automation makes with your keys. Boxel starts
          running the automation once every key approval is in place.
        </Callout>
      {{/if}}
      {{#if @windowFailure}}
        <Callout
          @tone='danger'
          @title='Boxel couldn’t open the secure window'
          data-test-automation-switch-on-window-failure
        >{{@windowFailure}}</Callout>
      {{/if}}
    {{/if}}
    <style scoped>
      .switch-on-keys__detail {
        display: block;
        margin-top: var(--boxel-sp-4xs);
      }
      .switch-on-keys__list {
        margin: var(--boxel-sp-4xs) 0;
        padding-inline-start: var(--boxel-sp-lg);
      }
    </style>
  </template>
}

// The switch-on screen. A direct writer of the workspace turns the
// automation on here and becomes the automation's payer, after reading what
// the automation is likely to cost a month and agreeing to a monthly limit.
// The same screen resumes an automation that Boxel paused because the card
// asks for more than the payer agreed to (`needsReconfirm`): whoever
// resumes it agrees to the card as it is and becomes the payer.
//
// The realm server takes the switch-on only at the monthly limit the card
// sets, so a person who picks another limit gets that limit written to the
// card first. The screen then waits for the server to read the card with the
// new limit before asking it to turn the automation on.
export class SwitchOnDialog extends GlimmerComponent<{
  Args: {
    model: Automation;
    context: CardContext | undefined;
    // The workspace's URL, as the workspace's permissions name the
    // workspace.
    realm: string | undefined;
    status: ServerStatus | undefined;
  };
}> {
  @tracked open = false;
  @tracked loading = false;
  @tracked estimate: SwitchOnEstimate | undefined;
  @tracked estimateFailure: string | undefined;
  // The monthly limit the person typed, or undefined while the person keeps
  // the card's own.
  @tracked typedCap: number | null | undefined;
  @tracked submitted = false;
  @tracked saving = false;
  @tracked failure: string | undefined;
  // The key approvals the screen shows: the estimate's before the person
  // confirms, then each answer of the switch-on route after.
  @tracked confirmedApprovals: KeyApprovals | undefined;
  // The screen the person confirmed in, which stays open while the
  // automation waits for key approval.
  @tracked confirmedMode: 'switch-on' | 'reconfirm' | undefined;
  @tracked windowFailure: string | undefined;
  // Whether the browser blocked the secure window the screen opened.
  @tracked windowBlocked = false;

  get mode(): 'switch-on' | 'reconfirm' {
    if (this.confirmedMode) {
      return this.confirmedMode;
    }
    return needsReconfirm(this.args.status) ? 'reconfirm' : 'switch-on';
  }
  get available() {
    let status = this.args.status;
    return (
      Boolean(this.args.realm && this.args.model.id && this.tools) &&
      (status?.switchedOn === false ||
        this.mode === 'reconfirm' ||
        this.confirmedMode !== undefined)
    );
  }

  get keyApprovals(): KeyApprovals | undefined {
    return this.confirmedApprovals ?? this.estimate?.keyApprovals;
  }
  get keyRows(): KeyApprovalRow[] {
    return (this.keyApprovals?.operations ?? []).map((operation, index) => {
      let row = {
        key: `${index}`,
        title: operationTitle(operation.operation),
        typeName: operation.targetType.name,
      };
      if (operation.state === 'approved') {
        return { ...row, look: { label: 'Approved', tone: 'success' } };
      }
      if (operation.state === 'unavailable') {
        return {
          ...row,
          look: { label: 'Unavailable', tone: 'danger' },
          detail: operation.refusal?.detail,
        };
      }
      let missing = operation.missing ?? [];
      switch (neediestWait(operation)) {
        case 'nobody-yet':
          return {
            ...row,
            look: { label: 'No key shared', tone: 'warning' },
            detail:
              'A realm administrator shares a key with the realm before anyone can approve the call.',
          };
        case 'share-suspended': {
          let share = missing.find(waitsOnSuspendedShare)?.shares?.[0];
          return {
            ...row,
            look: { label: 'Share suspended', tone: 'warning' },
            detail: `${ownerName(share)} resumes the share ${share?.label ?? ''} before anyone approves the call.`,
          };
        }
        case 'another-key-owner': {
          let share = missing.find((m) => m.canApprove === 'another-key-owner')
            ?.shares?.[0];
          return {
            ...row,
            look: { label: 'Another person approves', tone: 'warning' },
            detail: share
              ? `${ownerName(share)} approves the use of the key ${share.label}.`
              : 'The owner of the shared key approves the call.',
          };
        }
        default:
          return {
            ...row,
            look: {
              label: this.confirmedMode ? 'Waiting for you' : 'You approve',
              tone: 'info',
            },
          };
      }
    });
  }
  // Whether some missing approval is the payer's to give in the secure
  // window: not one whose share is suspended, which the share's owner
  // resumes first.
  get payerApproves() {
    return (this.keyApprovals?.operations ?? []).some((o) =>
      (o.missing ?? []).some(
        (m) => m.canApprove === 'payer' && !waitsOnSuspendedShare(m),
      ),
    );
  }
  get otherApprovers(): OtherApprover[] {
    let found = new Map<string, OtherApprover>();
    for (let operation of this.keyApprovals?.operations ?? []) {
      for (let missing of operation.missing ?? []) {
        if (
          missing.canApprove !== 'another-key-owner' ||
          waitsOnSuspendedShare(missing)
        ) {
          continue;
        }
        for (let share of missing.shares ?? []) {
          found.set(share.id, {
            label: share.label,
            owner: ownerName(share),
          });
        }
      }
    }
    return [...found.values()];
  }
  get nobodyYet() {
    return (this.keyApprovals?.operations ?? []).some((o) =>
      (o.missing ?? []).some((m) => m.canApprove === 'nobody-yet'),
    );
  }
  // Once the person confirms: the automation is on and every approval is
  // there.
  get active() {
    return (
      this.confirmedMode !== undefined && this.keyApprovals?.approved === true
    );
  }
  get tools() {
    return toolsOf(this.args.context);
  }
  get title() {
    return this.mode === 'reconfirm'
      ? 'Resume the automation'
      : 'Turn on the automation';
  }
  get openLabel() {
    return this.mode === 'reconfirm'
      ? 'Review and resume'
      : 'Turn on the automation';
  }
  get confirmLabel() {
    return this.mode === 'reconfirm'
      ? 'Resume and pay'
      : 'Turn on the automation and pay';
  }
  // Why Boxel paused an automation that the screen resumes.
  get reconfirmLead() {
    let status = this.args.status;
    if (!status?.switchedOn) {
      return undefined;
    }
    return status.pauseReason === 'batched-ai-enabled'
      ? 'Someone turned on batched AI after the payer agreed to the automation’s limits, so Boxel paused the automation. Resuming the automation makes you the payer, with batched AI on.'
      : 'Someone raised one of the automation’s limits above what the payer agreed to, so Boxel paused the automation. Resuming the automation makes you the payer of the new limits.';
  }

  get cap(): number | null {
    if (this.typedCap !== undefined) {
      return this.typedCap;
    }
    return this.estimate?.monthlyCredits ?? null;
  }
  get capProblem() {
    if (!this.submitted && this.typedCap === undefined) {
      return undefined;
    }
    let cap = this.cap;
    if (cap === null) {
      return 'Enter a monthly limit. Boxel turns an automation on only with a monthly limit.';
    }
    if (!Number.isInteger(cap) || cap < 0) {
      return 'Enter a whole number of credits, or 0 to forbid any spending.';
    }
    let daily = this.args.model.caps?.dailyCredits;
    if (typeof daily === 'number' && cap < daily) {
      return `The monthly limit can’t be below the daily limit of ${tally(daily)} credits. Enter at least ${tally(daily)}, or lower the daily limit in the automation’s editor.`;
    }
    return undefined;
  }
  get capBelowEstimate() {
    let cap = this.cap;
    return (
      typeof cap === 'number' &&
      this.estimate !== undefined &&
      cap < this.estimate.estimate.credits
    );
  }
  get capHint() {
    return this.capBelowEstimate
      ? 'The limit is below the estimate, so Boxel may stop starting runs before the month ends.'
      : 'Boxel starts no run in a calendar month once the automation’s charges that month reach this limit.';
  }
  get noLimits() {
    return !this.args.model.caps;
  }

  get estimateItems() {
    let e = this.estimate?.estimate;
    if (!e) {
      return [];
    }
    let exactRuns =
      e.unboundedRunsPerMonth + e.boundedRunsPerMonth + e.onceRuns;
    let runs = Math.round(exactRuns);
    return [
      {
        key: 'estimate',
        label: 'Estimate',
        value: `${tally(e.credits)} credits a month`,
        hint: 'The most each run can cost, times the runs the triggers make in a month.',
      },
      {
        key: 'perRun',
        label: 'Most one run can cost',
        value: `${tally(Math.ceil(e.perRun.totalCredits))} credits`,
        hint: 'What the per-run limits let one run spend on time, downloads and AI.',
      },
      {
        key: 'runs',
        label: 'Runs counted',
        value:
          exactRuns > 0 && exactRuns < 1
            ? 'Less than 1 run a month'
            : runs === 1
              ? '1 run a month'
              : `${tally(runs)} runs a month`,
        hint: 'Every scheduled run in an average month, and each one-time run still to come.',
      },
      {
        key: 'preview',
        label: 'Your last Preview',
        value:
          e.recentPreviewCredits === undefined
            ? 'No Preview yet'
            : `${tally(e.recentPreviewCredits)} credits`,
        hint: 'Boxel charges a Preview to the person who runs the Preview, so the estimate leaves Previews out.',
      },
    ];
  }
  hintOf = (key: string | undefined) =>
    this.estimateItems.find((item) => item.key === key)?.hint;
  get webhookTriggers() {
    return this.estimate?.estimate.webhookTriggers ?? [];
  }
  get canConfirm() {
    return (
      this.estimate !== undefined &&
      !this.loading &&
      !this.saving &&
      !this.capProblem &&
      !this.noLimits &&
      !this.nobodyYet
    );
  }

  show = () => {
    this.typedCap = undefined;
    this.submitted = false;
    this.failure = undefined;
    this.estimate = undefined;
    this.estimateFailure = undefined;
    this.confirmedApprovals = undefined;
    this.confirmedMode = undefined;
    this.windowFailure = undefined;
    this.windowBlocked = false;
    this.open = true;
    this.readEstimate();
  };
  close = () => {
    if (!this.saving) {
      this.open = false;
      this.confirmedMode = undefined;
      this.confirmedApprovals = undefined;
      this.stopRereading();
    }
  };

  willDestroy() {
    super.willDestroy();
    this.stopRereading();
  }

  // Opens the secure window on the automation's key approvals: the window
  // gathers every approval the automation is missing that the person can
  // give into one confirmation.
  approveKeys = async () => {
    this.windowFailure = undefined;
    try {
      let result = await new OpenSecureWindowTool(this.tools!).execute({
        mode: 'approve',
        automation: this.args.model.id,
        reason: 'To approve the calls the automation makes with your keys',
      });
      this.windowBlocked = result?.status === 'blocked';
    } catch (e) {
      this.windowFailure = e instanceof Error ? e.message : String(e);
    }
  };

  // Opens the secure window's share page for the automation's realm, where a
  // realm administrator shares a key with the realm. When the person comes
  // back to the page, the screen reads the switch-on route again, so a key
  // shared meanwhile shows who approves the key.
  shareKey = async () => {
    this.windowFailure = undefined;
    window.removeEventListener('focus', this.readAfterSharing);
    window.addEventListener('focus', this.readAfterSharing, { once: true });
    try {
      await new OpenSecureWindowTool(this.tools!).execute({
        mode: 'share-key',
        realm: this.args.realm,
        reason: 'To share a key the automation can use',
      });
    } catch (e) {
      this.windowFailure = e instanceof Error ? e.message : String(e);
    }
  };
  readAfterSharing = () => {
    if (this.isDestroying || this.isDestroyed || !this.open) {
      return;
    }
    if (this.confirmedMode) {
      this.rereadApprovals();
    } else {
      this.readEstimate();
    }
  };

  // While the automation waits for key approval, the screen asks the
  // switch-on route again each time the person comes back to the page, and
  // every few seconds, until every approval is there.
  private rereadTimer: ReturnType<typeof setInterval> | undefined;
  private startRereading() {
    this.stopRereading();
    window.addEventListener('focus', this.rereadApprovals);
    this.rereadTimer = setInterval(this.rereadApprovals, APPROVAL_REREAD_MS);
  }
  private stopRereading() {
    window.removeEventListener('focus', this.readAfterSharing);
    window.removeEventListener('focus', this.rereadApprovals);
    if (this.rereadTimer !== undefined) {
      clearInterval(this.rereadTimer);
      this.rereadTimer = undefined;
    }
    // A read still in flight answers for a screen that has stopped reading.
    this.rereads++;
  }
  // Each read is numbered, so only the latest answer counts, and a read
  // starts only once the one before it has answered, so a slow route still
  // gets its answers through.
  private rereads = 0;
  private rereading = false;
  rereadApprovals = async () => {
    if (
      this.isDestroying ||
      this.isDestroyed ||
      !this.confirmedMode ||
      this.rereading
    ) {
      return;
    }
    let read = ++this.rereads;
    this.rereading = true;
    try {
      let estimate = await this.fetchEstimate();
      if (
        read !== this.rereads ||
        this.isDestroying ||
        this.isDestroyed ||
        !this.confirmedMode
      ) {
        return;
      }
      if (estimate.keyApprovals) {
        this.confirmedApprovals = estimate.keyApprovals;
      }
      if (this.active) {
        this.stopRereading();
      }
    } catch {
      // The next read tries again.
    } finally {
      this.rereading = false;
    }
  };
  setCap = (value: number | null) => {
    this.typedCap = value;
    this.failure = undefined;
  };

  private request(attributes: {
    route: string;
    method: 'GET' | 'POST';
    monthlyCredits?: number;
  }) {
    return new AutomationRequestTool(this.tools!).execute({
      ...attributes,
      realm: this.args.realm,
      automation: this.args.model.id,
    });
  }

  private async fetchEstimate(): Promise<SwitchOnEstimate> {
    let result = await this.request({ route: SWITCH_ON_ROUTE, method: 'GET' });
    if (!result.ok) {
      throw new Error(
        result.errors?.[0] ??
          `Boxel answered with status ${result.status} for the estimate.`,
      );
    }
    return result.body?.data?.attributes as SwitchOnEstimate;
  }

  readEstimate = async () => {
    this.loading = true;
    try {
      this.estimate = await this.fetchEstimate();
      this.estimateFailure = undefined;
    } catch (e) {
      this.estimateFailure = e instanceof Error ? e.message : String(e);
    } finally {
      this.loading = false;
    }
  };

  // Writes the monthly limit to the card, and waits for the realm server to
  // read the card with that limit.
  private async writeCap(cap: number) {
    let caps = this.args.model.caps;
    if (!caps) {
      throw new Error(NO_LIMITS);
    }
    caps.monthlyCredits = cap;
    let started = Date.now();
    for (;;) {
      let estimate = await this.fetchEstimate();
      if (estimate.monthlyCredits === cap) {
        this.estimate = estimate;
        return;
      }
      if (Date.now() - started > CAP_SAVED_WAIT_MS) {
        throw new Error(
          'Boxel hasn’t read the automation with the new monthly limit yet. Try again in a moment.',
        );
      }
      await new Promise((resolve) => setTimeout(resolve, CAP_SAVED_POLL_MS));
    }
  }

  confirm = async () => {
    this.submitted = true;
    let cap = this.cap;
    // The screen the person clicked in decides the route, even when the
    // status changes while the screen waits for the card to save the limit.
    let mode = this.mode;
    if (!this.canConfirm || cap === null) {
      return;
    }
    this.saving = true;
    this.failure = undefined;
    try {
      if (cap !== this.estimate?.monthlyCredits) {
        await this.writeCap(cap);
      }
      let result = await this.request({
        route: mode === 'reconfirm' ? RESUME_ROUTE : SWITCH_ON_ROUTE,
        method: 'POST',
        monthlyCredits: cap,
      });
      if (!result.ok) {
        this.failure =
          result.errors?.[0] ?? `Boxel answered with status ${result.status}.`;
        if (result.status === 409) {
          // The card changed after the screen read it: show the limits the
          // card holds, in place of the one typed.
          this.typedCap = undefined;
          await this.readEstimate();
        }
        return;
      }
      let approvals = result.body?.meta?.keyApprovals as
        | KeyApprovals
        | undefined;
      if (!approvals || approvals.approved) {
        this.open = false;
        return;
      }
      // The automation is on and waits for key approval: the screen stays
      // open on what each approval waits for, and opens the secure window
      // for the approvals the person gives.
      this.confirmedMode = mode;
      this.confirmedApprovals = approvals;
      this.startRereading();
      if (this.payerApproves) {
        await this.approveKeys();
      }
    } catch (e) {
      this.failure = e instanceof Error ? e.message : String(e);
    } finally {
      this.saving = false;
    }
  };

  <template>
    {{#if this.available}}
      <div class='switch-on__open'>
        <Button {{on 'click' this.show}} data-test-automation-switch-on>
          {{this.openLabel}}
        </Button>
      </div>
      <Dialog
        @open={{this.open}}
        @onClose={{this.close}}
        @size='m'
        @label={{this.title}}
      >
        <:title>{{this.title}}</:title>
        <:default>
          <Stack @gap='m' data-test-automation-switch-on-screen>
            {{#if this.reconfirmLead}}
              <p
                data-test-automation-switch-on-reconfirm
              >{{this.reconfirmLead}}</p>
            {{/if}}
            {{#if this.noLimits}}
              <div data-test-automation-switch-on-no-limits>
                <Callout
                  @tone='warning'
                  @title='The automation has no limits'
                >{{NO_LIMITS}}</Callout>
              </div>
            {{/if}}
            {{#if this.confirmedMode}}
              {{#if this.active}}
                <Callout
                  @tone='success'
                  @title='The automation is on'
                  data-test-automation-switch-on-active
                >
                  Every key approval is in place, so Boxel runs the automation
                  each time a trigger fires.
                </Callout>
              {{else}}
                <Callout
                  @tone='warning'
                  @title='The automation is waiting for key approval'
                  data-test-automation-switch-on-waiting
                >
                  {{if
                    (eq this.mode 'reconfirm')
                    'Boxel resumed the automation.'
                    'Boxel turned on the automation.'
                  }}
                  The automation runs nothing until every key approval below is
                  in place.
                </Callout>
                {{#if this.payerApproves}}
                  <Callout
                    @tone='info'
                    @title={{if
                      this.windowBlocked
                      'Open the secure window'
                      'Approve the calls in the secure window'
                    }}
                    data-test-automation-switch-on-approve-keys
                  >
                    <:default>
                      {{#if this.windowBlocked}}
                        The browser kept Boxel from opening the secure window.
                        Open the secure window to approve the calls the
                        automation makes with your keys, in one step.
                      {{else}}
                        Boxel opened the secure window, where you approve the
                        calls the automation makes with your keys, in one step.
                      {{/if}}
                      Once every key approval is in place, the screen shows the
                      automation as on.
                    </:default>
                    <:action>
                      <Button
                        @appearance='outlined'
                        @size='sm'
                        {{on 'click' this.approveKeys}}
                        data-test-automation-switch-on-reopen-window
                      >{{if
                          this.windowBlocked
                          'Open the secure window'
                          'Open the secure window again'
                        }}</Button>
                    </:action>
                  </Callout>
                {{/if}}
              {{/if}}
              <SwitchOnKeyApprovals
                @rows={{this.keyRows}}
                @otherApprovers={{this.otherApprovers}}
                @nobodyYet={{this.nobodyYet}}
                @payerApproves={{false}}
                @confirmed={{true}}
                @windowFailure={{this.windowFailure}}
                @onShareKey={{this.shareKey}}
              />
            {{else if this.estimate}}
              <Descriptions
                @items={{this.estimateItems}}
                @columns={{2}}
                @layout='vertical'
                @bordered={{true}}
                data-test-automation-switch-on-estimate
              >
                <:value as |item|>
                  <span
                    class='switch-on__value'
                    data-test-automation-switch-on-fact={{item.key}}
                  >{{item.value}}</span>
                  <span class='switch-on__hint'>{{this.hintOf item.key}}</span>
                </:value>
              </Descriptions>
              <Callout
                @tone='info'
                @title='What the estimate leaves out'
                data-test-automation-switch-on-left-out
              >
                <ul class='switch-on__list'>
                  <li>The indexing that each run’s saves cause.</li>
                  <li>The daily storage of the files the runs create.</li>
                  <li>
                    Runs that a webhook delivery starts, since no schedule
                    predicts webhook deliveries.
                    {{#if this.webhookTriggers.length}}
                      This automation has webhook triggers:
                      {{#each this.webhookTriggers as |label|}}
                        <Token @value={{label}} />
                      {{/each}}
                    {{/if}}
                  </li>
                </ul>
                Boxel counts these charges toward the monthly limit too.
              </Callout>
              <Field
                @label='Monthly limit, in Boxel credits'
                @hint={{this.capHint}}
                @error={{this.capProblem}}
                as |id|
              >
                <NumberInput
                  @controlId={{id}}
                  @value={{this.cap}}
                  @invalid={{if this.capProblem true false}}
                  @min={{0}}
                  @onInput={{this.setCap}}
                  data-test-automation-switch-on-cap
                />
              </Field>
              <SwitchOnKeyApprovals
                @rows={{this.keyRows}}
                @otherApprovers={{this.otherApprovers}}
                @nobodyYet={{this.nobodyYet}}
                @payerApproves={{this.payerApproves}}
                @confirmed={{false}}
                @windowFailure={{this.windowFailure}}
                @onShareKey={{this.shareKey}}
              />
              <Callout
                @tone='info'
                @title='You become the payer'
                data-test-automation-switch-on-payer
              >
                Boxel charges every scheduled run to your credits, and the
                storage of the files the runs create for every day the
                automation stays on. The monthly limit stops Boxel from starting
                runs, while the storage charge continues until a realm
                administrator removes the automation. Any realm administrator
                can pause the automation, or resume the automation and become
                the payer instead.
              </Callout>
            {{else if this.estimateFailure}}
              <div data-test-automation-switch-on-estimate-failure>
                <Callout
                  @tone='danger'
                  @title='Boxel couldn’t read the estimate'
                >{{this.estimateFailure}}</Callout>
              </div>
            {{else}}
              <LoadingState @label='Reading the estimate' />
            {{/if}}
            {{#if this.failure}}
              <div data-test-automation-switch-on-failure>
                <Callout
                  @tone='danger'
                  @title={{if
                    (eq this.mode 'reconfirm')
                    'Boxel didn’t resume the automation'
                    'Boxel didn’t turn the automation on'
                  }}
                >{{this.failure}}</Callout>
              </div>
            {{/if}}
          </Stack>
        </:default>
        <:footer>
          {{#if this.confirmedMode}}
            <Button
              {{on 'click' this.close}}
              data-test-automation-switch-on-close
            >Close</Button>
          {{else}}
            <Button
              @tone='neutral'
              @appearance='outlined'
              @disabled={{this.saving}}
              {{on 'click' this.close}}
            >Cancel</Button>
            {{#if this.estimateFailure}}
              <Button
                @busy={{this.loading}}
                {{on 'click' this.readEstimate}}
                data-test-automation-switch-on-retry
              >Try again</Button>
            {{else if this.nobodyYet}}
              <Button
                {{on 'click' this.shareKey}}
                data-test-automation-switch-on-share-key
              >Share a key</Button>
            {{else}}
              <Button
                @busy={{this.saving}}
                @disabled={{if this.estimate false true}}
                {{on 'click' this.confirm}}
                data-test-automation-switch-on-confirm
              >{{this.confirmLabel}}</Button>
            {{/if}}
          {{/if}}
        </:footer>
      </Dialog>
    {{/if}}
    <style scoped>
      .switch-on__open {
        margin: 0 0 var(--boxel-sp-sm);
      }
      .switch-on__value {
        display: block;
        font-size: var(--boxel-font-size-md);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
      }
      .switch-on__hint {
        display: block;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .switch-on__list {
        margin: var(--boxel-sp-4xs) 0;
        padding-inline-start: var(--boxel-sp-lg);
      }
    </style>
  </template>
}

// A slot's state as a chip.
const SLOT_LOOKS: Record<
  SlotApprovalState,
  { label: string; tone: 'success' | 'warning' | 'danger' | 'neutral' }
> = {
  approved: { label: 'Approved', tone: 'success' },
  waiting: { label: 'Waiting for approval', tone: 'warning' },
  'no-share': { label: 'No shared key', tone: 'warning' },
  'needs-reapproval': { label: 'Needs reapproval', tone: 'warning' },
  'share-suspended': { label: 'Shared key suspended', tone: 'danger' },
  'key-rejected': { label: 'Key rejected', tone: 'danger' },
};

// The button that opens the secure window on the page that fixes a slot.
// Approving is one button for the whole automation, above the rows: the
// secure window gathers every approval the viewer can give into one
// confirmation.
const FIX_LABELS: Record<Exclude<SlotApprovalFix, 'approve'>, string> = {
  'review-changes': 'Review the changes',
  'replace-key': 'Replace the key',
  'swap-key': 'Replace the shared key',
  'share-key': 'Share a key',
};

// The one line the secure window shows as the card's words, per page.
const FIX_REASONS: Record<SlotApprovalFix, string> = {
  approve: 'To approve the calls the automation makes with your keys',
  'review-changes':
    'To review the calls the automation makes that changed since you approved them',
  'replace-key': 'To replace the key the service refused',
  'swap-key': 'To replace the suspended shared key with one of your keys',
  'share-key': 'To share a key the automation can use',
};

// The key a slot sends, as a sentence names the key.
function keyWords(slot: SlotApproval): string {
  if (slot.share) {
    return `the shared key “${slot.share.label}”`;
  }
  if (slot.key) {
    return `the key “${slot.key.name}”`;
  }
  return slot.kind === 'apiKey' ? 'a shared key' : 'the key';
}

// Who acts for a slot, as the subject of a sentence: the viewer, the key's
// owner by Matrix id when ADR 011 lets the viewer see them, or a description.
function ownerWords(slot: SlotApproval): string {
  if (slot.viewerIsKeyOwner) {
    return 'You';
  }
  if (slot.keyOwner) {
    return slot.keyOwner;
  }
  return slot.kind === 'apiKey' && !slot.share
    ? 'The owner of a shared key'
    : 'The key’s owner';
}

// Why a share is suspended, and who brings the share back, as sentences.
function suspendedSentence(slot: SlotApproval): string {
  let key = keyWords(slot);
  switch (slot.share?.suspensionReason) {
    case 'owner-lost-write':
      return `Boxel suspended ${key} because the key’s owner is no longer a realm administrator. A realm administrator needs to replace the shared key with another key.`;
    case 'key-deleted':
      return `Boxel suspended ${key} because the key’s owner deleted the key. A realm administrator needs to replace the shared key with another key.`;
    default: {
      let who = slot.share?.suspendedByViewer
        ? 'You'
        : (slot.share?.suspendedBy ?? 'A realm administrator');
      return `${who} suspended ${key}. A realm administrator needs to resume the shared key, or replace the shared key with another key.`;
    }
  }
}

// What a slot's state means, and who acts on it, as a sentence.
function slotSentence(slot: SlotApproval): string {
  let who = ownerWords(slot);
  let key = keyWords(slot);
  switch (slot.state) {
    case 'approved':
      return `${who} approved the automation’s use of ${key}.`;
    case 'waiting':
      return slot.viewerIsKeyOwner
        ? `You need to approve the automation’s use of ${key}.`
        : `${who} needs to approve the automation’s use of ${key}.`;
    case 'no-share':
      return 'Nobody has shared a key for this service in this workspace. A realm administrator needs to share a key, and the key’s owner then needs to approve the automation’s use of the key.';
    case 'needs-reapproval':
      return slot.viewerIsKeyOwner
        ? `The service request changed since you approved the request. You need to review the changes before Boxel sends ${key} again.`
        : `The service request changed since ${lowerFirst(who)} approved the request. ${who} needs to review the changes before Boxel sends ${key} again.`;
    case 'share-suspended':
      return suspendedSentence(slot);
    case 'key-rejected':
      return slot.viewerIsKeyOwner
        ? `The service refused ${key}. You need to replace the key, or sign in to the service again.`
        : `The service refused ${key}. ${who} needs to replace the key, or sign in to the service again.`;
  }
}

// Each declared operation of a switched-on automation, with where each of the
// operation's keys stands and, for a key the viewer can fix, the secure
// window page that fixes it. The section reads the automation's status,
// which an `automation` event refreshes, so an approval, a share or a
// replaced key shows without a reload.
class KeyApprovalsSection extends GlimmerComponent<{
  Args: {
    approvals: KeyApprovalStatus;
    automation: string | undefined;
    realm: string | undefined;
    tools: Tools | undefined;
  };
}> {
  // Whether the browser blocked the secure window the section opened, and
  // why opening it failed, if it did.
  @tracked windowBlocked = false;
  @tracked windowFailure: string | undefined;

  get lead() {
    let slots = this.args.approvals.operations.flatMap(({ slots }) => slots);
    if (!this.args.approvals.approved) {
      return 'Boxel holds every run until the owner of each key marked below approves the automation’s use of the key.';
    }
    return slots.every(({ state }) => state === 'approved')
      ? 'The owner of each key the automation uses approved the automation’s use of the key. Each approval lasts until someone changes the automation’s script, triggers, params or outside services.'
      : 'The owner of each key the automation uses approved the automation’s use of the key, but a run that sends a key marked below fails until someone fixes the key.';
  }
  get operations() {
    return this.args.approvals.operations.filter(
      ({ state, slots }) => state === 'unavailable' || slots.length > 0,
    );
  }
  // Whether the viewer can approve any key the automation still waits on.
  get viewerApproves() {
    return (
      Boolean(this.args.tools) &&
      this.args.approvals.operations.some(({ slots }) =>
        slots.some(({ fix }) => fix === 'approve'),
      )
    );
  }
  look = (slot: SlotApproval) => SLOT_LOOKS[slot.state];
  sentence = (slot: SlotApproval) => slotSentence(slot);
  fixLabel = (slot: SlotApproval) =>
    slot.fix && slot.fix !== 'approve' ? FIX_LABELS[slot.fix] : undefined;
  // Whether the row offers its own fix: every fix but approving, which the
  // button above the rows covers, and only where the card can open the
  // secure window.
  offersFix = (slot: SlotApproval) =>
    Boolean(this.args.tools && this.fixLabel(slot));
  // The fix button's accessible name, which names the operation, since rows
  // can share a button's label.
  fixName = (operation: OperationApproval, slot: SlotApproval) =>
    `${this.fixLabel(slot)} for ${operation.operation} on ${operation.targetType.name}`;
  approve = () =>
    this.open({ mode: 'approve', automation: this.args.automation }, 'approve');
  fix = (operation: OperationApproval, slot: SlotApproval) => {
    let { realm } = this.args;
    if (!slot.fix || slot.fix === 'approve') {
      return;
    }
    let input =
      slot.fix === 'share-key'
        ? { mode: 'share-key', realm }
        : slot.fix === 'swap-key'
          ? { mode: 'swap-key', realm, share: slot.share?.id }
          : {
              mode: slot.fix,
              module: operation.targetType.module,
              name: operation.targetType.name,
              realm,
              operation: operation.operation,
            };
    return this.open(input, slot.fix);
  };
  private open = async (
    input: Record<string, string | undefined>,
    fix: SlotApprovalFix,
  ) => {
    let { tools } = this.args;
    if (!tools) {
      return;
    }
    this.windowFailure = undefined;
    try {
      let result = await new OpenSecureWindowTool(tools).execute({
        ...input,
        reason: FIX_REASONS[fix],
      });
      this.windowBlocked = result?.status === 'blocked';
    } catch (e) {
      this.windowFailure = e instanceof Error ? e.message : String(e);
    }
  };

  <template>
    <p class='key-approvals__lead' data-test-automation-key-approvals-lead>
      {{this.lead}}
    </p>
    {{#if this.viewerApproves}}
      <div class='key-approvals__approve'>
        <Button
          @appearance='outlined'
          @size='s'
          data-test-automation-key-approval-fix='approve'
          {{on 'click' this.approve}}
        >Approve your keys in the secure window</Button>
      </div>
    {{/if}}
    {{#if this.windowBlocked}}
      <Callout
        @tone='warning'
        @title='The browser blocked the secure window'
        data-test-automation-key-approvals-window-blocked
      >
        The browser kept Boxel from opening the secure window. Boxel shows a
        button that opens the secure window.
      </Callout>
    {{/if}}
    {{#if this.windowFailure}}
      <Callout
        @tone='danger'
        @title='Boxel couldn’t open the secure window'
        data-test-automation-key-approvals-window-failure
      >
        {{this.windowFailure}}
      </Callout>
    {{/if}}
    <ul class='key-approvals'>
      {{#each this.operations as |operation|}}
        <li
          class='key-approvals__operation'
          data-test-automation-key-approval={{operation.operation}}
        >
          <h3 class='key-approvals__name'>
            <Token @value={{operation.operation}} />
            on
            {{operation.targetType.name}}
          </h3>
          {{#if (eq operation.state 'unavailable')}}
            <Item
              @size='s'
              @wrap={{true}}
              @alignStart={{true}}
              data-test-automation-key-approval-unavailable
            >
              <:leading>
                <Chip @label='Unavailable' @tone='neutral' />
              </:leading>
              <:description>
                Boxel can’t read this outside service in this workspace, so a
                run can’t call the service. A realm administrator needs to fix
                the outside service in the edit view.
              </:description>
            </Item>
          {{/if}}
          {{#each operation.slots as |slot|}}
            {{#let (this.look slot) as |look|}}
              <Item
                @size='s'
                @wrap={{true}}
                @alignStart={{true}}
                data-test-automation-key-approval-slot={{slot.slot}}
                data-test-automation-key-approval-state={{slot.state}}
              >
                <:leading>
                  <Chip @label={{look.label}} @tone={{look.tone}} />
                </:leading>
                <:description>
                  <span
                    data-test-automation-key-approval-sentence
                  >{{this.sentence slot}}</span>
                  {{#if slot.approvedAt}}
                    <span
                      class='key-approvals__since'
                      data-test-automation-key-approval-since
                    >
                      Approved
                      <FormatDate
                        @date={{slot.approvedAt}}
                        @month='short'
                        @day='numeric'
                        @year='numeric'
                      />
                    </span>
                  {{/if}}
                </:description>
                <:actions>
                  {{#if (this.offersFix slot)}}
                    <Button
                      @appearance='outlined'
                      @size='s'
                      aria-label={{this.fixName operation slot}}
                      data-test-automation-key-approval-fix={{slot.fix}}
                      {{on 'click' (fn this.fix operation slot)}}
                    >{{this.fixLabel slot}}</Button>
                  {{/if}}
                </:actions>
              </Item>
            {{/let}}
          {{/each}}
        </li>
      {{/each}}
    </ul>
    <style scoped>
      .key-approvals__approve {
        margin-block-end: var(--boxel-sp-sm);
      }
      .key-approvals {
        list-style: none;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp);
      }
      .key-approvals__operation {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .key-approvals__name {
        font: inherit;
        font-weight: 600;
      }
      .key-approvals__since {
        display: block;
      }
    </style>
  </template>
}

// Whether the way into the automations console shows: to a direct writer,
// on a card that knows its realm, outside the console itself.
function showsConsoleAction(
  model: { [realmURL]?: URL },
  context: CardContext | undefined,
  directWriter: boolean,
  inConsole: boolean | undefined,
): boolean {
  return (
    directWriter &&
    !inConsole &&
    Boolean(model[realmURL] && context?.toolContext)
  );
}

// The way from an automation's card to the automations console: the realm
// config card's Automations section, opened with the automation's row in
// view and marked. Shown to the realm's direct writers alone, the only
// viewers the console lists automations for, and left out of the automation
// rows the console itself shows.
class ShowInConsole extends GlimmerComponent<{
  Args: {
    // The automation card: its id, and the realm the card lives in.
    model: { id?: string; [realmURL]?: URL };
    context: CardContext | undefined;
    // Whether the status route answered that the viewer is a direct writer.
    directWriter: boolean;
    // An icon button for the fitted view's narrow heading row, or a labelled
    // button.
    iconOnly?: boolean;
  };
  Element: HTMLElement;
}> {
  @consume(AutomationsConsoleContextName) declare inConsole:
    | boolean
    | undefined;

  get shows() {
    return showsConsoleAction(
      this.args.model,
      this.args.context,
      this.args.directWriter,
      this.inConsole,
    );
  }

  @tracked private opening = false;

  // A click opens the console and nothing else: the card around the button
  // opens the automation on a click of its own.
  show = async (event: Event) => {
    event.stopPropagation();
    let realm = this.args.model[realmURL]?.href;
    let id = this.args.model.id;
    let toolContext = this.args.context?.toolContext;
    if (!realm || !id || !toolContext || this.opening) {
      return;
    }
    this.opening = true;
    try {
      await showAutomationInConsole(toolContext, realm, id);
    } catch (error) {
      // The host reports a card that fails to open; the button only has to
      // return to its idle state.
      console.error('Show in Automations could not open the console', error);
    } finally {
      this.opening = false;
    }
  };

  <template>
    {{#if this.shows}}
      {{#if @iconOnly}}
        <IconButton
          @label='Show in Automations'
          @icon={{LayoutListIcon}}
          @size='xs'
          @appearance='plain'
          @busy={{this.opening}}
          {{on 'click' this.show}}
          data-test-automation-show-in-console
          ...attributes
        />
      {{else}}
        <Button
          @size='s'
          @icon={{LayoutListIcon}}
          @busy={{this.opening}}
          {{on 'click' this.show}}
          data-test-automation-show-in-console
          ...attributes
        >
          Show in Automations
        </Button>
      {{/if}}
    {{/if}}
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
  get automation() {
    return this.args.model as Automation;
  }
  get tools() {
    return toolsOf(this.args.context);
  }
  private server = automationStatus(this, () => ({
    id: this.args.model.id,
    realm: this.realmHref,
    realmId: this.realmId,
    tools: toolsOf(this.args.context),
    keyApprovals: true,
  }));
  get status() {
    return this.server.current.visible ? this.server.current.status : undefined;
  }
  get directWriter() {
    return this.server.current.visible;
  }
  get statusKnown() {
    return this.server.current.known;
  }
  get keyApprovals() {
    let status = this.status;
    return status?.switchedOn &&
      status.keyApprovals?.operations.some(
        ({ state, slots }) => state === 'unavailable' || slots.length > 0,
      )
      ? status.keyApprovals
      : undefined;
  }
  private runList = automationRuns(this, () => ({
    id: this.args.model.id,
    realm: this.realmHref,
    realmId: this.realmId,
    tools: toolsOf(this.args.context),
  }));
  get runs() {
    return this.runList.current.state;
  }
  get showsRuns() {
    return this.runs.visible;
  }
  showRunsPage = (page: number) => this.runList.current.showPage(page);
  get runsSummary() {
    let total = this.runs.total;
    return total === 1 ? '1 run' : `${total.toLocaleString('en-US')} runs`;
  }
  triggerKindOf = (label: string | null) =>
    (this.args.model.triggers ?? []).find((trigger) => trigger?.label === label)
      ?.kind ?? undefined;
  get look() {
    return stateLook(this.status);
  }
  get stateSentence() {
    if (!this.status) {
      return undefined;
    }
    return stateSteps(this.status)?.lead ?? stateSentence(this.status);
  }
  get stateSteps() {
    return this.status ? (stateSteps(this.status)?.steps ?? []) : [];
  }
  get statusItems() {
    return this.status ? statusItems(this.status) : [];
  }
  get pauseProblems() {
    return pauseProblemRows(
      this.status,
      (this.args.model.triggers ?? []).map((trigger) => trigger?.label),
    );
  }
  // The script, read once for the Script section and for the milestones the
  // script declares.
  private script = scriptText(this, () => ({
    url: this.scriptURL,
    realm: this.realmHref,
    realmId: this.realmId,
    tools: toolsOf(this.args.context),
  }));
  get scriptState() {
    return this.script.current;
  }
  // The milestones the script declares with realm.progress.plan, read from
  // its text, shown before any run has reported its own.
  get declaredPlan() {
    let text = this.scriptState.text;
    return text ? declaredMilestones(text) : undefined;
  }
  get declaredRows() {
    return declaredMilestoneRows(this.declaredPlan ?? []);
  }
  // The run in progress when there is one, otherwise the last run that
  // ended, when it reported milestones or a plan.
  get shownRun() {
    let run = this.status?.currentRun ?? this.status?.lastRun;
    return run && (run.milestones.length > 0 || run.plan.length > 0)
      ? run
      : undefined;
  }
  get shownRunRows() {
    return this.shownRun ? runMilestoneRows(this.shownRun) : [];
  }
  get shownRunLead() {
    return this.shownRun ? runLead(this.shownRun) : undefined;
  }

  // What the section says when there is no last run to list: a viewer who
  // isn't a direct writer never sees runs; a direct writer sees them once a
  // run ends and the script reports milestones.
  get milestonesEmptyMessage() {
    if (!this.status) {
      return 'A realm administrator sees the milestones of the last run here.';
    }
    return this.status.lastRun
      ? 'The last run reported no milestones. A script reports milestones with realm.progress.plan and realm.progress.milestone.'
      : 'The milestones the script reports show here after a run ends.';
  }

  timeZoneAt = (index: number) => this.args.model.triggers?.[index]?.timeZone;
  triggerStatusAt = (index: number) =>
    statusOfTrigger(this.status, this.args.model.triggers?.[index]?.label);
  <template>
    <article class='automation' data-test-automation>
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
          <ShowInConsole
            class='automation__console'
            @model={{@model}}
            @context={{@context}}
            @directWriter={{this.directWriter}}
          />
        </div>
        <Stack
          class='automation__chips'
          @orientation='horizontal'
          @wrap={{true}}
          @gap='xs'
          @justify='end'
        >
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
        </Stack>
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
          {{#if this.stateSteps.length}}
            <ol class='automation__steps' data-test-automation-state-steps>
              {{#each this.stateSteps as |step|}}
                <li>{{step}}</li>
              {{/each}}
            </ol>
          {{/if}}
          <SwitchOnDialog
            @model={{this.automation}}
            @context={{@context}}
            @realm={{this.realmHref}}
            @status={{this.status}}
          />
          <StatusFacts @items={{this.statusItems}} @columns={{2}} />
          {{#if this.pauseProblems.length}}
            <Callout
              @tone='danger'
              @title='Problems to fix'
              data-test-automation-pause-problems
            >
              <ul class='automation__problems'>
                {{#each this.pauseProblems as |problem|}}
                  <li>
                    <Item
                      @size='s'
                      @wrap={{true}}
                      @title={{problem.place}}
                      @description={{problem.message}}
                      data-test-automation-pause-problem={{problem.place}}
                    />
                  </li>
                {{/each}}
              </ul>
            </Callout>
          {{/if}}
        </PanelSection>
      {{else if this.statusKnown}}
        <Callout
          @tone='info'
          @title='Who turns this automation on, and who pays'
          data-test-automation-who-pays
        >
          This automation runs only after a realm administrator turns the
          automation on. That person pays for every run.
        </Callout>
      {{/if}}

      {{#if this.keyApprovals}}
        <PanelSection
          @title='Key approvals'
          @collapsible={{false}}
          data-test-automation-key-approvals
        >
          <KeyApprovalsSection
            @approvals={{this.keyApprovals}}
            @automation={{@model.id}}
            @realm={{this.realmHref}}
            @tools={{this.tools}}
          />
        </PanelSection>
      {{/if}}

      {{#if this.showsRuns}}
        <PanelSection
          @title='Runs'
          @defaultOpen={{false}}
          @summary={{this.runsSummary}}
          data-test-automation-runs-section
        >
          <AutomationRuns
            @runs={{this.runs}}
            @showPage={{this.showRunsPage}}
            @triggerKind={{this.triggerKindOf}}
            @realm={{this.realmHref}}
            @automation={{@model.id}}
            @caps={{@model.caps}}
            @tools={{this.tools}}
          />
        </PanelSection>
      {{/if}}

      <PanelSection @title='Script' @collapsible={{false}}>
        <p class='automation__lead'>
          The script is what actually runs each time this automation runs.
        </p>
        {{#if this.scriptURL}}
          <ScriptView @url={{this.scriptURL}} @state={{this.scriptState}} />
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

      {{! The script declares its milestones and marks each one as a run
          reaches it; they come from the last run, not from a field here. }}
      <PanelSection
        @title='Run milestones'
        @collapsible={{false}}
        data-test-automation-milestones
      >
        {{#if this.shownRun}}
          <p class='automation__lead' data-test-automation-milestones-lead>
            {{this.shownRunLead}}
          </p>
          <MilestoneTimeline
            @rows={{this.shownRunRows}}
            @label='Milestones of the run'
          />
        {{else if this.declaredPlan}}
          <p class='automation__lead' data-test-automation-milestones-lead>
            The milestones the script plans to reach, in order. Each run reports
            how far the script got.
          </p>
          <MilestoneTimeline
            @rows={{this.declaredRows}}
            @label='Milestones the script declares'
          />
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='Shown from runs'
            @message={{this.milestonesEmptyMessage}}
          />
        {{/if}}
      </PanelSection>
    </article>
    <style scoped>
      .automation {
        /* The containing block of the visually hidden text Pret UI
           components carry, which is positioned: without one here, that
           text lands on the host's card container, which then scrolls as
           well as this view. */
        position: relative;
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
      /* Under the title, where the title's column gives the action room,
         rather than in the chip column, which would take that room from the
         title. */
      .automation__console {
        margin-block-start: var(--boxel-sp-xs);
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
      .automation__steps {
        margin: 0 0 var(--boxel-sp-sm);
        padding-inline-start: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp-4xs);
        color: var(--foreground);
      }
      .automation__problems {
        display: grid;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
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
      @container (inline-size < 40rem) {
        .automation {
          padding: var(--boxel-sp);
        }
        /* A narrow header gives the chips a row of their own under the
           title, so the title's column keeps room for the title and the
           Show in Automations button. */
        .automation__chips {
          grid-column: 2 / -1;
          justify-content: start;
        }
      }
    </style>
  </template>
}

// What a new script starts with: a comment on what a script is, and one
// reported step, so it runs as soon as it's created.
const STARTER_SCRIPT = `/* global realm */
// A Realm Runner script: the body of an async function, run with the
// automation's \`realm\` object. Find cards with realm.cards.search and
// write files with realm.fs.writeText. Name the run's milestones up front
// with realm.progress.plan, mark each as the script reaches it with
// realm.progress.milestone, and report each notable task inside one, such
// as "Grouped the bug label", with realm.progress.task.

realm.progress.plan(['Start']);
realm.progress.milestone('Start');
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

// What the fitted and embedded views show of the automation's milestones:
// the run in progress, otherwise the last run that ended, otherwise the plan
// the script declares. A run's milestones come from the run, never from a
// field on the card.
type GlanceKind = 'running' | 'failed' | 'stopped' | 'complete' | 'planned';

interface MilestoneGlance {
  kind: GlanceKind;
  // One sentence on where the run stands, such as "Failed in Group by label".
  headline: string;
  // "2 of 5"
  count: string;
  done: number;
  total: number;
  // The fill color of the progress bar, in the run's state color.
  hue: string;
  steps: StepItem[];
  // Each step's last task, by the step's index. Only the fitted list shows
  // them: the embedded track's narrow columns have no room for a task.
  lastTasks: (string | undefined)[];
  // The index of the milestone the run is in, failed in or stopped in; the
  // last milestone otherwise.
  focus: number;
}

const STEP_STATES: Record<MilestoneState, StepState> = {
  reached: 'complete',
  running: 'in-progress',
  failed: 'error',
  stopped: 'blocked',
  'not-started': 'upcoming',
};

const GLANCE_HUES: Record<GlanceKind, string> = {
  running: 'var(--info)',
  failed: 'var(--destructive)',
  stopped: 'var(--muted-foreground)',
  complete: 'var(--success)',
  planned: 'var(--muted-foreground)',
};

function milestoneWord(n: number): string {
  return n === 1 ? 'milestone' : 'milestones';
}

function milestoneGlance(
  rows: MilestoneRow[],
  run: LastRun | undefined,
): MilestoneGlance | undefined {
  if (rows.length === 0) {
    return undefined;
  }
  let total = rows.length;
  let done = rows.filter((row) => row.state === 'reached').length;
  let focusIndex = rows.findIndex(
    (row) =>
      row.state === 'running' ||
      row.state === 'failed' ||
      row.state === 'stopped',
  );
  let focusRow = focusIndex >= 0 ? rows[focusIndex] : undefined;
  let kind: GlanceKind;
  let headline: string;
  if (!run) {
    kind = 'planned';
    headline = `${tally(total)} ${milestoneWord(total)} planned`;
  } else if (run.state === 'running' || run.state === 'pending') {
    // A run that has reached no milestone yet has no running row.
    kind = 'running';
    headline =
      focusRow?.state === 'running'
        ? `Running ${focusRow.name}`
        : 'Running, before the first milestone';
  } else if (run.state === 'error') {
    kind = 'failed';
    headline =
      focusRow?.state === 'failed'
        ? `Failed in ${focusRow.name}`
        : 'Failed before the first milestone';
  } else if (run.state === 'canceled') {
    kind = 'stopped';
    headline =
      focusRow?.state === 'stopped'
        ? `Stopped in ${focusRow.name}`
        : 'Stopped before the first milestone';
  } else if (done === total) {
    kind = 'complete';
    headline =
      total === 1
        ? 'The 1 milestone done'
        : `All ${tally(total)} milestones done`;
  } else {
    // A complete run that left milestones of its plan unreached.
    kind = 'complete';
    headline = `Completed without ${tally(total - done)} planned ${milestoneWord(total - done)}`;
  }
  return {
    kind,
    headline,
    count: `${tally(done)} of ${tally(total)}`,
    done,
    total,
    hue: GLANCE_HUES[kind],
    // StepList has no state for a stopped step; it reads as blocked, so
    // the detail says where Boxel stopped the run.
    steps: rows.map((row) => ({
      label: row.name,
      state: STEP_STATES[row.state],
      detail:
        row.state === 'stopped'
          ? ['Stopped here', row.detail].filter(Boolean).join(' · ')
          : row.detail,
    })),
    lastTasks: rows.map((row) => row.tasks.at(-1)),
    // The milestone a run is in, failed in or stopped in. Otherwise the
    // first milestone the run didn't reach, or the last one when the run
    // reached them all, and the first one before any run.
    focus:
      focusIndex >= 0
        ? focusIndex
        : kind === 'planned'
          ? 0
          : Math.min(done, total - 1),
  };
}

interface StepWindow {
  steps: StepItem[];
  // "2 earlier milestones" and "3 more milestones", for the milestones the
  // window leaves out before and after it.
  earlier: string | undefined;
  later: string | undefined;
}

// At most `size` milestones around the one the run is in, so a short list
// still shows where the run stands.
function stepWindow(glance: MilestoneGlance, size: number): StepWindow {
  let { steps, focus } = glance;
  if (steps.length <= size) {
    return { steps, earlier: undefined, later: undefined };
  }
  // The milestone in focus, with the one after it when there is room: the
  // run's milestone and the next one, a complete run's last two, or the
  // first two before any run.
  let start = Math.min(
    Math.max(focus - Math.max(size - 2, 0), 0),
    steps.length - size,
  );
  let before = start;
  let after = steps.length - start - size;
  return {
    steps: steps.slice(start, start + size),
    earlier:
      before > 0
        ? `${tally(before)} earlier ${milestoneWord(before)}`
        : undefined,
    later:
      after > 0 ? `${tally(after)} more ${milestoneWord(after)}` : undefined,
  };
}

// What the fitted and embedded views show at a glance: the automation's
// state, when it runs, how its last run ended and where its milestones stand.
// A viewer who isn't a direct writer sees the card's own fields and the
// milestones the script declares. A prerender reads neither the status nor
// the script, so it shows the card's own fields alone.
class AtAGlance extends Component<typeof Automation> {
  private server = automationStatus(this, () => ({
    id: this.args.model.id,
    realm: this.args.model[realmURL]?.href,
    realmId: instanceRealmId(this.args.model as Automation),
    tools: toolsOf(this.args.context),
  }));
  // Read, for the plan the script declares, only once the status has
  // answered with no run that reports milestones.
  private script = scriptText(this, () => ({
    url: this.args.model.script?.id,
    realm: this.args.model[realmURL]?.href,
    realmId: instanceRealmId(this.args.model as Automation),
    tools: toolsOf(this.args.context),
  }));
  get status() {
    return this.server.current.visible ? this.server.current.status : undefined;
  }
  get directWriter() {
    return this.server.current.visible;
  }
  @consume(AutomationsConsoleContextName) declare inConsole:
    | boolean
    | undefined;
  // Whether ShowInConsole renders for this viewer, for a view that lays out
  // a place for the action only when the action shows.
  get showsConsoleAction() {
    return showsConsoleAction(
      this.args.model,
      this.args.context,
      this.directWriter,
      this.inConsole,
    );
  }
  get look() {
    return stateLook(this.status);
  }
  get triggers() {
    return this.args.model.triggers ?? [];
  }
  get when() {
    let first = this.triggers[0];
    return first ? triggerPhrase(first) : 'No triggers yet';
  }
  get firstKind() {
    return this.triggers[0]?.kind;
  }
  get moreTriggers() {
    let more = this.triggers.length - 1;
    return more > 0
      ? `Plus ${tally(more)} more ${more === 1 ? 'trigger' : 'triggers'}`
      : undefined;
  }
  get hasScript() {
    return Boolean(this.args.model.script);
  }
  get showsBatchedAI() {
    return (
      Boolean(this.args.model.batchedAI) && allowsAIRequests(this.args.model)
    );
  }
  get hasWarnings() {
    return !this.hasScript || this.showsBatchedAI;
  }
  get hasRunFacts() {
    return Boolean(this.nextRun || this.lastRun);
  }
  // The next run, only while Boxel runs the automation.
  get nextRun() {
    let status = this.status;
    return status?.switchedOn && status.state === 'active'
      ? (status.nextRun ?? undefined)
      : undefined;
  }
  get lastRun() {
    let status = this.status;
    if (!status?.switchedOn || !status.lastFinishedAt) {
      return undefined;
    }
    let result = lastRunText(status);
    return result
      ? {
          label: `Last run ${result.toLowerCase()}`,
          at: status.lastFinishedAt,
          result: status.lastResult,
        }
      : undefined;
  }
  get shownRun() {
    let run = this.status?.currentRun ?? this.status?.lastRun;
    return run && (run.milestones.length > 0 || run.plan.length > 0)
      ? run
      : undefined;
  }
  @cached
  get milestones(): MilestoneGlance | undefined {
    if (!this.server.current.known) {
      return undefined;
    }
    let run = this.shownRun;
    if (run) {
      return milestoneGlance(runMilestoneRows(run), run);
    }
    let text = this.script.current.text;
    let plan = text ? declaredMilestones(text) : undefined;
    return plan
      ? milestoneGlance(declaredMilestoneRows(plan), undefined)
      : undefined;
  }
  get milestoneValueText() {
    let m = this.milestones;
    return m ? `${m.headline}. ${m.count} ${milestoneWord(m.total)} done.` : '';
  }
  get stepped() {
    return (this.milestones?.total ?? 0) <= 12;
  }
  // Each trigger in words, for a view with room for more than the first.
  get triggerSummary() {
    let lines = this.triggers.slice(0, 3).map((trigger) => ({
      kind: trigger.kind,
      text: triggerPhrase(trigger),
    }));
    let more = this.triggers.length - lines.length;
    return {
      lines,
      more:
        more > 0
          ? `Plus ${tally(more)} more ${more === 1 ? 'trigger' : 'triggers'}`
          : undefined,
    };
  }
  // What one run may spend: its time limit, and its AI credits when the
  // limits allow AI requests.
  get runLimit() {
    let caps = this.args.model.caps;
    if (typeof caps?.seconds !== 'number') {
      return undefined;
    }
    let time = `Up to ${duration(caps.seconds)}`;
    return allowsAIRequests(this.args.model)
      ? `${time} and ${count(caps.aiCredits)} AI credits`
      : time;
  }
  // The outside services a run may call: each operation in words, with the
  // card type that declares it.
  get serviceNames(): string[] {
    return (this.args.model.operations ?? [])
      .filter((op) => op.operation && op.targetType?.name)
      .map((op) => `${operationTitle(op.operation)} (${op.targetType!.name})`);
  }
  get services() {
    let names = this.serviceNames;
    if (names.length === 0) {
      return 'None';
    }
    let shown = names.slice(0, 3).join(', ');
    let more = names.length - 3;
    return more > 0 ? `${shown}, plus ${tally(more)} more` : shown;
  }

  // Why Boxel holds the automation's runs, or why the last one failed, for a
  // direct writer: a pause, waiting for credits or for key approval, or a
  // failure streak.
  get statusNote() {
    let status = this.status;
    if (!status?.switchedOn) {
      return undefined;
    }
    if (
      status.state === 'paused' ||
      status.state === 'waiting-for-credits' ||
      status.state === 'waiting-for-key-approval'
    ) {
      return stateSentence(status);
    }
    let error = status.lastFailure?.message || status.lastFailure?.reason;
    return status.failuresInARow && error ? `Last error: ${error}` : undefined;
  }
  // Each limit the automation is near or at: this month's and today's spend
  // against the credit caps, and what the last run used of each per-run
  // limit. Near from 80% of a limit, reached at 100%. Most severe first.
  get limitsNear(): LimitNear[] {
    let status = this.status;
    let caps = this.args.model.caps;
    let near: LimitNear[] = [];
    let consider = (
      name: string,
      short: string,
      used: number | null | undefined,
      cap: number | null | undefined,
      period: string,
      show: (n: number) => string = tally,
    ) => {
      if (typeof used !== 'number' || typeof cap !== 'number' || cap <= 0) {
        return;
      }
      let share = used / cap;
      if (share < LIMIT_NEAR_SHARE) {
        return;
      }
      near.push({
        name,
        short,
        reached: share >= 1,
        share,
        text: `${name}: ${show(used)} of ${show(cap)} ${period}`,
      });
    };
    if (status?.switchedOn) {
      consider(
        'Monthly credits',
        'Monthly',
        status.spentThisMonth,
        status.monthlyCredits,
        'this month',
      );
      consider(
        'Daily credits',
        'Daily',
        status.spentToday,
        status.dailyCredits,
        'today',
      );
    }
    let usage = status?.lastRunUsage;
    if (usage) {
      consider(
        'Outside calls',
        'Calls',
        usage.callApiCalls,
        caps?.callApiCalls,
        'last run',
      );
      consider(
        'Response size',
        'Response size',
        usage.responseBytes,
        caps?.responseBytes,
        'last run',
        bytes,
      );
      consider(
        'AI requests',
        'AI requests',
        usage.resolveCalls,
        caps?.resolveCalls,
        'last run',
      );
      consider(
        'AI credits',
        'AI credits',
        usage.aiCredits,
        caps?.aiCredits,
        'last run',
      );
      consider('Saves', 'Saves', usage.writes, caps?.writes, 'last run');
      consider(
        'Run time',
        'Run time',
        usage.seconds,
        caps?.seconds,
        'last run',
        duration,
      );
    }
    return near.sort(
      (a, b) => Number(b.reached) - Number(a.reached) || b.share - a.share,
    );
  }
  // The limits as one short chip naming the most pressing one: "AI
  // requests at limit", "Monthly near limit", with "+2" for the others.
  get limitLook():
    | { label: string; tone: 'warning' | 'danger'; hue: string }
    | undefined {
    let [first, ...rest] = this.limitsNear;
    if (!first) {
      return undefined;
    }
    let label = `${first.short} ${first.reached ? 'at' : 'near'} limit${
      rest.length ? ` +${tally(rest.length)}` : ''
    }`;
    return first.reached
      ? { label, tone: 'danger', hue: 'var(--destructive)' }
      : { label, tone: 'warning', hue: 'var(--warning)' };
  }
  // The monthly spend bar's color: red at the monthly cap, amber near it.
  get spendHue() {
    let monthly = this.limitsNear.find(
      (limit) => limit.name === 'Monthly credits',
    );
    return monthly
      ? monthly.reached
        ? 'var(--destructive)'
        : 'var(--warning)'
      : undefined;
  }
  // This month's spend against the monthly cap, as a share for a bar.
  get spendShare() {
    let status = this.status;
    if (
      !status?.switchedOn ||
      typeof status.spentThisMonth !== 'number' ||
      typeof status.monthlyCredits !== 'number' ||
      status.monthlyCredits <= 0
    ) {
      return undefined;
    }
    return {
      spent: status.spentThisMonth,
      value: Math.min(status.spentThisMonth, status.monthlyCredits),
      max: status.monthlyCredits,
    };
  }
  // Who pays, for a direct writer's view: "Nobody yet" until someone turns
  // the automation on.
  get payer() {
    let status = this.status;
    return status ? payerText(status) : undefined;
  }
  // The spending line's label and value: this month's spend against the
  // monthly cap once the automation is on, or the monthly cap the card sets
  // until then.
  get spendLabel() {
    return this.status?.switchedOn ? 'This month' : 'Monthly limit';
  }
  get spending() {
    let status = this.status;
    if (!status) {
      return undefined;
    }
    if (!status.switchedOn) {
      let cap = this.args.model.caps?.monthlyCredits;
      return typeof cap === 'number'
        ? `Up to ${tally(cap)} credits a month`
        : 'No monthly limit';
    }
    if (typeof status.spentThisMonth !== 'number') {
      return undefined;
    }
    let spent = tally(status.spentThisMonth);
    return typeof status.monthlyCredits === 'number'
      ? `${spent} of ${tally(status.monthlyCredits)} credits`
      : `${spent} credits, with no monthly limit`;
  }
}

// Sixteen sizes, one layout: each step up in height adds the next most useful
// fact. A single line holds the title and, in a strip, the state. Then the
// first trigger, or where a running or failed run stands. Then the milestones
// as a bar. A tile adds the last run and the warnings; a card, or a tile from
// 240px tall, also the other triggers and the next run; a tile from 240px
// wide and 270px tall lists the milestones in place of the bar. A wide card,
// from 560px wide and 165px tall (the Extra Wide Card fitted size), also shows
// who pays and this month's spend against the monthly cap, in a column of its
// own. The root is the size container, so every rule queries its content box;
// the padding sits on the body inside it.
class Fitted extends AtAGlance {
  get focusLine() {
    let m = this.milestones;
    return m && (m.kind === 'running' || m.kind === 'failed')
      ? m.headline
      : this.when;
  }
  // The milestones as the fitted lists show them: each step's detail ends
  // with the milestone's last task, joined by index here once, so the lists
  // window over these steps rather than finding each one again.
  @cached
  get fittedMilestones(): MilestoneGlance | undefined {
    let milestones = this.milestones;
    if (!milestones) {
      return undefined;
    }
    let { lastTasks } = milestones;
    return {
      ...milestones,
      steps: milestones.steps.map((step, index) => {
        let detail = [step.detail, lastTasks[index]]
          .filter(Boolean)
          .join(' · ');
        return {
          label: step.label,
          state: step.state,
          ...(detail ? { detail } : {}),
        };
      }),
    };
  }
  // The fitted lists name each milestone, with its time, last task or where
  // Boxel stopped the run beside it.
  private list(size: number) {
    if (!this.fittedMilestones) {
      return { steps: [], earlier: undefined, later: undefined };
    }
    return stepWindow(this.fittedMilestones, size);
  }
  // The space the card leaves the list under the bar (`fitToSpace`), in
  // pixels: the list names as many milestones as fit there around the one
  // in focus, so the run's milestone is always named and its neighbours join
  // as the card grows. With room for two lines a milestone, each also shows
  // its time and last task.
  @tracked private spaceForList = 0;
  @tracked private rowHeight = 24;
  // The stretch of rail that marks milestones before or after the list
  // takes a little height too.
  private static moreHeight = 6;
  get fitDetails() {
    let total = this.milestones?.total ?? 0;
    return total > 0 && total * this.rowHeight * 2 <= this.spaceForList;
  }
  get fitList() {
    let none = { steps: [], earlier: undefined, later: undefined };
    let milestones = this.fittedMilestones;
    let total = milestones?.total ?? 0;
    let space = this.spaceForList;
    if (!milestones || total === 0) {
      return none;
    }
    let row = this.fitDetails ? this.rowHeight * 2 : this.rowHeight;
    if (total * row <= space) {
      return this.list(total);
    }
    // A shorter list says what it leaves out, with a line before or after
    // it, so the list keeps as many milestones as fit beside those lines.
    let more = Fitted.moreHeight;
    for (
      let size = Math.min(total - 1, Math.floor(space / row));
      size >= 1;
      size--
    ) {
      let window = stepWindow(milestones, size);
      let before = milestones.steps.indexOf(window.steps[0]);
      let after = total - before - window.steps.length;
      let needed =
        size * row + (before > 0 ? more : 0) + (after > 0 ? more : 0);
      if (needed <= space) {
        return {
          steps: window.steps,
          earlier:
            before > 0
              ? `${tally(before)} earlier ${milestoneWord(before)}`
              : undefined,
          later:
            after > 0
              ? `${tally(after)} more ${milestoneWord(after)}`
              : undefined,
        };
      }
    }
    return none;
  }
  // Measures the space the milestone list has, and the height of one of its
  // rows, whenever the card or anything shown after the list changes size,
  // and whenever something after the list appears.
  private fitToSpace = modifier((element: HTMLElement) => {
    let root = element.closest('[data-fit-root]') as HTMLElement | null;
    let body = element.closest('[data-fit-body]') as HTMLElement | null;
    let block = element.closest('[data-fit-milestones]') as HTMLElement | null;
    if (
      !root ||
      !body ||
      !block ||
      typeof ResizeObserver === 'undefined' ||
      typeof MutationObserver === 'undefined'
    ) {
      return;
    }
    let measure = () => {
      let rootBox = root!.getBoundingClientRect();
      let top = element.getBoundingClientRect().top;
      // Whatever shows after the milestones takes its space first.
      let after = 0;
      for (
        let next = block!.nextElementSibling as HTMLElement | null;
        next;
        next = next.nextElementSibling as HTMLElement | null
      ) {
        if (next.offsetParent !== null && next.offsetHeight > 0) {
          after += next.offsetHeight + 6;
        }
      }
      let padding = parseFloat(getComputedStyle(body!).paddingBottom);
      let lineHeight = parseFloat(getComputedStyle(element).lineHeight) || 18;
      // The list may run part way into the card's bottom padding: the
      // stretch of rail that marks later milestones is small enough to sit
      // there.
      let available = Math.max(
        0,
        Math.floor(rootBox.bottom - top - after - padding / 2),
      );
      if (available !== this.spaceForList) {
        this.spaceForList = available;
      }
      // A row's height without its detail line. A row with one is two
      // lines tall, so it counts half when every row has one.
      let rows = [...element.querySelectorAll('li')] as HTMLElement[];
      let plain = rows.find(
        (row) => !row.querySelector('[data-milestone-detail]'),
      );
      let rowHeight = plain
        ? Math.ceil(plain.getBoundingClientRect().height)
        : rows[0]
          ? Math.ceil(rows[0].getBoundingClientRect().height / 2)
          : lineHeight + 6;
      if (rowHeight !== this.rowHeight) {
        this.rowHeight = rowHeight;
      }
    };
    let resized = new ResizeObserver(() => measure());
    // The card's own size, and each element after the list: one that goes
    // from hidden to shown, or wraps onto another line, takes space from
    // the list.
    let watchAfterList = () => {
      for (
        let next = block!.nextElementSibling;
        next;
        next = next.nextElementSibling
      ) {
        resized.observe(next);
      }
    };
    resized.observe(root);
    watchAfterList();
    // An element rendered after the list later, such as a limit chip once
    // the status arrives, is watched too.
    let added = new MutationObserver(() => {
      watchAfterList();
      measure();
    });
    added.observe(body, { childList: true });
    // After the render that installed the modifier, so the measurement
    // never updates state that render read.
    let frame = requestAnimationFrame(measure);
    return () => {
      cancelAnimationFrame(frame);
      resized.disconnect();
      added.disconnect();
    };
  });
  <template>
    <div class='af' data-fit-root data-test-automation-fitted>
      <div class='af__body' data-fit-body>
        <div class='af__head'>
          <span class='af__icon' aria-hidden='true'>
            <CalendarClockIcon width='16' height='16' />
          </span>
          <div class='af__heading'>
            <p class='af__eyebrow'>Automation</p>
            <h3 class='af__title'>{{@model.cardTitle}}</h3>
          </div>
          {{#if this.look}}
            <Chip
              class='af__state'
              @label={{this.look.label}}
              @tone={{this.look.tone}}
              data-test-automation-fitted-state={{this.look.label}}
            />
          {{/if}}
          <ShowInConsole
            class='af__console'
            @model={{@model}}
            @context={{@context}}
            @directWriter={{this.directWriter}}
            @iconOnly={{true}}
          />
        </div>

        {{#if this.payer}}
          <div class='af__money' data-test-automation-fitted-money>
            <dl class='af__pairs'>
              <div class='af__money-pair'>
                <dt>Payer</dt>
                <dd data-test-automation-fitted-payer>{{this.payer}}</dd>
              </div>
              {{#if this.spending}}
                <div class='af__money-pair'>
                  <dt>{{this.spendLabel}}</dt>
                  <dd
                    data-test-automation-fitted-spending
                  >{{this.spending}}</dd>
                </div>
              {{/if}}
            </dl>
            {{#if this.spendShare}}
              <ProgressBar
                class='af__spend-bar'
                @value={{this.spendShare.value}}
                @max={{this.spendShare.max}}
                @hue={{this.spendHue}}
                @valueText={{this.spending}}
                aria-label='This month’s spending'
              />
            {{/if}}
            <dl class='af__pairs af__pairs--extra'>
              {{#if this.runLimit}}
                <div class='af__money-pair'>
                  <dt>Each run</dt>
                  <dd
                    data-test-automation-fitted-run-limit
                  >{{this.runLimit}}</dd>
                </div>
              {{/if}}
              <div class='af__money-pair'>
                <dt>Outside services</dt>
                <dd data-test-automation-fitted-services>{{this.services}}</dd>
              </div>
            </dl>
            {{#if this.statusNote}}
              <p
                class='af__note'
                data-test-automation-fitted-note
              >{{this.statusNote}}</p>
            {{/if}}
            {{#if this.limitsNear.length}}
              <ul class='af__limits' data-test-automation-fitted-limits>
                {{#each this.limitsNear as |limit|}}
                  <li
                    class='af__limit'
                    data-reached={{if limit.reached 'true' 'false'}}
                    data-test-automation-fitted-limit-item={{limit.name}}
                  >
                    <span class='af__limit-icon' aria-hidden='true'>
                      {{#if limit.reached}}
                        <OctagonAlertIcon width='12' height='12' />
                      {{else}}
                        <AlertTriangleIcon width='12' height='12' />
                      {{/if}}
                    </span>
                    <span class='af__limit-text'>{{limit.text}}</span>
                  </li>
                {{/each}}
              </ul>
            {{/if}}
          </div>
        {{/if}}

        <p class='af__focus' data-test-automation-fitted-focus>
          {{this.focusLine}}
        </p>

        <p class='af__when' data-test-automation-fitted-when>
          {{#if (eq this.firstKind 'cron')}}
            <RepeatIcon width='13' height='13' aria-hidden='true' />
          {{else if (eq this.firstKind 'once')}}
            <CalendarCheckIcon width='13' height='13' aria-hidden='true' />
          {{else if this.firstKind}}
            <ZapIcon width='13' height='13' aria-hidden='true' />
          {{/if}}
          <span>{{this.when}}</span>
        </p>
        {{#if this.moreTriggers}}
          <p class='af__more' data-test-automation-fitted-more>
            {{this.moreTriggers}}
          </p>
        {{/if}}
        <ul class='af__triggers' data-test-automation-fitted-triggers>
          {{#each this.triggerSummary.lines as |line|}}
            <li class='af__trigger'>
              {{#if (eq line.kind 'cron')}}
                <RepeatIcon width='13' height='13' aria-hidden='true' />
              {{else if (eq line.kind 'once')}}
                <CalendarCheckIcon width='13' height='13' aria-hidden='true' />
              {{else if line.kind}}
                <ZapIcon width='13' height='13' aria-hidden='true' />
              {{/if}}
              <span>{{line.text}}</span>
            </li>
          {{/each}}
          {{#if this.triggerSummary.more}}
            <li class='af__trigger af__trigger--more'>
              {{this.triggerSummary.more}}
            </li>
          {{/if}}
        </ul>

        {{#if this.nextRun}}
          <p class='af__fact af__fact--next' data-test-automation-fitted-next>
            Next run
            <FormatDate
              @date={{this.nextRun}}
              @month='short'
              @day='numeric'
              @hour='numeric'
              @minute='2-digit'
            />
          </p>
        {{/if}}
        {{#if this.serviceNames.length}}
          <p
            class='af__fact af__fact--services'
            data-test-automation-fitted-services-line
          >
            <PlugIcon width='13' height='13' aria-hidden='true' />
            <span>Calls {{this.services}}</span>
          </p>
        {{/if}}
        {{#if this.payer}}
          <p
            class='af__fact af__fact--payer'
            data-test-automation-fitted-paid-by
          >
            Paid by
            {{lowerFirst this.payer}}
          </p>
        {{/if}}
        {{#if this.lastRun}}
          <p
            class='af__fact af__fact--last'
            data-result={{this.lastRun.result}}
            data-test-automation-fitted-last={{this.lastRun.result}}
          >
            {{this.lastRun.label}}
            <RelativeTime @date={{this.lastRun.at}} />
          </p>
        {{/if}}

        {{#if this.milestones}}
          <div
            class='af__milestones'
            data-fit-milestones
            data-kind={{this.milestones.kind}}
            data-test-automation-fitted-milestones={{this.milestones.kind}}
          >
            <p class='af__headline'>
              <span
                class='af__headline-text'
              >{{this.milestones.headline}}</span>
              <span class='af__count'>{{this.milestones.count}}</span>
            </p>
            <ProgressBar
              class='af__bar'
              @value={{this.milestones.done}}
              @max={{this.milestones.total}}
              @steps={{this.stepped}}
              @hue={{this.milestones.hue}}
              @valueText={{this.milestoneValueText}}
              aria-label='Milestones'
            />
            <div class='af__fit' {{this.fitToSpace}}>
              {{#if this.fitList.steps.length}}
                <FittedMilestones
                  @steps={{this.fitList.steps}}
                  @details={{this.fitDetails}}
                  @earlier={{this.fitList.earlier}}
                  @later={{this.fitList.later}}
                />
              {{/if}}
            </div>
          </div>
        {{/if}}

        {{#unless this.hasScript}}
          <p class='af__hint' data-test-automation-fitted-hint>
            Add a script in the edit view to run this automation.
          </p>
        {{/unless}}

        {{#if @model.cardDescription}}
          <p class='af__summary'>{{@model.cardDescription}}</p>
        {{/if}}

        {{#if (or this.hasWarnings (bool this.look) (bool this.limitLook))}}
          <div class='af__chips'>
            {{#if this.limitLook}}
              <Chip
                @label={{this.limitLook.label}}
                @tone={{this.limitLook.tone}}
                data-test-automation-fitted-limit={{this.limitLook.tone}}
              />
            {{/if}}
            {{#if this.look}}
              <Chip
                class='af__state-foot'
                @label={{this.look.label}}
                @tone={{this.look.tone}}
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
                data-test-automation-fitted-batched-ai
              />
            {{/if}}
          </div>
        {{/if}}
      </div>
    </div>
    <style scoped>
      .af {
        container-type: size;
        inline-size: 100%;
        block-size: 100%;
        overflow: hidden;
      }
      .af__body {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        box-sizing: border-box;
        block-size: 100%;
        padding: var(--boxel-sp-xs);
        overflow: hidden;
        color: var(--foreground);
        font-size: var(--boxel-font-size-xs);
        line-height: var(--boxel-line-height-xs);
      }
      /* A line that doesn't fit is cut at the bottom of the card rather than
         squeezed into the lines above it. */
      .af__body > * {
        flex-shrink: 0;
      }
      .af__head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
        flex-shrink: 0;
      }
      .af__icon {
        display: grid;
        place-items: center;
        flex-shrink: 0;
        inline-size: 1.5rem;
        block-size: 1.5rem;
        border-radius: var(--radius);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .af__heading {
        flex: 1;
        min-inline-size: 0;
      }
      .af__eyebrow {
        display: none;
        color: var(--muted-foreground);
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
      }
      .af__title {
        overflow: hidden;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        line-height: var(--boxel-line-height-sm);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .af__state {
        display: none;
        flex-shrink: 0;
      }
      .af__console {
        display: none;
        flex-shrink: 0;
      }
      .af__focus,
      .af__when,
      .af__more,
      .af__fact,
      .af__milestones,
      .af__summary,
      .af__chips,
      .af__money,
      .af__triggers {
        display: none;
      }
      .af__triggers {
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        margin: 0;
        padding: 0;
        list-style: none;
        color: var(--muted-foreground);
      }
      .af__trigger {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .af__trigger > svg {
        flex-shrink: 0;
      }
      /* The ellipsis goes on the text, since a flex container cuts its
         content without one. */
      .af__trigger > span {
        min-inline-size: 0;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .af__spend-bar {
        margin-block-start: var(--boxel-sp-6xs);
      }
      .af__limits {
        display: grid;
        gap: var(--boxel-sp-6xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      /* A caution sign marks a limit drawing near and a stop sign one
         reached, each centered on the limit's first line. A limit wraps
         onto a second line before it is cut. */
      .af__limit {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp-5xs);
        color: var(--warning-ink);
      }
      .af__limit-icon {
        display: flex;
        align-items: center;
        block-size: 1lh;
      }
      .af__limit-text {
        display: -webkit-box;
        overflow: hidden;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
      }
      .af__limit[data-reached='true'] {
        color: var(--destructive-ink);
      }
      .af__note {
        margin: 0;
        color: var(--muted-foreground);
        display: -webkit-box;
        overflow: hidden;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 3;
      }
      .af__money {
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        margin: 0;
        padding-inline-start: var(--boxel-sp-sm);
        border-inline-start: 1px solid var(--border);
      }
      /* The pairs read as one list to a screen reader; the spending bar,
         the note and the limits sit between and after the lists. */
      .af__pairs {
        display: flex;
        flex-direction: column;
        gap: inherit;
        margin: 0;
      }
      .af__money-pair {
        display: grid;
        gap: var(--boxel-sp-6xs);
        min-inline-size: 0;
      }
      .af__money dt {
        color: var(--muted-foreground);
      }
      .af__money dd {
        margin: 0;
        overflow: hidden;
        font-weight: 600;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .af__focus,
      .af__when,
      .af__fact,
      .af__more {
        overflow: hidden;
        color: var(--muted-foreground);
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .af__when {
        align-items: center;
        gap: var(--boxel-sp-5xs);
      }
      .af__when > svg {
        flex-shrink: 0;
      }
      .af__when > span {
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .af__fact--services {
        align-items: center;
        gap: var(--boxel-sp-5xs);
      }
      .af__fact--services > svg {
        flex-shrink: 0;
      }
      .af__fact--services > span {
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .af__fact[data-result='error'] {
        color: var(--destructive-ink);
      }
      .af__milestones {
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        min-inline-size: 0;
      }
      .af__headline {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        min-inline-size: 0;
      }
      .af__headline-text {
        overflow: hidden;
        font-weight: 600;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .af__milestones[data-kind='failed'] .af__headline-text {
        color: var(--destructive-ink);
      }
      .af__count {
        flex-shrink: 0;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .af__list-more {
        color: var(--muted-foreground);
      }
      /* The milestones in the colors the isolated view gives them: green
         once done, blue while running, red where the run failed and gray
         where Boxel stopped the run. A short list can start partway through
         the run, so it leaves out the step numbers, which would count from
         its own first row. */
      .af__list {
        --pretui-step-upcoming-marker-fg: transparent;
        --pretui-step-complete-bar: var(--success);
        --pretui-step-in-progress-bar: var(--info);
        --pretui-step-in-progress-ring: var(--info);
        --pretui-step-in-progress-marker-fg: var(--info-ink);
        --pretui-step-blocked-tone: var(--foreground);
        --pretui-step-blocked-marker-fg: var(--muted-foreground);
        --pretui-step-blocked-ring: var(--muted-foreground);
        --pretui-step-blocked-bar: var(--muted-foreground);
      }
      .af__summary {
        display: none;
        overflow: hidden;
        color: var(--muted-foreground);
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 3;
      }
      .af__chips {
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
        margin-block-start: auto;
      }
      .af__state-foot,
      .af__hint {
        display: none;
      }
      .af__hint {
        color: var(--muted-foreground);
      }

      /* A strip has room for the state, and the way into the console,
         beside the title. */
      @container (min-width: 240px) {
        .af__state,
        .af__console {
          display: inline-flex;
        }
      }
      /* Two lines: the first trigger, or where a running or failed run
         stands. */
      @container (min-height: 60px) {
        .af__focus {
          display: block;
        }
      }
      /* Three lines: the first trigger, and the milestones as a bar. */
      @container (min-height: 100px) {
        .af__focus {
          display: none;
        }
        .af__when {
          display: flex;
        }
        .af__milestones {
          display: flex;
        }
      }
      /* A tile: the eyebrow, a two-line title, the last run and the
         warnings. */
      @container (min-height: 165px) {
        .af__body {
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-sm);
        }
        .af__head {
          align-items: flex-start;
        }
        .af__icon {
          inline-size: 2rem;
          block-size: 2rem;
        }
        .af__eyebrow {
          display: block;
        }
        .af__title {
          display: -webkit-box;
          white-space: normal;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
        }
        .af__fact--last,
        .af__fact--payer,
        .af__hint {
          display: block;
        }
        .af__chips {
          display: flex;
        }
        .af__milestones {
          margin-block-start: var(--boxel-sp-4xs);
        }
      }
      /* A card, or a tall tile: the other triggers and the next run too. */
      @container (min-height: 165px) and (min-width: 390px),
        (min-height: 240px) {
        .af__more,
        .af__fact {
          display: block;
        }
      }
      /* The outside services, on a card or tile tall enough. */
      .af__fact.af__fact--services {
        display: none;
      }
      @container (min-height: 240px) and (min-width: 240px) {
        .af__fact.af__fact--services {
          display: flex;
        }
      }
      /* A short card already shows the next and last run, so it leaves out
         the payer line, which would push the chips off the bottom. */
      @container (min-height: 165px) and (max-height: 239px) and (min-width: 390px) {
        .af__fact--payer {
          display: none;
        }
      }
      /* A small, narrow tile leaves out the payer line, so the chips can wrap
         onto a second line. */
      @container (max-width: 239px) and (max-height: 239px) {
        .af__fact--payer {
          display: none;
        }
      }
      /* A tall, narrow tile has no room for the milestones' list, so it
         spends the height on the description. */
      @container (min-height: 270px) and (max-width: 239px) {
        .af__summary {
          display: -webkit-box;
        }
      }
      /* A narrow tile gives the title the whole width, and the state moves
         to the footer. */
      @container (min-height: 165px) and (max-width: 239px) {
        .af__icon,
        .af__state {
          display: none;
        }
        .af__state-foot {
          display: inline-flex;
        }
      }
      /* A wide strip, such as the realm config's: three columns, so the
         strip's width shows what a taller card stacks. The title, state and
         first trigger with the last run; the milestones with the next run;
         and who pays, this month's spend and the closest limit. */
      @container (min-width: 560px) and (min-height: 100px) and (max-height: 164px) {
        .af__body {
          display: grid;
          grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr) minmax(0, 1fr);
          grid-template-rows: auto auto auto auto 1fr;
          column-gap: var(--boxel-sp);
          row-gap: var(--boxel-sp-5xs);
          align-content: start;
        }
        .af__body:not(:has(.af__money)) {
          grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr);
        }
        .af__head {
          grid-column: 1;
          grid-row: 1;
        }
        .af__when {
          display: flex;
          grid-column: 1;
          grid-row: 2;
        }
        .af__fact--next {
          display: block;
          grid-column: 1;
          grid-row: 3;
        }
        .af__fact--last {
          display: block;
          grid-column: 1;
          grid-row: 4;
        }
        .af__milestones {
          display: flex;
          grid-column: 2;
          grid-row: 1 / -1;
        }
        .af__money {
          display: flex;
          grid-column: 3;
          grid-row: 1 / -1;
          gap: var(--boxel-sp-6xs);
        }
        .af__money-pair {
          grid-template-columns: auto minmax(0, 1fr);
          column-gap: var(--boxel-sp-4xs);
          align-items: baseline;
        }
        .af__spend-bar,
        .af__note,
        .af__pairs--extra,
        .af__limit:not(:first-child),
        .af__focus,
        .af__more,
        .af__triggers,
        .af__fact--payer,
        .af__summary,
        .af__chips,
        .af__hint {
          display: none;
        }
      }
      /* A wide card, such as the Extra Wide Card fitted size: who pays and
         this month's spend, in a column beside the rest. */
      @container (min-height: 165px) and (min-width: 560px) {
        .af__body {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 14rem);
          grid-auto-rows: min-content;
          column-gap: var(--boxel-sp);
          align-content: start;
        }
        .af__body > * {
          grid-column: 1;
        }
        .af__head {
          grid-column: 1 / -1;
        }
        .af__body:not(:has(.af__money)) {
          grid-template-columns: minmax(0, 1fr);
        }
        .af__money {
          display: flex;
          grid-column: 2;
          grid-row: 2 / span 12;
        }
        .af__money-pair {
          grid-template-columns: auto minmax(0, 1fr);
          column-gap: var(--boxel-sp-4xs);
          align-items: baseline;
        }
        .af__spend-bar {
          grid-column: 1 / -1;
        }
        .af__summary {
          display: -webkit-box;
          -webkit-line-clamp: 2;
        }
        .af__when,
        .af__more,
        .af__fact--payer {
          display: none;
        }
        .af__triggers {
          display: flex;
        }
      }
      /* The tallest card: the description too. */
      @container (min-height: 440px) and (min-width: 240px) {
        .af__summary {
          display: -webkit-box;
        }
      }
    </style>
  </template>
}

// The automation as a row in a list: the title and state, each trigger in
// words, the next and last run, and the milestones, as a bar with where the
// run stands when narrow and as a track of every milestone when wide. The
// root is the inline-size container, so the padding sits on the body inside
// it.
class Embedded extends AtAGlance {
  get triggerLines() {
    return this.triggers.map((trigger) => ({
      kind: trigger.kind,
      phrase: triggerPhrase(trigger),
    }));
  }
  // A track of more than eight milestones is too dense to read, so a longer
  // run keeps the bar at every width.
  get showsTrack() {
    return (this.milestones?.total ?? 0) <= 8;
  }
  <template>
    <div class='ae' data-test-automation-embedded>
      <div class='ae__body'>
        {{! Item lays out an actions column whenever it gets an actions block,
            so the block is passed only to a viewer the action shows to. }}
        {{#if this.showsConsoleAction}}
          <Item
            @size='s'
            @alignStart={{true}}
            @title={{@model.cardTitle}}
            @description={{@model.cardDescription}}
          >
            <:leading>
              <span class='ae__icon' aria-hidden='true'>
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
            <:actions>
              <ShowInConsole
                @model={{@model}}
                @context={{@context}}
                @directWriter={{this.directWriter}}
              />
            </:actions>
          </Item>
        {{else}}
          <Item
            @size='s'
            @alignStart={{true}}
            @title={{@model.cardTitle}}
            @description={{@model.cardDescription}}
          >
            <:leading>
              <span class='ae__icon' aria-hidden='true'>
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
        {{/if}}

        {{#if this.triggerLines.length}}
          <div class='ae__grid'>
            <Stack @gap='none' class='ae__triggers'>
              {{#each this.triggerLines as |trigger|}}
                <Item
                  @size='xs'
                  @title={{trigger.phrase}}
                  data-test-automation-embedded-trigger
                >
                  <:leading>
                    {{#if (eq trigger.kind 'cron')}}
                      <RepeatIcon width='14' height='14' aria-hidden='true' />
                    {{else if (eq trigger.kind 'once')}}
                      <CalendarCheckIcon
                        width='14'
                        height='14'
                        aria-hidden='true'
                      />
                    {{else}}
                      <ZapIcon width='14' height='14' aria-hidden='true' />
                    {{/if}}
                  </:leading>
                </Item>
              {{/each}}
            </Stack>
            {{#if this.hasRunFacts}}
              <div class='ae__runs'>
                {{#if this.nextRun}}
                  <p class='ae__fact' data-test-automation-embedded-next>
                    <span class='ae__label'>Next run</span>
                    <FormatDate
                      @date={{this.nextRun}}
                      @month='short'
                      @day='numeric'
                      @hour='numeric'
                      @minute='2-digit'
                      @timeZoneName='short'
                    />
                  </p>
                {{/if}}
                {{#if this.lastRun}}
                  <p
                    class='ae__fact'
                    data-result={{this.lastRun.result}}
                    data-test-automation-embedded-last={{this.lastRun.result}}
                  >
                    <span class='ae__label'>{{this.lastRun.label}}</span>
                    <RelativeTime @date={{this.lastRun.at}} />
                  </p>
                {{/if}}
              </div>
            {{/if}}
          </div>
        {{else}}
          <EmptyState
            @size='s'
            @texture={{false}}
            @title='No triggers'
            @message='Add a schedule, a one-time run or a webhook in the edit view.'
          />
        {{/if}}

        {{#if this.milestones}}
          <div
            class='ae__milestones'
            data-kind={{this.milestones.kind}}
            data-track={{if this.showsTrack 'true' 'false'}}
            data-test-automation-embedded-milestones={{this.milestones.kind}}
          >
            <p class='ae__headline'>
              <span
                class='ae__headline-text'
              >{{this.milestones.headline}}</span>
              <span class='ae__count'>{{this.milestones.count}}</span>
            </p>
            <ProgressBar
              class='ae__bar'
              @value={{this.milestones.done}}
              @max={{this.milestones.total}}
              @steps={{this.stepped}}
              @hue={{this.milestones.hue}}
              @valueText={{this.milestoneValueText}}
              aria-label='Milestones'
            />
            {{#if this.showsTrack}}
              <div class='ae__track'>
                <StepList
                  @steps={{this.milestones.steps}}
                  @variant='track'
                  @announce={{false}}
                  @label='Milestones'
                />
              </div>
            {{/if}}
          </div>
        {{/if}}

        {{#if this.hasWarnings}}
          <div class='ae__chips'>
            {{#unless this.hasScript}}
              <Chip
                @label='No script yet'
                @tone='warning'
                data-test-automation-embedded-no-script
              />
            {{/unless}}
            {{#if this.showsBatchedAI}}
              <Chip
                @label='Batched AI'
                @tone='info'
                data-test-automation-embedded-batched-ai
              />
            {{/if}}
          </div>
        {{/if}}
      </div>
    </div>
    <style scoped>
      .ae {
        container-type: inline-size;
      }
      .ae__body {
        display: grid;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-xs);
        line-height: var(--boxel-line-height-xs);
      }
      .ae__icon {
        display: grid;
        place-items: center;
        width: 2.25rem;
        height: 2.25rem;
        border-radius: var(--radius);
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .ae__grid {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .ae__triggers {
        color: var(--muted-foreground);
      }
      .ae__runs {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
      }
      .ae__fact {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-5xs);
      }
      .ae__label {
        color: var(--muted-foreground);
      }
      .ae__fact[data-result='error'] .ae__label {
        color: var(--destructive-ink);
      }
      .ae__milestones {
        display: grid;
        gap: var(--boxel-sp-4xs);
        padding-block-start: var(--boxel-sp-xs);
        border-block-start: 1px solid var(--border);
      }
      .ae__headline {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      .ae__headline-text {
        font-weight: 600;
      }
      .ae__milestones[data-kind='failed'] .ae__headline-text {
        color: var(--destructive-ink);
      }
      .ae__count {
        flex-shrink: 0;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .ae__track {
        display: none;
        --pretui-step-complete-bar: var(--success);
        --pretui-step-in-progress-bar: var(--info);
        --pretui-step-in-progress-ring: var(--info);
        --pretui-step-in-progress-marker-fg: var(--info-ink);
        --pretui-step-blocked-tone: var(--foreground);
        --pretui-step-blocked-marker-fg: var(--muted-foreground);
        --pretui-step-blocked-ring: var(--muted-foreground);
        --pretui-step-blocked-bar: var(--muted-foreground);
      }
      .ae__chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      /* Wide enough for the triggers and the runs side by side. */
      @container (min-width: 36rem) {
        .ae__grid {
          grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
          align-items: start;
        }
        .ae__runs {
          flex-direction: column;
        }
      }
      /* Wide enough for a track of every milestone in place of the bar. */
      @container (min-width: 36rem) {
        .ae__milestones[data-track='true'] .ae__bar {
          display: none;
        }
        .ae__milestones[data-track='true'] .ae__track {
          display: block;
        }
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
