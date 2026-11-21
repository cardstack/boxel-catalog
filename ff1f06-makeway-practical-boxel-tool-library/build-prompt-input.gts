import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class BuildPromptInput extends CardDef {
  @field goal = contains(StringField);
  @field audience = contains(StringField);
  @field mustHave = contains(StringField);
  @field feel = contains(StringField);
}
