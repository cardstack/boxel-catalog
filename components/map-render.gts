import GlimmerComponent from '@glimmer/component';
import Modifier, { NamedArgs } from 'ember-modifier';

// Leaflet type definitions
interface LeafletMap {
  setView: (center: [number, number], zoom: number) => LeafletMap;
  addTo: (layer: any) => LeafletMap;
  on: (event: string, handler: (event: any) => void) => LeafletMap;
  remove: () => void;
  getSize: () => { x: number; y: number };
  getZoom: () => number;
  flyTo: (center: [number, number], zoom: number, options: any) => LeafletMap;
  flyToBounds: (bounds: any, options: any) => LeafletMap;
  invalidateSize: () => void;
}

interface LeafletTileLayer {
  addTo: (map: LeafletMap) => LeafletTileLayer;
  remove: () => void;
}

interface LeafletPopup {
  setContent: (content: string | HTMLElement) => LeafletPopup;
  getElement: () => HTMLElement | undefined;
}

interface LeafletMarker {
  bindPopup: (content: string, options?: any) => LeafletMarker;
  getLatLng: () => LeafletLatLng;
  openPopup: () => LeafletMarker;
  getPopup: () => LeafletPopup | undefined;
  on: (event: string, handler: (event: any) => void) => LeafletMarker;
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
  name?: string; // clean label (no HTML), used for Wikipedia title lookup
  lat: number;
  lng: number;
}

export interface NearbyPlace {
  name: string;
  lat: number;
  lng: number;
  kind: NearbyKind;
  // Optional detail pulled from OSM tags (often missing — crowd-sourced).
  openingHours?: string; // raw OSM `opening_hours` syntax
  website?: string;
  phone?: string;
  cuisine?: string; // raw OSM `cuisine` (e.g. "coffee_shop;sandwich")
}

// Real-world detail for a place, pulled from OSM tags (any field may be absent
// — coverage is crowd-sourced).
interface PlaceDetails {
  openingHours?: string;
  website?: string;
  phone?: string;
  cuisine?: string;
}

type NearbyKind = 'food' | 'hotel' | 'attraction';

// White line-icon (uses currentColor) per kind, for the filled Google-style
// nearby markers. Kept simple so they read at ~14px.
const NEARBY_ICON: Record<NearbyKind, string> = {
  food: `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 3v6a2 2 0 0 0 4 0V3"/><path d="M7 9v12"/><path d="M18 3c-1.7 0-3 1.9-3 4.5V13h3"/><path d="M18 3v18"/></svg>`,
  hotel: `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6v12"/><path d="M3 13h16a2 2 0 0 1 2 2v3"/><path d="M3 17h18"/><path d="M7 13v-2.5h5V13"/></svg>`,
  attraction: `<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 8h2l1.5-2h7L17 8h2a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z"/><circle cx="12" cy="13.5" r="3"/></svg>`,
};

const NEARBY_META: Record<
  NearbyKind,
  { emoji: string; label: string; color: string }
> = {
  food: { emoji: '🍽', label: 'Food', color: '#f97316' },
  hotel: { emoji: '🏨', label: 'Hotels', color: '#8b5cf6' },
  attraction: { emoji: '📷', label: 'Things to do', color: '#0ea5e9' },
};

export interface Route {
  name?: string;
  coordinates: Coordinate[];
}

interface LeafletMapConfig {
  tileserverUrl?: string;
  disableMapClick?: boolean;
  // Opt-in popup enrichments. Each is independent and off by default so other
  // consumers of this shared component are unaffected:
  //   showLocationImage -> fetch a representative Wikipedia photo for the place
  //   showNearbyPlaces  -> fetch nearby food/hotel/attraction recommendations
  //                        (with their own OSM detail) and render them as
  //                        clickable markers
  showLocationImage?: boolean;
  showNearbyPlaces?: boolean;
  nearbyRadius?: number; // meters, default 600
  // How to draw routes:
  //   'road'     -> follow real roads via the OSRM routing API (default)
  //   'straight' -> connect stops directly, no routing API call
  routeStyle?: 'road' | 'straight';
  // Color of the drawn route line. Any CSS color; defaults to a blue (#3b82f6).
  routeColor?: string;
  // Opt-in: append a "View on Google Maps" link to each marker popup, pointing
  // at the coordinate's lat/lng (no API key, just a maps URL). Off by default so
  // other consumers of this shared component are unaffected.
  showGoogleMapsLink?: boolean;
  // Opt-in: show a control button on the map that re-fits the view to frame
  // all markers (handy after the user has panned/zoomed away). Off by default.
  showFitButton?: boolean;
  // Pixels to reserve at the top edge when auto-panning a popup into view.
  // Leaflet popups live inside the map's transformed pane, so they can't be
  // z-indexed above a fixed overlay the host draws on the map (e.g. a filter
  // bar) — the transform traps them in their own stacking context. Reserving
  // space here makes the popup auto-pan to sit clear of that overlay instead.
  // Defaults to 0.
  popupTopInset?: number;
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
      injectPopupStyles();
    })();
  }
  return leafletLoaded;
}

