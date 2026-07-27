// Geometry audit for an exported img-to-3D model — a browser-free test loop.
//
// An exported model .js is self-contained: buildSculpture(THREE) plus a
// SCULPT_SPEC record of what was authored. three.js runs headlessly in node, so
// the model can be BUILT and measured without a browser, a GPU or an API call.
// Every defect in these renders has been geometric rather than visual — a part
// outside the silhouette, a cap above the bottle top, a 0.008-radius tube that
// renders as a wire — so measuring beats looking at pixels, and it takes
// milliseconds instead of a generation round.
//
// Usage:  node util/audit-model.mjs <exported-model.js> [more.js ...]
// Needs:  npm i three   (in whatever directory you run it from)
//
// Exit code is 1 when any check fails, so this can gate a change to the
// interpreter: run it over a folder of saved exports before and after.

import * as THREE from 'three';
import fs from 'fs';

// no DOM here — decal builders ask for textures they will never get
THREE.TextureLoader.prototype.load = () => new THREE.Texture();

const HAIRLINE = 0.02; // below this a tube/rib reads as a floating wire
const OUTSIDE_TOLERANCE = 0.03; // the overlap the assembly rules already allow

function auditFile(path) {
  const js = fs.readFileSync(path, 'utf8');
  const built = new Function(
    'THREE',
    js + '\nreturn buildSculpture(THREE);',
  )(THREE);
  const group = built.group;
  group.updateMatrixWorld(true);
  const specMatch = js.match(/var SCULPT_SPEC = (\{[\s\S]*?\});/);
  const spec = specMatch ? JSON.parse(specMatch[1]) : { components: [] };
  const components = spec.components ?? [];
  const byName = new Map(components.map((c) => [c.nodeId, c]));

  const meshes = [];
  group.traverse((o) => {
    if (o.isMesh) meshes.push(o);
  });
  // the ground shadow is deliberately wider than the object's contact point
  const isShadow = (name) => /shadow/i.test(name);
  const failures = [];
  const size = new THREE.Box3().setFromObject(group).getSize(new THREE.Vector3());

  console.log(`\n=== ${path.split('/').pop()} ===`);
  console.log(
    `size ${size.x.toFixed(2)} x ${size.y.toFixed(2)} x ${size.z.toFixed(2)} · ` +
      `${components.length} authored components · ${meshes.length} meshes after repeats`,
  );

  // ---- 1. hairline geometry: a surface mark modelled as a solid
  const hairline = components.filter((c) => {
    const d = c.dimensions ?? [];
    if (c.primitive === 'tube') return d[0] < HAIRLINE;
    if (c.primitive === 'torus') return d[1] < HAIRLINE * 0.4;
    if (c.primitive === 'box' || c.primitive === 'cylinder') {
      return d.slice(0, 3).filter((v) => v < HAIRLINE * 0.75).length >= 2;
    }
    return false;
  });
  report('hairline geometry (renders as a wire, not a feature)', hairline, (c) =>
    `${c.nodeId} — ${c.primitive} ${JSON.stringify(c.dimensions)} · partRef='${c.partRef}' · ${c.note ?? ''}`,
  );

  // ---- 2 & 3. the traced lathe profile is the object's true outer boundary,
  // so it doubles as the test envelope for everything else
  const lathe = components.find((c) => c.primitive === 'lathe');
  if (lathe) {
    const env = [];
    for (let i = 0; i + 1 < lathe.dimensions.length; i += 2) {
      env.push({ half: lathe.dimensions[i], y: lathe.dimensions[i + 1] });
    }
    const halfAt = (y) => {
      if (y <= env[0].y) return env[0].half;
      const last = env[env.length - 1];
      if (y >= last.y) return last.half;
      for (let i = 1; i < env.length; i++) {
        if (y <= env[i].y) {
          const a = env[i - 1];
          const b = env[i];
          const t = (y - a.y) / (b.y - a.y || 1);
          return a.half + t * (b.half - a.half);
        }
      }
      return last.half;
    };

    const outside = [];
    const above = [];
    const top = env[env.length - 1].y;
    for (const mesh of meshes) {
      if (isShadow(mesh.name)) continue;
      const box = new THREE.Box3().setFromObject(mesh);
      const centerY = box.getCenter(new THREE.Vector3()).y;
      const reach = Math.max(Math.abs(box.max.x), Math.abs(box.min.x));
      const allowed = halfAt(centerY) + OUTSIDE_TOLERANCE;
      if (reach > allowed) {
        outside.push(
          `${mesh.name} — reaches x=${reach.toFixed(3)} where the body half-width at y=${centerY.toFixed(2)} is ${allowed.toFixed(3)}`,
        );
      }
      if (box.max.y > top + 0.005) {
        above.push(
          `${mesh.name} — top y=${box.max.y.toFixed(3)}, ${(box.max.y - top).toFixed(3)} above the body top`,
        );
      }
    }
    report('outside the traced silhouette', outside, (s) => s);
    report(`above the body top (y=${top})`, above, (s) => s);
  }

  // ---- 4. radial repeats: the clones must land ON the declared circle, not
  // at the original's offset PLUS the radius
  const radial = [];
  for (const c of components) {
    let rep = c.repeat;
    if (typeof rep === 'string') {
      try {
        rep = JSON.parse(rep);
      } catch {
        continue;
      }
    }
    if (rep?.mode !== 'radial') continue;
    const axis = rep.axis === 'x' ? 'x' : rep.axis === 'z' ? 'z' : 'y';
    const plane = { x: ['y', 'z'], y: ['x', 'z'], z: ['x', 'y'] }[axis];
    const host = c.attachTo ? group.getObjectByName(c.attachTo) : undefined;
    const hostCenter = host
      ? new THREE.Box3().setFromObject(host).getCenter(new THREE.Vector3())
      : new THREE.Vector3();
    for (let i = 0; i < (rep.count ?? 0); i++) {
      const clone = group.getObjectByName(i === 0 ? c.nodeId : `${c.nodeId}-${i}`);
      if (!clone) continue;
      const p = clone.getWorldPosition(new THREE.Vector3());
      const got = Math.hypot(p[plane[0]] - hostCenter[plane[0]], p[plane[1]] - hostCenter[plane[1]]);
      const want = rep.radius ?? 0.5;
      if (Math.abs(got - want) > Math.max(0.02, want * 0.25)) {
        radial.push(
          `${clone.name} — sits at radius ${got.toFixed(3)} from '${c.attachTo ?? 'origin'}' but the repeat declares ${want}`,
        );
        break; // one line per repeat system is enough
      }
    }
  }
  report('radial repeat clones off their declared circle', radial, (s) => s);

  // ---- 5. whatever the builder itself noticed
  const warnings = built.warnings ?? [];
  report('assembly warnings from the builder', warnings, (s) => s);

  function report(title, items, format) {
    const list = items ?? [];
    console.log(`\n[${title}] ${list.length}`);
    for (const item of list.slice(0, 12)) console.log(`  ${format(item)}`);
    if (list.length > 12) console.log(`  … ${list.length - 12} more`);
    if (list.length) failures.push(`${title}: ${list.length}`);
  }

  return failures;
}

const paths = process.argv.slice(2);
if (!paths.length) {
  console.error('usage: node util/audit-model.mjs <exported-model.js> [...]');
  process.exit(2);
}
let failed = 0;
for (const path of paths) {
  try {
    failed += auditFile(path).length;
  } catch (e) {
    console.error(`\n=== ${path} ===\n  could not build: ${e.message}`);
    failed += 1;
  }
}
console.log(failed ? `\n${failed} check(s) reported findings` : '\nclean');
process.exit(failed ? 1 : 0);
