import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class UTMBuilderResult extends CardDef {
  @field output = contains(StringField);
}