// Leaflet popups render OUTSIDE the component's scoped CSS, so their styling
// can't live in the <style scoped> block. We inject one shared stylesheet into
// <head> the first time the map loads — this keeps the popup markup clean
// (class names instead of sprawling inline styles) and lets us use animations
// (the skeleton shimmer) that inline styles can't express.
let popupStylesInjected = false;

function injectPopupStyles() {
  if (popupStylesInjected || typeof document === 'undefined') return;
  popupStylesInjected = true;
  let style = document.createElement('style');
  style.setAttribute('data-bx-map-popup', '');
  style.textContent = `
    .leaflet-popup-content-wrapper {
      border-radius: 12px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.16);
      padding: 2px;
    }
    .leaflet-popup-content { margin: 12px 14px; }
    .bx-rich-popup {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      color: #1f2937;
      line-height: 1.4;
    }
    .bx-rich-popup strong { font-size: 14px; font-weight: 700; color: #111827; }
    .bx-rp-img {
      display: block; width: 100%; height: 124px; object-fit: cover;
      border-radius: 8px; margin: 8px 0; background: #f1f5f9;
    }
    .bx-rp-group { margin-top: 8px; }
    .bx-rp-group-label {
      display: flex; align-items: center; gap: 5px;
      font-weight: 700; font-size: 11px; letter-spacing: 0.02em;
      text-transform: uppercase; color: #6b7280; margin-bottom: 2px;
    }
    .bx-rp-item {
      font-size: 12.5px; line-height: 1.6; color: #374151;
      padding-left: 14px; position: relative;
    }
    .bx-rp-item::before {
      content: ''; position: absolute; left: 4px; top: 8px;
      width: 4px; height: 4px; border-radius: 50%; background: currentColor; opacity: 0.5;
    }
    .bx-rp-empty { margin-top: 8px; font-size: 12px; color: #9ca3af; }
    .bx-rp-kind { margin-top: 2px; font-size: 11px; color: #6b7280; }
    .bx-rp-hours {
      display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px;
      margin-top: 8px; font-size: 12px; color: #374151;
    }
    .bx-rp-hours-text { color: #6b7280; }
    .bx-rp-badge { font-size: 11px; font-weight: 700; }
    .bx-rp-open { color: #15803d; }
    .bx-rp-closed { color: #b91c1c; }
    .bx-rp-meta {
      display: block; margin-top: 6px; font-size: 12px;
      color: #374151; text-decoration: none;
    }
    a.bx-rp-meta { color: #1a73e8; }
    a.bx-rp-meta:hover { text-decoration: underline; }
    .bx-rp-link {
      display: inline-flex; align-items: center; gap: 5px;
      margin-top: 10px; padding: 5px 10px; border-radius: 7px;
      font-size: 12px; font-weight: 600; color: #1a73e8;
      background: #eef4fe; text-decoration: none;
      transition: background 0.12s ease;
    }
    .bx-rp-link:hover { background: #dbe8fd; }
    /* skeleton shimmer */
    .bx-sk-img, .bx-sk-line {
      border-radius: 6px;
      background: linear-gradient(100deg, #eceff3 30%, #f6f8fa 50%, #eceff3 70%);
      background-size: 200% 100%;
      animation: bx-sk-shimmer 1.2s ease-in-out infinite;
    }
    .bx-sk-img { width: 100%; height: 124px; margin: 8px 0; }
    .bx-sk-line { height: 11px; margin-top: 8px; }
    .bx-sk-line.w-40 { width: 40%; }
    .bx-sk-line.w-70 { width: 70%; }
    .bx-sk-line.w-90 { width: 90%; }
    @keyframes bx-sk-shimmer {
      0% { background-position: 200% 0; }
      100% { background-position: -200% 0; }
    }
    /* "fit all" control button — styled to match the Leaflet zoom buttons it
       stacks beneath (same 30px square, white, bordered "leaflet-bar" look). */
    .bx-fit-btn {
      box-sizing: border-box;
      width: 34px; height: 34px; padding: 0;
      display: flex; align-items: center; justify-content: center;
      background: #fff; color: #374151;
      border: 2px solid rgba(0,0,0,0.2); border-radius: 4px;
      cursor: pointer;
      transition: color 0.12s ease, background 0.12s ease;
    }
    .bx-fit-btn:hover { background: #f4f4f4; color: #111827; }
  `;
  document.head.appendChild(style);
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
  private nearbyGroup: LeafletLayerGroup | null = null;
  private map: LeafletMap;
  private markerById = new Map<string | number, LeafletMarker>();
  private showLocationImage: boolean;
  private showNearbyPlaces: boolean;
  private showGoogleMapsLink: boolean;
  private nearbyRadius: number;
  private routeStyle: 'road' | 'straight';
  private routeColor: string;
  private popupTopInset: number;
  // Per-coordinate cache so re-opening a popup never refetches.
  private enrichCache = new Map<
    string | number,
    { image: string | null; nearby: NearbyPlace[] }
  >();
  // The coordinate key whose stop popup is currently open; lets an in-flight
  // fetch detect that the user has since switched/closed popups.
  private activeKey: string | number | null = null;

  constructor(map: LeafletMap, mapConfig?: LeafletMapConfig) {
    this.map = map;
    this.showLocationImage = mapConfig?.showLocationImage ?? false;
    this.showNearbyPlaces = mapConfig?.showNearbyPlaces ?? false;
    this.showGoogleMapsLink = mapConfig?.showGoogleMapsLink ?? false;
    this.nearbyRadius = mapConfig?.nearbyRadius ?? 600;
    this.routeStyle = mapConfig?.routeStyle ?? 'road';
    this.routeColor = mapConfig?.routeColor ?? '#3b82f6';
    this.popupTopInset = mapConfig?.popupTopInset ?? 0;
    this.group = L.layerGroup();
    this.group?.addTo(this.map);
    this.nearbyGroup = L.layerGroup();
    this.nearbyGroup?.addTo(this.map);
  }

  focus(id: string | number) {
    let marker = this.markerById.get(id);
    if (!marker) return;
    // Center the map on the selected pin (keeping the current zoom, but never
    // staying further out than 14 so the stop is actually legible). Open the
    // popup only AFTER the fly settles: opening mid-flight makes the popup's
    // auto-pan compute against the in-flight view and ignore popupTopInset, so
    // the popup ends up under the host's top overlay (e.g. the day-filter bar).
    if (!this.map) {
      marker.openPopup();
      return;
    }
    let { lat, lng } = marker.getLatLng();
    let zoom = this.map.getZoom ? Math.max(this.map.getZoom(), 14) : 14;
    let duration = 0.6;
    this.map.flyTo([lat, lng], zoom, { animate: true, duration });
    setTimeout(() => marker.openPopup(), duration * 1000 + 60);
  }

  // Shared popup options. Reserves popupTopInset px at the top edge so a popup
  // auto-panning into view clears any fixed overlay the host draws above the
  // map (e.g. a filter bar). See popupTopInset in LeafletMapConfig for why this
  // is needed instead of a z-index.
  private popupOptions(extra: Record<string, any> = {}) {
    return {
      autoPanPaddingTopLeft: [16, this.popupTopInset + 16],
      autoPanPaddingBottomRight: [16, 16],
      ...extra,
    };
  }

  onCoordinatesChange(coordinates: Coordinate[]) {
    this.teardown();
    let markers = this.createMarkers(coordinates.filter(hasLatLng));
    this.addLayers(markers);
  }

  onRoutesChange(routes: Route[]) {
    this.teardown();
    let markerLayers: LeafletLayers[] = [];
    routes.forEach((route) => {
      let coords = (route.coordinates ?? []).filter(hasLatLng);
      if (coords.length > 0) {
        this.createMarkers(coords).forEach((marker) =>
          markerLayers.push(marker),
        );
      }
    });
    // Add markers + fit the view right away; the road-following route geometry
    // is fetched asynchronously and dropped in once it resolves.
    this.addLayers(markerLayers);
    routes.forEach((route) => {
      let coords = (route.coordinates ?? []).filter(hasLatLng);
      if (coords.length >= 2) {
        this.addRouteLine(coords);
      }
    });
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
      const header =
        c.address?.trim() ||
        (c.name
          ? `<strong>${escapeHtml(c.name)}</strong>`
          : `${c.lat.toFixed(6)}, ${c.lng.toFixed(6)}`);

      const linkHtml = this.showGoogleMapsLink
        ? googleMapsLinkHtml(googleMapsPlaceUrl(c.name, c.lat, c.lng))
        : '';

      if (this.showLocationImage || this.showNearbyPlaces) {
        marker.bindPopup(
          `<div class="bx-rich-popup">${header}${linkHtml}</div>`,
          this.popupOptions({ maxWidth: 280, minWidth: 220 }),
        );
        marker.on('popupopen', () =>
          this.enrichPopup(c, marker, header, linkHtml),
        );
      } else {
        marker.bindPopup(`${header}${linkHtml}`, this.popupOptions());
      }

      if (c.id != null) {
        this.markerById.set(c.id, marker);
      }
      return marker;
    });
  }

  // Lazily fill an opened stop popup with a place photo + nearby list, and drop
  // clickable markers for each nearby place. Network failures degrade silently
  // back to the header-only popup. Results are cached per coordinate id.
  private async enrichPopup(
    c: Coordinate,
    marker: LeafletMarker,
    header: string,
    linkHtml: string,
  ) {
    let key = c.id ?? `${c.lat},${c.lng}`;
    this.activeKey = key;
    this.nearbyGroup?.clearLayers();

    let render = (image: string | null, nearby: NearbyPlace[]) => {
      let popup = marker.getPopup();
      if (!popup) return;
      popup.setContent(
        buildRichPopupHtml(header, {
          image,
          nearby,
          linkHtml,
          showNearbyNote: this.showNearbyPlaces,
        }),
      );
      this.renderNearbyMarkers(nearby);
    };

    let cached = this.enrichCache.get(key);
    if (cached) {
      render(cached.image, cached.nearby);
      return;
    }

    // Show a skeleton placeholder immediately while we fetch, tailored to the
    // pieces we're actually loading.
    let popup = marker.getPopup();
    popup?.setContent(
      buildSkeletonHtml(header, {
        image: this.showLocationImage,
        nearby: this.showNearbyPlaces,
      }),
    );

    let [image, nearby] = await Promise.all([
      this.showLocationImage && c.name
        ? fetchPlaceImage(c.name, c.lat, c.lng)
        : Promise.resolve(null),
      this.showNearbyPlaces
        ? fetchNearbyPlaces(c.lat, c.lng, this.nearbyRadius)
        : Promise.resolve([] as NearbyPlace[]),
    ]);
    this.enrichCache.set(key, { image, nearby });

    // The user may have closed/switched popups while we were fetching; only
    // render if this marker's popup is still the open one.
    if (this.activeKey === key) {
      render(image, nearby);
    }
  }

  private renderNearbyMarkers(nearby: NearbyPlace[]) {
    this.nearbyGroup?.clearLayers();
    nearby.forEach((p) => {
      let marker = createNearbyMarker(p);
      // Named POIs resolve best by name (Google returns the actual business
      // listing); coords ride along to bias to the right one.
      let linkHtml = this.showGoogleMapsLink
        ? googleMapsLinkHtml(googleMapsPlaceUrl(p.name, p.lat, p.lng))
        : '';
      marker.bindPopup(buildNearbyPopupHtml(p, linkHtml));
      this.nearbyGroup?.addLayer(marker);
    });
  }

  // Draw the route between stops.
  // 'road' follows real roads via OSRM; 'straight' connects stops directly.
  private async addRouteLine(coordinates: Coordinate[]): Promise<void> {
    let style = {
      color: this.routeColor,
      weight: 4,
      opacity: 0.85,
      lineCap: 'round',
      lineJoin: 'round',
    };

    // 'straight' draws a direct connector with no routing API call.
    if (this.routeStyle === 'straight') {
      this.addStraightLine(coordinates, style);
      return;
    }

    // 'road' follows real roads via OSRM, falling back to a straight connector
    // if the routing service is unavailable so the route is never invisible.
    let route = await fetchRoute(coordinates);
    if (!this.group) return;
    if (route) {
      this.group.addLayer(L.geoJSON(route.geometry, { style }));
      return;
    }
    this.addStraightLine(coordinates, style);
  }

  private addStraightLine(coordinates: Coordinate[], style: any) {
    this.group?.addLayer(
      L.geoJSON(
        {
          type: 'Feature',
          geometry: {
            type: 'LineString',
            coordinates: coordinates.map((c) => [c.lng, c.lat]),
          },
        },
        { style: { ...style, dashArray: '1 10' } },
      ),
    );
  }

  // Re-fit the view to frame every marker currently on the map. Public so the
  // optional on-map "fit" control can trigger it on demand.
  recenter() {
    this.readjustMapView();
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
    this.nearbyGroup?.clearLayers();
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
  private fitControlAdded = false;

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
        this.state = new LeafletLayerState(this.map, mapConfig);
      }
      if (mapConfig?.showFitButton && !this.fitControlAdded) {
        this.addFitControl();
        this.fitControlAdded = true;
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

  // A small "fit all" control: re-frames the view around every marker. Added
  // once, only when mapConfig.showFitButton is set.
  private addFitControl() {
    if (!this.map) return;
    // topleft so it stacks directly beneath the default zoom in/out control.
    let control = L.control({ position: 'topleft' });
    control.onAdd = () => {
      let btn = L.DomUtil.create('button', 'bx-fit-btn');
      btn.type = 'button';
      btn.title = 'Fit all stops';
      btn.setAttribute('aria-label', 'Fit all stops');
      // corner-frame "fit to view" glyph — four brackets pulling inward,
      // reads as "frame everything" better than a locate-me crosshair.
      btn.innerHTML =
        '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3"/></svg>';
      L.DomEvent.disableClickPropagation(btn);
      L.DomEvent.on(btn, 'click', (e: Event) => {
        L.DomEvent.stop(e);
        this.state?.recenter();
      });
      return btn;
    };
    control.addTo(this.map);
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

// Fetch the actual road-following route through all stops from the public OSRM
// server (free, no key, CORS-enabled). Returns the GeoJSON LineString geometry.
// Any failure resolves to null so the caller can fall back.
async function fetchRoute(
  coordinates: Coordinate[],
): Promise<{ geometry: any } | null> {
  if (coordinates.length < 2) return null;
  let path = coordinates.map((c) => `${c.lng},${c.lat}`).join(';');
  try {
    let res = await fetch(
      `https://router.project-osrm.org/route/v1/driving/${path}` +
        `?overview=full&geometries=geojson`,
    );
    if (!res.ok) return null;
    let data = await res.json();
    let route = data?.routes?.[0];
    if (route?.geometry?.type !== 'LineString') return null;
    return { geometry: route.geometry };
  } catch (e) {
    return null;
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// A Google-style nearby marker: a solid kind-colored disc with a white line
// icon and a white ring, so its type (food / hotel / attraction) reads at a
// glance and it stands apart from the numbered stop pins.
function createNearbyMarker(place: NearbyPlace): LeafletMarker {
  const meta = NEARBY_META[place.kind];
  const html = `<div style="
      width:24px;height:24px;border-radius:50%;
      background:${meta.color};color:#fff;
      border:2.5px solid #fff;
      box-shadow:0 1px 4px rgba(0,0,0,0.4);
      display:flex;align-items:center;justify-content:center;
      line-height:0;">${NEARBY_ICON[place.kind]}</div>`;
  return L.marker([place.lat, place.lng], {
    icon: L.divIcon({
      className: 'nearby-marker',
      html,
      iconSize: [24, 24],
      iconAnchor: [12, 12],
      popupAnchor: [0, -14],
    }),
  });
}

// Builds the enriched stop popup body: header (name + time) → optional photo →
// grouped nearby list → Google link. Styling comes from the injected popup
// stylesheet.
function buildRichPopupHtml(
  header: string,
  opts: {
    image: string | null;
    nearby: NearbyPlace[];
    linkHtml?: string;
    showNearbyNote?: boolean;
  },
): string {
  let { image, nearby, linkHtml = '', showNearbyNote = false } = opts;
  let parts = [`<div class="bx-rich-popup">`, header];

  if (image) {
    parts.push(
      `<img class="bx-rp-img" src="${escapeHtml(image)}" alt="" loading="lazy" />`,
    );
  }

  let order: NearbyKind[] = ['food', 'attraction', 'hotel'];
  let hasNearby = nearby.length > 0;
  for (let kind of order) {
    let items = nearby.filter((p) => p.kind === kind).slice(0, 4);
    if (!items.length) continue;
    let meta = NEARBY_META[kind];
    parts.push(
      `<div class="bx-rp-group"><div class="bx-rp-group-label">${meta.emoji} ${meta.label}</div>` +
        items
          .map((p) => `<div class="bx-rp-item">${escapeHtml(p.name)}</div>`)
          .join('') +
        `</div>`,
    );
  }

  // Only show the "nothing nearby" line when nearby results were actually
  // requested — a popup that only carries a photo shouldn't claim emptiness.
  if (!hasNearby && showNearbyNote) {
    parts.push(`<div class="bx-rp-empty">No nearby places found.</div>`);
  }

  if (linkHtml) parts.push(linkHtml);

  parts.push(`</div>`);
  return parts.join('');
}

// Skeleton placeholder shown while a popup's photo / nearby list load. Only
// renders the rows for the pieces actually being fetched.
function buildSkeletonHtml(
  header: string,
  loading: { image: boolean; nearby: boolean },
): string {
  let parts = [`<div class="bx-rich-popup">`, header];
  if (loading.image) {
    parts.push(`<div class="bx-sk-img"></div>`);
  }
  if (loading.nearby) {
    parts.push(
      `<div class="bx-sk-line w-40"></div>`,
      `<div class="bx-sk-line w-90"></div>`,
      `<div class="bx-sk-line w-70"></div>`,
    );
  }
  parts.push(`</div>`);
  return parts.join('');
}

// Popup body for a single nearby place: name + kind/cuisine, plus any detail
// OSM happened to carry (open-now status from `opening_hours`, phone, website),
// and the Google Maps link. Every detail row is optional — OSM coverage varies.
function buildNearbyPopupHtml(p: NearbyPlace, linkHtml: string): string {
  let meta = NEARBY_META[p.kind];
  let parts = [
    `<div class="bx-rich-popup">`,
    `<strong>${escapeHtml(p.name)}</strong>`,
  ];

  let sub = p.cuisine
    ? `${meta.label} · ${formatCuisine(p.cuisine)}`
    : meta.label;
  parts.push(`<div class="bx-rp-kind">${meta.emoji} ${escapeHtml(sub)}</div>`);

  parts.push(detailRowsHtml(p));

  if (linkHtml) parts.push(linkHtml);
  parts.push(`</div>`);
  return parts.join('');
}

// Shared detail rows for a place popup: open-now badge + raw hours, phone, and
// website. Each row is emitted only when the underlying OSM tag exists.
function detailRowsHtml(d: PlaceDetails): string {
  let parts: string[] = [];
  if (d.openingHours) {
    let open = evalOpeningHours(d.openingHours, new Date());
    let badge =
      open === true
        ? `<span class="bx-rp-badge bx-rp-open">● Open now</span>`
        : open === false
          ? `<span class="bx-rp-badge bx-rp-closed">● Closed</span>`
          : '';
    parts.push(
      `<div class="bx-rp-hours">${badge}<span class="bx-rp-hours-text">${escapeHtml(d.openingHours)}</span></div>`,
    );
  }
  if (d.phone) {
    parts.push(
      `<a class="bx-rp-meta" href="tel:${escapeHtml(d.phone)}">📞 ${escapeHtml(d.phone)}</a>`,
    );
  }
  if (d.website) {
    parts.push(
      `<a class="bx-rp-meta" href="${escapeHtml(d.website)}" target="_blank" rel="noopener noreferrer">🌐 Website</a>`,
    );
  }
  return parts.join('');
}

// Turn a raw OSM `cuisine` value ("coffee_shop;sandwich") into a readable label
// ("Coffee Shop, Sandwich").
function formatCuisine(cuisine: string): string {
  return cuisine
    .split(';')
    .map((c) =>
      c
        .trim()
        .split('_')
        .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
        .join(' '),
    )
    .filter(Boolean)
    .slice(0, 2)
    .join(', ');
}

// Lightweight evaluator for OSM `opening_hours`. Returns true (open now), false
// (closed now), or null when the rule is too complex to judge confidently (so
// the caller just shows the raw string). Handles the common cases: "24/7",
// weekday specs (Mo, Mo-Fr, Mo,We,Fr), multiple time ranges, ranges crossing
// midnight, and explicit "off"/"closed". Bails (null) on anything fancier
// (months, holidays, week numbers, "sunrise", quoted comments, etc.).
function evalOpeningHours(spec: string, now: Date): boolean | null {
  let text = spec.trim();
  if (!text) return null;
  if (/^24\/7$/.test(text)) return true;
  // Unsupported advanced syntax → don't guess.
  if (
    /[a-z]{3,}|"|\d{4}|:|wk|PH|SH|sunrise|sunset/i.test(
      text.replace(/\b(Mo|Tu|We|Th|Fr|Sa|Su|off|closed|open)\b/gi, ''),
    )
  )
    return null;

  let dayTokens = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  let today = now.getDay();
  let mins = now.getHours() * 60 + now.getMinutes();
  let dayIndex: Record<string, number> = {
    Su: 0,
    Mo: 1,
    Tu: 2,
    We: 3,
    Th: 4,
    Fr: 5,
    Sa: 6,
  };

  let sawToday = false;
  for (let rule of text.split(/\s*;\s*/)) {
    if (!rule.trim()) continue;
    let times = rule.match(/\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}/g) ?? [];
    let dayPart = rule
      .replace(/\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}/g, '')
      .replace(/,/g, ' ')
      .trim();
    let closed = /\b(off|closed)\b/i.test(rule);

    if (!dayCoversToday(dayPart, today, dayIndex)) continue;
    sawToday = true;
    if (closed) return false;

    for (let t of times) {
      let m = t.match(/(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})/);
      if (!m) continue;
      let start = +m[1] * 60 + +m[2];
      let end = +m[3] * 60 + +m[4];
      if (end <= start) end += 24 * 60; // crosses midnight
      if (mins >= start && mins < end) return true;
      if (mins + 24 * 60 >= start && mins + 24 * 60 < end) return true; // early-morning wrap
    }
  }
  // We understood a rule for today but no time range matched → closed.
  // We never found a rule mentioning today → can't say.
  return dayTokens.length && sawToday ? false : null;
}

