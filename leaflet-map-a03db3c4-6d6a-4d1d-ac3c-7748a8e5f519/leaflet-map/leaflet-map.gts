// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import { CardDef } from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import NumberField from 'https://cardstack.com/base/number';
import StringField from 'https://cardstack.com/base/string';
import {
  Component,
  contains,
  field,
} from 'https://cardstack.com/base/card-api';
import Modifier, { NamedArgs } from 'ember-modifier';
import { action } from '@ember/object';
import MapIcon from '@cardstack/boxel-icons/map';

declare global {
  var L: any;
}

// ² Enhanced modifier for travel planning with multiple destinations
interface TravelMapModifierSignature {
  Args: {
    Positional: [];
    Named: {
      destinations?: Array<{
        lat: number;
        lon: number;
        name: string;
        description?: string;
      }>;
      tileserverUrl?: string;
      setMap?: (map: any) => void;
      centerLat?: number;
      centerLon?: number;
    };
  };
}

export class TravelMapModifier extends Modifier<TravelMapModifierSignature> {
  element: HTMLElement | null = null;
  map: any = null;

  modify(
    element: HTMLElement,
    [],
    {
      destinations = [],
      tileserverUrl,
      setMap,
      centerLat,
      centerLon,
    }: NamedArgs<TravelMapModifierSignature>,
  ) {
    // ³ Load Leaflet and create map with multiple markers
    fetch('https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.js')
      .then((r) => r.text())
      .then((t) => {
        eval(t);

        // Clear existing map if it exists
        if (this.map) {
          this.map.remove();
        }

        // ⁴ Determine map center and zoom based on destinations
        let mapCenter = [centerLat || 40.7128, centerLon || -74.006];
        let zoom = 13;

        if (destinations.length > 0) {
          // Center on first destination if available
          mapCenter = [destinations[0].lat, destinations[0].lon];

          // If multiple destinations, fit bounds to show all
          if (destinations.length > 1) {
            zoom = 10;
          }
        }

        this.map = L.map(element).setView(mapCenter, zoom);

        L.tileLayer(
          tileserverUrl || 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ).addTo(this.map);

        // ⁵ Add markers for each destination
        if (destinations.length > 0) {
          const group = new L.featureGroup();

          destinations.forEach((dest, index) => {
            if (dest.lat && dest.lon) {
              const marker = L.marker([dest.lat, dest.lon]).addTo(this.map);

              // ⁶ Create popup content with destination info
              const popupContent = `
                <div style="font-family: Inter, sans-serif;">
                  <h4 style="margin: 0 0 0.5rem 0; color: #1e40af; font-size: 1rem;">${
                    dest.name || `Destination ${index + 1}`
                  }</h4>
                  ${
                    dest.description
                      ? `<p style="margin: 0; color: #6b7280; font-size: 0.875rem;">${dest.description}</p>`
                      : ''
                  }
                  <div style="margin-top: 0.5rem; font-size: 0.75rem; color: #9ca3af;">
                    ${dest.lat.toFixed(4)}, ${dest.lon.toFixed(4)}
                  </div>
                </div>
              `;

              marker.bindPopup(popupContent);
              group.addLayer(marker);
            }
          });

          // ⁷ Fit map to show all destinations if multiple
          if (destinations.length > 1) {
            this.map.fitBounds(group.getBounds(), { padding: [20, 20] });
          }
        }

        setMap?.(this.map);
      });
  }

  willDestroy() {
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}

export class LeafletMap extends CardDef {
  static displayName = 'Leaflet Map';
  static icon = MapIcon;

  @field lat = contains(NumberField);
  @field lon = contains(NumberField);
  @field tileserverUrl = contains(StringField);

  map: any;

  @action
  setMap(map: any) {
    this.map = map;
  }

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <figure
        {{LeafletModifier
          lat=@model.lat
          lon=@model.lon
          tileserverUrl=@model.tileserverUrl
          setMap=@model.setMap
        }}
        class='map'
      >
        Map loading for
        {{@model.lat}},
        {{@model.lon}}
      </figure>

      <style scoped>
        figure.map {
          margin: 0;
          width: 100%;
          height: 100%;
        }
      </style>
      <link
        href='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css'
        rel='stylesheet'
      />
    </template>
  };
}

interface LeafletModifierSignature {
  Args: {
    Positional: [];
    Named: {
      lat: number | undefined;
      lon: number | undefined;
      tileserverUrl?: string;
      setMap?: (map: any) => void;
    };
  };
}

export class LeafletModifier extends Modifier<LeafletModifierSignature> {
  element: HTMLElement | null = null;

  modify(
    element: HTMLElement,
    [],
    { lat, lon, tileserverUrl, setMap }: NamedArgs<LeafletModifierSignature>,
  ) {
    fetch('https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.js')
      .then((r) => r.text())
      .then((t) => {
        eval(t);
        let map = L.map(element).setView([lat, lon], 13);

        L.tileLayer(
          tileserverUrl || 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        ).addTo(map);

        setMap?.(map);
      });
  }
}
