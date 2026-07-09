import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Command } from '@cardstack/runtime-common';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { TravelItinerary } from '../travel-itinerary';
import {
  parsePlanJson,
  geocodePlace,
  geocodePlannedStops,
  matchCategory,
  type PlannedStop,
} from '../utils/index';

// What the AI Assistant hands us: the trip card to update, the planned
// itinerary as the same JSON the travel-planner skill already produces, plus
// the trip-level destination and dates to set on a fresh plan.
class ApplyItineraryInput extends CardDef {
  @field cardId = contains(StringField, {
    description:
      'The id of the Travel Itinerary card to update — use the id of the attached trip card.',
  });
  @field planJson = contains(StringField, {
    description:
      'The full itinerary as a JSON object: { tripTitle, summary, stops: [{ day, name, lat, lon, startTime, endTime, notes, category }] }.',
  });
  @field destination = contains(StringField, {
    description:
      'The trip destination / region (e.g. "Tokyo, Japan"). Used to disambiguate geocoding and, on a fresh plan, to set the card\'s destination. Optional on a revision.',
  });
  @field startDate = contains(StringField, {
    description:
      'Trip start date as YYYY-MM-DD. Provide together with endDate on a fresh plan to set the trip dates.',
  });
  @field endDate = contains(StringField, {
    description:
      'Trip end date as YYYY-MM-DD. Provide together with startDate on a fresh plan to set the trip dates.',
  });
}

// Serialize a planned stop into the attribute shape `store.patch` expects for
// an ItineraryStop field: location is a GeoSearchPointField ({ searchKey, lat,
// lon }); start/end are TimeFields ({ value }); category is the enum string.
function serializeStops(planned: PlannedStop[]) {
  return planned.map((p) => ({
    day: p.day,
    location: {
      searchKey: p.name,
      ...(p.lat != null ? { lat: p.lat } : {}),
      ...(p.lon != null ? { lon: p.lon } : {}),
    },
    startTime: { value: p.startTime },
    endTime: { value: p.endTime },
    category: matchCategory(p.category) ?? null,
    notes: p.notes ?? null,
  }));
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

// Applies a planned itinerary to a Travel Itinerary card. Reuses the proven
// pipeline — parse the JSON, refine every stop's coordinates via Photon
// (the LLM's coords are only a hint), coerce categories to the enum — then
// patches the card. Exposed to the AI Assistant as a tool via the
// travel-planner skill, so the assistant plans conversationally and (after the
// traveller approves) calls this to write the result onto the open trip.
export default class ApplyItineraryCommand extends Command<
  typeof ApplyItineraryInput,
  undefined
> {
  static actionVerb = 'Apply Itinerary';
  static displayName = 'Apply Itinerary';

  description =
    'Write a planned itinerary onto the attached Travel Itinerary card: replaces its stops and sets the trip title, and (on a fresh plan) the destination and date range.';

  requireInputFields = ['cardId', 'planJson'];

  async getInputType() {
    return ApplyItineraryInput;
  }

  protected async run(input: ApplyItineraryInput): Promise<undefined> {
    if (!input.cardId) {
      throw new Error('cardId is required');
    }
    let trip = parsePlanJson(input.planJson ?? '');
    if (!trip || !trip.stops.length) {
      throw new Error('planJson did not contain any usable stops');
    }

    let destination = input.destination?.trim() || undefined;
    let stops = await geocodePlannedStops(trip.stops, destination);

    let attributes: Record<string, unknown> = {
      stops: serializeStops(stops),
    };
    if (trip.tripTitle) {
      attributes.tripTitle = trip.tripTitle;
    }
    // Set the trip dates when both are provided (a fresh plan); leave the
    // card's dates untouched on a revision that omits them.
    if (
      ISO_DATE.test(input.startDate ?? '') &&
      ISO_DATE.test(input.endDate ?? '')
    ) {
      attributes.dateRange = { start: input.startDate, end: input.endDate };
    }
    // Set the destination when provided, geocoding it so the map centers.
    if (destination) {
      let coords = await geocodePlace(destination);
      attributes.destination = {
        searchKey: destination,
        ...(coords ? { lat: coords.lat, lon: coords.lon } : {}),
      };
    }

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: TravelItinerary,
    }).execute({
      cardId: input.cardId,
      patch: { attributes },
    });

    return undefined;
  }
}