function dayCoversToday(
  dayPart: string,
  today: number,
  dayIndex: Record<string, number>,
): boolean {
  if (!dayPart) return true; // no day spec → applies every day
  let covered = new Set<number>();
  for (let tok of dayPart.split(/\s+/).filter(Boolean)) {
    if (tok.includes('-')) {
      let [a, b] = tok.split('-');
      if (dayIndex[a] == null || dayIndex[b] == null) continue;
      let i = dayIndex[a];
      for (let guard = 0; guard < 7; guard++) {
        covered.add(i);
        if (i === dayIndex[b]) break;
        i = (i + 1) % 7;
      }
    } else if (dayIndex[tok] != null) {
      covered.add(dayIndex[tok]);
    }
  }
  if (covered.size === 0) return true; // couldn't parse days → assume daily
  return covered.has(today);
}

// A Google Maps search URL for a free-text query (a "lat,lng" pair or a place
// name). No API key required.
function googleMapsSearchUrl(query: string): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
    query,
  )}`;
}

// A Google Maps URL that resolves the actual named place (business card with
// name/photos/reviews), not a bare coordinate pin. Uses the path form
// `/maps/search/<name>/@lat,lng,zoom` — Google searches the name centered on
// the coordinates, so a precise pin disambiguates to the right listing. Falls
// back to a plain name or coordinate query when one piece is missing.
function googleMapsPlaceUrl(
  name?: string,
  lat?: number | null,
  lng?: number | null,
): string {
  let q = (name ?? '').trim();
  let hasCoords = typeof lat === 'number' && typeof lng === 'number';
  if (q && hasCoords) {
    return `https://www.google.com/maps/search/${encodeURIComponent(q)}/@${lat},${lng},16z`;
  }
  if (q) return googleMapsSearchUrl(q);
  if (hasCoords) return googleMapsSearchUrl(`${lat},${lng}`);
  return googleMapsSearchUrl('');
}

