import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import SettingsIcon from '@cardstack/boxel-icons/settings';

import { SlaWindowField } from '../sla-window/sla-window-field';
import { IntegrationReferenceField } from '../external-reference/external-reference-field';
import { AutomationPolicyField } from '../automation-policy/automation-policy-field';
import { isValidIdentifierPattern } from '../record-identifier/record-identifier-field';

/**
 * The bag of desk-level settings an app card carries once:
 * `@field config = contains(AppConfigurationField)`.
 *
 * App-agnostic on purpose — nothing here says "support". A billing desk keeps
 * its own id pattern, hours and policies in the same shape. The Setup Wizard
 * writes it step by step (`setupStep` is the resume point) and stamps
 * `setupCompletedAt` at the end; until then the app shows a quiet banner,
 * never a lockout.
 *
 * `identifierSeq` is the mint counter for Record Identifiers: incremented by
 * the creating command on every mint. A separate counter card would be
 * cleaner under concurrent writers, but this desk has one writer per realm —
 * recorded as a known trade-off, not an accident.
 */
export class AppConfigurationField extends FieldDef {
  static displayName = 'App Configuration';
  static icon = SettingsIcon;

  @field idPattern = contains(StringField, {
    description: 'Record Identifier pattern, e.g. CASE-{yyyy}-{seq4}.',
  });
  @field identifierSeq = contains(NumberField, {
    description: 'Mint counter. Written only by the creating command.',
  });
  @field defaultSlaWindow = contains(SlaWindowField);
  @field integrations = containsMany(IntegrationReferenceField);
  @field policies = containsMany(AutomationPolicyField);
  @field setupStep = contains(NumberField, {
    description: 'First incomplete wizard step; the wizard resumes here.',
  });
  @field setupCompletedAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: AppConfigurationField) {
      return this.setupCompletedAt
        ? 'Configured'
        : `Setup in progress (step ${this.setupStep ?? 1})`;
    },
  });

  get idPatternValid() {
    return isValidIdentifierPattern(this.idPattern);
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='cfg'>
        <div class='cfg-row'>
          <span class='cfg-k'>Ids</span>
          <code>{{if @model.idPattern @model.idPattern '—'}}</code>
        </div>
        <div class='cfg-row'>
          <span class='cfg-k'>Hours</span>
          <span>{{@model.defaultSlaWindow.title}}</span>
        </div>
        <div class='cfg-row'>
          <span class='cfg-k'>Policies</span>
          <span>{{@model.policies.length}} automation policies</span>
        </div>
        <div class='cfg-row'>
          <span class='cfg-k'>Setup</span>
          <span>{{@model.title}}</span>
        </div>
      </div>
      <style scoped>
        .cfg {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
        }
        .cfg-row {
          display: grid;
          grid-template-columns: 4.5rem 1fr;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
        }
        .cfg-k {
          font-size: var(--boxel-font-size-xs);
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        code {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='cfg-atom'>{{@model.title}}</span>
      <style scoped>
        .cfg-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default AppConfigurationField;
