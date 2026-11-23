import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class MarkdownOutlineInput extends CardDef {
  @field source = contains(StringField);
}
