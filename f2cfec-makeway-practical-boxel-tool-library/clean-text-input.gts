import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class CleanTextInput extends CardDef {
  @field source = contains(StringField);
}
