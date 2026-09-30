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
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

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
    get items(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Ids', value: m?.idPattern ?? '' },
        { key: 'Hours', value: m?.defaultSlaWindow?.title ?? '' },
        {
          key: 'Policies',
          value: `${m?.policies?.length ?? 0} automation policies`,
        },
        { key: 'Setup', value: m?.title ?? '' },
      ];
    }
    <template>
      <KeyValue class='cfg' @items={{this.items}}>
        <:value as |item|>
          {{#if (eq item.key 'Ids')}}
            <code>{{if item.value item.value '—'}}</code>
          {{else}}
            {{item.value}}
          {{/if}}
        </:value>
      </KeyValue>
      <style scoped>
        /* Pret UI KeyValue at the field's own size, with its keys in the
           eyebrow role: KeyValue's key takes only a size, so the eyebrow's
           family, weight, tracking and case reach its dt from here. */
        .cfg {
          --text-ui-md: var(--boxel-font-size-sm);
          --space-6: var(--boxel-sp-xs);
        }
        .cfg :deep(dt) {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
        }
        code {
          font-family: var(--font-mono);
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
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default AppConfigurationField;
