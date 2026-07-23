// Loads the three.js UMD bundle from CDN exactly once and shares the
// namespace across every card instance in this module scope.
//
// The bundle is executed with new Function('module','exports', code) and an
// explicit CommonJS module/exports pair. Under the Boxel realm loader an
// ambient `define` (without define.amd) is visible to plain eval, which makes
// UMD wrappers take the AMD branch that only registers the factory and never
// runs it — leaving the library undefined in production. Forcing the
// CommonJS branch runs the factory synchronously regardless of the ambient
// loader. Dynamic import of the +esm build is equally unreliable through the
// realm loader's transpile pipeline. (Same treatment as Leaflet in
// components/map-render.gts.)
//
// three@0.147.0 is the last release line that ships a UMD build.
const THREE_UMD_URL =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/build/three.min.js';
// true 3D rounded box (all 6 faces rounded) — the add-on the War-Hauler
// showcase uses for every armored body volume
const ROUNDED_BOX_UMD_URL =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/geometries/RoundedBoxGeometry.js';

// examples/js exporter add-on — attaches THREE.GLTFExporter for .glb export
const GLTF_EXPORTER_UMD_URL =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/exporters/GLTFExporter.js';
// examples/js loader add-on — attaches THREE.GLTFLoader for meshAsset nodes
const GLTF_LOADER_UMD_URL =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/loaders/GLTFLoader.js';

let three: any;
let threeLoaded: Promise<any> | undefined;
let exporterLoaded: Promise<any> | undefined;
let loaderLoaded: Promise<any> | undefined;

export function loadThree(): Promise<any> {
  if (!threeLoaded) {
    threeLoaded = (async () => {
      if (!three?.Scene) {
        let response = await fetch(THREE_UMD_URL);
        if (!response.ok) {
          threeLoaded = undefined;
          throw new Error(`three.js CDN fetch failed: ${response.status}`);
        }
        let code = await response.text();
        let threeModule: { exports: any } = { exports: {} };
        new Function('module', 'exports', code)(
          threeModule,
          threeModule.exports,
        );
        three = threeModule.exports;
        if (!three?.Scene) {
          threeLoaded = undefined;
          throw new Error('three.js UMD bundle did not populate exports');
        }
        // r147 defaults to legacy color mode, which treats hex albedos as
        // LINEAR values — dark and saturated sRGB colors get massively
        // lifted/washed (black plastic renders mid-gray). Modern color
        // management converts sRGB hex → linear correctly and pairs with the
        // renderer's sRGB output encoding.
        if (three.ColorManagement) {
          three.ColorManagement.legacyMode = false;
        }
        try {
          let addOn = await fetch(ROUNDED_BOX_UMD_URL);
          if (addOn.ok) {
            new Function('THREE', await addOn.text())(three);
          }
        } catch {
          // optional add-on; roundedBox falls back to the extruded slab
        }
      }
      return three;
    })();
  }
  return threeLoaded;
}

// lazily adds THREE.GLTFLoader (only fetched when a spec uses meshAsset)
export function loadGltfLoader(): Promise<any> {
  if (!loaderLoaded) {
    loaderLoaded = (async () => {
      let ns = await loadThree();
      if (!ns.GLTFLoader) {
        let response = await fetch(GLTF_LOADER_UMD_URL);
        if (!response.ok) {
          loaderLoaded = undefined;
          throw new Error(`GLTFLoader CDN fetch failed: ${response.status}`);
        }
        new Function('THREE', await response.text())(ns);
        if (!ns.GLTFLoader) {
          loaderLoaded = undefined;
          throw new Error('GLTFLoader add-on did not register');
        }
      }
      return ns;
    })();
  }
  return loaderLoaded;
}

// lazily adds THREE.GLTFExporter (only fetched when the user hits export)
export function loadGltfExporter(): Promise<any> {
  if (!exporterLoaded) {
    exporterLoaded = (async () => {
      let ns = await loadThree();
      if (!ns.GLTFExporter) {
        let response = await fetch(GLTF_EXPORTER_UMD_URL);
        if (!response.ok) {
          exporterLoaded = undefined;
          throw new Error(`GLTFExporter CDN fetch failed: ${response.status}`);
        }
        new Function('THREE', await response.text())(ns);
        if (!ns.GLTFExporter) {
          exporterLoaded = undefined;
          throw new Error('GLTFExporter add-on did not register');
        }
      }
      return ns;
    })();
  }
  return exporterLoaded;
}
