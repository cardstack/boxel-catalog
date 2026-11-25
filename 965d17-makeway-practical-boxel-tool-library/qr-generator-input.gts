import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class QRGeneratorInput extends CardDef {
  @field value = contains(StringField);
}
