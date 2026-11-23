import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class RegexTesterResult extends CardDef {
  @field output = contains(StringField);
}
