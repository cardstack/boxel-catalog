import GlimmerComponent from '@glimmer/component';
import Modifier, { NamedArgs } from 'ember-modifier';

// Leaflet type definitions
interface LeafletMap {
  setView: (center: [number, number], zoom: number) => LeafletMap;
  addTo: (layer: any) => LeafletMap;
  on: (event: string, handler: (event: any) => void) => LeafletMap;
  remove: () => void;
  getSize: () => { x: number; y: number };
  flyTo: (center: [number, number], zoom: number, options: any) => LeafletMap;
  flyToBounds: (bounds: any, options: any) => LeafletMap;
  invalidateSize: () => void;
}

interface LeafletTileLayer {
  addTo: (map: LeafletMap) => LeafletTileLayer;
  remove: () => void;
}

interface LeafletMarker {
  bindPopup: (content: string) => LeafletMarker;
  getLatLng: () => LeafletLatLng;
  openPopup: () => LeafletMarker;
}

interface LeafletPolyline {
  // Leaflet polyline methods, we add this when we need more control over the polyline
}

type LeafletLayers = LeafletMarker | LeafletPolyline;

interface LeafletLatLng {
  lat: number;
  lng: number;
}

interface LeafletLayerGroup {
  addLayer: (layer: any) => LeafletLayerGroup;
  clearLayers: () => void;
  getLayers: () => any[];
  addTo: (map: LeafletMap) => LeafletLayerGroup;
}

export interface Coordinate {
  id?: string | number;
  address?: string;
  lat: number;
  lng: number;
}

export interface Route {
  name?: string;
  coordinates: Coordinate[];
}

interface LeafletMapConfig {
  tileserverUrl?: string;
  disableMapClick?: boolean;
}

interface MapRenderSignature {
  Args: {
    coordinates?: Coordinate[]; //use this arg if you want markers only
    routes?: Route[]; //use this arg if you want to render routes (polylines)
    mapConfig?: LeafletMapConfig;
    onMapClick?: (coordinate: Coordinate) => void;
    selectedId?: string | number | null; //open the popup of the marker with this Coordinate id
  };
  Element: HTMLElement;
}

// Leaflet instance, held in module scope (NOT on globalThis). Every map
// instance in this module shares this single reference, but it stays isolated
// from any other module that also loads Leaflet — so a sibling loader can never
// clobber or be clobbered by ours through a shared global.
let L: any;

// Leaflet is pulled from a CDN as a UMD bundle and run at runtime. Its wrapper
// picks where to expose itself based on the ambient module system:
//   - CommonJS branch  -> runs the factory synchronously against `exports`
//   - AMD branch       -> only REGISTERS the factory, never runs it
//   - browser-global   -> assigns window.L synchronously
// Under the realm loader a `define` (no define.amd) and a `module` are visible
// in the eval scope, so a plain `eval(script)` mis-detects the environment and
// leaves `L` unset — the next read of `L.Bounds` then throws "Cannot read
// properties of undefined (reading 'prototype')". Instead we run the bundle
// through `new Function('module','exports', ...)`, which executes in global
// scope with explicit CommonJS bindings: the factory always runs synchronously
// against our `exports`, regardless of any ambient `define`. We capture the
// result into the module-scoped `L` (not globalThis) once and share it across
// every map instance in this module.
let leafletLoaded: Promise<void> | undefined;

function loadLeaflet(): Promise<void> {
  if (!leafletLoaded) {
    leafletLoaded = (async () => {
      if (!L?.map) {
        let response = await fetch(
          'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js',
        );
        let code = await response.text();
        let leafletModule: { exports: any } = { exports: {} };
        new Function('module', 'exports', code)(
          leafletModule,
          leafletModule.exports,
        );
        L = leafletModule.exports;
      }
      // Polylines call L.Bounds.prototype.intersects(), which throws on the
      // LatLng -> Bounds conversion (a long-standing Leaflet bug). Short-circuit
      // it so bounds checks never reject valid coordinates.
      if (L?.Bounds?.prototype) {
        L.Bounds.prototype.intersects = function () {
          return true;
        };
      }
    })();
  }
  return leafletLoaded;
}

export class MapRender extends GlimmerComponent<MapRenderSignature> {
  <template>
    <figure
      {{LeafletModifier
        coordinates=@coordinates
        routes=@routes
        mapConfig=@mapConfig
        onMapClick=@onMapClick
        selectedId=@selectedId
      }}
      class='map'
    />

    <style scoped>
      figure.map {
        margin: 0;
        width: 100%;
        height: 100%;
        position: relative;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--boxel-50);
        color: #666;
        font-size: 14px;
        text-align: center;
        flex: 1;
        overflow: hidden; /* Prevent scrollbars from affecting tile calculations */
      }

      figure.map :deep(.leaflet-container) {
        width: 100% !important;
        height: 100% !important;
        min-height: 300px;
      }
    </style>
    <link
      href='https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.min.css'
      rel='stylesheet'
    />
  </template>
}

interface LeafletTileInterface {
  onTileChange: (tile: string | null) => void;
}

