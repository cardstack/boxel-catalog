import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class CurlConverterInput extends CardDef {
  @field command = contains(StringField);
}
