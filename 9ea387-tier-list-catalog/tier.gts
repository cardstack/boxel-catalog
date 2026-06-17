import { FieldDef, contains, field } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';

export class Tier extends FieldDef {
  static displayName = 'Tier';

  @field key = contains(StringField);
  @field label = contains(StringField);
  @field color = contains(StringField);
  @field sortOrder = contains(NumberField);
}
