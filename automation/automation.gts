import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  FieldDef,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import TimeField from '@cardstack/base/time';
import CodeRefField from '@cardstack/base/code-ref';
import enumField from '@cardstack/base/enum';
import { FileDef } from '@cardstack/base/file-api';
import {
  operation,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';

// An automation's definition: the Realm Runner script it runs, when it runs,
// and what each run may do and spend. The server reads these fields from the
// index as data and never runs this module to learn them, so every field the
// server reads is a stored value, never a computed. Who pays for an
// automation and whether it is switched on are server state, not fields here.

export const AutomationTriggerKind = markDefinition(
  enumField(StringField, {
    displayName: 'Trigger Kind',
    options: [
      { value: 'cron', label: 'Cron schedule' },
      { value: 'once', label: 'Once' },
      { value: 'webhook', label: 'Webhook' },
    ],
  }),
);

// A name and a value handed to the script. Values are text; the script parses
// what it needs.
export class AutomationParam extends FieldDef {
  static displayName = 'Automation Param';

  @field name = contains(StringField);
  @field value = contains(StringField);
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
// `label` names the trigger within its automation. The server counts a
// trigger's runs by its label, so editing the trigger's schedule keeps its
// count and renaming it starts a new one.
export class AutomationTrigger extends FieldDef {
  static displayName = 'Automation Trigger';

  @field kind = contains(AutomationTriggerKind);
  @field label = contains(StringField);
  @field expression = contains(StringField);
  @field timeZone = contains(StringField);
  @field untilDate = contains(DateField);
  @field untilTime = contains(TimeField);
  @field count = contains(NumberField);
  @field date = contains(DateField);
  @field time = contains(TimeField);
  @field webhookPath = contains(StringField);
  // Merged over the automation's own `params` for runs this trigger starts.
  @field params = containsMany(AutomationParam);
}

// A `callApi` operation the script may call: the card type that declares it
// and the operation's name.
export class AutomationOperation extends FieldDef {
  static displayName = 'Automation Operation';

  @field targetType = contains(CodeRefField);
  @field operation = contains(StringField);
}

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
}