class LeafletTile implements LeafletTileInterface {
  private tile: LeafletTileLayer | null = null;
  private map: LeafletMap;

  constructor(map: LeafletMap) {
    this.map = map;
  }

  onTileChange(tile: string | null) {
    this.teardown();
    const defaultTile = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    this.tile = L.tileLayer(tile || defaultTile, {
      maxZoom: 18,
      attribution: '© OpenStreetMap contributors',
    }).addTo(this.map);
  }

  teardown() {
    if (this.tile) {
      this.tile.remove();
      this.tile = null;
    }
  }
}

interface LeafletModifierSignature {
  Args: {
    Positional: [];
    Named: {
      coordinates?: Coordinate[];
      routes?: Route[];
      mapConfig?: LeafletMapConfig;
      onMapClick?: (coordinate: Coordinate) => void;
      selectedId?: string | number | null;
    };
  };
}

interface LeafletLayerStateInterface {
  onCoordinatesChange: (coordinates: Coordinate[]) => void;
  onRoutesChange: (routes: Route[]) => void;
}

class LeafletLayerState implements LeafletLayerStateInterface {
  private group: LeafletLayerGroup | null = null;
  private map: LeafletMap;
  private markerById = new Map<string | number, LeafletMarker>();

  constructor(map: LeafletMap) {
    this.map = map;
    this.group = L.layerGroup();
    this.group?.addTo(this.map);
  }

  focus(id: string | number) {
    let marker = this.markerById.get(id);
    if (marker) {
      // Leaflet popups auto-pan into view, so opening is enough to reveal it.
      marker.openPopup();
    }
  }

  onCoordinatesChange(coordinates: Coordinate[]) {
    this.teardown();
    let markers = this.createMarkers(coordinates.filter(hasLatLng));
    this.addLayers(markers);
  }

  onRoutesChange(routes: Route[]) {
    this.teardown();
    let layersToAdd: LeafletLayers[] = [];
    routes.forEach((route) => {
      let coords = (route.coordinates ?? []).filter(hasLatLng);
      if (coords.length > 0) {
        this.createMarkers(coords).forEach((marker) =>
          layersToAdd.push(marker),
        );
      }
      let line = this.addPolyline(coords);
      if (line) layersToAdd.push(line);
    });
    this.addLayers(layersToAdd);
  }

  private addLayers(layers: LeafletLayers[]) {
    layers.forEach((layer) => this.group?.addLayer(layer));
    this.readjustMapView();
  }

  private createMarkers(coords: Coordinate[]): LeafletMarker[] {
    return coords.map((c, i) => {
      const color =
        i === 0 ? '#22c55e' : i === coords.length - 1 ? '#ef4444' : '#3b82f6';
      const marker = createMarker(c, color);
      const trimmedAddress = c.address?.trim() || undefined;
      const popupContent =
        trimmedAddress ?? `${c.lat.toFixed(6)}, ${c.lng.toFixed(6)}`;
      marker.bindPopup(popupContent);
      if (c.id != null) {
        this.markerById.set(c.id, marker);
      }
      return marker;
    });
  }

  private addPolyline(coordinates: Coordinate[]): LeafletPolyline | null {
    if (coordinates.length < 2) return null;
    const latLngs = coordinates.map((c) => L.latLng(c.lat, c.lng));
    return new L.Polyline(latLngs);
  }

  private readjustMapView() {
    if (!this.group) return;

    let markerLayers = this.group
      .getLayers()
      .filter((layer: any) => layer instanceof L.Marker);
    let coords = markerLayers.map((markerLayer: LeafletMarker) => {
      return markerLayer.getLatLng();
    });
    this.fitMapToCoordinates(
      coords.map((ll: LeafletLatLng) => ({ lat: ll.lat, lng: ll.lng })),
    );
  }

  private fitMapToCoordinates(coords: Coordinate[], attempt = 0) {
    if (!this.map || coords.length === 0) {
      // nothing to fit — keep the current (world) view
      return;
    }

    let size = this.map.getSize ? this.map.getSize() : null;
    // Leaflet divides by the current map size; while prerender lays things out
    // the container reports 0×0 which produces NaNs, so retry a few times until
    // the map has real dimensions.
    if (!size || size.x === 0 || size.y === 0) {
      if (attempt >= 5) {
        return;
      }
      let delay = Math.min(200, 50 * (attempt + 1));
      setTimeout(() => {
        if (this.map) {
          this.fitMapToCoordinates(coords, attempt + 1);
        }
      }, delay);
      return;
    }

    if (coords.length === 1) {
      // single point → just flyTo
      this.map.flyTo([coords[0].lat, coords[0].lng], 13, {
        animate: true,
        duration: 1.2,
      });
    } else {
      const latLngs = coords.map((c) => L.latLng(c.lat, c.lng));
      this.map.flyToBounds(latLngs, {
        padding: [32, 32],
        animate: true,
        duration: 1.5,
      });
    }

    // Single invalidate size after view change to ensure proper tile coverage
    setTimeout(() => {
      if (this.map) {
        this.map.invalidateSize();
      }
    }, 200);
  }

