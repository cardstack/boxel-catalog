import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
export class CsvCleanerInput extends CardDef {
  @field source = contains(StringField);
}
