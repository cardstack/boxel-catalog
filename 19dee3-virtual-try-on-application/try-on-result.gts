import { CardDef, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';

export class TryOnResult extends CardDef {
  static displayName = 'Try-On Result';

  // Lookup keys — modelKey e.g. "m0", garmentKey = sorted card IDs joined by "|"
  @field modelKey = contains(StringField);
  @field garmentKey = contains(StringField);

  // Generated image URLs (realm file identifiers)
  @field frontViewUrl = contains(StringField);
  @field sideViewUrl = contains(StringField);
  @field backViewUrl = contains(StringField);
}
