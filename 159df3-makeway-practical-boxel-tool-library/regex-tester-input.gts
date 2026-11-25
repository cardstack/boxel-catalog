import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class RegexTesterInput extends CardDef {
  @field pattern = contains(StringField);
  @field flags = contains(StringField);
  @field sample = contains(StringField);
}