// "View on Google Maps" link for a marker popup. Styled via the injected popup
// stylesheet (.bx-rp-link) since Leaflet popups render outside scoped CSS.
function googleMapsLinkHtml(url: string): string {
  return (
    `<a class="bx-rp-link" href="${escapeHtml(url)}" ` +
    `target="_blank" rel="noopener noreferrer">📍 View on Google Maps</a>`
  );
}

// Wikimedia asks every caller to identify itself. Browsers forbid setting the
// real User-Agent header from fetch(), so we send Wikimedia's accepted
// Api-User-Agent alternative to stay within their API etiquette.
const WIKIMEDIA_HEADERS = {
  'Api-User-Agent': 'BoxelTravelItinerary/1.0 (https://app.boxel.ai/catalog/)',
};

interface WikiCandidate {
  title: string;
  thumb: string;
  order: number; // API order: search relevance, or geosearch distance
}

// One Wikipedia pageimages query. `generator` is 'search' (by name) or
// 'geosearch' (by coordinates). Returns the candidate articles that actually
// have a thumbnail, preserving the API's own ordering (relevance / distance).
async function wikiThumbs(params: string): Promise<WikiCandidate[]> {
  try {
    let res = await fetch(
      `https://en.wikipedia.org/w/api.php?action=query&format=json&origin=*` +
        `&prop=pageimages&piprop=thumbnail&pithumbsize=400&` +
        params,
      { headers: WIKIMEDIA_HEADERS },
    );
    if (!res.ok) return [];
    let data = await res.json();
    let pages = data?.query?.pages;
    if (!pages) return [];
    let out: WikiCandidate[] = [];
    for (let key of Object.keys(pages)) {
      let p = pages[key];
      let thumb = p?.thumbnail?.source;
      if (thumb && typeof p?.title === 'string') {
        out.push({ title: p.title, thumb, order: p.index ?? 999 });
      }
    }
    return out.sort((a, b) => a.order - b.order);
  } catch (e) {
    return [];
  }
}

