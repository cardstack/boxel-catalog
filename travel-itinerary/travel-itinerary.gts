import {
  CardDef,
  contains,
  containsMany,
  field,
  FieldDef,
} from 'https://cardstack.com/base/card-api';
import DateRangeField from 'https://cardstack.com/base/date-range-field';
import enumField from 'https://cardstack.com/base/enum';
import NumberField from 'https://cardstack.com/base/number';
import StringField from 'https://cardstack.com/base/string';
import TextAreaField from 'https://cardstack.com/base/text-area';
import TimeField from 'https://cardstack.com/base/time';
import PlaneIcon from '@cardstack/boxel-icons/plane';

import GeoSearchPointField from '@cardstack/catalog/fields/geo-search-point/geo-search-point';
import QRField from '@cardstack/catalog/fields/qr-code/qr-code';

import { ItineraryStopEmbedded } from './components/ti-stop';
import {
  TravelItineraryIsolated,
  TravelItineraryFitted,
} from './components/ti';
import { TRIP_CATEGORIES } from './utils/index';

// A stop's category is a fixed enum, rendered as a BoxelSelect in edit mode.
// The stored value is the plain category name; the label carries the emoji.
const CategoryField = enumField(StringField, {
  options: TRIP_CATEGORIES.map((c) => ({ value: c.value, label: c.label })),
});

export class ItineraryStop extends FieldDef {
  static displayName = 'Itinerary Stop';

  @field location = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        showRecentSearches: false,
        placeholder: 'Search for a place…',
        mapHeight: '220px',
      },
    },
  });
  @field day = contains(NumberField);
  @field startTime = contains(TimeField);
  @field endTime = contains(TimeField);
  @field category = contains(CategoryField);
  @field notes = contains(TextAreaField);
}

ItineraryStop.embedded = ItineraryStopEmbedded;

export class TravelItinerary extends CardDef {
  static displayName = 'Travel Itinerary Planner';
  static icon = PlaneIcon;
  static prefersWideFormat = true;

  @field tripTitle = contains(StringField);
  @field destination = contains(GeoSearchPointField, {
    configuration: {
      options: {
        showTopSearchResults: true,
        topSearchResultsLimit: 5,
        showRecentSearches: false,
        placeholder: 'Where to?',
        mapHeight: '200px',
      },
    },
  });
  @field dateRange = contains(DateRangeField, {
    configuration: { minDate: 'today' },
  });
  @field stops = containsMany(ItineraryStop);

  // A QR code for sharing this trip. Not computed — the traveller manually
  // enters the card instance id / URL into the field's `data` in edit mode.
  @field shareTripCode = contains(QRField);

  @field title = contains(StringField, {
    computeVia: function (this: TravelItinerary) {
      return (
        this.tripTitle?.trim() ||
        this.destination?.searchKey?.trim() ||
        'Travel Itinerary Planner'
      );
    },
  });
}

TravelItinerary.isolated = TravelItineraryIsolated;
TravelItinerary.embedded = TravelItineraryIsolated;
TravelItinerary.fitted = TravelItineraryFitted;
