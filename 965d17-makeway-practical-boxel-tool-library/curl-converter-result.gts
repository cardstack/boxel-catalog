import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class CurlConverterResult extends CardDef {
  @field output = contains(StringField);
}
