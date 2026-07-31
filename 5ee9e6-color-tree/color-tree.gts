import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import ColorField from 'https://cardstack.com/base/color';
import PaletteIcon from '@cardstack/boxel-icons/palette';
import { IsolatedColorTree } from './components/color-tree-isolated';
import { ColorTreeEmbedded } from './components/color-tree-embedded';
import { ColorTreeFitted } from './components/color-tree-fitted';

export class ColorTree extends CardDef {
  static displayName = 'Color Tree';
  static icon = PaletteIcon;
  static prefersWideFormat = true;

  @field selectedColor = contains(ColorField);
  @field selectedMunsell = contains(StringField);
  @field title = contains(StringField, {
    computeVia: function (this: ColorTree) {
      return this.selectedMunsell
        ? `Color Tree — ${this.selectedMunsell}`
        : 'Color Tree';
    },
  });

  static isolated = IsolatedColorTree;
  static embedded = ColorTreeEmbedded;
  static fitted = ColorTreeFitted;
}
