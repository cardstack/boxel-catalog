import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class UTMBuilderInput extends CardDef {
  @field url = contains(StringField);
  @field source = contains(StringField);
  @field medium = contains(StringField);
  @field campaign = contains(StringField);
  @field term = contains(StringField);
  @field content = contains(StringField);
}
