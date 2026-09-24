import {
  CardDef,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import MarkdownField from '@cardstack/base/markdown';
import UrlField from '@cardstack/base/url';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DatetimeField from '@cardstack/base/datetime';
import LayoutIcon from '@cardstack/boxel-icons/layout-dashboard';

import { Guest } from './guest';
import { Host } from './host';
import { Table } from './table';
import { Fixture } from './fixture';
import {
  TableSeatingPlannerIsolated,
  TableSeatingPlannerFitted,
} from './components/tsp';
import { PosterAspectField } from './commands/invitation-poster-command';

export class TableSeatingPlanner extends CardDef {
  static displayName = 'Table Seating Planner';
  static icon = LayoutIcon;
  static prefersWideFormat = true;

  @field eventLogo = contains(ImageSourceField);
  @field eventTitle = contains(StringField);
  // Optional glyph for the event mark and table centrepieces (e.g. 囍 or ✝).
  // Content, not colour, so it lives on the card rather than in a theme; empty
  // falls back to the event initials.
  @field motif = contains(StringField);
  @field eventDate = contains(DatetimeField);
  @field hosts = linksToMany(() => Host);
  @field venue = contains(StringField);

  @field hostNames = contains(StringField, {
    computeVia: function (this: TableSeatingPlanner) {
      return ((this.hosts ?? []) as Host[])
        .map((h) => h?.fullName?.trim())
        .filter(Boolean)
        .join(' & ');
    },
  });

  @field guests = linksToMany(() => Guest); // reusable people — stay cards

  @field tables = containsMany(Table);
  @field fixtures = containsMany(Fixture);
  @field floorPlanURL = contains(UrlField);
  @field floorPlanX = contains(NumberField);
  @field floorPlanY = contains(NumberField);
  @field floorPlanWidth = contains(NumberField);
  @field floorPlanHeight = contains(NumberField);
  @field floorPlanOpacity = contains(NumberField);
  @field floorPlanLocked = contains(BooleanField);
  @field invitationMessage = contains(TextAreaField);
  @field seatingMessage = contains(TextAreaField);
  @field poster = contains(ImageSourceField);
  @field posterPrompt = contains(MarkdownField);
  @field posterAspect = contains(PosterAspectField);

  @field title = contains(StringField, {
    computeVia: function (this: TableSeatingPlanner) {
      return this.eventTitle?.trim() || 'Table Seating Planner';
    },
  });
}

TableSeatingPlanner.isolated = TableSeatingPlannerIsolated;
TableSeatingPlanner.embedded = TableSeatingPlannerFitted;
TableSeatingPlanner.fitted = TableSeatingPlannerFitted;
