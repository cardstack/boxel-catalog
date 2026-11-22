import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class BuildPromptResult extends CardDef {
  @field output = contains(StringField);
}