  teardown() {
    this.group?.clearLayers();
    this.markerById.clear();
  }
}

export default class LeafletModifier extends Modifier<LeafletModifierSignature> {
  private element: HTMLElement | null = null;
  private moduleSet: boolean = false;
  private initializing: boolean = false;
  private lastCoordinates: Coordinate[] | undefined = undefined;
  private lastRoutes: Route[] | undefined = undefined;
  private map: LeafletMap | null = null;
  private tile: LeafletTile | null = null;
  private state: LeafletLayerState | undefined;

  modify(
    element: HTMLElement,
    _positional: [],
    named: NamedArgs<LeafletModifierSignature>,
  ) {
    let { coordinates, routes, onMapClick, mapConfig, selectedId } = named;
    let { tileserverUrl } = mapConfig || {};
    this.element = element;

    // Prerendered runs start with a 0×0 container, so give Leaflet a minimal
    // footprint until the real layout kicks in.
    if (element && (element.clientWidth === 0 || element.clientHeight === 0)) {
      if (!element.style.minWidth) {
        element.style.minWidth = '320px';
      }
      if (!element.style.minHeight) {
        element.style.minHeight = '320px';
      }
    }

    (async () => {
      if (!this.moduleSet) {
        // A re-render can call modify() again while the async load below is
        // still in flight; without this guard both passes would run initMap()
        // on the same element and Leaflet throws "Map container is already
        // initialized."
        if (this.initializing) {
          return;
        }
        this.initializing = true;
        try {
          await loadLeaflet();
          this.initMap(mapConfig, onMapClick);
          this.moduleSet = true;
        } finally {
          this.initializing = false;
        }
      }
      if (!this.map) {
        return;
      }
      if (!this.tile) {
        this.tile = new LeafletTile(this.map);
      }
      this.tile.onTileChange(tileserverUrl || null);

      if (!this.state) {
        this.state = new LeafletLayerState(this.map);
      }
      // Only rebuild layers when the data reference actually changes; otherwise
      // a re-render that merely changed selectedId would re-fit the whole map.
      if (coordinates && coordinates !== this.lastCoordinates) {
        this.lastCoordinates = coordinates;
        this.state.onCoordinatesChange(coordinates);
      }
      if (routes && routes !== this.lastRoutes) {
        this.lastRoutes = routes;
        this.state.onRoutesChange(routes);
      }
      if (selectedId != null) {
        this.state.focus(selectedId);
      }
    })();
  }

  willRemove() {
    this.teardown();
  }

  private initMap(
    mapConfig?: LeafletMapConfig,
    onMapClick?: (c: Coordinate) => void,
  ) {
    if (!this.element) return;
    // Leaflet tags an initialized container with a _leaflet_id; bail if one is
    // already present so we never double-initialize the same element.
    if ((this.element as any)._leaflet_id) return;

    const center = [20, 0];
    const zoom = 2;
    this.map = L.map(this.element).setView(center, zoom);

    L.tileLayer(
      mapConfig?.tileserverUrl ||
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      {
        maxZoom: 18,
        attribution: '© OpenStreetMap contributors',
      },
    ).addTo(this.map);

    if (!mapConfig?.disableMapClick && onMapClick) {
      this.map?.on(
        'click',
        (event: { latlng: { lat: number; lng: number } }) => {
          const { lat, lng } = event.latlng;
          onMapClick({ lat, lng });
        },
      );
    }
  }

  private teardown() {
    this.state?.teardown();
    if (this.map) {
      this.map.remove();
      this.map = null;
    }
  }
}

//utilities
function hasLatLng(c: Coordinate): boolean {
  // card field data can arrive with unset lat/lng even though the type says
  // number; Leaflet throws deep inside project() when handed null
  return c?.lat != null && c?.lng != null;
}

function createMarker(coord: Coordinate, color: string): LeafletMarker {
  const strokeColor = darken(color, 0.3);
  const html = `<svg width="24" height="32" viewBox="0 0 24 32" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 0C5.3 0 0 5.3 0 12c0 8.5 12 20 12 20s12-11.5 12-20C24 5.3 18.7 0 12 0z"
            fill="${color}" stroke="${strokeColor}" stroke-width="2"/>
      <circle cx="12" cy="12" r="4" fill="white" stroke="${strokeColor}" stroke-width="1"/>
    </svg>`;

  return L.marker([coord.lat, coord.lng], {
    icon: L.divIcon({
      className: 'marker',
      html,
      iconSize: [24, 32],
      iconAnchor: [12, 32],
      popupAnchor: [0, -32],
    }),
  });
}

function darken(hex: string, factor: number): string {
  const h = hex.replace('#', '');
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  const d = (c: number) => Math.max(0, Math.floor(c * (1 - factor)));
  return `#${d(r).toString(16).padStart(2, '0')}${d(g)
    .toString(16)
    .padStart(2, '0')}${d(b).toString(16).padStart(2, '0')}`;
}
