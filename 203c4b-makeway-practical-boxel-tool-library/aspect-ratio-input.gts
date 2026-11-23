import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class AspectRatioInput extends CardDef {
  @field width = contains(StringField);
  @field height = contains(StringField);
  @field targetWidth = contains(StringField);
  @field targetHeight = contains(StringField);
}
