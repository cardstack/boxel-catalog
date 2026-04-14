import { CardDef, FieldDef, field, contains, containsMany } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import MarkdownField from 'https://cardstack.com/base/markdown';

class ImageLinksField extends FieldDef {
  @field imageUrl = contains(StringField);
}

export class BrazilianPlantCard extends CardDef {
  static displayName = 'BrazilianPlantCard';

  @field commonName = contains(StringField);
  @field scientificName = contains(StringField);
  @field description = contains(MarkdownField);
  @field habitat = contains(StringField);
  @field conservationStatus = contains(StringField);
  @field uses = contains(MarkdownField);
  @field images = containsMany(ImageLinksField);
  @field growthConditions = contains(MarkdownField);
}


  /*
  static isolated = class Isolated extends Component<typeof this> {
    <template></template>
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template></template>
  }

  static atom = class Atom extends Component<typeof this> {
    <template></template>
  }

  static edit = class Edit extends Component<typeof this> {
    <template></template>
  }
  */
