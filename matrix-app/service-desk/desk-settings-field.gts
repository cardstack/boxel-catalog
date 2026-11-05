import {
  FieldDef,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import SettingsIcon from '@cardstack/boxel-icons/settings';

/**
 * The desk's settings: only what the desk reads. The id pattern and its mint
 * counter, a time zone, and the setup wizard's resume point. The Setup tab
 * writes it step by step and stamps `setupCompletedAt` at the end; until then
 * the desk shows a quiet banner, never a lockout.
 */
export class DeskSettingsField extends FieldDef {
  static displayName = 'Desk Settings';
  static icon = SettingsIcon;

  @field idPattern = contains(StringField, {
    description: 'Case id pattern, e.g. CASE-{yyyy}-{seq4}.',
  });
  @field identifierSeq = contains(NumberField, {
    description: 'Mint counter, written when a case is created.',
  });
  @field timeZone = contains(StringField, {
    description: 'IANA time zone, e.g. Asia/Kuala_Lumpur.',
  });
  @field setupStep = contains(NumberField, {
    description: 'First incomplete setup step; the wizard resumes here.',
  });
  @field setupCompletedAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: DeskSettingsField) {
      return this.setupCompletedAt
        ? 'Configured'
        : `Setup in progress (step ${this.setupStep ?? 1})`;
    },
  });
}
