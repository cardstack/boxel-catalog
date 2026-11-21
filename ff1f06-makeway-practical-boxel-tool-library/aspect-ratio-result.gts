import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class AspectRatioResult extends CardDef {
  @field output = contains(StringField);
}
