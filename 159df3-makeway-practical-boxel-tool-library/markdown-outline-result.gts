import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class MarkdownOutlineResult extends CardDef {
  @field output = contains(StringField);
}
