import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import HandGrabIcon from '@cardstack/boxel-icons/hand-grab';

import { PlacementPalette, type PlacementItem } from '../placement-palette';
import { PlacementField } from '../../fields/placement/placement-vocabulary';

export class PlacementExampleItem extends FieldDef {
  static displayName = 'Placement Example Item';

  @field itemId = contains(StringField);
  @field title = contains(StringField);
  @field group = contains(StringField);
  @field detail = contains(StringField);
}

class PlacementPaletteExampleIsolated extends Component<
  typeof PlacementPaletteExample
> {
  get items(): PlacementItem[] {
    return (this.args.model?.items ?? [])
      .filter((i) => i?.itemId && i?.title)
      .map((i) => ({
        id: i.itemId!,
        title: i.title!,
        group: i.group ?? undefined,
        detail: i.detail ?? undefined,
      }));
  }

  <template>
    <div class='palette-example'>
      <PlacementPalette
        @items={{this.items}}
        @placements={{@model.placements}}
        @groupBy={{true}}
        @searchable={{true}}
        @heading='Unassigned crew'
      />
    </div>
    <style scoped>
      .palette-example {
        max-width: 22rem;
        padding: var(--boxel-sp);
      }
    </style>
  </template>
}

/**
 * Crew to place, grouped by role. Two are already placed, so they have left
 * the rail and it reads as "what is left to do".
 */
export class PlacementPaletteExample extends CardDef {
  static displayName = 'Placement Palette Example';
  static icon = HandGrabIcon;

  @field items = containsMany(PlacementExampleItem);
  @field placements = containsMany(PlacementField);

  static isolated = PlacementPaletteExampleIsolated;
}