// Fetch a representative photo for a place. The old approach (look up the exact
// title, else grab the nearest geo article) often returned an unrelated image —
// an imprecise name hit a redirect/disambiguation, and the geo fallback grabbed
// whatever neighbouring article had a picture. Instead we gather candidates
// BOTH by name and by the (now precise) coordinates, then pick the one whose
// article title best matches the place name, breaking ties toward location and
// relevance. Any failure resolves to null — no broken images.
async function fetchPlaceImage(
  name: string,
  lat: number,
  lng: number,
): Promise<string | null> {
  let [byName, byGeo] = await Promise.all([
    wikiThumbs(
      `generator=search&gsrsearch=${encodeURIComponent(name)}&gsrlimit=5`,
    ),
    wikiThumbs(
      `generator=geosearch&ggscoord=${lat}|${lng}&ggsradius=1000&ggslimit=10`,
    ),
  ]);
  if (!byName.length && !byGeo.length) return null;

  let target = normalizePlaceText(name);
  // Drop generic place words ("shopping mall", "tower"…) so matching keys off
  // the distinctive part of the name. "Nu Sentral shopping mall" → "nu sentral".
  let core = target
    .split(' ')
    .filter((w) => w && !GENERIC_PLACE_WORDS.has(w))
    .join(' ')
    .trim();

  // High precision: an article counts only when its title clearly IS the place
  // — the title equals the name, or contains the full (generic-stripped) name.
  // We deliberately do NOT match on a single shared word, because that returned
  // unrelated articles (a search's top "related" result, or a neighbour that
  // merely shares "mall"/"sentral"). No clear match → no image.
  let titleMatches = (title: string): boolean => {
    let t = normalizePlaceText(title);
    if (!t) return false;
    if (t === target || t === core) return true;
    if (t.includes(target)) return true;
    if (core.length >= 4 && t.includes(core)) return true;
    return false;
  };

  // Among the clear matches, break ties toward location (precise coords) then
  // search relevance.
  let scored = [
    ...byGeo.map((c, i) => ({ c, base: 15 + Math.max(0, 10 - i) })),
    ...byName.map((c, i) => ({ c, base: 5 + Math.max(0, 5 - i) })),
  ]
    .filter((x) => titleMatches(x.c.title))
    .sort((a, b) => b.base - a.base);

  return scored[0]?.c.thumb ?? null;
}

