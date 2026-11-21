import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class CleanTextResult extends CardDef {
  @field output = contains(StringField);
}
