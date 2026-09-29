import {
  CardDef,
  contains,
  field,
  linksToMany,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import StackIcon from '@cardstack/boxel-icons/stack';

/**
 * One cluster of cards for the Gold Spec Demo, such as CRM: a title and links
 * to one existing example of each card in the cluster. Adding a cluster to the
 * demo is one new instance of this card, with no code change. The linked cards
 * are shared examples, so the demo only renders them.
 */
export class GoldSpecCardGroup extends CardDef {
  static displayName = 'Gold Spec Card Group';
  static icon = StackIcon;

  @field title = contains(StringField);
  @field cards = linksToMany(CardDef);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: GoldSpecCardGroup) {
      return this.title?.trim()?.length
        ? this.title
        : `Untitled ${this.constructor.displayName}`;
    },
  });
}

export default GoldSpecCardGroup;