// Lowercase, strip diacritics and punctuation, collapse spaces — so "Sensō-ji"
// and "Senso ji" compare equal and matching isn't thrown off by commas/macrons.
function normalizePlaceText(s: string): string {
  return s
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9 ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Generic words that don't identify a specific place; dropped before matching a
// Wikipedia article title so they can't trigger a false image match.
const GENERIC_PLACE_WORDS = new Set([
  'shopping',
  'mall',
  'centre',
  'center',
  'complex',
  'tower',
  'towers',
  'hotel',
  'resort',
  'restaurant',
  'cafe',
  'coffee',
  'bar',
  'park',
  'garden',
  'gardens',
  'museum',
  'gallery',
  'temple',
  'shrine',
  'market',
  'plaza',
  'square',
  'station',
  'central',
  'sentral',
  'city',
  'street',
  'road',
  'avenue',
  'beach',
  'pantai',
  'the',
  'and',
  'of',
  'at',
  'in',
]);

// Fetch nearby points of interest from the Overpass (OpenStreetMap) API. Any
// failure resolves to an empty list so the popup degrades gracefully.
async function fetchNearbyPlaces(
  lat: number,
  lng: number,
  radius: number,
): Promise<NearbyPlace[]> {
  let query =
    `[out:json][timeout:15];(` +
    `node["amenity"~"restaurant|cafe"](around:${radius},${lat},${lng});` +
    `node["tourism"="hotel"](around:${radius},${lat},${lng});` +
    `node["tourism"~"attraction|museum|gallery|viewpoint"](around:${radius},${lat},${lng});` +
    `);out body 30;`;

  try {
    let res = await fetch('https://overpass-api.de/api/interpreter', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain' },
      body: query,
    });
    if (!res.ok) return [];
    let data = await res.json();
    let elements: any[] = data?.elements ?? [];
    let places: NearbyPlace[] = [];
    let seen = new Set<string>();
    for (let el of elements) {
      let name = el?.tags?.name;
      if (!name || el.lat == null || el.lon == null) continue;
      if (seen.has(name)) continue;
      seen.add(name);
      let tags: Record<string, string> = el.tags ?? {};
      places.push({
        name,
        lat: el.lat,
        lng: el.lon,
        kind: classifyNearby(tags),
        openingHours: tags.opening_hours || undefined,
        website:
          tags.website || tags['contact:website'] || tags.url || undefined,
        phone: tags.phone || tags['contact:phone'] || undefined,
        cuisine: tags.cuisine || undefined,
      });
      if (places.length >= 12) break;
    }
    return places;
  } catch (e) {
    return [];
  }
}

function classifyNearby(tags: Record<string, string>): NearbyKind {
  if (tags.tourism === 'hotel') return 'hotel';
  if (tags.amenity === 'restaurant' || tags.amenity === 'cafe') return 'food';
  return 'attraction';
}
